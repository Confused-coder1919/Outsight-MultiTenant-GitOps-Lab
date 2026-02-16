APP_NAME := demo-api
IMAGE_NAME ?= ghcr.io/confused-coder1919/outsight-platform-devops-demo/demo-api
TAG ?= dev

.PHONY: lint test run docker-build docker-run k3d argocd observability gitops \
	vps-up vps-verify vps-down local-up local-verify vps-status \
	argo-rollouts rollouts-up canary-demo canary-success demo-traffic demo-compare open-ports help

lint:
	ruff check .

test:
	pytest -q

run:
	uvicorn app.main:app --reload --host 0.0.0.0 --port 8000

docker-build:
	docker build -t $(IMAGE_NAME):$(TAG) .

docker-run:
	docker run --rm -p 8000:8000 -e TENANT_NAME=local $(IMAGE_NAME):$(TAG)

k3d:
	./scripts/bootstrap_k3d.sh

argocd:
	./scripts/install_argocd.sh

observability:
	./scripts/install_observability.sh

gitops:
	./scripts/deploy_gitops.sh

rollouts-up:
	./scripts/install_argo_rollouts.sh

argo-rollouts: rollouts-up

rollouts: rollouts-up

vps-up:
	./scripts/bootstrap_vps.sh

vps-verify:
	KUBECONFIG=$(PWD)/infra/terraform/kubeconfig.yaml ./scripts/verify.sh

vps-down:
	@read -p "This will destroy the VPS k3s stack. Continue? [y/N] " ans; \
	if [ "$$ans" != "y" ] && [ "$$ans" != "Y" ]; then echo "Aborted."; exit 1; fi; \
	cd infra/terraform && terraform destroy

local-up:
	./scripts/run_local_k3d.sh

local-verify:
	@CLUSTER_NAME=$${CLUSTER_NAME:-outsight-demo}; \
	K3D_KUBECONFIG="$$HOME/.k3d/kubeconfig-$$CLUSTER_NAME.yaml"; \
	if [ ! -f "$$K3D_KUBECONFIG" ]; then k3d kubeconfig write "$$CLUSTER_NAME" >/dev/null; fi; \
	KUBECONFIG="$$K3D_KUBECONFIG" ./scripts/verify.sh

canary-demo: rollouts-up
	./scripts/canary_demo.sh

canary-success: rollouts-up
	./scripts/canary_success.sh

demo-traffic:
	./scripts/loadgen.sh --duration $${DURATION_SECONDS:-60}

demo-compare:
	./scripts/demo_premium_vs_standard.sh

vps-status:
	./scripts/vps_status.sh

open-ports:
	./scripts/open_demo_ports.sh

help:
	@echo "Usage:"; \
	echo "  make k3d              Create local k3d cluster"; \
	echo "  make observability    Install Prometheus/Grafana/Loki"; \
	echo "  make argocd           Install Argo CD"; \
	echo "  make rollouts-up      Install Argo Rollouts CRDs/controller"; \
	echo "  make gitops           Apply Argo Applications"; \
	echo "  make vps-up           Bootstrap VPS via Terraform"; \
	echo "  make vps-verify       Verify VPS deployment"; \
	echo "  make vps-down         Destroy VPS stack (prompted)"; \
	echo "  make vps-status       Show VPS cluster/apps/rollout status"; \
	echo "  make local-up         Run full demo locally"; \
	echo "  make local-verify     Verify local deployment"; \
	echo "  make canary-demo      Trigger canary failure and rollback demo"; \
	echo "  make canary-success   Run healthy canary progression demo"; \
	echo "  make demo-traffic     Generate healthy traffic for both tenants"; \
	echo "  make demo-compare     Compare Premium vs Standard tenant personas"; \
	echo "  make open-ports       Expose Argo/Grafana/Prometheus/Loki demo URLs"
