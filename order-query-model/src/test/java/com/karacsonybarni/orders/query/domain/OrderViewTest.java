package com.karacsonybarni.orders.query.domain;

import static org.assertj.core.api.Assertions.assertThat;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.List;
import java.util.UUID;

import org.junit.jupiter.api.Test;

class OrderViewTest {

    @Test
    void ignoresStaleStateTransition() {
        Instant createdAt = Instant.parse("2026-01-10T10:15:30Z");
        var view = new OrderView(
                UUID.randomUUID(),
                "customer-42",
                OrderViewStatus.CREATED,
                new BigDecimal("49.90"),
                List.of(new OrderItemView("keyboard", 1, new BigDecimal("49.90"))),
                createdAt,
                2);

        view.cancel(Instant.parse("2026-01-10T10:16:30Z"), 1);

        assertThat(view.getStatus()).isEqualTo(OrderViewStatus.CREATED);
        assertThat(view.getUpdatedAt()).isEqualTo(createdAt);
        assertThat(view.getAggregateVersion()).isEqualTo(2);
    }
}
