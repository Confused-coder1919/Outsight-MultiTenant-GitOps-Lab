# Architecture

## ASCII diagram

Developer
  |
  v
GitHub Actions / GitLab CI
  |        \
  |         \__ Docker image -> GHCR
  |
  v
GitOps repo (Helm values)
  |
  v
Argo CD
  |
  v
Kubernetes (k3d)
  |-- namespace: tenant-a -> demo-api
  |-- namespace: tenant-b -> demo-api
  |
  +--> Observability
       |-- Prometheus (scrapes ServiceMonitor per namespace)
       |-- Grafana (dashboards)
       +-- Loki + Promtail (logs per namespace)

## CI -> Image -> GitOps -> Deploy flow

- Developer pushes code to GitHub/GitLab.
- CI runs lint/tests, builds a container, and pushes to GHCR (image repo is lowercased for GHCR compatibility).
- On pushes to `main`, GitHub Actions opens a PR updating `gitops/tenants/*-values.yaml` with the new tag.
- Argo CD watches the repo and syncs the updated Helm values into each tenant namespace.
- Local note: Argo CD reads tenant values from `charts/demo-api/tenants/` to avoid path traversal.

## Progressive Delivery with Analysis (no mesh)

- The workload uses `kind: Rollout` (not Deployment) with canary steps:
  `10% -> pause 30s -> 50% -> pause 60s -> 100%`.
- Each canary promotion runs an `AnalysisTemplate` against Prometheus metrics:
  - 5xx rate must stay below 2%.
  - p95 latency must stay below 500ms.
- Prometheus queries use a no-data fallback (`or vector(0)`) so analysis stays deterministic when traffic is low.
- If analysis fails, Rollouts aborts promotion and keeps/reverts to stable pods.
- This gives controlled exposure with automated safety checks for each tenant namespace without service mesh complexity.

## Why GitOps

- Git is the single source of truth for tenant config and image versions.
- PRs provide an audit trail and make promotion explicit and reviewable.

## Why namespace-per-tenant

- It is the simplest isolation boundary in Kubernetes and easy to reason about.
- It maps cleanly to per-tenant quotas, RBAC, and NetworkPolicy.

## Multi-tenant model (namespace isolation)

- Each tenant gets a dedicated namespace (`tenant-a`, `tenant-b`).
- The same Helm chart is deployed twice with different `tenantName` values.
- This keeps workloads separated and provides tenant-scoped metrics/logs via namespace labels.

## Observability model

- Centralized stack in `observability` namespace (Prometheus, Grafana, Loki).
- Each tenant deploys its own ServiceMonitor so metrics are scraped per namespace.
- Promtail carries tenant/app/environment labels into logs for targeted Loki queries.
- Optional cloud-native integration: in production, the same metrics/logs could be
  forwarded to CloudWatch or a managed SaaS; here it is documented only.

## Centralized vs tenant-isolated observability

- Centralized observability is cheaper and simpler but increases shared blast radius.
- Tenant-isolated observability reduces risk but adds operational cost and complexity.

## Hardening choices

- NetworkPolicy limits ingress to in-namespace traffic plus Prometheus scraping, and
  restricts egress to DNS (and optional observability endpoints).
- Per-tenant read-only RBAC (tenant viewer) provides safe, scoped visibility.
- Probes and resource requests/limits enforce basic reliability guardrails.
- PodDisruptionBudget keeps at least one pod available during voluntary disruptions.
- Tenant/app/environment labels standardize filtering across metrics and logs.

## Why these choices matter in multi-tenant SaaS

- Isolation controls reduce noisy neighbor risk and accidental cross-tenant access.
- RBAC and labeling provide safe, predictable visibility without over-privileging.
- Reliability guardrails prevent cascading failures from impacting all tenants.

## Tradeoffs and choices

- Namespace isolation is practical for demos but not a hard security boundary.
- Centralized observability reduces ops overhead but increases shared blast radius.
- GitOps PRs provide auditability at the cost of extra CI workflow steps.

## What changes in AWS / hybrid (conceptual)

- Replace local k3d with managed Kubernetes (EKS) and use IRSA for least-privilege access.
- Push images to ECR (still lowercase naming) and mirror GitOps flow with the same PR model.
- Optionally federate metrics/logs into a managed backend while keeping tenant labels intact.
