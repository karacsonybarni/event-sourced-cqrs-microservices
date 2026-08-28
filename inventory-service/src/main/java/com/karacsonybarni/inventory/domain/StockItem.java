package com.karacsonybarni.inventory.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

@Entity
@Table(name = "stock_items")
public class StockItem {

    @Id
    @Column(name = "product_id", nullable = false, length = 100)
    private String productId;

    @Column(name = "available_quantity", nullable = false)
    private int availableQuantity;

    protected StockItem() {
    }

    public StockItem(String productId, int availableQuantity) {
        this.productId = productId;
        this.availableQuantity = availableQuantity;
    }

    public boolean canReserve(int quantity) {
        return availableQuantity >= quantity;
    }

    public void reserve(int quantity) {
        if (!canReserve(quantity)) {
            throw new IllegalStateException("Insufficient stock for " + productId);
        }
        availableQuantity -= quantity;
    }

    public void release(int quantity) {
        availableQuantity += quantity;
    }

    public String getProductId() {
        return productId;
    }

    public int getAvailableQuantity() {
        return availableQuantity;
    }
}
