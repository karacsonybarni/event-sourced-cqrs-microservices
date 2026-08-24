package com.karacsonybarni.orders.command.eventstore;

import java.util.List;
import java.util.UUID;

import org.springframework.data.jpa.repository.JpaRepository;

interface StoredOrderEventRepository extends JpaRepository<StoredOrderEvent, UUID> {

    List<StoredOrderEvent> findAllByAggregateIdOrderByAggregateVersion(UUID aggregateId);
}
