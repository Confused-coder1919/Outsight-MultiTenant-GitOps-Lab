#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ -z "${KUBECONFIG:-}" && -f "${ROOT_DIR}/infra/terraform/kubeconfig.yaml" ]]; then
  export KUBECONFIG="${ROOT_DIR}/infra/terraform/kubeconfig.yaml"
fi

DURATION_SECONDS="${DURATION_SECONDS:-60}"
TENANT_SCOPE="${TENANT_SCOPE:-both}"
HEALTHY_RPS="${HEALTHY_RPS:-3}"
ERROR_TENANT="${ERROR_TENANT:-}"
ERROR_RPS="${ERROR_RPS:-1}"
ERROR_CODE="${ERROR_CODE:-500}"

usage() {
  cat <<USAGE
Usage: $0 [options]
  --duration <seconds>       Traffic duration (default: 60)
  --tenant <tenant-a|tenant-b|both>
  --healthy-rps <n>          Healthy requests per second per tenant (default: 3)
  --error-tenant <tenant>    Send /fail traffic to this tenant
  --error-rps <n>            Error requests per second (default: 1)
  --error-code <400-599>     Status code for /fail (default: 500)
USAGE
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

for cmd in kubectl curl; do
  require_cmd "$cmd"
done

while [[ $# -gt 0 ]]; do
  case "$1" in
    --duration)
      DURATION_SECONDS="$2"
      shift 2
      ;;
    --tenant)
      TENANT_SCOPE="$2"
      shift 2
      ;;
    --healthy-rps)
      HEALTHY_RPS="$2"
      shift 2
      ;;
    --error-tenant)
      ERROR_TENANT="$2"
      shift 2
      ;;
    --error-rps)
      ERROR_RPS="$2"
      shift 2
      ;;
    --error-code)
      ERROR_CODE="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ "$TENANT_SCOPE" != "tenant-a" && "$TENANT_SCOPE" != "tenant-b" && "$TENANT_SCOPE" != "both" ]]; then
  echo "--tenant must be tenant-a, tenant-b, or both" >&2
  exit 1
fi

if ! [[ "$DURATION_SECONDS" =~ ^[0-9]+$ ]] || [[ "$DURATION_SECONDS" -le 0 ]]; then
  echo "--duration must be a positive integer" >&2
  exit 1
fi

if ! [[ "$HEALTHY_RPS" =~ ^[0-9]+$ ]] || [[ "$HEALTHY_RPS" -lt 0 ]]; then
  echo "--healthy-rps must be a non-negative integer" >&2
  exit 1
fi

if ! [[ "$ERROR_RPS" =~ ^[0-9]+$ ]] || [[ "$ERROR_RPS" -lt 0 ]]; then
  echo "--error-rps must be a non-negative integer" >&2
  exit 1
fi

if [[ -n "$ERROR_TENANT" ]] && [[ "$ERROR_TENANT" != "tenant-a" && "$ERROR_TENANT" != "tenant-b" ]]; then
  echo "--error-tenant must be tenant-a or tenant-b" >&2
  exit 1
fi

if ! [[ "$ERROR_CODE" =~ ^[0-9]+$ ]] || [[ "$ERROR_CODE" -lt 400 || "$ERROR_CODE" -gt 599 ]]; then
  echo "--error-code must be between 400 and 599" >&2
  exit 1
fi

tenants=()
if [[ "$TENANT_SCOPE" == "both" ]]; then
  tenants=(tenant-a tenant-b)
else
  tenants=("$TENANT_SCOPE")
fi

for ns in "${tenants[@]}"; do
  if ! kubectl get namespace "$ns" >/dev/null 2>&1; then
    echo "Namespace ${ns} not found." >&2
    exit 1
  fi
  if ! kubectl -n "$ns" get service demo-api >/dev/null 2>&1; then
    echo "Service demo-api not found in ${ns}." >&2
    exit 1
  fi
done

pids=()
ports=()
logs=()

cleanup() {
  for pid in "${pids[@]:-}"; do
    kill "$pid" >/dev/null 2>&1 || true
  done
}
trap cleanup EXIT

port_for_tenant() {
  case "$1" in
    tenant-a) echo 18080 ;;
    tenant-b) echo 18081 ;;
    *)
      echo "Unsupported tenant: $1" >&2
      exit 1
      ;;
  esac
}

echo "Starting port-forwards for traffic generation..."
for tenant in "${tenants[@]}"; do
  local_port="$(port_for_tenant "$tenant")"
  log_file="/tmp/loadgen-port-forward-${tenant}.log"
  kubectl -n "$tenant" port-forward svc/demo-api "${local_port}:8000" >"$log_file" 2>&1 &
  pids+=("$!")
  ports+=("$local_port")
  logs+=("$log_file")
done

for idx in "${!tenants[@]}"; do
  tenant="${tenants[$idx]}"
  local_port="${ports[$idx]}"
  ok=0
  for _ in {1..20}; do
    if curl -fsS "http://127.0.0.1:${local_port}/health" >/dev/null 2>&1; then
      ok=1
      break
    fi
    sleep 1
  done
  if [[ "$ok" -ne 1 ]]; then
    echo "Failed to connect to ${tenant}. See ${logs[$idx]}" >&2
    exit 1
  fi
done

healthy_sent=0
healthy_failed=0
error_sent=0

end_time=$(( $(date +%s) + DURATION_SECONDS ))

echo "Generating traffic for ${DURATION_SECONDS}s (healthy_rps=${HEALTHY_RPS}, error_tenant=${ERROR_TENANT:-none}, error_rps=${ERROR_RPS})..."
while [[ $(date +%s) -lt $end_time ]]; do
  for idx in "${!tenants[@]}"; do
    tenant="${tenants[$idx]}"
    local_port="${ports[$idx]}"

    for ((i = 0; i < HEALTHY_RPS; i++)); do
      if curl -fsS "http://127.0.0.1:${local_port}/" >/dev/null 2>&1; then
        healthy_sent=$((healthy_sent + 1))
      else
        healthy_failed=$((healthy_failed + 1))
      fi
    done

    if [[ -n "$ERROR_TENANT" && "$tenant" == "$ERROR_TENANT" ]]; then
      for ((i = 0; i < ERROR_RPS; i++)); do
        curl -s "http://127.0.0.1:${local_port}/fail?code=${ERROR_CODE}" >/dev/null || true
        error_sent=$((error_sent + 1))
      done
    fi
  done
  sleep 1
done

echo "Traffic complete. healthy_sent=${healthy_sent} healthy_failed=${healthy_failed} error_sent=${error_sent}"
