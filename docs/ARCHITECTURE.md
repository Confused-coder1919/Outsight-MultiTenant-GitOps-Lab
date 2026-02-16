# Architecture

## 1) System Overview

This project is a Kubernetes platform demo with four tightly connected concerns:

- CI/CD artifact production
- GitOps-based deployment control
- multi-tenant runtime isolation
- observability and progressive delivery safety gates

## 2) End-to-End Flow

```text
Code Push
  -> GitHub Actions (lint/test/build)
  -> GHCR image publish (sha/main/dev, multi-arch)
  -> GitOps PR updates tenant image tags
  -> Argo CD syncs Helm chart into tenant namespaces
  -> Argo Rollouts canary + analysis gates promotion
  -> Prometheus/Grafana/Loki observe result per tenant
```

## 3) Components

### Application

- FastAPI app
- `/health` for probes
- `/metrics` for Prometheus
- optional `/fail` endpoint for controlled canary-failure demo

### Packaging

- Docker image published to GHCR
- immutable deploy tag: `sha-<shortsha>`

### Deployment

- Helm chart in `charts/demo-api`
- two tenant values files for Argo runtime deployment

### GitOps

- Argo CD Applications under `gitops/argocd/`
- `CreateNamespace=true`
- `SkipDryRunOnMissingResource=true` for rollout CRD safety

### Progressive Delivery

- `Rollout` with canary steps and pauses
- `AnalysisTemplate` queries Prometheus for:
  - 5xx ratio
  - p95 latency
- failed analysis aborts promotion

### Tenant Personas (Premium vs Standard)

- Both tenants use one chart and one app image, with different value overlays.
- Premium (`tenant-a`) uses stricter rollout and policy defaults:
  - `10 -> pause -> analysis -> 50 -> pause -> analysis -> 100`
  - tighter analysis thresholds and stronger alert/policy posture.
- Standard (`tenant-b`) uses a cost-optimized profile:
  - `20 -> pause -> analysis -> 100`
  - looser thresholds and fewer enabled alerts.
- Shared baseline values are centralized in `charts/demo-api/values-common.yaml`.

### Observability

- Prometheus scrapes tenant ServiceMonitors
- Grafana dashboard compares tenant-a vs tenant-b
- Loki stores logs with tenant labels from promtail relabeling

## 4) Multi-Tenant Design

- isolation boundary: Kubernetes namespace
- standardized labels: `tenant`, `app`, `environment`
- tenant-scoped RBAC viewer role
- tenant network policies and resource guardrails

## 5) Deployment Modes

### Local

- k3d cluster
- script-driven install + verify

### VPS

- Terraform bootstraps k3s + add-ons
- kubeconfig copied locally for operations
- NodePorts exposed for Argo/Grafana/Prometheus/Loki demos

## 6) Security and Reliability Baselines

- probes + resource requests/limits
- PodDisruptionBudget
- NetworkPolicy baseline
- no secrets in repo
- runtime credentials retrieved from cluster secrets

## 7) Tradeoffs

### Chosen

- centralized observability stack
- namespace-level tenancy
- GitOps PR promotion model

### Benefits

- minimal operational overhead for demo
- reproducible and auditable workflow
- clear, explainable moving parts for interviews

### Limitations

- namespace isolation is not hard tenant isolation
- centralized observability increases shared blast radius
- NodePort exposure is demo-friendly, not production ingress/TLS best practice

## 8) Failure Modes and Recovery Patterns

- CI promotion PR blocked by repo permissions:
  - build/push still succeeds
  - workflow emits manual fallback commands
- rollout stuck in restarting state:
  - force pod rotation in tenant namespace
- Argo login invalid from initial secret:
  - reset password in `argocd-secret`, restart `argocd-server`

## 9) AWS / Hybrid Extension (Conceptual)

Without changing the core model:

- k3s/k3d -> EKS or hybrid cluster
- GHCR -> ECR (or dual-registry strategy)
- NodePort demo access -> Ingress + TLS + WAF
- centralized observability -> managed backends and/or per-tenant projects

Core workflow (CI -> GitOps PR -> Argo reconcile -> rollout analysis) remains the same.
