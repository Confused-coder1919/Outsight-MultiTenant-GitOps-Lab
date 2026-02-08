# Outsight Platform DevOps Demo

## What this project is (full context in one place)

This repo is an interview-ready, multi-tenant SaaS-style Kubernetes platform demo. It is
intentionally small, but it models the real workflows a DevOps/Platform engineer would
own: CI/CD builds and publishes container images, GitOps promotes tenant changes via PR,
Argo CD reconciles the cluster, and Prometheus/Grafana/Loki provide tenant-aware
observability. The goal is to show how I think about reliability, isolation, and
operational clarity in a multi-tenant environment, not to build a large product.

## Why it was built (thought process)

- Show end-to-end delivery, not just a single tool: lint/tests, image build, GitOps PR,
  Argo CD sync, and observability are all connected.
- Demonstrate multi-tenant basics with clean, explainable primitives: namespaces,
  labels, NetworkPolicy, minimal RBAC, and per-tenant Helm values.
- Keep it runnable locally (k3d or Docker Desktop) so an interviewer can verify it
  quickly without any cloud accounts or secrets.
- Provide clear operational docs (runbook + demo scripts) while keeping this README
  sufficient on its own for a recruiter to understand the scope and intent.

## High-level flow (CI → image → GitOps → deploy)

1) Developer pushes code.
2) CI runs lint + tests.
3) On `main`, CI builds a Docker image and pushes to GHCR.
4) CI opens a PR that updates tenant image tags in `gitops/tenants/*.yaml`.
5) Argo CD watches the repo and syncs the Helm chart with tenant-specific values into
   `tenant-a` and `tenant-b` namespaces.
6) Prometheus scrapes metrics per tenant; Grafana dashboards visualize them; Loki/Promtail
   provide tenant-labeled logs.

## Architecture summary

```
+--------------------+        +---------------------------+
|  GitHub Actions    |  PR    |   GitOps (this repo)      |
|  lint/test/build   +------->|  gitops/tenants/*.yaml     |
|  push image to GHCR|        |  charts/demo-api           |
+---------+----------+        +-------------+-------------+
          |                                   |
          |                                   v
          |                          +-------------------+
          |                          |   Argo CD          |
          |                          |   syncs Helm       |
          |                          +----------+--------+
          |                                     |
          v                                     v
+-------------------+                 +-------------------+
| GHCR image        |                 |  tenant-a ns      |
| demo-api:<tag>    |                 |  tenant-b ns      |
+-------------------+                 +---------+---------+
                                                |
                                                v
                                        +-----------------+
                                        | Observability   |
                                        | Prom/Grafana/Loki|
                                        +-----------------+
```

## Repository layout (what to look at)

- App (FastAPI): `app/main.py`
  - Endpoints: `/`, `/health`, `/metrics`
  - Uses `TENANT_NAME` env var to differentiate tenant responses and metric labels.
- Tests: `tests/test_main.py`
- Container: `Dockerfile` (port 8000)

- Helm chart: `charts/demo-api/`
  - Deploys the app with probes, resource limits, PDB, and NetworkPolicy.
  - Values support per-tenant overrides (`tenantName`, `image.repository`, `image.tag`).
  - In-chart tenant values used by Argo CD: `charts/demo-api/tenants/*.yaml`.

- GitOps (Argo CD): `gitops/argocd/`
  - Two Application manifests for tenant-a and tenant-b.

- CI/CD:
  - GitHub Actions: `.github/workflows/ci.yml`
    - PRs: lint + tests only.
    - `main` pushes: build/push image to GHCR, update tenant values, open a PR.
  - GitLab CI: `.gitlab-ci.yml` (parity example).

- Observability:
  - `observability/helm-values/` for kube-prometheus-stack + loki-stack
  - Grafana dashboard: `observability/grafana/dashboards/tenant-overview.json`
  - Loki queries: `observability/LOKI_QUERIES.md`

