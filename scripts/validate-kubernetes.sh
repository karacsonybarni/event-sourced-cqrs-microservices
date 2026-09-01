#!/usr/bin/env bash
set -Eeuo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
kubectl_image="registry.k8s.io/kubectl:v1.36.4@sha256:b8d523e7b8cdc5e3caa0f8891ee9f504abf137dec786e6e0ddd33e4f272c2f13"
kubeconform_image="ghcr.io/yannh/kubeconform:v0.8.0@sha256:faffaf43f95aa6425306e1ab8d6fcad72acb9049158f38e574c085ea1ec0f64e"

COMMAND_DB_PASSWORD=validation \
QUERY_DB_PASSWORD=validation \
INVENTORY_DB_PASSWORD=validation \
AWS_REGION=eu-central-1 \
CLOUDWATCH_LOG_GROUP=/validation/containers \
KAFKA_NODE_HOST=10.20.1.10 \
PLATFORM_HOST=10.20.1.10 \
  docker compose \
    --file compose.yml \
    --file compose.cloud.yml \
    --file compose.aws-kubernetes.yml \
    --file compose.kubernetes-platform.yml \
    config --quiet

for overlay in azure aws; do
  docker run --rm \
    --volume "${repository_root}:/workspace:ro" \
    --workdir /workspace \
    "${kubectl_image}" \
    kustomize "deploy/kubernetes/overlays/${overlay}" |
    docker run --rm --interactive \
      "${kubeconform_image}" \
      -strict \
      -summary \
      -kubernetes-version 1.36.0
done
