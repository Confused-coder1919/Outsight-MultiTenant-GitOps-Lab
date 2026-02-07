# Demo Script: CI -> GHCR -> GitOps -> Argo CD -> Rollouts -> Observability

## 2-minute pitch

1. Open a PR and show GitHub Actions running lint + tests only.
2. Merge to `main`; CI builds and pushes a multi-arch image (`linux/amd64,linux/arm64`) to GHCR.
3. CI opens a GitOps PR that bumps tenant image tags to immutable `sha-<shortsha>`.
4. Merge that GitOps PR; Argo CD syncs tenant apps and Argo Rollouts performs canary progression.
5. Show tenant-aware metrics/logs in Grafana and Loki, then run canary success/failure demos.

## CI and promotion flow (talk track)

1. Create a small PR and point out PR-only checks (fast lint/test).
2. Merge to `main` and open Actions logs for buildx multi-arch push.
3. Show generated GitOps PR: `chore(gitops): bump demo-api to sha-<shortsha>`.
4. Merge GitOps PR and verify Argo apps are `Synced` and `Healthy`.

## Baseline verification commands

```bash
kubectl -n argocd get applications -o wide
kubectl -n tenant-a get pods
kubectl -n tenant-b get pods
kubectl get rollout -A
```

```bash
kubectl -n tenant-a port-forward svc/demo-api 18080:8000
curl http://127.0.0.1:18080/health
curl http://127.0.0.1:18080/metrics | head
```

## Progressive Delivery Demo

Install CLI plugin once (optional):

```bash
brew install argoproj/tap/kubectl-argo-rollouts
```

### Happy path canary

Use a known-good tag that differs from current tenant value:

```bash
SUCCESS_TAG=main make canary-success
```

While it runs:

```bash
kubectl -n tenant-a get rollout demo-api -w
kubectl -n tenant-a get analysisrun -w
```

Expected:

- Rollout steps progress: `10% -> pause -> 50% -> pause -> 100%`.
- Latest `AnalysisRun` ends `Successful`.
- Rollout `phase` returns to `Healthy`.

### Failure path canary (auto-abort)

```bash
make canary-demo
```

What this does:

- Temporarily enables `/fail` endpoint only for tenant-a.
- Generates error traffic during analysis windows.
- Waits for degraded/failed analysis signal.
- Reverts tenant-a back to chart values at script exit.

Inspect after/while running:

```bash
kubectl -n tenant-a get rollout demo-api -o wide
kubectl -n tenant-a get analysisrun --sort-by=.metadata.creationTimestamp
kubectl -n tenant-a describe rollout demo-api
```

## What to show in Argo CD UI

- `demo-api-tenant-a` app sync status and health.
- Resource tree with `Rollout` instead of `Deployment`.
- Events around pause, analysis, and abort (for failure demo).

## What to show in Grafana

1. Tenant dashboard request-rate panels (`tenant-a` vs `tenant-b`).
2. Error-rate changes during failure demo window.
3. Loki Explore query filtered by tenant:

```logql
{tenant="tenant-a"}
```

```logql
{tenant="tenant-b"}
```

## URLs and credential commands from Terraform outputs

```bash
cd infra/terraform
terraform output -raw argocd_url
terraform output -raw grafana_url
terraform output -raw argocd_initial_admin_password_command
terraform output -raw grafana_admin_password_command
```

Run the returned password commands only when needed.

## Failure modes and quick diagnosis

### ImagePullBackOff

Causes: tag not found, private GHCR package, wrong architecture.

```bash
kubectl -n tenant-a describe pod <pod-name>
```

Checks:

- image tag exists in GHCR (`sha-<shortsha>` from merged GitOps PR)
- image manifest includes `amd64` and `arm64`
- package visibility/auth is correct

### Readiness probe failing

```bash
kubectl -n tenant-a describe pod <pod-name>
kubectl -n tenant-a logs <pod-name>
```

Checks:

- app listens on port `8000`
- `/health` returns 200

### Argo app degraded

```bash
kubectl -n argocd describe application demo-api-tenant-a
kubectl -n tenant-a describe rollout demo-api
```

Common reasons:

- invalid Helm values
- failed canary analysis
- image pull/probe failures
