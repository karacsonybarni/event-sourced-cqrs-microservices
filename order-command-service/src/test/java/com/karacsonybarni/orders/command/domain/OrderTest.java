package com.karacsonybarni.orders.command.domain;

import static org.assertj.core.api.Assertions.assertThat;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.List;
import java.util.UUID;

import com.karacsonybarni.orders.command.domain.event.OrderCancelledEvent;
import com.karacsonybarni.orders.command.domain.event.OrderConfirmedEvent;
import com.karacsonybarni.orders.command.domain.event.OrderCreatedEvent;
import com.karacsonybarni.orders.command.domain.event.OrderEvent;
import com.karacsonybarni.orders.command.domain.event.OrderRejectedEvent;
import org.junit.jupiter.api.Test;

class OrderTest {

    private static final Instant CREATED_AT = Instant.parse("2026-01-10T10:15:30Z");

    @Test
    void newOrderRecordsOneCreatedEvent() {
        var items = List.of(
                new OrderLineItem("keyboard", 2, new BigDecimal("49.90")),
                new OrderLineItem("mouse", 1, new BigDecimal("29.00")));

        Order order = Order.create(UUID.randomUUID(), "customer-42", items, CREATED_AT);

        assertThat(order.getStatus()).isEqualTo(OrderStatus.CREATED);
        assertThat(order.getTotalAmount()).isEqualByComparingTo("128.80");
        assertThat(order.getVersion()).isOne();
        assertThat(order.getUncommittedEvents())
                .singleElement()
                .isInstanceOf(OrderCreatedEvent.class);
    }

    @Test
    void rehydratesCurrentStateFromHistoryWithoutPendingEvents() {
        var items = List.of(new OrderLineItem("keyboard", 1, new BigDecimal("49.90")));
        Instant cancelledAt = CREATED_AT.plusSeconds(60);
        List<OrderEvent> history = List.of(
                new OrderCreatedEvent("customer-42", new BigDecimal("49.90"), items, CREATED_AT),
                new OrderCancelledEvent(cancelledAt));

        Order order = Order.rehydrate(UUID.randomUUID(), history);

        assertThat(order.getStatus()).isEqualTo(OrderStatus.CANCELLED);
        assertThat(order.getVersion()).isEqualTo(2);
        assertThat(order.getUpdatedAt()).isEqualTo(cancelledAt);
        assertThat(order.getUncommittedEvents()).isEmpty();
    }

    @Test
    void cancellationIsIdempotentAndRecordsOneEvent() {
        var item = new OrderLineItem("keyboard", 1, new BigDecimal("49.90"));
        Order order = Order.rehydrate(
                UUID.randomUUID(),
                List.of(new OrderCreatedEvent("customer-42", new BigDecimal("49.90"), List.of(item), CREATED_AT)));

        boolean firstCancellationChangedState = order.cancel(CREATED_AT.plusSeconds(60));
        boolean repeatedCancellationChangedState = order.cancel(CREATED_AT.plusSeconds(120));

        assertThat(firstCancellationChangedState).isTrue();
        assertThat(repeatedCancellationChangedState).isFalse();
        assertThat(order.getStatus()).isEqualTo(OrderStatus.CANCELLED);
        assertThat(order.getVersion()).isEqualTo(2);
        assertThat(order.getUncommittedEvents())
                .singleElement()
                .isInstanceOf(OrderCancelledEvent.class);
    }

    @Test
    void inventoryReservationConfirmsANewOrderOnce() {
        Order order = createdOrder();

        boolean firstConfirmationChangedState = order.confirm(CREATED_AT.plusSeconds(30));
        boolean repeatedConfirmationChangedState = order.confirm(CREATED_AT.plusSeconds(60));

        assertThat(firstConfirmationChangedState).isTrue();
        assertThat(repeatedConfirmationChangedState).isFalse();
        assertThat(order.getStatus()).isEqualTo(OrderStatus.CONFIRMED);
        assertThat(order.getUncommittedEvents())
                .singleElement()
                .isInstanceOf(OrderConfirmedEvent.class);
    }

    @Test
    void inventoryRejectionRecordsTheReasonAndPreventsCancellation() {
        Order order = createdOrder();

        boolean rejected = order.reject("Insufficient stock for keyboard", CREATED_AT.plusSeconds(30));
        boolean cancelled = order.cancel(CREATED_AT.plusSeconds(60));

        assertThat(rejected).isTrue();
        assertThat(cancelled).isFalse();
        assertThat(order.getStatus()).isEqualTo(OrderStatus.REJECTED);
        assertThat(order.getRejectionReason()).isEqualTo("Insufficient stock for keyboard");
        assertThat(order.getUncommittedEvents())
                .singleElement()
                .isInstanceOf(OrderRejectedEvent.class);
    }

    @Test
    void lateInventoryOutcomeDoesNotReviveACancelledOrder() {
        Order order = createdOrder();
        order.cancel(CREATED_AT.plusSeconds(30));

        boolean confirmed = order.confirm(CREATED_AT.plusSeconds(60));

        assertThat(confirmed).isFalse();
        assertThat(order.getStatus()).isEqualTo(OrderStatus.CANCELLED);
        assertThat(order.getUncommittedEvents())
                .singleElement()
                .isInstanceOf(OrderCancelledEvent.class);
    }

    private Order createdOrder() {
        var item = new OrderLineItem("keyboard", 1, new BigDecimal("49.90"));
        return Order.rehydrate(
                UUID.randomUUID(),
                List.of(new OrderCreatedEvent("customer-42", new BigDecimal("49.90"), List.of(item), CREATED_AT)));
    }
}
