# Repository Context

## Purpose

This repo is an interview-ready, multi-tenant Kubernetes demo that shows a full DevOps loop:
CI/CD builds and publishes a container, GitOps updates tenant values, Argo CD syncs the
cluster, and Prometheus/Grafana/Loki provide observability. It is intentionally small but
realistic and runnable locally on k3d or Docker Desktop.

## High-level flow

1) Developer pushes code.
2) CI runs lint/tests; on `main` it builds the image, pushes to GHCR (lowercased repo),
   and opens a PR updating tenant image tags in `gitops/tenants/*-values.yaml`.
3) Argo CD watches the repo and syncs the Helm chart with tenant values from
   `charts/demo-api/tenants/` (local-safe path).
4) Prometheus scrapes each tenant via ServiceMonitor; Grafana dashboards visualize metrics;
   Loki/Promtail provide tenant-labeled logs.

## Key components

- App (FastAPI): `app/main.py`
  - Endpoints: `/`, `/health`, `/metrics`.
  - Uses `TENANT_NAME` env var for tenant-specific output and metric labels.
- Tests: `tests/test_main.py`
- Container: `Dockerfile` (listens on port 8000)

## Kubernetes + Helm

- Helm chart: `charts/demo-api`
  - Templates: Deployment, Service, ServiceMonitor, PrometheusRule, NetworkPolicy, RBAC,
    PodDisruptionBudget.
  - Values: `tenantName`, `image.repository`, `image.tag`, labels, resources, probes.
- Tenants (Argo local):
  - `charts/demo-api/tenants/tenant-a-values.yaml`
  - `charts/demo-api/tenants/tenant-b-values.yaml`
- Tenants (GitOps PRs):
  - `gitops/tenants/tenant-a-values.yaml`
  - `gitops/tenants/tenant-b-values.yaml`
  - Keep these in sync when demoing locally.

## GitOps (Argo CD)

- Applications:
  - `gitops/argocd/tenant-a-app.yaml`
  - `gitops/argocd/tenant-b-app.yaml`
- Each points to `charts/demo-api` and uses tenant values under `charts/demo-api/tenants/`.
- Uses `CreateNamespace=true` to auto-create `tenant-a` and `tenant-b` namespaces.

## CI/CD

- GitHub Actions: `.github/workflows/ci.yml`
  - PRs: lint + tests only.
  - Push to `main`: build/push image to GHCR, update tenant image tag values,
    open a PR for GitOps changes.
  - Image repo is computed in lowercase and used consistently for build/push/values.
- GitLab CI: `.gitlab-ci.yml`
  - Mirrors lint/test/build/push stages for parity.

## Observability

- Helm values:
  - `observability/helm-values/kube-prometheus-stack-values.yaml`
  - `observability/helm-values/loki-stack-values.yaml`
- Grafana dashboard JSON:
  - `observability/grafana/dashboards/tenant-overview.json`
- Loki queries:
  - `observability/LOKI_QUERIES.md`
- Loki datasource provisioning fix:
  - Loki is not default (Prometheus remains default).
  - Loki image pinned to `2.9.4` to satisfy Grafana health check.

## Scripts (idempotent)

- `scripts/bootstrap_k3d.sh`: create local k3d cluster.
- `scripts/install_argocd.sh`: install Argo CD.
- `scripts/install_observability.sh`: install Prometheus/Grafana/Loki.
- `scripts/deploy_gitops.sh`: apply Argo CD Applications.
- `scripts/bootstrap_vps.sh`: Terraform-based VPS bootstrap + health checks.
- `scripts/run_local_k3d.sh`: end-to-end local demo runner.
- `scripts/verify.sh`: cluster and app verification (port-forward checks).

## Infra bootstrap (Terraform)

- `infra/terraform/` bootstraps a single VPS into k3s and installs ingress-nginx,
  Argo CD, kube-prometheus-stack, and loki-stack.
- Terraform also bootstraps Argo CD GitOps by applying the tenant Applications from
  `gitops/argocd/` as-is (or generating minimal ones if missing) using the provided
  `GITOPS_REPO` and `GITOPS_REVISION`.
- Security hardening: kubeconfig is copied to the SSH user's home with `600` perms
  (no world-readable `/etc/rancher/k3s/k3s.yaml`).
- k3s installs with Traefik disabled (`--disable traefik`) since ingress-nginx is used.

## Docs

- `docs/ARCHITECTURE.md`: architecture, flow, and tradeoffs.
- `docs/RUNBOOK.md`: exact commands to run locally.
- `docs/REPORT.md`: internship-aligned report.
- `docs/INTERVIEW_TALK_TRACK.md`: pitch and Q&A.
- `docs/DEMO_SCRIPT.md`: live demo steps and troubleshooting.
- `docs/QUICKSTART.md`: reproducible VPS + local workflows.

## Placeholders to update

- GHCR repo path (if you fork):
  - `charts/demo-api/tenants/tenant-a-values.yaml`
  - `charts/demo-api/tenants/tenant-b-values.yaml`
  - `gitops/tenants/tenant-a-values.yaml`
  - `gitops/tenants/tenant-b-values.yaml`
  - `.github/workflows/ci.yml` `IMAGE_REPO`
- Argo CD repo URL (if you fork):
  - `gitops/argocd/tenant-a-app.yaml`
  - `gitops/argocd/tenant-b-app.yaml`

## Quick local run

```bash
make k3d
make observability
make argocd
make gitops
```

Verify:
```bash
kubectl get pods -n tenant-a
kubectl get pods -n tenant-b
```

## Expected tenant behavior

- `tenant-a` returns `{ "tenant": "tenant-a" }` at `/`.
- `tenant-b` returns `{ "tenant": "tenant-b" }` at `/`.
- `/metrics` exposes Prometheus metrics with tenant labels.

## Notes for reviewers

- Namespace isolation is the multi-tenant model for this demo.
- Centralized observability trades simplicity for shared blast radius.
- GitOps PR flow is used to keep changes auditable.
