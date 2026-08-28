package com.karacsonybarni.inventory.application;

import java.time.Clock;
import java.time.Instant;
import java.util.List;
import java.util.Map;
import java.util.TreeMap;
import java.util.UUID;
import java.util.function.Function;
import java.util.stream.Collectors;

import com.karacsonybarni.inventory.domain.InventoryReservation;
import com.karacsonybarni.inventory.domain.ReservedItem;
import com.karacsonybarni.inventory.domain.StockItem;
import com.karacsonybarni.inventory.eventstore.InventoryEventStore;
import com.karacsonybarni.inventory.infrastructure.StockItemRepository;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class InventoryService {

    private final StockItemRepository stockItemRepository;
    private final InventoryEventStore eventStore;
    private final Clock clock;

    public InventoryService(
            StockItemRepository stockItemRepository,
            InventoryEventStore eventStore,
            Clock clock) {
        this.stockItemRepository = stockItemRepository;
        this.eventStore = eventStore;
        this.clock = clock;
    }

    @Transactional
    public void reserve(UUID orderId, List<RequestedItem> requestedItems) {
        if (eventStore.exists(orderId)) {
            return;
        }

        Map<String, Integer> requestedQuantityByProduct;
        try {
            requestedQuantityByProduct = combineQuantities(requestedItems);
        } catch (ArithmeticException ignored) {
            eventStore.create(InventoryReservation.reject(
                    orderId,
                    "Requested quantity exceeds the supported maximum",
                    clock.instant()));
            return;
        }
        List<StockItem> lockedStock = stockItemRepository.findAllByProductIdForUpdate(
                requestedQuantityByProduct.keySet());
        Map<String, StockItem> stockByProduct = lockedStock.stream()
                .collect(Collectors.toMap(StockItem::getProductId, Function.identity()));
        String rejectionReason = rejectionReason(requestedQuantityByProduct, stockByProduct);
        Instant now = clock.instant();
        if (rejectionReason != null) {
            eventStore.create(InventoryReservation.reject(orderId, rejectionReason, now));
            return;
        }

        List<ReservedItem> reservedItems = requestedQuantityByProduct.entrySet().stream()
                .map(entry -> {
                    stockByProduct.get(entry.getKey()).reserve(entry.getValue());
                    return new ReservedItem(entry.getKey(), entry.getValue());
                })
                .toList();
        eventStore.create(InventoryReservation.reserve(orderId, reservedItems, now));
    }

    @Transactional
    public void release(UUID orderId) {
        if (!eventStore.exists(orderId)) {
            return;
        }
        InventoryReservation reservation = eventStore.loadForUpdate(orderId);
        if (!reservation.release(clock.instant())) {
            return;
        }
        Map<String, Integer> reservedQuantityByProduct = reservation.getItems().stream()
                .collect(Collectors.toMap(ReservedItem::productId, ReservedItem::quantity));
        Map<String, StockItem> stockByProduct = stockItemRepository.findAllByProductIdForUpdate(
                        reservedQuantityByProduct.keySet()).stream()
                .collect(Collectors.toMap(StockItem::getProductId, Function.identity()));
        reservedQuantityByProduct.forEach((productId, quantity) ->
                stockByProduct.get(productId).release(quantity));
        eventStore.append(reservation);
    }

    private Map<String, Integer> combineQuantities(List<RequestedItem> requestedItems) {
        var quantities = new TreeMap<String, Integer>();
        for (RequestedItem item : requestedItems) {
            if (item.quantity() < 1) {
                throw new IllegalArgumentException("Inventory quantity must be positive");
            }
            quantities.merge(item.productId(), item.quantity(), Math::addExact);
        }
        if (quantities.isEmpty()) {
            throw new IllegalArgumentException("Inventory reservation requires at least one item");
        }
        return quantities;
    }

    private String rejectionReason(
            Map<String, Integer> requestedQuantityByProduct,
            Map<String, StockItem> stockByProduct) {
        for (var request : requestedQuantityByProduct.entrySet()) {
            StockItem stockItem = stockByProduct.get(request.getKey());
            if (stockItem == null) {
                return "Unknown product: " + request.getKey();
            }
            if (!stockItem.canReserve(request.getValue())) {
                return "Insufficient stock for " + request.getKey();
            }
        }
        return null;
    }

    public record RequestedItem(String productId, int quantity) {
    }
}
