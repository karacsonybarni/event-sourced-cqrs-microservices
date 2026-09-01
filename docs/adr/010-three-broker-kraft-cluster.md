# ADR-010: Run a three-node KRaft cluster for broker failover

- Status: Accepted
- Date: 2026-09-01

## Context

The event backbone must remain available when one Kafka process stops, and the demo needs an observable broker-failover exercise comparable to application-replica failover. The Azure runtime already contains a Kafka 4.3.1 KRaft cluster with one static controller/broker, retained events, Debezium Connect offsets, and application plus internal topics at replication factor 1. Recreating that broker from fresh storage would lose authoritative delivery state and can strand live saga messages.

The Azure target remains one two-vCPU/eight-GiB VM because a multi-host or managed Kafka deployment is outside the credit-protected budget. Three processes on that VM can demonstrate Kafka replication and election but cannot protect against VM, disk, or host-network failure.

## Decision

Run one logical Kafka 4.3.1 cluster with three stable nodes. Each demo node has combined broker/controller roles, a named data volume, a 192 MiB initial/320 MiB maximum heap, and a 640 MiB container limit. Internal clients bootstrap from all three service-DNS endpoints; local host clients use ports 19092, 29092, and 39092; Azure K3s and Function clients use VM-private ports 9094, 9095, and 9096. Listener metadata advertises addresses reachable from the listener's client network.

Migrate Azure state with Kafka's supported static-to-dynamic quorum procedure. Finalize `kraft.version=1` on the running static quorum, stop Connect and Kafka, copy and verify the effective log directory in a stable node-1 volume, then restart node 1 with `controller.quorum.bootstrap.servers`. Format nodes 2 and 3 with the preserved cluster ID and `--no-initial-controllers`; add each controller only after it is an observer at lag zero.

The six application/DLT topics retain three partitions and use replication factor 3. Debezium Connect config, offset, and status topics and Kafka consumer-offset and transaction-state topics also use replication factor 3. Reassign existing RF1 partitions explicitly and require every governed partition to reach ISR 3 before applying `min.insync.replicas=2`. Spring and Debezium producers use `acks=all`.

The acceptance test stops the current leader of `orders.events.v1` partition 0, requires a replacement leader with ISR 2, executes the Order-Inventory saga through the independent projection worker and query service, restores the broker, and requires every governed partition to return to ISR 3.

## Consequences

- One broker process can stop while replicated topics continue reads and durable writes through the remaining ISR.
- Stable named volumes preserve broker metadata and logs across ordinary Compose shutdown and recreation.
- The initial migration has a controlled Kafka/Connect outage so the source log tree is copied from a consistent stopped broker. Identity, feature-level, copy, observer, reassignment, and ISR mismatches stop migration rather than resetting data.
- RF3 consumes approximately three times the retained Kafka log storage plus replication overhead. The migration deliberately retains the previous anonymous source volume for recovery, temporarily increasing the cutover footprint to roughly four log copies until a separately approved cleanup retires it.
- The three broker limits total 1.875 GiB. Compared with the former one-GiB broker limit, the 875 MiB cap increase fits inside the measured 2.76 GiB Azure headroom, but the VM has no swap and remains capacity constrained.
- Combined roles and same-host placement are demo compromises. A critical production deployment should separate broker and controller roles and distribute processes, storage, and network paths across independent failure domains.
