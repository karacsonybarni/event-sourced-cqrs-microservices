#!/usr/bin/env bash
set -Eeuo pipefail

for command_name in az jq; do
  if ! command -v "${command_name}" >/dev/null; then
    echo "Required command is unavailable: ${command_name}" >&2
    exit 1
  fi
done

subscription_id="$(az account show --query id --output tsv)"
subscription_policy="$(az rest \
  --method GET \
  --url "https://management.azure.com/subscriptions/${subscription_id}?api-version=2020-01-01")"

subscription_state="$(jq -r '.state' <<<"${subscription_policy}")"
spending_limit="$(jq -r '.subscriptionPolicies.spendingLimit' <<<"${subscription_policy}")"
quota_id="$(jq -r '.subscriptionPolicies.quotaId' <<<"${subscription_policy}")"

if [[ "${subscription_state}" != "Enabled" ]]; then
  echo "Azure subscription is not enabled: ${subscription_state}" >&2
  exit 1
fi

if [[ "${spending_limit}" != "On" ]]; then
  cat >&2 <<EOF
Azure spending protection is not enabled (value: ${spending_limit}).
Provisioning is blocked because this deployment may not charge a payment method.
EOF
  exit 1
fi

if [[ -z "${quota_id}" || "${quota_id}" == "null" ]]; then
  echo "Azure did not expose the subscription offer identifier; free-plan verification cannot continue." >&2
  exit 1
fi

printf 'Azure subscription is enabled with spending protection On (offer %s).\n' "${quota_id}"
