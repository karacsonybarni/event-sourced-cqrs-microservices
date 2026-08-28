package com.karacsonybarni.orders.command.infrastructure;

import java.util.UUID;

import org.springframework.data.jpa.repository.JpaRepository;

public interface ProcessedInventoryEventRepository extends JpaRepository<ProcessedInventoryEvent, UUID> {
}
