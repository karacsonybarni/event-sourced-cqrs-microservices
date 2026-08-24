package com.karacsonybarni.orders.command.application;

import java.time.Clock;
import java.time.Instant;
import java.util.List;
import java.util.UUID;

import com.karacsonybarni.orders.command.domain.Order;
import com.karacsonybarni.orders.command.domain.OrderLineItem;
import com.karacsonybarni.orders.command.eventstore.OrderEventStore;
import com.karacsonybarni.orders.command.infrastructure.CommandRequest;
import com.karacsonybarni.orders.command.infrastructure.CommandRequestRepository;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class OrderCommandService {

    private final OrderEventStore eventStore;
    private final CommandRequestRepository commandRequestRepository;
    private final CreateOrderCommandFingerprint commandFingerprint;
    private final Clock clock;

    public OrderCommandService(
            OrderEventStore eventStore,
            CommandRequestRepository commandRequestRepository,
            CreateOrderCommandFingerprint commandFingerprint,
            Clock clock) {
        this.eventStore = eventStore;
        this.commandRequestRepository = commandRequestRepository;
        this.commandFingerprint = commandFingerprint;
        this.clock = clock;
    }

    @Transactional
    public CommandResult create(String idempotencyKey, CreateOrderCommand command) {
        Instant now = clock.instant();
        UUID orderId = UUID.randomUUID();
        String requestFingerprint = commandFingerprint.calculate(command);
        int claimed = commandRequestRepository.claim(idempotencyKey, orderId, requestFingerprint, now);
        if (claimed == 0) {
            CommandRequest existingRequest = commandRequestRepository.findById(idempotencyKey).orElseThrow();
            if (!existingRequest.getRequestFingerprint().equals(requestFingerprint)) {
                throw new IdempotencyKeyConflictException(idempotencyKey);
            }
            UUID existingOrderId = existingRequest.getOrderId();
            Order existingOrder = eventStore.load(existingOrderId);
            return CommandResult.replayed(existingOrder);
        }

        List<OrderLineItem> items = command.items().stream()
                .map(item -> new OrderLineItem(item.productId(), item.quantity(), item.unitPrice()))
                .toList();
        Order order = Order.create(orderId, command.customerId(), items, now);
        eventStore.create(order);
        return CommandResult.accepted(order);
    }

    @Transactional
    public CommandResult cancel(UUID orderId) {
        Order order = eventStore.loadForUpdate(orderId);
        if (order.cancel(clock.instant())) {
            eventStore.append(order);
        }
        return CommandResult.accepted(order);
    }
}
