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

application_compose=(
  docker compose
  --profile ui
  --env-file "${runtime_environment}"
  --file compose.yml
  --file compose.azure.yml
)
compose=(
  "${application_compose[@]}"
  --file compose.kubernetes-platform.yml
)
export PLATFORM_HOST="${platform_host}"
export KAFKA_VNET_HOST="${platform_host}"

image_archive="$(mktemp --suffix=.tar)"
render_directory="$(mktemp -d)"
port_forward_log="$(mktemp)"
deployment_backup="$(mktemp)"
runtime_config_backup="$(mktemp)"
failure_diagnostics="$(mktemp)"
port_forward_pid=""
cluster_existed="false"
platform_mutated="false"
runtime_config_mutated="false"
cluster_mutated="false"
deployment_completed="false"
runtime_secret_existed="false"
runtime_configmap_existed="false"
rollback_images=()
cleanup() {
  set +e
  if [[ -n "${port_forward_pid}" ]]; then
    kill "${port_forward_pid}" 2>/dev/null || true
    wait "${port_forward_pid}" 2>/dev/null || true
  fi
  if [[ "${deployment_completed}" != "true" && \
        ("${platform_mutated}" == "true" || \
         "${runtime_config_mutated}" == "true" || \
         "${cluster_mutated}" == "true") ]]; then
    if [[ "${cluster_existed}" != "true" ]]; then
      k3s kubectl delete namespace "${namespace}" --ignore-not-found --wait --timeout=120s
      "${application_compose[@]}" up --no-build --detach --wait --wait-timeout 600 --remove-orphans \
        --scale order-command-service=2 \
        --scale order-query-service=2 \
        command-db query-db inventory-db kafka kafka-2 kafka-3 kafka-init debezium \
        order-command-service order-projection-worker order-query-service \
        inventory-service api-gateway frontend edge-proxy
    else
      if [[ "${runtime_config_mutated}" == "true" && -s "${runtime_config_backup}" ]]; then
        k3s kubectl apply \
          --server-side \
          --force-conflicts \
          --field-manager=event-sourced-cqrs-deployer \
          --filename "${runtime_config_backup}"
        if [[ "${runtime_secret_existed}" != "true" ]]; then
          k3s kubectl --namespace "${namespace}" delete secret runtime-secrets --ignore-not-found
        fi
        if [[ "${runtime_configmap_existed}" != "true" ]]; then
          k3s kubectl --namespace "${namespace}" delete configmap runtime-config --ignore-not-found
        fi
      fi
      if [[ "${cluster_mutated}" == "true" && -s "${deployment_backup}" ]]; then
        k3s kubectl apply \
          --server-side \
          --force-conflicts \
          --field-manager=event-sourced-cqrs-deployer \
          --filename "${deployment_backup}"
        for deployment in \
          order-command-service \
          order-projection-worker \
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
      if [[ "${platform_mutated}" == "true" ]]; then
        "${compose[@]}" up --no-build --detach --wait --wait-timeout 600 \
          command-db query-db inventory-db kafka kafka-2 kafka-3 kafka-init debezium
      fi
    fi
  fi
  if [[ -s "${failure_diagnostics}" ]]; then
    printf '\nKubernetes deployment failure diagnostics:\n' >&2
    cat "${failure_diagnostics}" >&2
  fi
  rm -f \
    "${image_archive}" \
    "${port_forward_log}" \
    "${deployment_backup}" \
    "${runtime_config_backup}" \
    "${failure_diagnostics}"
  rm -rf "${render_directory}"
}
trap cleanup EXIT

existing_gateway="$(
  k3s kubectl --namespace "${namespace}" get deployment api-gateway \
    --ignore-not-found \
    --output=name
)"
if [[ -n "${existing_gateway}" ]]; then
  cluster_existed="true"
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
  mapfile -t rollback_images < <(
    jq -r '.items[] | select(.metadata.name != "edge-proxy") | .spec.template.spec.containers[0].image' \
      "${deployment_backup}"
  )
  if k3s kubectl --namespace "${namespace}" get secret runtime-secrets >/dev/null 2>&1; then
    runtime_secret_existed="true"
  fi
  if k3s kubectl --namespace "${namespace}" get configmap runtime-config >/dev/null 2>&1; then
    runtime_configmap_existed="true"
  fi
  k3s kubectl --namespace "${namespace}" get \
    secret/runtime-secrets configmap/runtime-config \
    --ignore-not-found \
    --output=json |
    jq '{
      apiVersion: "v1",
      kind: "List",
      items: [.items[] | del(
        .metadata.annotations,
        .metadata.creationTimestamp,
        .metadata.managedFields,
        .metadata.resourceVersion,
        .metadata.uid
      )]
    }' >"${runtime_config_backup}"
