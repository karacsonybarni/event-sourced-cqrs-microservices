package com.karacsonybarni.orders.command.messaging;

import static org.assertj.core.api.Assertions.assertThat;

import java.math.BigDecimal;
import java.time.Clock;
import java.time.Instant;
import java.time.ZoneOffset;
import java.util.List;
import java.util.UUID;

import com.karacsonybarni.orders.command.domain.Order;
import com.karacsonybarni.orders.command.domain.OrderLineItem;
import org.junit.jupiter.api.Test;
import tools.jackson.databind.json.JsonMapper;

class OrderEventFactoryTest {

    @Test
    void createdEventUsesVersionedEnvelopeContract() throws Exception {
        Instant now = Instant.parse("2026-01-10T10:15:30Z");
        Clock clock = Clock.fixed(now, ZoneOffset.UTC);
        var objectMapper = JsonMapper.builder().findAndAddModules().build();
        var factory = new OrderEventFactory(objectMapper, clock);
        UUID orderId = UUID.randomUUID();
        Order order = Order.create(
                orderId,
                "customer-42",
                List.of(new OrderLineItem("keyboard", 2, new BigDecimal("49.90"))),
                now);

        var event = factory.orderCreated(order);
        var envelope = objectMapper.readTree(event.getPayload());

        assertThat(envelope.required("eventType").stringValue()).isEqualTo("OrderCreated.v1");
        assertThat(envelope.required("aggregateId").stringValue()).isEqualTo(orderId.toString());
        assertThat(envelope.required("aggregateVersion").asLong()).isEqualTo(1);
        assertThat(envelope.required("payload").required("totalAmount").decimalValue())
                .isEqualByComparingTo("99.80");
    }
}
