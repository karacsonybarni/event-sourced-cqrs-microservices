#!/usr/bin/env bash
set -Eeuo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
runtime_environment="${RUNTIME_ENVIRONMENT:-/etc/event-sourced-cqrs/runtime.env}"
namespace="cqrs-orders"

if [[ ! -r "${runtime_environment}" ]]; then
  echo "AWS runtime configuration is unavailable at ${runtime_environment}" >&2
  exit 1
fi

read_runtime_setting() {
  local setting_name="$1"
  local setting_value
  setting_value="$(sed -n "s/^${setting_name}=//p" "${runtime_environment}" | tail -1)"
  if [[ -z "${setting_value}" ]]; then
    printf 'AWS runtime setting %s is missing.\n' "${setting_name}" >&2
    return 1
  fi
  printf '%s' "${setting_value}"
}

if ! grep --quiet '^INVENTORY_DB_PASSWORD=' "${runtime_environment}"; then
  inventory_db_password="$(openssl rand -hex 24)"
  (
    umask 077
    printf 'INVENTORY_DB_PASSWORD=%s\n' "${inventory_db_password}" >>"${runtime_environment}"
  )
fi

command_db_password="$(read_runtime_setting COMMAND_DB_PASSWORD)"
query_db_password="$(read_runtime_setting QUERY_DB_PASSWORD)"
inventory_db_password="$(read_runtime_setting INVENTORY_DB_PASSWORD)"
saga_activation_at="$(read_runtime_setting SAGA_ACTIVATION_AT)"

token="$(curl --fail --silent --show-error \
  --request PUT \
  --header 'X-aws-ec2-metadata-token-ttl-seconds: 300' \
  http://169.254.169.254/latest/api/token)"
platform_host="$(curl --fail --silent --show-error \
  --header "X-aws-ec2-metadata-token: ${token}" \
  http://169.254.169.254/latest/meta-data/local-ipv4)"
if [[ ! "${platform_host}" =~ ^10\.20\.1\.[0-9]+$ ]]; then
  printf 'Unexpected EC2 platform address %s.\n' "${platform_host}" >&2
  exit 1
fi

cd "${repository_root}"
deployment_revision="$(git rev-parse HEAD)"
if [[ ! "${deployment_revision}" =~ ^[0-9a-f]{40}$ ]]; then
  echo "The checked-out deployment revision is not a complete Git commit SHA." >&2
  exit 1
fi

bash ./scripts/aws/install-k3s.sh

export PLATFORM_HOST="${platform_host}"
export KAFKA_NODE_HOST="${platform_host}"
compose=(
  docker compose
  --profile ui
  --env-file "${runtime_environment}"
  --file compose.yml
  --file compose.cloud.yml
  --file compose.aws-kubernetes.yml
  --file compose.kubernetes-platform.yml
)

"${compose[@]}" up --no-build --detach --wait \
  command-db query-db inventory-db kafka kafka-init debezium

# Reclaim the legacy Compose application footprint before building and importing
# the Kubernetes application images. The stateful platform remains in Compose.
"${compose[@]}" stop \
  frontend api-gateway order-command-service order-projection-worker \
  order-query-service inventory-service || true
"${compose[@]}" rm --force \
  frontend api-gateway order-command-service order-projection-worker \
  order-query-service inventory-service || true

./mvnw --batch-mode --no-transfer-progress -DskipTests package

application_images=(
  "escqrs/order-command-service:${deployment_revision}"
  "escqrs/order-projection-worker:${deployment_revision}"
  "escqrs/order-query-service:${deployment_revision}"
  "escqrs/inventory-service:${deployment_revision}"
  "escqrs/api-gateway:${deployment_revision}"
  "escqrs/frontend:${deployment_revision}"
)

docker build --tag "${application_images[0]}" --file order-command-service/Dockerfile .
docker build --tag "${application_images[1]}" --file order-projection-worker/Dockerfile .
docker build --tag "${application_images[2]}" --file order-query-service/Dockerfile .
docker build --tag "${application_images[3]}" --file inventory-service/Dockerfile .
docker build --tag "${application_images[4]}" --file api-gateway/Dockerfile .
docker build --tag "${application_images[5]}" frontend

