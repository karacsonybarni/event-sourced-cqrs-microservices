#!/usr/bin/env bash
set -Eeuo pipefail

expected_revision="${1:?Pass the expected 40-character deployment revision}"
namespace="cqrs-orders"

if [[ ! "${expected_revision}" =~ ^[0-9a-f]{40}$ ]]; then
  echo "Expected deployment revision must be a complete Git SHA." >&2
  exit 1
fi

expected_deployments="$(
  printf '%s\n' \
    api-gateway \
    frontend \
    inventory-service \
    order-command-service \
    order-projection-worker \
    order-query-service
)"
actual_deployments="$(
  k3s kubectl --namespace "${namespace}" get deployments \
    --output jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' | sort
)"

if [[ "${actual_deployments}" != "${expected_deployments}" ]]; then
  printf 'Unexpected Kubernetes deployment set.\nExpected:\n%s\nActual:\n%s\n' \
    "${expected_deployments}" "${actual_deployments}" >&2
  exit 1
fi

for deployment in \
  api-gateway \
  frontend \
  inventory-service \
  order-command-service \
  order-projection-worker \
  order-query-service; do
  image="$(
    k3s kubectl --namespace "${namespace}" get "deployment/${deployment}" \
      --output jsonpath='{.spec.template.spec.containers[0].image}'
  )"
  case "${image}" in
    *:"${expected_revision}") ;;
    *)
      printf 'Deployment %s uses unexpected image %s.\n' "${deployment}" "${image}" >&2
      exit 1
      ;;
  esac
done

k3s kubectl --namespace "${namespace}" wait \
  --for=condition=Available deployment --all --timeout=180s

service_type="$(
  k3s kubectl --namespace "${namespace}" get service/frontend \
    --output jsonpath='{.spec.type}'
)"
service_port="$(
  k3s kubectl --namespace "${namespace}" get service/frontend \
    --output jsonpath='{.spec.ports[0].port}'
)"
if [[ "${service_type}" != "LoadBalancer" || "${service_port}" != "8080" ]]; then
  printf 'Frontend service has unexpected exposure %s:%s.\n' \
    "${service_type}" "${service_port}" >&2
  exit 1
fi

legacy_services="$(
  docker ps --format '{{.Label "com.docker.compose.service"}}' |
    grep -E '^(frontend|api-gateway|inventory-service|order-command-service|order-projection-worker|order-query-service)$' || true
)"
if [[ -n "${legacy_services}" ]]; then
  printf 'Legacy Compose application containers are still running:\n%s\n' \
    "${legacy_services}" >&2
  exit 1
fi

printf 'AWS Kubernetes runtime verified at revision %s\n' "${expected_revision}"
