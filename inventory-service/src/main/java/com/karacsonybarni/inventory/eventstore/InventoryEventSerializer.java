package com.karacsonybarni.inventory.eventstore;

import java.time.Instant;
import java.util.ArrayList;
import java.util.Map;
import java.util.UUID;

import com.karacsonybarni.inventory.domain.ReservedItem;
import com.karacsonybarni.inventory.domain.event.InventoryEvent;
import com.karacsonybarni.inventory.domain.event.InventoryRejectedEvent;
import com.karacsonybarni.inventory.domain.event.InventoryReleasedEvent;
import com.karacsonybarni.inventory.domain.event.InventoryReservedEvent;
import org.springframework.stereotype.Component;
import tools.jackson.databind.JsonNode;
import tools.jackson.databind.ObjectMapper;
import tools.jackson.databind.node.ObjectNode;

@Component
public class InventoryEventSerializer {

    static final String AGGREGATE_TYPE = "inventory";

    private final ObjectMapper objectMapper;

    public InventoryEventSerializer(ObjectMapper objectMapper) {
        this.objectMapper = objectMapper;
    }

    StoredInventoryEvent serialize(UUID aggregateId, long aggregateVersion, InventoryEvent event) {
        UUID eventId = UUID.randomUUID();
        ObjectNode envelope = objectMapper.createObjectNode();
        envelope.put("eventId", eventId.toString());
        envelope.put("eventType", event.type());
        envelope.put("aggregateId", aggregateId.toString());
        envelope.put("aggregateVersion", aggregateVersion);
        envelope.put("occurredAt", event.occurredAt().toString());
        envelope.set("payload", serializePayload(event));
        return new StoredInventoryEvent(
                eventId,
                AGGREGATE_TYPE,
                aggregateId,
                aggregateVersion,
                event.type(),
                toMap(envelope),
                event.occurredAt());
    }

    InventoryEvent deserialize(StoredInventoryEvent storedEvent) {
        JsonNode payload = objectMapper.valueToTree(storedEvent.getPayload()).required("payload");
        return switch (storedEvent.getEventType()) {
            case InventoryEvent.INVENTORY_RESERVED -> deserializeReserved(payload);
            case InventoryEvent.INVENTORY_REJECTED -> new InventoryRejectedEvent(
                    requiredText(payload, "reason"),
                    Instant.parse(requiredText(payload, "rejectedAt")));
            case InventoryEvent.INVENTORY_RELEASED -> new InventoryReleasedEvent(
                    Instant.parse(requiredText(payload, "releasedAt")));
            default -> throw new IllegalArgumentException(
                    "Unsupported inventory event: " + storedEvent.getEventType());
        };
    }

    private ObjectNode serializePayload(InventoryEvent event) {
        return switch (event) {
            case InventoryReservedEvent reserved -> serializeReserved(reserved);
            case InventoryRejectedEvent rejected -> serializeRejected(rejected);
            case InventoryReleasedEvent released -> serializeReleased(released);
        };
    }

    private ObjectNode serializeReserved(InventoryReservedEvent event) {
        ObjectNode payload = objectMapper.createObjectNode();
        payload.put("status", "RESERVED");
        var items = payload.putArray("items");
        event.items().forEach(item -> {
            ObjectNode node = items.addObject();
            node.put("productId", item.productId());
            node.put("quantity", item.quantity());
        });
        payload.put("reservedAt", event.reservedAt().toString());
        return payload;
    }

    private ObjectNode serializeRejected(InventoryRejectedEvent event) {
        ObjectNode payload = objectMapper.createObjectNode();
        payload.put("status", "REJECTED");
        payload.put("reason", event.reason());
        payload.put("rejectedAt", event.rejectedAt().toString());
        return payload;
    }

    private ObjectNode serializeReleased(InventoryReleasedEvent event) {
        ObjectNode payload = objectMapper.createObjectNode();
        payload.put("status", "RELEASED");
        payload.put("releasedAt", event.releasedAt().toString());
        return payload;
    }

    private InventoryReservedEvent deserializeReserved(JsonNode payload) {
        var items = new ArrayList<ReservedItem>();
        payload.required("items").forEach(item -> items.add(new ReservedItem(
                requiredText(item, "productId"),
                item.required("quantity").asInt())));
        return new InventoryReservedEvent(
                items,
                Instant.parse(requiredText(payload, "reservedAt")));
    }

    private String requiredText(JsonNode node, String fieldName) {
        return node.required(fieldName).asString();
    }

    @SuppressWarnings("unchecked")
    private Map<String, Object> toMap(ObjectNode envelope) {
        return objectMapper.convertValue(envelope, Map.class);
    }
}
