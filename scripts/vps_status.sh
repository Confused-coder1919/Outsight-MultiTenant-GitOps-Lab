#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="${ROOT_DIR}/infra/terraform"

if [[ -z "${KUBECONFIG:-}" && -f "${TF_DIR}/kubeconfig.yaml" ]]; then
  export KUBECONFIG="${TF_DIR}/kubeconfig.yaml"
fi

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

require_cmd kubectl

SERVER_URL="$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}' 2>/dev/null || true)"
HOST_IP="$(printf '%s' "$SERVER_URL" | sed -E 's#https?://([^:/]+).*#\1#')"
if [[ -z "$HOST_IP" || "$HOST_IP" == "$SERVER_URL" ]]; then
  HOST_IP="<node-ip>"
fi

echo "Cluster status"
kubectl get nodes

echo
echo "Key namespaces"
kubectl get ns argocd tenant-a tenant-b observability argo-rollouts ingress-nginx 2>/dev/null || kubectl get ns

echo
echo "Argo CD applications"
kubectl -n argocd get applications.argoproj.io -o wide || true

echo
echo "Rollouts"
if kubectl get crd rollouts.argoproj.io >/dev/null 2>&1; then
  kubectl get rollouts.argoproj.io -A || true
else
  echo "Rollout CRD is missing; rollouts are not available yet."
  echo "Hint: run 'make rollouts-up' then re-run this status check."
fi

if [[ -d "$TF_DIR" && -f "${TF_DIR}/terraform.tfstate" ]] && command -v terraform >/dev/null 2>&1; then
  echo
  echo "Terraform outputs"
  (
    cd "$TF_DIR"
    echo "Argo CD URL: $(terraform output -raw argocd_url 2>/dev/null || echo unavailable)"
    echo "Grafana URL: $(terraform output -raw grafana_url 2>/dev/null || echo unavailable)"
    echo "Argo CD password command: $(terraform output -raw argocd_initial_admin_password_command 2>/dev/null || echo unavailable)"
    echo "Grafana password command: $(terraform output -raw grafana_admin_password_command 2>/dev/null || echo unavailable)"
  )
else
  echo
  echo "Terraform state not found in ${TF_DIR}; skipping URL output lookup."
fi

echo
echo "Demo URLs (NodePort)"
echo "Argo CD:    https://${HOST_IP}:30443"
echo "Grafana:    http://${HOST_IP}:30000"
echo "Prometheus: http://${HOST_IP}:30090"
echo "Loki API:   http://${HOST_IP}:31000/ready"
echo
echo "Tenant app metrics (port-forward)"
echo "kubectl -n tenant-a port-forward svc/demo-api 18080:8000"
echo "kubectl -n tenant-b port-forward svc/demo-api 28080:8000"
