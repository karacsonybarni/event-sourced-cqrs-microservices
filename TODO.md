# Kafka failover integration handoff

Repository: karacsonybarni/event-sourced-cqrs-microservices
Target branch: codex/kafka-broker-failover
Current base: main 259c637f9d5c4b5101c6968669d61c7d83752fb6 (feature commits rebased onto this revision)

## Objective

Prepare this feature branch for merging into current main, preserving both the Kafka failover feature and main's deployment behavior.

## Current state

The feature adds three Kafka broker/controllers, persistent storage migration, deployment configuration, and a broker failover smoke test. Prior to rebase, CI and local Maven, fresh bootstrap, restart and failover tests passed. The coordinating agent has now rebased onto main, preserving main's AWS Kubernetes flow and adding all three brokers to stateful startup. New local tests are pending until fixes are applied. Independent Astra review reported the five defects listed below; its re-review is required after fixes.

## Tasks

- [ ] Read the exact published revision and the target branch, current main, and relevant instructions.
- [x] Rebase onto main 259c637. Do not create a merge commit or repeat the old merge-based implementation; inspect the rebased files and preserve current main behavior.
- [ ] Fix confirmed migration review finding: kafka/reconcile-cluster.sh executes --generate output unchanged, which preserves RF1 instead of expanding it. Generate an explicit three-distinct-broker replica assignment for every existing governed partition, preserve partition identities and records, and prove RF1 to RF3 migration reaches ISR3. Avoid early-closing live Kafka command output pipes.
- [ ] Fix confirmed migration review finding: the AWS runtime entry point must run the storage preparation/migration before any Compose reconciliation can replace the original Kafka container and logs. Preserve main's deployment and readiness behavior while resolving the conflict.
- [ ] Fix confirmed redeployment review finding: scripts/azure/runtime-deploy.sh hardcodes a cluster ID from one deployment, rejecting subsequent deployments of a freshly generated cluster. Retain identity validation against persisted/live state and optional explicitly configured expected identity; do not impose a deployment-specific ID on all installations.
- [ ] Fix confirmed migration ordering finding: existing RF1 __consumer_offsets inherits broker min.insync.replicas=2, so the grouped probe cannot persist group metadata. Repair existing internal-topic replication before grouped or transactional probes, while still creating missing internal topics safely on fresh clusters. Do not rely on temporarily lowering minimum ISR for already protected traffic.
- [ ] Fix confirmed local startup finding: scripts/local/runtime-up.sh runs storage adoption before builds; adoption stops legacy Kafka and Connect, then a build failure leaves them stopped. Finish fallible Maven/image builds before entering storage adoption, or reliably restore prior state on failure.
- [ ] Run relevant validation, including Bash syntax and ShellCheck for changed scripts and Compose configuration validation. State any tests unavailable in this environment.
- [ ] Remove this task-scoped TODO.md before returning the implementation. No other task files are in scope for deletion.
- [ ] Push changes only to codex/kafka-broker-failover, or return a complete applicable patch if GitHub writes are unavailable.

## Constraints and acceptance

Do not merge the feature into main, force-push, change repository settings, deploy infrastructure, delete existing data volumes, or alter unrelated work. The coordinating agent handles independent review, final tests and the final PR merge. Feature completion requires that final merge, not merely a branch push. If a conflict requires a product decision, explain it rather than dropping either side.

Relevant files include scripts/aws/runtime-deploy.sh, compose.cloud.yml, README.md, kafka/*.sh, scripts/kafka/prepare-storage.sh, and scripts/kafka-broker-failover-test.sh. Inspect the full branch delta to understand integration effects.

Suggested validation: bash -n scripts/aws/runtime-deploy.sh; shellcheck scripts/aws/runtime-deploy.sh; docker compose --profile ui config --quiet. Validate the cloud overlay with placeholder database passwords, AWS_REGION and CLOUDWATCH_LOG_GROUP as shown in Makefile's cloud-config target.
