# ADR-004: Credit-protected Azure deployment

- Status: Accepted
- Date: 2026-08-26

## Context

The complete local topology includes three PostgreSQL databases, Kafka, Debezium, Eureka, the gateway, replicated command and query services, and Inventory. Azure's 12-month free VM shapes provide only 1 GiB each, which cannot safely host this topology. Splitting it across several undersized VMs or replacing Kafka and Debezium with unrelated services would make the deployment fragile or change the architecture being demonstrated.

Azure Free Accounts include promotional credit and enable a subscription spending limit by default. A two-vCPU, 8-GiB burstable VM can run the already verified Compose topology within that credit, but it has a retail price and is not permanently free.

## Decision

Run the complete topology on one `Standard_B2as_v2` Linux VM while credit is active. Provision only when Azure reports the subscription as enabled and spending protection as `On`. Add a low resource-group budget, private versioned Terraform state, a stable DNS label, Caddy-managed HTTPS, boot diagnostics, and GitHub Actions deployment through Entra workload identity federation and Azure Run Command.

Keep the Azure runtime isolated from the preserved AWS infrastructure and disable AWS automatic deployment. Do not remove or rewrite the AWS Terraform state.

## Consequences

- The event-sourced CQRS, saga choreography, Debezium CDC, Kafka, Eureka, and multi-replica failover behavior remains identical across local, AWS, and Azure runtimes.
- Explicit 256 MiB Inventory database and 512 MiB Inventory service limits keep the demonstration within the existing VM shape, at the cost of reduced burst headroom that must be remeasured under representative load.
- No long-lived Azure credential is stored in GitHub; the federated identity trusts the repository's immutable numeric identity and `cloud` environment.
- The payment method is protected while the Azure spending limit remains `On`. When credit expires or is exhausted, Azure can stop the runtime and the endpoint becomes unavailable.
- The stable VM DNS name and HTTPS certificate provide a conventional public boundary, but the one-host topology is not highly available.
- A production evolution should use an orchestrator and managed stateful services across failure domains. That evolution is intentionally separate because it has a materially different recurring cost.
