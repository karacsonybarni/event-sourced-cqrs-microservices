#!/usr/bin/env bash
set -Eeuo pipefail
repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${repository_root}"
project="cqrs-adoption-test-$$"
export KAFKA_STORAGE_VOLUME="${project}-data"
compose=(docker compose --project-name "${project}" --file scripts/kafka/legacy-compose.yml)
cleanup() {
  "${compose[@]}" down --volumes >/dev/null
  docker volume rm "${KAFKA_STORAGE_VOLUME}" >/dev/null 2>&1 || true
}
trap cleanup EXIT
"${compose[@]}" up --detach
container="$("${compose[@]}" ps --quiet kafka)"
for _ in {1..60}; do
  if docker exec "${container}" /opt/kafka/bin/kafka-topics.sh --bootstrap-server localhost:9092 --list >/dev/null 2>&1; then
    break
  fi
  sleep 2
done
docker exec "${container}" /opt/kafka/bin/kafka-topics.sh --bootstrap-server localhost:9092 \
  --create --topic adoption-marker --partitions 1 --replication-factor 1
printf 'preserved-before-storage-adoption\n' | docker exec -i "${container}" \
  /opt/kafka/bin/kafka-console-producer.sh --bootstrap-server localhost:9092 --topic adoption-marker
# This fixture reproduces the cloud failure: the generated config omits log.dirs.
if docker exec "${container}" grep -q '^log.dirs=' /opt/kafka/config/server.properties; then
  echo 'Legacy fixture no longer reproduces omitted log.dirs' >&2
  exit 1
fi
bash scripts/kafka/prepare-storage.sh --project-name "${project}" --file scripts/kafka/legacy-compose.yml
[[ "$(docker inspect --format '{{.State.Running}}' "${container}")" == false ]]
# The adoption script compares every copied file and its metadata. Also verify
# that the copied topic segment contains the record, not merely meta.properties.
docker run --rm --volume "${KAFKA_STORAGE_VOLUME}:/data:ro" --entrypoint bash apache/kafka:4.3.1 \
  -ec '
    set -o pipefail
    test -f /data/meta.properties
    for segment in /data/adoption-marker-0/*.log; do
      /opt/kafka/bin/kafka-dump-log.sh --files "$segment" --print-data-log
    done | grep -F preserved-before-storage-adoption
  '
echo 'Legacy Kafka storage adoption preserved existing data'
