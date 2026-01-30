# Interview Talk Track

## 30-second intro

I built a multi-tenant Kubernetes demo that mirrors a SaaS platform: a tiny FastAPI app deployed to two tenant namespaces via Helm and Argo CD, with GitHub Actions and GitLab CI pipelines, plus Prometheus, Grafana, and Loki for observability. It is intentionally small but realistic, showing CI/CD, GitOps, and tenant-aware monitoring end to end.

## 2-minute pitch 

This repo is a compact, interview-ready platform demo that maps directly to your internship scope. It packages a FastAPI service with `/`, `/health`, and `/metrics`, then deploys it twice into `tenant-a` and `tenant-b` namespaces using a Helm chart and Argo CD. The same image runs for both tenants, but the Helm values inject a tenant name so the API responses and metrics are tenant-labeled.

On the CI/CD side, GitHub Actions runs lint and tests, builds a container, pushes it to GHCR, and opens a PR that updates the image tag in the GitOps values. That PR is the audit trail, and Argo CD reconciles the cluster to it. A parallel GitLab CI pipeline shows how I would port the same stages to another system.

For observability, kube-prometheus-stack scrapes each tenant via ServiceMonitor, Grafana visualizes request rate, latency, and namespace resource usage, and Loki provides per-tenant log queries. The result is a small but complete system that demonstrates CI/CD, Kubernetes deployment management, GitOps flows, and monitoring tradeoffs in a way that is easy to run locally.

## Walkthrough (step-by-step narrative)

1) Start at the app: `app/main.py` is a tiny FastAPI service with `/`, `/health`, and `/metrics`. It adds Prometheus counters and latency histograms and logs each request with the tenant name.
2) Containerize: `Dockerfile` builds a minimal image. This mirrors how the CI system will publish artifacts.
3) Helm chart: `charts/demo-api` templates Deployment, Service, and ServiceMonitor. The chart is parameterized by `tenantName`, `image.repository`, and `image.tag`.
4) Multi-tenant config: Argo CD reads tenant values from `charts/demo-api/tenants/` for local
   compatibility, while `gitops/tenants/` is the GitOps layer updated by CI. Both set the
   tenant name and image tag.
5) GitOps: `gitops/argocd/*-app.yaml` defines two Argo CD Applications, each pointing at the same chart but with different values and namespaces. Argo CD creates the namespaces and keeps them reconciled.
6) CI/CD: `.github/workflows/ci.yml` runs lint/tests, builds and pushes to GHCR, then opens a PR updating the GitOps values. That PR is what drives the deployment change, which is a common production pattern. `.gitlab-ci.yml` mirrors the same logic for parity.
7) Observability: `observability/helm-values/*` installs kube-prometheus-stack and Loki. The chart’s ServiceMonitor uses a release label that matches the Prometheus selector so each tenant is scraped. Grafana uses a tenant dashboard from `observability/grafana/dashboards/tenant-overview.json`.
8) Run locally: `scripts/` provide idempotent setup for k3d, Argo CD, observability, and GitOps deployment. The `docs/RUNBOOK.md` gives exact commands.

## Insights 

### CI/CD
- Why a PR step? It creates an audit trail and aligns with GitOps, so the cluster changes are always visible and reviewable.
- Why GHCR? It is a standard registry for GitHub-native workflows and easy to configure with repository-level permissions.

### GitOps
- Argo CD Applications point to the chart plus tenant values. This keeps the chart reusable and tenant config explicit.
- `CreateNamespace=true` makes the onboarding flow hands-free while still allowing RBAC and quotas per tenant.

### Multi-tenant model
- Namespace isolation is a simple and common baseline. It’s not a hard security boundary, but it’s realistic for a demo.
- The app reads `TENANT_NAME` from env to show how the same image can behave differently.

### Observability
- Centralized Prometheus/Grafana/Loki reduces ops overhead but increases shared blast radius; labels are critical.
- Each tenant has its own ServiceMonitor so metrics can be filtered by namespace.

### Tradeoffs
- GitOps PRs are slower than direct deploys, but they improve traceability and reduce config drift.
- Centralized observability is easy to manage but may need stronger tenancy controls in production.

## Questions + sample answers

1) Why use GitOps for such a small demo?
- It mirrors how production systems avoid config drift and make changes auditable. Even in a demo, it shows the workflow: build artifact -> change Git -> reconciler applies it.

2) How would you harden tenant isolation beyond namespaces?
- Add NetworkPolicies, RBAC per namespace, resource quotas, and optionally separate node pools. For stronger isolation, use separate clusters or virtual clusters.

3) Why choose Helm instead of raw YAML or Kustomize?
- Helm is common in platform teams and makes parameterizing image tags and per-tenant values straightforward. It also integrates naturally with Argo CD.

4) What happens if the ServiceMonitor label does not match Prometheus?
- Prometheus will not scrape the service. That is why the chart defaults the label to `release: kube-prometheus-stack` and docs call it out explicitly.

5) How do you ensure CI/CD and GitOps stay in sync?
- The workflow updates the GitOps values via PR using the same image tag it just built. That tag is the single source of truth.

6) How would you add alerts or SLOs?
- Add PrometheusRule resources via Helm and create Grafana alert rules. SLOs could be computed on request latency and error rates per namespace.

7) What would you change for a real multi-tenant SaaS?
- Stronger isolation, per-tenant quotas, per-tenant auth policies, separate observability projects, and more robust secrets management.

8) What is the biggest risk in this design?
- Centralized observability and shared cluster access can create noisy neighbors or blast radius issues. I would mitigate with quotas, rate limits, and strict RBAC.
