.PHONY: install test run run-hardening metrics demo-a demo-b demo-cross demo-lora demo-spoof aws-check aws-create-cluster aws-build-push aws-deploy aws-smoke aws-logs aws-destroy aws-danger-check aws-danger-create-gpu-cluster aws-danger-oidc aws-danger-artifacts aws-danger-install-lbc aws-danger-install-aibrix aws-danger-redis-quota aws-danger-billing-ledger aws-danger-pod-identity aws-danger-deploy aws-danger-verify-private aws-danger-verify-adapters aws-danger-smoke aws-danger-logs aws-danger-destroy tree ci-supply-chain

install:
	python -m pip install -r requirements.txt

test:
	PYTHONPATH=src pytest -q

run:
	APP_TENANT_REGISTRY_PATH=./config/tenants.yaml \
	APP_AUTH_MODE=mock \
	APP_MOCK_UPSTREAM=true \
	PYTHONPATH=src \
	uvicorn tenant_policy_gateway.main:app --host 0.0.0.0 --port 8080

run-hardening:
	APP_TENANT_REGISTRY_PATH=./config/tenants.yaml \
	APP_AUTH_MODE=mock \
	APP_ENVIRONMENT=local \
	APP_MOCK_UPSTREAM=true \
	APP_QUOTA_MODE=in_memory \
	APP_BILLING_MODE=ledger_required \
	APP_AUDIT_SINK=jsonl \
	APP_ADAPTER_GOVERNANCE_MODE=catalog_enforced \
	APP_SECURITY_POSTURE_MODE=audit \
	PYTHONPATH=src \
	uvicorn tenant_policy_gateway.main:app --host 0.0.0.0 --port 8080

metrics:
	curl -s http://localhost:8080/metrics

demo-a:
	./examples/tenant-a-valid.sh

demo-b:
	./examples/tenant-b-valid.sh

demo-cross:
	./examples/cross-tenant-denied.sh

demo-lora:
	./examples/forbidden-lora-denied.sh

demo-spoof:
	./examples/spoofed-header-ignored.sh

tree:
	find . -maxdepth 4 -type f | sort


aws-check:
	./scripts/aws/00-check-prereqs.sh

aws-create-cluster:
	./scripts/aws/01-create-cluster.sh

aws-build-push:
	./scripts/aws/02-build-push-ecr.sh

aws-deploy:
	./scripts/aws/03-deploy-demo.sh

aws-smoke:
	./scripts/aws/04-smoke-test.sh

aws-logs:
	./scripts/aws/05-logs.sh

aws-destroy:
	./scripts/aws/99-destroy-demo.sh


# AWS DANGER ZONE: real GPU/AIBrix/vLLM/OIDC path. Requires explicit consent:
#   export I_UNDERSTAND_AWS_GPU_COST_AND_QUOTAS=yes
aws-danger-check:
	./scripts/aws-danger/00-check-danger-prereqs.sh

aws-danger-create-gpu-cluster:
	./scripts/aws-danger/01-create-gpu-cluster.sh

aws-danger-oidc:
	./scripts/aws-danger/02-bootstrap-cognito-oidc.sh

aws-danger-artifacts:
	./scripts/aws-danger/03-create-artifact-buckets.sh

aws-danger-install-lbc:
	./scripts/aws-danger/04-install-load-balancer-controller.sh

aws-danger-install-aibrix:
	./scripts/aws-danger/04-install-aibrix-platform.sh

aws-danger-redis-quota:
	./scripts/aws-danger/09-create-redis-quota-backend.sh

aws-danger-billing-ledger:
	./scripts/aws-danger/11-create-aws-native-billing-ledger.sh

aws-danger-pod-identity:
	./scripts/aws-danger/12-bootstrap-gateway-pod-identity.sh

aws-danger-deploy:
	./scripts/aws-danger/05-deploy-gateway-full-stack.sh

aws-danger-verify-private:
	./scripts/aws-danger/08-verify-private-networking.sh

aws-danger-verify-adapters:
	./scripts/aws-danger/10-verify-adapter-artifacts.sh

aws-danger-smoke:
	./scripts/aws-danger/06-smoke-test-full-stack.sh

aws-danger-logs:
	./scripts/aws-danger/07-logs-full-stack.sh

aws-danger-destroy:
	./scripts/aws-danger/99-destroy-full-stack.sh


ci-supply-chain:
	python -m pip install -r requirements.txt
	PYTHONPATH=src pytest -q
	@if command -v trivy >/dev/null 2>&1; then trivy fs --exit-code 1 --severity HIGH,CRITICAL .; else echo "trivy not installed; skipping local scan"; fi
	@if command -v syft >/dev/null 2>&1; then syft packages dir:. -o spdx-json > sbom.spdx.json; else echo "syft not installed; skipping local SBOM"; fi
