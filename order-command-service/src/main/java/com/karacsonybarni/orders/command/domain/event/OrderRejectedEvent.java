package com.karacsonybarni.orders.command.domain.event;

import java.time.Instant;

public record OrderRejectedEvent(String reason, Instant rejectedAt) implements OrderEvent {

    @Override
    public String type() {
        return ORDER_REJECTED;
    }

    @Override
    public Instant occurredAt() {
        return rejectedAt;
    }
}
