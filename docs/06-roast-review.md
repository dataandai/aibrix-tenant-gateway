# 06 — Roast Review

This is the deliberately harsh review of the repository. It exists so that nobody accidentally presents the project as a finished SaaS LLM platform.

## What would break in production?

- Direct access to AIBrix/vLLM would bypass the gateway policy.
- Shared vLLM runtimes still need KV-cache, batching, and noisy-neighbor proof.
- Redis quota requires real HA, failover, regional, and failure-mode decisions.
- S3/DynamoDB billing evidence is not a complete billing platform.
- Streaming is blocked in billing-required modes because billing-grade stream usage extraction is not implemented.
- Adapter SHA checks are not the same as cryptographic supply-chain enforcement.
- AWS networking scripts produce evidence, not a full private landing zone.
- GPU capacity, cost, model cold-starts, and image/model pull times can still surprise users.

## What is fake or demo-only?

- Mock auth.
- Mock upstream.
- Local JSONL audit and billing files.
- Placeholder model/LoRA artifacts used to exercise verification paths.
- CPU-only AWS demo as a security model.
- Any claim that the advanced GPU path proves production isolation.

## What is real and useful?

- Tenant resolution from Host domain.
- JWT tenant claim matching.
- Header stripping and trusted header injection.
- Model and LoRA allowlist enforcement.
- OIDC hardening hooks: token_use, scopes, groups, JWKS cache.
- Redis Lua-based quota reference.
- AWS-native billing reference through boto3, S3 Object Lock, and DynamoDB idempotency.
- Streaming proxy with TTFT metrics and safe billing gate.
- AWS Load Balancer Controller and Pod Identity reference scripts.
- Adapter verification evidence gate for the advanced path.

## What would an enterprise reviewer reject?

An enterprise reviewer would reject any claim that this is production-certified. They would ask for:

- full AWS landing zone controls,
- IAM least-privilege review,
- VPC endpoint and egress proof,
- WAF/TLS/certificate lifecycle,
- enterprise IdP lifecycle and federation,
- billing reconciliation and financial controls,
- runtime model/adapter admission enforcement,
- KV-cache isolation evidence,
- GPU load tests with TTFT, queue time, and noisy-neighbor analysis,
- SIEM/audit-retention integration,
- signed images, SBOM retention, and registry admission policy.

## Correct positioning

The repository is strong because it is honest. It shows a credible architecture and practical AWS/EKS paths, while explicitly naming the controls that remain outside the reference implementation.

Best description:

> Audit-hardened AWS/EKS LLMOps reference lab for tenant-policy governance in front of AIBrix/vLLM.

Do not call it production-ready.
