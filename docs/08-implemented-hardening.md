# 08 — Implemented Hardening

This document lists the hardening controls currently implemented in the repository. It is intentionally precise: implemented reference controls are not the same as production certification.

## Application controls

| Control | Status |
|---|---|
| Mock auth blocked outside local/dev/test/ci by default | Implemented |
| OIDC/JWKS validation | Implemented |
| JWKS cache | Implemented |
| `token_use`, scope, group, `nbf`, leeway checks | Implemented |
| Host tenant must match JWT tenant claim | Implemented |
| Client routing headers stripped | Implemented |
| Trusted internal headers injected | Implemented |
| Model allowlist | Implemented |
| LoRA adapter allowlist | Implemented |
| Adapter catalog metadata enforcement | Implemented |
| Adapter SHA256 verification utility | Implemented |
| Streaming proxy | Implemented |
| Upstream streaming status propagation | Implemented |
| TTFT metrics | Implemented |
| Streaming blocked in billing-required modes by default | Implemented |

## Quota and billing controls

| Control | Status |
|---|---|
| Local in-memory quota for demos | Implemented |
| Redis Lua quota reference | Implemented |
| Tenant and user request counters | Implemented |
| Tenant and user input-token counters | Implemented |
| Tenant and user concurrency counters | Implemented |
| Local JSONL audit/billing reference | Implemented |
| AWS-native S3 Object Lock billing reference | Implemented |
| DynamoDB request-id idempotency reference | Implemented |

## AWS/EKS controls

| Control | Status |
|---|---|
| CPU-only AWS demo path | Implemented |
| Advanced GPU full-stack path | Implemented as optional warning-gated path |
| AWS Load Balancer Controller script | Implemented |
| NLB scheme verification | Implemented |
| Cognito OIDC bootstrap | Implemented |
| Immutable Cognito tenant claim | Implemented |
| Default Cognito password rejection | Implemented |
| Redis/ElastiCache quota bootstrap | Implemented |
| S3 artifact buckets | Implemented |
| Pod Identity/IRSA reference | Implemented |
| Private networking evidence script | Implemented |
| AIBrix/vLLM deployment templates | Implemented |

## Supply-chain controls

| Control | Status |
|---|---|
| `requirements.lock` | Implemented |
| GitHub Actions CI | Implemented |
| Trivy/SBOM workflow references | Implemented |
| Container image signing reference | Documented/reference |
| Base image digest pinning | Left to deploying org |

## Controls not completed

- KV-cache isolation proof.
- Cryptographic runtime adapter signature enforcement.
- Billing reconciliation and invoice lifecycle.
- Billing-grade streaming usage extraction.
- Full private AWS landing zone.
- Karpenter GPU autoscaling.
- GPU load tests and noisy-neighbor evidence.
- Admission-controller level model/adapter governance.