- Docs:
  - `docs/RUNBOOK.md`: full end-to-end commands
  - `docs/ARCHITECTURE.md`: deeper design + tradeoffs
  - `docs/REPORT.md`: internship mapping and results
  - `docs/INTERVIEW_TALK_TRACK.md`, `docs/DEMO_SCRIPT.md`

## Multi-tenant model (simple but realistic)

- Each tenant runs in its own namespace: `tenant-a`, `tenant-b`.
- Namespace isolation + consistent labels: `tenant`, `app`, `environment`.
- Minimal NetworkPolicy to limit ingress/egress per tenant.
- Read-only Role + RoleBinding per tenant for safe access.
- Same app image, different values (`TENANT_NAME`, image tag).

## Observability model

- Centralized Prometheus/Grafana/Loki in `observability` namespace.
- ServiceMonitor per tenant so metrics are scraped consistently.
- Grafana dashboard compares tenant-a vs tenant-b traffic.
- Loki/Promtail adds tenant labels to logs for filtering.

Tradeoff: centralized observability is simpler to run and demo, but in production you
might split per-tenant to reduce blast radius or meet compliance requirements.

## Production-like hardening (minimal, explainable)

- Probes: liveness/readiness use `/health`.
- Resource requests/limits for predictable scheduling.
- PodDisruptionBudget for safe maintenance.
- NetworkPolicy to reduce east-west exposure.
- Minimal RBAC for tenant viewer access.

## Local quickstart (k3d)

```bash
make k3d
make observability
make argocd
make gitops
```

Quick checks:
```bash
kubectl get pods -n tenant-a
kubectl get pods -n tenant-b
```

## VPS demo URLs (open everything needed for UI/metrics)

```bash
make open-ports
```

This ensures NodePorts are exposed for demo access and prints links:

- Argo CD: `https://<vps-ip>:30443`
- Grafana: `http://<vps-ip>:30000`
- Prometheus: `http://<vps-ip>:30090`
- Loki readiness/API: `http://<vps-ip>:31000/ready`

Credentials:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo
kubectl -n observability get secret kube-prometheus-stack-grafana -o jsonpath='{.data.admin-password}' | base64 -d; echo
```

Tenant app endpoints remain internal by design (ClusterIP). Use port-forward:

```bash
kubectl -n tenant-a port-forward svc/demo-api 18080:8000
kubectl -n tenant-b port-forward svc/demo-api 28080:8000
curl http://127.0.0.1:18080/health
curl http://127.0.0.1:18080/metrics | head
```

## Local Docker (sanity check)

```bash
make docker-build TAG=dev
make docker-run TAG=dev
```

```bash
curl http://127.0.0.1:8000/health
curl http://127.0.0.1:8000/metrics | head -n 5
```

## Local image (no GHCR)

Build the image with the same GHCR name used by the chart so k3d can find it locally
when `imagePullPolicy: IfNotPresent` is set.

```bash
docker build -t ghcr.io/confused-coder1919/outsight-platform-devops-demo/demo-api:dev .
```

## CI/CD + GitOps behavior (short)

- PRs: lint + tests only (fast feedback).
- `main` pushes: build/push image to GHCR, update tenant image tags, open GitOps PR.
- Argo CD syncs the merged values into tenant namespaces.

Note: Argo CD uses in-chart tenant values (`charts/demo-api/tenants/`). CI updates
`gitops/tenants/` for the GitOps PR flow, so keep them in sync when demoing locally.

## How this maps to the internship responsibilities

- CI/CD: automated lint/tests, image build/push, GitOps PR for promotion.
- Kubernetes + Helm + Argo CD: multi-tenant namespaces and per-tenant Helm values.
- Observability: Prometheus/Grafana/Loki with tenant labels and dashboards.
- Cloud-native monitoring integration: simulated with documented patterns (no cloud
  account required).
- Documentation: architecture, runbook, report, demo scripts.

## Next places to look (if you want more depth)

- `docs/ARCHITECTURE.md`
- `docs/RUNBOOK.md`
- `docs/REPORT.md`
- `docs/INTERVIEW_TALK_TRACK.md`
- `docs/DEMO_SCRIPT.md`
