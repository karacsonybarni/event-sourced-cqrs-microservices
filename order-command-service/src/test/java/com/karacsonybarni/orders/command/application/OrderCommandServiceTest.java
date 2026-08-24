package com.karacsonybarni.orders.command.application;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.math.BigDecimal;
import java.time.Clock;
import java.time.Instant;
import java.time.ZoneOffset;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import com.karacsonybarni.orders.command.domain.Order;
import com.karacsonybarni.orders.command.domain.OrderLineItem;
import com.karacsonybarni.orders.command.eventstore.OrderEventStore;
import com.karacsonybarni.orders.command.infrastructure.CommandRequest;
import com.karacsonybarni.orders.command.infrastructure.CommandRequestRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

@ExtendWith(MockitoExtension.class)
class OrderCommandServiceTest {

    private static final Instant NOW = Instant.parse("2026-01-10T10:15:30Z");

    @Mock
    private OrderEventStore eventStore;

    @Mock
    private CommandRequestRepository commandRequestRepository;

    @Mock
    private CreateOrderCommandFingerprint commandFingerprint;

    private OrderCommandService service;

    @BeforeEach
    void setUp() {
        Clock clock = Clock.fixed(NOW, ZoneOffset.UTC);
        service = new OrderCommandService(eventStore, commandRequestRepository, commandFingerprint, clock);
    }

    @Test
    void createsOrderAsAnEventStream() {
        when(commandFingerprint.calculate(any())).thenReturn("fingerprint");
        when(commandRequestRepository.claim(any(), any(), any(), any())).thenReturn(1);
        var item = new CreateOrderCommand.Item("keyboard", 2, new BigDecimal("49.90"));
        var command = new CreateOrderCommand("customer-42", List.of(item));

        CommandResult result = service.create("create-42", command);

        ArgumentCaptor<Order> orderCaptor = ArgumentCaptor.forClass(Order.class);
        verify(eventStore).create(orderCaptor.capture());
        Order order = orderCaptor.getValue();
        assertThat(order.getTotalAmount()).isEqualByComparingTo("99.80");
        assertThat(order.getVersion()).isOne();
        assertThat(order.getUncommittedEvents()).hasSize(1);
        assertThat(result.orderId()).isEqualTo(order.getId());
        assertThat(result.replayed()).isFalse();
        verify(commandRequestRepository).claim("create-42", order.getId(), "fingerprint", NOW);
    }

    @Test
    void returnsOriginalOrderForRepeatedIdempotencyKeyWithoutAppendingAgain() {
        UUID orderId = UUID.randomUUID();
        Order existing = Order.create(
                orderId,
                "customer-42",
                List.of(new OrderLineItem("keyboard", 1, new BigDecimal("49.90"))),
                NOW);
        when(commandFingerprint.calculate(any())).thenReturn("fingerprint");
        when(commandRequestRepository.claim(any(), any(), any(), any())).thenReturn(0);
        when(commandRequestRepository.findById("create-42"))
                .thenReturn(Optional.of(new CommandRequest("create-42", orderId, "fingerprint", NOW)));
        when(eventStore.load(orderId)).thenReturn(existing);
        var command = new CreateOrderCommand("ignored", List.of());

        CommandResult result = service.create("create-42", command);

        assertThat(result.orderId()).isEqualTo(orderId);
        assertThat(result.replayed()).isTrue();
        verify(eventStore, never()).create(any());
        verify(eventStore, never()).append(any());
    }

    @Test
    void rejectsRepeatedIdempotencyKeyForDifferentCommand() {
        UUID orderId = UUID.randomUUID();
        when(commandFingerprint.calculate(any())).thenReturn("different-fingerprint");
        when(commandRequestRepository.claim(any(), any(), any(), any())).thenReturn(0);
        when(commandRequestRepository.findById("create-42"))
                .thenReturn(Optional.of(new CommandRequest("create-42", orderId, "original-fingerprint", NOW)));
        var item = new CreateOrderCommand.Item("monitor", 1, new BigDecimal("299.90"));
        var command = new CreateOrderCommand("different-customer", List.of(item));

        assertThatThrownBy(() -> service.create("create-42", command))
                .isInstanceOf(IdempotencyKeyConflictException.class)
                .hasMessageContaining("create-42");

        verify(eventStore, never()).load(any());
        verify(eventStore, never()).create(any());
        verify(eventStore, never()).append(any());
    }
}
