package com.karacsonybarni.inventory.application;

import static org.assertj.core.api.Assertions.assertThat;

import java.time.Clock;
import java.time.Instant;
import java.time.ZoneOffset;
import java.util.List;
import java.util.UUID;

import com.karacsonybarni.inventory.application.InventoryService.RequestedItem;
import com.karacsonybarni.inventory.domain.ReservationStatus;
import com.karacsonybarni.inventory.eventstore.InventoryEventSerializer;
import com.karacsonybarni.inventory.eventstore.InventoryEventStore;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.data.jpa.test.autoconfigure.DataJpaTest;
import org.springframework.boot.jdbc.test.autoconfigure.AutoConfigureTestDatabase;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Import;
import org.springframework.context.annotation.Primary;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;
import org.testcontainers.postgresql.PostgreSQLContainer;
import tools.jackson.databind.ObjectMapper;
import tools.jackson.databind.json.JsonMapper;

@Testcontainers
@DataJpaTest
@AutoConfigureTestDatabase(replace = AutoConfigureTestDatabase.Replace.NONE)
@Import({
    InventoryService.class,
    InventoryEventStore.class,
    InventoryEventSerializer.class,
    InventoryServicePostgresIntegrationTest.TestBeans.class
})
@Transactional(propagation = Propagation.NOT_SUPPORTED)
class InventoryServicePostgresIntegrationTest {

    private static final Instant NOW = Instant.parse("2026-01-10T10:15:30Z");

    @Container
    private static final PostgreSQLContainer POSTGRES = new PostgreSQLContainer("postgres:18-alpine");

    @Autowired
    private InventoryService service;

    @Autowired
    private InventoryEventStore eventStore;

    @Autowired
    private JdbcTemplate jdbcTemplate;

    @DynamicPropertySource
    static void databaseProperties(DynamicPropertyRegistry registry) {
        registry.add("spring.datasource.url", POSTGRES::getJdbcUrl);
        registry.add("spring.datasource.username", POSTGRES::getUsername);
        registry.add("spring.datasource.password", POSTGRES::getPassword);
    }

    @BeforeEach
    void resetInventory() {
        jdbcTemplate.execute("TRUNCATE TABLE processed_events, inventory_events, inventory_streams CASCADE");
        jdbcTemplate.update("UPDATE stock_items SET available_quantity = 100 WHERE product_id = 'mechanical-keyboard'");
        jdbcTemplate.update("UPDATE stock_items SET available_quantity = 200 WHERE product_id = 'wireless-mouse'");
    }

    @Test
    void reservesAllItemsAndPublishesTheOutcomeInTheSameDatabase() {
        UUID orderId = UUID.randomUUID();

        service.reserve(orderId, List.of(
                new RequestedItem("mechanical-keyboard", 1),
                new RequestedItem("wireless-mouse", 2)));

        assertThat(available("mechanical-keyboard")).isEqualTo(99);
        assertThat(available("wireless-mouse")).isEqualTo(198);
        assertThat(eventStore.load(orderId)).satisfies(reservation -> {
            assertThat(reservation.getStatus()).isEqualTo(ReservationStatus.RESERVED);
            assertThat(reservation.getItems()).hasSize(2);
            assertThat(reservation.getUncommittedEvents()).isEmpty();
        });
        assertThat(inventoryEventTypes(orderId)).containsExactly("InventoryReserved.v1");
    }

    @Test
    void rejectsTheWholeReservationWithoutPartiallyConsumingStock() {
        UUID orderId = UUID.randomUUID();

        service.reserve(orderId, List.of(
                new RequestedItem("mechanical-keyboard", 1),
                new RequestedItem("out-of-stock-item", 1)));

        assertThat(available("mechanical-keyboard")).isEqualTo(100);
        assertThat(eventStore.load(orderId)).satisfies(reservation -> {
            assertThat(reservation.getStatus()).isEqualTo(ReservationStatus.REJECTED);
            assertThat(reservation.getReason()).isEqualTo("Insufficient stock for out-of-stock-item");
        });
        assertThat(inventoryEventTypes(orderId)).containsExactly("InventoryRejected.v1");
    }

    @Test
    void rejectsDuplicateProductQuantitiesThatOverflowWithoutPoisoningTheSaga() {
        UUID orderId = UUID.randomUUID();

        service.reserve(orderId, List.of(
                new RequestedItem("mechanical-keyboard", Integer.MAX_VALUE),
                new RequestedItem("mechanical-keyboard", 1)));

        assertThat(available("mechanical-keyboard")).isEqualTo(100);
        assertThat(eventStore.load(orderId)).satisfies(reservation -> {
            assertThat(reservation.getStatus()).isEqualTo(ReservationStatus.REJECTED);
            assertThat(reservation.getReason()).isEqualTo("Requested quantity exceeds the supported maximum");
        });
        assertThat(inventoryEventTypes(orderId)).containsExactly("InventoryRejected.v1");
    }

    @Test
    void cancellationReleasesStockOnceAndPublishesOneCompensationEvent() {
        UUID orderId = UUID.randomUUID();
        service.reserve(orderId, List.of(new RequestedItem("mechanical-keyboard", 2)));

        service.release(orderId);
        service.release(orderId);

        assertThat(available("mechanical-keyboard")).isEqualTo(100);
        assertThat(eventStore.load(orderId))
                .extracting(reservation -> reservation.getStatus())
                .isEqualTo(ReservationStatus.RELEASED);
        assertThat(inventoryEventTypes(orderId))
                .containsExactly("InventoryReserved.v1", "InventoryReleased.v1");
    }

    private int available(String productId) {
        return jdbcTemplate.queryForObject(
                "SELECT available_quantity FROM stock_items WHERE product_id = ?", Integer.class, productId);
    }

    private List<String> inventoryEventTypes(UUID orderId) {
        return jdbcTemplate.queryForList(
                "SELECT event_type FROM inventory_events WHERE aggregate_id = ? ORDER BY aggregate_version",
                String.class,
                orderId);
    }

    @TestConfiguration(proxyBeanMethods = false)
    static class TestBeans {

        @Bean
        @Primary
        Clock fixedClock() {
            return Clock.fixed(NOW, ZoneOffset.UTC);
        }

        @Bean
        ObjectMapper objectMapper() {
            return JsonMapper.builder().findAndAddModules().build();
        }
    }
}
