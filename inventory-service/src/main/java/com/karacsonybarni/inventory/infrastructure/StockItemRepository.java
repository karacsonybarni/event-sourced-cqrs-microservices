package com.karacsonybarni.inventory.infrastructure;

import java.util.Collection;
import java.util.List;

import com.karacsonybarni.inventory.domain.StockItem;
import jakarta.persistence.LockModeType;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface StockItemRepository extends JpaRepository<StockItem, String> {

    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("select item from StockItem item where item.productId in :productIds order by item.productId")
    List<StockItem> findAllByProductIdForUpdate(@Param("productIds") Collection<String> productIds);
}
