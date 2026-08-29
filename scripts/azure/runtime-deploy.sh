#!/usr/bin/env bash
set -Eeuo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
runtime_environment="${RUNTIME_ENVIRONMENT:-/etc/event-sourced-cqrs/runtime.env}"
platform_host="${PLATFORM_HOST:-10.42.1.4}"
namespace="cqrs-orders"

if [[ ! -r "${runtime_environment}" ]]; then
  echo "Azure runtime configuration is unavailable at ${runtime_environment}" >&2
  exit 1
fi

if ! grep --quiet '^INVENTORY_DB_PASSWORD=' "${runtime_environment}"; then
  inventory_db_password="$(openssl rand -hex 24)"
  (
    umask 077
    printf 'INVENTORY_DB_PASSWORD=%s\n' "${inventory_db_password}" >>"${runtime_environment}"
  )
fi

read_runtime_setting() {
  local setting_name="$1"
  local setting_value
  setting_value="$(sed -n "s/^${setting_name}=//p" "${runtime_environment}" | tail -1)"
  if [[ -z "${setting_value}" ]]; then
    printf 'Azure runtime setting %s is missing.\n' "${setting_name}" >&2
    return 1
  fi
  printf '%s' "${setting_value}"
}

command_db_password="$(read_runtime_setting COMMAND_DB_PASSWORD)"
query_db_password="$(read_runtime_setting QUERY_DB_PASSWORD)"
inventory_db_password="$(read_runtime_setting INVENTORY_DB_PASSWORD)"
saga_activation_at="$(read_runtime_setting SAGA_ACTIVATION_AT)"
public_host="$(read_runtime_setting PUBLIC_HOST)"
acme_email="$(read_runtime_setting ACME_EMAIL)"
activity_function_host="$(read_runtime_setting ACTIVITY_FUNCTION_HOST)"

cd "${repository_root}"
deployment_revision="$(git rev-parse HEAD)"
if [[ ! "${deployment_revision}" =~ ^[0-9a-f]{40}$ ]]; then
  echo "The checked-out deployment revision is not a complete Git commit SHA." >&2
  exit 1
fi

./scripts/azure/install-k3s.sh

compose=(
  docker compose
  --profile ui
  --env-file "${runtime_environment}"
  --file compose.yml
  --file compose.azure.yml
  --file compose.kubernetes-platform.yml
)
export PLATFORM_HOST="${platform_host}"
export KAFKA_VNET_HOST="${platform_host}"

"${compose[@]}" up --no-build --detach --wait \
  command-db query-db inventory-db kafka kafka-init debezium

image_archive="$(mktemp --suffix=.tar)"
render_directory="$(mktemp -d)"
port_forward_log="$(mktemp)"
deployment_backup="$(mktemp)"
port_forward_pid=""
compose_application_stopped="false"
cluster_mutated="false"
deployment_completed="false"
cleanup() {
  set +e
  if [[ -n "${port_forward_pid}" ]]; then
    kill "${port_forward_pid}" 2>/dev/null || true
    wait "${port_forward_pid}" 2>/dev/null || true
  fi
  if [[ "${deployment_completed}" != "true" ]]; then
    if [[ "${compose_application_stopped}" == "true" ]]; then
      k3s kubectl delete namespace "${namespace}" --ignore-not-found --wait --timeout=120s
      "${compose[@]}" up --no-build --detach --wait \
        --scale order-command-service=2 \
        --scale order-query-service=2 \
        discovery-server order-command-service order-query-service \
        inventory-service api-gateway frontend edge-proxy
    elif [[ "${cluster_mutated}" == "true" && -s "${deployment_backup}" ]]; then
      k3s kubectl apply \
        --server-side \
        --force-conflicts \
        --field-manager=event-sourced-cqrs-deployer \
        --filename "${deployment_backup}"
      for deployment in \
        order-command-service \
        order-query-service \
        inventory-service \
        api-gateway \
        frontend \
        edge-proxy; do
        k3s kubectl --namespace "${namespace}" rollout status \
          "deployment/${deployment}" \
          --timeout=300s
      done
    fi
  fi
  rm -f "${image_archive}" "${port_forward_log}" "${deployment_backup}"
  rm -rf "${render_directory}"
}
trap cleanup EXIT

cluster_existed="false"
if k3s kubectl --namespace "${namespace}" get deployment api-gateway >/dev/null 2>&1; then
  cluster_existed="true"
else
  # The first cutover must reclaim the measured Compose application footprint
  # before Maven and image builds run alongside the K3s control plane.
  compose_application_stopped="true"
  "${compose[@]}" stop \
    edge-proxy frontend api-gateway order-command-service \
    order-query-service inventory-service discovery-server
fi

./mvnw --batch-mode --no-transfer-progress -DskipTests package

