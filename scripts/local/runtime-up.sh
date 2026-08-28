#!/usr/bin/env bash
set -Eeuo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
runtime_directory="${repository_root}/.runtime"
activation_file="${runtime_directory}/saga-activation-at"

cd "${repository_root}"

compose=(docker compose --profile ui)

./mvnw --batch-mode --no-transfer-progress -DskipTests package
"${compose[@]}" build

if [[ ! -r "${activation_file}" ]]; then
  # Existing local database volumes may contain pre-saga orders. Quiesce
  # command ingress, then persist one cutoff shared by the migration and the
  # inventory consumer. Fresh databases safely use the same procedure.
  "${compose[@]}" stop api-gateway order-command-service
  mkdir -p "${runtime_directory}"
  printf '%s\n' "$(date --utc --iso-8601=seconds)" >"${activation_file}"
fi

activation_at="$(<"${activation_file}")"
SAGA_ACTIVATION_AT="${activation_at}" \
  "${compose[@]}" up --no-build --detach --wait \
  --scale order-command-service=2 \
  --scale order-query-service=2
