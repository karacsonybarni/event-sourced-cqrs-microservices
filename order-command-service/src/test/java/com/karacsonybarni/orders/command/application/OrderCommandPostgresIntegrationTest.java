package com.karacsonybarni.orders.command.application;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import java.math.BigDecimal;
import java.time.Clock;
import java.time.Instant;
import java.time.ZoneOffset;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.concurrent.Callable;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;

import com.karacsonybarni.orders.command.domain.OrderStatus;
import com.karacsonybarni.orders.command.eventstore.OrderEventSerializer;
import com.karacsonybarni.orders.command.eventstore.OrderEventStore;
import com.karacsonybarni.orders.command.infrastructure.CommandRequestRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.data.jpa.test.autoconfigure.DataJpaTest;
import org.springframework.boot.jdbc.test.autoconfigure.AutoConfigureTestDatabase;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Import;
import org.springframework.context.annotation.Primary;
import org.springframework.dao.DataAccessException;
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
    OrderCommandService.class,
    OrderEventStore.class,
    OrderEventSerializer.class,
    CreateOrderCommandFingerprint.class,
    OrderCommandPostgresIntegrationTest.TestBeans.class
})
@Transactional(propagation = Propagation.NOT_SUPPORTED)
class OrderCommandPostgresIntegrationTest {

    private static final int CONCURRENT_CALLERS = 12;
    private static final Instant NOW = Instant.parse("2026-01-10T10:15:30Z");

    @Container
    private static final PostgreSQLContainer POSTGRES = new PostgreSQLContainer("postgres:18-alpine");

    @Autowired
    private OrderCommandService service;

    @Autowired
    private OrderEventStore eventStore;

    @Autowired
    private CommandRequestRepository commandRequestRepository;

    @Autowired
    private JdbcTemplate jdbcTemplate;

    @DynamicPropertySource
    static void databaseProperties(DynamicPropertyRegistry registry) {
        registry.add("spring.datasource.url", POSTGRES::getJdbcUrl);
        registry.add("spring.datasource.username", POSTGRES::getUsername);
        registry.add("spring.datasource.password", POSTGRES::getPassword);
    }

    @BeforeEach
    void clearDatabase() {
        jdbcTemplate.execute("TRUNCATE TABLE command_requests, order_events, aggregate_streams CASCADE");
    }

    @Test
    void concurrentCreateRetriesResolveToOneStreamAndOneEvent() throws Exception {
        var command = createCommand("customer-42", "keyboard", "49.90");

        List<CommandResult> results = runConcurrently(() -> service.create("concurrent-create", command));

        assertThat(results).extracting(CommandResult::orderId).containsOnly(results.getFirst().orderId());
        assertThat(results).filteredOn(result -> !result.replayed()).hasSize(1);
        assertThat(results).filteredOn(CommandResult::replayed).hasSize(CONCURRENT_CALLERS - 1);
        assertThat(countRows("aggregate_streams")).isOne();
        assertThat(commandRequestRepository.count()).isOne();
        assertThat(countRows("order_events")).isOne();
    }

    @Test
    void repeatedIdempotencyKeyRejectsDifferentCommand() {
        service.create("payload-bound-key", createCommand("first-customer", "keyboard", "49.90"));
        CreateOrderCommand differentCommand = createCommand("different-customer", "monitor", "299.90");

        assertThatThrownBy(() -> service.create("payload-bound-key", differentCommand))
                .isInstanceOf(IdempotencyKeyConflictException.class)
                .hasMessageContaining("payload-bound-key");

        assertThat(countRows("aggregate_streams")).isOne();
        assertThat(commandRequestRepository.count()).isOne();
        assertThat(countRows("order_events")).isOne();
    }

