package com.karacsonybarni.orders.command.domain;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;

import com.karacsonybarni.orders.command.domain.event.OrderCancelledEvent;
import com.karacsonybarni.orders.command.domain.event.OrderCreatedEvent;
import com.karacsonybarni.orders.command.domain.event.OrderEvent;

public final class Order {

    private final UUID id;
    private final List<OrderEvent> uncommittedEvents = new ArrayList<>();

    private String customerId;
    private OrderStatus status;
    private BigDecimal totalAmount;
    private List<OrderLineItem> items = List.of();
    private Instant createdAt;
    private Instant updatedAt;
    private long version;

    private Order(UUID id) {
        this.id = id;
    }

    public static Order create(UUID id, String customerId, List<OrderLineItem> items, Instant now) {
        if (items.isEmpty()) {
            throw new IllegalArgumentException("An order requires at least one item");
        }
        BigDecimal totalAmount = items.stream()
                .map(OrderLineItem::lineTotal)
                .reduce(BigDecimal.ZERO, BigDecimal::add);
        var order = new Order(id);
        var event = new OrderCreatedEvent(customerId, totalAmount, items, now);
        order.record(event);
        return order;
    }

    public static Order rehydrate(UUID id, List<OrderEvent> history) {
        if (history.isEmpty()) {
            throw new OrderNotFoundException(id);
        }
        var order = new Order(id);
        history.forEach(order::apply);
        return order;
    }

    public boolean cancel(Instant now) {
        if (status == OrderStatus.CANCELLED) {
            return false;
        }
        record(new OrderCancelledEvent(now));
        return true;
    }

    private void record(OrderEvent event) {
        apply(event);
        uncommittedEvents.add(event);
    }

    private void apply(OrderEvent event) {
        switch (event) {
            case OrderCreatedEvent created -> applyCreated(created);
            case OrderCancelledEvent cancelled -> applyCancelled(cancelled);
        }
        version++;
    }

    private void applyCreated(OrderCreatedEvent event) {
        if (version != 0) {
            throw new IllegalStateException("OrderCreated must be the first event in an order stream");
        }
        customerId = event.customerId();
        status = OrderStatus.CREATED;
        totalAmount = event.totalAmount();
        items = List.copyOf(event.items());
        createdAt = event.createdAt();
        updatedAt = event.createdAt();
    }

    private void applyCancelled(OrderCancelledEvent event) {
        if (status == null) {
            throw new IllegalStateException("OrderCancelled requires an existing order");
        }
        status = OrderStatus.CANCELLED;
        updatedAt = event.cancelledAt();
    }

    public UUID getId() {
        return id;
    }

    public String getCustomerId() {
        return customerId;
    }

    public OrderStatus getStatus() {
        return status;
    }

    public BigDecimal getTotalAmount() {
        return totalAmount;
    }

    public List<OrderLineItem> getItems() {
        return items;
    }

    public Instant getCreatedAt() {
        return createdAt;
    }

    public Instant getUpdatedAt() {
        return updatedAt;
    }

    public long getVersion() {
        return version;
    }

    public List<OrderEvent> getUncommittedEvents() {
        return List.copyOf(uncommittedEvents);
    }

    public void markEventsCommitted() {
        uncommittedEvents.clear();
    }
}
