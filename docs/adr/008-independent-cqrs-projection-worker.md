# ADR-008: Split CQRS projection processing from the query API

- Status: Accepted
- Date: 2026-08-30

## Context

The primary CQRS read side previously combined two different runtime responsibilities in `order-query-service`: consuming Kafka events to materialize the relational read model and serving HTTP queries from that model. Those responsibilities have different traffic patterns and failure modes. Scaling the HTTP API also created additional Kafka consumers, while consumer rebalances or projection failures happened inside the same JVM that served reads.

Both responsibilities operate on the same denormalized order read model. They are two runtime roles of one CQRS read-side consistency boundary, not independent data-owning microservices.

## Decision

Split the read side into three Maven modules:

- `order-query-model` owns the shared JPA read-model entities, repositories, and Flyway schema.
- `order-projection-worker` exclusively consumes `orders.events.v1` and transactionally updates the query PostgreSQL database.
- `order-query-service` exclusively serves read-only HTTP queries from that database.

Keep the existing `order-query-projection-v2` Kafka consumer group, processed-event idempotency table, dead-letter behavior, and aggregate-version guards. The split changes deployment responsibility rather than projection semantics.

Deploy one projection-worker instance by default in both Docker Compose and the Kubernetes application tier. It has an Actuator endpoint for health and metrics but no business-facing Kubernetes Service. It can be scaled independently later, bounded by Kafka partition count and database capacity.

Keep the primary projector as a Spring Boot workload rather than moving it to Azure Functions at this stage. The query PostgreSQL database still runs on the single deployment VM, so a serverless projector would add a separate Function-to-VM database connection boundary without removing the VM availability dependency. Keeping the worker in the normal application tier also preserves local/cloud runtime parity. The existing Azure Function remains an independent Kafka-to-Cosmos activity projection.

## Consequences

- Query API replicas can scale for read traffic without creating unnecessary Kafka consumers.
- Projection throughput, rollout, consumer rebalancing, and failures are isolated from the HTTP query process.
- If projection processing pauses, the query API can continue serving the last materialized state while projection lag grows.
- The worker and query API intentionally share a database and schema, so they are separate deployables within one CQRS read-side component rather than independent microservices.
- `order-query-model` is a compile-time contract between those deployables. Schema changes therefore need rolling-deployment compatibility.
- Flyway can start from either runtime. Its database locking serializes concurrent migration attempts, but migrations must still be compatible with mixed application revisions during rolling rollout.
- One additional JVM, image, and deployment increases the small-host resource footprint. The query API resource allocation is reduced to offset part of that cost.
- The query PostgreSQL database remains a shared availability boundary for both roles.

## Production evolution

If projection load becomes significant, scale the worker according to measured Kafka lag and partition count rather than HTTP traffic. If the platform moves to managed PostgreSQL and managed Kafka, a serverless projector becomes a more attractive alternative because the stateful dependencies no longer live on the single application VM.
