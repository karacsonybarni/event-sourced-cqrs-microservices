package com.karacsonybarni.orders.activity;

import com.microsoft.azure.functions.ExecutionContext;
import com.microsoft.azure.functions.OutputBinding;
import com.microsoft.azure.functions.BrokerProtocol;
import com.microsoft.azure.functions.annotation.CosmosDBOutput;
import com.microsoft.azure.functions.annotation.ExponentialBackoffRetry;
import com.microsoft.azure.functions.annotation.FunctionName;
import com.microsoft.azure.functions.annotation.KafkaOutput;
import com.microsoft.azure.functions.annotation.KafkaTrigger;
import tools.jackson.core.JacksonException;
import tools.jackson.databind.ObjectMapper;

public class OrderActivityFunction {

    private final OrderActivityDocumentMapper documentMapper = new OrderActivityDocumentMapper(new ObjectMapper());

    @FunctionName("projectOrderActivity")
    @ExponentialBackoffRetry(
            maxRetryCount = -1,
            minimumInterval = "00:00:01",
            maximumInterval = "00:01:00")
    public void project(
            @KafkaTrigger(
                    name = "orderEvent",
                    topic = "orders.events.v1",
                    brokerList = "%KAFKA_BROKERS%",
                    consumerGroup = "order-activity-function-v1",
                    protocol = BrokerProtocol.PLAINTEXT,
                    dataType = "string") String serializedEvent,
            @CosmosDBOutput(
                    name = "activityDocument",
                    databaseName = "%COSMOS_DATABASE_NAME%",
                    containerName = "%COSMOS_CONTAINER_NAME%",
                    connection = "CosmosConnection",
                    partitionKey = "/orderId") OutputBinding<String> output,
            @KafkaOutput(
                    name = "deadLetterEvent",
                    topic = "orders.events.v1.activity.DLT",
                    brokerList = "%KAFKA_BROKERS%",
                    protocol = BrokerProtocol.PLAINTEXT,
                    dataType = "string",
                    enableIdempotence = true) OutputBinding<String> deadLetterOutput,
            ExecutionContext context) {
        try {
            String activityDocument = documentMapper.map(serializedEvent);
            output.setValue(activityDocument);
            context.getLogger().info("Projected an order event into the activity document model");
        } catch (IllegalArgumentException | JacksonException exception) {
            deadLetterOutput.setValue(serializedEvent);
            context.getLogger().warning("Routed an invalid order event to the activity dead-letter topic");
        }
    }
}
