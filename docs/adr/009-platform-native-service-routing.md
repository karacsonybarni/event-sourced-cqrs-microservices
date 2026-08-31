# ADR-009: Use deployment-platform service routing

- Status: Accepted
- Date: 2026-08-30
- Supersedes: ADR-002 and the discovery portions of ADR-003, ADR-004, and ADR-007

## Context

The gateway needs stable addresses for replicated command and query services in local Docker Compose, the single-host AWS deployment, and the Azure K3s application tier. Maintaining an application registry adds a service, client dependencies, lease configuration, health integration, and environment-specific behavior even though every deployment platform already provides stable service names.

Azure already routes through Kubernetes Services and ready endpoints. Local and AWS deployments can use Docker Compose service DNS without introducing another discovery mechanism or hard-coding container addresses.

## Decision

Use direct HTTP gateway routes whose host names are supplied by the deployment platform:

- standalone gateway defaults use `localhost` ports for direct development;
- local and AWS Compose use `order-command-service` and `order-query-service` service names; and
- Azure uses Kubernetes Services with the same names.

Application services do not register themselves. Docker Compose health checks gate startup and deployment, while the smoke tests count healthy containers and exercise the complete gateway path. The replica-failover test stops each command and query container in turn and requires traffic to succeed through the surviving service address. Kubernetes readiness probes continue to control Service endpoints in Azure.

## Consequences

- One runtime service and its server/client dependencies, configuration, image, port, and lease lifecycle are eliminated.
- Gateway routing has one direct-URI contract across standalone, Compose, and Kubernetes environments.
- Kubernetes retains readiness-aware endpoint selection and rolling updates.
- Compose DNS does not provide a separate health-aware registry. Startup health gates prevent initially unhealthy containers from serving, and the failover smoke allows bounded retries while Docker DNS and existing connections converge after a container stops.
- The single-host local and AWS environments continue to demonstrate application replica recovery, not host-level high availability. A production AWS topology should use ECS or EKS service routing.

## Alternatives considered

- **Retain an application registry for Compose only:** rejected because it preserves environment-specific application dependencies and an additional single point of failure.
- **Add a dedicated proxy for each backend service:** rejected because it adds another routing tier without a requirement that Compose DNS and the gateway cannot satisfy.
- **Configure container IP addresses:** rejected because replica addresses are ephemeral and owned by the deployment platform.
