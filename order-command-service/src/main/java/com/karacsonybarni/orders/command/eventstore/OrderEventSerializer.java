package com.karacsonybarni.orders.command.eventstore;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.ArrayList;
import java.util.Map;
import java.util.UUID;

import com.karacsonybarni.orders.command.domain.OrderLineItem;
import com.karacsonybarni.orders.command.domain.event.OrderCancelledEvent;
import com.karacsonybarni.orders.command.domain.event.OrderConfirmedEvent;
import com.karacsonybarni.orders.command.domain.event.OrderCreatedEvent;
import com.karacsonybarni.orders.command.domain.event.OrderEvent;
import com.karacsonybarni.orders.command.domain.event.OrderRejectedEvent;
import org.springframework.stereotype.Component;
import tools.jackson.databind.JsonNode;
import tools.jackson.databind.ObjectMapper;
import tools.jackson.databind.node.ObjectNode;

@Component
public class OrderEventSerializer {

    static final String AGGREGATE_TYPE = "orders";

    private final ObjectMapper objectMapper;

    public OrderEventSerializer(ObjectMapper objectMapper) {
        this.objectMapper = objectMapper;
    }

    StoredOrderEvent serialize(UUID aggregateId, long aggregateVersion, OrderEvent event) {
        UUID eventId = UUID.randomUUID();
        ObjectNode envelope = objectMapper.createObjectNode();
        envelope.put("eventId", eventId.toString());
        envelope.put("eventType", event.type());
        envelope.put("aggregateId", aggregateId.toString());
        envelope.put("aggregateVersion", aggregateVersion);
        envelope.put("occurredAt", event.occurredAt().toString());
        envelope.set("payload", serializePayload(event));
        return new StoredOrderEvent(
                eventId,
                AGGREGATE_TYPE,
                aggregateId,
                aggregateVersion,
                event.type(),
                toMap(envelope),
                event.occurredAt());
    }

    OrderEvent deserialize(StoredOrderEvent storedEvent) {
        JsonNode payload = objectMapper.valueToTree(storedEvent.getPayload()).required("payload");
        return switch (storedEvent.getEventType()) {
            case OrderEvent.ORDER_CREATED -> deserializeCreated(payload);
            case OrderEvent.ORDER_CONFIRMED -> new OrderConfirmedEvent(
                    Instant.parse(requiredText(payload, "confirmedAt")));
            case OrderEvent.ORDER_REJECTED -> new OrderRejectedEvent(
                    requiredText(payload, "reason"),
                    Instant.parse(requiredText(payload, "rejectedAt")));
            case OrderEvent.ORDER_CANCELLED -> new OrderCancelledEvent(
                    Instant.parse(requiredText(payload, "cancelledAt")));
            default -> throw new IllegalArgumentException("Unsupported order event: " + storedEvent.getEventType());
        };
    }

    private ObjectNode serializePayload(OrderEvent event) {
        return switch (event) {
            case OrderCreatedEvent created -> serializeCreated(created);
            case OrderConfirmedEvent confirmed -> serializeConfirmed(confirmed);
            case OrderRejectedEvent rejected -> serializeRejected(rejected);
            case OrderCancelledEvent cancelled -> serializeCancelled(cancelled);
        };
    }

    private ObjectNode serializeCreated(OrderCreatedEvent event) {
        ObjectNode payload = objectMapper.createObjectNode();
        payload.put("customerId", event.customerId());
        payload.put("status", "CREATED");
        payload.put("totalAmount", event.totalAmount());
        var items = payload.putArray("items");
        event.items().forEach(item -> {
            var node = items.addObject();
            node.put("productId", item.productId());
            node.put("quantity", item.quantity());
            node.put("unitPrice", item.unitPrice());
        });
        payload.put("createdAt", event.createdAt().toString());
        return payload;
    }

    private ObjectNode serializeCancelled(OrderCancelledEvent event) {
        ObjectNode payload = objectMapper.createObjectNode();
        payload.put("status", "CANCELLED");
        payload.put("cancelledAt", event.cancelledAt().toString());
        return payload;
    }

    private ObjectNode serializeConfirmed(OrderConfirmedEvent event) {
        ObjectNode payload = objectMapper.createObjectNode();
        payload.put("status", "CONFIRMED");
        payload.put("confirmedAt", event.confirmedAt().toString());
        return payload;
    }

    private ObjectNode serializeRejected(OrderRejectedEvent event) {
        ObjectNode payload = objectMapper.createObjectNode();
        payload.put("status", "REJECTED");
        payload.put("reason", event.reason());
        payload.put("rejectedAt", event.rejectedAt().toString());
        return payload;
    }

    private OrderCreatedEvent deserializeCreated(JsonNode payload) {
        var items = new ArrayList<OrderLineItem>();
        payload.required("items").forEach(item -> {
            var orderItem = new OrderLineItem(
                    requiredText(item, "productId"),
                    item.required("quantity").asInt(),
                    new BigDecimal(requiredText(item, "unitPrice")));
            items.add(orderItem);
        });
        return new OrderCreatedEvent(
                requiredText(payload, "customerId"),
                new BigDecimal(requiredText(payload, "totalAmount")),
                items,
                Instant.parse(requiredText(payload, "createdAt")));
    }

    private String requiredText(JsonNode node, String fieldName) {
        return node.required(fieldName).asString();
    }

    @SuppressWarnings("unchecked")
    private Map<String, Object> toMap(ObjectNode envelope) {
        return objectMapper.convertValue(envelope, Map.class);
    }
}
