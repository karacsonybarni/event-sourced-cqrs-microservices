package com.karacsonybarni.orders.query.domain;

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

@Entity
@Table(name = "order_views")
public class OrderView {

    @Id
    private UUID id;

    @Column(name = "customer_id", nullable = false, length = 100)
    private String customerId;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 30)
    private OrderViewStatus status;

    @Column(name = "total_amount", nullable = false, precision = 19, scale = 2)
    private BigDecimal totalAmount;

    @ElementCollection(fetch = FetchType.LAZY)
    @CollectionTable(name = "order_item_views", joinColumns = @JoinColumn(name = "order_id"))
    private List<OrderItemView> items = new ArrayList<>();

    @Column(name = "created_at", nullable = false)
    private Instant createdAt;

    @Column(name = "updated_at", nullable = false)
    private Instant updatedAt;

    @Column(name = "rejection_reason", length = 300)
    private String rejectionReason;

    @Column(name = "aggregate_version", nullable = false)
    private long aggregateVersion;

    protected OrderView() {
    }

    public OrderView(
            UUID id,
            String customerId,
            OrderViewStatus status,
            BigDecimal totalAmount,
            List<OrderItemView> items,
            Instant createdAt,
            long aggregateVersion) {
        this.id = id;
        this.customerId = customerId;
        this.status = status;
        this.totalAmount = totalAmount;
        this.items = new ArrayList<>(items);
        this.createdAt = createdAt;
        this.updatedAt = createdAt;
        this.aggregateVersion = aggregateVersion;
    }

    public void cancel(Instant cancelledAt, long newAggregateVersion) {
        transitionTo(OrderViewStatus.CANCELLED, cancelledAt, newAggregateVersion, null);
    }

    public void confirm(Instant confirmedAt, long newAggregateVersion) {
        transitionTo(OrderViewStatus.CONFIRMED, confirmedAt, newAggregateVersion, null);
    }

    public void reject(String reason, Instant rejectedAt, long newAggregateVersion) {
        transitionTo(OrderViewStatus.REJECTED, rejectedAt, newAggregateVersion, reason);
    }

    private void transitionTo(
            OrderViewStatus newStatus,
            Instant transitionedAt,
            long newAggregateVersion,
            String newRejectionReason) {
        if (newAggregateVersion <= aggregateVersion) {
            return;
        }
        status = newStatus;
        updatedAt = transitionedAt;
        aggregateVersion = newAggregateVersion;
        rejectionReason = newRejectionReason;
    }

    public UUID getId() {
        return id;
    }

    public String getCustomerId() {
        return customerId;
    }

    public OrderViewStatus getStatus() {
        return status;
    }

    public BigDecimal getTotalAmount() {
        return totalAmount;
    }

    public List<OrderItemView> getItems() {
        return List.copyOf(items);
    }

    public Instant getCreatedAt() {
        return createdAt;
    }

    public Instant getUpdatedAt() {
        return updatedAt;
    }

    public String getRejectionReason() {
        return rejectionReason;
    }

    public long getAggregateVersion() {
        return aggregateVersion;
    }
}
