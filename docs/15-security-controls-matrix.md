# 15 — Security Controls Matrix

This matrix maps repository controls to evidence and known gaps.

| Control area | Implemented reference control | Evidence | Remaining gap |
|---|---|---|---|
| Mock auth guardrail | mock mode blocked outside local/dev/test/ci unless unsafe override is set | `config.py`, tests | does not make mock auth secure |
| Tenant boundary | Host domain must match JWT tenant claim | `policy_engine.py`, tests | requires trusted ingress and non-bypassable upstream |
| OIDC hardening | issuer/audience/signature, `exp`, `iat`, `nbf`, optional `token_use`, scopes, groups, JWKS cache | `jwt_validation.py`, `jwks_cache.py` | no enterprise IdP lifecycle or federation workflow |
| Header spoofing defense | client routing headers stripped and trusted headers injected | `header_sanitizer.py`, tests | AIBrix must not be directly reachable |
| Runtime quota | in-memory demo + Redis Lua reference backend | `quota_enforcer.py`, `scripts/aws-danger/09-create-redis-quota-backend.sh` | no full HA/failover, cost budget, or regional policy |
| Billing ledger | JSONL + S3 Object Lock/DynamoDB reference | `billing_ledger.py`, `scripts/aws-danger/11-create-aws-native-billing-ledger.sh` | no reconciliation, invoicing, or dispute workflow |
| Streaming | upstream status propagation, TTFT metrics, billing-required block | `proxy.py`, `main.py`, `slo_metrics.py` | no billing-grade streaming usage extraction |
| Adapter governance | allowlist + catalog + SHA verification utility + evidence gate | `adapter_governance.py`, `adapter_artifact_verifier.py` | no cryptographic signature enforcement at runtime |
| AWS Load Balancer | AWS LBC install, IAM policy, service account, NLB verification | `scripts/aws-danger/04-install-load-balancer-controller.sh`, `05-deploy-gateway-full-stack.sh` | org-specific IAM and SG review still required |
| Pod AWS identity | Pod Identity/IRSA bootstrap for gateway AWS API access | `scripts/aws-danger/12-bootstrap-gateway-pod-identity.sh` | must be reviewed against org IAM boundaries |
| Private networking | private node default + verification script | `cluster-gpu.yaml`, `08-verify-private-networking.sh` | not a full VPC endpoint/egress landing zone |
| Supply chain | locked requirements, CI scans, SBOM workflow, container scan/signing reference | `requirements.lock`, `.github/workflows` | deploying org must enforce digest pinning/signature admission |
| Runtime isolation | isolation intent in tenant config and headers | `tenant_registry.py`, tenant YAML | no KV-cache/batching proof |
