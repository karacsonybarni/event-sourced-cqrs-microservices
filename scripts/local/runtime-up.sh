#!/usr/bin/env bash
set -Eeuo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

cd "${repository_root}"

compose=(docker compose --profile ui)

./mvnw --batch-mode --no-transfer-progress -DskipTests package
"${compose[@]}" build
"${compose[@]}" up --no-build --detach --wait command-db

activation_at="$(
  "${compose[@]}" exec --no-TTY command-db \
    psql --username orders --dbname orders_command --tuples-only --no-align \
    --command "SELECT to_char(activation_at AT TIME ZONE 'UTC', 'YYYY-MM-DD\"T\"HH24:MI:SS\"Z\"') FROM saga_configuration WHERE configuration_key = 'inventory-saga-activation'" \
    2>/dev/null || true
)"

if [[ -z "${activation_at}" ]]; then
  # Existing local database volumes may contain pre-saga orders. Quiesce
  # command ingress before fixing the cutoff that Flyway persists alongside
  # the event store. Fresh databases safely use the same procedure.
  "${compose[@]}" stop api-gateway order-command-service
  activation_at="$(date --utc --iso-8601=seconds)"
fi

SAGA_ACTIVATION_AT="${activation_at}" \
  "${compose[@]}" up --no-build --detach --wait \
  --scale order-command-service=2 \
  --scale order-query-service=2

persisted_activation_at="$(
  "${compose[@]}" exec --no-TTY command-db \
    psql --username orders --dbname orders_command --tuples-only --no-align \
    --command "SELECT to_char(activation_at AT TIME ZONE 'UTC', 'YYYY-MM-DD\"T\"HH24:MI:SS\"Z\"') FROM saga_configuration WHERE configuration_key = 'inventory-saga-activation'"
)"
if [[ "$(date --date "${persisted_activation_at}" --utc +%s)" != "$(date --date "${activation_at}" --utc +%s)" ]]; then
  echo "Persisted saga activation boundary does not match the runtime boundary" >&2
  exit 1
fi
