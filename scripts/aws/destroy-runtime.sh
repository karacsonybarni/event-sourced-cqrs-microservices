#!/usr/bin/env bash
set -Eeuo pipefail

if [[ "${CONFIRM_DESTROY:-}" != "event-sourced-cqrs" ]]; then
  echo 'Set CONFIRM_DESTROY=event-sourced-cqrs to remove the runtime resources.' >&2
  exit 1
fi

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
aws_region="${AWS_REGION:-eu-central-1}"
github_repository="${GITHUB_REPOSITORY:-karacsonybarni/event-sourced-cqrs-microservices}"

if ! command -v gh >/dev/null; then
  echo "Required command is unavailable: gh" >&2
  exit 1
fi

gh auth status --hostname github.com >/dev/null
gh variable set AWS_DEPLOY_ENABLED --repo "${github_repository}" --body "false"

terraform -chdir="${repository_root}/infra/aws" destroy \
  -var "aws_region=${aws_region}"

printf 'Runtime resources removed. The versioned Terraform state bucket was preserved.\n'
