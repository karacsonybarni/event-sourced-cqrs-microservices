package com.karacsonybarni.orders.activity;

import java.util.Optional;

import com.microsoft.azure.functions.HttpMethod;
import com.microsoft.azure.functions.annotation.AuthorizationLevel;
import com.microsoft.azure.functions.annotation.CosmosDBInput;
import com.microsoft.azure.functions.annotation.FunctionName;
import com.microsoft.azure.functions.annotation.HttpTrigger;
import tools.jackson.core.JacksonException;
import tools.jackson.databind.ObjectMapper;
import tools.jackson.databind.node.ArrayNode;

public class OrderActivityQueryFunction {

    private final ObjectMapper objectMapper = new ObjectMapper();

    @FunctionName("getOrderActivity")
    public String getOrderActivity(
            @HttpTrigger(
                    name = "request",
                    methods = HttpMethod.GET,
                    authLevel = AuthorizationLevel.ANONYMOUS,
                    route = "activity/{orderId:guid}") Optional<String> request,
            @CosmosDBInput(
                    name = "activityDocuments",
                    databaseName = "%COSMOS_DATABASE_NAME%",
                    containerName = "%COSMOS_CONTAINER_NAME%",
                    connection = "CosmosConnection",
                    sqlQuery = "SELECT * FROM c WHERE c.orderId = {orderId} ORDER BY c.aggregateVersion ASC")
                    String[] activityDocuments) throws JacksonException {
        ArrayNode response = objectMapper.createArrayNode();
        for (String activityDocument : activityDocuments) {
            response.add(objectMapper.readTree(activityDocument));
        }
        return objectMapper.writeValueAsString(response);
    }
}
