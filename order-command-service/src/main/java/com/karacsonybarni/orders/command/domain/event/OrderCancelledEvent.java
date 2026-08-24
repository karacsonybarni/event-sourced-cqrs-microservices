package com.karacsonybarni.orders.command.domain.event;

import java.time.Instant;

public record OrderCancelledEvent(Instant cancelledAt) implements OrderEvent {

    @Override
    public String type() {
        return ORDER_CANCELLED;
    }

    @Override
    public Instant occurredAt() {
        return cancelledAt;
    }
}
