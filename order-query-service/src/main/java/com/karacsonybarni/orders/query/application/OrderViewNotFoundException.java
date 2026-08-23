package com.karacsonybarni.orders.query.application;

import java.util.UUID;

public class OrderViewNotFoundException extends RuntimeException {

    public OrderViewNotFoundException(UUID orderId) {
        super("Order %s is not present in the read model yet".formatted(orderId));
    }
}
