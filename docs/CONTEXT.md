# Repository Context

This document is the single source of truth for what this project is, how it is wired, how it is operated, and where the tradeoffs are.

If you know nothing about this repository, start here.

## 1) Project Intent

`Outsight-MultiTenant-GitOps-Lab` is a production-style DevOps/Platform lab for a multi-tenant SaaS deployment model on Kubernetes.

It is built to show practical operational capability, not product complexity.

Core goals:

- prove CI/CD maturity (test, lint, build, publish, promote)
- prove GitOps operations (Argo CD + declarative sync)
- prove progressive delivery capability (Argo Rollouts + analysis)
- prove observability capability (Prometheus + Grafana + Loki)
- prove repeatability locally and on a VPS

## 2) What Runs In The System

### Application

- FastAPI app in `app/main.py`
- Endpoints:
  - `/`
  - `/health`
  - `/metrics` (Prometheus format)
  - `/fail?code=...` (demo-only failure injection)
- Containerized via `Dockerfile` (port `8000`)

### Tenancy Model

- Namespace-per-tenant:
  - `tenant-a`
  - `tenant-b`
- Same chart and app for both tenants
- Tenant identity comes from values/env (`TENANT_NAME`)

### Deployment Model

- Helm chart: `charts/demo-api`
- Shared baseline values: `charts/demo-api/values-common.yaml`
- Argo CD Applications:
  - `gitops/argocd/tenant-a-app.yaml`
  - `gitops/argocd/tenant-b-app.yaml`
- Argo CD sync target values used for runtime deployments:
  - `charts/demo-api/tenants/tenant-a-values.yaml`
  - `charts/demo-api/tenants/tenant-b-values.yaml`

### Progressive Delivery

- Workload type is `Rollout` (not Deployment)
- Tenant personas:
  - `tenant-a` (Premium): `10% -> pause 30s -> analysis -> 50% -> pause 60s -> analysis -> 100%`
  - `tenant-b` (Standard): `20% -> pause 15s -> analysis -> 100%`
- Analysis with Prometheus metrics via `AnalysisTemplate`
- Analysis args are tenant-specific:
  - Premium: `maxErrorRate=0.005`, `maxP95LatencyMs=500`
  - Standard: `maxErrorRate=0.02`, `maxP95LatencyMs=1200`
- Abort/rollback on failed analysis

### Observability

- Namespace: `observability`
- Stack:
  - kube-prometheus-stack (Prometheus + Grafana)
  - Loki + Promtail
- Tenant-aware signals:
  - metrics via ServiceMonitor labels
  - logs via promtail relabeling (`tenant`, `app`, `environment`)

## 3) CI/CD + GitOps Flow

Workflow file: `.github/workflows/ci.yml`

### PR flow

- Run lint and tests only
- No image push
- No promotion PR

### Main branch flow

- Build and push multi-arch image to GHCR (`amd64`, `arm64`)
- Image tags:
  - immutable: `sha-<shortsha>`
  - moving: `main`, `dev`
- Update tenant values in:
  - `charts/demo-api/tenants/tenant-a-values.yaml`
  - `charts/demo-api/tenants/tenant-b-values.yaml`
- Open GitOps PR using `peter-evans/create-pull-request`

### CI resilience behavior

If action-based PR creation is blocked by repo settings, workflow logs a clear warning with manual fallback commands instead of failing the whole pipeline after successful build/push.

## 4) Infrastructure Bootstrap Modes

### A) Local mode (k3d)

- `make local-up`
- `make local-verify`

### B) VPS mode (Terraform + k3s)

Terraform in `infra/terraform/` installs:

- k3s (traefik disabled)
- ingress-nginx
- Argo CD
- Argo Rollouts
- kube-prometheus-stack
- loki-stack

Then it applies GitOps app manifests from `gitops/argocd/`.

## 5) Runtime Access Model

### Public demo endpoints (NodePort)

After `make open-ports`:

- Argo CD: `https://<vps-ip>:30443`
- Grafana: `http://<vps-ip>:30000`
- Prometheus: `http://<vps-ip>:30090`
- Loki readiness: `http://<vps-ip>:31000/ready`

### Internal app endpoints (ClusterIP)

Tenant app services remain internal by design. Use port-forward:

- `kubectl -n tenant-a port-forward svc/demo-api 18080:8000`
- `kubectl -n tenant-b port-forward svc/demo-api 28080:8000`

## 6) Credentials Reality (Important)

### Argo CD

- Username is `admin`
- Password is expected from `argocd-initial-admin-secret`
- But that initial secret can become stale after password changes

Canonical retrieval command:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo
```

If invalid, reset password by patching `argocd-secret` and restarting `argocd-server`.

### Grafana

Credentials come from secret `kube-prometheus-stack-grafana` in `observability` namespace.

## 7) Hardening Implemented

- liveness/readiness probes
- requests/limits
- PodDisruptionBudget
- tenant labels on workloads/services/metrics/logs
- tenant-level RBAC viewer role
- NetworkPolicy baseline
- Argo sync safety for CRDs (`SkipDryRunOnMissingResource=true`)

## 8) Scripts You Should Know

- `scripts/install_argo_rollouts.sh` - ensures rollouts CRD/controller exists
- `scripts/open_demo_ports.sh` - exposes/prints all NodePort UI links
- `scripts/verify.sh` - end-to-end cluster + app verification
- `scripts/vps_status.sh` - concise status + URLs + credential commands
- `scripts/demo_premium_vs_standard.sh` - deterministic premium vs standard comparison output
- `scripts/canary-success.sh` - deterministic healthy canary demo
- `scripts/canary_demo.sh` - deterministic failing canary demo with cleanup

## 9) Known Tradeoffs and Limitations

- Namespace-per-tenant is practical but not hard multi-tenant isolation
- Centralized observability is simpler but has shared blast radius
- App services are ClusterIP; explicit port-forward is needed for direct app UI checks
- GitOps promotion depends on GitHub repo settings allowing action-created PRs
- Argo CD initial admin secret can diverge from active password after resets

## 10) “Demo Ready” Checklist

Run in order:

```bash
export KUBECONFIG=$(pwd)/infra/terraform/kubeconfig.yaml
make rollouts-up
make gitops
make demo-compare
make open-ports
./scripts/verify.sh
./scripts/vps_status.sh
WAIT_SECONDS=180 TRAFFIC_SECONDS=30 make canary-success
```

Pass criteria:

- Argo apps `Synced/Healthy`
- rollouts present in tenant namespaces
- all endpoint URLs reachable
- `/health` and `/metrics` checks pass for both tenants

## 11) If Something Breaks

### Argo login fails with "invalid"

- initial admin secret may be stale
- reset admin password in `argocd-secret` and restart `argocd-server`

### Rollout command hangs on restart

- rollout can stay in `Progressing` with `rollout is restarting` if pods did not rotate
- delete tenant pods once to force re-creation and state convergence

### CI build succeeds but promotion PR missing

- enable GitHub Actions PR creation permission in repo settings
- use fallback commands emitted by CI workflow logs

## 12) File Map For Reviewers

- Platform entry: `README.md`
- Ops context: `docs/CONTEXT.md`
- Design/tradeoffs: `docs/ARCHITECTURE.md`
- Operational commands: `docs/RUNBOOK.md`
- Quick start path: `docs/QUICKSTART.md`
- Live interview script: `docs/DEMO_SCRIPT.md`
- Interview narrative: `docs/INTERVIEW_TALK_TRACK.md`
- Outcome summary: `docs/REPORT.md`
