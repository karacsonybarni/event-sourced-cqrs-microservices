package com.karacsonybarni.inventory.eventstore;

import java.util.List;
import java.util.UUID;

import org.springframework.data.jpa.repository.JpaRepository;

public interface StoredInventoryEventRepository extends JpaRepository<StoredInventoryEvent, UUID> {

    List<StoredInventoryEvent> findAllByAggregateIdOrderByAggregateVersion(UUID aggregateId);
}
