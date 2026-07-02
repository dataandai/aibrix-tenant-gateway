# 01 — Architecture

## One-sentence architecture

The Tenant Policy Gateway is a SaaS governance layer in front of AIBrix/vLLM: it resolves the tenant, validates identity, enforces model/adapter policy, strips spoofable headers, applies reference quota/billing hooks, and forwards only trusted metadata to the serving substrate.

```text
Client
  -> DNS / NLB / Gateway layer
  -> Tenant Policy Gateway
  -> AIBrix / Envoy / vLLM serving substrate
```

AIBrix/vLLM is intentionally treated as the serving substrate, not as the SaaS auth boundary.

## Request decision sequence

1. Receive request on `/v1/chat/completions` or `/v1/completions`.
2. Resolve tenant from the `Host` domain.
3. Strip client-supplied routing headers from the request context.
4. Validate JWT in local mock mode or OIDC/JWKS mode.
5. Verify JWT tenant claim equals the resolved tenant.
6. Validate optional OIDC controls such as `token_use`, scopes, groups, `nbf`, and leeway.
7. Parse the body through a strict Pydantic request contract. Unknown fields fail closed with `400 invalid_request_schema`.
8. Extract the canonical requested model and optional canonical `lora_adapter` field from the normalized request.
9. Estimate input tokens with the initialized deterministic tokenizer for quota decisions.
10. Enforce tenant model allowlist.
11. Enforce tenant/model LoRA adapter allowlist.
12. Optionally enforce adapter catalog and artifact-verification evidence.
13. Enforce runtime quota through local demo mode or Redis ZSET sliding-window reference mode.
14. Block streaming when billing-required modes cannot safely account for final usage.
15. Inject trusted AIBrix-facing headers.
16. Proxy to mock upstream, CPU demo upstream, or AIBrix/vLLM upstream.
17. Emit structured metering, audit, and Prometheus-compatible metrics.
18. Optionally enqueue billing reference events to a memory-bounded batched JSONL/S3 ledger.

## Trusted header injection

The gateway injects these headers after an allow decision:

```text
user: {tenant_id}:{user_id}
external-filter: tenant={tenant_id}
config-profile: <profile>
x-internal-tenant-id: <tenant_id>
x-internal-user-id: <user_id>
x-internal-kv-cache-isolation-required: <true|false>
x-internal-runtime-isolation-mode: <mode>
```

These headers are for downstream routing, request tagging, scheduler hints, and audit correlation. They are **not** a security boundary by themselves.

## Spoofed header behavior

A client may send a header such as `external-filter: tenant=other`. The gateway does not use that value for policy decisions and does not forward it.

If the request is otherwise valid, it may still be allowed. The security goal is not “deny every spoofed-header request.” The goal is stronger and more precise: client-supplied routing metadata must not influence the policy decision or downstream trusted headers.

## AIBrix integration point

The upstream URL is configurable. In the advanced AWS GPU path, it is expected to be a private Kubernetes service such as:

```text
http://aibrix-gateway.aibrix-system.svc.cluster.local
```

A production design must ensure this upstream is not reachable directly by untrusted clients or untrusted workloads.

## Streaming behavior

The gateway supports `stream=true` proxying and records TTFT-style metrics. However, streaming is blocked by default when `APP_BILLING_MODE=ledger_required` or `APP_BILLING_MODE=aws_native_reference`, because the reference implementation does not yet provide billing-grade final usage extraction from streaming responses.

This is intentional fail-closed behavior.

## Strict request contract

The gateway intentionally does not scan arbitrary JSON for adapter hints. Supported request bodies are parsed through strict Pydantic models for `/v1/chat/completions` and `/v1/completions`. The canonical adapter field is `lora_adapter`. Unknown fields such as vendor-specific hidden adapter parameters are rejected with `400 invalid_request_schema` instead of being forwarded silently.

This is important because adapter allowlisting is only meaningful if the policy engine sees exactly the same adapter instruction that will be forwarded downstream.

## Token estimation behavior

Input-token estimates used for pre-forward quota decisions are produced by an initialized tokenizer. Production-like quota modes require either `tiktoken` or a local HuggingFace fast tokenizer asset. The loose character-count fallback was removed from production modes because it can undercount multilingual text and code.

A deterministic UTF-8 byte upper-bound mode remains only for local/demo use. It is conservative, not billing-grade.

## Billing behavior

Billing modes are reference controls:

| Mode | Behavior | Production status |
|---|---|---|
| `observability` | emits metering/audit events only | not billing-grade |
| `ledger_required` | requires upstream `usage` fields and enqueues local JSONL ledger records | reference only |
| `aws_native_reference` | batches JSONL records into S3 Object Lock objects with optional DynamoDB idempotency | reference only |

The ledger is memory-bounded and flushed in batches to avoid one S3 PUT per request. The repository still does not include invoice reconciliation, dispute handling, customer billing lifecycle, or financial controls.

## Deployment paths

| Path | Description |
|---|---|
| Local demo | FastAPI + mock auth + mock upstream for local testing |
| CPU-only AWS demo | EKS deployment with mock upstream and public LoadBalancer for easy review |
| Advanced AWS GPU full-stack path | Optional paid AWS lab with GPU node group, AIBrix/vLLM, Cognito, Redis, S3/DynamoDB, and Pod Identity |

The Makefile target prefix `aws-danger-*` marks the advanced path as cost-bearing and quota-dependent. It is not a product name.

## Production-readiness boundary

This repository is production-inspired and audit-hardened, but not production-certified. The deepest remaining gaps are KV-cache isolation proof, full model/adapter supply-chain enforcement, streaming usage accounting, enterprise identity lifecycle, load-test evidence, and a complete AWS landing zone.
