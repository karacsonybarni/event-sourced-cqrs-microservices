package com.karacsonybarni.orders.command.messaging;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.time.Clock;
import java.time.Instant;
import java.time.ZoneOffset;
import java.util.UUID;

import com.karacsonybarni.orders.command.application.OrderCommandService;
import com.karacsonybarni.orders.command.infrastructure.ProcessedInventoryEvent;
import com.karacsonybarni.orders.command.infrastructure.ProcessedInventoryEventRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import tools.jackson.databind.json.JsonMapper;

@ExtendWith(MockitoExtension.class)
class OrderSagaListenerTest {

    @Mock
    private OrderCommandService orderCommandService;

    @Mock
    private ProcessedInventoryEventRepository processedEventRepository;

    private OrderSagaListener listener;

    @BeforeEach
    void setUp() {
        Clock clock = Clock.fixed(Instant.parse("2026-01-10T10:15:30Z"), ZoneOffset.UTC);
        listener = new OrderSagaListener(
                orderCommandService,
                processedEventRepository,
                JsonMapper.builder().findAndAddModules().build(),
                clock);
    }

    @Test
    void reservationConfirmationAdvancesTheOrderSaga() throws Exception {
        UUID eventId = UUID.randomUUID();
        UUID orderId = UUID.randomUUID();
        when(processedEventRepository.existsById(eventId)).thenReturn(false);
        String event = envelope(eventId, orderId, "InventoryReserved.v1", "{\"status\":\"RESERVED\"}");

        listener.handle(event);

        verify(orderCommandService).confirmInventoryReservation(orderId);
        verify(processedEventRepository).save(any(ProcessedInventoryEvent.class));
    }

    @Test
    void rejectionReasonIsPreservedInTheOrderHistory() throws Exception {
        UUID eventId = UUID.randomUUID();
        UUID orderId = UUID.randomUUID();
        when(processedEventRepository.existsById(eventId)).thenReturn(false);
        String payload = "{\"status\":\"REJECTED\",\"reason\":\"Unknown product: keyboard\"}";
        String event = envelope(eventId, orderId, "InventoryRejected.v1", payload);

        listener.handle(event);

        verify(orderCommandService).rejectInventoryReservation(orderId, "Unknown product: keyboard");
        verify(processedEventRepository).save(any(ProcessedInventoryEvent.class));
    }

    @Test
    void duplicateInventoryEventDoesNotRepeatTheOrderTransition() throws Exception {
        UUID eventId = UUID.randomUUID();
        when(processedEventRepository.existsById(eventId)).thenReturn(true);
        String event = """
                {"eventId":"%s"}
                """.formatted(eventId);

        listener.handle(event);

        verify(orderCommandService, never()).confirmInventoryReservation(any());
        verify(orderCommandService, never()).rejectInventoryReservation(any(), any());
        verify(processedEventRepository, never()).save(any());
    }

    private String envelope(UUID eventId, UUID orderId, String eventType, String payload) {
        return """
                {
                  "eventId": "%s",
                  "eventType": "%s",
                  "aggregateId": "%s",
                  "payload": %s
                }
                """.formatted(eventId, eventType, orderId, payload);
    }
}
