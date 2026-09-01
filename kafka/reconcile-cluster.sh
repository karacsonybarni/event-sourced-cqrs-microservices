#!/usr/bin/env bash
set -euo pipefail

readonly KAFKA_HOME=${KAFKA_HOME:-/opt/kafka}
readonly BOOTSTRAP_SERVERS=${BOOTSTRAP_SERVERS:-kafka:9092,kafka-2:9092,kafka-3:9092}
readonly REASSIGNMENT_FILE=/tmp/kafka-reassignment.json
readonly TOPICS_FILE=/tmp/kafka-topics-to-move.json
readonly PROBE_TOPIC=cluster.reconciliation.probe

declare -A topic_partitions=(
  [orders.events.v1]=3
  [orders.events.v1.inventory.DLT]=3
  [inventory.events.v1]=3
  [inventory.events.v1.orders.DLT]=3
  [orders.events.v1.DLT]=3
  [orders.events.v1.activity.DLT]=3
  [orders.connect.configs]=1
  [orders.connect.offsets]=25
  [orders.connect.statuses]=5
)

declare -A topic_cleanup_policy=(
  [orders.connect.configs]=compact
  [orders.connect.offsets]=compact
  [orders.connect.statuses]=compact
)

for topic in "${!topic_partitions[@]}"; do
  create_args=(
    --bootstrap-server "${BOOTSTRAP_SERVERS}"
    --create
    --if-not-exists
    --topic "${topic}"
    --partitions "${topic_partitions[${topic}]}"
    --replication-factor 3
  )
  if [[ -n "${topic_cleanup_policy[${topic}]:-}" ]]; then
    create_args+=(--config "cleanup.policy=${topic_cleanup_policy[${topic}]}" )
  fi
  "${KAFKA_HOME}/bin/kafka-topics.sh" "${create_args[@]}"
done

"${KAFKA_HOME}/bin/kafka-topics.sh" \
  --bootstrap-server "${BOOTSTRAP_SERVERS}" \
  --create \
  --if-not-exists \
  --topic "${PROBE_TOPIC}" \
  --partitions 1 \
  --replication-factor 3

"${KAFKA_HOME}/bin/kafka-producer-perf-test.sh" \
  --topic "${PROBE_TOPIC}" \
  --num-records 1 \
  --record-size 16 \
  --throughput -1 \
  --transaction-duration-ms 1000 \
  --producer-props \
    "bootstrap.servers=${BOOTSTRAP_SERVERS}" \
    acks=all \
    enable.idempotence=true \
    transactional.id=cluster-reconciliation-producer >/dev/null

"${KAFKA_HOME}/bin/kafka-console-consumer.sh" \
  --bootstrap-server "${BOOTSTRAP_SERVERS}" \
  --topic "${PROBE_TOPIC}" \
  --group cluster-reconciliation-consumer \
  --from-beginning \
  --max-messages 1 \
  --timeout-ms 30000 >/dev/null

for internal_topic in __consumer_offsets __transaction_state; do
  internal_topic_ready=false
  for _ in {1..60}; do
    if "${KAFKA_HOME}/bin/kafka-topics.sh" \
        --bootstrap-server "${BOOTSTRAP_SERVERS}" \
        --topic "${internal_topic}" \
        --describe >/dev/null 2>&1; then
      internal_topic_ready=true
      break
    fi
    sleep 2
  done
  if [[ "${internal_topic_ready}" != "true" ]]; then
    echo "${internal_topic} was not created within the bounded wait" >&2
    exit 1
  fi
done

all_topics=("${!topic_partitions[@]}" __consumer_offsets __transaction_state)
needs_reassignment=false
for topic in "${all_topics[@]}"; do
  description=$(
    "${KAFKA_HOME}/bin/kafka-topics.sh" \
      --bootstrap-server "${BOOTSTRAP_SERVERS}" \
      --topic "${topic}" \
      --describe | head -n 1
  )
  replication_factor=$(sed -n 's/.*ReplicationFactor: \([0-9][0-9]*\).*/\1/p' <<<"${description}")
  if [[ "${replication_factor}" != "3" ]]; then
    needs_reassignment=true
  fi
