#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TENANT="${TENANT:-tenant-a}"
VALUES_FILE="${ROOT_DIR}/charts/demo-api/tenants/${TENANT}-values.yaml"
ROLLOUT_NAME="${ROLLOUT_NAME:-demo-api}"
CANARY_TAG="${CANARY_TAG:-}"
FORCE_FAIL="${FORCE_FAIL:-1}"
WAIT_SECONDS="${WAIT_SECONDS:-300}"
TRAFFIC_SECONDS="${TRAFFIC_SECONDS:-90}"
HEALTHY_RPS="${HEALTHY_RPS:-3}"

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

if ! [[ "$WAIT_SECONDS" =~ ^[0-9]+$ ]] || [[ "$WAIT_SECONDS" -le 0 ]]; then
  echo "WAIT_SECONDS must be a positive integer" >&2
  exit 1
fi
if ! [[ "$TRAFFIC_SECONDS" =~ ^[0-9]+$ ]] || [[ "$TRAFFIC_SECONDS" -le 0 ]]; then
  echo "TRAFFIC_SECONDS must be a positive integer" >&2
  exit 1
fi
if (( TRAFFIC_SECONDS > WAIT_SECONDS )); then
  echo "TRAFFIC_SECONDS (${TRAFFIC_SECONDS}) cannot exceed WAIT_SECONDS (${WAIT_SECONDS})." >&2
  exit 1
fi

ensure_rollouts_available() {
  if kubectl get crd rollouts.argoproj.io >/dev/null 2>&1; then
    return 0
  fi

  if [[ -x "${ROOT_DIR}/scripts/install_argo_rollouts.sh" ]]; then
    echo "Rollouts CRD missing. Installing Argo Rollouts..."
    "${ROOT_DIR}/scripts/install_argo_rollouts.sh"
  else
    echo "Missing install script: ${ROOT_DIR}/scripts/install_argo_rollouts.sh" >&2
    return 1
  fi

  kubectl get crd rollouts.argoproj.io >/dev/null 2>&1
}

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

terminate_pid() {
  local pid="$1"
  local label="$2"
  local timeout="${3:-15}"

  if [[ -z "$pid" ]]; then
    return 0
  fi
  if ! kill -0 "$pid" >/dev/null 2>&1; then
    return 0
  fi

  kill "$pid" >/dev/null 2>&1 || true
  local start_ts
  start_ts="$(date +%s)"
  while kill -0 "$pid" >/dev/null 2>&1; do
    if (( $(date +%s) - start_ts >= timeout )); then
      echo "${label} did not stop in ${timeout}s; sending SIGKILL" >&2
      kill -9 "$pid" >/dev/null 2>&1 || true
      break
    fi
    sleep 1
  done

  wait "$pid" >/dev/null 2>&1 || true
}

wait_rollout_healthy() {
  local timeout="${1:-180}"
  local start_ts
  start_ts="$(date +%s)"

  while true; do
    local phase
    phase="$(kubectl -n "$TENANT" get rollouts.argoproj.io "$ROLLOUT_NAME" -o jsonpath='{.status.phase}' 2>/dev/null || true)"
    if [[ "$phase" == "Healthy" ]]; then
      return 0
    fi
    if (( $(date +%s) - start_ts >= timeout )); then
      return 1
    fi
    sleep 5
  done
}

ensure_rollouts_available || {
  echo "Failed to install/verify Argo Rollouts CRDs." >&2
  exit 1
}

if [[ ! -f "$VALUES_FILE" ]]; then
  echo "Values file not found: $VALUES_FILE" >&2
  exit 1
fi
if ! kubectl get namespace "$TENANT" >/dev/null 2>&1; then
  echo "Namespace ${TENANT} not found. Run make gitops first." >&2
  exit 1
fi
if ! kubectl -n "$TENANT" get rollouts.argoproj.io "$ROLLOUT_NAME" >/dev/null 2>&1; then
  echo "Rollout ${ROLLOUT_NAME} not found in ${TENANT}." >&2
  exit 1
fi

HELM_RELEASE="${HELM_RELEASE:-$(kubectl -n "$TENANT" get rollouts.argoproj.io "$ROLLOUT_NAME" -o jsonpath='{.metadata.labels.app\.kubernetes\.io/instance}' 2>/dev/null || true)}"
if [[ -z "$HELM_RELEASE" ]]; then
  HELM_RELEASE="demo-api-${TENANT}"
fi

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
loadgen_pid=""
revert_needed=true