application_images=(
  "escqrs/order-command-service:${deployment_revision}"
  "escqrs/order-query-service:${deployment_revision}"
  "escqrs/inventory-service:${deployment_revision}"
  "escqrs/api-gateway:${deployment_revision}"
  "escqrs/frontend:${deployment_revision}"
)

docker build --tag "${application_images[0]}" --file order-command-service/Dockerfile .
docker build --tag "${application_images[1]}" --file order-query-service/Dockerfile .
docker build --tag "${application_images[2]}" --file inventory-service/Dockerfile .
docker build --tag "${application_images[3]}" --file api-gateway/Dockerfile .
docker build \
  --build-arg VITE_SERVERLESS_PROJECTION_ENABLED=true \
  --tag "${application_images[4]}" \
  frontend

docker save --output "${image_archive}" "${application_images[@]}"
k3s ctr images import "${image_archive}"

k3s kubectl apply --filename deploy/kubernetes/base/namespace.yaml
k3s kubectl --namespace "${namespace}" create secret generic runtime-secrets \
  --from-literal="command-db-password=${command_db_password}" \
  --from-literal="query-db-password=${query_db_password}" \
  --from-literal="inventory-db-password=${inventory_db_password}" \
  --from-literal="saga-activation-at=${saga_activation_at}" \
  --dry-run=client \
  --output=yaml | k3s kubectl apply --filename=-
k3s kubectl --namespace "${namespace}" create configmap runtime-config \
  --from-literal="PUBLIC_HOST=${public_host}" \
  --from-literal="ACME_EMAIL=${acme_email}" \
  --from-literal="ACTIVITY_FUNCTION_HOST=${activity_function_host}" \
  --dry-run=client \
  --output=yaml | k3s kubectl apply --filename=-

cp --recursive deploy/kubernetes "${render_directory}/kubernetes"
sed --in-place \
  -e "s/newTag: IMAGE_TAG/newTag: ${deployment_revision}/g" \
  -e "s/DEPLOYMENT_REVISION/${deployment_revision}/g" \
  "${render_directory}/kubernetes/overlays/azure/kustomization.yaml"

if [[ "${cluster_existed}" == "true" ]]; then
  k3s kubectl --namespace "${namespace}" get deployments --output=json |
    jq '{
      apiVersion: "v1",
      kind: "List",
      items: [.items[] | del(
        .metadata.creationTimestamp,
        .metadata.generation,
        .metadata.managedFields,
        .metadata.resourceVersion,
        .metadata.uid,
        .metadata.annotations."deployment.kubernetes.io/revision",
        .status
      )]
    }' >"${deployment_backup}"
fi

k3s kubectl apply \
  --server-side \
  --dry-run=server \
  --field-manager=event-sourced-cqrs-deployer \
  --kustomize "${render_directory}/kubernetes/overlays/azure" >/dev/null

cluster_mutated="true"
k3s kubectl apply \
  --server-side \
  --field-manager=event-sourced-cqrs-deployer \
  --kustomize "${render_directory}/kubernetes/overlays/azure"

for deployment in \
  order-command-service \
  order-query-service \
  inventory-service \
  api-gateway \
  frontend \
  edge-proxy; do
  k3s kubectl --namespace "${namespace}" rollout status \
    "deployment/${deployment}" \
    --timeout=300s
done

"${compose[@]}" rm --force \
  edge-proxy frontend api-gateway order-command-service \
  order-query-service inventory-service discovery-server || true

for attempt in {1..30}; do
  if curl --fail --silent --show-error "http://127.0.0.1" >/dev/null; then
    break
  fi
  if ((attempt == 30)); then
    echo "The Kubernetes edge service did not claim the Azure host ports." >&2
    k3s kubectl --namespace "${namespace}" get pods,services >&2
    exit 1
  fi
  sleep 2
done

"${compose[@]}" run --rm --no-deps debezium-init

k3s kubectl --namespace "${namespace}" port-forward \
  service/api-gateway 18080:8080 \
  >"${port_forward_log}" 2>&1 &
port_forward_pid="$!"
for attempt in {1..30}; do
  if curl --fail --silent "http://127.0.0.1:18080/actuator/health/readiness" >/dev/null; then
    break
  fi
  if ((attempt == 30)); then
    cat "${port_forward_log}" >&2
    exit 1
  fi
  sleep 1
done

GATEWAY_URL=http://127.0.0.1:18080 \
VERIFY_PLATFORM=false \
  ./scripts/smoke-test.sh

for connector_name in order-events inventory-events; do
  connector_status="$(curl --fail --silent "http://${platform_host}:8083/connectors/${connector_name}/status")"
  jq -e '.connector.state == "RUNNING" and .tasks != [] and all(.tasks[]; .state == "RUNNING")' \
    <<<"${connector_status}" >/dev/null
done

deployment_completed="true"

printf 'Azure Kubernetes application deployment %s and CDC verification completed successfully\n' \
  "${deployment_revision}"
