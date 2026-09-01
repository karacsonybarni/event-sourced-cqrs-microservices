#!/usr/bin/env bash
set -Eeuo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
aws_region="${AWS_REGION:-eu-central-1}"
project_name="${PROJECT_NAME:-event-sourced-cqrs}"
github_repository="${GITHUB_REPOSITORY:-karacsonybarni/event-sourced-cqrs-microservices}"
github_environment="${GITHUB_ENVIRONMENT:-cloud}"
plan_file=".origin-recovery.tfplan"

for command_name in aws gh terraform; do
  if ! command -v "${command_name}" >/dev/null; then
    echo "Required command is unavailable: ${command_name}" >&2
    exit 1
  fi
done

aws_account_id="$(aws sts get-caller-identity --query Account --output text)"
gh auth status --hostname github.com >/dev/null

state_bucket="${project_name}-${aws_account_id}-tfstate"
if ! aws s3api head-bucket --bucket "${state_bucket}" >/dev/null 2>&1; then
  echo "Existing Terraform state bucket is not accessible: ${state_bucket}" >&2
  echo "Refusing to bootstrap or create replacement infrastructure from this maintenance script." >&2
  exit 1
fi

owner_id="$(gh api "repos/${github_repository}" --jq '.owner.id')"
repository_id="$(gh api "repos/${github_repository}" --jq '.id')"

terraform -chdir="${repository_root}/infra/aws" init \
  -input=false \
  -reconfigure \
  -backend-config="bucket=${state_bucket}" \
  -backend-config="region=${aws_region}"

rm -f "${repository_root}/infra/aws/${plan_file}"
trap 'rm -f "${repository_root}/infra/aws/${plan_file}"' EXIT

terraform -chdir="${repository_root}/infra/aws" plan \
  -input=false \
  -var "aws_region=${aws_region}" \
  -var "project_name=${project_name}" \
  -var "github_repository=${github_repository}" \
  -var "github_repository_owner_id=${owner_id}" \
  -var "github_repository_id=${repository_id}" \
  -var "github_environment=${github_environment}" \
  -target=aws_iam_role_policy.instance_gateway_origin \
  -target=aws_ssm_association.gateway_origin_refresh \
  -out="${plan_file}"

terraform -chdir="${repository_root}/infra/aws" apply \
  -input=false \
  "${plan_file}"

instance_id="$(terraform -chdir="${repository_root}/infra/aws" output -raw instance_id)"
public_api_url="$(terraform -chdir="${repository_root}/infra/aws" output -raw public_api_url)"
public_dns="$(aws ec2 describe-instances \
  --instance-ids "${instance_id}" \
  --region "${aws_region}" \
  --query 'Reservations[0].Instances[0].PublicDnsName' \
  --output text)"
api_id="$(aws apigatewayv2 get-apis \
  --region "${aws_region}" \
  --query "Items[?Name=='${project_name}-${github_environment}'].ApiId | [0]" \
  --output text)"
integration_id="$(aws apigatewayv2 get-integrations \
  --api-id "${api_id}" \
  --region "${aws_region}" \
  --query 'Items[0].IntegrationId' \
  --output text)"
integration_uri="$(aws apigatewayv2 get-integration \
  --api-id "${api_id}" \
  --integration-id "${integration_id}" \
  --region "${aws_region}" \
  --query 'IntegrationUri' \
  --output text)"
expected_uri="http://${public_dns}:8080"

if [[ -z "${public_dns}" || "${public_dns}" == "None" ]]; then
  echo "EC2 instance ${instance_id} has no public DNS hostname." >&2
  exit 1
fi
if [[ "${integration_uri}" != "${expected_uri}" ]]; then
  echo "API Gateway origin verification failed." >&2
  echo "Expected: ${expected_uri}" >&2
  echo "Actual:   ${integration_uri}" >&2
  exit 1
fi

printf 'Origin recovery installed and API Gateway points to %s\n' "${expected_uri}"
printf 'Public API remains %s\n' "${public_api_url}"

gh workflow run deploy-aws.yml --repo "${github_repository}" --ref main
printf 'Triggered the AWS deployment workflow for final public smoke verification.\n'
