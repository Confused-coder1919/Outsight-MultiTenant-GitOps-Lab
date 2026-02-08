# Runbook

This runbook provisions a local k3d cluster, installs Argo CD and observability,
and deploys both tenants via GitOps.

## Prerequisites

- Docker
- kubectl
- helm
- k3d
- Optional: `kubectl-argo-rollouts` plugin for richer canary inspection

## Clone and enter repo

```bash
git clone https://github.com/confused-coder1919/outsight-platform-devops-demo.git
cd outsight-platform-devops-demo
```

## Create local cluster

```bash
make k3d
```

## Install observability

```bash
make observability
```

## Install Argo CD

```bash
make argocd
```

## Ensure Argo Rollouts CRDs/controller (idempotent)

```bash
make argo-rollouts
kubectl get crd rollouts.argoproj.io
```

## Deploy GitOps applications

```bash
make gitops
```

If you are not pulling from GHCR, build the local image first (see "Local image" below).

## Verify workloads

```bash
kubectl get ns
kubectl get pods -n tenant-a
kubectl get pods -n tenant-b
```

## Access the app

```bash
kubectl -n tenant-a port-forward svc/demo-api 8081:8000
curl http://localhost:8081/

kubectl -n tenant-b port-forward svc/demo-api 8082:8000
curl http://localhost:8082/
```

## Access Argo CD UI

```bash
kubectl -n argocd port-forward svc/argocd-server 8083:443
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

Open https://localhost:8083 and login as `admin` with the decoded password.

## Open all VPS demo ports (Argo + Grafana + Prometheus + Loki)

```bash
make open-ports
```

Expected direct URLs:

- `https://<vps-ip>:30443` (Argo CD)
- `http://<vps-ip>:30000` (Grafana)
- `http://<vps-ip>:30090` (Prometheus)
- `http://<vps-ip>:31000/ready` (Loki readiness/API)

## Access Grafana

```bash
kubectl -n observability port-forward svc/kube-prometheus-stack-grafana 3000:80
```

Open http://localhost:3000 and login with `admin` / `admin`.
Import the dashboard from `observability/grafana/dashboards/tenant-overview.json`.

## View logs in Loki

In Grafana Explore, select the Loki datasource and try the queries in:
`observability/LOKI_QUERIES.md`.

## Optional: local image build

```bash
make docker-build TAG=dev
```

## Optional: local container run

```bash
make docker-run TAG=dev
curl http://127.0.0.1:8000/health
curl http://127.0.0.1:8000/metrics | head -n 5
```

## Local image (no GHCR)

Build the image with the same GHCR name used by the chart so k3d can find it locally
when `imagePullPolicy: IfNotPresent` is set.

```bash
docker build -t ghcr.io/confused-coder1919/outsight-platform-devops-demo/demo-api:dev .
```

## Progressive delivery checks

Successful canary:

```bash
SUCCESS_TAG=main TRAFFIC_SECONDS=120 WAIT_SECONDS=420 make canary-success
```

Failure and rollback demo:

```bash
TRAFFIC_SECONDS=120 WAIT_SECONDS=420 make canary-demo
```

Inspect rollout and analysis runs:

```bash
kubectl -n tenant-a get rollout demo-api -o wide
kubectl -n tenant-a get analysisrun --sort-by=.metadata.creationTimestamp
```

## Notes

- Update the Git repository URL in `gitops/argocd/tenant-a-app.yaml` and
  `gitops/argocd/tenant-b-app.yaml` to point at your fork.
- Update `image.repository` in `charts/demo-api/tenants/*.yaml` to match your GHCR path.
- For CI/GitOps PRs, keep `gitops/tenants/*.yaml` aligned with the same image repo.
- Keep `.github/workflows/ci.yml` `IMAGE_REPO` aligned with the same GHCR path.
- For local Argo CD, tenant values live in `charts/demo-api/tenants/`. If you change
  `gitops/tenants/`, copy those updates into the chart tenant files.
