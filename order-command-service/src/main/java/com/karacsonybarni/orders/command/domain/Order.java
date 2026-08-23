package com.karacsonybarni.orders.command.domain;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;

import jakarta.persistence.CollectionTable;
import jakarta.persistence.Column;
import jakarta.persistence.ElementCollection;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.FetchType;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.Table;
import jakarta.persistence.Version;

@Entity
@Table(name = "orders")
public class Order {

    @Id
    private UUID id;

    @Column(name = "customer_id", nullable = false, length = 100)
    private String customerId;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 30)
    private OrderStatus status;

    @Column(name = "total_amount", nullable = false, precision = 19, scale = 2)
    private BigDecimal totalAmount;

    @ElementCollection(fetch = FetchType.LAZY)
    @CollectionTable(name = "order_items", joinColumns = @JoinColumn(name = "order_id"))
    private List<OrderLineItem> items = new ArrayList<>();

    @Column(name = "created_at", nullable = false)
    private Instant createdAt;

    @Column(name = "updated_at", nullable = false)
    private Instant updatedAt;

    @Column(name = "event_sequence", nullable = false)
    private long eventSequence;

    @Version
    @Column(name = "lock_version", nullable = false)
    private long lockVersion;

    protected Order() {
    }

    public static Order create(UUID id, String customerId, List<OrderLineItem> items, Instant now) {
        if (items.isEmpty()) {
            throw new IllegalArgumentException("An order requires at least one item");
        }
        Order order = new Order();
        order.id = id;
        order.customerId = customerId;
        order.items = new ArrayList<>(items);
        order.totalAmount = items.stream()
                .map(OrderLineItem::lineTotal)
                .reduce(BigDecimal.ZERO, BigDecimal::add);
        order.status = OrderStatus.CREATED;
        order.createdAt = now;
        order.updatedAt = now;
        order.eventSequence = 1;
        return order;
    }

    public boolean cancel(Instant now) {
        if (status == OrderStatus.CANCELLED) {
            return false;
        }
        status = OrderStatus.CANCELLED;
        updatedAt = now;
        eventSequence++;
        return true;
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
        return List.copyOf(items);
    }

    public Instant getCreatedAt() {
        return createdAt;
    }

    public Instant getUpdatedAt() {
        return updatedAt;
    }

    public long getEventSequence() {
        return eventSequence;
    }
}
