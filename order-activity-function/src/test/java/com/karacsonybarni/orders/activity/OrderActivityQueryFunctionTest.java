package com.karacsonybarni.orders.activity;

import java.lang.reflect.Method;

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
        assertThat(trigger.route()).isEqualTo("activity/{orderId:guid}");

        BindingName orderId = function.getParameters()[1].getAnnotation(BindingName.class);
        assertThat(orderId.value()).isEqualTo("orderId");
    }
}
