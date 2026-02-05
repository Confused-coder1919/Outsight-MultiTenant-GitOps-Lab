# Quickstart

This guide provides two reproducible paths:

- **VPS (Terraform + k3s + Argo GitOps)**
- **Local (k3d)**

## VPS path (Terraform)

### Requirements

- Terraform >= 1.5
- SSH access to the VPS (user must have sudo)
- Open firewall ports:
  - `22` (SSH)
  - `30443` (Argo CD NodePort)
  - `30000` (Grafana NodePort)
  - `80/443` (optional, if you later expose Ingress)

### Required env vars

```bash
export TF_VAR_VPS_IP="203.0.113.10"
export TF_VAR_VPS_USER="ubuntu"
export TF_VAR_SSH_KEY_PATH="$HOME/.ssh/id_rsa"
export TF_VAR_GITOPS_REPO="https://github.com/you/outsight-platform-devops-demo.git"
export TF_VAR_GITOPS_REVISION="main"
```

### Run

```bash
make vps-up
make vps-verify
```

### Notes

- Argo CD and Grafana are exposed via NodePorts for simplicity.
- If NodePorts are blocked, use port-forwarding:
  - `kubectl -n argocd port-forward svc/argocd-server 8080:443`
  - `kubectl -n observability port-forward svc/kube-prometheus-stack-grafana 3000:80`

## Local path (k3d)

### Requirements

- Docker + k3d installed
- Helm + kubectl installed

### Run

```bash
make local-up
make local-verify
```

### Port-forward helpers

```bash
kubectl -n tenant-a port-forward svc/demo-api 18080:8000
kubectl -n tenant-b port-forward svc/demo-api 18081:8000
```

Then:

```bash
curl http://127.0.0.1:18080/health
curl http://127.0.0.1:18080/metrics | head -n 5
```
