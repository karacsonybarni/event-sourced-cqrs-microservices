package com.karacsonybarni.orders.activity;

import java.lang.reflect.Method;
import java.util.Map;

import com.microsoft.azure.functions.HttpMethod;
import com.microsoft.azure.functions.HttpRequestMessage;
import com.microsoft.azure.functions.annotation.AuthorizationLevel;
import com.microsoft.azure.functions.annotation.BindingName;
import com.microsoft.azure.functions.annotation.FunctionName;
import com.microsoft.azure.functions.annotation.HttpTrigger;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

class OrderActivityQueryFunctionTest {

    @Test
    void exposesTheOrderPartitionAsAnAnonymousReadOnlyHttpQuery() throws NoSuchMethodException {
        Method function = OrderActivityQueryFunction.class.getMethod(
                "getOrderActivity",
                HttpRequestMessage.class,
                String.class,
                com.microsoft.azure.functions.ExecutionContext.class);

        assertThat(function.getAnnotation(FunctionName.class).value()).isEqualTo("getOrderActivity");

        HttpTrigger trigger = function.getParameters()[0].getAnnotation(HttpTrigger.class);
        assertThat(trigger.authLevel()).isEqualTo(AuthorizationLevel.ANONYMOUS);
        assertThat(trigger.methods()).containsExactly(HttpMethod.GET);
        assertThat(trigger.route()).isEqualTo("activity/{orderId:guid}");

        BindingName orderId = function.getParameters()[1].getAnnotation(BindingName.class);
        assertThat(orderId.value()).isEqualTo("orderId");
    }

    @Test
    void exposesOnlyThePublicActivityContract() {
        Map<String, Object> cosmosDocument = Map.of(
                "id", "event-1",
                "orderId", "order-1",
                "eventType", "OrderCreated.v1",
                "aggregateVersion", 1L,
                "occurredAt", "2026-01-10T10:15:30Z",
                "payload", Map.of("status", "CREATED"),
                "_etag", "opaque-cosmos-etag",
                "_ts", 123456789L);

        Map<String, Object> publicDocument = OrderActivityQueryFunction.publicDocument(cosmosDocument);

        assertThat(publicDocument)
                .containsOnlyKeys("id", "orderId", "eventType", "aggregateVersion", "occurredAt", "payload")
                .doesNotContainKeys("_etag", "_ts");
    }
}
