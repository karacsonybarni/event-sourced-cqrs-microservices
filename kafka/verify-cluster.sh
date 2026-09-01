#!/usr/bin/env bash
set -euo pipefail

readonly KAFKA_HOME=${KAFKA_HOME:-/opt/kafka}
readonly BOOTSTRAP_SERVERS=${BOOTSTRAP_SERVERS:-kafka:9092,kafka-2:9092,kafka-3:9092}
readonly CONTROLLER_BOOTSTRAP_SERVERS=${CONTROLLER_BOOTSTRAP_SERVERS:-kafka:9093,kafka-2:9093,kafka-3:9093}

declare -A expected_partitions=(
  [orders.events.v1]=3
  [orders.events.v1.inventory.DLT]=3
  [inventory.events.v1]=3
  [inventory.events.v1.orders.DLT]=3
  [orders.events.v1.DLT]=3
  [orders.events.v1.activity.DLT]=3
  [orders.connect.configs]=1
  [orders.connect.offsets]=25
  [orders.connect.statuses]=5
  [__consumer_offsets]=50
  [__transaction_state]=50
)

quorum=$(
  "${KAFKA_HOME}/bin/kafka-metadata-quorum.sh" \
    --bootstrap-controller "${CONTROLLER_BOOTSTRAP_SERVERS}" \
    describe --replication
)
voters=$(awk 'NR > 1 && ($7 == "Leader" || $7 == "Follower") { print $1 }' <<<"${quorum}" | sort -n | xargs)
if [[ "${voters}" != "1 2 3" ]]; then
  echo "Expected KRaft voters 1 2 3, found: ${voters:-none}" >&2
  echo "${quorum}" >&2
  exit 1
fi

for topic in "${!expected_partitions[@]}"; do
  description=$(
    "${KAFKA_HOME}/bin/kafka-topics.sh" \
      --bootstrap-server "${BOOTSTRAP_SERVERS}" \
      --describe \
      --topic "${topic}"
  )
  summary=$(head -n 1 <<<"${description}")
  partition_count=$(sed -n 's/.*PartitionCount: \([0-9][0-9]*\).*/\1/p' <<<"${summary}")
  replication_factor=$(sed -n 's/.*ReplicationFactor: \([0-9][0-9]*\).*/\1/p' <<<"${summary}")

  if [[ "${partition_count}" != "${expected_partitions[${topic}]}" ]]; then
    echo "${topic}: expected ${expected_partitions[${topic}]} partitions, found ${partition_count}" >&2
    exit 1
  fi
  if [[ "${replication_factor}" != "3" ]]; then
    echo "${topic}: expected replication factor 3, found ${replication_factor}" >&2
    exit 1
  fi

  while IFS= read -r partition_line; do
    replicas=$(sed -n 's/.*Replicas: \([^[:space:]]*\).*/\1/p' <<<"${partition_line}")
    isr=$(sed -n 's/.*Isr: \([^[:space:]]*\).*/\1/p' <<<"${partition_line}")
    if [[ $(tr ',' '\n' <<<"${replicas}" | sed '/^$/d' | wc -l) -ne 3 ]]; then
      echo "${topic}: partition has replicas ${replicas}, expected three" >&2
      exit 1
    fi
    if [[ $(tr ',' '\n' <<<"${isr}" | sed '/^$/d' | wc -l) -ne 3 ]]; then
      echo "${topic}: partition ISR is ${isr}, expected all three brokers" >&2
      exit 1
    fi
  done < <(tail -n +2 <<<"${description}")

  configs=$(
    "${KAFKA_HOME}/bin/kafka-configs.sh" \
      --bootstrap-server "${BOOTSTRAP_SERVERS}" \
      --entity-type topics \
      --entity-name "${topic}" \
      --describe
  )
  if ! grep -q 'min.insync.replicas=2' <<<"${configs}"; then
    echo "${topic}: min.insync.replicas is not explicitly 2" >&2
    exit 1
  fi
done

echo "Kafka dynamic quorum, replication factor, and ISR verification passed"