fi

platform_mutated="true"
EXPECTED_KAFKA_CLUSTER_ID=5L6g3nShT-eMCtK--X86sw \
  ./scripts/kafka/prepare-storage.sh \
  --profile ui \
  --env-file "${runtime_environment}" \
  --file compose.yml \
  --file compose.azure.yml \
  --file compose.kubernetes-platform.yml
"${compose[@]}" up --no-build --detach --wait --wait-timeout 600 \
  --remove-orphans \
  command-db query-db inventory-db kafka kafka-2 kafka-3 kafka-init debezium

if [[ "${cluster_existed}" != "true" ]]; then
  # The first cutover must reclaim the measured Compose application footprint
  # before Maven and image builds run alongside the K3s control plane.
  "${compose[@]}" stop \
    edge-proxy frontend api-gateway order-command-service \
    order-projection-worker order-query-service inventory-service
fi

./mvnw --batch-mode --no-transfer-progress -DskipTests package

application_images=(
  "escqrs/order-command-service:${deployment_revision}"
  "escqrs/order-projection-worker:${deployment_revision}"
  "escqrs/order-query-service:${deployment_revision}"
  "escqrs/inventory-service:${deployment_revision}"
  "escqrs/api-gateway:${deployment_revision}"
  "escqrs/frontend:${deployment_revision}"
)
edge_proxy_image="caddy:2.10.2-alpine@sha256:4c6e91c6ed0e2fa03efd5b44747b625fec79bc9cd06ac5235a779726618e530d"

retained_application_image() {
  local candidate="${1#docker.io/}"
  local retained
  for retained in "${application_images[@]}" "${rollback_images[@]}"; do
    if [[ "${candidate}" == "${retained#docker.io/}" ]]; then
      return 0
    fi
  done
  return 1
}

prune_application_images() {
  local application_image_pattern='^escqrs/(order-command-service|order-projection-worker|order-query-service|inventory-service|api-gateway|frontend):[0-9a-f]{40}$'
  local image
  local normalized_image

  while IFS= read -r image; do
    if [[ "${image}" =~ ${application_image_pattern} ]] && ! retained_application_image "${image}"; then
      docker image rm "${image}"
    fi
  done < <(docker image list --format '{{.Repository}}:{{.Tag}}')

  while IFS= read -r image; do
    normalized_image="${image#docker.io/}"
    if [[ "${normalized_image}" =~ ${application_image_pattern} ]] && \
       ! retained_application_image "${normalized_image}"; then
      k3s ctr images remove "${image}"
    fi
  done < <(k3s ctr images list --quiet)

  docker buildx prune --force --max-used-space 2GB
}

docker build --tag "${application_images[0]}" --file order-command-service/Dockerfile .
docker build --tag "${application_images[1]}" --file order-projection-worker/Dockerfile .
docker build --tag "${application_images[2]}" --file order-query-service/Dockerfile .
docker build --tag "${application_images[3]}" --file inventory-service/Dockerfile .
docker build --tag "${application_images[4]}" --file api-gateway/Dockerfile .
docker build \
  --build-arg VITE_SERVERLESS_PROJECTION_ENABLED=true \
  --tag "${application_images[5]}" \
  frontend
docker save --output "${image_archive}" "${application_images[@]}"
k3s ctr images import "${image_archive}"
k3s ctr images pull "docker.io/library/${edge_proxy_image}"
k3s ctr images inspect "docker.io/library/${edge_proxy_image}" >/dev/null

