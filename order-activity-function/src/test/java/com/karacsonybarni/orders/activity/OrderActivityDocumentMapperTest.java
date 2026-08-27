package com.karacsonybarni.orders.activity;

import org.junit.jupiter.api.Test;
import tools.jackson.core.JacksonException;
import tools.jackson.databind.JsonNode;
import tools.jackson.databind.ObjectMapper;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

class OrderActivityDocumentMapperTest {

    private static final String EVENT_ID = "b67c1f1c-c391-4ef0-a1b2-c54bc632a4aa";
    private static final String ORDER_ID = "42989fcc-11b0-4c63-af36-533fdef5927b";

    private final ObjectMapper objectMapper = new ObjectMapper();
    private final OrderActivityDocumentMapper mapper = new OrderActivityDocumentMapper(objectMapper);

    @Test
    void mapsTheVersionedEnvelopeToAnOrderPartitionedDocument() throws JacksonException {
        String event = """
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

        JsonNode document = objectMapper.readTree(mapper.map(event));

        assertThat(document.required("id").asString()).isEqualTo(EVENT_ID);
        assertThat(document.required("orderId").asString()).isEqualTo(ORDER_ID);
        assertThat(document.required("eventType").asString()).isEqualTo("OrderCreated.v1");
        assertThat(document.required("aggregateVersion").asLong()).isEqualTo(1);
        assertThat(document.required("occurredAt").asString()).isEqualTo("2026-01-10T10:15:30Z");
        assertThat(document.required("payload").required("customerId").asString()).isEqualTo("customer-42");
        assertThat(document.required("payload").required("status").asString()).isEqualTo("CREATED");
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

        String firstDelivery = mapper.map(event);
        String redelivery = mapper.map(event);

        assertThat(redelivery).isEqualTo(firstDelivery);
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
}
