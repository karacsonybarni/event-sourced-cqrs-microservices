package com.karacsonybarni.orders.activity;

import com.microsoft.azure.functions.BrokerProtocol;
import com.microsoft.azure.functions.ExecutionContext;
import com.microsoft.azure.functions.OutputBinding;
import com.microsoft.azure.functions.annotation.ExponentialBackoffRetry;
import com.microsoft.azure.functions.annotation.FunctionName;
import com.microsoft.azure.functions.annotation.KafkaOutput;
import com.microsoft.azure.functions.annotation.KafkaTrigger;
import tools.jackson.core.JacksonException;
import tools.jackson.databind.ObjectMapper;

public class OrderActivityFunction {

    private final OrderActivityDocumentMapper documentMapper;
    private final OrderActivityStore activityStore;

    public OrderActivityFunction() {
        this(new OrderActivityDocumentMapper(new ObjectMapper()), CosmosOrderActivityStore.instance());
    }

    OrderActivityFunction(OrderActivityDocumentMapper documentMapper, OrderActivityStore activityStore) {
        this.documentMapper = documentMapper;
        this.activityStore = activityStore;
    }

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
            @KafkaOutput(
                    name = "deadLetterEvent",
                    topic = "orders.events.v1.activity.DLT",
                    brokerList = "%KAFKA_BROKERS%",
                    protocol = BrokerProtocol.PLAINTEXT,
                    dataType = "string",
                    enableIdempotence = true) OutputBinding<String> deadLetterOutput,
            ExecutionContext context) {
        try {
            activityStore.upsert(documentMapper.map(serializedEvent));
            context.getLogger().info("Projected an order event into the activity document model");
        } catch (IllegalArgumentException | JacksonException exception) {
            deadLetterOutput.setValue(serializedEvent);
            context.getLogger().warning("Routed an invalid order event to the activity dead-letter topic");
        }
    }
}
