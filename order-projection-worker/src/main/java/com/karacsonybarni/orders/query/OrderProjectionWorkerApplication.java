package com.karacsonybarni.orders.query;

import java.time.Clock;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.context.annotation.Bean;

@SpringBootApplication
public class OrderProjectionWorkerApplication {

    public static void main(String[] args) {
        SpringApplication.run(OrderProjectionWorkerApplication.class, args);
    }

    @Bean
    Clock clock() {
        return Clock.systemUTC();
    }
}
