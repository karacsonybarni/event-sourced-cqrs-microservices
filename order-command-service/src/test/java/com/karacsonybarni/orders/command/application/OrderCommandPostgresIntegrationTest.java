package com.karacsonybarni.orders.command.application;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import java.math.BigDecimal;
import java.time.Clock;
import java.time.Instant;
import java.time.ZoneOffset;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;
import java.util.concurrent.Callable;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;

import com.karacsonybarni.orders.command.domain.OrderStatus;
import com.karacsonybarni.orders.command.infrastructure.CommandRequestRepository;
import com.karacsonybarni.orders.command.infrastructure.OrderRepository;
import com.karacsonybarni.orders.command.messaging.OrderEventFactory;
import com.karacsonybarni.orders.command.outbox.OutboxEvent;
import com.karacsonybarni.orders.command.outbox.OutboxEventRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.data.jpa.test.autoconfigure.DataJpaTest;
import org.springframework.boot.jdbc.test.autoconfigure.AutoConfigureTestDatabase;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Import;
import org.springframework.context.annotation.Primary;
import org.springframework.data.domain.PageRequest;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.support.TransactionTemplate;
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
    OrderEventFactory.class,
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
    private OrderRepository orderRepository;

    @Autowired
    private CommandRequestRepository commandRequestRepository;

    @Autowired
    private OutboxEventRepository outboxEventRepository;

    @Autowired
    private JdbcTemplate jdbcTemplate;

    @Autowired
    private PlatformTransactionManager transactionManager;

    @DynamicPropertySource
    static void databaseProperties(DynamicPropertyRegistry registry) {
        registry.add("spring.datasource.url", POSTGRES::getJdbcUrl);
        registry.add("spring.datasource.username", POSTGRES::getUsername);
        registry.add("spring.datasource.password", POSTGRES::getPassword);
    }

    @BeforeEach
    void clearDatabase() {
        jdbcTemplate.execute(
                "TRUNCATE TABLE command_requests, outbox_events, order_items, orders RESTART IDENTITY CASCADE");
    }

    @Test
    void concurrentCreateRetriesResolveToOneOrderAndOneOutboxEvent() throws Exception {
        var command = createCommand("customer-42", "keyboard", "49.90");

        List<CommandResult> results = runConcurrently(() -> service.create("concurrent-create", command));

        assertThat(results).extracting(CommandResult::orderId).containsOnly(results.getFirst().orderId());
        assertThat(results).filteredOn(result -> !result.replayed()).hasSize(1);
        assertThat(results).filteredOn(CommandResult::replayed).hasSize(CONCURRENT_CALLERS - 1);
        assertThat(orderRepository.count()).isOne();
        assertThat(commandRequestRepository.count()).isOne();
        assertThat(outboxEventRepository.count()).isOne();
    }

    @Test
    void repeatedIdempotencyKeyRejectsDifferentCommand() {
        CreateOrderCommand firstCommand = createCommand("first-customer", "keyboard", "49.90");
        service.create("payload-bound-key", firstCommand);
        CreateOrderCommand differentCommand = createCommand("different-customer", "monitor", "299.90");

        assertThatThrownBy(() -> service.create("payload-bound-key", differentCommand))
                .isInstanceOf(IdempotencyKeyConflictException.class)
                .hasMessageContaining("payload-bound-key");

        assertThat(orderRepository.count()).isOne();
        assertThat(commandRequestRepository.count()).isOne();
        assertThat(outboxEventRepository.count()).isOne();
    }

    @Test
    void concurrentCancellationRetriesCreateOneCancellationEvent() throws Exception {
        CreateOrderCommand command = createCommand("customer-42", "keyboard", "49.90");
        CommandResult created = service.create("order-to-cancel", command);

        List<CommandResult> results = runConcurrently(() -> service.cancel(created.orderId()));

        assertThat(results).extracting(CommandResult::status).containsOnly(OrderStatus.CANCELLED);
        assertThat(orderRepository.findById(created.orderId())).hasValueSatisfying(order -> {
            assertThat(order.getStatus()).isEqualTo(OrderStatus.CANCELLED);
            assertThat(order.getEventSequence()).isEqualTo(2);
        });
        assertThat(outboxEventRepository.count()).isEqualTo(2);
    }

    @Test
    void unpublishedEventsUseDatabaseRelaySequenceWhenTimestampsAreInvertedOrEqual() {
        UUID firstEventId = UUID.randomUUID();
        UUID secondEventId = UUID.randomUUID();
        UUID thirdEventId = UUID.randomUUID();
        Instant later = NOW.plusSeconds(60);
        var first = outboxEvent(firstEventId, later);
        var second = outboxEvent(secondEventId, NOW);
        var third = outboxEvent(thirdEventId, NOW);
        var transaction = new TransactionTemplate(transactionManager);
        var firstPage = PageRequest.of(0, 10);

        List<UUID> eventIds = transaction.execute(status -> {
            outboxEventRepository.saveAndFlush(first);
            outboxEventRepository.saveAndFlush(second);
            outboxEventRepository.saveAndFlush(third);
            return outboxEventRepository.findUnpublished(firstPage).stream()
                    .map(OutboxEvent::getEventId)
                    .toList();
        });

        assertThat(eventIds).containsExactly(firstEventId, secondEventId, thirdEventId);
    }

    private static CreateOrderCommand createCommand(String customerId, String productId, String unitPrice) {
        var item = new CreateOrderCommand.Item(productId, 1, new BigDecimal(unitPrice));
        return new CreateOrderCommand(customerId, List.of(item));
    }

    private static OutboxEvent outboxEvent(UUID eventId, Instant occurredAt) {
        return new OutboxEvent(
                eventId, UUID.randomUUID(), OrderEventFactory.ORDER_CREATED, "{}", occurredAt);
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
