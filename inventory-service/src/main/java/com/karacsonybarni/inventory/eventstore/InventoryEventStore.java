package com.karacsonybarni.inventory.eventstore;

import java.util.List;
import java.util.UUID;

import com.karacsonybarni.inventory.domain.InventoryReservation;
import com.karacsonybarni.inventory.domain.event.InventoryEvent;
import org.springframework.stereotype.Component;

@Component
public class InventoryEventStore {

    private final InventoryStreamRepository streamRepository;
    private final StoredInventoryEventRepository eventRepository;
    private final InventoryEventSerializer eventSerializer;

    public InventoryEventStore(
            InventoryStreamRepository streamRepository,
            StoredInventoryEventRepository eventRepository,
            InventoryEventSerializer eventSerializer) {
        this.streamRepository = streamRepository;
        this.eventRepository = eventRepository;
        this.eventSerializer = eventSerializer;
    }

    public boolean exists(UUID orderId) {
        return streamRepository.existsById(orderId);
    }

    public void create(InventoryReservation reservation) {
        var newStream = new InventoryStream(reservation.getOrderId(), InventoryEventSerializer.AGGREGATE_TYPE);
        InventoryStream stream = streamRepository.save(newStream);
        appendTo(stream, reservation);
    }

    public InventoryReservation load(UUID orderId) {
        InventoryStream stream = streamRepository.findById(orderId)
                .orElseThrow(() -> new IllegalArgumentException("Missing inventory reservation " + orderId));
        InventoryReservation reservation = replay(orderId);
        verifyVersion(stream, reservation.getVersion());
        return reservation;
    }

    public InventoryReservation loadForUpdate(UUID orderId) {
        InventoryStream stream = streamRepository.findByIdForUpdate(orderId)
                .orElseThrow(() -> new IllegalArgumentException("Missing inventory reservation " + orderId));
        InventoryReservation reservation = replay(orderId);
        verifyVersion(stream, reservation.getVersion());
        return reservation;
    }

    public void append(InventoryReservation reservation) {
        InventoryStream stream = streamRepository.findByIdForUpdate(reservation.getOrderId())
                .orElseThrow(() -> new IllegalArgumentException(
                        "Missing inventory reservation " + reservation.getOrderId()));
        appendTo(stream, reservation);
    }

    private InventoryReservation replay(UUID orderId) {
        List<InventoryEvent> history = eventRepository
                .findAllByAggregateIdOrderByAggregateVersion(orderId).stream()
                .map(eventSerializer::deserialize)
                .toList();
        return InventoryReservation.rehydrate(orderId, history);
    }

    private void appendTo(InventoryStream stream, InventoryReservation reservation) {
        List<InventoryEvent> uncommittedEvents = reservation.getUncommittedEvents();
        long persistedVersion = reservation.getVersion() - uncommittedEvents.size();
        verifyVersion(stream, persistedVersion);
        long nextVersion = persistedVersion;
        for (InventoryEvent event : uncommittedEvents) {
            nextVersion++;
            StoredInventoryEvent storedEvent = eventSerializer.serialize(
                    reservation.getOrderId(), nextVersion, event);
            eventRepository.save(storedEvent);
            stream.advanceTo(nextVersion);
        }
        eventRepository.flush();
        streamRepository.flush();
        reservation.markEventsCommitted();
    }

    private void verifyVersion(InventoryStream stream, long expectedVersion) {
        if (stream.getCurrentVersion() != expectedVersion) {
            throw new IllegalStateException(
                    "Inventory stream version conflict for " + stream.getAggregateId()
                            + ": persisted " + stream.getCurrentVersion() + ", expected " + expectedVersion);
        }
    }
}
