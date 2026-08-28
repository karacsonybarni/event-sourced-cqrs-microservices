package com.karacsonybarni.inventory.eventstore;

import java.util.UUID;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

@Entity
@Table(name = "inventory_streams")
public class InventoryStream {

    @Id
    @Column(name = "aggregate_id", nullable = false)
    private UUID aggregateId;

    @Column(name = "aggregate_type", nullable = false, length = 100)
    private String aggregateType;

    @Column(name = "current_version", nullable = false)
    private long currentVersion;

    protected InventoryStream() {
    }

    public InventoryStream(UUID aggregateId, String aggregateType) {
        this.aggregateId = aggregateId;
        this.aggregateType = aggregateType;
    }

    public void advanceTo(long version) {
        if (version != currentVersion + 1) {
            throw new IllegalArgumentException("Inventory stream versions must be contiguous");
        }
        currentVersion = version;
    }

    public UUID getAggregateId() {
        return aggregateId;
    }

    public long getCurrentVersion() {
        return currentVersion;
    }
}
