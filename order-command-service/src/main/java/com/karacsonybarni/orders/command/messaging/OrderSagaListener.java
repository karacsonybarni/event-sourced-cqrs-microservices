package com.karacsonybarni.orders.command.messaging;

import java.time.Clock;
import java.util.UUID;

import com.karacsonybarni.orders.command.application.OrderCommandService;
import com.karacsonybarni.orders.command.infrastructure.ProcessedInventoryEvent;
import com.karacsonybarni.orders.command.infrastructure.ProcessedInventoryEventRepository;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.kafka.annotation.KafkaListener;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;
import tools.jackson.core.JacksonException;
import tools.jackson.databind.JsonNode;
import tools.jackson.databind.ObjectMapper;

@Component
public class OrderSagaListener {

    private static final Logger LOGGER = LoggerFactory.getLogger(OrderSagaListener.class);
    private static final String INVENTORY_RESERVED = "InventoryReserved.v1";
    private static final String INVENTORY_REJECTED = "InventoryRejected.v1";
    private static final String INVENTORY_RELEASED = "InventoryReleased.v1";

    private final OrderCommandService orderCommandService;
    private final ProcessedInventoryEventRepository processedEventRepository;
    private final ObjectMapper objectMapper;
    private final Clock clock;

    public OrderSagaListener(
            OrderCommandService orderCommandService,
            ProcessedInventoryEventRepository processedEventRepository,
            ObjectMapper objectMapper,
            Clock clock) {
        this.orderCommandService = orderCommandService;
        this.processedEventRepository = processedEventRepository;
        this.objectMapper = objectMapper;
        this.clock = clock;
    }

    @KafkaListener(topics = "${inventory.events.topic}")
    @Transactional
    public void handle(String serializedEvent) throws JacksonException {
        JsonNode envelope = objectMapper.readTree(serializedEvent);
        UUID eventId = UUID.fromString(requiredText(envelope, "eventId"));
        if (processedEventRepository.existsById(eventId)) {
            LOGGER.debug("Ignoring duplicate inventory event {}", eventId);
            return;
        }

        String eventType = requiredText(envelope, "eventType");
        UUID orderId = UUID.fromString(requiredText(envelope, "aggregateId"));
        switch (eventType) {
            case INVENTORY_RESERVED -> orderCommandService.confirmInventoryReservation(orderId);
            case INVENTORY_REJECTED -> orderCommandService.rejectInventoryReservation(
                    orderId, requiredText(envelope.required("payload"), "reason"));
            case INVENTORY_RELEASED -> LOGGER.debug(
                    "Inventory release completed for cancelled order {}", orderId);
            default -> throw new IllegalArgumentException("Unsupported inventory event: " + eventType);
        }

        processedEventRepository.save(new ProcessedInventoryEvent(eventId, clock.instant()));
        LOGGER.info("Handled {} event {} for order {}", eventType, eventId, orderId);
    }

    private String requiredText(JsonNode node, String fieldName) {
        return node.required(fieldName).asString();
    }
}
