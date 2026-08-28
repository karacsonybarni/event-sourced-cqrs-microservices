package com.karacsonybarni.inventory.messaging;

import java.time.Clock;
import java.util.List;
import java.util.UUID;

import com.karacsonybarni.inventory.application.InventoryService;
import com.karacsonybarni.inventory.application.InventoryService.RequestedItem;
import com.karacsonybarni.inventory.infrastructure.ProcessedEvent;
import com.karacsonybarni.inventory.infrastructure.ProcessedEventRepository;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.kafka.annotation.KafkaListener;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;
import tools.jackson.core.JacksonException;
import tools.jackson.databind.JsonNode;
import tools.jackson.databind.ObjectMapper;

@Component
public class InventorySagaListener {

    private static final Logger LOGGER = LoggerFactory.getLogger(InventorySagaListener.class);
    private static final String ORDER_CREATED = "OrderCreated.v1";
    private static final String ORDER_CANCELLED = "OrderCancelled.v1";
    private static final String ORDER_CONFIRMED = "OrderConfirmed.v1";
    private static final String ORDER_REJECTED = "OrderRejected.v1";

    private final InventoryService inventoryService;
    private final ProcessedEventRepository processedEventRepository;
    private final ObjectMapper objectMapper;
    private final Clock clock;

    public InventorySagaListener(
            InventoryService inventoryService,
            ProcessedEventRepository processedEventRepository,
            ObjectMapper objectMapper,
            Clock clock) {
        this.inventoryService = inventoryService;
        this.processedEventRepository = processedEventRepository;
        this.objectMapper = objectMapper;
        this.clock = clock;
    }

    @KafkaListener(topics = "${orders.events.topic}")
    @Transactional
    public void handle(String serializedEvent) throws JacksonException {
        JsonNode envelope = objectMapper.readTree(serializedEvent);
        UUID eventId = UUID.fromString(requiredText(envelope, "eventId"));
        if (processedEventRepository.existsById(eventId)) {
            LOGGER.debug("Ignoring duplicate order event {}", eventId);
            return;
        }

        String eventType = requiredText(envelope, "eventType");
        UUID orderId = UUID.fromString(requiredText(envelope, "aggregateId"));
        switch (eventType) {
            case ORDER_CREATED -> inventoryService.reserve(orderId, requestedItems(envelope.required("payload")));
            case ORDER_CANCELLED -> inventoryService.release(orderId);
            case ORDER_CONFIRMED, ORDER_REJECTED -> LOGGER.debug(
                    "Order event {} requires no inventory action for order {}", eventType, orderId);
            default -> throw new IllegalArgumentException("Unsupported order event: " + eventType);
        }

        processedEventRepository.save(new ProcessedEvent(eventId, clock.instant()));
        LOGGER.info("Handled {} event {} for inventory reservation {}", eventType, eventId, orderId);
    }

    private List<RequestedItem> requestedItems(JsonNode payload) {
        return payload.required("items").valueStream()
                .map(item -> new RequestedItem(
                        requiredText(item, "productId"),
                        item.required("quantity").asInt()))
                .toList();
    }

    private String requiredText(JsonNode node, String fieldName) {
        return node.required(fieldName).asString();
    }
}
