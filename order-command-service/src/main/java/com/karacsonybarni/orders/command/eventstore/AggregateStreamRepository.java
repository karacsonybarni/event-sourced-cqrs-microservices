package com.karacsonybarni.orders.command.eventstore;

import java.util.Optional;
import java.util.UUID;

import jakarta.persistence.LockModeType;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

interface AggregateStreamRepository extends JpaRepository<AggregateStream, UUID> {

    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("select stream from AggregateStream stream where stream.aggregateId = :aggregateId")
    Optional<AggregateStream> findByIdForUpdate(@Param("aggregateId") UUID aggregateId);
}
