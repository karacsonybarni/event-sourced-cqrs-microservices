package com.karacsonybarni.inventory.domain;

public record ReservedItem(String productId, int quantity) {

    public ReservedItem {
        if (productId == null || productId.isBlank()) {
            throw new IllegalArgumentException("Product id must not be blank");
        }
        if (quantity < 1) {
            throw new IllegalArgumentException("Reserved quantity must be positive");
        }
    }
}
