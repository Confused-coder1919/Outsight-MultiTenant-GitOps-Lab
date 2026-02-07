#!/usr/bin/env bash
set -euo pipefail

ARGOCD_VERSION="${ARGOCD_VERSION:-v2.11.7}"
ARGO_ROLLOUTS_VERSION="${ARGO_ROLLOUTS_VERSION:-v1.7.2}"

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

if kubectl get namespace argo-rollouts >/dev/null 2>&1; then
  echo "Namespace 'argo-rollouts' already exists."
else
  echo "Creating namespace 'argo-rollouts'..."
  kubectl create namespace argo-rollouts
fi

echo "Installing Argo Rollouts ${ARGO_ROLLOUTS_VERSION}..."
kubectl apply -n argo-rollouts -f "https://github.com/argoproj/argo-rollouts/releases/download/${ARGO_ROLLOUTS_VERSION}/install.yaml"

echo "Waiting for Argo Rollouts controller to be ready..."
kubectl rollout status -n argo-rollouts deployment/argo-rollouts --timeout=180s

echo "Argo CD and Argo Rollouts installed."
