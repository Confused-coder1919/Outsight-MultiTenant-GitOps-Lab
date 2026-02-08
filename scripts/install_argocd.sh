#!/usr/bin/env bash
set -euo pipefail

ARGOCD_VERSION="${ARGOCD_VERSION:-v2.11.7}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if kubectl get namespace argocd >/dev/null 2>&1; then
  echo "Namespace 'argocd' already exists."
else
  echo "Creating namespace 'argocd'..."
  kubectl create namespace argocd
fi

echo "Installing Argo CD ${ARGOCD_VERSION}..."
kubectl apply -n argocd -f "https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"

echo "Waiting for Argo CD server to be ready..."
kubectl rollout status -n argocd deployment/argocd-server --timeout=180s

echo "Installing Argo Rollouts..."
"${ROOT_DIR}/scripts/install_argo_rollouts.sh"

echo "Argo CD and Argo Rollouts installed."
