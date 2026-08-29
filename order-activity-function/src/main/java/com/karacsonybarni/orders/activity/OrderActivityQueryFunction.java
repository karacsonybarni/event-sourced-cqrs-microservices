package com.karacsonybarni.orders.activity;

import java.util.LinkedHashMap;
import java.util.List;
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

    private static final List<String> PUBLIC_FIELDS = List.of(
            "id",
            "orderId",
            "eventType",
            "aggregateVersion",
            "occurredAt",
            "payload");

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
            List<Map<String, Object>> activity = activityStore.findByOrderId(orderId).stream()
                    .map(OrderActivityQueryFunction::publicDocument)
                    .toList();
            String response = objectMapper.writeValueAsString(activity);
            return request.createResponseBuilder(HttpStatus.OK)
                    .header("Content-Type", "application/json")
                    .body(response)
                    .build();
        } catch (CosmosException exception) {
            context.getLogger().severe(
                    "Cosmos activity query failed with status " + exception.getStatusCode()
                            + " and substatus " + exception.getSubStatusCode());
            String response = objectMapper.writeValueAsString(Map.of(
                    "error", "activity-query-unavailable"));
            return request.createResponseBuilder(HttpStatus.SERVICE_UNAVAILABLE)
                    .header("Content-Type", "application/json")
                    .body(response)
                    .build();
        }
    }

    static Map<String, Object> publicDocument(Map<String, Object> document) {
        Map<String, Object> publicDocument = new LinkedHashMap<>();
        for (String field : PUBLIC_FIELDS) {
            if (document.containsKey(field)) {
                publicDocument.put(field, document.get(field));
            }
        }
        return publicDocument;
    }
}
