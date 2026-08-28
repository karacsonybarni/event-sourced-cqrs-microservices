package com.karacsonybarni.inventory.eventstore;

import java.util.Optional;
import java.util.UUID;

import jakarta.persistence.LockModeType;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface InventoryStreamRepository extends JpaRepository<InventoryStream, UUID> {

    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("select stream from InventoryStream stream where stream.aggregateId = :aggregateId")
    Optional<InventoryStream> findByIdForUpdate(@Param("aggregateId") UUID aggregateId);
}
