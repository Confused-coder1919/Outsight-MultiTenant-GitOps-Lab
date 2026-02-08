#!/usr/bin/env bash
set -euo pipefail
export DEMO_FORCE_FAIL=0
exec "$(git rev-parse --show-toplevel)/scripts/canary_demo.sh"
