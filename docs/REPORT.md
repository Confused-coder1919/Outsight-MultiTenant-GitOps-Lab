# Report

## Goals

- Deliver a multi-tenant SaaS-style Kubernetes demo using FastAPI.
- Showcase CI/CD (GitHub Actions + GitLab CI) with image publishing to GHCR.
- Implement GitOps deployments with Helm and Argo CD.
- Provide observability with Prometheus, Grafana, and Loki.
- Document architecture, steps, and outcomes.

## Architecture

- FastAPI service packaged as a Docker image.
- Helm chart deploys the app to namespaces `tenant-a` and `tenant-b`.
- Argo CD Applications pull Helm values per tenant from GitOps.
- Prometheus scrapes metrics via ServiceMonitor; Loki collects logs via Promtail.

## Implementation

- App exposes `/`, `/health`, `/metrics` with Prometheus counters and latency histograms.
- Helm chart supports per-tenant values and ServiceMonitor configuration.
- GitHub Actions runs lint/tests, builds the image, pushes to GHCR, and opens a PR to
  update image tags in GitOps values (`gitops/tenants/`).
- For local Argo CD, tenant values live under `charts/demo-api/tenants/`.
- GitLab CI mirrors the pipeline stages for parity and interview discussion.
- k3d scripts bootstrap a local cluster and install observability + Argo CD.
- Cloud-native integration (simulated): documentation notes how metrics/logs could be
  forwarded to CloudWatch or a managed SaaS without requiring an AWS account.

## Hardening choices

- NetworkPolicies restrict ingress to in-namespace traffic and Prometheus scraping,
  with egress limited to DNS (and optional observability endpoints).
- Read-only tenant RBAC provides a safe viewer role per namespace.
- Probes, resource requests/limits, and a PodDisruptionBudget add baseline resilience.
- Tenant/app/environment labels standardize filtering across metrics and logs.

## Why these choices matter in multi-tenant SaaS

- Basic isolation and RBAC reduce cross-tenant risk without heavy operational overhead.
- Reliability guardrails avoid one tenant impacting others during disruptions.
- Standard labels keep observability consistent as tenant count scales.

## Results

- Two isolated namespaces each run the same app with tenant-specific output.
- Metrics are available per tenant in Prometheus and Grafana.
- Logs are queryable in Loki by namespace and tenant labels.

## Progressive Delivery Evidence

- `kind: Rollout` replaces Deployment with canary steps `10 -> 50 -> 100` and pause gates.
- Automated Prometheus analysis checks both 5xx rate and p95 latency before promotion.
- No-data-safe PromQL (`or vector(0)`) avoids false crashes during low/no traffic windows.
- Demo scripts prove both outcomes:
  - `make canary-success SUCCESS_TAG=main` for successful gated rollout.
  - `make canary-demo` for forced analysis failure and automatic rollback behavior.

## Lessons Learned

- Namespace isolation is an effective baseline for SaaS multi-tenancy demos.
- GitOps keeps deployments predictable but benefits from automated PR workflows.
- Observability configuration is easiest when labels are consistent across stacks.

## Next Steps

- Extend CI to build multi-arch images and add SAST scanning.
- Add per-tenant quotas, network policy refinements, and stricter RBAC boundaries.
- Add SLOs/alerts and per-tenant dashboards.

## Mapping to Outsight Internship Responsibilities

- Enhance CI/CD pipelines: GitHub Actions + GitLab CI show lint/test/build/publish flows,
  image tagging, and GitOps PR updates.
- Manage Kubernetes deployments: Helm chart + namespaces deploy the same app to multiple
  tenants with clear configuration overrides.
- Build/configure observability: Prometheus ServiceMonitors, Grafana dashboard, and Loki
  queries provide tenant-aware metrics and logs.
- Integrate cloud-native monitoring services: CloudWatch-style integration is simulated
  via documentation that explains where exporters or log forwarding would fit.
- Document architecture and outcomes: `docs/ARCHITECTURE.md`, `docs/RUNBOOK.md`, and this
  report provide structure for design, execution, and results.
