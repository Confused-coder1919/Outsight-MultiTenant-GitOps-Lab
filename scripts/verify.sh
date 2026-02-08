#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -z "${KUBECONFIG:-}" && -f "${ROOT_DIR}/infra/terraform/kubeconfig.yaml" ]]; then
  export KUBECONFIG="${ROOT_DIR}/infra/terraform/kubeconfig.yaml"
fi

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "FAIL: missing required command '$1'" >&2
    exit 1
  fi
}

pass() {
  echo "PASS: $1"
}

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

for cmd in kubectl curl; do
  require_cmd "$cmd"
done

echo "Cluster overview:"
kubectl get nodes
kubectl get ns
kubectl -n argocd get applications.argoproj.io -o wide

api_resources="$(kubectl api-resources 2>/dev/null || true)"
if printf '%s\n' "$api_resources" | grep -iE 'rollout|rollouts\.argoproj\.io' >/dev/null; then
  pass "rollout API is listed in api-resources"
else
  fail "rollout API not found in api-resources. Run 'make rollouts-up'."
fi

if kubectl get crd rollouts.argoproj.io >/dev/null 2>&1; then
  pass "rollouts.argoproj.io CRD exists"
else
  fail "rollouts.argoproj.io CRD missing. Run 'make rollouts-up'."
fi

kubectl get rollouts.argoproj.io -A
kubectl -n tenant-a get pods,svc
kubectl -n tenant-b get pods,svc

assert_namespace_healthy() {
  local ns="$1"
  local not_running

  not_running="$(kubectl -n "$ns" get pods --no-headers 2>/dev/null | awk '$3 != "Running" && $3 != "Completed" {print $1 ":" $3}')"
  if [[ -n "$not_running" ]]; then
    fail "non-running pods in ${ns}: ${not_running}"
  fi

  if kubectl -n "$ns" get rollouts.argoproj.io demo-api >/dev/null 2>&1; then
    pass "rollout demo-api exists in ${ns}"
  else
    fail "rollout demo-api missing in ${ns}"
  fi

  pass "all pods healthy in ${ns}"
}

assert_namespace_healthy tenant-a
assert_namespace_healthy tenant-b

port_forward_and_check() {
  local ns="$1"
  local local_port="$2"
  local pf_pid
  local log_file="/tmp/port-forward-${ns}.log"

  kubectl -n "$ns" port-forward svc/demo-api "${local_port}:8000" >"$log_file" 2>&1 &
  pf_pid="$!"

  cleanup_pf() {
    kill "$pf_pid" >/dev/null 2>&1 || true
    wait "$pf_pid" >/dev/null 2>&1 || true
  }
  trap cleanup_pf RETURN

  local ready=false
  for _ in {1..20}; do
    if curl -fsS "http://127.0.0.1:${local_port}/health" >/dev/null 2>&1; then
      ready=true
      break
    fi
    sleep 1
  done

  if [[ "$ready" != true ]]; then
    fail "port-forward readiness failed for ${ns}. See ${log_file}"
  fi

  if curl -fsS "http://127.0.0.1:${local_port}/health" >/dev/null; then
    pass "${ns} /health check"
  else
    fail "${ns} /health check failed"
  fi

  if curl -fsS "http://127.0.0.1:${local_port}/metrics" | grep -q "http_requests_total"; then
    pass "${ns} /metrics check"
  else
    fail "${ns} /metrics missing http_requests_total"
  fi
}

port_forward_and_check tenant-a 18080
port_forward_and_check tenant-b 18081

echo "Verification complete."
