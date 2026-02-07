# Repository Context

## Purpose

This repo is an interview-ready, multi-tenant Kubernetes demo that shows a full DevOps loop:
CI/CD builds and publishes a container, GitOps updates tenant values, Argo CD syncs the
cluster, Argo Rollouts performs canary analysis, and Prometheus/Grafana/Loki provide
observability. It is intentionally small but realistic and runnable locally on k3d or on a VPS.

## High-level flow

1) Developer pushes code.
2) CI runs lint/tests; on `main` it builds a multi-arch image (`amd64` + `arm64`),
   pushes immutable and moving tags to GHCR, then opens a PR updating tenant image tags in
   `charts/demo-api/tenants/*-values.yaml`.
3) Argo CD watches the repo and syncs the Helm chart with tenant values from
   `charts/demo-api/tenants/`.
4) Argo Rollouts applies canary steps and runs Prometheus-backed AnalysisRuns.
5) Prometheus scrapes each tenant via ServiceMonitor; Grafana dashboards visualize metrics;
   Loki/Promtail provide tenant-labeled logs.

## Key components

- App (FastAPI): `app/main.py`
  - Endpoints: `/`, `/health`, `/metrics`, `/fail?code=...`.
  - `/fail` is gated by `ENABLE_DEMO_FAILURE_ENDPOINT=true` for demo-only failure injection.
  - Uses `TENANT_NAME` env var for tenant-specific output and metric labels.
- Tests: `tests/test_main.py`
- Container: `Dockerfile` (port 8000)

## Kubernetes + Helm

- Helm chart: `charts/demo-api`
  - Templates: Rollout, AnalysisTemplate, Service, ServiceMonitor, PrometheusRule,
    NetworkPolicy, RBAC, PodDisruptionBudget.
  - Values: `tenantName`, `image.repository`, `image.tag`, labels, resources, probes,
    canary analysis thresholds.
- Tenants (Argo source of truth):
  - `charts/demo-api/tenants/tenant-a-values.yaml`
  - `charts/demo-api/tenants/tenant-b-values.yaml`
- Tenants (legacy GitOps PR path retained):
  - `gitops/tenants/tenant-a-values.yaml`
  - `gitops/tenants/tenant-b-values.yaml`

## GitOps (Argo CD)

- Applications:
  - `gitops/argocd/tenant-a-app.yaml`
  - `gitops/argocd/tenant-b-app.yaml`
- Each points to `charts/demo-api` and uses in-chart tenant value files.
- Sync options include `CreateNamespace=true` and `SkipDryRunOnMissingResource=true`.

## Progressive delivery

- Workload object is `kind: Rollout` (Argo Rollouts).
- Canary steps: `10% -> pause 30s -> 50% -> pause 60s -> 100%`.
- `AnalysisTemplate` evaluates:
  - 5xx rate `< 2%`
  - p95 latency `< 500ms`
- Prometheus queries are no-data-safe (`or vector(0)`), preventing empty-result runtime issues.

## CI/CD

- GitHub Actions: `.github/workflows/ci.yml`
  - PRs: lint + tests only.
  - Push to `main`: build/push multi-arch image (`sha-<shortsha>`, `main`, `dev`) and open a GitOps PR.
  - Uses lowercase GHCR repo: `ghcr.io/confused-coder1919/outsight-platform-devops-demo/demo-api`.
- GitLab CI: `.gitlab-ci.yml` (parity reference).

## Observability

- Helm values:
  - `observability/helm-values/kube-prometheus-stack-values.yaml`
  - `observability/helm-values/loki-stack-values.yaml`
- Grafana dashboard JSON:
  - `observability/grafana/dashboards/tenant-overview.json`
- Loki queries:
  - `observability/LOKI_QUERIES.md`

## Scripts (idempotent)

- `scripts/bootstrap_k3d.sh`: create local k3d cluster.
- `scripts/install_argocd.sh`: install Argo CD and Argo Rollouts.
- `scripts/install_observability.sh`: install Prometheus/Grafana/Loki.
- `scripts/deploy_gitops.sh`: apply Argo CD Applications.
- `scripts/bootstrap_vps.sh`: Terraform-based VPS bootstrap + health checks.
- `scripts/run_local_k3d.sh`: end-to-end local demo runner.
- `scripts/verify.sh`: cluster + app verification including rollout checks.
- `scripts/loadgen.sh`: deterministic healthy/error traffic generation.
- `scripts/canary_demo.sh`: failing canary demo with auto-revert.
- `scripts/canary_success.sh`: healthy canary demo path.
- `scripts/vps_status.sh`: nodes/apps/rollouts + terraform URLs summary.

## Terraform bootstrap

- `infra/terraform/` bootstraps VPS k3s + ingress-nginx + Argo CD + Argo Rollouts + observability stack.
- Can bootstrap Argo Applications from `gitops/argocd/`.
- k3s installs with Traefik disabled (`--disable traefik`).

## Docs

- `docs/ARCHITECTURE.md`
- `docs/RUNBOOK.md`
- `docs/QUICKSTART.md`
- `docs/DEMO_SCRIPT.md`
- `docs/INTERVIEW_TALK_TRACK.md`
- `docs/REPORT.md`

## Quick commands

```bash
make local-up
make local-verify
make demo-traffic
make canary-success SUCCESS_TAG=main
make canary-demo
```

## Expected tenant behavior

- `tenant-a` returns `{ "tenant": "tenant-a" }` at `/`.
- `tenant-b` returns `{ "tenant": "tenant-b" }` at `/`.
- `/metrics` exposes tenant-labeled Prometheus metrics.

## Notes for reviewers

- Namespace isolation is the multi-tenant model for this demo.
- Canary gates are tenant-scoped and driven by Prometheus analysis.
- Centralized observability trades simplicity for shared blast radius.
- GitOps PR flow keeps changes auditable.
