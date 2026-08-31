# ADR-003: Cost-optimized AWS deployment

## Status

Superseded in part by ADR-009

## Context

The complete platform needs Kafka, Debezium Connect, three PostgreSQL databases, a registry, a gateway, replicated command and query services, and the event-driven Inventory service. Permanently managed equivalents would create significant fixed cost, while reducing the topology to one application or replacing Kafka would stop demonstrating the implemented consistency and delivery contracts.

The deployment must remain reproducible, externally reachable over HTTPS, observable, inexpensive to remove, and free of long-lived cloud credentials in CI.

## Decision

Provision a dedicated AWS VPC and one encrypted eight-GiB EC2 instance with Terraform. Run the existing Compose topology on that host with explicit memory limits and expose only Spring Cloud Gateway. Place an Amazon API Gateway HTTP API in front for a stable HTTPS client boundary, access logging, metrics, and throttling.

Use Systems Manager instead of SSH. GitHub Actions authenticates through an OIDC role restricted to the repository's `cloud` environment and can execute only the managed deployment document against the provisioned instance. Store Terraform state in a private, encrypted, versioned S3 bucket with native lock files. Send container and ingress logs to CloudWatch with short retention and create explicit budget and instance-health controls.

Generate database passwords on the instance during first bootstrap. They remain in a root-readable runtime environment file and never enter Git, GitHub Actions, Terraform input, or Terraform state.

## Consequences

- The full event-sourced CQRS, saga, and Debezium paths run without changing application semantics.
- Inventory reduces the eight-GiB host's previous spare headroom; its resource limits preserve the economical shape, but representative load must be remeasured before this becomes a capacity baseline.
- Provisioning, identity, networking, delivery, verification, logging, and teardown are reproducible and reviewable.
- The public client receives an AWS-managed HTTPS URL without purchasing a domain or load balancer.
- Free operation depends on account-specific AWS Free plan credits; this is not an always-free topology, and paid accounts can incur standard usage charges.
- One host is a deliberate cost boundary and a single point of failure. Application replica failover remains demonstrable, but host, Kafka, database, and registry high availability do not.
- Stopping and starting the instance can change its public hostname. A subsequent Terraform apply refreshes the API Gateway integration; a production environment would use private integrations and stable managed targets.
- Production evolution replaces the single host with ECS or EKS, managed multi-AZ databases and Kafka, a redundant or platform-native registry, managed secrets, private subnets, and an internal load balancer or VPC Link.
