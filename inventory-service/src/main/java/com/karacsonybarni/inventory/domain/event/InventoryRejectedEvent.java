package com.karacsonybarni.inventory.domain.event;

import java.time.Instant;

public record InventoryRejectedEvent(String reason, Instant rejectedAt) implements InventoryEvent {

    @Override
    public String type() {
        return INVENTORY_REJECTED;
    }

    @Override
    public Instant occurredAt() {
        return rejectedAt;
    }
}
