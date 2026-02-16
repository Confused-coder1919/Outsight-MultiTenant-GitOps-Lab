#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROLLOUT_NAME="${ROLLOUT_NAME:-demo-api}"

if [[ -z "${KUBECONFIG:-}" && -f "${ROOT_DIR}/infra/terraform/kubeconfig.yaml" ]]; then
  export KUBECONFIG="${ROOT_DIR}/infra/terraform/kubeconfig.yaml"
fi

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

get_rollout_yaml() {
  local namespace="$1"
  local output=""

  if output="$(kubectl -n "$namespace" get rollout "$ROLLOUT_NAME" -o yaml 2>/dev/null)"; then
    printf '%s\n' "$output"
    return 0
  fi

  if output="$(kubectl -n "$namespace" get rollouts.argoproj.io "$ROLLOUT_NAME" -o yaml 2>/dev/null)"; then
    printf '%s\n' "$output"
    return 0
  fi

  return 1
}

print_rollout_steps() {
  local namespace="$1"
  local rollout_yaml=""
  local steps=""

  if ! rollout_yaml="$(get_rollout_yaml "$namespace")"; then
    echo "Rollout ${ROLLOUT_NAME} not found."
    return 0
  fi

  steps="$(printf '%s\n' "$rollout_yaml" | grep -E 'setWeight:' || true)"
  if [[ -z "$steps" ]]; then
    echo "No canary setWeight steps found."
    return 0
  fi

  printf '%s\n' "$steps"
}

print_analysis_thresholds() {
  local namespace="$1"
  local rollout_yaml=""
  local thresholds=""

  if ! rollout_yaml="$(get_rollout_yaml "$namespace")"; then
    echo "Rollout ${ROLLOUT_NAME} not found."
    return 0
  fi

  thresholds="$(printf '%s\n' "$rollout_yaml" | awk '
    /name:[[:space:]]*maxErrorRate/ { key = "maxErrorRate"; next }
    /name:[[:space:]]*maxP95LatencyMs/ { key = "maxP95LatencyMs"; next }
    key != "" && /value:[[:space:]]*/ {
      value = $2
      gsub(/"/, "", value)
      if (!(key in seen)) {
        print key ": " value
        seen[key] = 1
      }
      key = ""
    }
  ')"

  if [[ -z "$thresholds" ]]; then
    echo "No maxErrorRate/maxP95LatencyMs args found."
    return 0
  fi

  printf '%s\n' "$thresholds"
}

print_network_policy_status() {
  local namespace="$1"

  if kubectl -n "$namespace" get networkpolicy "$ROLLOUT_NAME" >/dev/null 2>&1; then
    echo "present"
    return 0
  fi

  if kubectl -n "$namespace" get networkpolicy --no-headers >/dev/null 2>&1; then
    local count
    count="$(kubectl -n "$namespace" get networkpolicy --no-headers 2>/dev/null | wc -l | tr -d ' ')"
    if [[ "$count" -gt 0 ]]; then
      echo "present (different name)"
    else
      echo "absent"
    fi
    return 0
  fi

  echo "unknown (namespace or cluster unreachable)"
}

print_tenant_block() {
  local title="$1"
  local namespace="$2"

  echo "=== ${title} ==="
  echo "Rollout Steps:"
  print_rollout_steps "$namespace"
  echo
  echo "Analysis Thresholds:"
  print_analysis_thresholds "$namespace"
  echo
  echo "NetworkPolicy:"
  print_network_policy_status "$namespace"
  echo
}

require_cmd kubectl

echo "=============================================="
echo " PREMIUM VS STANDARD TENANT COMPARISON (DEMO) "
echo "=============================================="
echo

print_tenant_block "PREMIUM TENANT (tenant-a)" "tenant-a"
print_tenant_block "STANDARD TENANT (tenant-b)" "tenant-b"

echo "=== SUMMARY ==="
echo "tenant-a (Premium): stricter canary gates, stricter analysis thresholds, tighter network controls."
echo "tenant-b (Standard): simpler canary path, looser thresholds, reduced policy overhead."
