# Kafka failover integration handoff

Repository: karacsonybarni/event-sourced-cqrs-microservices
Target branch: codex/kafka-broker-failover
Starting implementation commit: 92b39178ad4de8790f5d9c2abf0449e6e5d5c778

## Objective

Prepare this feature branch for merging into current main, preserving both the Kafka failover feature and main's deployment behavior.

## Current state

The feature adds three Kafka broker/controllers, persistent storage migration, deployment configuration, and a broker failover smoke test. The implementation commit's CI passed. Local Maven verification, fresh Kafka bootstrap, persisted cluster startup, and saga traffic during broker outage with ISR recovery passed. Main has advanced; a merge preview reports a content conflict in scripts/aws/runtime-deploy.sh. An independent reviewer is separately inspecting the feature; do not assume this implies approval.

## Tasks

- [ ] Read the exact published revision and the target branch, current main, and relevant instructions.
- [ ] Integrate current main into the feature branch, resolving the AWS runtime deployment conflict while preserving both branches' intended behavior. Inspect automatically merged deployment files too.
- [ ] Run relevant validation, including Bash syntax and ShellCheck for changed scripts and Compose configuration validation. State any tests unavailable in this environment.
- [ ] Remove this task-scoped TODO.md before returning the implementation. No other task files are in scope for deletion.
- [ ] Push changes only to codex/kafka-broker-failover, or return a complete applicable patch if GitHub writes are unavailable.

## Constraints and acceptance

Do not merge the feature into main, force-push, change repository settings, deploy infrastructure, delete existing data volumes, or alter unrelated work. The coordinating agent handles independent review, final tests and the final PR merge. Feature completion requires that final merge, not merely a branch push. If a conflict requires a product decision, explain it rather than dropping either side.

Relevant files include scripts/aws/runtime-deploy.sh, compose.cloud.yml, README.md, kafka/*.sh, scripts/kafka/prepare-storage.sh, and scripts/kafka-broker-failover-test.sh. Inspect the full branch delta to understand integration effects.

Suggested validation: bash -n scripts/aws/runtime-deploy.sh; shellcheck scripts/aws/runtime-deploy.sh; docker compose --profile ui config --quiet. Validate the cloud overlay with placeholder database passwords, AWS_REGION and CLOUDWATCH_LOG_GROUP as shown in Makefile's cloud-config target.
