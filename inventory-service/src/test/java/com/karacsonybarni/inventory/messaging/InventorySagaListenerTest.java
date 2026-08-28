package com.karacsonybarni.inventory.messaging;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.time.Clock;
import java.time.Instant;
import java.time.ZoneOffset;
import java.util.List;
import java.util.UUID;

import com.karacsonybarni.inventory.application.InventoryService;
import com.karacsonybarni.inventory.application.InventoryService.RequestedItem;
import com.karacsonybarni.inventory.infrastructure.ProcessedEvent;
import com.karacsonybarni.inventory.infrastructure.ProcessedEventRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import tools.jackson.databind.json.JsonMapper;

@ExtendWith(MockitoExtension.class)
class InventorySagaListenerTest {

    private static final Instant NOW = Instant.parse("2026-01-10T10:15:30Z");

    @Mock
    private InventoryService inventoryService;

    @Mock
    private ProcessedEventRepository processedEventRepository;

    private InventorySagaListener listener;

    @BeforeEach
    void setUp() {
        Clock clock = Clock.fixed(NOW, ZoneOffset.UTC);
        listener = new InventorySagaListener(
                inventoryService,
                processedEventRepository,
                JsonMapper.builder().findAndAddModules().build(),
                clock);
    }

    @Test
    void orderCreatedRequestsOneAtomicInventoryReservation() throws Exception {
        UUID eventId = UUID.randomUUID();
        UUID orderId = UUID.randomUUID();
        when(processedEventRepository.existsById(eventId)).thenReturn(false);
        String event = """
                {
                  "eventId": "%s",
                  "eventType": "OrderCreated.v1",
                  "aggregateId": "%s",
                  "payload": {
                    "items": [
                      {"productId": "keyboard", "quantity": 1},
                      {"productId": "mouse", "quantity": 2}
                    ]
                  }
                }
                """.formatted(eventId, orderId);

        listener.handle(event);

        verify(inventoryService).reserve(orderId, List.of(
                new RequestedItem("keyboard", 1),
                new RequestedItem("mouse", 2)));
        verify(processedEventRepository).save(any(ProcessedEvent.class));
    }

    @Test
    void duplicateOrderEventDoesNotRepeatInventoryWork() throws Exception {
        UUID eventId = UUID.randomUUID();
        when(processedEventRepository.existsById(eventId)).thenReturn(true);
        String event = """
                {"eventId":"%s"}
                """.formatted(eventId);

        listener.handle(event);

        verify(inventoryService, never()).reserve(any(), any());
        verify(inventoryService, never()).release(any());
        verify(processedEventRepository, never()).save(any());
    }

    @Test
    void orderCancellationRequestsInventoryCompensation() throws Exception {
        UUID eventId = UUID.randomUUID();
        UUID orderId = UUID.randomUUID();
        when(processedEventRepository.existsById(eventId)).thenReturn(false);
        String event = """
                {
                  "eventId": "%s",
                  "eventType": "OrderCancelled.v1",
                  "aggregateId": "%s",
                  "payload": {}
                }
                """.formatted(eventId, orderId);

        listener.handle(event);

        verify(inventoryService).release(orderId);
        verify(processedEventRepository).save(any(ProcessedEvent.class));
    }
}
