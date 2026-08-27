package com.karacsonybarni.orders.activity;

import java.lang.reflect.Method;

import com.microsoft.azure.functions.BrokerProtocol;
import com.microsoft.azure.functions.OutputBinding;
import com.microsoft.azure.functions.annotation.CosmosDBOutput;
import com.microsoft.azure.functions.annotation.ExponentialBackoffRetry;
import com.microsoft.azure.functions.annotation.FunctionName;
import com.microsoft.azure.functions.annotation.KafkaOutput;
import com.microsoft.azure.functions.annotation.KafkaTrigger;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

class OrderActivityFunctionTest {

    private static final String EVENT_ID = "b67c1f1c-c391-4ef0-a1b2-c54bc632a4aa";
    private static final String ORDER_ID = "42989fcc-11b0-4c63-af36-533fdef5927b";

    @Test
    void declaresKafkaAsItsTriggerAndCosmosDbAsItsOutput() throws NoSuchMethodException {
        Method function = OrderActivityFunction.class.getMethod(
                "project",
                String.class,
                OutputBinding.class,
                OutputBinding.class,
                com.microsoft.azure.functions.ExecutionContext.class);

        assertThat(function.getAnnotation(FunctionName.class).value()).isEqualTo("projectOrderActivity");
        KafkaTrigger trigger = function.getParameters()[0].getAnnotation(KafkaTrigger.class);
        assertThat(trigger.topic()).isEqualTo("orders.events.v1");
        assertThat(trigger.brokerList()).isEqualTo("%KAFKA_BROKERS%");
        assertThat(trigger.consumerGroup()).isEqualTo("order-activity-function-v1");
        assertThat(trigger.protocol()).isEqualTo(BrokerProtocol.PLAINTEXT);

        CosmosDBOutput output = function.getParameters()[1].getAnnotation(CosmosDBOutput.class);
        assertThat(output.databaseName()).isEqualTo("%COSMOS_DATABASE_NAME%");
        assertThat(output.containerName()).isEqualTo("%COSMOS_CONTAINER_NAME%");
        assertThat(output.connection()).isEqualTo("CosmosConnection");
        assertThat(output.partitionKey()).isEqualTo("/orderId");

        KafkaOutput deadLetter = function.getParameters()[2].getAnnotation(KafkaOutput.class);
        assertThat(deadLetter.topic()).isEqualTo("orders.events.v1.activity.DLT");
        assertThat(deadLetter.brokerList()).isEqualTo("%KAFKA_BROKERS%");
        assertThat(deadLetter.protocol()).isEqualTo(BrokerProtocol.PLAINTEXT);
        assertThat(deadLetter.enableIdempotence()).isTrue();

        ExponentialBackoffRetry retry = function.getAnnotation(ExponentialBackoffRetry.class);
        assertThat(retry.maxRetryCount()).isEqualTo(-1);
        assertThat(retry.minimumInterval()).isEqualTo("00:00:01");
        assertThat(retry.maximumInterval()).isEqualTo("00:01:00");
    }

    @Test
    void usesTheEventIdAsTheStableCosmosDocumentId() {
        String event = """
                {
                  "eventId": "%s",
                  "eventType": "OrderCreated.v1",
                  "aggregateId": "%s",
                  "aggregateVersion": 1,
                  "occurredAt": "2026-01-10T10:15:30Z",
                  "payload": {"status": "CREATED"}
                }
                """.formatted(EVENT_ID, ORDER_ID);
        var output = new CapturingOutputBinding();
        var deadLetterOutput = new CapturingOutputBinding();
        var context = new TestExecutionContext();

        new OrderActivityFunction().project(event, output, deadLetterOutput, context);

        assertThat(output.getValue()).contains("\"id\":\"" + EVENT_ID + "\"");
        assertThat(output.getValue()).contains("\"orderId\":\"" + ORDER_ID + "\"");
        assertThat(deadLetterOutput.getValue()).isNull();
    }

    @Test
    void routesInvalidEventsToTheActivityDeadLetterTopic() {
        String invalidEvent = """
                {
                  "eventId": "%s",
                  "eventType": "OrderCreated.v1",
                  "aggregateId": "%s",
                  "aggregateVersion": 1,
                  "occurredAt": "not-an-instant",
                  "payload": {}
                }
                """.formatted(EVENT_ID, ORDER_ID);
        var output = new CapturingOutputBinding();
        var deadLetterOutput = new CapturingOutputBinding();

        new OrderActivityFunction().project(
                invalidEvent,
                output,
                deadLetterOutput,
                new TestExecutionContext());

        assertThat(output.getValue()).isNull();
        assertThat(deadLetterOutput.getValue()).isEqualTo(invalidEvent);
    }

    private static final class CapturingOutputBinding implements OutputBinding<String> {

        private String value;

        @Override
        public String getValue() {
            return value;
        }

        @Override
        public void setValue(String value) {
            this.value = value;
        }
    }

    private static final class TestExecutionContext implements com.microsoft.azure.functions.ExecutionContext {

        @Override
        public java.util.logging.Logger getLogger() {
            return java.util.logging.Logger.getLogger(OrderActivityFunctionTest.class.getName());
        }

        @Override
        public String getInvocationId() {
            return "test-invocation";
        }

        @Override
        public String getFunctionName() {
            return "projectOrderActivity";
        }
    }
}
