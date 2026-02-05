#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${KUBECONFIG:-}" ]]; then
  echo "KUBECONFIG is not set. Export KUBECONFIG before running." >&2
  exit 1
fi

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

for cmd in kubectl curl; do
  require_cmd "$cmd"
done

echo "Cluster overview:"
kubectl get nodes
kubectl get ns
kubectl -n argocd get applications.argoproj.io -o wide
kubectl -n tenant-a get pods,svc
kubectl -n tenant-b get pods,svc

pids=()
cleanup() {
  for pid in "${pids[@]:-}"; do
    kill "$pid" >/dev/null 2>&1 || true
  done
}
trap cleanup EXIT

port_forward_and_check() {
  local ns="$1"
  local local_port="$2"
  local log_file
  log_file="/tmp/port-forward-${ns}.log"

  kubectl -n "$ns" port-forward svc/demo-api "${local_port}:8000" >"$log_file" 2>&1 &
  local pf_pid=$!
  pids+=("$pf_pid")

  for i in {1..10}; do
    if curl -fsS "http://127.0.0.1:${local_port}/health" >/dev/null 2>&1; then
      break
    fi
    sleep 1
  done

  if ! curl -fsS "http://127.0.0.1:${local_port}/health" >/dev/null; then
    echo "Health check failed for ${ns}. See ${log_file}" >&2
    exit 1
  fi

  if ! curl -fsS "http://127.0.0.1:${local_port}/metrics" | grep -q "http_requests_total"; then
    echo "Metrics check failed for ${ns}." >&2
    exit 1
  fi

  echo "${ns} health and metrics checks passed."
}

port_forward_and_check tenant-a 18080
port_forward_and_check tenant-b 18081

echo "Verification complete."
