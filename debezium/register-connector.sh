#!/usr/bin/env sh
set -eu

connect_url="http://debezium:8083"
connector_name="order-events"

curl --fail --silent --show-error \
  --request PUT \
  --header 'Content-Type: application/json' \
  --data @/config/order-events-connector.json \
  "${connect_url}/connectors/${connector_name}/config" >/dev/null

attempt=1
while [ "${attempt}" -le 30 ]; do
  status="$(curl --fail --silent \
    "${connect_url}/connectors/${connector_name}/status" 2>/dev/null || true)"
  running_count="$(printf '%s' "${status}" | grep -o '"state":"RUNNING"' | wc -l | tr -d ' ')"
  if [ "${running_count}" -ge 2 ]; then
    printf 'Debezium connector %s is running\n' "${connector_name}"
    exit 0
  fi
  attempt=$((attempt + 1))
  sleep 2
done

printf 'Debezium connector %s did not reach RUNNING state\n' "${connector_name}" >&2
exit 1
