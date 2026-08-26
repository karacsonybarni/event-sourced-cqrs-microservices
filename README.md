# Event-Sourced CQRS Microservices

[![CI](https://github.com/karacsonybarni/event-sourced-cqrs-microservices/actions/workflows/ci.yml/badge.svg)](https://github.com/karacsonybarni/event-sourced-cqrs-microservices/actions/workflows/ci.yml)
[![Azure deployment](https://github.com/karacsonybarni/event-sourced-cqrs-microservices/actions/workflows/deploy-azure.yml/badge.svg)](https://github.com/karacsonybarni/event-sourced-cqrs-microservices/actions/workflows/deploy-azure.yml)
[![AWS deployment](https://github.com/karacsonybarni/event-sourced-cqrs-microservices/actions/workflows/deploy-aws.yml/badge.svg)](https://github.com/karacsonybarni/event-sourced-cqrs-microservices/actions/workflows/deploy-aws.yml)
[![Spring Boot](https://img.shields.io/badge/Spring%20Boot-4.1.1-6DB33F?logo=springboot)](https://spring.io/projects/spring-boot)
[![Java](https://img.shields.io/badge/Java-21-ED8B00?logo=openjdk)](https://adoptium.net/)
[![Debezium](https://img.shields.io/badge/Debezium-3.6.1.Final-2C4F7C)](https://debezium.io/)

A runnable reference architecture combining Command Query Responsibility Segregation (CQRS), event sourcing, Debezium change data capture, registry-backed service discovery, and horizontal scaling. The command database stores immutable domain events as the source of truth, Debezium streams committed inserts to Kafka, and replicated query services build and serve a disposable read model.

The design follows the pattern language at [microservices.io](https://microservices.io/patterns/microservices.html), especially [Event Sourcing](https://microservices.io/patterns/data/event-sourcing.html), [CQRS](https://microservices.io/patterns/data/cqrs.html), [Database per Service](https://microservices.io/patterns/data/database-per-service.html), [API Gateway](https://microservices.io/patterns/apigateway.html), and [Idempotent Consumer](https://microservices.io/patterns/communication-style/idempotent-consumer.html).

## Architecture at a glance

```mermaid
flowchart LR
    Client([Client]) -->|HTTP :8080| Gateway[Spring Cloud<br/>API Gateway]
    Registry[Eureka<br/>Service Registry]
    Gateway <-->|discover instances| Registry
    Command[Order Command Service<br/>2 replicas] -->|self-register| Registry
    Query[Order Query Service<br/>2 replicas] -->|self-register| Registry
    Gateway -->|lb:// POST / PUT| Command
    Gateway -->|lb:// GET| Query

    Command -->|append in one ACID transaction| EventStore[(Command PostgreSQL<br/>append-only event store)]
    EventStore -->|logical replication / WAL| Debezium[Debezium<br/>PostgreSQL connector]
    Debezium -->|versioned envelope<br/>keyed by orderId| Kafka{{Apache Kafka}}
    Kafka -->|at-least-once| Projector[Idempotent projector]
    Projector --> QueryDB[(Query PostgreSQL<br/>denormalized views)]
    Query --> QueryDB
    Kafka -. poison events .-> DLT[(Dead-letter topic)]
```

| Component | Responsibility | Data ownership |
| --- | --- | --- |
| `api-gateway` | Method-aware routing and correlation IDs | None |
| `discovery-server` | Instance registry and health-aware service lookup | Registry leases |
| `order-command-service` | Validates commands, replays aggregates, appends events | Event streams and command deduplication |
| Debezium | Captures committed event inserts from PostgreSQL WAL | Replication offset and connector state |
| `order-query-service` | Projects events and serves query-optimized responses | Order read model and processed-event IDs |
| Kafka | Durable asynchronous transport | `orders.events.v1` and `orders.events.v1.DLT` |

The write and read services share neither a database nor a Java model. Their integration contract is the versioned event envelope stored in `order_events` and emitted unchanged by Debezium.

## Run the complete system

Prerequisites: Docker with Compose, Java 21+, `curl`, and `jq`.

```bash
make up
make smoke
```

`make up` compiles the services, starts PostgreSQL, Kafka, Debezium, Eureka, the gateway, two command-service replicas, and two query-service replicas, registers the connector idempotently, and waits for health checks. `make smoke` proves this flow through the gateway:

1. create an order;
2. repeat the same command and verify idempotent replay;
3. reuse the key with another payload and verify `409 Conflict`;
4. wait for Debezium and Kafka to update the query model;
5. cancel the order; and
6. verify the read model advances from event version 1 to 2.

`make scale-smoke` then stops every command and query replica in turn. It waits for Eureka to evict the stopped instance and proves that the gateway continues routing commands and queries to the surviving replica before restoring the full topology.

Stop the stack and remove its local volumes with:

```bash
make down
```

## Deploy to Azure

The repository includes a credit-protected Azure deployment with Terraform, Azure Virtual Network, a hardened Linux VM, private versioned Blob state, Entra workload identity federation, GitHub Actions OIDC, Azure Run Command, boot diagnostics, a resource-group budget, stable DNS, and Caddy-managed HTTPS. It preserves the complete multi-replica Kafka and Debezium topology and refuses to provision unless the Azure subscription is enabled with spending protection set to `On`.

Verified public API: [https://escqrs-62636a3dc4.polandcentral.cloudapp.azure.com](https://escqrs-62636a3dc4.polandcentral.cloudapp.azure.com)

See [Azure cloud deployment](docs/azure-deployment.md) for the architecture, provisioning command, security model, cost boundary, delivery flow, operations, and teardown procedure. [ADR-004](docs/adr/004-credit-protected-azure-deployment.md) records why the complete topology uses promotional credit on one 8-GiB VM instead of the undersized 12-month free VM shapes.

## Preserved AWS deployment

The AWS deployment remains fully described and reproducible with Terraform, Amazon API Gateway, EC2, VPC networking, IAM, Systems Manager, CloudWatch, S3 remote state, GitHub Actions OIDC, automated delivery, and public end-to-end verification. Its remote state and runtime resources are intentionally preserved while AWS automatic delivery is paused.

Last assigned API endpoint: `https://n6jxpgtbrc.execute-api.eu-central-1.amazonaws.com/`

See [AWS cloud deployment](docs/aws-deployment.md) for the architecture, provisioning command, security model, operations, cost controls, and teardown procedure. [ADR-003](docs/adr/003-cost-optimized-aws-deployment.md) records why the economical topology uses one deployment host and how it evolves into managed production services.

## Try the API manually

All client traffic enters through `http://localhost:8080`.

```bash
curl --request POST http://localhost:8080/api/orders \
  --header 'Content-Type: application/json' \
  --header 'Idempotency-Key: order-demo-1' \
  --data '{
    "customerId": "customer-42",
    "items": [
      {"productId": "keyboard", "quantity": 1, "unitPrice": 129.90},
      {"productId": "mouse", "quantity": 2, "unitPrice": 39.50}
    ]
  }'
```

The command returns `202 Accepted` after the event-store transaction commits. Use the returned `orderId` to query and cancel:

```bash
curl http://localhost:8080/api/orders/{orderId}
curl --request PUT http://localhost:8080/api/orders/{orderId}/cancellation
curl 'http://localhost:8080/api/orders?customerId=customer-42&status=CANCELLED'
```

Operational endpoints:

- Eureka registry: [http://localhost:8761](http://localhost:8761)
- Debezium Connect: [http://localhost:8083/connectors/order-events/status](http://localhost:8083/connectors/order-events/status)
- Gateway health: [http://localhost:8080/actuator/health](http://localhost:8080/actuator/health)
- Prometheus metrics: `/actuator/prometheus` on every Spring service

Backend replicas receive random host ports so they can scale without collisions. Resolve a replica's host port when direct Swagger or Actuator access is needed:

```bash
docker compose port --index 1 order-command-service 8081
docker compose port --index 1 order-query-service 8082
```

## Event-sourcing and delivery guarantees

- **Events are authoritative:** an `Order` is reconstructed by replaying its ordered event stream; no mutable order table exists.
- **Append-only enforcement:** PostgreSQL rejects `UPDATE` and `DELETE` against `order_events`, and a unique `(aggregate_id, aggregate_version)` constraint rejects conflicting stream positions.
- **Optimistic stream version plus row serialization:** `aggregate_streams.current_version` is concurrency metadata. A row lock serializes concurrent transitions while the event history remains the source of aggregate state.
- **No application-level database/Kafka dual write:** the command transaction ends after appending the event. Debezium reads only committed WAL changes and owns publication to Kafka.
- **At-least-once delivery:** connector or consumer recovery can redeliver a record. `processed_events.event_id` makes projection replay harmless.
- **Per-order ordering:** every event has a contiguous aggregate version and uses `orderId` as its Kafka key, preserving the partition-ordering boundary.
- **Poison-event isolation:** projection failures retry twice and then move to `orders.events.v1.DLT`.
- **Idempotent client retries:** PostgreSQL atomically claims `Idempotency-Key` and binds it to a deterministic request fingerprint.
- **Honest eventual consistency:** query responses include `X-Data-Consistency: eventual`; a newly committed order may briefly be absent from the read side.

See [Architecture](docs/architecture.md) for the detailed mechanics and [ADR-001](docs/adr/001-event-sourcing-and-debezium-cdc.md) for the main trade-offs.

## Verification

```bash
./mvnw clean verify
docker compose config --quiet
make up
make smoke
make scale-smoke
```

The test suite covers aggregate replay, versioned serialization, append-only database enforcement, concurrent create/cancel commands, idempotent command fingerprints, duplicate event delivery, stale projection versions, dead-letter routing, API behavior, gateway correlation IDs, and load-balanced route configuration. The smoke tests add real PostgreSQL logical decoding, Debezium, Kafka, Eureka registration, two replicas of each business service, instance eviction, failover, both databases, Flyway, and all HTTP services.

## Technology baseline

- Java 21 LTS
- Spring Boot 4.1.1
- Spring Cloud 2025.1.3, Spring Cloud Gateway, LoadBalancer, and Netflix Eureka
- Spring Data JPA, Flyway, PostgreSQL 18
- Debezium 3.6.1.Final PostgreSQL connector
- Spring for Apache Kafka and Apache Kafka 4.3.1 in KRaft mode
- springdoc-openapi 3.1.0
- Micrometer Actuator and Prometheus metrics
- Maven Wrapper, Docker Compose, GitHub Actions, Dependabot
- Terraform, Azure Virtual Network, Linux VM, Entra workload identity federation, Run Command, Blob state, budgets, DNS, and HTTPS
- Terraform, AWS API Gateway, EC2, VPC, IAM, Systems Manager, CloudWatch, and S3 remote state

## Repository map

```text
api-gateway/             HTTP entry point and routing
discovery-server/        Eureka service registry
order-command-service/  event-sourced aggregate, event store, command API
order-query-service/    Kafka projection, read model, query API
debezium/                replication user and connector registration
docs/                    architecture narrative and decisions
scripts/                 end-to-end and multi-replica failover checks
infra/aws/               Terraform state bootstrap and AWS runtime infrastructure
infra/azure/             Terraform state bootstrap and Azure runtime infrastructure
compose.yml              complete local platform
compose.cloud.yml        cloud-only exposure, resource, secret, and logging policy
compose.azure.yml        Azure exposure, resource, secret, logging, and HTTPS policy
```

## License

MIT
