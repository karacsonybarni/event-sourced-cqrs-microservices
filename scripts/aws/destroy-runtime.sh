#!/usr/bin/env bash
set -Eeuo pipefail

if [[ "${CONFIRM_DESTROY:-}" != "event-sourced-cqrs" ]]; then
  echo 'Set CONFIRM_DESTROY=event-sourced-cqrs to remove the runtime resources.' >&2
  exit 1
fi

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
aws_region="${AWS_REGION:-eu-central-1}"
github_repository="${GITHUB_REPOSITORY:-karacsonybarni/event-sourced-cqrs-microservices}"
github_environment="${GITHUB_ENVIRONMENT:-cloud}"

for command_name in gh terraform; do
  if ! command -v "${command_name}" >/dev/null; then
    echo "Required command is unavailable: ${command_name}" >&2
    exit 1
  fi
done

gh auth status --hostname github.com >/dev/null
github_repository_owner_id="$(gh api "repos/${github_repository}" --jq '.owner.id')"
github_repository_id="$(gh api "repos/${github_repository}" --jq '.id')"
gh variable set AWS_DEPLOY_ENABLED --repo "${github_repository}" --body "false"

terraform -chdir="${repository_root}/infra/aws" destroy \
  -var "aws_region=${aws_region}" \
  -var "github_repository=${github_repository}" \
  -var "github_repository_owner_id=${github_repository_owner_id}" \
  -var "github_repository_id=${github_repository_id}" \
  -var "github_environment=${github_environment}"

printf 'Runtime resources removed. The versioned Terraform state bucket was preserved.\n'
