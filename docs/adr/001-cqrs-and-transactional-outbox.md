# ADR-001: Split order commands and queries with an event-driven projection

- Status: Accepted
- Date: 2026-08-23

## Context

The showcase needs to demonstrate conventional microservice data ownership and the real consistency boundary created by CQRS. Publishing directly to Kafka after a database commit would introduce a dual-write failure: the order could commit while its event is lost.

## Decision

Use separate Spring Boot command and query services with separate PostgreSQL databases. The command service writes the order and a versioned domain-event envelope to a transactional outbox in one database transaction. PostgreSQL atomically claims idempotency keys and binds each key to a deterministic command fingerprint; row locking serializes idempotent cancellation retries. A scheduled relay publishes pending rows in database-assigned relay-sequence order rather than application-clock order. The query service consumes at least once, deduplicates by event ID, applies aggregate versions in order, and stores a denormalized read model.

Use a Spring Cloud Gateway entry point that routes commands and queries by HTTP method while preserving one public resource URL.

## Consequences

Positive:

- write-side invariants and read-side shape evolve independently;
- no distributed transaction is required;
- committed event intent survives Kafka outages;
- delivery and projection failure are observable and recoverable;
- each service owns its persistence model.

Negative:

- clients must understand eventual consistency;
- the platform includes Kafka and two databases;
- duplicate delivery is normal and every consumer must be idempotent;
- schema evolution and DLT replay need explicit operational ownership.

## Alternatives considered

- **Synchronous command-to-query call:** couples availability and still leaves a distributed write problem.
- **Publish after commit without an outbox:** simpler code but can permanently lose events.
- **Event sourcing:** useful when the event log itself must be the aggregate source of truth, but it adds conceptual and migration cost that CQRS alone does not require.
- **One service with separate packages:** demonstrates code organization, not independently deployable microservice ownership.
