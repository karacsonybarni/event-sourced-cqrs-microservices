#!/usr/bin/env bash
set -Eeuo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
activation_file="${repository_root}/.runtime/saga-activation-at"

cd "${repository_root}"
docker compose --profile ui down --volumes --remove-orphans
rm -f "${activation_file}"
