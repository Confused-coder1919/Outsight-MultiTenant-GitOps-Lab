# Report

## Project Goal

Build a realistic, interview-ready platform demo that proves end-to-end DevOps ownership for:

- CI/CD
- Kubernetes deployment management
- GitOps operations
- observability
- progressive delivery safety

## Scope Delivered

### Application

- FastAPI service with health and Prometheus metrics
- deterministic failure endpoint (gated for demo use)

### Multi-tenant Kubernetes

- namespace isolation (`tenant-a`, `tenant-b`)
- shared chart with per-tenant values
- premium vs standard tenant personas with distinct rollout/analysis/policy profiles
- standardized labels for observability and operations

### CI/CD

- GitHub Actions primary pipeline:
  - PR: lint/test
  - main: multi-arch build + GHCR push + GitOps promotion PR
- immutable and moving image tags
- promotion PR fallback messaging if repo policy blocks action-created PRs

### GitOps

- Argo CD Applications drive deployments from Git state
- sync options handle rollout CRD bootstrapping safely

### Progressive delivery

- Argo Rollouts canary deployment strategy
- Prometheus-backed AnalysisTemplate for 5xx and latency gates
- abort/rollback behavior demonstrated via scripts

### Observability

- Prometheus/Grafana/Loki/Promtail installed and wired
- tenant-aware dashboard and log filtering
- NodePort exposure for demo-friendly access

### Automation and operations

- idempotent scripts for bootstrap, verification, status, canary demos, and endpoint exposure
- deterministic tenant comparison via `make demo-compare` for recruiter walkthroughs

## Key Results

- full cluster is reproducibly brought to healthy state from scripts
- tenant workloads are independently observable and verifiable
- canary success and failure paths are both demonstrable on demand
- all primary demo UIs are reachable from stable VPS links

## Hardening Implemented

- probes, resource limits/requests, PDB
- baseline tenant network policies and RBAC
- CRD-aware sync settings
- no secret material in repo

## Challenges and Resolutions

1. **Argo CD login mismatches**
   - issue: initial admin secret can be stale after password changes
   - fix: documented reset flow patching active secret + syncing initial secret

2. **Rollout restart edge case**
   - issue: rollout can remain in `Progressing` with `rollout is restarting`
   - fix: documented operational recovery by forcing tenant pod rotation

3. **CI promotion PR reliability**
   - issue: action-created PR blocked by repo settings
   - fix: CI now emits clear fallback commands without hiding successful image build/push

## Limitations

- namespace tenancy is not strict security isolation
- centralized observability has shared blast radius
- NodePort exposure is demo-first, not production ingress best practice

## Next Steps

- add policy-as-code checks (admission controls)
- add SLO/alert budgets per tenant
- add signed image verification gate in promotion path
- move UI access to ingress + TLS in production-like mode

## Internship Responsibility Mapping

- **Enhance CI/CD pipelines**
  - implemented lint/test/build/promote pipeline with auditable GitOps handoff

- **Manage Kubernetes deployments using YAML, Helm, Argo CD**
  - implemented tenant-scoped Helm values + Argo CD Application model

- **Build observability (Prometheus/Grafana/Loki)**
  - implemented tenant-aware scraping, dashboarding, and log querying

- **Cloud-native monitoring integration orientation**
  - architecture supports migration to managed cloud backends without changing core workflow

- **Document architecture and outcomes**
  - full documentation set now aligned to actual runtime behavior and recovery paths
