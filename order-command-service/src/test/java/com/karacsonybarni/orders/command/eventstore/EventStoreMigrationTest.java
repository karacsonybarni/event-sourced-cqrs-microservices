package com.karacsonybarni.orders.command.eventstore;

import static org.assertj.core.api.Assertions.assertThat;

import java.math.BigDecimal;
import java.sql.Timestamp;
import java.time.Instant;
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

    @Container
    private static final PostgreSQLContainer POSTGRES = new PostgreSQLContainer("postgres:18-alpine");

    @Test
    void migratesExistingOrderStateToAReplayableEventStream() {
        Flyway v1Flyway = flyway("1");
        v1Flyway.migrate();
        JdbcTemplate jdbcTemplate = jdbcTemplate();
        UUID orderId = UUID.randomUUID();
        Instant createdAt = Instant.parse("2026-01-10T10:15:30Z");
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
    }

    private Flyway flyway(String target) {
        var configuration = Flyway.configure()
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
