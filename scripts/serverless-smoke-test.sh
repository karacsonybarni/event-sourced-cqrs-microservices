#!/usr/bin/env bash
set -Eeuo pipefail

gateway_url="${GATEWAY_URL:-http://localhost:8080}"
customer_id="serverless-smoke-$(date +%s)-${RANDOM}"
idempotency_key="serverless-smoke-${customer_id}"

create_response="$(curl --fail-with-body --silent --show-error \
  --request POST \
  --header 'Content-Type: application/json' \
  --header "Idempotency-Key: ${idempotency_key}" \
  --data "{\"customerId\":\"${customer_id}\",\"items\":[{\"productId\":\"serverless-proof\",\"quantity\":1,\"unitPrice\":1.00}]}" \
  "${gateway_url}/api/orders")"
order_id="$(jq -er '.orderId' <<<"${create_response}")"
printf 'Waiting for serverless activity projection for order %s\n' "${order_id}"

curl --fail-with-body --silent --show-error \
  --request PUT \
  "${gateway_url}/api/orders/${order_id}/cancellation" >/dev/null

response_file="$(mktemp)"
error_file="$(mktemp)"
trap 'rm -f "${response_file}" "${error_file}"' EXIT
last_http_status=""
last_activity=""
last_curl_error=""

for _ in {1..120}; do
  : >"${response_file}"
  : >"${error_file}"
  if http_status="$(curl --silent --show-error \
      --output "${response_file}" \
      --write-out '%{http_code}' \
      "${gateway_url}/serverless/api/activity/${order_id}" 2>"${error_file}")"; then
    last_http_status="${http_status}"
    last_activity="$(cat "${response_file}")"
    last_curl_error=""
    if [[ "${http_status}" == "200" ]] &&
        jq -e '
          length == 2 and
          .[0].eventType == "OrderCreated.v1" and
          .[0].aggregateVersion == 1 and
          .[1].eventType == "OrderCancelled.v1" and
          .[1].aggregateVersion == 2
        ' <<<"${last_activity}" >/dev/null 2>&1; then
      printf 'Serverless Kafka-to-Cosmos activity projection verified for order %s\n' "${order_id}"
      exit 0
    fi
  else
    last_http_status="curl-error"
    last_activity="$(cat "${response_file}")"
    last_curl_error="$(cat "${error_file}")"
  fi
  sleep 1
done

printf 'Serverless activity projection did not converge within 120 seconds for order %s\n' "${order_id}" >&2
printf 'Last activity endpoint status: %s\n' "${last_http_status:-unknown}" >&2
if [[ -n "${last_activity}" ]]; then
  printf 'Last activity endpoint body: %s\n' "${last_activity}" >&2
fi
if [[ -n "${last_curl_error}" ]]; then
  printf 'Last activity endpoint curl error: %s\n' "${last_curl_error}" >&2
fi
exit 1
