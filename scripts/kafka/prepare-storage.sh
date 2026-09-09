#!/usr/bin/env bash
set -Eeuo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${repository_root}"

compose=(docker compose "$@")
readonly kafka_image=apache/kafka:4.3.1
readonly stable_volume=${KAFKA_STORAGE_VOLUME:-cqrs-orders-kafka-1-data}
readonly expected_cluster_id=${EXPECTED_KAFKA_CLUSTER_ID:-}

kafka_container="$("${compose[@]}" ps --all --quiet kafka 2>/dev/null || true)"
if [[ -z "${kafka_container}" ]]; then
  echo "No existing Kafka container found; fresh dynamic-cluster bootstrap will create stable storage."
  exit 0
fi

mounted_volume="$(docker inspect --format '{{range .Mounts}}{{if eq .Destination "/var/lib/kafka/data"}}{{.Name}}{{end}}{{end}}' "${kafka_container}")"
if [[ "${mounted_volume}" == "${stable_volume}" ]]; then
  stable_cluster_id="$(
    docker run --rm --user root --volume "${stable_volume}:/target:ro" "${kafka_image}" \
      bash -ec 'test -f /target/meta.properties; awk -F= '\''$1 == "cluster.id" { print $2 }'\'' /target/meta.properties'
  )"
  if [[ -z "${stable_cluster_id}" ]]; then
    echo "Stable Kafka volume ${stable_volume} has no cluster identity" >&2
    exit 1
  fi
  if [[ -n "${expected_cluster_id}" && "${stable_cluster_id}" != "${expected_cluster_id}" ]]; then
    echo "Stable Kafka volume belongs to ${stable_cluster_id}, expected ${expected_cluster_id}" >&2
    exit 1
  fi
  echo "Kafka node 1 already uses stable volume ${stable_volume} for cluster ${stable_cluster_id}."
  exit 0
fi

staging_directory="$(mktemp -d)"
kafka_was_running="$(docker inspect --format '{{.State.Running}}' "${kafka_container}")"
connect_container="$("${compose[@]}" ps --all --quiet debezium 2>/dev/null || true)"
connect_was_running=false
if [[ -n "${connect_container}" ]]; then
  connect_was_running="$(docker inspect --format '{{.State.Running}}' "${connect_container}")"
fi
migration_complete=false
cleanup() {
  exit_status=$?
  trap - EXIT
  set +e
  rm -rf "${staging_directory}"

  if [[ "${migration_complete}" != "true" ]]; then
    echo "Kafka storage adoption did not complete; restoring the original container state." >&2
    if [[ "${kafka_was_running}" == "true" ]]; then
      docker start "${kafka_container}" >/dev/null
      kafka_restored=false
      for _ in {1..60}; do
        if docker exec "${kafka_container}" /opt/kafka/bin/kafka-topics.sh \
            --bootstrap-server localhost:9092 --list >/dev/null 2>&1; then
          kafka_restored=true
          break
        fi
        sleep 2
      done
      if [[ "${kafka_restored}" != "true" ]]; then
        echo "Original Kafka container did not return to readiness within two minutes." >&2
      fi
    else
      docker stop --time 60 "${kafka_container}" >/dev/null 2>&1 || true
    fi
    if [[ "${connect_was_running}" == "true" ]]; then
      docker start "${connect_container}" >/dev/null
    fi
  fi
  exit "${exit_status}"
}
trap cleanup EXIT

if [[ "${kafka_was_running}" != "true" ]]; then
  docker start "${kafka_container}" >/dev/null
fi

for _ in {1..60}; do
  if docker exec "${kafka_container}" /opt/kafka/bin/kafka-topics.sh \
      --bootstrap-server localhost:9092 --list >/dev/null 2>&1; then
    break
  fi
  sleep 2
done
docker exec "${kafka_container}" /opt/kafka/bin/kafka-topics.sh \
  --bootstrap-server localhost:9092 --list >/dev/null

live_cluster_description="$(
  docker exec "${kafka_container}" /opt/kafka/bin/kafka-cluster.sh \
    cluster-id --bootstrap-server localhost:9092
)"
live_cluster_id="$(awk -F': ' '/Cluster ID:/ { print $2 }' <<<"${live_cluster_description}")"
if [[ -z "${live_cluster_id}" ]]; then
  echo "Could not read the live Kafka cluster ID" >&2
  exit 1
fi
if [[ -n "${expected_cluster_id}" && "${live_cluster_id}" != "${expected_cluster_id}" ]]; then
  echo "Refusing migration: live cluster ID ${live_cluster_id} differs from expected ${expected_cluster_id}" >&2
  exit 1
fi

