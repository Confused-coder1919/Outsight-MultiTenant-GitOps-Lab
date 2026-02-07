#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TENANT="${TENANT:-tenant-a}"
HELM_RELEASE="${HELM_RELEASE:-demo-api-${TENANT}}"
VALUES_FILE="${ROOT_DIR}/charts/demo-api/tenants/${TENANT}-values.yaml"
ROLLOUT_NAME="${ROLLOUT_NAME:-demo-api}"
SUCCESS_TAG="${SUCCESS_TAG:-main}"
WAIT_SECONDS="${WAIT_SECONDS:-480}"
TRAFFIC_SECONDS="${TRAFFIC_SECONDS:-150}"
HEALTHY_RPS="${HEALTHY_RPS:-4}"

if [[ -z "${KUBECONFIG:-}" && -f "${ROOT_DIR}/infra/terraform/kubeconfig.yaml" ]]; then
  export KUBECONFIG="${ROOT_DIR}/infra/terraform/kubeconfig.yaml"
fi

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

for cmd in kubectl helm awk mktemp; do
  require_cmd "$cmd"
done

ensure_rollouts_available() {
  if kubectl get crd rollouts.argoproj.io >/dev/null 2>&1; then
    return
  fi
  if [[ -x "${ROOT_DIR}/scripts/install_argo_rollouts.sh" ]]; then
    echo "Rollout CRD missing; installing Argo Rollouts..."
    "${ROOT_DIR}/scripts/install_argo_rollouts.sh"
  fi
  kubectl get crd rollouts.argoproj.io >/dev/null 2>&1 || {
    echo "rollouts.argoproj.io CRD is still missing after install attempt." >&2
    exit 1
  }
}

ensure_rollouts_available

if [[ ! -f "$VALUES_FILE" ]]; then
  echo "Values file not found: $VALUES_FILE" >&2
  exit 1
fi

if ! kubectl get ns "$TENANT" >/dev/null 2>&1; then
  echo "Namespace ${TENANT} does not exist. Run make gitops first." >&2
  exit 1
fi

if ! kubectl -n "$TENANT" get rollout "$ROLLOUT_NAME" >/dev/null 2>&1; then
  echo "Rollout ${ROLLOUT_NAME} not found in ${TENANT}. Install Argo Rollouts and deploy GitOps first." >&2
  exit 1
fi

get_image_tag() {
  awk '
    /^image:[[:space:]]*$/ { in_image = 1; next }
    in_image && /^[^[:space:]]/ { in_image = 0 }
    in_image && /^[[:space:]]*tag:[[:space:]]*/ {
      gsub(/"/, "", $2)
      print $2
      exit
    }
  ' "$1"
}

CURRENT_TAG="$(get_image_tag "$VALUES_FILE")"
if [[ -z "$CURRENT_TAG" ]]; then
  echo "Could not parse image.tag from ${VALUES_FILE}" >&2
  exit 1
fi

if [[ "$SUCCESS_TAG" == "$CURRENT_TAG" ]]; then
  echo "SUCCESS_TAG (${SUCCESS_TAG}) matches current tag (${CURRENT_TAG}). Set SUCCESS_TAG to a different known-good tag." >&2
  exit 1
fi

OVERRIDE_FILE="$(mktemp)"
cat >"$OVERRIDE_FILE" <<YAML
demoFailureEndpoint:
  enabled: false
image:
  tag: "$SUCCESS_TAG"
YAML

loadgen_pid=""
revert_needed=true

cleanup() {
  if [[ -n "$loadgen_pid" ]]; then
    kill "$loadgen_pid" >/dev/null 2>&1 || true
    wait "$loadgen_pid" >/dev/null 2>&1 || true
  fi

  if [[ "$revert_needed" == true ]]; then
    echo "Reverting ${TENANT} to chart values after interruption/failure..."
    helm template "$HELM_RELEASE" "${ROOT_DIR}/charts/demo-api" -n "$TENANT" -f "$VALUES_FILE" \
      | kubectl -n "$TENANT" apply -f - >/dev/null
  fi

  rm -f "$OVERRIDE_FILE"
}
trap cleanup EXIT INT TERM

echo "Applying candidate tag ${SUCCESS_TAG} to ${TENANT}..."
helm template "$HELM_RELEASE" "${ROOT_DIR}/charts/demo-api" -n "$TENANT" -f "$VALUES_FILE" -f "$OVERRIDE_FILE" \
  | kubectl -n "$TENANT" apply -f - >/dev/null

echo "Generating healthy traffic during canary analysis window..."
"${ROOT_DIR}/scripts/loadgen.sh" \
  --tenant "$TENANT" \
  --duration "$TRAFFIC_SECONDS" \
  --healthy-rps "$HEALTHY_RPS" &
loadgen_pid="$!"

start_time="$(date +%s)"
completed=false

while true; do
  phase="$(kubectl -n "$TENANT" get rollout "$ROLLOUT_NAME" -o jsonpath='{.status.phase}' 2>/dev/null || true)"
  latest_analysis="$(kubectl -n "$TENANT" get analysisrun --sort-by=.metadata.creationTimestamp -o jsonpath='{.items[-1:].metadata.name}' 2>/dev/null || true)"
  analysis_phase=""

  if [[ -n "$latest_analysis" ]]; then
    analysis_phase="$(kubectl -n "$TENANT" get analysisrun "$latest_analysis" -o jsonpath='{.status.phase}' 2>/dev/null || true)"
    if [[ "$analysis_phase" == "Failed" || "$analysis_phase" == "Error" || "$analysis_phase" == "Inconclusive" ]]; then
      echo "Canary analysis failed unexpectedly: ${analysis_phase}" >&2
      exit 1
    fi
  fi

  if [[ "$phase" == "Healthy" ]]; then
    completed=true
    break
  fi

  if (( $(date +%s) - start_time > WAIT_SECONDS )); then
    echo "Timed out waiting for healthy rollout after ${WAIT_SECONDS}s." >&2
    break
  fi

  sleep 5
done

wait "$loadgen_pid" >/dev/null 2>&1 || true
loadgen_pid=""

if kubectl argo rollouts version >/dev/null 2>&1; then
  kubectl argo rollouts get rollout "$ROLLOUT_NAME" -n "$TENANT"
else
  kubectl -n "$TENANT" get rollout "$ROLLOUT_NAME" -o wide
  kubectl -n "$TENANT" describe rollout "$ROLLOUT_NAME"
fi

kubectl -n "$TENANT" get analysisrun --sort-by=.metadata.creationTimestamp | tail -n 5 || true

if [[ "$completed" != true ]]; then
  echo "Canary success demo did not reach Healthy state." >&2
  exit 1
fi

echo "Canary success demo completed for ${TENANT} with tag ${SUCCESS_TAG}."
revert_needed=false
