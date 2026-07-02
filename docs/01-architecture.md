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
7. Extract requested model and optional LoRA adapter.
8. Enforce tenant model allowlist.
9. Enforce tenant/model LoRA adapter allowlist.
10. Optionally enforce adapter catalog and artifact-verification evidence.
11. Enforce runtime quota through local demo mode or Redis reference mode.
12. Block streaming when billing-required modes cannot safely account for final usage.
13. Inject trusted AIBrix-facing headers.
14. Proxy to mock upstream, CPU demo upstream, or AIBrix/vLLM upstream.
15. Emit structured metering, audit, and Prometheus-compatible metrics.
16. Optionally write billing reference events to JSONL or AWS-native S3/DynamoDB.

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

## Billing behavior

Billing modes are reference controls:

| Mode | Behavior | Production status |
|---|---|---|
| `observability` | emits metering/audit events only | not billing-grade |
| `ledger_required` | requires upstream `usage` fields and writes local ledger | reference only |
| `aws_native_reference` | writes S3 Object Lock records with optional DynamoDB idempotency | reference only |

The repository does not include invoice reconciliation, dispute handling, customer billing lifecycle, or financial controls.

## Deployment paths

| Path | Description |
|---|---|
| Local demo | FastAPI + mock auth + mock upstream for local testing |
| CPU-only AWS demo | EKS deployment with mock upstream and public LoadBalancer for easy review |
| Advanced AWS GPU full-stack path | Optional paid AWS lab with GPU node group, AIBrix/vLLM, Cognito, Redis, S3/DynamoDB, and Pod Identity |

The Makefile target prefix `aws-danger-*` marks the advanced path as cost-bearing and quota-dependent. It is not a product name.

## Production-readiness boundary

This repository is production-inspired and audit-hardened, but not production-certified. The deepest remaining gaps are KV-cache isolation proof, full model/adapter supply-chain enforcement, streaming usage accounting, enterprise identity lifecycle, load-test evidence, and a complete AWS landing zone.
