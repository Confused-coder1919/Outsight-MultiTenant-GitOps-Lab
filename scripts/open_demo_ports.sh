#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="${ROOT_DIR}/infra/terraform"

if [[ -z "${KUBECONFIG:-}" && -f "${TF_DIR}/kubeconfig.yaml" ]]; then
  export KUBECONFIG="${TF_DIR}/kubeconfig.yaml"
fi

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

require_cmd kubectl

echo "Using kubeconfig: ${KUBECONFIG:-<current-context>}"
kubectl get nodes >/dev/null

SERVER_URL="$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}' 2>/dev/null || true)"
HOST_IP="$(printf '%s' "$SERVER_URL" | sed -E 's#https?://([^:/]+).*#\1#')"
if [[ -z "$HOST_IP" || "$HOST_IP" == "$SERVER_URL" ]]; then
  HOST_IP="<node-ip>"
fi

echo "Ensuring NodePort services for demo UIs..."

kubectl -n argocd patch svc argocd-server --type merge -p '{
  "spec": {
    "type": "NodePort",
    "ports": [
      {"name":"http","port":80,"protocol":"TCP","targetPort":8080,"nodePort":30080},
      {"name":"https","port":443,"protocol":"TCP","targetPort":8080,"nodePort":30443}
    ]
  }
}' >/dev/null

kubectl -n observability patch svc kube-prometheus-stack-grafana --type merge -p '{
  "spec": {
    "type": "NodePort",
    "ports": [
      {"name":"http-web","port":80,"protocol":"TCP","targetPort":"grafana","nodePort":30000}
    ]
  }
}' >/dev/null

kubectl -n observability patch svc kube-prometheus-stack-prometheus --type merge -p '{
  "spec": {
    "type": "NodePort",
    "ports": [
      {"name":"http-web","port":9090,"protocol":"TCP","targetPort":9090,"nodePort":30090},
      {"name":"reloader-web","port":8080,"protocol":"TCP","targetPort":"reloader-web","nodePort":30091}
    ]
  }
}' >/dev/null

kubectl -n observability patch svc loki --type merge -p '{
  "spec": {
    "type": "NodePort",
    "ports": [
      {"name":"http-metrics","port":3100,"protocol":"TCP","targetPort":"http-metrics","nodePort":31000}
    ]
  }
}' >/dev/null

echo "NodePort exposure complete."
echo
echo "Accessible URLs:"
echo "  Argo CD      : https://${HOST_IP}:30443"
echo "  Grafana      : http://${HOST_IP}:30000"
echo "  Prometheus   : http://${HOST_IP}:30090"
echo "  Loki API     : http://${HOST_IP}:31000/ready"
echo
echo "Credential commands:"
echo "  Argo CD admin password:"
echo "    kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo"
echo "  Grafana admin password:"
echo "    kubectl -n observability get secret kube-prometheus-stack-grafana -o jsonpath='{.data.admin-password}' | base64 -d; echo"
echo
echo "Tenant app/metrics (port-forward, because app services remain ClusterIP):"
echo "  kubectl -n tenant-a port-forward svc/demo-api 18080:8000"
echo "  kubectl -n tenant-b port-forward svc/demo-api 28080:8000"
echo "  curl http://127.0.0.1:18080/health"
echo "  curl http://127.0.0.1:18080/metrics | head"
