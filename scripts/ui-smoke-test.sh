#!/usr/bin/env bash
set -Eeuo pipefail

ui_url="${UI_URL:-http://localhost:3000}"
ui_url="${ui_url%/}"
headers_file="$(mktemp)"
html_file="$(mktemp)"
asset_file="$(mktemp)"
trap 'rm -f "${headers_file}" "${html_file}" "${asset_file}"' EXIT

curl --fail --silent --show-error \
  --dump-header "${headers_file}" \
  --output "${html_file}" \
  "${ui_url}/"

grep --quiet '<title>CQRS Order Portal</title>' "${html_file}"
grep --ignore-case --quiet '^content-security-policy:' "${headers_file}"
grep --ignore-case --quiet '^x-content-type-options: nosniff' "${headers_file}"

asset_path="$(sed -n 's/.*src="\([^\"]*\.js\)".*/\1/p' "${html_file}" | head -n 1)"
if [[ -z "${asset_path}" ]]; then
  echo 'The UI document does not reference a JavaScript application bundle.' >&2
  exit 1
fi

case "${asset_path}" in
  /*) asset_url="${ui_url}${asset_path}" ;;
  *) asset_url="${ui_url}/${asset_path}" ;;
esac

curl --fail --silent --show-error --output "${asset_file}" "${asset_url}"
grep --quiet 'Run complete architecture proof' "${asset_file}"

printf 'React UI smoke test passed at %s\n' "${ui_url}"
