#!/usr/bin/env bash
set -euo pipefail

readonly KAFKA_HOME=/opt/kafka
readonly DATA_DIR=/var/lib/kafka/data
readonly SERVER_CONFIG=/tmp/kafka-server.properties
readonly READY_FILE=/tmp/kafka-controller-ready

: "${KAFKA_NODE_ID:?Set KAFKA_NODE_ID}"
: "${KAFKA_INTERNAL_HOST:?Set KAFKA_INTERNAL_HOST}"
: "${KAFKA_EXTERNAL_HOST:?Set KAFKA_EXTERNAL_HOST}"
: "${KAFKA_EXTERNAL_PORT:?Set KAFKA_EXTERNAL_PORT}"
: "${KAFKA_CONTROLLER_QUORUM_BOOTSTRAP_SERVERS:?Set KAFKA_CONTROLLER_QUORUM_BOOTSTRAP_SERVERS}"

rm -f "${READY_FILE}"

cat >"${SERVER_CONFIG}" <<EOF
node.id=${KAFKA_NODE_ID}
process.roles=broker,controller
listeners=CONTROLLER://${KAFKA_INTERNAL_HOST}:9093,INTERNAL://0.0.0.0:9092,EXTERNAL://0.0.0.0:9094
advertised.listeners=INTERNAL://${KAFKA_INTERNAL_HOST}:9092,EXTERNAL://${KAFKA_EXTERNAL_HOST}:${KAFKA_EXTERNAL_PORT}
controller.listener.names=CONTROLLER
listener.security.protocol.map=CONTROLLER:PLAINTEXT,INTERNAL:PLAINTEXT,EXTERNAL:PLAINTEXT
inter.broker.listener.name=INTERNAL
controller.quorum.bootstrap.servers=${KAFKA_CONTROLLER_QUORUM_BOOTSTRAP_SERVERS}
log.dirs=${DATA_DIR}
num.partitions=3
default.replication.factor=3
min.insync.replicas=2
offsets.topic.num.partitions=50
offsets.topic.replication.factor=3
offsets.topic.min.insync.replicas=2
transaction.state.log.num.partitions=50
transaction.state.log.replication.factor=3
transaction.state.log.min.isr=2
group.initial.rebalance.delay.ms=0
auto.create.topics.enable=false
unclean.leader.election.enable=false
EOF

cluster_id_from_meta() {
  awk -F= '$1 == "cluster.id" { print $2 }' "${DATA_DIR}/meta.properties"
}

cluster_id_from_broker() {
  local output
  for _ in {1..120}; do
    if output=$("${KAFKA_HOME}/bin/kafka-cluster.sh" cluster-id \
        --bootstrap-server kafka:9092 2>/dev/null); then
      awk -F': ' '/Cluster ID:/ { print $2 }' <<<"${output}"
      return 0
    fi
    sleep 2
  done
  echo "Timed out discovering the Kafka cluster ID" >&2
  return 1
}

if [[ -f "${DATA_DIR}/meta.properties" ]]; then
  existing_node_id=$(awk -F= '$1 == "node.id" { print $2 }' "${DATA_DIR}/meta.properties")
  if [[ "${existing_node_id}" != "${KAFKA_NODE_ID}" ]]; then
    echo "Kafka data belongs to node ${existing_node_id}, not configured node ${KAFKA_NODE_ID}" >&2
    exit 1
  fi
  cluster_id=$(cluster_id_from_meta)
  if [[ -z "${cluster_id}" ]]; then
    echo "Kafka meta.properties has no cluster.id" >&2
    exit 1
  fi
elif [[ "${KAFKA_NODE_ID}" == "1" ]]; then
  cluster_id=$("${KAFKA_HOME}/bin/kafka-storage.sh" random-uuid)
  "${KAFKA_HOME}/bin/kafka-storage.sh" format \
    --standalone \
    --cluster-id "${cluster_id}" \
    --config "${SERVER_CONFIG}"
else
  cluster_id=$(cluster_id_from_broker)
  if [[ -z "${cluster_id}" ]]; then
    echo "Could not discover the existing Kafka cluster ID" >&2
    exit 1
  fi
  "${KAFKA_HOME}/bin/kafka-storage.sh" format \
    --no-initial-controllers \
    --cluster-id "${cluster_id}" \
    --config "${SERVER_CONFIG}"
fi

"${KAFKA_HOME}/bin/kafka-server-start.sh" "${SERVER_CONFIG}" &
kafka_pid=$!

shutdown() {
  rm -f "${READY_FILE}"
  kill -TERM "${kafka_pid}" 2>/dev/null || true
  wait "${kafka_pid}" 2>/dev/null || true
}
trap shutdown TERM INT

broker_ready=false
for _ in {1..120}; do
  if "${KAFKA_HOME}/bin/kafka-topics.sh" \
      --bootstrap-server localhost:9092 --list >/dev/null 2>&1; then
    broker_ready=true
    break
  fi
  if ! kill -0 "${kafka_pid}" 2>/dev/null; then
    wait "${kafka_pid}"
  fi
  sleep 2
done
if [[ "${broker_ready}" != "true" ]]; then
  echo "Kafka node ${KAFKA_NODE_ID} did not become ready within four minutes" >&2
  exit 1
fi

quorum_replication() {
  "${KAFKA_HOME}/bin/kafka-metadata-quorum.sh" \
    --bootstrap-controller "${KAFKA_CONTROLLER_QUORUM_BOOTSTRAP_SERVERS}" \
    describe --replication
}

is_voter() {
  quorum_replication | awk -v node_id="${KAFKA_NODE_ID}" \
    'NR > 1 && $1 == node_id && ($7 == "Leader" || $7 == "Follower") { found = 1 } END { exit !found }'
}

if ! is_voter; then
  echo "Waiting for controller ${KAFKA_NODE_ID} to catch up as an observer"
  observer_ready=false
  for _ in {1..180}; do
    if quorum_replication | awk -v node_id="${KAFKA_NODE_ID}" \
        'NR > 1 && $1 == node_id && $4 == 0 && $7 == "Observer" { found = 1 } END { exit !found }'; then
      observer_ready=true
      break
    fi
    if ! kill -0 "${kafka_pid}" 2>/dev/null; then
      wait "${kafka_pid}"
    fi
    sleep 2
  done
  if [[ "${observer_ready}" != "true" ]]; then
    echo "Controller ${KAFKA_NODE_ID} did not reach observer lag zero within six minutes" >&2
    exit 1
  fi

  "${KAFKA_HOME}/bin/kafka-metadata-quorum.sh" \
    --bootstrap-controller "${KAFKA_CONTROLLER_QUORUM_BOOTSTRAP_SERVERS}" \
    --command-config "${SERVER_CONFIG}" \
    add-controller
fi

voter_ready=false
for _ in {1..120}; do
  if is_voter; then
    voter_ready=true
    break
  fi
  if ! kill -0 "${kafka_pid}" 2>/dev/null; then
    wait "${kafka_pid}"
  fi
  sleep 2
done
if [[ "${voter_ready}" != "true" ]]; then
  echo "Controller ${KAFKA_NODE_ID} did not become a voter within four minutes" >&2
  exit 1
fi

touch "${READY_FILE}"
wait "${kafka_pid}"
