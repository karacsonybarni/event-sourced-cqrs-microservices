package com.karacsonybarni.orders.query.messaging;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.time.Clock;
import java.time.Instant;
import java.time.ZoneOffset;
import java.util.Optional;
import java.util.UUID;

import com.karacsonybarni.orders.query.domain.OrderView;
import com.karacsonybarni.orders.query.infrastructure.OrderViewRepository;
import com.karacsonybarni.orders.query.infrastructure.ProcessedEvent;
import com.karacsonybarni.orders.query.infrastructure.ProcessedEventRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import tools.jackson.databind.json.JsonMapper;

@ExtendWith(MockitoExtension.class)
class OrderProjectionListenerTest {

    private static final Instant NOW = Instant.parse("2026-01-10T10:15:30Z");

    @Mock
    private OrderViewRepository orderViewRepository;

    @Mock
    private ProcessedEventRepository processedEventRepository;

    private OrderProjectionListener listener;

    @BeforeEach
    void setUp() {
        var objectMapper = JsonMapper.builder().findAndAddModules().build();
        Clock clock = Clock.fixed(NOW, ZoneOffset.UTC);
        listener = new OrderProjectionListener(
                objectMapper, orderViewRepository, processedEventRepository, clock);
    }

    @Test
    void projectsCreatedEventIntoQueryOptimizedModel() throws Exception {
        UUID eventId = UUID.randomUUID();
        UUID orderId = UUID.randomUUID();
        when(processedEventRepository.existsById(eventId)).thenReturn(false);
        when(orderViewRepository.existsById(orderId)).thenReturn(false);
        String event = """
                {
                  "eventId": "%s",
                  "eventType": "OrderCreated.v1",
                  "aggregateId": "%s",
                  "aggregateVersion": 1,
                  "occurredAt": "2026-01-10T10:15:30Z",
                  "payload": {
                    "customerId": "customer-42",
                    "status": "CREATED",
                    "totalAmount": 99.80,
                    "items": [{"productId": "keyboard", "quantity": 2, "unitPrice": 49.90}],
                    "createdAt": "2026-01-10T10:15:30Z"
                  }
                }
                """.formatted(eventId, orderId);

        listener.project(event);

        ArgumentCaptor<OrderView> viewCaptor = ArgumentCaptor.forClass(OrderView.class);
        verify(orderViewRepository).save(viewCaptor.capture());
        OrderView projected = viewCaptor.getValue();
        assertThat(projected.getId()).isEqualTo(orderId);
        assertThat(projected.getTotalAmount()).isEqualByComparingTo("99.80");
        assertThat(projected.getItems()).hasSize(1);
        verify(processedEventRepository).save(any(ProcessedEvent.class));
    }

    @Test
    void duplicateEventDoesNotMutateProjection() throws Exception {
        UUID eventId = UUID.randomUUID();
        when(processedEventRepository.existsById(eventId)).thenReturn(true);
        String duplicateEvent = """
                {"eventId":"%s","eventType":"OrderCreated.v1"}
                """.formatted(eventId);

        listener.project(duplicateEvent);

        verify(orderViewRepository, never()).save(any());
        verify(processedEventRepository, never()).save(any());
    }

    @Test
    void appliesCancellationOnlyAfterCreateProjectionExists() throws Exception {
        UUID eventId = UUID.randomUUID();
        UUID orderId = UUID.randomUUID();
        var projectedOrder = new OrderView(
                orderId,
                "customer-42",
                com.karacsonybarni.orders.query.domain.OrderViewStatus.CREATED,
                new java.math.BigDecimal("99.80"),
                java.util.List.of(),
                NOW,
                1);
        when(processedEventRepository.existsById(eventId)).thenReturn(false);
        when(orderViewRepository.findById(orderId)).thenReturn(Optional.of(projectedOrder));
        String cancellation = """
                {
                  "eventId": "%s",
                  "eventType": "OrderCancelled.v1",
                  "aggregateId": "%s",
                  "aggregateVersion": 2,
                  "occurredAt": "2026-01-10T10:16:30Z",
                  "payload": {"status": "CANCELLED", "cancelledAt": "2026-01-10T10:16:30Z"}
                }
                """.formatted(eventId, orderId);

        listener.project(cancellation);

        assertThat(projectedOrder.getStatus().name()).isEqualTo("CANCELLED");
        assertThat(projectedOrder.getAggregateVersion()).isEqualTo(2);
        verify(processedEventRepository).save(any(ProcessedEvent.class));
    }

    @Test
    void projectsSagaConfirmationAtTheNextAggregateVersion() throws Exception {
        UUID eventId = UUID.randomUUID();
        UUID orderId = UUID.randomUUID();
        OrderView projectedOrder = createdOrder(orderId);
        when(processedEventRepository.existsById(eventId)).thenReturn(false);
        when(orderViewRepository.findById(orderId)).thenReturn(Optional.of(projectedOrder));
        String confirmation = """
                {
                  "eventId": "%s",
                  "eventType": "OrderConfirmed.v1",
                  "aggregateId": "%s",
                  "aggregateVersion": 2,
                  "occurredAt": "2026-01-10T10:16:00Z",
                  "payload": {"status": "CONFIRMED", "confirmedAt": "2026-01-10T10:16:00Z"}
                }
                """.formatted(eventId, orderId);

        listener.project(confirmation);

        assertThat(projectedOrder.getStatus().name()).isEqualTo("CONFIRMED");
        assertThat(projectedOrder.getAggregateVersion()).isEqualTo(2);
        verify(processedEventRepository).save(any(ProcessedEvent.class));
    }

    @Test
    void projectsSagaRejectionReason() throws Exception {
        UUID eventId = UUID.randomUUID();
        UUID orderId = UUID.randomUUID();
        OrderView projectedOrder = createdOrder(orderId);
        when(processedEventRepository.existsById(eventId)).thenReturn(false);
        when(orderViewRepository.findById(orderId)).thenReturn(Optional.of(projectedOrder));
        String rejection = """
                {
                  "eventId": "%s",
                  "eventType": "OrderRejected.v1",
                  "aggregateId": "%s",
                  "aggregateVersion": 2,
                  "occurredAt": "2026-01-10T10:16:00Z",
                  "payload": {
                    "status": "REJECTED",
                    "reason": "Insufficient stock for keyboard",
                    "rejectedAt": "2026-01-10T10:16:00Z"
                  }
                }
                """.formatted(eventId, orderId);

        listener.project(rejection);

        assertThat(projectedOrder.getStatus().name()).isEqualTo("REJECTED");
        assertThat(projectedOrder.getRejectionReason()).isEqualTo("Insufficient stock for keyboard");
        verify(processedEventRepository).save(any(ProcessedEvent.class));
    }

    private OrderView createdOrder(UUID orderId) {
        return new OrderView(
                orderId,
                "customer-42",
                com.karacsonybarni.orders.query.domain.OrderViewStatus.CREATED,
                new java.math.BigDecimal("99.80"),
                java.util.List.of(),
                NOW,
                1);
    }
}
