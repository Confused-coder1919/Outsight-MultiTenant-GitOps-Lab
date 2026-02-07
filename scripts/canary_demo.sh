#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TENANT="${TENANT:-tenant-a}"
VALUES_FILE="${ROOT_DIR}/charts/demo-api/tenants/${TENANT}-values.yaml"
BROKEN_TAG="${BROKEN_TAG:-sha-broken-canary}"
WAIT_SECONDS="${WAIT_SECONDS:-240}"
ROLLOUT_NAME="demo-api"

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

for cmd in kubectl helm yq; do
  require_cmd "$cmd"
done

if [[ ! -f "$VALUES_FILE" ]]; then
  echo "Values file not found: $VALUES_FILE" >&2
  exit 1
fi

if ! kubectl get ns "$TENANT" >/dev/null 2>&1; then
  echo "Namespace ${TENANT} does not exist. Deploy the tenant app first." >&2
  exit 1
fi

PREV_TAG="$(yq e '.image.tag' "$VALUES_FILE")"
if [[ -z "$PREV_TAG" || "$PREV_TAG" == "null" ]]; then
  echo "Could not read previous image tag from $VALUES_FILE" >&2
  exit 1
fi

rollback() {
  echo "Reverting ${TENANT} to previous tag ${PREV_TAG}..."
  yq -i ".image.tag = \"${PREV_TAG}\"" "$VALUES_FILE"
  helm template demo-api "$ROOT_DIR/charts/demo-api" -n "$TENANT" -f "$VALUES_FILE" | kubectl -n "$TENANT" apply -f - >/dev/null
}

trap 'rollback' EXIT

echo "Setting broken tag ${BROKEN_TAG} for ${TENANT}..."
yq -i ".image.tag = \"${BROKEN_TAG}\"" "$VALUES_FILE"
helm template demo-api "$ROOT_DIR/charts/demo-api" -n "$TENANT" -f "$VALUES_FILE" | kubectl -n "$TENANT" apply -f - >/dev/null

echo "Waiting for rollout to show paused/degraded state..."
start="$(date +%s)"
while true; do
  phase="$(kubectl -n "$TENANT" get rollout "$ROLLOUT_NAME" -o jsonpath='{.status.phase}' 2>/dev/null || true)"
  reason="$(kubectl -n "$TENANT" get rollout "$ROLLOUT_NAME" -o jsonpath='{.status.pauseConditions[0].reason}' 2>/dev/null || true)"

  if [[ "$phase" == "Degraded" || -n "$reason" ]]; then
    echo "Observed rollout signal: phase=${phase:-unknown}, pauseReason=${reason:-none}"
    break
  fi

  if (( $(date +%s) - start > WAIT_SECONDS )); then
    echo "Timed out after ${WAIT_SECONDS}s waiting for degraded/paused state." >&2
    break
  fi
  sleep 5
done

if kubectl argo rollouts version >/dev/null 2>&1; then
  kubectl argo rollouts get rollout "$ROLLOUT_NAME" -n "$TENANT"
else
  kubectl -n "$TENANT" get rollout "$ROLLOUT_NAME" -o wide
  kubectl -n "$TENANT" describe rollout "$ROLLOUT_NAME"
fi

rollback
trap - EXIT

echo "Canary demo completed. Current rollout status:"
kubectl -n "$TENANT" get rollout "$ROLLOUT_NAME" -o wide
