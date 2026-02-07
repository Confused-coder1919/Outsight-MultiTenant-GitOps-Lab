#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TENANT="${TENANT:-tenant-a}"
HELM_RELEASE="${HELM_RELEASE:-demo-api-${TENANT}}"
VALUES_FILE="${ROOT_DIR}/charts/demo-api/tenants/${TENANT}-values.yaml"
ROLLOUT_NAME="${ROLLOUT_NAME:-demo-api}"
CANARY_TAG="${CANARY_TAG:-}"
WAIT_SECONDS="${WAIT_SECONDS:-360}"
TRAFFIC_SECONDS="${TRAFFIC_SECONDS:-150}"
HEALTHY_RPS="${HEALTHY_RPS:-3}"
ERROR_RPS="${ERROR_RPS:-8}"
CANARY_PF_PORT="${CANARY_PF_PORT:-18082}"

if [[ -z "${KUBECONFIG:-}" && -f "${ROOT_DIR}/infra/terraform/kubeconfig.yaml" ]]; then
  export KUBECONFIG="${ROOT_DIR}/infra/terraform/kubeconfig.yaml"
fi

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

for cmd in kubectl helm awk mktemp curl; do
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

TARGET_TAG="$CURRENT_TAG"
if [[ -n "$CANARY_TAG" ]]; then
  TARGET_TAG="$CANARY_TAG"
fi

OVERRIDE_FILE="$(mktemp)"
cat >"$OVERRIDE_FILE" <<YAML
demoFailureEndpoint:
  enabled: true
image:
  tag: "$TARGET_TAG"
rollout:
  analysis:
    # Use a stricter demo threshold so short canary windows reliably fail on injected 5xx traffic.
    successCondition5xx: "result[0] < 0.001"
    failureCondition5xx: "result[0] >= 0.001"
YAML

loadgen_pid=""
error_pid=""
pf_pid=""
revert_needed=true

cleanup() {
  for pid in "$error_pid" "$loadgen_pid" "$pf_pid"; do
    if [[ -n "$pid" ]]; then
      kill "$pid" >/dev/null 2>&1 || true
      wait "$pid" >/dev/null 2>&1 || true
    fi
  done

  if [[ "$revert_needed" == true ]]; then
    echo "Reverting ${TENANT} rollout to chart values..."
    helm template "$HELM_RELEASE" "${ROOT_DIR}/charts/demo-api" -n "$TENANT" -f "$VALUES_FILE" \
      | kubectl -n "$TENANT" apply -f - >/dev/null
  fi

  rm -f "$OVERRIDE_FILE"
}
trap cleanup EXIT INT TERM

wait_for_canary_pod() {
  local start_ts
  start_ts="$(date +%s)"

  while true; do
    local current_hash stable_hash canary_pod canary_ready
    current_hash="$(kubectl -n "$TENANT" get rollout "$ROLLOUT_NAME" -o jsonpath='{.status.currentPodHash}' 2>/dev/null || true)"
    stable_hash="$(kubectl -n "$TENANT" get rollout "$ROLLOUT_NAME" -o jsonpath='{.status.stableRS}' 2>/dev/null || true)"

    if [[ -n "$current_hash" ]]; then
      canary_pod="$(kubectl -n "$TENANT" get pods -l "rollouts-pod-template-hash=${current_hash}" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
      if [[ -n "$canary_pod" ]]; then
        canary_ready="$(kubectl -n "$TENANT" get pod "$canary_pod" -o jsonpath='{.status.containerStatuses[0].ready}' 2>/dev/null || true)"
        if [[ "$canary_ready" == "true" ]]; then
          echo "$canary_pod"
          return 0
        fi
      fi
    fi

    if (( $(date +%s) - start_ts > WAIT_SECONDS )); then
      echo "Timed out waiting for a ready canary pod in ${TENANT}." >&2
      return 1
    fi

    sleep 2
  done
}

