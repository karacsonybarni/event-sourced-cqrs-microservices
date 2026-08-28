package com.karacsonybarni.inventory.domain.event;

import java.time.Instant;

public sealed interface InventoryEvent permits
        InventoryReservedEvent,
        InventoryRejectedEvent,
        InventoryReleasedEvent {

    String INVENTORY_RESERVED = "InventoryReserved.v1";
    String INVENTORY_REJECTED = "InventoryRejected.v1";
    String INVENTORY_RELEASED = "InventoryReleased.v1";

    String type();

    Instant occurredAt();
}
