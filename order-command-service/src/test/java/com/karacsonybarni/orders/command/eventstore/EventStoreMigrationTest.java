package com.karacsonybarni.orders.command.eventstore;

import static org.assertj.core.api.Assertions.assertThat;

import java.math.BigDecimal;
import java.sql.Timestamp;
import java.time.Instant;
import java.util.Map;
import java.util.UUID;

import org.flywaydb.core.Flyway;
import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DriverManagerDataSource;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;
import org.testcontainers.postgresql.PostgreSQLContainer;

@Testcontainers
class EventStoreMigrationTest {

    private static final Instant SAGA_ACTIVATION_AT = Instant.parse("2026-01-11T00:00:00.750123Z");

    @Container
    private static final PostgreSQLContainer POSTGRES = new PostgreSQLContainer("postgres:18-alpine");

    @Test
    void migratesExistingOrderStateToAReplayableEventStream() {
        Flyway v1Flyway = flyway("1");
        v1Flyway.migrate();
        JdbcTemplate jdbcTemplate = jdbcTemplate();
        UUID orderId = UUID.randomUUID();
        UUID grandfatheredOrderId = UUID.randomUUID();
        UUID postCutoverOrderId = UUID.randomUUID();
        Instant createdAt = Instant.parse("2026-01-10T10:15:30Z");
        Instant grandfatheredCreatedAt = Instant.parse("2026-01-11T00:00:00.750122Z");
        Instant cancelledAt = createdAt.plusSeconds(60);
        jdbcTemplate.update("""
                INSERT INTO orders (
                    id, customer_id, status, total_amount, created_at, updated_at, event_sequence, lock_version
                ) VALUES (?, ?, 'CANCELLED', ?, ?, ?, 2, 0)
                """,
                orderId,
                "migrated-customer",
                new BigDecimal("99.80"),
                Timestamp.from(createdAt),
                Timestamp.from(cancelledAt));
        jdbcTemplate.update("""
                INSERT INTO order_items (order_id, product_id, quantity, unit_price)
                VALUES (?, ?, ?, ?)
                """, orderId, "keyboard", 2, new BigDecimal("49.90"));
        flyway("2").migrate();

        insertCreatedStream(jdbcTemplate, grandfatheredOrderId, grandfatheredCreatedAt);
        insertCreatedStream(jdbcTemplate, postCutoverOrderId, Instant.parse("2026-01-11T00:00:00.750124Z"));

        flyway(null).migrate();

        assertThat(jdbcTemplate.queryForObject(
                "SELECT current_version FROM aggregate_streams WHERE aggregate_id = ?",
                Long.class,
                orderId)).isEqualTo(2);
        assertThat(jdbcTemplate.queryForList("""
                SELECT event_type
                FROM order_events
                WHERE aggregate_id = ?
                ORDER BY aggregate_version
                """, String.class, orderId))
                .containsExactly("OrderCreated.v1", "OrderCancelled.v1");
        assertThat(jdbcTemplate.queryForObject("""
                SELECT payload -> 'payload' ->> 'customerId'
                FROM order_events
                WHERE aggregate_id = ? AND aggregate_version = 1
                """, String.class, orderId)).isEqualTo("migrated-customer");
        assertThat(jdbcTemplate.queryForObject("SELECT to_regclass('public.orders')", String.class)).isNull();
        assertThat(jdbcTemplate.queryForObject("SELECT to_regclass('public.outbox_events')", String.class)).isNull();
        assertThat(jdbcTemplate.queryForObject(
                "SELECT current_version FROM aggregate_streams WHERE aggregate_id = ?",
                Long.class,
                grandfatheredOrderId)).isEqualTo(2);
        assertThat(jdbcTemplate.queryForList("""
                SELECT event_type
                FROM order_events
                WHERE aggregate_id = ?
                ORDER BY aggregate_version
                """, String.class, grandfatheredOrderId))
                .containsExactly("OrderCreated.v1", "OrderConfirmed.v1");
        String confirmedAt = jdbcTemplate.queryForObject("""
                SELECT payload -> 'payload' ->> 'confirmedAt'
                FROM order_events
                WHERE aggregate_id = ? AND aggregate_version = 2
                """, String.class, grandfatheredOrderId);
        assertThat(Instant.parse(confirmedAt)).isEqualTo(grandfatheredCreatedAt);
        assertThat(jdbcTemplate.queryForObject("""
                SELECT payload -> 'payload' ->> 'status'
                FROM order_events
                WHERE aggregate_id = ? AND aggregate_version = 2
                """, String.class, grandfatheredOrderId)).isEqualTo("CONFIRMED");
        assertThat(jdbcTemplate.queryForObject(
                "SELECT current_version FROM aggregate_streams WHERE aggregate_id = ?",
                Long.class,
                postCutoverOrderId)).isOne();
        assertThat(jdbcTemplate.queryForList(
                "SELECT event_type FROM order_events WHERE aggregate_id = ?",
                String.class,
                postCutoverOrderId)).containsExactly("OrderCreated.v1");
        assertThat(jdbcTemplate.queryForObject("""
                SELECT activation_at
                FROM saga_configuration
                WHERE configuration_key = 'inventory-saga-activation'
                """, Instant.class)).isEqualTo(SAGA_ACTIVATION_AT);
    }

    private void insertCreatedStream(JdbcTemplate jdbcTemplate, UUID orderId, Instant occurredAt) {
        UUID eventId = UUID.randomUUID();
        Timestamp timestamp = Timestamp.from(occurredAt);
        jdbcTemplate.update("""
                INSERT INTO aggregate_streams (aggregate_id, aggregate_type, current_version)
                VALUES (?, 'orders', 1)
                """, orderId);
        jdbcTemplate.update("""
                INSERT INTO order_events (
                    event_id, aggregate_type, aggregate_id, aggregate_version,
                    event_type, payload, occurred_at
                ) VALUES (?, 'orders', ?, 1, 'OrderCreated.v1',
                    jsonb_build_object(
                        'eventId', ?::text,
                        'eventType', 'OrderCreated.v1',
                        'aggregateId', ?::text,
                        'aggregateVersion', 1,
                        'occurredAt', ?::text,
                        'payload', jsonb_build_object(
                            'customerId', 'migration-customer',
                            'status', 'CREATED',
                            'totalAmount', 249.90,
                            'items', jsonb_build_array(jsonb_build_object(
                                'productId', 'monitor', 'quantity', 1, 'unitPrice', 249.90
                            )),
                            'createdAt', ?::text
                        )
                    ), ?)
                """,
                eventId,
                orderId,
                eventId,
                orderId,
                timestamp,
                timestamp,
                timestamp);
    }

    private Flyway flyway(String target) {
        var configuration = Flyway.configure()
                .placeholders(Map.of("sagaActivationAt", SAGA_ACTIVATION_AT.toString()))
                .dataSource(POSTGRES.getJdbcUrl(), POSTGRES.getUsername(), POSTGRES.getPassword());
        if (target != null) {
            configuration.target(target);
        }
        return configuration.load();
    }

    private JdbcTemplate jdbcTemplate() {
        var dataSource = new DriverManagerDataSource(
                POSTGRES.getJdbcUrl(), POSTGRES.getUsername(), POSTGRES.getPassword());
        return new JdbcTemplate(dataSource);
    }
}
