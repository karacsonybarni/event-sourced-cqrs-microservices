package com.karacsonybarni.orders.activity;

import java.lang.reflect.Method;
import java.util.Optional;

import com.microsoft.azure.functions.annotation.AuthorizationLevel;
import com.microsoft.azure.functions.annotation.CosmosDBInput;
import com.microsoft.azure.functions.annotation.FunctionName;
import com.microsoft.azure.functions.annotation.HttpTrigger;
import org.junit.jupiter.api.Test;
import tools.jackson.databind.JsonNode;
import tools.jackson.databind.ObjectMapper;

import static org.assertj.core.api.Assertions.assertThat;

class OrderActivityQueryFunctionTest {

    @Test
    void exposesTheOrderPartitionAsAnAnonymousReadOnlyHttpQuery() throws NoSuchMethodException {
        Method function = OrderActivityQueryFunction.class.getMethod(
                "getOrderActivity",
                Optional.class,
                String[].class);

        assertThat(function.getAnnotation(FunctionName.class).value()).isEqualTo("getOrderActivity");

        HttpTrigger trigger = function.getParameters()[0].getAnnotation(HttpTrigger.class);
        assertThat(trigger.authLevel()).isEqualTo(AuthorizationLevel.ANONYMOUS);
        assertThat(trigger.route()).isEqualTo("activity/{orderId:guid}");

        CosmosDBInput input = function.getParameters()[1].getAnnotation(CosmosDBInput.class);
        assertThat(input.databaseName()).isEqualTo("%COSMOS_DATABASE_NAME%");
        assertThat(input.containerName()).isEqualTo("%COSMOS_CONTAINER_NAME%");
        assertThat(input.connection()).isEqualTo("CosmosConnection");
        assertThat(input.sqlQuery())
                .isEqualTo("SELECT * FROM c WHERE c.orderId = {orderId} ORDER BY c.aggregateVersion ASC");
    }

    @Test
    void returnsTheProjectedOrderActivityAsAJsonArray() throws Exception {
        String created = """
                {"id":"event-1","orderId":"order-1","eventType":"OrderCreated.v1","aggregateVersion":1}
                """;
        String cancelled = """
                {"id":"event-2","orderId":"order-1","eventType":"OrderCancelled.v1","aggregateVersion":2}
                """;

        String response = new OrderActivityQueryFunction()
                .getOrderActivity(Optional.empty(), new String[]{created, cancelled});
        JsonNode body = new ObjectMapper().readTree(response);

        assertThat(body).hasSize(2);
        assertThat(body.get(0).required("eventType").asString()).isEqualTo("OrderCreated.v1");
        assertThat(body.get(1).required("eventType").asString()).isEqualTo("OrderCancelled.v1");
    }
}
