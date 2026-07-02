# 07 — Production Hardening Implementation Plan

This plan separates what the repository demonstrates from what a production platform would still need.

## Implemented reference layers

| Area | Current reference implementation |
|---|---|
| Auth | mock guardrail, OIDC/JWKS validation, tenant claim matching |
| OIDC hardening | token_use, scopes, groups, nbf/leeway, JWKS cache |
| Header security | spoofable routing headers stripped, trusted headers injected |
| Quota | in-memory demo and Redis Lua reference backend |
| Billing | JSONL reference and AWS-native S3 Object Lock + DynamoDB reference |
| Adapter governance | allowlist, catalog metadata, SHA256 verification utility, evidence gate |
| Streaming | SSE proxy, upstream status propagation, TTFT metrics, billing-required block |
| AWS | EKS scripts, LBC, Pod Identity, Redis, S3/DynamoDB, AIBrix/vLLM advanced path |
| Supply chain | lockfile, CI scan references, SBOM workflow, container scan/signing reference |

## Production roadmap

### Phase 1 — Hardening the reference lab

- Run the advanced path in a real AWS account and capture evidence.
- Validate Pod Identity IAM policies with least-privilege review.
- Replace optional public HTTPS egress with FQDN policy, VPC endpoints, or egress proxy.
- Capture NLB, security group, and route-table evidence.
- Add live smoke tests for Redis, S3, DynamoDB, Cognito JWKS, and AIBrix upstream.

### Phase 2 — Billing and quota maturity

- Add output-token quota and cost budget enforcement.
- Add billing reconciliation jobs.
- Add duplicate/retry/idempotency tests against DynamoDB and S3.
- Define pricing-plan lifecycle and tenant-tier changes.
- Decide whether streaming will remain blocked in billing-required modes or implement final usage extraction.

### Phase 3 — Runtime and model governance

- Add model registry as the runtime source of truth.
- Add adapter signature verification using KMS/cosign.
- Add admission or initContainer gates for verified model/adapter artifacts.
- Add quarantine and rollback workflows.
- Prove vLLM/AIBrix KV-cache and batching behavior under multi-tenant load.

### Phase 4 — Production AWS landing zone

- Multi-account AWS structure.
- VPC endpoints and egress controls.
- Centralized logging and SIEM export.
- GuardDuty/Security Hub integration.
- WAF/TLS/cert lifecycle.
- Disaster recovery.
- Policy-as-code and compliance evidence.

## Non-goal

This plan does not turn the repository into a managed service. It describes the work needed to evolve the reference lab toward a production platform.
