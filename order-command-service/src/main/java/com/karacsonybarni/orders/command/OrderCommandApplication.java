package com.karacsonybarni.orders.command;

import java.time.Clock;

import io.swagger.v3.oas.annotations.OpenAPIDefinition;
import io.swagger.v3.oas.annotations.info.Info;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.context.annotation.Bean;
import org.springframework.scheduling.annotation.EnableScheduling;

@EnableScheduling
@OpenAPIDefinition(info = @Info(
        title = "Order Command API",
        version = "v1",
        description = "CQRS write API backed by a transactional outbox"))
@SpringBootApplication
public class OrderCommandApplication {

    public static void main(String[] args) {
        SpringApplication.run(OrderCommandApplication.class, args);
    }

    @Bean
    Clock clock() {
        return Clock.systemUTC();
    }
}
