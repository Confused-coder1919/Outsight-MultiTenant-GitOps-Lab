# Terraform VPS Bootstrap (k3s + platform addons)

This folder bootstraps a single VPS into a minimal k3s-based platform and installs
common platform addons. It is intentionally small and idempotent for demo purposes.

## What it installs

- k3s (single-node control plane)
- Helm
- ingress-nginx
- Argo CD (NodePort)
- Argo Rollouts controller/CRDs
- kube-prometheus-stack (Grafana via NodePort)
- loki-stack (Loki + Promtail)

## Requirements

- Terraform >= 1.5
- SSH access to the VPS
- A user with `sudo` privileges
- Open firewall ports:
  - `22` (SSH)
  - `30443` (Argo CD NodePort)
  - `30000` (Grafana NodePort)
  - `80/443` (optional, if you later expose Ingress)

If your SSH key is passphrase-protected, ensure `ssh-agent` is running:

```bash
eval "$(ssh-agent -s)" && ssh-add ~/.ssh/hostinger_ed25519
```

## Variables

- `VPS_IP` — public IP address of the VPS
- `VPS_USER` — SSH user with sudo privileges
- `SSH_KEY_PATH` — path to the private SSH key
- `GITOPS_REPO` — public Git repo URL for Argo CD (this repo or your fork)
- `GITOPS_REVISION` — Git revision to track (default: `main`)

You can set them via env vars:

```bash
export TF_VAR_VPS_IP="203.0.113.10"
export TF_VAR_VPS_USER="ubuntu"
export TF_VAR_SSH_KEY_PATH="$HOME/.ssh/id_rsa"
export TF_VAR_GITOPS_REPO="https://github.com/you/outsight-platform-devops-demo.git"
export TF_VAR_GITOPS_REVISION="main"
```

Or create a `terraform.tfvars`:

```hcl
VPS_IP       = "203.0.113.10"
VPS_USER     = "ubuntu"
SSH_KEY_PATH = "/home/me/.ssh/id_rsa"
GITOPS_REPO  = "https://github.com/you/outsight-platform-devops-demo.git"
GITOPS_REVISION = "main"
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

> Note: These are NodePorts for simplicity. In production, prefer Ingress + TLS.

## Admin password commands

Terraform outputs command strings for initial admin credentials:

- `argocd_initial_admin_password_command`
- `grafana_admin_password_command`

Run them after `terraform apply` to print the passwords.

## GitOps bootstrap

After `terraform apply`, Argo CD will be bootstrapped with tenant Applications using the
repo you provided via `GITOPS_REPO`:

- If `gitops/argocd/*.yaml` exists, those manifests are applied as-is. Ensure the repo URL
  and revision are correct in those files.
- If they don't exist, minimal tenant-a/tenant-b Applications are generated using
  `GITOPS_REPO` and `GITOPS_REVISION`.

## Notes

- This bootstrap only sets up the platform layer. It does not deploy the demo app or
  GitOps apps yet.
- If your VPS already has k3s, the install step is skipped.
