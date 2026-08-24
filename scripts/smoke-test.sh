#!/usr/bin/env bash
set -Eeuo pipefail

gateway_url="${GATEWAY_URL:-http://localhost:8080}"
idempotency_key="smoke-$(date +%s)-${RANDOM}"

wait_for_health() {
  local attempts=30
  for ((attempt = 1; attempt <= attempts; attempt++)); do
    if curl --fail --silent "${gateway_url}/actuator/health/readiness" | jq -e '.status == "UP"' >/dev/null; then
      return 0
    fi
    sleep 1
  done
  echo "Gateway did not become ready at ${gateway_url}" >&2
  return 1
}

wait_for_status() {
  local order_id="$1"
  local expected_status="$2"
  local attempts=30
  for ((attempt = 1; attempt <= attempts; attempt++)); do
    local response
    response="$(curl --silent "${gateway_url}/api/orders/${order_id}")"
    if jq -e --arg status "${expected_status}" '.status == $status' <<<"${response}" >/dev/null 2>&1; then
      printf '%s\n' "${response}"
      return 0
    fi
    sleep 1
  done
  echo "Order ${order_id} did not reach ${expected_status} in the read model" >&2
  return 1
}

wait_for_health

create_payload='{"customerId":"smoke-customer","items":[{"productId":"mechanical-keyboard","quantity":1,"unitPrice":129.90},{"productId":"wireless-mouse","quantity":2,"unitPrice":39.50}]}'
create_response="$(curl --fail --silent \
  --request POST \
  --header 'Content-Type: application/json' \
  --header "Idempotency-Key: ${idempotency_key}" \
  --data "${create_payload}" \
  "${gateway_url}/api/orders")"
order_id="$(jq -er '.orderId' <<<"${create_response}")"

replay_headers="$(curl --fail --silent --dump-header - --output /dev/null \
  --request POST \
  --header 'Content-Type: application/json' \
  --header "Idempotency-Key: ${idempotency_key}" \
  --data "${create_payload}" \
  "${gateway_url}/api/orders")"
grep -qi '^Idempotent-Replay: true' <<<"${replay_headers}"

conflicting_payload='{"customerId":"different-customer","items":[{"productId":"monitor","quantity":1,"unitPrice":299.90}]}'
conflict_response_file="$(mktemp)"
trap 'rm -f "${conflict_response_file}"' EXIT
conflict_status="$(curl --silent --output "${conflict_response_file}" --write-out '%{http_code}' \
  --request POST \
  --header 'Content-Type: application/json' \
  --header "Idempotency-Key: ${idempotency_key}" \
  --data "${conflicting_payload}" \
  "${gateway_url}/api/orders")"
test "${conflict_status}" = "409"
jq -e '.status == 409 and (.detail | contains("different create command"))' \
  "${conflict_response_file}" >/dev/null

created_view="$(wait_for_status "${order_id}" CREATED)"
jq -e '.totalAmount == 208.90 and (.items | length) == 2 and .version == 1' \
  <<<"${created_view}" >/dev/null

curl --fail --silent \
  --request PUT \
  "${gateway_url}/api/orders/${order_id}/cancellation" >/dev/null
cancelled_view="$(wait_for_status "${order_id}" CANCELLED)"
jq -e '.version == 2' <<<"${cancelled_view}" >/dev/null

printf 'Event-sourced CQRS smoke test passed for order %s: CREATED -> CANCELLED\n' "${order_id}"
