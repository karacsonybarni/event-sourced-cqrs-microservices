package com.karacsonybarni.orders.query.application;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.List;
import java.util.UUID;

import com.karacsonybarni.orders.query.domain.OrderItemView;
import com.karacsonybarni.orders.query.domain.OrderView;
import com.karacsonybarni.orders.query.domain.OrderViewStatus;
import com.karacsonybarni.orders.query.infrastructure.OrderViewRepository;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.domain.Specification;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class OrderQueryService {

    private final OrderViewRepository repository;

    public OrderQueryService(OrderViewRepository repository) {
        this.repository = repository;
    }

    @Transactional(readOnly = true)
    public OrderDetails findById(UUID orderId) {
        OrderView view = repository.findDetailedById(orderId)
                .orElseThrow(() -> new OrderViewNotFoundException(orderId));
        return OrderDetails.from(view);
    }

    @Transactional(readOnly = true)
    public Page<OrderSummary> find(String customerId, OrderViewStatus status, Pageable pageable) {
        Specification<OrderView> filters = (root, query, builder) -> builder.conjunction();
        if (customerId != null && !customerId.isBlank()) {
            filters = filters.and((root, query, builder) -> builder.equal(root.get("customerId"), customerId));
        }
        if (status != null) {
            filters = filters.and((root, query, builder) -> builder.equal(root.get("status"), status));
        }
        return repository.findAll(filters, pageable).map(OrderSummary::from);
    }

    public record OrderSummary(
            UUID orderId,
            String customerId,
            OrderViewStatus status,
            BigDecimal totalAmount,
            String rejectionReason,
            Instant createdAt,
            Instant updatedAt) {

        static OrderSummary from(OrderView view) {
            return new OrderSummary(
                    view.getId(),
                    view.getCustomerId(),
                    view.getStatus(),
                    view.getTotalAmount(),
                    view.getRejectionReason(),
                    view.getCreatedAt(),
                    view.getUpdatedAt());
        }
    }

    public record OrderDetails(
            UUID orderId,
            String customerId,
            OrderViewStatus status,
            BigDecimal totalAmount,
            List<Item> items,
            String rejectionReason,
            Instant createdAt,
            Instant updatedAt,
            long version) {

        static OrderDetails from(OrderView view) {
            List<Item> items = view.getItems().stream().map(Item::from).toList();
            return new OrderDetails(
                    view.getId(),
                    view.getCustomerId(),
                    view.getStatus(),
                    view.getTotalAmount(),
                    items,
                    view.getRejectionReason(),
                    view.getCreatedAt(),
                    view.getUpdatedAt(),
                    view.getAggregateVersion());
        }
    }

    public record Item(String productId, int quantity, BigDecimal unitPrice) {

        static Item from(OrderItemView item) {
            return new Item(item.getProductId(), item.getQuantity(), item.getUnitPrice());
        }
    }
}
