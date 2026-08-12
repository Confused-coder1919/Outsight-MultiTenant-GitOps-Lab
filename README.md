# Multi-Tenant GitOps Platform Lab

A production-style platform engineering lab for a multi-tenant SaaS-style workload on Kubernetes.

> **Scope:** this is a lab, not a live enterprise platform. It demonstrates a reproducible delivery and operations model without claiming production traffic, uptime, MTTR, or hard tenant isolation.

**Flagship case study:** [architecture, design decisions, rollback behavior, and verification evidence](https://syedtashfin.com/case-studies/cicd-gitops-multitenant-kubernetes-saas)

This repository demonstrates the full operating loop:

- CI (lint/test/build, multi-arch image publish)
- GitOps promotion (automated image bump PRs)
- Argo CD reconciliation into tenant namespaces
- Argo Rollouts progressive delivery with Prometheus analysis
- Observability with Prometheus, Grafana, Loki, and Promtail

It is intentionally compact, but operationally realistic.

## What This Project Demonstrates

- Multi-tenant Kubernetes delivery using namespace isolation (`tenant-a`, `tenant-b`)
- Helm chart reuse with per-tenant values
- Tenant personas with differentiated rollout gates and runtime guardrails
- GitHub Actions CI/CD with GHCR publishing (`linux/amd64`, `linux/arm64`)
- GitOps promotion flow via PR to tenant image tags
- Progressive delivery (canary + analysis + rollback)
- Centralized observability with tenant-level filtering

## Architecture At A Glance

```text
Developer Push
   |
   v
GitHub Actions (PR: lint/test, main: build+push+promote)
   |
   v
GHCR image tags (sha-<shortsha>, main, dev)
   |
   v
GitOps PR updates charts/demo-api/tenants/*.yaml
   |
   v
Argo CD syncs chart into tenant-a / tenant-b
   |
   v
Argo Rollouts canary + AnalysisTemplate (Prometheus)
   |
   v
Prometheus/Grafana/Loki observe metrics + logs per tenant
```

## Repo Structure

- App: `app/main.py`
- Tests: `tests/test_main.py`
- Container: `Dockerfile`
- Chart: `charts/demo-api`
  - Shared baseline: `charts/demo-api/values-common.yaml`
  - Tenant overlays: `charts/demo-api/tenants/tenant-a-values.yaml`, `charts/demo-api/tenants/tenant-b-values.yaml`
- Argo CD apps: `gitops/argocd`
- Observability values: `observability/helm-values`
- Automation scripts: `scripts/`
- Infra bootstrap: `infra/terraform/`
- Docs: `docs/`

## Tenant Personas

Both tenants run the same app image but use different policy profiles.

- Premium (`tenant-a`):
  - canary: `10% -> pause 30s -> analysis -> 50% -> pause 60s -> analysis -> 100%`
  - stricter analysis thresholds (`maxErrorRate=0.005`, `maxP95LatencyMs=500`)
  - stronger runtime controls (replicas/resources/network policy/alerts)
- Standard (`tenant-b`):
  - canary: `20% -> pause 15s -> analysis -> 100%`
  - looser thresholds (`maxErrorRate=0.02`, `maxP95LatencyMs=1200`)
  - lower-cost runtime profile

## CI/CD Behavior

Workflow file: `.github/workflows/ci.yml`

- `pull_request`: lint + tests only
- `push` to `main`:
  - build and push multi-arch image to GHCR
  - tags: `sha-<shortsha>`, `main`, `dev`
  - update `charts/demo-api/tenants/tenant-a-values.yaml` and `tenant-b-values.yaml`
  - open GitOps PR using `peter-evans/create-pull-request`

Important repository setting for GitOps PR automation:

- GitHub repo settings must allow Actions to create PRs
- If disabled, workflow now prints explicit manual fallback commands

## Quick Start (VPS)

```bash
git clone https://github.com/SyedTashfin/Outsight-MultiTenant-GitOps-Lab.git
cd Outsight-MultiTenant-GitOps-Lab
export KUBECONFIG=$(pwd)/infra/terraform/kubeconfig.yaml

make rollouts-up
make gitops
make demo-compare
make open-ports
./scripts/verify.sh
```

`make demo-compare` prints a deterministic tenant comparison:
- rollout `setWeight` steps
- analysis args (`maxErrorRate`, `maxP95LatencyMs`)
- NetworkPolicy presence for each tenant

## Demo URLs

After `make open-ports`:

- Argo CD: `https://<vps-ip>:30443`
- Grafana: `http://<vps-ip>:30000`
- Prometheus: `http://<vps-ip>:30090`
- Loki readiness/API: `http://<vps-ip>:31000/ready`

## Credentials

### Argo CD

- Username: `admin`
- Password source:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo
```

If login fails, the initial secret may be stale. Reset safely:

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

## Tenant App Checks

Tenant app services are intentionally `ClusterIP`.

```bash
kubectl -n tenant-a port-forward svc/demo-api 18080:8000
kubectl -n tenant-b port-forward svc/demo-api 28080:8000

curl http://127.0.0.1:18080/health
curl http://127.0.0.1:18080/metrics | head
curl http://127.0.0.1:28080/health
curl http://127.0.0.1:28080/metrics | head
```

## Progressive Delivery Demo

Success path:

```bash
WAIT_SECONDS=300 TRAFFIC_SECONDS=60 make canary-success
```

Failure path (with auto-revert):

```bash
WAIT_SECONDS=300 TRAFFIC_SECONDS=60 make canary-demo
```

## Local Development (k3d)

```bash
make local-up
make local-verify
```

## Documentation Index

- `docs/CONTEXT.md` - full project context from zero
- `docs/ARCHITECTURE.md` - component-level design and tradeoffs
- `docs/RUNBOOK.md` - operational run procedures
- `docs/QUICKSTART.md` - concise command paths
- `docs/DEMO_SCRIPT.md` - interview demo script
- `docs/INTERVIEW_TALK_TRACK.md` - pitch + likely Q&A
- `docs/REPORT.md` - implementation summary and internship mapping
