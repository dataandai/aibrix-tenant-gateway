# 01 — Architecture

## High-level flow

```text
Client
  -> Gateway API / Envoy Gateway / ALB integration
  -> Tenant Policy Gateway
  -> AIBrix Gateway / vLLM pool
```

AIBrix/vLLM is treated as the serving substrate. The Tenant Policy Gateway is the SaaS policy enforcement point.

## Request decision sequence

1. Receive request on `/v1/chat/completions` or `/v1/completions`.
2. Resolve tenant from `Host` domain.
3. Validate JWT in mock or OIDC/JWKS mode.
4. Verify JWT tenant claim equals resolved tenant.
5. Extract requested model from request body.
6. Extract optional LoRA adapter from supported MVP fields.
7. Enforce tenant model allowlist.
8. Enforce model adapter allowlist.
9. Strip spoofable routing headers.
10. Inject trusted AIBrix-facing headers.
11. Proxy to upstream AIBrix service or mock upstream.
12. Emit structured JSON metering event.

## AIBrix integration point

The MVP forwards allowed requests to a configurable upstream URL. In Kubernetes this is expected to be an internal service such as:

```text
http://aibrix-gateway.aibrix-system.svc.cluster.local
```

The gateway injects:

```text
user: {tenant_id}:{user_id}
external-filter: tenant={tenant_id}
config-profile: <profile>
x-internal-tenant-id: <tenant_id>
x-internal-user-id: <user_id>
```

These headers are intended to support downstream routing, filtering, request tagging, or scheduler integration. They are not a security boundary by themselves.

## Spoofed header behavior

A client may send spoofed routing headers such as `external-filter: tenant=other`. The gateway does not use those values for policy decisions and does not forward them.

If the request is otherwise valid, it can still be allowed, but AIBrix receives only gateway-derived trusted headers. If the tenant/domain/JWT/model/adapter policy fails, the request is denied.

This is more precise than saying "spoofed header equals denied." The security goal is: spoofed headers must not steer policy or routing.

## LoRA routing model

The tenant registry uses per-model adapter allowlists:

```yaml
allowed_models:
  meta-llama/Llama-3.1-8B-Instruct:
    allowed_lora_adapters:
      - tenant-a-support
      - tenant-a-sales
```

This allows the policy gateway to reject an adapter before it reaches AIBrix/vLLM. It does not implement adapter signing, artifact scanning, tenant-specific storage controls, or lifecycle approval workflows.

## Metering model

The gateway emits one structured JSON event per request. The event includes:

- request ID,
- tenant ID,
- user ID,
- domain,
- model,
- adapter,
- allow/deny decision,
- status code,
- reason,
- latency,
- upstream status code when available,
- estimated token fields with source and billing-grade flags.

Token values are observability estimates, not customer billing data.

## Failure behavior

The gateway fails closed:

- missing tenant registry: `503 registry_unavailable`,
- unknown host/domain: `403 unknown_tenant`,
- missing/invalid token: `401`,
- tenant claim mismatch: `403 tenant_claim_mismatch`,
- unknown model: `403 unknown_model`,
- unknown adapter: `403 unknown_adapter`.

## MVP production-readiness boundary

This repository is production-inspired but not production-ready. A real platform needs durable metering, rate limiting, private networking, mTLS/service identity, GPU-aware autoscaling, adapter governance, and runtime isolation proof.

## Post-roast hardening layer

The gateway now has an additional hardening layer in front of the proxy step:

```text
parse request
  -> resolve tenant from Host
  -> validate auth
  -> enforce tenant/model/LoRA policy
  -> optionally enforce adapter catalog governance
  -> optionally enforce in-memory runtime quota
  -> strip spoofable headers
  -> inject trusted routing and isolation-intent headers
  -> proxy to AIBrix/vLLM
  -> optionally require upstream usage for billing ledger
  -> emit metering, audit, and metrics
```

New modules:

- `quota_enforcer.py`: per-process reference quota enforcement,
- `adapter_governance.py`: optional adapter catalog metadata enforcement,
- `billing_ledger.py`: JSONL reference ledger for `ledger_required` mode,
- `audit.py`: stdout/JSONL audit events,
- `security_posture.py`: audit/enforce checks for unsafe deployment posture,
- `slo_metrics.py`: Prometheus-text request/latency metrics.

These modules are intentionally small and replaceable. In a production platform,
quota, audit, billing, artifact governance, service identity, and autoscaling would
usually be external systems or controllers, not only in-process Python code.
