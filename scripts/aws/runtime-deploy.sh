#!/usr/bin/env bash
set -Eeuo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
runtime_environment="${RUNTIME_ENVIRONMENT:-/etc/event-sourced-cqrs/runtime.env}"

if [[ ! -r "${runtime_environment}" ]]; then
  echo "Cloud runtime configuration is unavailable at ${runtime_environment}" >&2
  exit 1
fi

if ! grep --quiet '^INVENTORY_DB_PASSWORD=' "${runtime_environment}"; then
  inventory_db_password="$(openssl rand -hex 24)"
  (
    umask 077
    printf 'INVENTORY_DB_PASSWORD=%s\n' "${inventory_db_password}" >>"${runtime_environment}"
  )
fi

cd "${repository_root}"

compose=(
  docker compose
  --profile ui
  --env-file "${runtime_environment}"
  --file compose.yml
  --file compose.cloud.yml
)

./mvnw --batch-mode --no-transfer-progress -DskipTests package
"${compose[@]}" build

if ! grep --quiet '^SAGA_ACTIVATION_AT=' "${runtime_environment}"; then
  # Finish all fallible preparation first, then quiesce command ingress before
  # fixing the one-time boundary. A failed rollout can now be retried without
  # leaving accepted orders on the wrong side of an already-persisted cutoff.
  "${compose[@]}" stop api-gateway order-command-service
  saga_activation_at="$(date --utc +%Y-%m-%dT%H:%M:%S.%NZ)"
  printf 'SAGA_ACTIVATION_AT=%sZ\n' "${saga_activation_at:0:26}" >>"${runtime_environment}"
fi

if ! "${compose[@]}" up --no-build --detach --wait --remove-orphans \
  --scale order-command-service=2 \
  --scale order-query-service=2; then
  "${compose[@]}" logs --no-color --tail 200 >&2 || true
  exit 1
fi

GATEWAY_URL=http://localhost:8080 \
GATEWAY_HEALTH_URL=http://localhost:9080 \
EXPECTED_COMMAND_INSTANCES=2 \
EXPECTED_QUERY_INSTANCES=2 \
EXPECTED_INVENTORY_INSTANCES=1 \
  ./scripts/smoke-test.sh

UI_URL=http://localhost:8080 ./scripts/ui-smoke-test.sh

for connector_name in order-events inventory-events; do
  connector_status="$(curl --fail --silent "http://localhost:8083/connectors/${connector_name}/status")"
  jq -e '.connector.state == "RUNNING" and .tasks != [] and all(.tasks[]; .state == "RUNNING")' \
    <<<"${connector_status}" >/dev/null
done

printf 'Cloud runtime deployment and CDC verification completed successfully\n'
