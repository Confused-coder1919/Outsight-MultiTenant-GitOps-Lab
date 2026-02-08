#!/usr/bin/env bash
set -euo pipefail

# Installs Argo Rollouts controller + CRDs in an idempotent way.
# Uses the official install manifest.
NAMESPACE="${ARGO_ROLLOUTS_NAMESPACE:-argo-rollouts}"

if kubectl api-resources | awk "{print \$1}" | grep -qx "rollouts"; then
  echo "[rollouts] API already present."
else
  echo "[rollouts] Installing Argo Rollouts..."
  kubectl create namespace "$NAMESPACE" >/dev/null 2>&1 || true
  kubectl apply -n "$NAMESPACE" -f https://github.com/argoproj/argo-rollouts/releases/latest/download/install.yaml
fi

echo "[rollouts] Waiting for controller deployment..."
kubectl -n "$NAMESPACE" rollout status deploy/argo-rollouts --timeout=180s
echo "[rollouts] OK"
