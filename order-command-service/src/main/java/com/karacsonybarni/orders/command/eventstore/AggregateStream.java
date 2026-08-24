package com.karacsonybarni.orders.command.eventstore;

import java.util.UUID;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

@Entity
@Table(name = "aggregate_streams")
public class AggregateStream {

    @Id
    @Column(name = "aggregate_id", nullable = false)
    private UUID aggregateId;

    @Column(name = "aggregate_type", nullable = false, length = 100)
    private String aggregateType;

    @Column(name = "current_version", nullable = false)
    private long currentVersion;

    protected AggregateStream() {
    }

    AggregateStream(UUID aggregateId, String aggregateType) {
        this.aggregateId = aggregateId;
        this.aggregateType = aggregateType;
    }

    public UUID getAggregateId() {
        return aggregateId;
    }

    public long getCurrentVersion() {
        return currentVersion;
    }

    void advanceTo(long newVersion) {
        if (newVersion != currentVersion + 1) {
            throw new EventStreamVersionConflictException(aggregateId, currentVersion, newVersion);
        }
        currentVersion = newVersion;
    }
}
