package com.karacsonybarni.orders.command.infrastructure;

import java.time.Instant;
import java.util.UUID;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface CommandRequestRepository extends JpaRepository<CommandRequest, String> {

    @Modifying
    @Query(value = """
            INSERT INTO command_requests (idempotency_key, order_id, request_fingerprint, created_at)
            VALUES (:idempotencyKey, :orderId, :requestFingerprint, :createdAt)
            ON CONFLICT (idempotency_key) DO NOTHING
            """, nativeQuery = true)
    int claim(
            @Param("idempotencyKey") String idempotencyKey,
            @Param("orderId") UUID orderId,
            @Param("requestFingerprint") String requestFingerprint,
            @Param("createdAt") Instant createdAt);
}
