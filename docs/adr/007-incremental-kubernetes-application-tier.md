# ADR-007: Incremental Kubernetes application tier on Azure

- Status: Accepted
- Date: 2026-08-29

## Context

The Azure environment runs the complete system on one credit-backed `Standard_B2as_v2` VM with two vCPUs and 8 GiB of memory. A live measurement before this change showed about 4.7 GiB in use and 3.1 GiB available. The project budget remains USD 25 per month, and the subscription spending limit is the hard no-charge boundary.

Moving directly to Azure Kubernetes Service (AKS) would require an AKS-compatible system node pool whose recurring VM cost is not compatible with the current budget; a production-recommended multi-node pool would widen that gap. Moving PostgreSQL, Kafka, and Debezium into a single-node Kubernetes cluster would add controllers and a data migration without improving durability or failure-domain isolation. Keeping Eureka inside Kubernetes would duplicate the service discovery and load-balancing capabilities already owned by Kubernetes Services.

The project still benefits from a real orchestration boundary for stateless application releases: immutable image revisions, declarative replica ownership, rolling updates, health probes, resource policy, service discovery, configuration, secret projection, network policy, and observable rollout state.

## Decision

Install a pinned, checksum-verified K3s distribution on the existing Azure VM. K3s is a conformant, resource-efficient Kubernetes distribution suitable for the project's single-node, credit-limited environment.

Move these stateless workloads to the `cqrs-orders` Kubernetes namespace:

- two Order command replicas;
- two Order query replicas;
- one Inventory saga participant;
- the API gateway;
- the React/Nginx frontend; and
- the Caddy public edge.

Use Kubernetes Services for application discovery. The gateway receives direct Kubernetes service URIs, and Eureka is disabled for Kubernetes pods. Local Docker Compose keeps Eureka so the existing local discovery and failover exercise remains intact.

Keep the three PostgreSQL databases, Kafka, and Debezium in Docker Compose for this increment. Selectorless Kubernetes Services and explicit EndpointSlices expose those platform dependencies to pods over the VM's private address. The K3s pod CIDR is `10.244.0.0/16`, deliberately separated from the Azure virtual network's `10.42.0.0/16` range.

Build application images from the exact deployment commit on the VM, import them into the single node's containerd image store, and deploy that immutable SHA as the image tag. Pin the external Caddy image by digest. This avoids a new registry and credential boundary while the cluster has exactly one node. A multi-node cluster must use a real registry and must not retain this node-local image path.

## Consequences

- Azure now exercises Kubernetes Deployments, Services, Kustomize overlays, EndpointSlices, startup/readiness/liveness probes, resource requests and limits, graceful termination, NetworkPolicies, Pod Security admission labels, secret/config projection, persistent edge certificate storage, and exact-revision rollout verification.
- Azure no longer runs Eureka. Kubernetes DNS and Services own application discovery and gateway load balancing there; local Compose continues to demonstrate Eureka-specific behavior.
- Existing PostgreSQL, Kafka, Debezium data, replication slots, connector offsets, and event history remain in place without a risky storage migration.
- The host operates both K3s and Docker Compose. This is a deliberate transitional boundary, not a preferred long-term production topology.
- The first migration briefly stops the Compose application tier before packaging and image builds so the constrained VM cannot exceed its measured memory headroom. A failed first cutover deletes the incomplete namespace and restores the Compose application tier; later failed rollouts restore the previously captured Deployment specifications.
- The five application Deployments roll without planned downtime, but the single Caddy replica uses a `Recreate` strategy because its node-local certificate volume is `ReadWriteOnce`; an edge configuration rollout can therefore cause a brief connection interruption.
- The single node, local-path Caddy volume, and node-local application images are not highly available. A host failure stops the synchronous path and Kafka processing.
- Horizontal Pod Autoscalers and PodDisruptionBudgets are intentionally absent. No representative load target has justified autoscaling, and a disruption budget on one node would not create availability.
- Production evolution should move stateless workloads to multi-node AKS, publish images through a managed registry, move PostgreSQL and Kafka to managed multi-zone services, and size replicas and autoscaling from measured service-level objectives.

## References

- [K3s installation requirements](https://docs.k3s.io/installation/requirements)
- [K3s resource profiling](https://docs.k3s.io/reference/resource-profiling)
- [AKS system node pools](https://learn.microsoft.com/azure/aks/use-system-pools)
- [AKS pricing tiers](https://learn.microsoft.com/azure/aks/free-standard-pricing-tiers)