image_archive="$(mktemp --suffix=.tar)"
render_directory="$(mktemp -d)"
port_forward_log="$(mktemp)"
port_forward_pid=""
cleanup() {
  set +e
  if [[ -n "${port_forward_pid}" ]]; then
    kill "${port_forward_pid}" 2>/dev/null || true
    wait "${port_forward_pid}" 2>/dev/null || true
  fi
  rm -f "${image_archive}" "${port_forward_log}"
  rm -rf "${render_directory}"
}
trap cleanup EXIT

docker save --output "${image_archive}" "${application_images[@]}"
k3s ctr images import "${image_archive}"

runtime_config_revision="$(
  {
    printf 'COMMAND_DB_PASSWORD\0%s\0' "${command_db_password}"
    printf 'QUERY_DB_PASSWORD\0%s\0' "${query_db_password}"
    printf 'INVENTORY_DB_PASSWORD\0%s\0' "${inventory_db_password}"
    printf 'SAGA_ACTIVATION_AT\0%s\0' "${saga_activation_at}"
    printf 'PLATFORM_HOST\0%s\0' "${platform_host}"
  } | sha256sum | cut -d' ' -f1
)"

k3s kubectl apply --filename deploy/kubernetes/base/namespace.yaml
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

cp --recursive deploy/kubernetes "${render_directory}/kubernetes"
sed --in-place \
  -e "s/newTag: IMAGE_TAG/newTag: ${deployment_revision}/g" \
  -e "s/RUNTIME_CONFIG_REVISION/${runtime_config_revision}/g" \
  -e "s/value: PLATFORM_HOST/value: ${platform_host}/g" \
  "${render_directory}/kubernetes/overlays/aws/kustomization.yaml"

k3s kubectl apply \
  --server-side \
  --dry-run=server \
  --field-manager=event-sourced-cqrs-deployer \
  --kustomize "${render_directory}/kubernetes/overlays/aws" >/dev/null
k3s kubectl apply \
  --server-side \
  --field-manager=event-sourced-cqrs-deployer \
  --kustomize "${render_directory}/kubernetes/overlays/aws"

for deployment in \
  order-command-service \
  order-projection-worker \
  order-query-service \
  inventory-service \
  api-gateway \
  frontend; do
  if ! k3s kubectl --namespace "${namespace}" rollout status \
    "deployment/${deployment}" --timeout=300s; then
    k3s kubectl --namespace "${namespace}" get pods,services,endpointslices --output=wide >&2 || true
    k3s kubectl --namespace "${namespace}" describe "deployment/${deployment}" >&2 || true
    k3s kubectl --namespace "${namespace}" logs \
      --selector "app.kubernetes.io/name=${deployment}" \
      --all-containers --tail=100 >&2 || true
    exit 1
  fi
done

for attempt in {1..60}; do
  if curl --fail --silent --show-error http://127.0.0.1:8080/ >/dev/null; then
    break
  fi
  if ((attempt == 60)); then
    echo "The Kubernetes frontend Service did not claim AWS host port 8080." >&2
    k3s kubectl --namespace "${namespace}" get pods,services --output=wide >&2
    exit 1
  fi
  sleep 2
done

bash ./scripts/aws/verify-kubernetes-runtime.sh "${deployment_revision}"

"${compose[@]}" run --rm --no-deps debezium-init

k3s kubectl --namespace "${namespace}" port-forward service/api-gateway 18080:8080 \
  >"${port_forward_log}" 2>&1 &
port_forward_pid="$!"
for attempt in {1..30}; do
  if curl --fail --silent http://127.0.0.1:18080/actuator/health/readiness >/dev/null; then
    break
  fi
  if ((attempt == 30)); then
    cat "${port_forward_log}" >&2
    exit 1
  fi
  sleep 1
done

GATEWAY_URL=http://127.0.0.1:18080 VERIFY_PLATFORM=false ./scripts/smoke-test.sh
GATEWAY_URL=http://127.0.0.1:8080 VERIFY_PLATFORM=false ./scripts/smoke-test.sh
UI_URL=http://127.0.0.1:8080 ./scripts/ui-smoke-test.sh

for connector_name in order-events inventory-events; do
  connector_status="$(curl --fail --silent "http://${platform_host}:8083/connectors/${connector_name}/status")"
  jq -e '.connector.state == "RUNNING" and .tasks != [] and all(.tasks[]; .state == "RUNNING")' \
    <<<"${connector_status}" >/dev/null
done

printf 'AWS Kubernetes application deployment %s and CDC verification completed successfully\n' \
  "${deployment_revision}"
