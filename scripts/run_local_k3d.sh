#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

for cmd in k3d kubectl helm; do
  require_cmd "$cmd"
done

if command -v make >/dev/null 2>&1 && [[ -f "${ROOT_DIR}/Makefile" ]]; then
  if grep -q "^k3d:" "${ROOT_DIR}/Makefile"; then
    echo "Using Makefile targets to bootstrap local cluster..."
    (cd "$ROOT_DIR" && make k3d observability argocd gitops)
  else
    echo "Makefile targets missing. Falling back to scripts..."
    "$ROOT_DIR/scripts/bootstrap_k3d.sh"
    "$ROOT_DIR/scripts/install_observability.sh"
    "$ROOT_DIR/scripts/install_argocd.sh"
    "$ROOT_DIR/scripts/deploy_gitops.sh"
  fi
else
  echo "Make not available. Falling back to scripts..."
  "$ROOT_DIR/scripts/bootstrap_k3d.sh"
  "$ROOT_DIR/scripts/install_observability.sh"
  "$ROOT_DIR/scripts/install_argocd.sh"
  "$ROOT_DIR/scripts/deploy_gitops.sh"
fi

cat <<'OUTPUT'

Local access (port-forward examples):
- Argo CD:   kubectl -n argocd port-forward svc/argocd-server 8080:443
- Grafana:   kubectl -n observability port-forward svc/kube-prometheus-stack-grafana 3000:80
- Tenant A:  kubectl -n tenant-a port-forward svc/demo-api 18080:8000
- Tenant B:  kubectl -n tenant-b port-forward svc/demo-api 18081:8000

Admin credentials:
- Argo CD:   kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d; echo
- Grafana:   kubectl -n observability get secret kube-prometheus-stack-grafana -o jsonpath="{.data.admin-password}" | base64 -d; echo
OUTPUT
