package com.karacsonybarni.orders.query.infrastructure;

import java.util.Optional;
import java.util.UUID;

import com.karacsonybarni.orders.query.domain.OrderView;
import org.springframework.data.jpa.repository.EntityGraph;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.JpaSpecificationExecutor;

public interface OrderViewRepository
        extends JpaRepository<OrderView, UUID>, JpaSpecificationExecutor<OrderView> {

    @EntityGraph(attributePaths = "items")
    Optional<OrderView> findDetailedById(UUID id);
}
