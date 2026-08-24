package com.karacsonybarni.orders.command.eventstore;

import static org.assertj.core.api.Assertions.assertThat;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.List;
import java.util.UUID;

import com.karacsonybarni.orders.command.domain.Order;
import com.karacsonybarni.orders.command.domain.OrderLineItem;
import com.karacsonybarni.orders.command.domain.event.OrderCreatedEvent;
import org.junit.jupiter.api.Test;
import tools.jackson.databind.json.JsonMapper;

class OrderEventSerializerTest {

    @Test
    void persistedPayloadIsTheVersionedIntegrationEnvelope() {
        Instant now = Instant.parse("2026-01-10T10:15:30Z");
        var serializer = new OrderEventSerializer(JsonMapper.builder().findAndAddModules().build());
        UUID orderId = UUID.randomUUID();
        Order order = Order.create(
                orderId,
                "customer-42",
                List.of(new OrderLineItem("keyboard", 2, new BigDecimal("49.90"))),
                now);

        StoredOrderEvent stored = serializer.serialize(orderId, 1, order.getUncommittedEvents().getFirst());
        var payload = JsonMapper.builder().build().valueToTree(stored.getPayload());

        assertThat(stored.getEventType()).isEqualTo("OrderCreated.v1");
        assertThat(stored.getAggregateVersion()).isOne();
        assertThat(payload.required("eventId").asString()).isEqualTo(stored.getEventId().toString());
        assertThat(payload.required("aggregateId").asString()).isEqualTo(orderId.toString());
        assertThat(payload.required("aggregateVersion").asLong()).isOne();
        assertThat(payload.required("payload").required("totalAmount").decimalValue())
                .isEqualByComparingTo("99.80");
    }

    @Test
    void storedEventRoundTripsToTheDomainEvent() {
        Instant now = Instant.parse("2026-01-10T10:15:30Z");
        var serializer = new OrderEventSerializer(JsonMapper.builder().findAndAddModules().build());
        var event = new OrderCreatedEvent(
                "customer-42",
                new BigDecimal("49.90"),
                List.of(new OrderLineItem("keyboard", 1, new BigDecimal("49.90"))),
                now);

        StoredOrderEvent stored = serializer.serialize(UUID.randomUUID(), 1, event);

        assertThat(serializer.deserialize(stored)).isEqualTo(event);
    }
}
