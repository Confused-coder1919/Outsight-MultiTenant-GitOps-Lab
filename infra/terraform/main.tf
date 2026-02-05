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
    type        = "ssh"
    host        = var.VPS_IP
    user        = var.VPS_USER
    private_key = file(var.SSH_KEY_PATH)
  }

  provisioner "remote-exec" {
    inline = [
      "set -e",
      "if ! command -v k3s >/dev/null 2>&1; then curl -sfL https://get.k3s.io | sh -; fi",
      "sudo systemctl enable --now k3s",
      "sudo chmod 644 /etc/rancher/k3s/k3s.yaml",
      "export KUBECONFIG=/etc/rancher/k3s/k3s.yaml",
      "if ! command -v helm >/dev/null 2>&1; then curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash; fi",
      "helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx || true",
      "helm repo add argo https://argoproj.github.io/argo-helm || true",
      "helm repo add prometheus-community https://prometheus-community.github.io/helm-charts || true",
      "helm repo add grafana https://grafana.github.io/helm-charts || true",
      "helm repo update",
      "helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx --namespace ingress-nginx --create-namespace",
      "helm upgrade --install argocd argo/argo-cd --namespace argocd --create-namespace --set server.service.type=NodePort --set server.service.nodePortHttp=30080 --set server.service.nodePortHttps=30443",
      "helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack --namespace observability --create-namespace --set grafana.service.type=NodePort --set grafana.service.nodePort=30000",
      "helm upgrade --install loki grafana/loki-stack --namespace observability --create-namespace --set grafana.enabled=false --set loki.isDefault=false --set promtail.enabled=true"
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
    EOT
  }
}
