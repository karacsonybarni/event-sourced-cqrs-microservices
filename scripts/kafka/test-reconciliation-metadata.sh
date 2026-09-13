#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
fixture=$(mktemp -d)
trap 'rm -rf "${fixture}"' EXIT
mkdir -p "${fixture}/bin"
export KAFKA_HOME="${fixture}" MOCK_RESPONSE="${fixture}/response" MOCK_CALLS="${fixture}/calls"
cat >"${fixture}/bin/kafka-topics.sh" <<'MOCK'
#!/usr/bin/env bash
set -eu
echo call >>"${MOCK_CALLS}"
[[ "${MOCK_FAIL:-false}" != true ]] || exit 1
cat "${MOCK_RESPONSE}"
MOCK
chmod +x "${fixture}/bin/kafka-topics.sh"
# shellcheck source=/dev/null
source "${root}/kafka/reconcile-cluster.sh"
reassignment_needed=true

write_fixture() {
  local rf="${1:-3}" isr="${2:-1,2,3}" second="${3:-orders.two}"
  printf 'Topic: orders.one PartitionCount: 1 ReplicationFactor: %s\n' "$rf"
  printf 'Topic: orders.one Partition: 0 Leader: 1 Replicas: 1,2,3 Isr: %s\n' "$isr"
  printf 'Topic: %s PartitionCount: 1 ReplicationFactor: 3\n' "$second"
  printf 'Topic: %s Partition: 0 Leader: 1 Replicas: 1,2,3 Isr: 1,2,3\n' "$second"
}
write_fixture >"${MOCK_RESPONSE}"
all_partitions_have_rf_and_isr_three orders.one orders.two
[[ $(wc -l <"${MOCK_CALLS}") == 1 ]]
write_reassignment_file orders.one orders.two >"${fixture}/assignment.json"
[[ $(wc -l <"${MOCK_CALLS}") == 2 ]]
[[ "${reassignment_needed}" == false ]]
jq -e '.partitions | length == 2' "${fixture}/assignment.json" >/dev/null

for args in '2 1,2,3 orders.two' '3 1,2 orders.two' '3 1,2,3 ordersXtwo'; do
  read -r rf isr second <<<"$args"
  write_fixture "$rf" "$isr" "$second" >"${MOCK_RESPONSE}"
  if all_partitions_have_rf_and_isr_three orders.one orders.two; then
    echo "Accepted invalid metadata: $args" >&2
    exit 1
  fi
done
write_fixture >"${MOCK_RESPONSE}"
all_partitions_have_rf_and_isr_three orders.one orders.two
if MOCK_FAIL=true all_partitions_have_rf_and_isr_three orders.one orders.two; then
  echo 'Accepted failed metadata request' >&2
  exit 1
fi
: >"${MOCK_RESPONSE}"
if all_partitions_have_rf_and_isr_three orders.one orders.two; then
  echo 'Accepted missing metadata' >&2
  exit 1
fi
echo 'Kafka batched metadata tests passed'
