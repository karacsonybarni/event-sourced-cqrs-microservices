package com.karacsonybarni.orders.command.application;

import java.math.BigDecimal;
import java.util.List;

public record CreateOrderCommand(String customerId, List<Item> items) {

    public record Item(String productId, int quantity, BigDecimal unitPrice) {
    }
}