runtime_config_revision="$(
  {
    printf 'COMMAND_DB_PASSWORD\0%s\0' "${command_db_password}"
    printf 'QUERY_DB_PASSWORD\0%s\0' "${query_db_password}"
    printf 'INVENTORY_DB_PASSWORD\0%s\0' "${inventory_db_password}"
    printf 'SAGA_ACTIVATION_AT\0%s\0' "${saga_activation_at}"
    printf 'PUBLIC_HOST\0%s\0' "${public_host}"
    printf 'ACME_EMAIL\0%s\0' "${acme_email}"
    printf 'ACTIVITY_FUNCTION_HOST\0%s\0' "${activity_function_host}"
  } | sha256sum | cut -d' ' -f1
)"

k3s kubectl apply --filename deploy/kubernetes/base/namespace.yaml
runtime_config_mutated="true"
k3s kubectl --namespace "${namespace}" create secret generic runtime-secrets \
  --from-literal="command-db-password=${command_db_password}" \
  --from-literal="query-db-password=${query_db_password}" \
  --from-literal="inventory-db-password=${inventory_db_password}" \
  --from-literal="saga-activation-at=${saga_activation_at}" \
  --dry-run=client \
  --output=yaml | k3s kubectl apply \
    --server-side \
    --force-conflicts \
    --field-manager=event-sourced-cqrs-deployer \
    --filename=-
k3s kubectl --namespace "${namespace}" create configmap runtime-config \
  --from-literal="PUBLIC_HOST=${public_host}" \
  --from-literal="ACME_EMAIL=${acme_email}" \
  --from-literal="ACTIVITY_FUNCTION_HOST=${activity_function_host}" \
  --dry-run=client \
  --output=yaml | k3s kubectl apply \
    --server-side \
    --force-conflicts \
    --field-manager=event-sourced-cqrs-deployer \
    --filename=-

cp --recursive deploy/kubernetes "${render_directory}/kubernetes"
sed --in-place \
  -e "s/newTag: IMAGE_TAG/newTag: ${deployment_revision}/g" \
  -e "s/DEPLOYMENT_REVISION/${deployment_revision}/g" \
  -e "s/RUNTIME_CONFIG_REVISION/${runtime_config_revision}/g" \
  "${render_directory}/kubernetes/overlays/azure/kustomization.yaml"

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
  order-projection-worker \
  order-query-service \
  inventory-service \
  api-gateway \
  frontend \
  edge-proxy; do
  if ! k3s kubectl --namespace "${namespace}" rollout status \
    "deployment/${deployment}" \
    --timeout=300s; then
    {
      printf 'Rollout failed for deployment/%s.\n' "${deployment}"
      k3s kubectl --namespace "${namespace}" get \
        pods,services,persistentvolumeclaims \
        --output=wide || true
      k3s kubectl --namespace "${namespace}" describe "deployment/${deployment}" || true
      k3s kubectl --namespace "${namespace}" describe pods \
        --selector "app.kubernetes.io/name=${deployment}" || true
      k3s kubectl --namespace "${namespace}" logs \
        --selector "app.kubernetes.io/name=${deployment}" \
        --all-containers \
        --tail=100 || true
      k3s kubectl --namespace "${namespace}" get events \
        --sort-by=.lastTimestamp || true
    } >"${failure_diagnostics}" 2>&1
    exit 1
  fi
done

"${compose[@]}" rm --force \
  edge-proxy frontend api-gateway order-command-service \
  order-projection-worker order-query-service inventory-service || true

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

GATEWAY_URL=http://127.0.0.1:18080 \
VERIFY_PLATFORM=false \
COMPOSE_FILE=compose.yml:compose.azure.yml:compose.kubernetes-platform.yml \
COMPOSE_ENV_FILES="${runtime_environment}" \
  ./scripts/kafka-broker-failover-test.sh \
    --profile ui \
    --env-file "${runtime_environment}" \
    --file compose.yml \
    --file compose.azure.yml \
    --file compose.kubernetes-platform.yml

for connector_name in order-events inventory-events; do
  connector_status="$(curl --fail --silent "http://${platform_host}:8083/connectors/${connector_name}/status")"
  jq -e '.connector.state == "RUNNING" and .tasks != [] and all(.tasks[]; .state == "RUNNING")' \
    <<<"${connector_status}" >/dev/null
done

prune_application_images
deployment_completed="true"

printf 'Azure Kubernetes application deployment %s and CDC verification completed successfully\n' \
  "${deployment_revision}"
