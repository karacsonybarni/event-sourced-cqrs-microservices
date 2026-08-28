package com.karacsonybarni.orders.command.domain.event;

import java.time.Instant;

public sealed interface OrderEvent permits
        OrderCreatedEvent,
        OrderConfirmedEvent,
        OrderRejectedEvent,
        OrderCancelledEvent {

    String ORDER_CREATED = "OrderCreated.v1";
    String ORDER_CONFIRMED = "OrderConfirmed.v1";
    String ORDER_REJECTED = "OrderRejected.v1";
    String ORDER_CANCELLED = "OrderCancelled.v1";

    String type();

    Instant occurredAt();
}
