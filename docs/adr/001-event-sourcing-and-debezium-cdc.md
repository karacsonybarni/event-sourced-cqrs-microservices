# ADR-001: Use event sourcing and Debezium CDC for order propagation

- Status: Accepted
- Date: 2026-08-24

## Context

The system needs independently owned command and query models while retaining the complete history used to make order decisions. Publishing to Kafka from command code would add a second consistency boundary: a database commit could succeed while the broker write is lost, or the broker write could escape before a rollback.

## Decision

Store each order as an append-only event stream in the command service's PostgreSQL database. Reconstruct the aggregate by replaying `OrderCreated.v1` and `OrderCancelled.v1`. Keep a small stream-metadata row for expected-version checks, locking, and referential integrity; do not store mutable order state there.

Enforce immutability with a database trigger that rejects event updates and deletes. Enforce one event per stream position with a unique `(aggregate_id, aggregate_version)` constraint.

Use Debezium's PostgreSQL connector with `pgoutput` to capture committed inserts from the event table. Apply the Debezium Outbox Event Router transform directly to the authoritative event-store row, preserving the stored JSON envelope as the Kafka value and using the aggregate ID as the key. The command application has no Kafka producer dependency.

The query service consumes at least once, deduplicates by event ID, checks aggregate versions, and stores a denormalized read model in its own PostgreSQL database.

## Consequences

Positive:

- aggregate state is reproducible from an immutable business history;
- temporal debugging and audit trails do not depend on mutable snapshots;
- no application transaction spans PostgreSQL and Kafka;
- database commits remain fast and independent of broker availability;
- event inserts, CDC records, Kafka messages, and projections share one stable event ID;
- the query model can evolve and rebuild independently.

Negative:

- command reads replay history and may eventually require derived snapshots;
- event schemas become permanent compatibility commitments;
- logical replication slots and connector offsets require monitoring and recovery procedures;
- at-least-once delivery still requires every consumer to be idempotent;
- data correction uses compensating events instead of direct row updates;
- connector, Kafka, and projection lag make consistency explicitly eventual.

## Alternatives considered

- **Transactional outbox beside mutable aggregate tables:** solves the dual-write problem but duplicates business facts between current state and publication rows, and the aggregate cannot be reconstructed from its authoritative history.
- **Publish after database commit:** has an unrecoverable gap between the local commit and broker acknowledgement.
- **Application polling publisher:** avoids CDC infrastructure but adds polling, claiming, publication-state mutation, and relay code to the command service.
- **Event sourcing without CDC:** retains history but still needs a safe mechanism to propagate committed events across the service boundary.
- **Synchronous command-to-query call:** couples availability and still introduces a distributed write problem.
