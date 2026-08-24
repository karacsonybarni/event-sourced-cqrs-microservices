#!/usr/bin/env bash
set -Eeuo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
aws_region="${AWS_REGION:-eu-central-1}"
github_repository="${GITHUB_REPOSITORY:-karacsonybarni/event-sourced-cqrs-microservices}"
github_environment="${GITHUB_ENVIRONMENT:-cloud}"
terraform_apply_arguments=()

if [[ "${AUTO_APPROVE:-false}" == "true" ]]; then
  terraform_apply_arguments+=("-auto-approve")
fi

for command_name in aws gh terraform; do
  if ! command -v "${command_name}" >/dev/null; then
    echo "Required command is unavailable: ${command_name}" >&2
    exit 1
  fi
done

aws sts get-caller-identity >/dev/null
gh auth status --hostname github.com >/dev/null

verify_aws_service_access() {
  local service_name="$1"
  shift

  local error_output
  if ! error_output="$("$@" 2>&1 >/dev/null)"; then
    printf 'AWS account cannot access %s. New-account activation may still be in progress.\n%s\n' \
      "${service_name}" "${error_output}" >&2
    return 1
  fi
}

verify_aws_service_access "Amazon S3" aws s3api list-buckets --max-items 1
verify_aws_service_access "Amazon EC2 in ${aws_region}" \
  aws ec2 describe-regions --region "${aws_region}" --region-names "${aws_region}"

terraform -chdir="${repository_root}/infra/aws/bootstrap" init -input=false
terraform -chdir="${repository_root}/infra/aws/bootstrap" apply \
  -input=false \
  -var "aws_region=${aws_region}" \
  "${terraform_apply_arguments[@]}"

state_bucket="$(terraform -chdir="${repository_root}/infra/aws/bootstrap" output -raw state_bucket_name)"

terraform -chdir="${repository_root}/infra/aws" init \
  -input=false \
  -reconfigure \
  -backend-config="bucket=${state_bucket}" \
  -backend-config="region=${aws_region}"

main_apply_arguments=(
  -input=false
  -var "aws_region=${aws_region}"
  -var "github_repository=${github_repository}"
  -var "github_environment=${github_environment}"
)
if [[ -n "${BUDGET_ALERT_EMAIL:-}" ]]; then
  main_apply_arguments+=("-var" "budget_alert_email=${BUDGET_ALERT_EMAIL}")
fi
if [[ -n "${GITHUB_OIDC_PROVIDER_ARN:-}" ]]; then
  main_apply_arguments+=("-var" "github_oidc_provider_arn=${GITHUB_OIDC_PROVIDER_ARN}")
fi
main_apply_arguments+=("${terraform_apply_arguments[@]}")

terraform -chdir="${repository_root}/infra/aws" apply "${main_apply_arguments[@]}"

aws_account_id="$(terraform -chdir="${repository_root}/infra/aws" output -raw aws_account_id)"
deployment_role_arn="$(terraform -chdir="${repository_root}/infra/aws" output -raw deployment_role_arn)"
instance_id="$(terraform -chdir="${repository_root}/infra/aws" output -raw instance_id)"
public_api_url="$(terraform -chdir="${repository_root}/infra/aws" output -raw public_api_url)"

gh api \
  --method PUT \
  "repos/${github_repository}/environments/${github_environment}" \
  --silent
gh variable set AWS_ACCOUNT_ID --repo "${github_repository}" --body "${aws_account_id}"
gh variable set AWS_DEPLOY_ENABLED --repo "${github_repository}" --body "true"
gh variable set AWS_DEPLOY_ROLE_ARN --repo "${github_repository}" --body "${deployment_role_arn}"
gh variable set AWS_INSTANCE_ID --repo "${github_repository}" --body "${instance_id}"
gh variable set AWS_REGION --repo "${github_repository}" --body "${aws_region}"
gh variable set PUBLIC_API_URL --repo "${github_repository}" --body "${public_api_url}"

gh workflow run deploy-aws.yml --repo "${github_repository}" --ref main

printf 'AWS infrastructure is provisioned. Deployment workflow started for %s\n' "${public_api_url}"
