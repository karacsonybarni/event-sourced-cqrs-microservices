package com.karacsonybarni.gateway;

import static org.assertj.core.api.Assertions.assertThat;

import java.net.URI;
import java.util.Map;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.cloud.gateway.route.RouteDefinition;
import org.springframework.cloud.gateway.route.RouteDefinitionLocator;

@SpringBootTest
class GatewayRouteConfigurationTest {

    @Autowired
    private RouteDefinitionLocator routeDefinitionLocator;

    @Test
    void routesCommandsAndQueriesToLocalServicesByDefault() {
        Map<String, URI> routeUris = routeDefinitionLocator.getRouteDefinitions()
                .collectMap(RouteDefinition::getId, RouteDefinition::getUri)
                .blockOptional()
                .orElseThrow();

        assertThat(routeUris)
                .containsEntry("order-commands", URI.create("http://localhost:8081"))
                .containsEntry("order-queries", URI.create("http://localhost:8082"));
    }
}
