package com.karacsonybarni.inventory.domain;

import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;

import com.karacsonybarni.inventory.domain.event.InventoryEvent;
import com.karacsonybarni.inventory.domain.event.InventoryRejectedEvent;
import com.karacsonybarni.inventory.domain.event.InventoryReleasedEvent;
import com.karacsonybarni.inventory.domain.event.InventoryReservedEvent;

public final class InventoryReservation {

    private final UUID orderId;
    private final List<InventoryEvent> uncommittedEvents = new ArrayList<>();

    private ReservationStatus status;
    private List<ReservedItem> items = List.of();
    private String reason;
    private long version;

    private InventoryReservation(UUID orderId) {
        this.orderId = orderId;
    }

    public static InventoryReservation reserve(UUID orderId, List<ReservedItem> items, Instant now) {
        var reservation = new InventoryReservation(orderId);
        reservation.record(new InventoryReservedEvent(items, now));
        return reservation;
    }

    public static InventoryReservation reject(UUID orderId, String reason, Instant now) {
        var reservation = new InventoryReservation(orderId);
        reservation.record(new InventoryRejectedEvent(reason, now));
        return reservation;
    }

    public static InventoryReservation rehydrate(UUID orderId, List<InventoryEvent> history) {
        if (history.isEmpty()) {
            throw new IllegalArgumentException("Missing inventory reservation " + orderId);
        }
        var reservation = new InventoryReservation(orderId);
        history.forEach(reservation::apply);
        return reservation;
    }

    public boolean release(Instant now) {
        if (status != ReservationStatus.RESERVED) {
            return false;
        }
        record(new InventoryReleasedEvent(now));
        return true;
    }

    private void record(InventoryEvent event) {
        apply(event);
        uncommittedEvents.add(event);
    }

    private void apply(InventoryEvent event) {
        switch (event) {
            case InventoryReservedEvent reserved -> applyReserved(reserved);
            case InventoryRejectedEvent rejected -> applyRejected(rejected);
            case InventoryReleasedEvent released -> applyReleased();
        }
        version++;
    }

    private void applyReserved(InventoryReservedEvent event) {
        requireNewStream("InventoryReserved");
        status = ReservationStatus.RESERVED;
        items = List.copyOf(event.items());
    }

    private void applyRejected(InventoryRejectedEvent event) {
        requireNewStream("InventoryRejected");
        status = ReservationStatus.REJECTED;
        reason = event.reason();
    }

    private void applyReleased() {
        if (status != ReservationStatus.RESERVED) {
            throw new IllegalStateException("InventoryReleased requires an active reservation");
        }
        status = ReservationStatus.RELEASED;
    }

    private void requireNewStream(String eventType) {
        if (version != 0) {
            throw new IllegalStateException(eventType + " must be the first inventory event");
        }
    }

    public UUID getOrderId() {
        return orderId;
    }

    public ReservationStatus getStatus() {
        return status;
    }

    public List<ReservedItem> getItems() {
        return List.copyOf(items);
    }

    public String getReason() {
        return reason;
    }

    public long getVersion() {
        return version;
    }

    public List<InventoryEvent> getUncommittedEvents() {
        return List.copyOf(uncommittedEvents);
    }

    public void markEventsCommitted() {
        uncommittedEvents.clear();
    }
}