cleanup() {
  terminate_pid "$loadgen_pid" "load generator" 20

  if [[ "$revert_needed" == true ]]; then
    echo "Reverting ${TENANT} rollout to baseline chart values..."
    helm template "$HELM_RELEASE" "${ROOT_DIR}/charts/demo-api" -n "$TENANT" -f "$VALUES_FILE" \
      | kubectl -n "$TENANT" apply -f - >/dev/null

    if ! wait_rollout_healthy 180; then
      echo "Rollout still not healthy after baseline apply; forcing rollout recreation..." >&2
      kubectl -n "$TENANT" delete rollouts.argoproj.io "$ROLLOUT_NAME" --ignore-not-found=true >/dev/null 2>&1 || true
      helm template "$HELM_RELEASE" "${ROOT_DIR}/charts/demo-api" -n "$TENANT" -f "$VALUES_FILE" \
        | kubectl -n "$TENANT" apply -f - >/dev/null
      if ! wait_rollout_healthy 180; then
        local revert_phase
        revert_phase="$(kubectl -n "$TENANT" get rollouts.argoproj.io "$ROLLOUT_NAME" -o jsonpath='{.status.phase}' 2>/dev/null || true)"
        echo "Warning: rollout did not return to Healthy within cleanup timeout (phase=${revert_phase:-unknown})." >&2
      fi
    fi
  fi

  rm -f "$OVERRIDE_FILE"
}
trap cleanup EXIT INT TERM

if [[ "$FORCE_FAIL" == "1" ]]; then
  FAIL_SUCCESS_CONDITION='result[0] < 0'
  FAIL_FAILURE_CONDITION='result[0] >= 0'
else
  FAIL_SUCCESS_CONDITION='result[0] < 0.8'
  FAIL_FAILURE_CONDITION='result[0] >= 0.8'
fi

cat >"$OVERRIDE_FILE" <<YAML
demoFailureEndpoint:
  enabled: true
image:
  tag: "$TARGET_TAG"
rollout:
  analysis:
    successCondition5xx: "$FAIL_SUCCESS_CONDITION"
    failureCondition5xx: "$FAIL_FAILURE_CONDITION"
YAML

echo "Applying canary demo override for ${TENANT} (force_fail=${FORCE_FAIL}, tag=${TARGET_TAG})..."
helm template "$HELM_RELEASE" "${ROOT_DIR}/charts/demo-api" -n "$TENANT" -f "$VALUES_FILE" -f "$OVERRIDE_FILE" \
  | kubectl -n "$TENANT" apply -f - >/dev/null

echo "Generating healthy traffic for ${TRAFFIC_SECONDS}s..."
"${ROOT_DIR}/scripts/loadgen.sh" \
  --tenant "$TENANT" \
  --duration "$TRAFFIC_SECONDS" \
  --healthy-rps "$HEALTHY_RPS" >/tmp/loadgen-${TENANT}.log 2>&1 &
loadgen_pid="$!"

start_ts="$(date +%s)"
expected_state_met=false

while true; do
  phase="$(kubectl -n "$TENANT" get rollouts.argoproj.io "$ROLLOUT_NAME" -o jsonpath='{.status.phase}' 2>/dev/null || true)"
  latest_analysis="$(kubectl -n "$TENANT" get analysisruns.argoproj.io --sort-by=.metadata.creationTimestamp -o jsonpath='{.items[-1:].metadata.name}' 2>/dev/null || true)"
  analysis_phase=""

  if [[ -n "$latest_analysis" ]]; then
    analysis_phase="$(kubectl -n "$TENANT" get analysisruns.argoproj.io "$latest_analysis" -o jsonpath='{.status.phase}' 2>/dev/null || true)"
  fi

  if [[ "$FORCE_FAIL" == "1" ]]; then
    if [[ "$phase" == "Degraded" || "$analysis_phase" == "Failed" || "$analysis_phase" == "Error" || "$analysis_phase" == "Inconclusive" ]]; then
      expected_state_met=true
      echo "Observed failing canary signal: rollout_phase=${phase:-unknown}, analysis_phase=${analysis_phase:-none}"
      break
    fi
  else
    if [[ "$phase" == "Healthy" && "$analysis_phase" != "Failed" && "$analysis_phase" != "Error" && "$analysis_phase" != "Inconclusive" ]]; then
      expected_state_met=true
      echo "Observed healthy canary signal: rollout_phase=${phase:-unknown}, analysis_phase=${analysis_phase:-none}"
      break
    fi
  fi

  if (( $(date +%s) - start_ts >= WAIT_SECONDS )); then
    echo "Timed out after ${WAIT_SECONDS}s waiting for canary state transition (phase=${phase:-unknown}, analysis=${analysis_phase:-none})." >&2
    break
  fi

  sleep 5
done

terminate_pid "$loadgen_pid" "load generator" 20
loadgen_pid=""

if kubectl argo rollouts version >/dev/null 2>&1; then
  kubectl argo rollouts get rollout "$ROLLOUT_NAME" -n "$TENANT"
else
  kubectl -n "$TENANT" get rollouts.argoproj.io "$ROLLOUT_NAME" -o wide
  kubectl -n "$TENANT" describe rollouts.argoproj.io "$ROLLOUT_NAME"
fi
kubectl -n "$TENANT" get analysisruns.argoproj.io --sort-by=.metadata.creationTimestamp | tail -n 5 || true

if [[ "$expected_state_met" != true ]]; then
  echo "Canary demo did not reach expected state." >&2
  exit 1
fi

echo "Canary demo completed. Baseline will be restored by cleanup."
