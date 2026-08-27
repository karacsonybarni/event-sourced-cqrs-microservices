package com.karacsonybarni.orders.activity;

import java.time.Instant;
import java.time.format.DateTimeParseException;
import java.util.UUID;

import tools.jackson.core.JacksonException;
import tools.jackson.databind.JsonNode;
import tools.jackson.databind.ObjectMapper;
import tools.jackson.databind.node.ObjectNode;

final class OrderActivityDocumentMapper {

    private final ObjectMapper objectMapper;

    OrderActivityDocumentMapper(ObjectMapper objectMapper) {
        this.objectMapper = objectMapper;
    }

    String map(String serializedEvent) throws JacksonException {
        JsonNode envelope = objectMapper.readTree(serializedEvent);
        String eventId = requiredText(envelope, "eventId");
        String orderId = requiredText(envelope, "aggregateId");
        String occurredAt = requiredText(envelope, "occurredAt");
        UUID.fromString(eventId);
        UUID.fromString(orderId);
        try {
            Instant.parse(occurredAt);
        } catch (DateTimeParseException exception) {
            throw new IllegalArgumentException("occurredAt must be an ISO-8601 instant", exception);
        }

        JsonNode aggregateVersionNode = envelope.required("aggregateVersion");
        if (!aggregateVersionNode.isIntegralNumber()) {
            throw new IllegalArgumentException("aggregateVersion must be an integer");
        }
        long aggregateVersion = aggregateVersionNode.asLong();
        if (aggregateVersion < 1) {
            throw new IllegalArgumentException("aggregateVersion must be positive");
        }

        JsonNode payload = envelope.required("payload");
        if (!payload.isObject()) {
            throw new IllegalArgumentException("payload must be a JSON object");
        }

        ObjectNode document = objectMapper.createObjectNode();
        document.put("id", eventId);
        document.put("orderId", orderId);
        document.put("eventType", requiredText(envelope, "eventType"));
        document.put("aggregateVersion", aggregateVersion);
        document.put("occurredAt", occurredAt);
        document.set("payload", payload.deepCopy());
        return objectMapper.writeValueAsString(document);
    }

    private String requiredText(JsonNode node, String fieldName) {
        JsonNode valueNode = node.required(fieldName);
        if (!valueNode.isString()) {
            throw new IllegalArgumentException(fieldName + " must be a string");
        }
        String value = valueNode.asString();
        if (value.isBlank()) {
            throw new IllegalArgumentException(fieldName + " must not be blank");
        }
        return value;
    }
}
