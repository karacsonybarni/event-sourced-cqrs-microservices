# ADR-005: Add an independent serverless order-activity projection

- Status: Accepted
- Date: 2026-08-27

## Context

The primary query service needs relational filtering and a current-state order view, while an activity timeline has a different access pattern: append one document per event, read a single order's history, preserve event-specific payloads, and absorb irregular traffic independently from the order APIs.

Kafka already carries the committed, versioned order-event contract. Adding Azure Service Bus as a second transport would introduce another delivery boundary without a distinct routing, protocol, or ownership requirement.

## Decision

Add a separately deployable Java 21 Azure Function triggered by `orders.events.v1`. Validate each envelope and write one Azure Cosmos DB for NoSQL document per event. Use `/orderId` as the partition key and the immutable `eventId` as the document ID.

Retry transient execution failures until recovery, using exponential backoff capped at one minute between attempts so the affected Kafka offset is preserved. Publish invalid envelopes to the dedicated `orders.events.v1.activity.DLT` Kafka topic so a poison message cannot stall its partition.

Keep the Function outside the synchronous order path and outside the primary CQRS read model. PostgreSQL remains authoritative for event streams and remains the query service's optimized store. Package the Function in the Maven reactor with Azure Functions runtime metadata generated from its annotations.

Use Azure Functions Flex Consumption because Kafka triggers require Functions 4.x on Flex Consumption, Elastic Premium, or Dedicated hosting. Integrate a dedicated Function subnet with the runtime virtual network and expose a second Kafka listener only on the VM's private address. Cap the Function at two on-demand instances with no always-ready allocation so it scales to zero between events.

Provision one Cosmos DB account with the lifetime free-tier discount, 400 RU/s of shared provisioned throughput, and one `/orderId`-partitioned container. Use a user-assigned managed identity for Function host storage and Cosmos DB data access; disable Cosmos DB local-key authentication. Expose a read-only HTTP Function for one order's activity so the public portal and deployment checks can verify the derived NoSQL view end to end.

## Consequences

- Event processing scales independently and runs only when Kafka supplies work.
- Event-specific payloads remain natural JSON documents rather than sparse relational columns.
- The public proof can compare the relational current-state projection with the document-oriented activity timeline.
- At-least-once delivery is idempotent because the same event writes the same document ID in the same logical partition.
- Activity-projection outages create lag without reducing command or primary query availability.
- A prolonged downstream outage pauses affected Kafka partitions and requires an operational alert.
- Cosmos DB and the Function add monitoring, networking, retention, and cost boundaries; Terraform enforces free-tier throughput and scale-to-zero defaults.
- The activity view is derived data and can be rebuilt from retained Kafka history or the authoritative event store.

## Alternatives considered

- **Add Azure Service Bus:** duplicates Kafka's asynchronous delivery role and creates an unnecessary bridge.
- **Store activity documents in the query PostgreSQL database:** keeps operations simpler but provides no independent scaling or document-oriented access boundary.
- **Replace the query read model with Cosmos DB:** weakens the relational search use case and couples a focused extension to the primary API.
- **Implement both Azure Functions and AWS Lambda handlers:** duplicates one responsibility across clouds without another domain requirement.
