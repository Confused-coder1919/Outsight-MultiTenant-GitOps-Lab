# Runbook

Operational guide to run the project end-to-end in both VPS and local modes.

## 1) Prerequisites

- Docker (daemon running)
- kubectl
- helm
- terraform (for VPS mode)
- python3 + pip
- Optional but recommended: `kubectl-argo-rollouts`, `argocd`

Quick check:

```bash
make help
```

## 2) Select Cluster Context

For VPS mode:

```bash
cd /Users/syedtashfin/Documents/GitHub/outsight-platform-devops-demo
export KUBECONFIG=$(pwd)/infra/terraform/kubeconfig.yaml
kubectl get nodes
```

For local k3d mode, use `make local-up` and `make local-verify`.

## 3) Bring Platform To Ready State

```bash
make rollouts-up
make gitops
make demo-compare
make open-ports
```

What this guarantees:

- Argo Rollouts CRD/controller present
- Argo CD Applications applied
- Premium vs Standard tenant comparison printed
- external NodePorts exposed for demo UIs

## 4) Verify Baseline Health

```bash
./scripts/verify.sh
./scripts/vps_status.sh
```

Expected:

- both Argo apps: `Synced / Healthy`
- both tenant rollouts: `Healthy`
- both tenant pods: running

## 5) Access UIs

- Argo CD: `https://<vps-ip>:30443`
- Grafana: `http://<vps-ip>:30000`
- Prometheus: `http://<vps-ip>:30090`
- Loki readiness: `http://<vps-ip>:31000/ready`

If needed, print current URLs again:

```bash
./scripts/vps_status.sh
```

## 6) Credentials

### Argo CD

- Username: `admin`
- Password retrieval:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo
```

If login is invalid, initial secret may be stale. Reset and sync both secrets:

```bash
NEW_PASS='<new-strong-password>'
HASH=$(argocd account bcrypt --password "$NEW_PASS")
kubectl -n argocd patch secret argocd-secret --type merge -p "{\"stringData\":{\"admin.password\":\"$HASH\",\"admin.passwordMtime\":\"$(date -u +%FT%TZ)\"}}"
kubectl -n argocd patch secret argocd-initial-admin-secret --type merge -p "{\"stringData\":{\"password\":\"$NEW_PASS\"}}"
kubectl -n argocd rollout restart deployment argocd-server
```

### Grafana

```bash
kubectl -n observability get secret kube-prometheus-stack-grafana -o jsonpath='{.data.admin-user}' | base64 -d; echo
kubectl -n observability get secret kube-prometheus-stack-grafana -o jsonpath='{.data.admin-password}' | base64 -d; echo
```

## 7) Tenant API/metrics access

Tenant services are ClusterIP. Use port-forward:

```bash
kubectl -n tenant-a port-forward svc/demo-api 18080:8000
kubectl -n tenant-b port-forward svc/demo-api 28080:8000
```

Validate:

```bash
curl http://127.0.0.1:18080/health
curl http://127.0.0.1:18080/metrics | head
curl http://127.0.0.1:28080/health
curl http://127.0.0.1:28080/metrics | head
```

## 8) Progressive Delivery Operations

### Success path

```bash
WAIT_SECONDS=300 TRAFFIC_SECONDS=60 make canary-success
```

### Failure path (auto rollback demonstration)

```bash
WAIT_SECONDS=300 TRAFFIC_SECONDS=60 make canary-demo
```

Inspect rollout/analysis:

```bash
kubectl -n tenant-a get rollouts.argoproj.io
kubectl -n tenant-a get analysisruns.argoproj.io --sort-by=.metadata.creationTimestamp
kubectl argo rollouts get rollout demo-api -n tenant-a
```

## 9) Known Ops Pitfalls

### Rollout restart appears stuck

Symptom: rollout shows `Progressing` with `rollout is restarting` for too long.

Recovery:

```bash
kubectl -n tenant-a delete pod -l app.kubernetes.io/instance=demo-api-tenant-a
kubectl -n tenant-b delete pod -l app.kubernetes.io/instance=demo-api-tenant-b
```

### CI build succeeds but no promotion PR

Check repo setting:

- GitHub Actions must be allowed to create/approve pull requests.

Fallback commands are printed in CI logs.

### Image pull failures

Check GHCR visibility and tag existence:

```bash
kubectl -n tenant-a describe pod <pod>
```

## 10) Local Mode (k3d)

```bash
make local-up
make local-verify
```

For local-only app sanity:

```bash
make docker-build TAG=dev
make docker-run TAG=dev
curl http://127.0.0.1:8000/health
```
