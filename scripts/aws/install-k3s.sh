#!/usr/bin/env bash
set -Eeuo pipefail

k3s_version="v1.36.4+k3s1"
installer_sha256="46177d4c99440b4c0311b67233823a8e8a2fc09693f6c89af1a7161e152fbfad"

download_directory="$(mktemp -d)"
trap 'rm -rf "${download_directory}"' EXIT
installer="${download_directory}/install-k3s.sh"
desired_config="${download_directory}/config.yaml"
config_changed="false"

wait_for_node_ready() {
  for _ in {1..90}; do
    if [[ -n "$(k3s kubectl get nodes --no-headers 2>/dev/null || true)" ]]; then
      k3s kubectl wait --for=condition=Ready node --all --timeout=180s
      return
    fi
    sleep 2
  done
  echo "K3s did not register a node in time." >&2
  return 1
}

wait_for_local_path_provisioner() {
  for _ in {1..60}; do
    if k3s kubectl --namespace kube-system get deployment/local-path-provisioner >/dev/null 2>&1; then
      k3s kubectl --namespace kube-system rollout status deployment/local-path-provisioner --timeout=180s
      return
    fi
    sleep 2
  done
  echo "K3s did not create the local-path-provisioner deployment in time." >&2
  return 1
}

printf '%s\n' \
  'disable:' \
  '  - traefik' \
  'secrets-encryption: true' \
  'cluster-cidr: 10.244.0.0/16' \
  'service-cidr: 10.96.0.0/12' \
  'kubelet-arg:' \
  '  - system-reserved=cpu=200m,memory=1536Mi' \
  '  - eviction-hard=memory.available<512Mi,nodefs.available<10%' \
  >"${desired_config}"

install --directory --mode 0755 /etc/rancher/k3s
if ! cmp --silent "${desired_config}" /etc/rancher/k3s/config.yaml 2>/dev/null; then
  install --mode 0600 "${desired_config}" /etc/rancher/k3s/config.yaml
  config_changed="true"
fi

if command -v k3s >/dev/null && k3s --version | grep --fixed-strings --quiet "${k3s_version}"; then
  systemctl enable k3s
  if [[ "${config_changed}" == "true" ]] && systemctl is-active --quiet k3s; then
    systemctl restart k3s
  else
    systemctl start k3s
  fi
  wait_for_node_ready
  wait_for_local_path_provisioner
  exit 0
fi

curl --fail --silent --show-error --location \
  "https://raw.githubusercontent.com/k3s-io/k3s/${k3s_version}/install.sh" \
  --output "${installer}"
printf '%s  %s\n' "${installer_sha256}" "${installer}" | sha256sum --check

INSTALL_K3S_VERSION="${k3s_version}" sh "${installer}"
systemctl enable --now k3s
wait_for_node_ready
wait_for_local_path_provisioner
