package com.karacsonybarni.orders.command.infrastructure;

import java.util.Optional;
import java.util.UUID;

import com.karacsonybarni.orders.command.domain.Order;
import jakarta.persistence.LockModeType;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface OrderRepository extends JpaRepository<Order, UUID> {

    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("select orders from Order orders where orders.id = :orderId")
    Optional<Order> findByIdForUpdate(@Param("orderId") UUID orderId);
}
