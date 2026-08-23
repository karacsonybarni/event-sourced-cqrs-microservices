package com.karacsonybarni.orders.query.messaging;

import java.math.BigDecimal;
import java.time.Clock;
import java.time.Instant;
import java.util.List;
import java.util.UUID;

import com.karacsonybarni.orders.query.domain.OrderItemView;
import com.karacsonybarni.orders.query.domain.OrderView;
import com.karacsonybarni.orders.query.domain.OrderViewStatus;
import com.karacsonybarni.orders.query.infrastructure.OrderViewRepository;
import com.karacsonybarni.orders.query.infrastructure.ProcessedEvent;
import com.karacsonybarni.orders.query.infrastructure.ProcessedEventRepository;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.kafka.annotation.KafkaListener;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;
import tools.jackson.core.JacksonException;
import tools.jackson.databind.JsonNode;
import tools.jackson.databind.ObjectMapper;

@Component
public class OrderProjectionListener {

    private static final Logger LOGGER = LoggerFactory.getLogger(OrderProjectionListener.class);
    private static final String ORDER_CREATED = "OrderCreated.v1";
    private static final String ORDER_CANCELLED = "OrderCancelled.v1";

    private final ObjectMapper objectMapper;
    private final OrderViewRepository orderViewRepository;
    private final ProcessedEventRepository processedEventRepository;
    private final Clock clock;

    public OrderProjectionListener(
            ObjectMapper objectMapper,
            OrderViewRepository orderViewRepository,
            ProcessedEventRepository processedEventRepository,
            Clock clock) {
        this.objectMapper = objectMapper;
        this.orderViewRepository = orderViewRepository;
        this.processedEventRepository = processedEventRepository;
        this.clock = clock;
    }

    @KafkaListener(topics = "${orders.events.topic}")
    @Transactional
    public void project(String serializedEvent) throws JacksonException {
        JsonNode envelope = objectMapper.readTree(serializedEvent);
        UUID eventId = UUID.fromString(requiredText(envelope, "eventId"));
        if (processedEventRepository.existsById(eventId)) {
            LOGGER.debug("Ignoring duplicate event {}", eventId);
            return;
        }

        String eventType = requiredText(envelope, "eventType");
        UUID orderId = UUID.fromString(requiredText(envelope, "aggregateId"));
        long aggregateVersion = envelope.required("aggregateVersion").asLong();
        JsonNode payload = envelope.required("payload");

        switch (eventType) {
            case ORDER_CREATED -> applyCreated(orderId, aggregateVersion, payload);
            case ORDER_CANCELLED -> applyCancelled(orderId, aggregateVersion, payload);
            default -> throw new IllegalArgumentException("Unsupported event type: " + eventType);
        }

        processedEventRepository.save(new ProcessedEvent(eventId, clock.instant()));
        LOGGER.info("Projected {} event {} for order {}", eventType, eventId, orderId);
    }

    private void applyCreated(UUID orderId, long aggregateVersion, JsonNode payload) throws JacksonException {
        if (orderViewRepository.existsById(orderId)) {
            return;
        }
        CreatedPayload created = objectMapper.treeToValue(payload, CreatedPayload.class);
        List<OrderItemView> items = created.items().stream()
                .map(item -> new OrderItemView(item.productId(), item.quantity(), item.unitPrice()))
                .toList();
        var view = new OrderView(
                orderId,
                created.customerId(),
                OrderViewStatus.valueOf(created.status()),
                created.totalAmount(),
                items,
                created.createdAt(),
                aggregateVersion);
        orderViewRepository.save(view);
    }

    private void applyCancelled(UUID orderId, long aggregateVersion, JsonNode payload) throws JacksonException {
        CancelledPayload cancelled = objectMapper.treeToValue(payload, CancelledPayload.class);
        OrderView order = orderViewRepository.findById(orderId)
                .orElseThrow(() -> new IllegalStateException("Cannot cancel missing order projection " + orderId));
        order.cancel(cancelled.cancelledAt(), aggregateVersion);
    }

    private String requiredText(JsonNode node, String fieldName) {
        return node.required(fieldName).stringValue();
    }

    record CreatedPayload(
            String customerId,
            String status,
            BigDecimal totalAmount,
            List<ItemPayload> items,
            Instant createdAt) {
    }

    record ItemPayload(String productId, int quantity, BigDecimal unitPrice) {
    }

    record CancelledPayload(String status, Instant cancelledAt) {
    }
}
