package com.karacsonybarni.gateway;

import static org.assertj.core.api.Assertions.assertThat;

import java.net.URI;
import java.util.Map;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.cloud.gateway.route.RouteDefinition;
import org.springframework.cloud.gateway.route.RouteDefinitionLocator;

@SpringBootTest(properties = {
        "eureka.client.enabled=false",
        "ORDER_COMMAND_URI=http://order-command-service:8081",
        "ORDER_QUERY_URI=http://order-query-service:8082"
})
class KubernetesGatewayRouteConfigurationTest {

    @Autowired
    private RouteDefinitionLocator routeDefinitionLocator;

    @Test
    void routesThroughKubernetesServicesWithoutEureka() {
        Map<String, URI> routeUris = routeDefinitionLocator.getRouteDefinitions()
                .collectMap(RouteDefinition::getId, RouteDefinition::getUri)
                .blockOptional()
                .orElseThrow();

        assertThat(routeUris)
                .containsEntry("order-commands", URI.create("http://order-command-service:8081"))
                .containsEntry("order-queries", URI.create("http://order-query-service:8082"));
    }
}
