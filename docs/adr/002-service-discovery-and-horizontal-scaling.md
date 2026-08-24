# ADR-002: Use registry-backed gateway routing for local horizontal scaling

- Status: Accepted
- Date: 2026-08-24

## Context

Command and query services must run as replaceable replicas whose network locations can change. Static gateway URLs neither select among instances nor stop routing to an instance that has failed. The repository also needs an executable local topology rather than deployment claims that are only inferred from stateless application code.

## Decision

Run a standalone Eureka registry in the local Compose topology. The command service, query service, and gateway register themselves and publish health through Spring Boot Actuator. External clients call only the gateway. Its method-aware routes use Spring Cloud LoadBalancer URIs:

```text
lb://order-command-service
lb://order-query-service
```

Run two command replicas and two query replicas by default. Publish random backend host ports to avoid collisions while keeping service-to-service traffic on the Compose network. Verify the topology by stopping every business-service replica in turn, waiting for registry eviction, exercising traffic through the surviving replica, and restoring the stopped instance.

Use short leases and disable registry self-preservation only in this deterministic local environment. Production deployments must use a highly available registry with appropriate lease policy or the deployment platform's native service discovery and load balancing.

## Consequences

Positive:

- external clients remain unaware of individual service locations;
- the gateway selects among dynamically registered instances;
- failed instances leave the routing set after lease expiration;
- multi-replica command and projection behavior is executable and regression-tested;
- the registry dashboard makes topology changes observable.

Negative:

- Eureka adds another stateful runtime component;
- registry convergence creates a bounded failover delay;
- local lease settings are intentionally more aggressive than production settings;
- the single local registry is not highly available;
- platform-native discovery would make Eureka redundant in environments such as Kubernetes.

## Alternatives considered

- **Static gateway URLs:** simplest for one instance but cannot demonstrate dynamic instance selection or failover.
- **Docker DNS alone:** resolves service names but does not expose an explicit health-aware registry and load-balancer contract in the Spring architecture.
- **Kubernetes Services:** a conventional production choice, but requiring a cluster would make the repository's primary local workflow substantially heavier.
- **Client-side discovery in external consumers:** duplicates discovery concerns and violates the gateway boundary.
