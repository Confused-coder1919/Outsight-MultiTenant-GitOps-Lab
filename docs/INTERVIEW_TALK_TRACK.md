# Interview Talk Track

## 30-second intro

I built a multi-tenant Kubernetes platform demo that shows the full delivery lifecycle: CI builds and publishes an image, GitOps promotes that image via PR, Argo CD reconciles tenant namespaces, Argo Rollouts gates rollout quality, and Prometheus/Grafana/Loki provide tenant-aware observability.

## 2-minute pitch

This project is intentionally small but operationally complete. The same FastAPI app is deployed to `tenant-a` and `tenant-b` using one Helm chart and tenant-specific values. CI runs lint/tests for pull requests, and on `main` it builds a multi-arch image, pushes to GHCR, and opens a GitOps PR that updates tenant image tags.

Argo CD watches the repository and reconciles changes declaratively. Instead of plain Deployments, I use Argo Rollouts with canary steps and Prometheus analysis to gate promotions. If analysis fails, rollout aborts automatically. For observability, Prometheus scrapes tenant metrics, Grafana visualizes tenant comparisons, and Loki queries logs by tenant labels.

I also expose a deterministic `make demo-compare` step that prints the Premium vs Standard tenant rollout steps, analysis thresholds, and network policy posture before running live canary demos.

The main point is to demonstrate reliable, auditable, and explainable platform operations, not just cluster setup.

## 5-minute technical walkthrough

1. **Start from CI pipeline**
   - show `.github/workflows/ci.yml`
   - explain PR vs main behavior
   - highlight image tags and GitOps PR automation

2. **Show GitOps deployment model**
   - `gitops/argocd/tenant-a-app.yaml`, `tenant-b-app.yaml`
   - explain chart reuse and tenant values separation

3. **Show rollout-based delivery**
   - `charts/demo-api/templates/rollout.yaml`
   - canary sequence and analysis template

4. **Show observability path**
   - ServiceMonitor and dashboard JSON
   - Loki label filtering for tenant-level logs

5. **Show operations scripts**
   - `verify.sh`, `vps_status.sh`, `canary-success`, `canary-demo`, `open_demo_ports.sh`

## If asked deeper

### CI/CD

- Why immutable tags? deterministic rollback and reproducibility
- Why PR-based promotion? auditable deployment intent
- What if CI cannot create PR? workflow now emits manual fallback commands

### GitOps

- Why Argo CD? continuous reconciliation and clear desired-state model
- Why chart values under `charts/demo-api/tenants`? stable path resolution for Argo source

### Multi-tenant model

- Why namespaces? simplest useful isolation boundary for demo and many SaaS workloads
- What would stronger isolation add? per-tenant clusters/virtual clusters, stricter policy controls

### Progressive delivery

- Why no mesh? keep demo lightweight and reproducible while still proving canary analysis gates
- How rollback works? failed AnalysisRun causes rollout abort, stable ReplicaSet remains

### Observability

- Metrics per tenant: service monitor labels + namespace filters
- Logs per tenant: promtail relabeling for `tenant`, `app`, `environment`

### Security/ops

- baseline policies: network policy, RBAC, probes, limits, PDB
- no secrets committed in repo

## 8 likely questions and strong sample answers

1. **How do you avoid config drift?**
   - GitOps is the source of truth; Argo continuously reconciles actual state to git state.

2. **How do you prove tenant isolation?**
   - Separate namespaces, tenant labels, and tenant-scoped RBAC/network policy.

3. **How do you handle bad releases?**
   - Argo Rollouts canary with Prometheus analysis aborts automatically.

4. **Why multi-arch images?**
   - ensures both local arm64 dev machines and amd64 VPS runtimes pull the same logical release tag.

5. **Where are your weakest points?**
   - namespace isolation and centralized observability are pragmatic but not strict enterprise isolation.

6. **What if Argo login fails with the initial secret?**
   - initial secret can be stale; reset active admin password in `argocd-secret` and restart server.

7. **What if rollout restart hangs?**
   - known restart edge case can leave `rollout is restarting`; force pod rotation to converge.

8. **How do you move this toward production?**
   - ingress+TLS, stronger policy enforcement, SLO-driven alerts, signed artifact verification, managed backend hardening.