start_canary_error_traffic() {
  local canary_pod="$1"
  local pf_log="/tmp/canary-pod-forward-${TENANT}.log"

  kubectl -n "$TENANT" port-forward "pod/${canary_pod}" "${CANARY_PF_PORT}:8000" >"$pf_log" 2>&1 &
  pf_pid="$!"

  local fail_enabled=false
  for _ in {1..20}; do
    code="$(curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:${CANARY_PF_PORT}/fail?code=500" || true)"
    if [[ "$code" == "500" ]]; then
      fail_enabled=true
      break
    fi
    sleep 1
  done

  if [[ "$fail_enabled" != true ]]; then
    echo "Could not trigger /fail on canary pod ${canary_pod}." >&2
    echo "Expected HTTP 500, but endpoint is likely unavailable in image tag ${TARGET_TAG}." >&2
    echo "Build/push latest image and set tenant tag to that image before running canary-demo." >&2
    return 1
  fi

  (
    local end_time
    end_time=$(( $(date +%s) + TRAFFIC_SECONDS ))
    while [[ $(date +%s) -lt "$end_time" ]]; do
      for ((i = 0; i < ERROR_RPS; i++)); do
        curl -s "http://127.0.0.1:${CANARY_PF_PORT}/fail?code=500" >/dev/null || true
      done
      sleep 1
    done
  ) &
  error_pid="$!"
}

echo "Applying canary-failure config for ${TENANT} (tag=${TARGET_TAG}, failure endpoint enabled)..."
helm template "$HELM_RELEASE" "${ROOT_DIR}/charts/demo-api" -n "$TENANT" -f "$VALUES_FILE" -f "$OVERRIDE_FILE" \
  | kubectl -n "$TENANT" apply -f - >/dev/null

echo "Generating healthy traffic during analysis window..."
"${ROOT_DIR}/scripts/loadgen.sh" \
  --tenant "$TENANT" \
  --duration "$TRAFFIC_SECONDS" \
  --healthy-rps "$HEALTHY_RPS" &
loadgen_pid="$!"

canary_pod="$(wait_for_canary_pod)"
echo "Using canary pod ${canary_pod} for forced error traffic."
start_canary_error_traffic "$canary_pod"

start_time="$(date +%s)"
failed=false

while true; do
  phase="$(kubectl -n "$TENANT" get rollout "$ROLLOUT_NAME" -o jsonpath='{.status.phase}' 2>/dev/null || true)"
  latest_analysis="$(kubectl -n "$TENANT" get analysisrun --sort-by=.metadata.creationTimestamp -o jsonpath='{.items[-1:].metadata.name}' 2>/dev/null || true)"
  analysis_phase=""

  if [[ -n "$latest_analysis" ]]; then
    analysis_phase="$(kubectl -n "$TENANT" get analysisrun "$latest_analysis" -o jsonpath='{.status.phase}' 2>/dev/null || true)"
  fi

  if [[ "$phase" == "Degraded" || "$analysis_phase" == "Failed" || "$analysis_phase" == "Error" || "$analysis_phase" == "Inconclusive" ]]; then
    echo "Observed failing canary signal: rollout_phase=${phase:-unknown}, analysis_phase=${analysis_phase:-none}"
    failed=true
    break
  fi

  if (( $(date +%s) - start_time > WAIT_SECONDS )); then
    echo "Timed out waiting for failing canary signal after ${WAIT_SECONDS}s." >&2
    break
  fi

  sleep 5
done

if [[ -n "$pf_pid" ]]; then
  kill "$pf_pid" >/dev/null 2>&1 || true
  wait "$pf_pid" >/dev/null 2>&1 || true
fi
pf_pid=""

for pid in "$error_pid" "$loadgen_pid"; do
  if [[ -n "$pid" ]]; then
    wait "$pid" >/dev/null 2>&1 || true
  fi
done
error_pid=""
loadgen_pid=""
pf_pid=""

if kubectl argo rollouts version >/dev/null 2>&1; then
  kubectl argo rollouts get rollout "$ROLLOUT_NAME" -n "$TENANT"
else
  kubectl -n "$TENANT" get rollout "$ROLLOUT_NAME" -o wide
  kubectl -n "$TENANT" describe rollout "$ROLLOUT_NAME"
fi

kubectl -n "$TENANT" get analysisrun --sort-by=.metadata.creationTimestamp | tail -n 5 || true

if [[ "$failed" != true ]]; then
  echo "Canary did not degrade as expected." >&2
  exit 1
fi

echo "Canary failure demo completed. Cleanup will restore chart values."
