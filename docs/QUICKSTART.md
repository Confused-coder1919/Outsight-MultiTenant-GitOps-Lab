# Quickstart

Two runnable paths are supported.

## VPS Path (recommended for interview demo)

```bash
cd /path/to/Outsight-MultiTenant-GitOps-Lab
export KUBECONFIG=$(pwd)/infra/terraform/kubeconfig.yaml

make rollouts-up
make gitops
make demo-compare
make open-ports
./scripts/verify.sh
./scripts/vps_status.sh
```

`make demo-compare` prints a deterministic Premium vs Standard tenant comparison:
- rollout step weights
- analysis thresholds (`maxErrorRate`, `maxP95LatencyMs`)
- NetworkPolicy presence per tenant namespace

Use URLs printed by `./scripts/vps_status.sh`:

- Argo CD: `https://<vps-ip>:30443`
- Grafana: `http://<vps-ip>:30000`
- Prometheus: `http://<vps-ip>:30090`
- Loki: `http://<vps-ip>:31000/ready`

## Local Path (k3d)

```bash
cd /path/to/Outsight-MultiTenant-GitOps-Lab
make local-up
make local-verify
```

## Canary Demo Commands

Success path:

```bash
WAIT_SECONDS=300 TRAFFIC_SECONDS=60 make canary-success
```

Failure path:

```bash
WAIT_SECONDS=300 TRAFFIC_SECONDS=60 make canary-demo
```

## Credentials

Argo CD username is `admin`.

Password commands:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo
kubectl -n observability get secret kube-prometheus-stack-grafana -o jsonpath='{.data.admin-password}' | base64 -d; echo
```

If Argo password from initial secret is invalid, reset via `docs/RUNBOOK.md`.
