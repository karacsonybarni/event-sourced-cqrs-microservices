#!/usr/bin/env bash
set -euo pipefail

readonly KAFKA_HOME=${KAFKA_HOME:-/opt/kafka}
readonly BOOTSTRAP_SERVERS=${BOOTSTRAP_SERVERS:-kafka:9092,kafka-2:9092,kafka-3:9092}
readonly REASSIGNMENT_FILE=/tmp/kafka-reassignment.json
readonly PROBE_TOPIC=cluster.reconciliation.probe

readonly -a governed_topics=(
  orders.events.v1
  orders.events.v1.inventory.DLT
  inventory.events.v1
  inventory.events.v1.orders.DLT
  orders.events.v1.DLT
  orders.events.v1.activity.DLT
  orders.connect.configs
  orders.connect.offsets
  orders.connect.statuses
)
readonly -a internal_topics=(__consumer_offsets __transaction_state)

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

topic_description() {
  local topic="$1"
  "${KAFKA_HOME}/bin/kafka-topics.sh" \
    --bootstrap-server "${BOOTSTRAP_SERVERS}" \
    --topic "${topic}" \
    --describe
}

csv_count() {
  local value="$1"
  if [[ -z "${value}" ]]; then
    printf '0\n'
  else
    awk -F',' '{ print NF }' <<<"${value}"
  fi
}

write_reassignment_file() {
  local topic description summary replication_factor partition_line partition replicas
  local broker replica separator= partition_separator=
  local -a current_replicas assignment

  reassignment_needed=false
  printf '{"version":1,"partitions":['
  for topic in "$@"; do
    description="$(topic_description "${topic}")"
    summary="$(sed -n '1p' <<<"${description}")"
    replication_factor="$(sed -n 's/.*ReplicationFactor: \([0-9][0-9]*\).*/\1/p' <<<"${summary}")"
    if [[ -z "${replication_factor}" ]]; then
      echo "${topic}: replication factor was not returned" >&2
      return 1
    fi
    if [[ "${replication_factor}" != "3" ]]; then
      reassignment_needed=true
    fi

    while IFS= read -r partition_line; do
      [[ -n "${partition_line}" ]] || continue
      partition="$(sed -n 's/.*Partition: \([0-9][0-9]*\).*/\1/p' <<<"${partition_line}")"
      replicas="$(sed -n 's/.*Replicas: \([^[:space:]]*\).*/\1/p' <<<"${partition_line}")"
      if [[ -z "${partition}" || -z "${replicas}" ]]; then
        echo "${topic}: could not parse partition assignment: ${partition_line}" >&2
        return 1
      fi

      IFS=',' read -r -a current_replicas <<<"${replicas}"
      assignment=()
      for broker in "${current_replicas[@]}" 1 2 3; do
        case "${broker}" in
          1|2|3) ;;
          *)
            echo "${topic}: partition ${partition} uses unexpected broker ${broker}" >&2
            return 1
            ;;
        esac
        for replica in "${assignment[@]}"; do
          if [[ "${replica}" == "${broker}" ]]; then
            continue 2
          fi
        done
        assignment+=("${broker}")
      done
      if [[ "${#assignment[@]}" -ne 3 ]]; then
        echo "${topic}: partition ${partition} could not be assigned to three distinct brokers" >&2
        return 1
      fi

      printf '%s{"topic":"%s","partition":%s,"replicas":[' \
        "${partition_separator}" "${topic}" "${partition}"
      separator=
      for replica in "${assignment[@]}"; do
        printf '%s%s' "${separator}" "${replica}"
        separator=,
      done
      printf ']}'
      partition_separator=,
    done < <(sed -n '2,$p' <<<"${description}")
  done
  printf ']}\n'
}

