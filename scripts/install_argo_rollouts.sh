#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PREFERRED_KUBECONFIG="${ROOT_DIR}/infra/terraform/kubeconfig.yaml"

if [[ -z "${KUBECONFIG:-}" && -f "$PREFERRED_KUBECONFIG" ]]; then
  export KUBECONFIG="$PREFERRED_KUBECONFIG"
  echo "Using kubeconfig: $KUBECONFIG"
fi

NAMESPACE="${ARGO_ROLLOUTS_NAMESPACE:-argo-rollouts}"
ARGO_ROLLOUTS_VERSION="${ARGO_ROLLOUTS_VERSION:-v1.7.2}"
MANIFEST_URL="https://github.com/argoproj/argo-rollouts/releases/download/${ARGO_ROLLOUTS_VERSION}/install.yaml"

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

for cmd in kubectl; do
  require_cmd "$cmd"
done

echo "Ensuring namespace '${NAMESPACE}' exists..."
kubectl create namespace "$NAMESPACE" >/dev/null 2>&1 || true

echo "Applying Argo Rollouts manifest (${ARGO_ROLLOUTS_VERSION})..."
kubectl apply -n "$NAMESPACE" -f "$MANIFEST_URL"

echo "Waiting for Argo Rollouts controller deployment..."
kubectl -n "$NAMESPACE" rollout status deploy/argo-rollouts --timeout=180s

echo "Verifying Rollouts CRD is present..."
kubectl get crd rollouts.argoproj.io >/dev/null

echo "Argo Rollouts installation complete."
