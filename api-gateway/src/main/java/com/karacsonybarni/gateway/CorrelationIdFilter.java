package com.karacsonybarni.gateway;

import java.util.UUID;

import org.springframework.cloud.gateway.filter.GatewayFilterChain;
import org.springframework.cloud.gateway.filter.GlobalFilter;
import org.springframework.core.Ordered;
import org.springframework.http.server.reactive.ServerHttpRequest;
import org.springframework.stereotype.Component;
import org.springframework.web.server.ServerWebExchange;
import reactor.core.publisher.Mono;

@Component
class CorrelationIdFilter implements GlobalFilter, Ordered {

    static final String CORRELATION_ID = "X-Correlation-ID";

    @Override
    public Mono<Void> filter(ServerWebExchange exchange, GatewayFilterChain chain) {
        String requestedCorrelationId = exchange.getRequest().getHeaders().getFirst(CORRELATION_ID);
        String correlationId = requestedCorrelationId == null || requestedCorrelationId.isBlank()
                ? UUID.randomUUID().toString()
                : requestedCorrelationId;

        ServerHttpRequest request = exchange.getRequest().mutate()
                .headers(headers -> headers.set(CORRELATION_ID, correlationId))
                .build();
        exchange.getResponse().getHeaders().set(CORRELATION_ID, correlationId);
        return chain.filter(exchange.mutate().request(request).build());
    }

    @Override
    public int getOrder() {
        return Ordered.HIGHEST_PRECEDENCE;
    }
}
