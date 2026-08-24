package com.karacsonybarni.orders.command.domain;

import java.math.BigDecimal;

public record OrderLineItem(String productId, int quantity, BigDecimal unitPrice) {

    public OrderLineItem {
        if (productId == null || productId.isBlank()) {
            throw new IllegalArgumentException("Product ID must not be blank");
        }
        if (quantity < 1) {
            throw new IllegalArgumentException("Quantity must be positive");
        }
        if (unitPrice == null || unitPrice.signum() <= 0) {
            throw new IllegalArgumentException("Unit price must be positive");
        }
    }

    public BigDecimal lineTotal() {
        return unitPrice.multiply(BigDecimal.valueOf(quantity));
    }
}
