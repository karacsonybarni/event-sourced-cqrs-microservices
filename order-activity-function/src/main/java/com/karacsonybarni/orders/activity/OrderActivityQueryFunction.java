package com.karacsonybarni.orders.activity;

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
            String response = "{\"error\":\"cosmos-query-failed\",\"statusCode\":"
                    + exception.getStatusCode()
                    + ",\"subStatusCode\":"
                    + exception.getSubStatusCode()
                    + "}";
            return request.createResponseBuilder(HttpStatus.SERVICE_UNAVAILABLE)
                    .header("Content-Type", "application/json")
                    .body(response)
                    .build();
        }
    }
}
