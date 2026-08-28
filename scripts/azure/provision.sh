#!/usr/bin/env bash
set -Eeuo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
azure_location="${AZURE_LOCATION:-polandcentral}"
github_repository="${GITHUB_REPOSITORY:-karacsonybarni/event-sourced-cqrs-microservices}"
github_environment="${GITHUB_ENVIRONMENT:-cloud}"
azure_config_dir="${AZURE_CONFIG_DIR:?Set AZURE_CONFIG_DIR to a task-owned directory}"
bootstrap_state="${azure_config_dir}/terraform-bootstrap.tfstate"
ssh_directory="${azure_config_dir}/ssh"
ssh_private_key="${ssh_directory}/id_ed25519"
terraform_apply_arguments=()

initialize_runtime_state() {
  local attempt

  for attempt in {1..60}; do
    if terraform -chdir="${repository_root}/infra/azure" init \
      -input=false \
      -reconfigure \
      -backend-config="resource_group_name=${state_resource_group}" \
      -backend-config="storage_account_name=${state_storage_account}" \
      -backend-config="container_name=${state_container}"; then
      return 0
    fi

    if ((attempt == 60)); then
      echo "Azure Blob role assignment did not propagate within 10 minutes." >&2
      return 1
    fi

    printf 'Waiting for Azure Blob role assignment propagation (%d/60)\n' "${attempt}" >&2
    sleep 10
  done
}

if [[ "${AUTO_APPROVE:-false}" == "true" ]]; then
  terraform_apply_arguments+=("-auto-approve")
fi

for command_name in az curl gh jq ssh-keygen terraform; do
  if ! command -v "${command_name}" >/dev/null; then
    echo "Required command is unavailable: ${command_name}" >&2
    exit 1
  fi
done

az account show >/dev/null
gh auth status --hostname github.com >/dev/null
"${repository_root}/scripts/azure/verify-free-plan.sh"

subscription_id="$(az account show --query id --output tsv)"
tenant_id="$(az account show --query tenantId --output tsv)"
state_access_ip="$(curl --fail --silent --show-error --ipv4 https://api.ipify.org)"
github_repository_owner_id="$(gh api "repos/${github_repository}" --jq '.owner.id')"
github_repository_id="$(gh api "repos/${github_repository}" --jq '.id')"

install -d -m 0700 "${ssh_directory}"
if [[ ! -f "${ssh_private_key}" ]]; then
  ssh-keygen -q -t ed25519 -N '' -C 'event-sourced-cqrs Azure recovery' -f "${ssh_private_key}"
fi
admin_ssh_public_key="$(ssh-keygen -y -f "${ssh_private_key}")"

terraform -chdir="${repository_root}/infra/azure/bootstrap" init -backend=false -input=false
terraform -chdir="${repository_root}/infra/azure/bootstrap" apply \
  -input=false \
  -state="${bootstrap_state}" \
  -var "subscription_id=${subscription_id}" \
  -var "location=${azure_location}" \
  -var "state_access_ip=${state_access_ip}" \
  "${terraform_apply_arguments[@]}"

state_resource_group="$(terraform -chdir="${repository_root}/infra/azure/bootstrap" output -state="${bootstrap_state}" -raw resource_group_name)"
state_storage_account="$(terraform -chdir="${repository_root}/infra/azure/bootstrap" output -state="${bootstrap_state}" -raw storage_account_name)"
state_container="$(terraform -chdir="${repository_root}/infra/azure/bootstrap" output -state="${bootstrap_state}" -raw container_name)"

initialize_runtime_state

main_apply_arguments=(
  -input=false
  -var "subscription_id=${subscription_id}"
  -var "tenant_id=${tenant_id}"
  -var "azure_location=${azure_location}"
  -var "admin_ssh_public_key=${admin_ssh_public_key}"
  -var "github_repository=${github_repository}"
  -var "github_repository_owner_id=${github_repository_owner_id}"
  -var "github_repository_id=${github_repository_id}"
  -var "github_environment=${github_environment}"
)
if [[ -n "${BUDGET_ALERT_EMAIL:-}" ]]; then
  main_apply_arguments+=("-var" "budget_alert_email=${BUDGET_ALERT_EMAIL}")
fi
main_apply_arguments+=("${terraform_apply_arguments[@]}")

terraform -chdir="${repository_root}/infra/azure" apply "${main_apply_arguments[@]}"

gh api \
  --method PUT \
  -H "X-GitHub-Api-Version: 2026-03-10" \
  "repos/${github_repository}/actions/oidc/customization/sub" \
  -F use_default=true \
  -F use_immutable_subject=true \
  --silent

azure_client_id="$(terraform -chdir="${repository_root}/infra/azure" output -raw azure_client_id)"
resource_group_name="$(terraform -chdir="${repository_root}/infra/azure" output -raw resource_group_name)"
vm_name="$(terraform -chdir="${repository_root}/infra/azure" output -raw vm_name)"
public_api_url="$(terraform -chdir="${repository_root}/infra/azure" output -raw public_api_url)"
activity_function_name="$(terraform -chdir="${repository_root}/infra/azure" output -raw activity_function_name)"
activity_function_hostname="$(terraform -chdir="${repository_root}/infra/azure" output -raw activity_function_hostname)"

if [[ ! "${activity_function_hostname}" =~ ^[a-z0-9-]+\.azurewebsites\.net$ ]]; then
  echo "Unexpected Function App hostname: ${activity_function_hostname}" >&2
  exit 1
fi

runtime_initialization_output="$(az vm run-command invoke \
  --resource-group "${resource_group_name}" \
  --name "${vm_name}" \
  --command-id RunShellScript \
  --scripts "sudo cloud-init status --wait && sudo sed -i '/^ACTIVITY_FUNCTION_HOST=/d;/^KAFKA_VNET_HOST=/d' /etc/event-sourced-cqrs/runtime.env && printf '%s\\n' 'ACTIVITY_FUNCTION_HOST=${activity_function_hostname}' 'KAFKA_VNET_HOST=10.42.1.4' | sudo tee -a /etc/event-sourced-cqrs/runtime.env >/dev/null && sudo systemctl start event-sourced-cqrs.service && printf 'AZURE_RUNTIME_INITIALIZATION_SUCCEEDED\\n'" \
  --query 'value[].message' \
  --output tsv)"
printf '%s\n' "${runtime_initialization_output}"
grep --quiet '^AZURE_RUNTIME_INITIALIZATION_SUCCEEDED$' <<<"${runtime_initialization_output}"

gh api \
  --method PUT \
  "repos/${github_repository}/environments/${github_environment}" \
  --silent
gh variable set AWS_DEPLOY_ENABLED --repo "${github_repository}" --body "false"
gh variable set AZURE_CLIENT_ID --repo "${github_repository}" --body "${azure_client_id}"
gh variable set AZURE_FUNCTION_APP_NAME --repo "${github_repository}" --body "${activity_function_name}"
gh variable set AZURE_RESOURCE_GROUP --repo "${github_repository}" --body "${resource_group_name}"
gh variable set AZURE_SUBSCRIPTION_ID --repo "${github_repository}" --body "${subscription_id}"
gh variable set AZURE_TENANT_ID --repo "${github_repository}" --body "${tenant_id}"
gh variable set AZURE_VM_NAME --repo "${github_repository}" --body "${vm_name}"

gh workflow run deploy-azure.yml --repo "${github_repository}" --ref main

printf 'Azure infrastructure is provisioned. Deployment workflow started for %s\n' "${public_api_url}"
