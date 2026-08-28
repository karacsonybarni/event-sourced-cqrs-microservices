package com.karacsonybarni.orders.activity;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;

import com.azure.cosmos.CosmosClient;
import com.azure.cosmos.CosmosClientBuilder;
import com.azure.cosmos.CosmosContainer;
import com.azure.cosmos.models.CosmosItemRequestOptions;
import com.azure.cosmos.models.CosmosQueryRequestOptions;
import com.azure.cosmos.models.PartitionKey;
import com.azure.cosmos.models.SqlParameter;
import com.azure.cosmos.models.SqlQuerySpec;
import com.azure.identity.ManagedIdentityCredentialBuilder;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ObjectNode;

final class CosmosOrderActivityStore implements OrderActivityStore {

    private static final ObjectMapper COSMOS_OBJECT_MAPPER = new ObjectMapper();

    private static final class Holder {
        private static final CosmosOrderActivityStore INSTANCE = fromEnvironment();
    }

    private final CosmosClient client;
    private final CosmosContainer container;

    private CosmosOrderActivityStore(CosmosClient client, CosmosContainer container) {
        this.client = client;
        this.container = container;
    }

    static CosmosOrderActivityStore instance() {
        return Holder.INSTANCE;
    }

    private static CosmosOrderActivityStore fromEnvironment() {
        String endpoint = requiredEnvironment("CosmosConnection__accountEndpoint");
        String clientId = requiredEnvironment("CosmosConnection__clientId");
        String databaseName = requiredEnvironment("COSMOS_DATABASE_NAME");
        String containerName = requiredEnvironment("COSMOS_CONTAINER_NAME");

        var credential = new ManagedIdentityCredentialBuilder()
                .clientId(clientId)
                .build();
        CosmosClient client = new CosmosClientBuilder()
                .endpoint(endpoint)
                .credential(credential)
                .gatewayMode()
                .buildClient();
        return new CosmosOrderActivityStore(
                client,
                client.getDatabase(databaseName).getContainer(containerName));
    }

    @Override
    public void upsert(Map<String, Object> document) {
        String orderId = requiredDocumentValue(document, "orderId");
        ObjectNode cosmosDocument = COSMOS_OBJECT_MAPPER.valueToTree(document);
        container.upsertItem(
                cosmosDocument,
                new PartitionKey(orderId),
                new CosmosItemRequestOptions());
    }

    @Override
    @SuppressWarnings({"rawtypes", "unchecked"})
    public List<Map<String, Object>> findByOrderId(String orderId) {
        var query = new SqlQuerySpec(
                "SELECT * FROM c WHERE c.orderId = @orderId ORDER BY c.aggregateVersion ASC",
                List.of(new SqlParameter("@orderId", orderId)));
        var options = new CosmosQueryRequestOptions()
                .setPartitionKey(new PartitionKey(orderId));
        List<Map<String, Object>> documents = new ArrayList<>();
        container.queryItems(query, options, Map.class)
                .forEach(document -> documents.add((Map<String, Object>) document));
        return documents;
    }

    private static String requiredEnvironment(String name) {
        String value = System.getenv(name);
        if (value == null || value.isBlank()) {
            throw new IllegalStateException("Required Function setting is missing: " + name);
        }
        return value;
    }

    private static String requiredDocumentValue(Map<String, Object> document, String name) {
        Object value = document.get(name);
        if (!(value instanceof String stringValue) || stringValue.isBlank()) {
            throw new IllegalArgumentException("Activity document is missing " + name);
        }
        return stringValue;
    }
}
