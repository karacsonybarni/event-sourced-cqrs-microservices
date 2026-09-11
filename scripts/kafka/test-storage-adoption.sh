#!/usr/bin/env bash
set -Eeuo pipefail
repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${repository_root}"
project="cqrs-adoption-test-$$"
export KAFKA_STORAGE_VOLUME="${project}-data"
compose=(docker compose --project-name "${project}" --file scripts/kafka/legacy-compose.yml)
adopted_compose=(docker compose --project-name "${project}-adopted" --file scripts/kafka/adopted-compose.yml)
cleanup() {
  "${adopted_compose[@]}" down >/dev/null 2>&1 || true
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

# Reproduce an already-adopted volume whose files have regressed to root
# ownership. Identity checks must run before repair mutates any ownership.
"${adopted_compose[@]}" create kafka >/dev/null
adopted_container="$("${adopted_compose[@]}" ps --all --quiet kafka)"
docker run --rm --user root --volume "${KAFKA_STORAGE_VOLUME}:/data" apache/kafka:4.3.1 \
  bash -ec 'chown -R root:root /data; sed -i "s/^node.id=.*/node.id=2/" /data/meta.properties'
if bash scripts/kafka/prepare-storage.sh \
    --project-name "${project}-adopted" --file scripts/kafka/adopted-compose.yml; then
  echo 'Storage repair accepted the wrong Kafka node identity' >&2
  exit 1
fi
docker run --rm --user root --volume "${KAFKA_STORAGE_VOLUME}:/data:ro" apache/kafka:4.3.1 \
  bash -ec 'test -z "$(find /data \( ! -user 0 -o ! -group 0 \) -print -quit)"'

docker run --rm --user root --volume "${KAFKA_STORAGE_VOLUME}:/data" apache/kafka:4.3.1 \
  bash -ec 'sed -i "s/^node.id=.*/node.id=1/" /data/meta.properties; chown -R root:root /data'
if EXPECTED_KAFKA_CLUSTER_ID=definitely-not-this-cluster \
    bash scripts/kafka/prepare-storage.sh \
      --project-name "${project}-adopted" --file scripts/kafka/adopted-compose.yml; then
  echo 'Storage repair accepted the wrong Kafka cluster identity' >&2
  exit 1
fi
docker run --rm --user root --volume "${KAFKA_STORAGE_VOLUME}:/data:ro" apache/kafka:4.3.1 \
  bash -ec 'test -z "$(find /data \( ! -user 0 -o ! -group 0 \) -print -quit)"'

bash scripts/kafka/prepare-storage.sh \
  --project-name "${project}-adopted" --file scripts/kafka/adopted-compose.yml

# Exercise the production broker entrypoint against the repaired volume. A
# metadata-only comparison cannot detect ownership that prevents Kafka writes.
"${adopted_compose[@]}" up --detach kafka >/dev/null

for _ in {1..60}; do
  if docker exec "${adopted_container}" /opt/kafka/bin/kafka-topics.sh \
      --bootstrap-server localhost:9092 --list >/dev/null 2>&1; then
    break
  fi
  if [[ "$(docker inspect --format '{{.State.Running}}' "${adopted_container}")" != true ]]; then
    docker logs "${adopted_container}" >&2
    exit 1
  fi
  sleep 2
done
docker exec "${adopted_container}" /opt/kafka/bin/kafka-topics.sh \
  --bootstrap-server localhost:9092 --list | grep -Fx adoption-marker
docker exec "${adopted_container}" /opt/kafka/bin/kafka-console-consumer.sh \
  --bootstrap-server localhost:9092 --topic adoption-marker --partition 0 --from-beginning \
  --max-messages 1 --timeout-ms 30000 | grep -Fx preserved-before-storage-adoption

printf 'written-after-ownership-repair\n' | docker exec -i "${adopted_container}" \
  /opt/kafka/bin/kafka-console-producer.sh --bootstrap-server localhost:9092 --topic adoption-marker
docker exec "${adopted_container}" /opt/kafka/bin/kafka-console-consumer.sh \
  --bootstrap-server localhost:9092 --topic adoption-marker --partition 0 --from-beginning \
  --max-messages 2 --timeout-ms 30000 | grep -Fx written-after-ownership-repair

echo 'Legacy Kafka storage adoption preserved data, safely repaired ownership, and accepted new writes'
