package com.karacsonybarni.orders.query;

import io.swagger.v3.oas.annotations.OpenAPIDefinition;
import io.swagger.v3.oas.annotations.info.Info;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

@OpenAPIDefinition(info = @Info(
        title = "Order Query API",
        version = "v1",
        description = "Eventually consistent CQRS read API"))
@SpringBootApplication
public class OrderQueryApplication {

    public static void main(String[] args) {
        SpringApplication.run(OrderQueryApplication.class, args);
    }
}
