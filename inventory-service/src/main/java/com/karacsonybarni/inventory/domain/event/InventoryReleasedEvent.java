package com.karacsonybarni.inventory.domain.event;

import java.time.Instant;

public record InventoryReleasedEvent(Instant releasedAt) implements InventoryEvent {

    @Override
    public String type() {
        return INVENTORY_RELEASED;
    }

    @Override
    public Instant occurredAt() {
        return releasedAt;
    }
}
