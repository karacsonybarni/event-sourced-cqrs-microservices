package com.karacsonybarni.orders.command.domain.event;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.List;

import com.karacsonybarni.orders.command.domain.OrderLineItem;

public record OrderCreatedEvent(
        String customerId,
        BigDecimal totalAmount,
        List<OrderLineItem> items,
        Instant createdAt) implements OrderEvent {

    public OrderCreatedEvent {
        items = List.copyOf(items);
    }

    @Override
    public String type() {
        return ORDER_CREATED;
    }

    @Override
    public Instant occurredAt() {
        return createdAt;
    }
}
