terraform {
  required_version = ">= 1.5.0"
  required_providers {
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }
}

provider "null" {}

locals {
  kubeconfig_path = "${path.module}/kubeconfig.yaml"
}

resource "null_resource" "bootstrap" {
  triggers = {
    vps_ip      = var.VPS_IP
    vps_user    = var.VPS_USER
    ssh_key_sha = filesha256(var.SSH_KEY_PATH)
  }

  connection {
    type  = "ssh"
    host  = var.VPS_IP
    user  = var.VPS_USER
    agent = true
  }

  provisioner "remote-exec" {
    inline = [
      "set -e",
      "if ! command -v k3s >/dev/null 2>&1; then curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC='--disable traefik' sh -; fi",
      "sudo systemctl enable --now k3s",
      "export KUBECONFIG=/etc/rancher/k3s/k3s.yaml",
      "if ! command -v helm >/dev/null 2>&1; then curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash; fi",
      "helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx || true",
      "helm repo add argo https://argoproj.github.io/argo-helm || true",
      "helm repo add prometheus-community https://prometheus-community.github.io/helm-charts || true",
      "helm repo add grafana https://grafana.github.io/helm-charts || true",
      "helm repo update",
      "helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx --namespace ingress-nginx --create-namespace --wait --timeout 10m",
      "helm upgrade --install argocd argo/argo-cd --namespace argocd --create-namespace --set server.service.type=NodePort --set server.service.nodePortHttp=30080 --set server.service.nodePortHttps=30443 --wait --timeout 10m",
      "helm upgrade --install argo-rollouts argo/argo-rollouts --namespace argo-rollouts --create-namespace --wait --timeout 10m",
      "kubectl -n argo-rollouts rollout status deploy/argo-rollouts --timeout=180s",
      "kubectl get crd rollouts.argoproj.io >/dev/null",
      "helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack --namespace observability --create-namespace --set grafana.service.type=NodePort --set grafana.service.nodePort=30000 --set prometheus.service.type=NodePort --set prometheus.service.nodePort=30090 --wait --timeout 10m",
      "helm upgrade --install loki grafana/loki-stack --namespace observability --create-namespace --set grafana.enabled=false --set loki.isDefault=false --set loki.service.type=NodePort --set loki.service.nodePort=31000 --set promtail.enabled=true --wait --timeout 10m"
    ]
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -e
      TMP_KCFG="${path.module}/k3s.yaml"
      FINAL_KCFG="${path.module}/kubeconfig.yaml"
      scp -o StrictHostKeyChecking=no -i "${var.SSH_KEY_PATH}" "${var.VPS_USER}@${var.VPS_IP}:/etc/rancher/k3s/k3s.yaml" "$TMP_KCFG"
      sed "s/127.0.0.1/${var.VPS_IP}/" "$TMP_KCFG" > "$FINAL_KCFG"
      rm -f "$TMP_KCFG"
      echo "Wrote kubeconfig to $FINAL_KCFG"
      export KUBECONFIG="$FINAL_KCFG"

      ARGO_DIR="${path.module}/../../gitops/argocd"
      if [ -d "$ARGO_DIR" ] && ls "$ARGO_DIR"/*.yaml >/dev/null 2>&1; then
        echo "Applying Argo CD Applications from $ARGO_DIR (as-is)"
        kubectl apply -f "$ARGO_DIR"
      else
        TMP_DIR="$(mktemp -d)"
        echo "No Argo CD manifests found under $ARGO_DIR. Creating minimal Applications."
        cat <<EOF > "$TMP_DIR/tenant-a-app.yaml"
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: demo-api-tenant-a
  namespace: argocd
spec:
  project: default
  source:
    repoURL: ${var.GITOPS_REPO}
    targetRevision: ${var.GITOPS_REVISION}
    path: charts/demo-api
    helm:
      valueFiles:
        - tenants/tenant-a-values.yaml
  destination:
    server: https://kubernetes.default.svc
    namespace: tenant-a
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
EOF
        cat <<EOF > "$TMP_DIR/tenant-b-app.yaml"
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: demo-api-tenant-b
  namespace: argocd
spec:
  project: default
  source:
    repoURL: ${var.GITOPS_REPO}
    targetRevision: ${var.GITOPS_REVISION}
    path: charts/demo-api
    helm:
      valueFiles:
        - tenants/tenant-b-values.yaml
  destination:
    server: https://kubernetes.default.svc
    namespace: tenant-b
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
EOF
        kubectl apply -f "$TMP_DIR/tenant-a-app.yaml"
        kubectl apply -f "$TMP_DIR/tenant-b-app.yaml"
        rm -rf "$TMP_DIR"
      fi
    EOT
  }
}
