# Demo Script

Use this script to run a clean 8-10 minute interview demo.

## 1) 2-minute framing

- This is a multi-tenant SaaS platform demo on Kubernetes.
- CI builds and publishes multi-arch images.
- GitOps promotion updates tenant values through PRs.
- Argo CD syncs, Argo Rollouts gates deployment quality.
- Prometheus/Grafana/Loki provide tenant-aware observability.

## 2) Pre-demo prep

```bash
cd /Users/syedtashfin/Documents/GitHub/outsight-platform-devops-demo
export KUBECONFIG=$(pwd)/infra/terraform/kubeconfig.yaml

make rollouts-up
make gitops
make demo-compare
make open-ports
./scripts/verify.sh
```

`make demo-compare` is the first recruiter-facing step. It prints:
- canary rollout step weights (`setWeight`) for tenant-a vs tenant-b
- rollout analysis thresholds (`maxErrorRate`, `maxP95LatencyMs`)
- whether NetworkPolicy is present in each tenant namespace

## 3) Show platform status

```bash
make demo-compare
./scripts/vps_status.sh
kubectl -n argocd get applications -o wide
kubectl -n tenant-a get rollouts.argoproj.io,pods
kubectl -n tenant-b get rollouts.argoproj.io,pods
```

What to say:

- both tenant apps are reconciled (`Synced/Healthy`)
- both tenants run same app image with isolated namespace boundaries

## 4) Show UIs and credentials

Open:

- Argo CD: `https://<vps-ip>:30443`
- Grafana: `http://<vps-ip>:30000`
- Prometheus: `http://<vps-ip>:30090`
- Loki readiness: `http://<vps-ip>:31000/ready`

Credential commands:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo
kubectl -n observability get secret kube-prometheus-stack-grafana -o jsonpath='{.data.admin-password}' | base64 -d; echo
```

## 5) Show tenant app behavior

```bash
kubectl -n tenant-a port-forward svc/demo-api 18080:8000
kubectl -n tenant-b port-forward svc/demo-api 28080:8000
```

Then:

```bash
curl http://127.0.0.1:18080/
curl http://127.0.0.1:28080/
curl http://127.0.0.1:18080/metrics | head
```

## 6) Progressive delivery (success)

```bash
WAIT_SECONDS=300 TRAFFIC_SECONDS=60 make canary-success
```

Show while running:

```bash
kubectl -n tenant-a get analysisruns.argoproj.io --sort-by=.metadata.creationTimestamp
kubectl argo rollouts get rollout demo-api -n tenant-a
```

Expected outcome:

- rollout remains healthy
- latest AnalysisRun is successful

## 7) Progressive delivery (failure + auto-abort)

```bash
WAIT_SECONDS=300 TRAFFIC_SECONDS=60 make canary-demo
```

Expected outcome:

- canary analysis fails
- rollout aborts and script cleans up to baseline

## 8) CI/GitOps story (show in GitHub)

- PR run: lint + test only
- main run: buildx multi-arch push + GitOps promotion PR
- if PR creation is blocked by repo policy, workflow emits manual fallback commands

## 9) Troubleshooting cues

- Argo invalid login from initial secret: stale secret, reset via runbook
- rollout restart seems stuck: force pod rotation in tenant namespaces
- ImagePullBackOff: check GHCR tag visibility/auth and architecture manifest
