package com.karacsonybarni.orders.activity;

import java.time.Instant;
import java.util.Map;
import java.util.Optional;

import com.azure.cosmos.CosmosException;
import com.microsoft.azure.functions.ExecutionContext;
import com.microsoft.azure.functions.HttpMethod;
import com.microsoft.azure.functions.HttpRequestMessage;
import com.microsoft.azure.functions.HttpResponseMessage;
import com.microsoft.azure.functions.HttpStatus;
import com.microsoft.azure.functions.annotation.AuthorizationLevel;
import com.microsoft.azure.functions.annotation.BindingName;
import com.microsoft.azure.functions.annotation.FunctionName;
import com.microsoft.azure.functions.annotation.HttpTrigger;
import tools.jackson.core.JacksonException;
import tools.jackson.databind.ObjectMapper;

public class OrderActivityQueryFunction {

    private static final String PROBE_DOCUMENT_ID = "cosmos-write-probe";

    private final ObjectMapper objectMapper;
    private final OrderActivityStore activityStore;

    public OrderActivityQueryFunction() {
        this(new ObjectMapper(), CosmosOrderActivityStore.instance());
    }

    OrderActivityQueryFunction(ObjectMapper objectMapper, OrderActivityStore activityStore) {
        this.objectMapper = objectMapper;
        this.activityStore = activityStore;
    }

    @FunctionName("getOrderActivity")
    public HttpResponseMessage getOrderActivity(
            @HttpTrigger(
                    name = "request",
                    methods = HttpMethod.GET,
                    authLevel = AuthorizationLevel.ANONYMOUS,
                    route = "activity/{orderId:guid}") HttpRequestMessage<Optional<String>> request,
            @BindingName("orderId") String orderId,
            ExecutionContext context) throws JacksonException {
        try {
            String response = objectMapper.writeValueAsString(activityStore.findByOrderId(orderId));
            return request.createResponseBuilder(HttpStatus.OK)
                    .header("Content-Type", "application/json")
                    .body(response)
                    .build();
        } catch (CosmosException exception) {
            context.getLogger().severe(
                    "Cosmos activity query failed with status " + exception.getStatusCode()
                            + " and substatus " + exception.getSubStatusCode());
            String response = objectMapper.writeValueAsString(Map.of(
                    "error", "cosmos-query-failed",
                    "statusCode", exception.getStatusCode(),
                    "subStatusCode", exception.getSubStatusCode()));
            return request.createResponseBuilder(HttpStatus.SERVICE_UNAVAILABLE)
                    .header("Content-Type", "application/json")
                    .body(response)
                    .build();
        }
    }

    @FunctionName("probeOrderActivityStore")
    public HttpResponseMessage probeOrderActivityStore(
            @HttpTrigger(
                    name = "request",
                    methods = HttpMethod.POST,
                    authLevel = AuthorizationLevel.FUNCTION,
                    route = "activity-probe/{orderId:guid}") HttpRequestMessage<Optional<String>> request,
            @BindingName("orderId") String orderId,
            ExecutionContext context) throws JacksonException {
        Map<String, Object> probeDocument = Map.of(
                "id", PROBE_DOCUMENT_ID,
                "orderId", orderId,
                "eventType", "CosmosWriteProbe.v1",
                "aggregateVersion", 1L,
                "occurredAt", Instant.now().toString(),
                "payload", Map.of("probe", true));

        try {
            activityStore.upsert(probeDocument);
            boolean visible = activityStore.findByOrderId(orderId).stream()
                    .anyMatch(document -> PROBE_DOCUMENT_ID.equals(document.get("id")));
            if (!visible) {
                return request.createResponseBuilder(HttpStatus.INTERNAL_SERVER_ERROR)
                        .header("Content-Type", "application/json")
                        .body("{\"error\":\"cosmos-probe-write-not-visible\"}")
                        .build();
            }

            return request.createResponseBuilder(HttpStatus.OK)
                    .header("Content-Type", "application/json")
                    .body("{\"status\":\"ok\"}")
                    .build();
        } catch (CosmosException exception) {
            context.getLogger().severe(
                    "Cosmos activity write probe failed with status " + exception.getStatusCode()
                            + " and substatus " + exception.getSubStatusCode()
                            + ": " + exception.getMessage());
            String response = objectMapper.writeValueAsString(Map.of(
                    "error", "cosmos-write-probe-failed",
                    "statusCode", exception.getStatusCode(),
                    "subStatusCode", exception.getSubStatusCode(),
                    "message", Optional.ofNullable(exception.getMessage()).orElse("")));
            return request.createResponseBuilder(HttpStatus.SERVICE_UNAVAILABLE)
                    .header("Content-Type", "application/json")
                    .body(response)
                    .build();
        } catch (RuntimeException exception) {
            context.getLogger().severe(
                    "Cosmos activity write probe failed with " + exception.getClass().getName()
                            + ": " + exception.getMessage());
            String response = objectMapper.writeValueAsString(Map.of(
                    "error", "cosmos-write-probe-runtime-failure",
                    "exception", exception.getClass().getName(),
                    "message", Optional.ofNullable(exception.getMessage()).orElse("")));
            return request.createResponseBuilder(HttpStatus.INTERNAL_SERVER_ERROR)
                    .header("Content-Type", "application/json")
                    .body(response)
                    .build();
        }
    }
}
