package com.karacsonybarni.orders.command.web;

import java.math.BigDecimal;
import java.net.URI;
import java.util.List;
import java.util.UUID;

import com.karacsonybarni.orders.command.application.CommandResult;
import com.karacsonybarni.orders.command.application.CreateOrderCommand;
import com.karacsonybarni.orders.command.application.OrderCommandService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.responses.ApiResponse;
import io.swagger.v3.oas.annotations.responses.ApiResponses;
import jakarta.validation.Valid;
import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotEmpty;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/orders")
class OrderCommandController {

    private final OrderCommandService service;

    OrderCommandController(OrderCommandService service) {
        this.service = service;
    }

    @PostMapping
    @Operation(summary = "Create an order", description = """
            Persists the order and its domain event atomically. Concurrent retries with the same Idempotency-Key and
            logical command return the original order; reusing the key for a different command returns 409.
            """)
    @ApiResponses({
        @ApiResponse(responseCode = "202", description = "Command accepted; the read model updates asynchronously"),
        @ApiResponse(responseCode = "409", description = "Idempotency-Key was already used for a different command")
    })
    ResponseEntity<CommandResponse> create(
            @RequestHeader("Idempotency-Key") @NotBlank @Size(max = 100) String idempotencyKey,
            @Valid @RequestBody CreateOrderRequest request) {
        var commandItems = request.items().stream()
                .map(item -> new CreateOrderCommand.Item(item.productId(), item.quantity(), item.unitPrice()))
                .toList();
        var command = new CreateOrderCommand(request.customerId(), commandItems);
        CommandResult result = service.create(idempotencyKey, command);
        URI queryLocation = URI.create("/api/orders/" + result.orderId());
        return ResponseEntity.accepted()
                .location(queryLocation)
                .header("Idempotent-Replay", Boolean.toString(result.replayed()))
                .body(CommandResponse.from(result));
    }

    @PutMapping("/{orderId}/cancellation")
    @Operation(summary = "Cancel an order")
    @ApiResponse(responseCode = "202", description = "Cancellation accepted")
    ResponseEntity<CommandResponse> cancel(@PathVariable UUID orderId) {
        CommandResult result = service.cancel(orderId);
        return ResponseEntity.accepted().body(CommandResponse.from(result));
    }

    record CreateOrderRequest(
            @NotBlank @Size(max = 100) String customerId,
            @NotEmpty List<@Valid ItemRequest> items) {
    }

    record ItemRequest(
            @NotBlank @Size(max = 100) String productId,
            @NotNull @jakarta.validation.constraints.Min(1) Integer quantity,
            @NotNull @DecimalMin(value = "0.01") BigDecimal unitPrice) {
    }

    record CommandResponse(UUID orderId, String status) {

        static CommandResponse from(CommandResult result) {
            return new CommandResponse(result.orderId(), result.status().name());
        }
    }
}
