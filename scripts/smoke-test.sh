#!/usr/bin/env bash
set -Eeuo pipefail

gateway_url="${GATEWAY_URL:-http://localhost:8080}"
gateway_health_url="${GATEWAY_HEALTH_URL:-${gateway_url}}"
discovery_url="${DISCOVERY_URL:-http://localhost:8761}"
expected_command_instances="${EXPECTED_COMMAND_INSTANCES:-1}"
expected_query_instances="${EXPECTED_QUERY_INSTANCES:-1}"
expected_inventory_instances="${EXPECTED_INVENTORY_INSTANCES:-1}"
verify_platform="${VERIFY_PLATFORM:-true}"
verify_inventory_state="${VERIFY_INVENTORY_STATE:-${verify_platform}}"
idempotency_key="smoke-$(date +%s)-${RANDOM}"

wait_for_health() {
  local attempts=30
  for ((attempt = 1; attempt <= attempts; attempt++)); do
    if curl --fail --silent "${gateway_health_url}/actuator/health/readiness" | jq -e '.status == "UP"' >/dev/null; then
      return 0
    fi
    sleep 1
  done
  echo "Gateway did not become ready at ${gateway_url}" >&2
  return 1
}

registry_instance_count() {
  local application_name="$1"
  local response
  if ! response="$(curl --fail --silent \
    --header 'Accept: application/json' \
    "${discovery_url}/eureka/apps/${application_name}")"; then
    printf '0\n'
    return
  fi
  jq -r '[.application.instance[]? | select(.status == "UP")] | length' <<<"${response}"
}

wait_for_instances() {
  local application_name="$1"
  local expected_count="$2"
  local attempts=60
  for ((attempt = 1; attempt <= attempts; attempt++)); do
    if [[ "$(registry_instance_count "${application_name}")" -ge "${expected_count}" ]]; then
      return 0
    fi
    sleep 1
  done
  echo "${application_name} did not register ${expected_count} instances" >&2
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

inventory_stock() {
  local product_id="$1"
  docker compose exec -T inventory-db \
    psql --username inventory --dbname inventory --tuples-only --no-align \
    --command "SELECT available_quantity FROM stock_items WHERE product_id = '${product_id}'" \
    | tr -d '[:space:]'
}

wait_for_inventory_event() {
  local order_id="$1"
  local expected_event_type="$2"
  local attempts=30
  for ((attempt = 1; attempt <= attempts; attempt++)); do
    local event_count
    event_count="$(docker compose exec -T inventory-db \
      psql --username inventory --dbname inventory --tuples-only --no-align \
      --command "SELECT count(*) FROM inventory_events WHERE aggregate_id = '${order_id}'::uuid AND event_type = '${expected_event_type}'" \
      2>/dev/null | tr -d '[:space:]')"
    if [[ "${event_count}" == "1" ]]; then
      return 0
    fi
    sleep 1
  done
  echo "Inventory reservation ${order_id} did not append ${expected_event_type}" >&2
  return 1
}

if [[ "${verify_platform}" == "true" ]]; then
  wait_for_health
  wait_for_instances ORDER-COMMAND-SERVICE "${expected_command_instances}"
  wait_for_instances ORDER-QUERY-SERVICE "${expected_query_instances}"
  wait_for_instances INVENTORY-SERVICE "${expected_inventory_instances}"
fi

if [[ "${verify_inventory_state}" == "true" ]]; then
  keyboard_stock_before="$(inventory_stock mechanical-keyboard)"
  mouse_stock_before="$(inventory_stock wireless-mouse)"
fi

create_payload='{"customerId":"smoke-customer","items":[{"productId":"mechanical-keyboard","quantity":1,"unitPrice":129.90},{"productId":"wireless-mouse","quantity":2,"unitPrice":39.50}]}'
create_response="$(curl --fail --silent \
  --request POST \
  --header 'Content-Type: application/json' \
  --header "Idempotency-Key: ${idempotency_key}" \
  --data "${create_payload}" \
  "${gateway_url}/api/orders")"
order_id="$(jq -er '.orderId' <<<"${create_response}")"
[[ "${order_id}" =~ ^[0-9a-fA-F-]{36}$ ]]

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

confirmed_view="$(wait_for_status "${order_id}" CONFIRMED)"
jq -e '.totalAmount == 208.90 and (.items | length) == 2 and .version == 2' \
  <<<"${confirmed_view}" >/dev/null

if [[ "${verify_inventory_state}" == "true" ]]; then
  wait_for_inventory_event "${order_id}" InventoryReserved.v1
  test "$(inventory_stock mechanical-keyboard)" = "$((keyboard_stock_before - 1))"
  test "$(inventory_stock wireless-mouse)" = "$((mouse_stock_before - 2))"
fi

curl --fail --silent \
  --request PUT \
  "${gateway_url}/api/orders/${order_id}/cancellation" >/dev/null
cancelled_view="$(wait_for_status "${order_id}" CANCELLED)"
jq -e '.version == 3' <<<"${cancelled_view}" >/dev/null

if [[ "${verify_inventory_state}" == "true" ]]; then
  wait_for_inventory_event "${order_id}" InventoryReleased.v1
  test "$(inventory_stock mechanical-keyboard)" = "${keyboard_stock_before}"
  test "$(inventory_stock wireless-mouse)" = "${mouse_stock_before}"
fi

rejected_response="$(curl --fail --silent \
  --request POST \
  --header 'Content-Type: application/json' \
  --header "Idempotency-Key: ${idempotency_key}-rejected" \
  --data '{"customerId":"smoke-customer","items":[{"productId":"out-of-stock-item","quantity":1,"unitPrice":1.00}]}' \
  "${gateway_url}/api/orders")"
rejected_order_id="$(jq -er '.orderId' <<<"${rejected_response}")"
[[ "${rejected_order_id}" =~ ^[0-9a-fA-F-]{36}$ ]]
rejected_view="$(wait_for_status "${rejected_order_id}" REJECTED)"
jq -e '.version == 2 and .rejectionReason == "Insufficient stock for out-of-stock-item"' \
  <<<"${rejected_view}" >/dev/null

if [[ "${verify_inventory_state}" == "true" ]]; then
  wait_for_inventory_event "${rejected_order_id}" InventoryRejected.v1
fi

printf 'Saga smoke test passed: order %s CONFIRMED -> CANCELLED with compensation; order %s REJECTED\n' \
  "${order_id}" "${rejected_order_id}"
