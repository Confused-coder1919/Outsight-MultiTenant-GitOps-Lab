# Terraform VPS Bootstrap (k3s + platform addons)

This folder bootstraps a single VPS into a minimal k3s-based platform and installs
common platform addons. It is intentionally small and idempotent for demo purposes.

## What it installs

- k3s (single-node control plane)
- Helm
- ingress-nginx
- Argo CD (NodePort)
- kube-prometheus-stack (Grafana via NodePort)
- loki-stack (Loki + Promtail)

## Requirements

- Terraform >= 1.5
- SSH access to the VPS
- A user with `sudo` privileges
- Open firewall ports (for NodePorts below)

## Variables

- `VPS_IP` — public IP address of the VPS
- `VPS_USER` — SSH user with sudo privileges
- `SSH_KEY_PATH` — path to the private SSH key

You can set them via env vars:

```bash
export TF_VAR_VPS_IP="203.0.113.10"
export TF_VAR_VPS_USER="ubuntu"
export TF_VAR_SSH_KEY_PATH="$HOME/.ssh/id_rsa"
```

Or create a `terraform.tfvars`:

```hcl
VPS_IP       = "203.0.113.10"
VPS_USER     = "ubuntu"
SSH_KEY_PATH = "/home/me/.ssh/id_rsa"
```

## Run

```bash
terraform init
terraform plan
terraform apply
```

Terraform will also pull the kubeconfig to:

```
infra/terraform/kubeconfig.yaml
```

Use it with:

```bash
export KUBECONFIG="$(pwd)/infra/terraform/kubeconfig.yaml"
```

## Access URLs

Outputs:
- `argocd_url` -> https://<VPS_IP>:30443
- `grafana_url` -> http://<VPS_IP>:30000

> Note: These are NodePorts for simplicity. In production you would normally expose
> services behind an Ingress and TLS.

## Notes

- This bootstrap only sets up the platform layer. It does not deploy the demo app or
  GitOps apps yet.
- If your VPS already has k3s, the install step is skipped.