done

if [[ "${needs_reassignment}" == "true" ]]; then
  {
    printf '{"topics":['
    separator=
    for topic in "${all_topics[@]}"; do
      printf '%s{"topic":"%s"}' "${separator}" "${topic}"
      separator=,
    done
    printf '],"version":1}\n'
  } >"${TOPICS_FILE}"

  generation=$(
    "${KAFKA_HOME}/bin/kafka-reassign-partitions.sh" \
      --bootstrap-server "${BOOTSTRAP_SERVERS}" \
      --broker-list 1,2,3 \
      --topics-to-move-json-file "${TOPICS_FILE}" \
      --generate
  )
  awk '/Proposed partition reassignment configuration/ { getline; print; exit }' \
    <<<"${generation}" >"${REASSIGNMENT_FILE}"
  if ! grep -q '"partitions"' "${REASSIGNMENT_FILE}"; then
    echo "Kafka did not generate a proposed partition reassignment" >&2
    echo "${generation}" >&2
    exit 1
  fi

  "${KAFKA_HOME}/bin/kafka-reassign-partitions.sh" \
    --bootstrap-server "${BOOTSTRAP_SERVERS}" \
    --reassignment-json-file "${REASSIGNMENT_FILE}" \
    --execute

  reassignment_complete=false
  for _ in {1..200}; do
    verification=$(
      "${KAFKA_HOME}/bin/kafka-reassign-partitions.sh" \
        --bootstrap-server "${BOOTSTRAP_SERVERS}" \
        --reassignment-json-file "${REASSIGNMENT_FILE}" \
        --verify
    )
    if grep -q 'completed successfully' <<<"${verification}" && \
        ! grep -q 'is still in progress' <<<"${verification}"; then
      reassignment_complete=true
      break
    fi
    sleep 3
  done
  if [[ "${reassignment_complete}" != "true" ]]; then
    echo "Kafka partition reassignment did not complete within 10 minutes" >&2
    echo "${verification}" >&2
    exit 1
  fi
fi

all_partitions_have_isr_three() {
  local topic
  local description
  local partition_line
  local isr
  for topic in "${all_topics[@]}"; do
    description=$(
      "${KAFKA_HOME}/bin/kafka-topics.sh" \
        --bootstrap-server "${BOOTSTRAP_SERVERS}" \
        --topic "${topic}" \
        --describe
    )
    while IFS= read -r partition_line; do
      isr=$(sed -n 's/.*Isr: \([^[:space:]]*\).*/\1/p' <<<"${partition_line}")
      if [[ $(tr ',' '\n' <<<"${isr}" | sed '/^$/d' | wc -l) -ne 3 ]]; then
        return 1
      fi
    done < <(tail -n +2 <<<"${description}")
  done
}

isr_ready=false
for _ in {1..200}; do
  if all_partitions_have_isr_three; then
    isr_ready=true
    break
  fi
  sleep 3
done
if [[ "${isr_ready}" != "true" ]]; then
  echo "Not every governed Kafka partition reached ISR 3 within 10 minutes" >&2
  exit 1
fi

for topic in "${all_topics[@]}"; do
  "${KAFKA_HOME}/bin/kafka-configs.sh" \
    --bootstrap-server "${BOOTSTRAP_SERVERS}" \
    --entity-type topics \
    --entity-name "${topic}" \
    --alter \
    --add-config min.insync.replicas=2
done

"${KAFKA_HOME}/bin/kafka-topics.sh" \
  --bootstrap-server "${BOOTSTRAP_SERVERS}" \
  --delete \
  --topic "${PROBE_TOPIC}"

env BOOTSTRAP_SERVERS="${BOOTSTRAP_SERVERS}" \
  "$(dirname "$0")/verify-cluster.sh"