    @Test
    void concurrentCancellationRetriesAppendOneCancellationEvent() throws Exception {
        CommandResult created = service.create(
                "order-to-cancel", createCommand("customer-42", "keyboard", "49.90"));

        List<CommandResult> results = runConcurrently(() -> service.cancel(created.orderId()));

        assertThat(results).extracting(CommandResult::status).containsOnly(OrderStatus.CANCELLED);
        assertThat(eventStore.load(created.orderId())).satisfies(order -> {
            assertThat(order.getStatus()).isEqualTo(OrderStatus.CANCELLED);
            assertThat(order.getVersion()).isEqualTo(2);
            assertThat(order.getUncommittedEvents()).isEmpty();
        });
        assertThat(countRows("order_events")).isEqualTo(2);
        assertThat(jdbcTemplate.queryForObject(
                "SELECT current_version FROM aggregate_streams WHERE aggregate_id = ?",
                Long.class,
                created.orderId())).isEqualTo(2);
    }

    @Test
    void storedEventsUseContiguousVersionsAndVersionedEnvelopes() {
        CommandResult created = service.create(
                "ordered-events", createCommand("customer-42", "keyboard", "49.90"));
        service.cancel(created.orderId());

        List<Map<String, Object>> events = jdbcTemplate.queryForList("""
                SELECT aggregate_version, event_type, payload
                FROM order_events
                WHERE aggregate_id = ?
                ORDER BY aggregate_version
                """, created.orderId());

        assertThat(events).extracting(event -> event.get("aggregate_version")).containsExactly(1L, 2L);
        assertThat(events).extracting(event -> event.get("event_type"))
                .containsExactly("OrderCreated.v1", "OrderCancelled.v1");
        assertThat(events).allSatisfy(event -> assertThat(event.get("payload").toString())
                .contains("aggregateVersion", "eventId", "payload"));
    }

    @Test
    void databaseRejectsUpdatesAndDeletesFromEventStore() {
        CommandResult created = service.create(
                "append-only", createCommand("customer-42", "keyboard", "49.90"));

        assertThatThrownBy(() -> jdbcTemplate.update(
                "UPDATE order_events SET event_type = 'Changed' WHERE aggregate_id = ?",
                created.orderId()))
                .isInstanceOf(DataAccessException.class)
                .hasMessageContaining("order_events is append-only");
        assertThatThrownBy(() -> jdbcTemplate.update(
                "DELETE FROM order_events WHERE aggregate_id = ?",
                created.orderId()))
                .isInstanceOf(DataAccessException.class)
                .hasMessageContaining("order_events is append-only");
        assertThat(countRows("order_events")).isOne();
    }

    private long countRows(String table) {
        return jdbcTemplate.queryForObject("SELECT COUNT(*) FROM " + table, Long.class);
    }

    private static CreateOrderCommand createCommand(String customerId, String productId, String unitPrice) {
        var item = new CreateOrderCommand.Item(productId, 1, new BigDecimal(unitPrice));
        return new CreateOrderCommand(customerId, List.of(item));
    }

    private static <T> List<T> runConcurrently(Callable<T> operation) throws Exception {
        var executor = Executors.newFixedThreadPool(CONCURRENT_CALLERS);
        var ready = new CountDownLatch(CONCURRENT_CALLERS);
        var start = new CountDownLatch(1);
        var futures = new ArrayList<Future<T>>(CONCURRENT_CALLERS);
        try {
            for (int index = 0; index < CONCURRENT_CALLERS; index++) {
                futures.add(executor.submit(() -> {
                    ready.countDown();
                    if (!start.await(10, TimeUnit.SECONDS)) {
                        throw new IllegalStateException("Concurrent operation did not start in time");
                    }
                    return operation.call();
                }));
            }
            assertThat(ready.await(10, TimeUnit.SECONDS)).isTrue();
            start.countDown();

            var results = new ArrayList<T>(CONCURRENT_CALLERS);
            for (Future<T> future : futures) {
                results.add(future.get(20, TimeUnit.SECONDS));
            }
            return results;
        } finally {
            executor.shutdownNow();
            assertThat(executor.awaitTermination(10, TimeUnit.SECONDS)).isTrue();
        }
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
