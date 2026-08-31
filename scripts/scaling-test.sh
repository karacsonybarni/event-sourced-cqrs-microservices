#!/usr/bin/env bash
set -Eeuo pipefail

gateway_url="${GATEWAY_URL:-http://localhost:8080}"
stopped_containers=()

restore_containers() {
  local container_id
  for container_id in "${stopped_containers[@]}"; do
    docker start "${container_id}" >/dev/null 2>&1 || true
  done
}
trap restore_containers EXIT

healthy_container_count() {
  local service_name="$1"
  local container_id
  local health_status
  local count=0
  while IFS= read -r container_id; do
    if [[ -z "${container_id}" ]]; then
      continue
    fi
    health_status="$(docker inspect \
      --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' \
      "${container_id}")"
    if [[ "${health_status}" == "healthy" || "${health_status}" == "running" ]]; then
      ((count += 1))
    fi
  done < <(docker compose ps --status running --quiet "${service_name}")
  printf '%d\n' "${count}"
}

wait_for_instance_count() {
  local service_name="$1"
  local expected_count="$2"
  local attempts=60
  for ((attempt = 1; attempt <= attempts; attempt++)); do
    if [[ "$(healthy_container_count "${service_name}")" -eq "${expected_count}" ]]; then
      return 0
    fi
    sleep 1
  done
  echo "${service_name} did not reach ${expected_count} healthy containers" >&2
  return 1
}

create_order() {
  local idempotency_key
  idempotency_key="scale-$(date +%s)-${RANDOM}"
  local payload='{"customerId":"scale-customer","items":[{"productId":"mechanical-keyboard","quantity":1,"unitPrice":99.90}]}'
  local attempts=30
  local response
  for ((attempt = 1; attempt <= attempts; attempt++)); do
    if response="$(curl --fail --silent \
      --request POST \
      --header 'Content-Type: application/json' \
      --header "Idempotency-Key: ${idempotency_key}" \
      --data "${payload}" \
      "${gateway_url}/api/orders" 2>/dev/null)"; then
      jq -er '.orderId' <<<"${response}"
      return 0
    fi
    sleep 1
  done
  echo "Gateway did not route a create command to the surviving replica" >&2
  return 1
}

wait_for_order() {
  local order_id="$1"
  local attempts=30
  for ((attempt = 1; attempt <= attempts; attempt++)); do
    if curl --fail --silent "${gateway_url}/api/orders/${order_id}" | jq -e '.status == "CONFIRMED"' >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  echo "Query traffic did not reach a surviving replica for order ${order_id}" >&2
  return 1
}

mapfile -t command_containers < <(docker compose ps -q order-command-service)
mapfile -t query_containers < <(docker compose ps -q order-query-service)
test "${#command_containers[@]}" -eq 2
test "${#query_containers[@]}" -eq 2
wait_for_instance_count order-command-service 2
wait_for_instance_count order-query-service 2

last_order_id=""
for container_id in "${command_containers[@]}"; do
  docker stop "${container_id}" >/dev/null
  stopped_containers+=("${container_id}")
  wait_for_instance_count order-command-service 1
  last_order_id="$(create_order)"
  wait_for_order "${last_order_id}"
  docker start "${container_id}" >/dev/null
  stopped_containers=()
  wait_for_instance_count order-command-service 2
done

for container_id in "${query_containers[@]}"; do
  docker stop "${container_id}" >/dev/null
  stopped_containers+=("${container_id}")
  wait_for_instance_count order-query-service 1
  wait_for_order "${last_order_id}"
  docker start "${container_id}" >/dev/null
  stopped_containers=()
  wait_for_instance_count order-query-service 2
done

printf 'Platform DNS routing and failover test passed with two command and two query replicas\n'
