# Demo Script: CI -> GHCR -> GitOps -> Argo CD -> Observability

## 2-minute talk track

1. Open a PR and show GitHub Actions running lint + tests only.
2. Merge to `main`; CI builds a multi-arch image (`linux/amd64,linux/arm64`) and pushes to GHCR.
3. The same workflow opens a GitOps PR that bumps tenant image tags to `sha-<shortsha>`.
4. Merge the GitOps PR; Argo CD syncs tenant apps and rolls out new pods in `tenant-a` and `tenant-b`.
5. Validate app health and show observability in Grafana + Loki filtered by tenant labels.

## Pre-demo setup

- Repo has Argo Applications in `gitops/argocd/`.
- Tenant Helm values are in `charts/demo-api/tenants/`.
- CI workflow uses:
  - immutable tag `sha-<shortsha>`
  - moving tags `main` and `dev`
  - GHCR repo `ghcr.io/confused-coder1919/outsight-platform-devops-demo/demo-api`

## CI and GitOps promotion flow

1. Create any small app/doc change PR.
2. Show CI checks: lint + tests only on `pull_request`.
3. Merge to `main`.
4. Open Actions run and confirm:
   - multi-arch image push completed
   - GitOps PR `chore(gitops): bump demo-api to sha-<shortsha>` created
5. Merge the GitOps PR.

## VPS verification commands

```bash
kubectl -n argocd get applications -o wide
kubectl -n tenant-a get pods
kubectl -n tenant-b get pods
```

```bash
kubectl -n tenant-a port-forward svc/demo-api 18080:8000
curl http://127.0.0.1:18080/health
curl http://127.0.0.1:18080/metrics | head
```

Optional tenant-b app check:

```bash
kubectl -n tenant-b port-forward svc/demo-api 18081:8000
curl http://127.0.0.1:18081/health
curl http://127.0.0.1:18081/metrics | head
```

## Argo CD / Grafana URLs and credentials via Terraform outputs

```bash
cd infra/terraform
terraform output -raw argocd_url
terraform output -raw grafana_url
terraform output -raw argocd_initial_admin_password_command
terraform output -raw grafana_admin_password_command
```

Run returned password commands only when needed.

## Observability demo (Grafana + Loki)

1. Open Grafana from `terraform output -raw grafana_url`.
2. Open tenant dashboard (`observability/grafana/dashboards/tenant-overview.json`) and show request activity by tenant.
3. In Grafana Explore with Loki datasource, run:

```logql
{tenant="tenant-a"}
```

```logql
{tenant="tenant-b"}
```

## Failure modes and quick diagnosis

### 1) ImagePullBackOff (tag missing / arch mismatch / auth)

- Check pod events:
  `kubectl -n tenant-a describe pod <pod-name>`
- Confirm tag exists in GHCR and is multi-arch:
  image should be `sha-<shortsha>` from merged GitOps PR.
- If registry is private, verify pull auth policy/secret.

### 2) Readiness probe failing

- Check pod logs and probe status:
  - `kubectl -n tenant-a logs <pod-name>`
  - `kubectl -n tenant-a describe pod <pod-name>`
- Confirm app listens on `8000` and `/health` returns 200.

### 3) Argo Degraded reasons

- Inspect Argo app details:
  `kubectl -n argocd describe application demo-api-tenant-a`
- Common causes:
  - invalid Helm values
  - image not pullable
  - failed rollout due to probes/resources

## Local fallback (no GHCR auth required)

For local-only runs, keep using current local workflow:

```bash
make local-up
make local-verify
```

This path does not require GitHub secrets locally.

## Progressive Delivery Demo

### What to show

1. Deployment object is now `Rollout` with canary steps `10% -> pause 30s -> 50% -> pause 60s -> 100%`.
2. Prometheus-driven `AnalysisTemplate` runs during canary and auto-aborts on bad metrics.
3. Failed canary rolls back automatically to stable ReplicaSet.

### Commands

Install the CLI plugin (one-time, optional but recommended):

```bash
brew install argoproj/tap/kubectl-argo-rollouts
```

Check rollout and analysis resources:

```bash
kubectl -n tenant-a get rollout demo-api
kubectl -n tenant-a get analysistemplate demo-api-analysis
kubectl -n tenant-a get rollout demo-api -o yaml | rg "setWeight|pause|analysis"
```

Watch rollout progress:

```bash
kubectl argo rollouts get rollout demo-api -n tenant-a --watch
kubectl argo rollouts get rollout demo-api -n tenant-b --watch
```

Run the scripted failure-and-revert demo:

```bash
make canary-demo
```

Manual inspect during demo:

```bash
kubectl -n tenant-a get rollout demo-api -o wide
kubectl -n tenant-a get analysisrun
kubectl -n tenant-b get analysisrun
kubectl -n tenant-a describe rollout demo-api
kubectl -n tenant-a describe analysisrun $(kubectl -n tenant-a get analysisrun -o name | tail -n1)
```

Prometheus verification queries used by analysis:

```promql
(
  sum(rate(http_requests_total{tenant="tenant-a",namespace="tenant-a",status=~"5.."}[2m]))
  /
  clamp_min(sum(rate(http_requests_total{tenant="tenant-a",namespace="tenant-a"}[2m])), 1)
)
```

```promql
histogram_quantile(0.95, sum(rate(http_request_duration_seconds_bucket{tenant="tenant-a",namespace="tenant-a"}[2m])) by (le))
```