# The image-generated properties can omit log.dirs and use Kafka's default.
# Ask the live broker rather than guessing a path from a template or defaults.
log_directories="$(
  docker exec "${kafka_container}" /opt/kafka/bin/kafka-log-dirs.sh \
    --bootstrap-server localhost:9092 --broker-list 1 --describe |
    bash "${repository_root}/scripts/kafka/read-log-directory.sh"
)"

feature_description="$(
  docker exec "${kafka_container}" /opt/kafka/bin/kafka-features.sh \
    --bootstrap-server localhost:9092 describe
)"
if grep -Eq 'Feature: kraft.version.*FinalizedVersionLevel: 0' <<<"${feature_description}"; then
  docker exec "${kafka_container}" /opt/kafka/bin/kafka-features.sh \
    --bootstrap-server localhost:9092 \
    upgrade \
    --feature kraft.version=1
  feature_description="$(
    docker exec "${kafka_container}" /opt/kafka/bin/kafka-features.sh \
      --bootstrap-server localhost:9092 describe
  )"
fi
if ! grep -Eq 'Feature: kraft.version[[:space:]]+SupportedMinVersion:.*FinalizedVersionLevel: 1' \
    <<<"${feature_description}"; then
  echo "Kafka kraft.version did not finalize at level 1" >&2
  echo "${feature_description}" >&2
  exit 1
fi

if [[ "${connect_was_running}" == "true" ]]; then
  docker stop --time 60 "${connect_container}" >/dev/null
fi
docker stop --time 60 "${kafka_container}" >/dev/null

# Copy the directory itself into a new child so its owner/mode are retained;
# copying only its contents would keep mktemp's root-owned 0700 directory.
docker cp --archive "${kafka_container}:${log_directories}" "${staging_directory}/data" >/dev/null
if [[ ! -f "${staging_directory}/data/meta.properties" ]]; then
  echo "Kafka log copy has no meta.properties" >&2
  exit 1
fi
source_cluster_id="$(awk -F= '$1 == "cluster.id" { print $2 }' "${staging_directory}/data/meta.properties")"
source_node_id="$(awk -F= '$1 == "node.id" { print $2 }' "${staging_directory}/data/meta.properties")"
if [[ -z "${source_cluster_id}" || "${source_node_id}" != "1" ]]; then
  echo "Kafka log copy has invalid cluster/node identity" >&2
  exit 1
fi
if [[ "${source_cluster_id}" != "${live_cluster_id}" ]]; then
  echo "Kafka log copy cluster ID differs from the live cluster ID" >&2
  exit 1
fi

if ! docker volume inspect "${stable_volume}" >/dev/null 2>&1; then
  docker volume create \
    --label com.docker.compose.project=cqrs-orders \
    --label com.docker.compose.volume=kafka-1-data \
    "${stable_volume}" >/dev/null
fi

target_has_data="$(
  docker run --rm --user root --volume "${stable_volume}:/target" "${kafka_image}" \
    bash -ec 'find /target -mindepth 1 -print -quit'
)"
if [[ -n "${target_has_data}" ]]; then
  target_cluster_id="$(
    docker run --rm --user root --volume "${stable_volume}:/target:ro" "${kafka_image}" \
      bash -ec 'test -f /target/meta.properties; awk -F= '\''$1 == "cluster.id" { print $2 }'\'' /target/meta.properties'
  )"
  if [[ "${target_cluster_id}" != "${source_cluster_id}" ]]; then
    echo "Refusing to overwrite non-empty ${stable_volume}; cluster IDs differ" >&2
    exit 1
  fi
else
  docker run --rm --user root \
    --volume "${staging_directory}/data:/source:ro" \
    --volume "${stable_volume}:/target" \
    "${kafka_image}" \
    bash -ec 'cp -a /source/. /target/'
fi

docker run --rm --user root \
  --volume "${staging_directory}/data:/source:ro" \
  --volume "${stable_volume}:/target:ro" \
  "${kafka_image}" \
  bash -ec '
    set -o pipefail
    diff -qr /source /target
    # The Kafka image has BusyBox find (no -printf). Materialize manifests
    # so a failed traversal cannot be hidden by process substitution.
    # Directory allocation sizes differ across filesystems; diff above checks
    # file content, while these manifests check types, permissions and owners.
    (cd /source && find . -exec stat -c "%n %F %a %u %g" {} + | sort) > /tmp/source-manifest
    (cd /target && find . -exec stat -c "%n %F %a %u %g" {} + | sort) > /tmp/target-manifest
    diff /tmp/source-manifest /tmp/target-manifest
  '

migration_complete=true
echo "Kafka cluster ${source_cluster_id} was copied from ${log_directories} to stable volume ${stable_volume}."
echo "The old stopped container remains available until the next Compose reconciliation."
