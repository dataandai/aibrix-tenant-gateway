# Security Controls Matrix

| Control | Repo implementation | Evidence | Residual risk |
|---|---|---|---|
| Tenant identity | Host tenant resolution + OIDC tenant claim match | `policy_engine.py`, `jwt_validation.py` | Host routing still requires trusted ingress/LB/DNS posture |
| OIDC hardening | issuer/audience/signature, `exp`, `iat`, `nbf`, optional `token_use`, scope, group checks, JWKS cache | `jwt_validation.py`, `jwks_cache.py` | No IdP federation lifecycle or break-glass process |
| Header spoofing defense | Client routing headers stripped and trusted headers injected | `header_sanitizer.py`, tests | AIBrix must not be directly reachable by untrusted clients |
| Runtime quota | In-memory demo + Redis reference backend | `quota_enforcer.py`, `scripts/aws-danger/09-create-redis-quota-backend.sh` | Redis HA/failover and regional consistency not solved |
| Billing ledger | Local JSONL + AWS-native S3 Object Lock reference | `billing_ledger.py`, `scripts/aws-danger/11-create-aws-native-billing-ledger.sh` | No reconciliation job or invoice-grade controls |
| Adapter governance | Allowlist + catalog + artifact SHA verification utility | `adapter_governance.py`, `adapter_artifact_verifier.py` | No cryptographic signature enforcement at runtime |
| AWS Load Balancer | AWS LBC install, IAM policy, service account, NLB verification | `scripts/aws-danger/04-install-load-balancer-controller.sh`, `05-deploy-gateway-full-stack.sh` | Controller policy should be reviewed and scoped per org |
| Private networking | Private node default + verification script | `cluster-gpu.yaml`, `08-verify-private-networking.sh` | VPC endpoint and egress policy are evidence, not full landing zone |
| Supply chain | Locked requirements, CI scans, SBOM workflow, container scan/signing reference | `requirements.lock`, `.github/workflows` | Base image digest pinning must be finalized by the deploying org |
| Streaming SLOs | SSE proxy, TTFT metrics, stream token hints | `proxy.py`, `main.py`, `slo_metrics.py` | Decode tokens/sec and billing-grade stream usage not complete |
