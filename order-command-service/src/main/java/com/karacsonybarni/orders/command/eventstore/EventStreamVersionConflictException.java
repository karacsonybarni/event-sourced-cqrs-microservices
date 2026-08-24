package com.karacsonybarni.orders.command.eventstore;

import java.util.UUID;

public class EventStreamVersionConflictException extends RuntimeException {

    EventStreamVersionConflictException(UUID aggregateId, long streamVersion, long aggregateVersion) {
        super("Order event stream %s metadata is at version %d but the aggregate is at version %d"
                .formatted(aggregateId, streamVersion, aggregateVersion));
    }
}
