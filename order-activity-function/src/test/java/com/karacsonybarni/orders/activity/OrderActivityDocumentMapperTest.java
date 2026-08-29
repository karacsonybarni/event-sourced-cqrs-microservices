package com.karacsonybarni.orders.activity;

import java.util.Map;

import org.junit.jupiter.api.Test;
import tools.jackson.core.JacksonException;
import tools.jackson.databind.ObjectMapper;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

class OrderActivityDocumentMapperTest {

    private static final String EVENT_ID = "b67c1f1c-c391-4ef0-a1b2-c54bc632a4aa";
    private static final String ORDER_ID = "42989fcc-11b0-4c63-af36-533fdef5927b";

    private final ObjectMapper objectMapper = new ObjectMapper();
    private final OrderActivityDocumentMapper mapper = new OrderActivityDocumentMapper(objectMapper);

    @Test
    @SuppressWarnings("unchecked")
    void mapsTheVersionedEnvelopeToAnOrderPartitionedDocument() throws JacksonException {
        String event = createdEvent();

        Map<String, Object> document = mapper.map(event);

        assertThat(document.get("id")).isEqualTo(EVENT_ID);
        assertThat(document.get("orderId")).isEqualTo(ORDER_ID);
        assertThat(document.get("eventType")).isEqualTo("OrderCreated.v1");
        assertThat(document.get("aggregateVersion")).isEqualTo(1L);
        assertThat(document.get("occurredAt")).isEqualTo("2026-01-10T10:15:30Z");
        Map<String, Object> payload = (Map<String, Object>) document.get("payload");
        assertThat(payload.get("customerId")).isEqualTo("customer-42");
        assertThat(payload.get("status")).isEqualTo("CREATED");
    }

    @Test
    void unwrapsTheAzureKafkaEventValueBeforeMapping() throws JacksonException {
        String kafkaEvent = objectMapper.createObjectNode()
                .put("Offset", 12)
                .put("Partition", 2)
                .put("Topic", "orders.events.v1")
                .put("Value", createdEvent())
                .toString();

        Map<String, Object> document = mapper.map(kafkaEvent);

        assertThat(document.get("id")).isEqualTo(EVENT_ID);
        assertThat(document.get("orderId")).isEqualTo(ORDER_ID);
        assertThat(document.get("eventType")).isEqualTo("OrderCreated.v1");
    }

    @Test
    void rejectsBlankKafkaEventsAsInvalidMessages() {
        assertThatThrownBy(() -> mapper.map("   "))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessage("Kafka event must contain a JSON object");
    }

    @Test
    void rejectsWrappedValuesThatDoNotContainAnEventObject() {
        String kafkaEvent = objectMapper.createObjectNode()
                .put("Value", "null")
                .toString();

        assertThatThrownBy(() -> mapper.map(kafkaEvent))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessage("Kafka event Value must contain a JSON object");
    }

    @Test
    void producesTheSameDocumentWhenKafkaRedeliversAnEvent() throws JacksonException {
        String event = """
                {
                  "eventId": "%s",
                  "eventType": "OrderCancelled.v1",
                  "aggregateId": "%s",
                  "aggregateVersion": 2,
                  "occurredAt": "2026-01-10T10:20:30Z",
                  "payload": {
                    "status": "CANCELLED",
                    "cancelledAt": "2026-01-10T10:20:30Z"
                  }
                }
                """.formatted(EVENT_ID, ORDER_ID);

        assertThat(mapper.map(event)).isEqualTo(mapper.map(event));
    }

    @Test
    void rejectsAnInvalidEnvelopeBeforeWritingToCosmosDb() {
        String event = """
                {
                  "eventId": "%s",
                  "eventType": "OrderCreated.v1",
                  "aggregateId": "%s",
                  "aggregateVersion": 0,
                  "occurredAt": "2026-01-10T10:15:30Z",
                  "payload": {}
                }
                """.formatted(EVENT_ID, ORDER_ID);

        assertThatThrownBy(() -> mapper.map(event))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessage("aggregateVersion must be positive");
    }

    private String createdEvent() {
        return """
                {
                  "eventId": "%s",
                  "eventType": "OrderCreated.v1",
                  "aggregateId": "%s",
                  "aggregateVersion": 1,
                  "occurredAt": "2026-01-10T10:15:30Z",
                  "payload": {
                    "customerId": "customer-42",
                    "status": "CREATED",
                    "totalAmount": 208.90,
                    "items": []
                  }
                }
                """.formatted(EVENT_ID, ORDER_ID);
    }
}
