package com.karacsonybarni.orders.command.domain.event;

import java.time.Instant;

public record OrderConfirmedEvent(Instant confirmedAt) implements OrderEvent {

    @Override
    public String type() {
        return ORDER_CONFIRMED;
    }

    @Override
    public Instant occurredAt() {
        return confirmedAt;
    }
}
