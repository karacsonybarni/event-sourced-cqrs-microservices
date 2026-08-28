package com.karacsonybarni.inventory.domain.event;

import java.time.Instant;
import java.util.List;

import com.karacsonybarni.inventory.domain.ReservedItem;

public record InventoryReservedEvent(List<ReservedItem> items, Instant reservedAt) implements InventoryEvent {

    public InventoryReservedEvent {
        items = List.copyOf(items);
    }

    @Override
    public String type() {
        return INVENTORY_RESERVED;
    }

    @Override
    public Instant occurredAt() {
        return reservedAt;
    }
}
