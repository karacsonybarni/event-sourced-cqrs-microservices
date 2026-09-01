#!/usr/bin/env bash
set -Eeuo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${repository_root}"

compose=(docker compose "$@")
readonly bootstrap_servers=kafka:9092,kafka-2:9092,kafka-3:9092
leader_service=""
leader_stopped=false

service_for_node() {
  case "$1" in
    1) printf 'kafka\n' ;;
    2) printf 'kafka-2\n' ;;
    3) printf 'kafka-3\n' ;;
    *) echo "Unknown Kafka node ID: $1" >&2; return 1 ;;
  esac
}

restore_leader() {
  if [[ "${leader_stopped}" == "true" ]]; then
    echo "Restoring ${leader_service}"
    "${compose[@]}" start "${leader_service}" >/dev/null
    leader_stopped=false
  fi
}
trap 'restore_leader || true' EXIT

"${compose[@]}" exec --no-TTY kafka \
  env BOOTSTRAP_SERVERS="${bootstrap_servers}" \
  /workspace/kafka/verify-cluster.sh

partition_description="$(
  "${compose[@]}" exec --no-TTY kafka \
    /opt/kafka/bin/kafka-topics.sh \
      --bootstrap-server "${bootstrap_servers}" \
      --describe \
      --topic orders.events.v1 |
    awk '$0 ~ /Partition: 0([[:space:]]|$)/ { print; exit }'
)"
leader_node="$(sed -n 's/.*Leader: \([0-9][0-9]*\).*/\1/p' <<<"${partition_description}")"
leader_service="$(service_for_node "${leader_node}")"

case "${leader_node}" in
  1) observer_service=kafka-2 ;;
  2|3) observer_service=kafka ;;
esac

echo "Stopping current orders.events.v1 partition 0 leader: node ${leader_node} (${leader_service})"
"${compose[@]}" stop --timeout 60 "${leader_service}"
leader_stopped=true

replacement_ready=false
for _ in {1..60}; do
  description="$(
    "${compose[@]}" exec --no-TTY "${observer_service}" \
      /opt/kafka/bin/kafka-topics.sh \
        --bootstrap-server "${bootstrap_servers}" \
        --describe \
        --topic orders.events.v1 2>/dev/null |
      awk '$0 ~ /Partition: 0([[:space:]]|$)/ { print; exit }' || true
  )"
  replacement_leader="$(sed -n 's/.*Leader: \([0-9][0-9]*\).*/\1/p' <<<"${description}")"
  isr="$(sed -n 's/.*Isr: \([^[:space:]]*\).*/\1/p' <<<"${description}")"
  isr_count="$(tr ',' '\n' <<<"${isr}" | sed '/^$/d' | wc -l)"
  if [[ -n "${replacement_leader}" && "${replacement_leader}" != "${leader_node}" && "${isr_count}" -eq 2 ]]; then
    replacement_ready=true
    break
  fi
  sleep 2
done
if [[ "${replacement_ready}" != "true" ]]; then
  echo "Partition 0 did not elect a replacement leader with ISR 2" >&2
  exit 1
fi

./scripts/smoke-test.sh

restore_leader

verified=false
for _ in {1..90}; do
  if "${compose[@]}" exec --no-TTY "${observer_service}" \
      env BOOTSTRAP_SERVERS="${bootstrap_servers}" \
      /workspace/kafka/verify-cluster.sh >/dev/null 2>&1; then
    verified=true
    break
  fi
  sleep 2
done
if [[ "${verified}" != "true" ]]; then
  echo "Restored broker did not rejoin every target ISR" >&2
  exit 1
fi

echo "Kafka broker failover passed: saga/query traffic survived node ${leader_node}, and ISR returned to 3."
