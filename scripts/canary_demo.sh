#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="${NAMESPACE:-tenant-a}"
ROLLOUT_NAME="${ROLLOUT_NAME:-demo-api}"
SERVICE_NAME="${SERVICE_NAME:-demo-api}"
LOCAL_PORT="${LOCAL_PORT:-18080}"

# Demo knobs: override analysis conditions for short deterministic windows
# When DEMO_FORCE_FAIL=1, we fail quickly. When 0, we succeed.
DEMO_FORCE_FAIL="${DEMO_FORCE_FAIL:-1}"

ROOT="$(git rev-parse --show-toplevel)"
"$ROOT/scripts/install_argo_rollouts.sh" >/dev/null

echo "[canary] Patching chart values for deterministic demo gating (DEMO_FORCE_FAIL=$DEMO_FORCE_FAIL)"
# We keep this local-only: patch values files used by Argo (charts/demo-api/tenants/*)
# so Argo will reconcile it.
TENANT_VALUES="$ROOT/charts/demo-api/tenants/tenant-a-values.yaml"
test -f "$TENANT_VALUES" || { echo "Missing $TENANT_VALUES"; exit 1; }

# Use python to patch YAML without requiring yq
python3 - "$TENANT_VALUES" "$DEMO_FORCE_FAIL" <<'PY'
import sys, yaml
path = sys.argv[1]
force_fail = sys.argv[2] == "1"
with open(path, "r") as f:
    data = yaml.safe_load(f) or {}

data.setdefault("rollouts", {})
data["rollouts"]["enabled"] = True

data.setdefault("analysis", {})
data["analysis"]["enabled"] = True

# Deterministic gating: if force_fail, fail when any 5xx > 0.
# If not, require 5xx == 0.
if force_fail:
    data["analysis"]["successCondition5xx"] = "result[0] == 0"
    data["analysis"]["failureCondition5xx"] = "result[0] > 0"
else:
    data["analysis"]["successCondition5xx"] = "result[0] == 0"
    data["analysis"]["failureCondition5xx"] = "result[0] > 0"

with open(path, "w") as f:
    yaml.safe_dump(data, f, sort_keys=False)
print(f"Patched {path}")
PY

echo "[canary] Committing demo gating patch (local repo state)."
git add "$TENANT_VALUES" >/dev/null 2>&1 || true
git commit -m "chore(canary): deterministic gating for demo" >/dev/null 2>&1 || true

echo "[canary] Wait for Argo to sync the change..."
# Just wait for rollout object to exist; Argo sync time varies.
for i in $(seq 1 60); do
  if kubectl -n "$NAMESPACE" get rollout "$ROLLOUT_NAME" >/dev/null 2>&1; then break; fi
  sleep 2
done

echo "[canary] Port-forward service for generating traffic (kills itself on exit)"
set +e
kubectl -n "$NAMESPACE" port-forward "svc/$SERVICE_NAME" "${LOCAL_PORT}:8000" >/tmp/pf_canary.log 2>&1 &
PF_PID=$!
set -e

cleanup() {
  if ps -p "$PF_PID" >/dev/null 2>&1; then kill "$PF_PID" >/dev/null 2>&1 || true; fi
}
trap cleanup EXIT

sleep 2

echo "[canary] Generating traffic for ~20s (includes some 5xx when force_fail=1 if app supports it)"
END=$((SECONDS+20))
while [ $SECONDS -lt $END ]; do
  curl -fsS "http://127.0.0.1:${LOCAL_PORT}/health" >/dev/null 2>&1 || true
  curl -fsS "http://127.0.0.1:${LOCAL_PORT}/metrics" >/dev/null 2>&1 || true
  # If your app has a failure endpoint, call it. Otherwise this is harmless.
  if [ "$DEMO_FORCE_FAIL" = "1" ]; then
    curl -fsS "http://127.0.0.1:${LOCAL_PORT}/fail" >/dev/null 2>&1 || true
  fi
  sleep 0.2
done

echo "[canary] Stopping port-forward to avoid hangs..."
cleanup

echo "[canary] Show rollout + analysis status"
kubectl -n "$NAMESPACE" get rollout,analysisrun -o wide || true

echo "[canary] Done"
