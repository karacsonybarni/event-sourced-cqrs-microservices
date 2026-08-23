package com.karacsonybarni.orders.query.web;

import java.util.UUID;

import com.karacsonybarni.orders.query.application.OrderQueryService;
import com.karacsonybarni.orders.query.application.OrderQueryService.OrderDetails;
import com.karacsonybarni.orders.query.application.OrderQueryService.OrderSummary;
import com.karacsonybarni.orders.query.domain.OrderViewStatus;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.responses.ApiResponse;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/orders")
class OrderQueryController {

    private static final String PROJECTION_HEADER = "X-Data-Consistency";
    private static final String EVENTUAL = "eventual";

    private final OrderQueryService service;

    OrderQueryController(OrderQueryService service) {
        this.service = service;
    }

    @GetMapping("/{orderId}")
    @Operation(summary = "Get an order from the CQRS read model")
    @ApiResponse(responseCode = "404", description = "Unknown order or projection not caught up yet")
    ResponseEntity<OrderDetails> findById(@PathVariable UUID orderId) {
        return ResponseEntity.ok()
                .header(PROJECTION_HEADER, EVENTUAL)
                .body(service.findById(orderId));
    }

    @GetMapping
    @Operation(summary = "Search the denormalized order read model")
    ResponseEntity<Page<OrderSummary>> find(
            @RequestParam(required = false) String customerId,
            @RequestParam(required = false) OrderViewStatus status,
            Pageable pageable) {
        return ResponseEntity.ok()
                .header(PROJECTION_HEADER, EVENTUAL)
                .body(service.find(customerId, status, pageable));
    }
}
