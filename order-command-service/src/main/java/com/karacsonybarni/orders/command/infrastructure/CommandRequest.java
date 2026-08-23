package com.karacsonybarni.orders.command.infrastructure;

import java.time.Instant;
import java.util.UUID;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

@Entity
@Table(name = "command_requests")
public class CommandRequest {

    @Id
    @Column(name = "idempotency_key", length = 100)
    private String idempotencyKey;

    @Column(name = "order_id", nullable = false)
    private UUID orderId;

    @Column(name = "request_fingerprint", nullable = false, length = 64)
    private String requestFingerprint;

    @Column(name = "created_at", nullable = false)
    private Instant createdAt;

    protected CommandRequest() {
    }

    public CommandRequest(String idempotencyKey, UUID orderId, String requestFingerprint, Instant createdAt) {
        this.idempotencyKey = idempotencyKey;
        this.orderId = orderId;
        this.requestFingerprint = requestFingerprint;
        this.createdAt = createdAt;
    }

    public UUID getOrderId() {
        return orderId;
    }

    public String getRequestFingerprint() {
        return requestFingerprint;
    }
}
