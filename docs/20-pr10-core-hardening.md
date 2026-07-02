# 20 — PR10 Core Hardening Notes

PR10 updates the gateway internals behind the earlier audit-remediation work. The goal is to remove several reference-level shortcuts that would fail under real SaaS load or security review.

This does not certify the system as production-ready. It upgrades the implementation patterns used by the core modules.

## PR10-1: Redis sliding-window quota

Updated file:

```text
src/tenant_policy_gateway/quota_enforcer.py
```

Implemented:

- Redis ZSET-based sliding-window rate limiting instead of fixed buckets.
- Millisecond timestamp scoring.
- User-level and tenant-level request limits.
- User-level and tenant-level input-token limits.
- Request-id based concurrency tracking.
- Stale concurrency cleanup using TTL/cutoff logic.
- `finish_request()` removes the exact request member when a request completes.
- Backward-compatible safety removal remains for older call sites that do not pass a request ID.

Why it matters: fixed-window counters can allow boundary bursts at minute edges. Anonymous concurrency counters can leak if a pod crashes. PR10 moves quota toward a stricter distributed control pattern.

Remaining gaps:

- Redis HA/failover policy is not proven.
- Regional quota consistency is not solved.
- Output-token quota and cost-budget enforcement remain outside the pre-forward quota check.
- A real deployment still needs Redis/ElastiCache integration tests under failure conditions.

## PR10-2: Deterministic tokenizer startup

Updated file:

```text
src/tenant_policy_gateway/metering.py
```

Implemented:

- Removed the loose `len(text) // 4` fallback from production-like quota paths.
- Added startup tokenizer initialization through the FastAPI lifespan.
- Supported tokenizer modes:
  - `tiktoken`
  - `hf_local`
  - `utf8_bytes` for local/demo safety only
- Production-like quota enforcement fails fast if a real tokenizer cannot be initialized.
- Multimodal/chat content extraction now handles structured content deterministically instead of lazily dumping arbitrary objects.

Why it matters: undercounting input tokens before forwarding can leak GPU capacity and weaken quota enforcement. A production-like gateway should fail closed when it cannot produce the quota estimate it depends on.

Remaining gaps:

- Tokenizer artifact signing/pinning is not implemented.
- Token estimates are still not a billing-grade source of truth.
- Model-specific tokenizer selection needs explicit policy when several model families are served.

## PR10-3: Memory-bounded batched billing ledger

Updated file:

```text
src/tenant_policy_gateway/billing_ledger.py
```

Implemented:

- Replaced per-request S3 object writes with a memory-bounded batching buffer.
- Flushes batches periodically or when the batch reaches the configured record count.
- Writes JSONL batches under partitioned S3 prefixes such as:

```text
billing-ledger/tenant_id=tenant-a/year=2026/month=07/day=02/hour=16/batch_ts=...jsonl
```

- Uses a bounded LRU request-id cache instead of an unbounded in-memory set.
- Supports DynamoDB idempotency claims in AWS-native reference mode.
- Flushes on shutdown.
- Fails closed when the billing queue is full in required ledger modes.

Why it matters: one S3 PUT per request is too expensive and latency-sensitive at high RPS. An unbounded `_seen_request_ids` set is a memory leak. PR10 fixes both reference-level flaws.

Remaining gaps:

- This is still not a full invoicing or reconciliation system.
- Streaming usage extraction remains blocked in billing-required modes.
- Delivery guarantees depend on the configured queue, worker, S3, and DynamoDB behavior under failure.

## PR10-4: Strict request schema and canonical adapter field

Updated file:

```text
src/tenant_policy_gateway/policy_engine.py
```

Implemented:

- Strict Pydantic models for `/v1/chat/completions` and `/v1/completions`.
- `extra="forbid"` semantics for request bodies and nested content models.
- Unknown or vendor-specific fields fail closed with `400 invalid_request_schema`.
- The only accepted adapter instruction is the canonical `lora_adapter` field.
- Legacy aliases such as `adapter`, `lora`, and `metadata.adapter` are rejected rather than guessed.
- The normalized request body is forwarded downstream, not the original unvalidated body.

Why it matters: a policy engine cannot allowlist an adapter it does not see. Loose adapter scavenging can miss hidden vendor-specific fields that the upstream serving layer might still understand. Strict schema enforcement ensures the forwarded request matches the policy decision.

Remaining gaps:

- The gateway intentionally supports only its modeled API contract.
- New OpenAI/vLLM/AIBrix request fields must be intentionally added to the schema and policy review process before forwarding.
- Schema validation does not replace downstream runtime isolation or adapter artifact enforcement.

## Updated positioning after PR10

A precise statement is:

```text
The core gateway internals have been hardened from reference-level shortcuts toward production-grade implementation patterns.
```

A misleading statement would be:

```text
The repository is now a production-certified SaaS LLM platform.
```

The latter remains false without live AWS integration evidence, Redis failure-mode tests, tokenizer artifact supply-chain controls, AIBrix/vLLM load tests, billing reconciliation, and KV-cache/runtime-isolation proof.
