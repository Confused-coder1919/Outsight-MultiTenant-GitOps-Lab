#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PREFERRED_KUBECONFIG="${ROOT_DIR}/infra/terraform/kubeconfig.yaml"

if [[ -z "${KUBECONFIG:-}" && -f "$PREFERRED_KUBECONFIG" ]]; then
  export KUBECONFIG="$PREFERRED_KUBECONFIG"
  echo "Using kubeconfig: $KUBECONFIG"
fi

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

for cmd in helm kubectl; do
  require_cmd "$cmd"
done

echo "Installing/upgrading Argo Rollouts via Helm..."
helm repo add argo https://argoproj.github.io/argo-helm || true
helm repo update

helm upgrade --install argo-rollouts argo/argo-rollouts \
  --namespace argo-rollouts \
  --create-namespace

echo "Waiting for Argo Rollouts controller deployment..."
kubectl -n argo-rollouts rollout status deploy/argo-rollouts --timeout=180s

echo "Verifying Rollout CRD exists..."
kubectl get crd rollouts.argoproj.io >/dev/null

echo "Argo Rollouts installation complete."
