#!/usr/bin/env bash
set -Eeuo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
runtime_environment="${RUNTIME_ENVIRONMENT:-/etc/event-sourced-cqrs/runtime.env}"

if [[ ! -r "${runtime_environment}" ]]; then
  echo "Azure runtime configuration is unavailable at ${runtime_environment}" >&2
  exit 1
fi

if ! grep --quiet '^INVENTORY_DB_PASSWORD=' "${runtime_environment}"; then
  inventory_db_password="$(openssl rand -hex 24)"
  umask 077
  printf 'INVENTORY_DB_PASSWORD=%s\n' "${inventory_db_password}" >>"${runtime_environment}"
fi

if ! grep --quiet '^SAGA_ACTIVATION_AT=' "${runtime_environment}"; then
  printf 'SAGA_ACTIVATION_AT=%s\n' "$(date --utc --iso-8601=seconds)" >>"${runtime_environment}"
fi

cd "${repository_root}"

compose=(
  docker compose
  --profile ui
  --env-file "${runtime_environment}"
  --file compose.yml
  --file compose.azure.yml
)

./mvnw --batch-mode --no-transfer-progress -DskipTests package

if ! "${compose[@]}" up --build --detach --wait --remove-orphans \
  --scale order-command-service=2 \
  --scale order-query-service=2; then
  "${compose[@]}" logs --no-color --tail 200 >&2 || true
  exit 1
fi

# Caddy loads its bind-mounted configuration at startup, so recreate only the
# edge container to apply routing or security-header changes on every release.
if ! "${compose[@]}" up --detach --force-recreate --no-deps --wait edge-proxy; then
  "${compose[@]}" logs --no-color --tail 200 edge-proxy >&2 || true
  exit 1
fi

GATEWAY_URL=http://localhost:8080 \
GATEWAY_HEALTH_URL=http://localhost:9080 \
DISCOVERY_URL=http://localhost:8761 \
EXPECTED_COMMAND_INSTANCES=2 \
EXPECTED_QUERY_INSTANCES=2 \
EXPECTED_INVENTORY_INSTANCES=1 \
  ./scripts/smoke-test.sh

for connector_name in order-events inventory-events; do
  connector_status="$(curl --fail --silent "http://localhost:8083/connectors/${connector_name}/status")"
  jq -e '.connector.state == "RUNNING" and .tasks != [] and all(.tasks[]; .state == "RUNNING")' \
    <<<"${connector_status}" >/dev/null
done

printf 'Azure runtime deployment and CDC verification completed successfully\n'
