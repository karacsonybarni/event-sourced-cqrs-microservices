package com.karacsonybarni.orders.command.domain;

import static org.assertj.core.api.Assertions.assertThat;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.List;
import java.util.UUID;

import org.junit.jupiter.api.Test;

class OrderTest {

    private static final Instant CREATED_AT = Instant.parse("2026-01-10T10:15:30Z");

    @Test
    void calculatesTotalAndStartsAtFirstEventSequence() {
        var items = List.of(
                new OrderLineItem("keyboard", 2, new BigDecimal("49.90")),
                new OrderLineItem("mouse", 1, new BigDecimal("29.00")));

        Order order = Order.create(UUID.randomUUID(), "customer-42", items, CREATED_AT);

        assertThat(order.getStatus()).isEqualTo(OrderStatus.CREATED);
        assertThat(order.getTotalAmount()).isEqualByComparingTo("128.80");
        assertThat(order.getEventSequence()).isEqualTo(1);
    }

    @Test
    void cancellationIsIdempotentAndAdvancesSequenceOnlyOnce() {
        var item = new OrderLineItem("keyboard", 1, new BigDecimal("49.90"));
        Order order = Order.create(UUID.randomUUID(), "customer-42", List.of(item), CREATED_AT);

        boolean firstCancellationChangedState = order.cancel(Instant.parse("2026-01-10T10:16:30Z"));
        boolean repeatedCancellationChangedState = order.cancel(Instant.parse("2026-01-10T10:17:30Z"));

        assertThat(firstCancellationChangedState).isTrue();
        assertThat(repeatedCancellationChangedState).isFalse();
        assertThat(order.getStatus()).isEqualTo(OrderStatus.CANCELLED);
        assertThat(order.getEventSequence()).isEqualTo(2);
        assertThat(order.getUpdatedAt()).isEqualTo(Instant.parse("2026-01-10T10:16:30Z"));
    }
}
