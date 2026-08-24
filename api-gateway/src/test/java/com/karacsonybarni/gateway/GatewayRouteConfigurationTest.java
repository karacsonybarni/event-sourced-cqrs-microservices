package com.karacsonybarni.gateway;

import static org.assertj.core.api.Assertions.assertThat;

import java.net.URI;
import java.util.Map;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.cloud.gateway.route.RouteDefinition;
import org.springframework.cloud.gateway.route.RouteDefinitionLocator;

@SpringBootTest(properties = "eureka.client.enabled=false")
class GatewayRouteConfigurationTest {

    @Autowired
    private RouteDefinitionLocator routeDefinitionLocator;

    @Test
    void routesCommandsAndQueriesThroughServiceDiscovery() {
        Map<String, URI> routeUris = routeDefinitionLocator.getRouteDefinitions()
                .collectMap(RouteDefinition::getId, RouteDefinition::getUri)
                .blockOptional()
                .orElseThrow();

        assertThat(routeUris)
                .containsEntry("order-commands", URI.create("lb://order-command-service"))
                .containsEntry("order-queries", URI.create("lb://order-query-service"));
    }
}
