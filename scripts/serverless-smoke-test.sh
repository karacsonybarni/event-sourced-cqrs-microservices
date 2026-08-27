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

curl --fail-with-body --silent --show-error \
  --request PUT \
  "${gateway_url}/api/orders/${order_id}/cancellation" >/dev/null

for _ in {1..120}; do
  if activity="$(curl --fail-with-body --silent --show-error \
      "${gateway_url}/serverless/api/activity/${order_id}" 2>/dev/null)" &&
      jq -e '
        length == 2 and
        .[0].eventType == "OrderCreated.v1" and
        .[0].aggregateVersion == 1 and
        .[1].eventType == "OrderCancelled.v1" and
        .[1].aggregateVersion == 2
      ' <<<"${activity}" >/dev/null; then
    printf 'Serverless Kafka-to-Cosmos activity projection verified for order %s\n' "${order_id}"
    exit 0
  fi
  sleep 1
done

echo "Serverless activity projection did not converge within 120 seconds" >&2
exit 1
