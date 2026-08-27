# Order activity function

This Java 21 Azure Function consumes `orders.events.v1` through the Azure Functions Kafka trigger and writes one document per event through the Cosmos DB output binding. It is a derived, independently scalable activity view; order commands and the primary query API remain independent of it.

## Build

From the repository root:

```bash
./mvnw -pl order-activity-function clean verify
```

The deployable Functions directory is generated at `order-activity-function/target/azure-functions/order-activity-function`.

## Runtime settings

Configure these Function App settings through the deployment platform:

| Setting | Purpose |
| --- | --- |
| `KAFKA_BROKERS` | Kafka bootstrap endpoints reachable from the Function App network |
| `COSMOS_DATABASE_NAME` | Existing Cosmos DB for NoSQL database |
| `COSMOS_CONTAINER_NAME` | Existing container partitioned by `/orderId` |
| `CosmosConnection` | Cosmos DB binding connection setting |

Run the app on Azure Functions 4.x using Flex Consumption, Elastic Premium, or Dedicated hosting because Kafka bindings require one of those plans. The supplied `host.json` selects the supported 4.x extension bundle containing the Kafka and Cosmos DB bindings.

Runtime references: [Azure Functions Kafka bindings](https://learn.microsoft.com/en-us/azure/azure-functions/functions-bindings-kafka) and [Azure Cosmos DB output binding](https://learn.microsoft.com/en-us/azure/azure-functions/functions-bindings-cosmosdb-v2-output).

The broker should use authenticated TLS outside a private development network. Store the Cosmos connection as a Function App secret or replace it with an identity-based connection supported by the binding; keep connection values out of source control.

## Delivery behavior

- Kafka consumer group: `order-activity-function-v1`
- Invalid-event topic: `orders.events.v1.activity.DLT`
- Cosmos DB partition key: `/orderId`
- Cosmos DB document ID: immutable event `eventId`
- Consistency: asynchronous and at least once
- Recovery: transient failures retry with exponential backoff until the dependency recovers; invalid envelopes move to the activity dead-letter topic; duplicate delivery converges on the same document
