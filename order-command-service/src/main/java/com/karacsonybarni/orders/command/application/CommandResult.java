package com.karacsonybarni.orders.command.application;

import java.util.UUID;

import com.karacsonybarni.orders.command.domain.Order;
import com.karacsonybarni.orders.command.domain.OrderStatus;

public record CommandResult(UUID orderId, OrderStatus status, boolean replayed) {

    static CommandResult accepted(Order order) {
        return new CommandResult(order.getId(), order.getStatus(), false);
    }

    static CommandResult replayed(Order order) {
        return new CommandResult(order.getId(), order.getStatus(), true);
    }
}
