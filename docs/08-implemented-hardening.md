# 08 - Implemented Hardening Reference

This document describes what was added after the production roast.

## Security posture enforcement

`APP_SECURITY_POSTURE_MODE` supports:

- `audit`: emit findings but do not block traffic,
- `enforce`: block readiness and requests when critical/high findings are present.

Production-like environments are checked for risky settings such as mock upstream,
disabled quota, disabled billing, disabled audit, and non-private upstreams.

## Runtime quota enforcement

`APP_QUOTA_MODE=in_memory` enables a per-process sliding-window quota enforcer using
tenant limits from the registry:

```yaml
limits:
  requests_per_minute: 60
  input_tokens_per_minute: 100000
```

This demonstrates where quota belongs in the request path. It is not distributed
and therefore not production-grade for multi-pod deployments.

## Adapter governance catalog

`APP_ADAPTER_GOVERNANCE_MODE=catalog_enforced` requires requested adapters to exist
in the tenant adapter catalog and be:

- `active`,
- compatible with the requested model,
- associated with a checksum,
- associated with a signer identity.

Example:

```yaml
adapter_artifacts:
  tenant-a-support:
    artifact_uri: s3://example-lora-artifacts/tenant-a/support/v1/adapter.safetensors
    sha256: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
    signed_by: kms-key-alias/aibrix-lora-signing
    status: active
    compatible_models:
      - meta-llama/Llama-3.1-8B-Instruct
```

This is still metadata validation, not real artifact signing verification.

## Billing ledger required mode

`APP_BILLING_MODE=ledger_required` requires the upstream response to include:

```json
{
  "usage": {
    "prompt_tokens": 1,
    "completion_tokens": 1,
    "total_tokens": 2
  }
}
```

If usage is missing or inconsistent, the gateway returns `502 billing_usage_missing`.
If usage is valid, the gateway appends a JSONL reference ledger entry.

This is a useful request-path guardrail, but still not an enterprise billing system.

## Audit sink

`APP_AUDIT_SINK` supports:

- `disabled`,
- `stdout`,
- `jsonl`.

Audit events include tenant, user, model, adapter, decision, auth mode, quota mode,
adapter governance mode, billing mode, and the explicit claim that the gateway is
not the downstream security boundary.

## SLO metrics endpoint

`GET /metrics` exposes Prometheus-text reference metrics:

- request totals by tenant/decision/reason,
- latency sum/count,
- upstream status totals.

This is not TTFT/queue-depth/GPU-aware autoscaling yet. It is the first metrics
surface needed before wiring a real autoscaling loop.

## KV-cache isolation intent

The tenant registry now supports:

```yaml
runtime_isolation:
  mode: shared_pool_reference
  kv_cache_isolation_required: true
  kv_cache_isolation_proven: false
  evidence: null
```

The gateway forwards internal isolation intent headers. This is not proof of
runtime isolation. Real proof must come from AIBrix/vLLM configuration and tests.
