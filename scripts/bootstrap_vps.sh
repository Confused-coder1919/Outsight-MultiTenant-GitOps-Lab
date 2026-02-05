#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TERRAFORM_DIR="${ROOT_DIR}/infra/terraform"

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

for cmd in terraform ssh scp kubectl; do
  require_cmd "$cmd"
done

missing_env=0
for var in TF_VAR_VPS_IP TF_VAR_VPS_USER TF_VAR_SSH_KEY_PATH TF_VAR_GITOPS_REPO; do
  if [[ -z "${!var:-}" ]]; then
    echo "Missing required env var: ${var}" >&2
    missing_env=1
  fi
done
if [[ "$missing_env" -eq 1 ]]; then
  echo "Set the required TF_VAR_* values before running." >&2
  exit 1
fi

trap 'echo "Bootstrap failed. Troubleshooting tips:" >&2; echo "- Verify SSH connectivity: ssh ${TF_VAR_VPS_USER}@${TF_VAR_VPS_IP}" >&2; echo "- Check cluster: kubectl --kubeconfig=${TERRAFORM_DIR}/kubeconfig.yaml get pods -A" >&2; echo "- Inspect Argo CD: kubectl --kubeconfig=${TERRAFORM_DIR}/kubeconfig.yaml -n argocd get pods" >&2; echo "- Re-run: terraform apply in ${TERRAFORM_DIR}" >&2' ERR

cd "$TERRAFORM_DIR"

echo "Initializing Terraform..."
terraform init

if [[ "${TF_AUTO_APPROVE:-}" == "1" ]]; then
  echo "Applying Terraform (auto-approve enabled)..."
  terraform apply -auto-approve
else
  echo "Applying Terraform..."
  terraform apply
fi

export KUBECONFIG="${TERRAFORM_DIR}/kubeconfig.yaml"

echo "Waiting for namespaces to be created..."
for ns in argocd observability ingress-nginx; do
  for i in {1..60}; do
    if kubectl get namespace "$ns" >/dev/null 2>&1; then
      echo "Namespace $ns is present."
      break
    fi
    sleep 5
  done
  if ! kubectl get namespace "$ns" >/dev/null 2>&1; then
    echo "Timed out waiting for namespace $ns." >&2
    exit 1
  fi

done

echo "Waiting for core workloads to be ready..."
for ns in ingress-nginx argocd observability; do
  if kubectl -n "$ns" get deployment >/dev/null 2>&1; then
    kubectl -n "$ns" wait --for=condition=Available deployment --all --timeout=10m
  fi
  sts_list=$(kubectl -n "$ns" get statefulset -o name 2>/dev/null || true)
  if [[ -n "$sts_list" ]]; then
    while read -r sts; do
      kubectl -n "$ns" rollout status "$sts" --timeout=10m
    done <<< "$sts_list"
  fi
done

echo "Waiting for Argo CD Applications to be Synced and Healthy..."
wait_app() {
  local app="$1"
  local timeout=900
  local start
  start=$(date +%s)
  while true; do
    local sync health
    sync=$(kubectl -n argocd get application "$app" -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "Missing")
    health=$(kubectl -n argocd get application "$app" -o jsonpath='{.status.health.status}' 2>/dev/null || echo "Missing")
    if [[ "$sync" == "Synced" && "$health" == "Healthy" ]]; then
      echo "$app is Synced and Healthy."
      return 0
    fi
    if (( $(date +%s) - start > timeout )); then
      echo "Timed out waiting for $app (sync=$sync health=$health)." >&2
      return 1
    fi
    echo "Waiting for $app (sync=$sync health=$health)..."
    sleep 10
  done
}

wait_app demo-api-tenant-a
wait_app demo-api-tenant-b

echo "\nOutputs:"
terraform output -raw argocd_url
terraform output -raw grafana_url

echo "\nPassword commands:"
terraform output -raw argocd_initial_admin_password_command
terraform output -raw grafana_admin_password_command

echo "\nDone. Use KUBECONFIG=${TERRAFORM_DIR}/kubeconfig.yaml for kubectl commands."
