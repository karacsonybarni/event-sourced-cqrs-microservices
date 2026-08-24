package com.karacsonybarni.gateway;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.concurrent.atomic.AtomicReference;

import org.junit.jupiter.api.Test;
import org.springframework.cloud.gateway.filter.GatewayFilterChain;
import org.springframework.mock.http.server.reactive.MockServerHttpRequest;
import org.springframework.mock.web.server.MockServerWebExchange;
import org.springframework.web.server.ServerWebExchange;
import reactor.core.publisher.Mono;
import reactor.test.StepVerifier;

class CorrelationIdFilterTest {

    private final CorrelationIdFilter filter = new CorrelationIdFilter();

    @Test
    void generatesAndReturnsCorrelationIdWhenRequestDoesNotProvideOne() {
        ServerWebExchange exchange = MockServerWebExchange.from(MockServerHttpRequest.get("/api/orders"));
        AtomicReference<ServerWebExchange> forwardedExchange = new AtomicReference<>();
        GatewayFilterChain chain = forwarded -> {
            forwardedExchange.set(forwarded);
            return Mono.empty();
        };

        StepVerifier.create(filter.filter(exchange, chain)).verifyComplete();

        String correlationId = forwardedExchange.get().getRequest().getHeaders()
                .getFirst(CorrelationIdFilter.CORRELATION_ID);
        assertThat(correlationId).isNotBlank();
        assertThat(exchange.getResponse().getHeaders().getFirst(CorrelationIdFilter.CORRELATION_ID))
                .isEqualTo(correlationId);
    }

    @Test
    void preservesCallerProvidedCorrelationId() {
        ServerWebExchange exchange = MockServerWebExchange.from(MockServerHttpRequest.get("/api/orders")
                .header(CorrelationIdFilter.CORRELATION_ID, "caller-request-42"));
        AtomicReference<ServerWebExchange> forwardedExchange = new AtomicReference<>();

        StepVerifier.create(filter.filter(exchange, forwarded -> {
            forwardedExchange.set(forwarded);
            return Mono.empty();
        })).verifyComplete();

        assertThat(forwardedExchange.get().getRequest().getHeaders()
                .getFirst(CorrelationIdFilter.CORRELATION_ID)).isEqualTo("caller-request-42");
    }
}
