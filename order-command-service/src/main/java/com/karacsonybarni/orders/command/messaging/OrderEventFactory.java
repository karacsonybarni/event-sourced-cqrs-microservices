package com.karacsonybarni.orders.command.messaging;

import java.time.Clock;
import java.time.Instant;
import java.util.List;
import java.util.UUID;

import com.karacsonybarni.orders.command.domain.Order;
import com.karacsonybarni.orders.command.domain.OrderLineItem;
import com.karacsonybarni.orders.command.outbox.OutboxEvent;
import org.springframework.stereotype.Component;
import tools.jackson.core.JacksonException;
import tools.jackson.databind.ObjectMapper;

@Component
public class OrderEventFactory {

    public static final String ORDER_CREATED = "OrderCreated.v1";
    public static final String ORDER_CANCELLED = "OrderCancelled.v1";

    private final ObjectMapper objectMapper;
    private final Clock clock;

    public OrderEventFactory(ObjectMapper objectMapper, Clock clock) {
        this.objectMapper = objectMapper;
        this.clock = clock;
    }

    public OutboxEvent orderCreated(Order order) {
        var items = order.getItems().stream().map(ItemPayload::from).toList();
        var payload = new OrderCreatedPayload(
                order.getCustomerId(), order.getStatus().name(), order.getTotalAmount(), items, order.getCreatedAt());
        return createEvent(order, ORDER_CREATED, payload);
    }

    public OutboxEvent orderCancelled(Order order) {
        var payload = new OrderCancelledPayload(order.getStatus().name(), order.getUpdatedAt());
        return createEvent(order, ORDER_CANCELLED, payload);
    }

    private OutboxEvent createEvent(Order order, String type, Object payload) {
        UUID eventId = UUID.randomUUID();
        Instant occurredAt = clock.instant();
        var envelope = new EventEnvelope(
                eventId, type, order.getId(), order.getEventSequence(), occurredAt, payload);
        try {
            String serializedEnvelope = objectMapper.writeValueAsString(envelope);
            return new OutboxEvent(eventId, order.getId(), type, serializedEnvelope, occurredAt);
        } catch (JacksonException exception) {
            throw new IllegalStateException("Could not serialize order event", exception);
        }
    }

    record EventEnvelope(
            UUID eventId,
            String eventType,
            UUID aggregateId,
            long aggregateVersion,
            Instant occurredAt,
            Object payload) {
    }

    record OrderCreatedPayload(
            String customerId,
            String status,
            java.math.BigDecimal totalAmount,
            List<ItemPayload> items,
            Instant createdAt) {
    }

    record OrderCancelledPayload(String status, Instant cancelledAt) {
    }

    record ItemPayload(String productId, int quantity, java.math.BigDecimal unitPrice) {

        static ItemPayload from(OrderLineItem item) {
            return new ItemPayload(item.getProductId(), item.getQuantity(), item.getUnitPrice());
        }
    }
}