reassign_topics_to_three() {
  local verification
  local -a topics=("$@")

  write_reassignment_file "${topics[@]}" >"${REASSIGNMENT_FILE}"
  if [[ "${reassignment_needed}" != "true" ]]; then
    return 0
  fi

  "${KAFKA_HOME}/bin/kafka-reassign-partitions.sh" \
    --bootstrap-server "${BOOTSTRAP_SERVERS}" \
    --reassignment-json-file "${REASSIGNMENT_FILE}" \
    --execute

  for _ in {1..200}; do
    verification=$(
      "${KAFKA_HOME}/bin/kafka-reassign-partitions.sh" \
        --bootstrap-server "${BOOTSTRAP_SERVERS}" \
        --reassignment-json-file "${REASSIGNMENT_FILE}" \
        --verify
    )
    if grep -q 'completed successfully' <<<"${verification}" && \
        ! grep -q 'is still in progress' <<<"${verification}"; then
      return 0
    fi
    sleep 3
  done

  echo "Kafka partition reassignment did not complete within 10 minutes" >&2
  echo "${verification}" >&2
  return 1
}

all_partitions_have_rf_and_isr_three() {
  local topic description summary replication_factor partition_line replicas isr
  for topic in "$@"; do
    if ! description="$(topic_description "${topic}" 2>/dev/null)"; then
      return 1
    fi
    summary="$(sed -n '1p' <<<"${description}")"
    replication_factor="$(sed -n 's/.*ReplicationFactor: \([0-9][0-9]*\).*/\1/p' <<<"${summary}")"
    [[ "${replication_factor}" == "3" ]] || return 1

    while IFS= read -r partition_line; do
      [[ -n "${partition_line}" ]] || continue
      replicas="$(sed -n 's/.*Replicas: \([^[:space:]]*\).*/\1/p' <<<"${partition_line}")"
      isr="$(sed -n 's/.*Isr: \([^[:space:]]*\).*/\1/p' <<<"${partition_line}")"
      if [[ "$(csv_count "${replicas}")" -ne 3 || "$(csv_count "${isr}")" -ne 3 ]]; then
        return 1
      fi
    done < <(sed -n '2,$p' <<<"${description}")
  done
}

wait_for_rf_and_isr_three() {
  local description="$1"
  shift
  for _ in {1..200}; do
    if all_partitions_have_rf_and_isr_three "$@"; then
      return 0
    fi
    sleep 3
  done
  echo "${description} did not reach replication factor and ISR 3 within 10 minutes" >&2
  return 1
}

wait_for_topic() {
  local topic="$1"
  for _ in {1..60}; do
    if topic_description "${topic}" >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
  done
  echo "${topic} was not created within the bounded wait" >&2
  return 1
}

for topic in "${governed_topics[@]}"; do
  create_args=(
    --bootstrap-server "${BOOTSTRAP_SERVERS}"
    --create
    --if-not-exists
    --topic "${topic}"
    --partitions "${topic_partitions[${topic}]}"
    --replication-factor 3
  )
  if [[ -n "${topic_cleanup_policy[${topic}]:-}" ]]; then
    create_args+=(--config "cleanup.policy=${topic_cleanup_policy[${topic}]}")
  fi
  "${KAFKA_HOME}/bin/kafka-topics.sh" "${create_args[@]}"
done

topic_listing=$(
  "${KAFKA_HOME}/bin/kafka-topics.sh" \
    --bootstrap-server "${BOOTSTRAP_SERVERS}" \
    --list
)
existing_internal_topics=()
for topic in "${internal_topics[@]}"; do
  if grep -Fxq "${topic}" <<<"${topic_listing}"; then
    existing_internal_topics+=("${topic}")
  fi
done

pre_probe_topics=("${governed_topics[@]}" "${existing_internal_topics[@]}")
reassign_topics_to_three "${pre_probe_topics[@]}"
wait_for_rf_and_isr_three \
  "Existing governed Kafka partitions" \
  "${pre_probe_topics[@]}"

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

for topic in "${internal_topics[@]}"; do
  wait_for_topic "${topic}"
done

all_topics=("${governed_topics[@]}" "${internal_topics[@]}")
reassign_topics_to_three "${all_topics[@]}"
wait_for_rf_and_isr_three \
  "All governed Kafka partitions" \
  "${all_topics[@]}"

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
