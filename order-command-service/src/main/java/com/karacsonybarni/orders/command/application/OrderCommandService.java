package com.karacsonybarni.orders.command.application;

import java.time.Clock;
import java.time.Instant;
import java.util.List;
import java.util.UUID;

import com.karacsonybarni.orders.command.domain.Order;
import com.karacsonybarni.orders.command.domain.OrderLineItem;
import com.karacsonybarni.orders.command.domain.OrderNotFoundException;
import com.karacsonybarni.orders.command.infrastructure.CommandRequest;
import com.karacsonybarni.orders.command.infrastructure.CommandRequestRepository;
import com.karacsonybarni.orders.command.infrastructure.OrderRepository;
import com.karacsonybarni.orders.command.messaging.OrderEventFactory;
import com.karacsonybarni.orders.command.outbox.OutboxEvent;
import com.karacsonybarni.orders.command.outbox.OutboxEventRepository;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class OrderCommandService {

    private final OrderRepository orderRepository;
    private final CommandRequestRepository commandRequestRepository;
    private final OutboxEventRepository outboxEventRepository;
    private final OrderEventFactory eventFactory;
    private final CreateOrderCommandFingerprint commandFingerprint;
    private final Clock clock;

    public OrderCommandService(
            OrderRepository orderRepository,
            CommandRequestRepository commandRequestRepository,
            OutboxEventRepository outboxEventRepository,
            OrderEventFactory eventFactory,
            CreateOrderCommandFingerprint commandFingerprint,
            Clock clock) {
        this.orderRepository = orderRepository;
        this.commandRequestRepository = commandRequestRepository;
        this.outboxEventRepository = outboxEventRepository;
        this.eventFactory = eventFactory;
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
            Order existingOrder = orderRepository.findById(existingOrderId)
                    .orElseThrow(() -> new OrderNotFoundException(existingOrderId));
            return CommandResult.replayed(existingOrder);
        }

        List<OrderLineItem> items = command.items().stream()
                .map(item -> new OrderLineItem(item.productId(), item.quantity(), item.unitPrice()))
                .toList();
        Order order = Order.create(orderId, command.customerId(), items, now);
        orderRepository.save(order);
        OutboxEvent event = eventFactory.orderCreated(order);
        outboxEventRepository.save(event);
        return CommandResult.accepted(order);
    }

    @Transactional
    public CommandResult cancel(UUID orderId) {
        Order order = orderRepository.findByIdForUpdate(orderId)
                .orElseThrow(() -> new OrderNotFoundException(orderId));
        if (order.cancel(clock.instant())) {
            OutboxEvent event = eventFactory.orderCancelled(order);
            outboxEventRepository.save(event);
        }
        return CommandResult.accepted(order);
    }
}
