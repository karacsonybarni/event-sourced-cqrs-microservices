package com.karacsonybarni.orders.command.eventstore;

import java.util.List;
import java.util.UUID;

import com.karacsonybarni.orders.command.domain.Order;
import com.karacsonybarni.orders.command.domain.OrderNotFoundException;
import com.karacsonybarni.orders.command.domain.event.OrderEvent;
import org.springframework.stereotype.Component;

@Component
public class OrderEventStore {

    private final AggregateStreamRepository streamRepository;
    private final StoredOrderEventRepository eventRepository;
    private final OrderEventSerializer eventSerializer;

    public OrderEventStore(
            AggregateStreamRepository streamRepository,
            StoredOrderEventRepository eventRepository,
            OrderEventSerializer eventSerializer) {
        this.streamRepository = streamRepository;
        this.eventRepository = eventRepository;
        this.eventSerializer = eventSerializer;
    }

    public void create(Order order) {
        var newStream = new AggregateStream(order.getId(), OrderEventSerializer.AGGREGATE_TYPE);
        AggregateStream stream = streamRepository.save(newStream);
        appendTo(stream, order);
    }

    public Order load(UUID aggregateId) {
        AggregateStream stream = streamRepository.findById(aggregateId)
                .orElseThrow(() -> new OrderNotFoundException(aggregateId));
        Order order = replay(aggregateId);
        verifyVersion(stream, order.getVersion());
        return order;
    }

    public Order loadForUpdate(UUID aggregateId) {
        AggregateStream stream = streamRepository.findByIdForUpdate(aggregateId)
                .orElseThrow(() -> new OrderNotFoundException(aggregateId));
        Order order = replay(aggregateId);
        verifyVersion(stream, order.getVersion());
        return order;
    }

    public void append(Order order) {
        AggregateStream stream = streamRepository.findByIdForUpdate(order.getId())
                .orElseThrow(() -> new OrderNotFoundException(order.getId()));
        appendTo(stream, order);
    }

    private Order replay(UUID aggregateId) {
        List<OrderEvent> history = eventRepository.findAllByAggregateIdOrderByAggregateVersion(aggregateId).stream()
                .map(eventSerializer::deserialize)
                .toList();
        return Order.rehydrate(aggregateId, history);
    }

    private void appendTo(AggregateStream stream, Order order) {
        List<OrderEvent> uncommittedEvents = order.getUncommittedEvents();
        long persistedVersion = order.getVersion() - uncommittedEvents.size();
        verifyVersion(stream, persistedVersion);
        long nextVersion = persistedVersion;
        for (OrderEvent event : uncommittedEvents) {
            nextVersion++;
            StoredOrderEvent storedEvent = eventSerializer.serialize(order.getId(), nextVersion, event);
            eventRepository.save(storedEvent);
            stream.advanceTo(nextVersion);
        }
        eventRepository.flush();
        streamRepository.flush();
        order.markEventsCommitted();
    }

    private void verifyVersion(AggregateStream stream, long expectedVersion) {
        if (stream.getCurrentVersion() != expectedVersion) {
            throw new EventStreamVersionConflictException(
                    stream.getAggregateId(), stream.getCurrentVersion(), expectedVersion);
        }
    }
}
