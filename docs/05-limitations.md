# 05 — Limitations

This repository is an audit-hardened reference lab, not a production platform. It demonstrates how a SaaS governance layer can sit in front of AIBrix/vLLM, but it does not certify the full stack for enterprise workloads.

## Header-based routing is not a security boundary

The gateway strips client-supplied routing headers and injects trusted headers after policy allow. That is the correct pattern, but it is not enough by itself.

If untrusted clients or workloads can reach AIBrix/vLLM directly, they can bypass the gateway entirely. Production deployments need private networking, strict ingress paths, NetworkPolicies, service identity, and preferably mTLS or equivalent workload identity between trusted components.

## Mock JWT mode is not production authentication

Mock mode accepts local demo tokens such as `mock:tenant-a:user-123`. The app rejects mock auth outside local/dev/test/ci by default unless an explicitly unsafe override is set. This is a guardrail, not authentication.

## OIDC integration is a reference, not an identity product

OIDC/JWKS mode validates issuer, audience, signature, temporal claims, tenant claim, and optional `token_use`, scopes, and groups. It does not provide enterprise IdP federation lifecycle, tenant onboarding, tenant migration, token revocation semantics, break-glass access, MFA policy, or conditional access.

## Quota enforcement is a reference control

The repo includes local in-memory quota for demos and Redis-backed quota for the advanced AWS path. Redis mode now uses ZSET-based sliding-window Lua scripts with request-id concurrency tracking and stale-entry TTL cleanup. This removes the fixed-window burst issue and anonymous concurrency-counter leak from earlier reference versions.

It is still not a complete quota platform. Remaining gaps include Redis HA/failover policy, regional consistency, output-token quota before billing reconciliation, cost-budget enforcement, customer/tier policy lifecycle, reconciliation, and operational dashboards.

## Billing reference is not billing-grade commerce infrastructure

The gateway supports observability mode, local ledger-required mode, and AWS-native reference ledger mode using S3 Object Lock and DynamoDB idempotency. Billing records are queued in a memory-bounded buffer and flushed as batched JSONL objects rather than one S3 PUT per request. Immediate replay protection uses a bounded LRU, not an unbounded in-memory set.

This is useful audit evidence and a better cost profile than per-request S3 writes. It is still not a complete billing system. It does not include invoice reconciliation, dispute workflows, refunds, pricing plans, tax handling, customer contracts, financial controls, or billing-grade streaming usage extraction.

## Streaming billing is intentionally fail-closed

The streaming path can emit TTFT metrics and proxy SSE-style responses. In billing-required modes, streaming is blocked by default because the reference implementation does not yet extract final billing-grade usage from stream responses.

This is a deliberate safety choice.

## Request schema hardening does not replace complete API governance

The gateway now rejects unknown request fields through strict Pydantic request contracts and only accepts the canonical `lora_adapter` field for adapter selection. This closes the hidden-vendor-field adapter bypass class that existed in earlier reference versions.

However, this also means the gateway supports only the explicit OpenAI-compatible subset it models. New upstream API parameters must be intentionally added to the schema and policy contract before being forwarded.

## LoRA allowlist and artifact checks are not full adapter governance

The repo includes model/adapter allowlists, adapter catalog metadata, and SHA256 artifact verification utilities. It does not yet enforce cryptographic signatures through KMS/cosign, malware scanning, admission-control policy, quarantine workflows, version rollback, or full adapter lifecycle approval.

## KV-cache isolation is not proven

The gateway can express isolation intent through tenant config and internal headers, but it cannot prove or enforce vLLM/AIBrix KV-cache isolation.

This document does not claim that data leakage exists. It claims only that this repository does not prove the opposite. Production systems must test runtime isolation mode, batching behavior, LoRA interaction, cache eviction, memory reuse, and noisy-neighbor behavior.

## SLO autoscaling loop is not implemented

The repo exposes latency and TTFT-style metrics. It does not implement autoscaling based on LLM-specific signals such as queue time, prefill latency, decode latency, GPU memory pressure, adapter load latency, or tenant SLO tier.

## AWS manifests and scripts are not a full enterprise landing zone

The AWS/EKS files are practical reference paths. They do not include AWS Organizations, SCPs, centralized logging accounts, GuardDuty/Security Hub integration, full VPC endpoint strategy, complete egress lockdown, WAF/Shield, production TLS lifecycle, disaster recovery, or compliance evidence.

## No prompt/data governance

The gateway does not classify prompt content, redact PII, enforce data residency, implement DLP, or route requests based on data sensitivity.

## No production load-test evidence

The repository contains tests for application logic and static deployment assets. It does not include live GPU load tests proving TTFT, queue depth, cache behavior, model cold-start behavior, or noisy-neighbor isolation under real tenant load.

## Summary matrix

| Area | Implemented reference control | Remaining limitation |
|---|---|---|
| Auth | mock guardrail + OIDC/JWKS validation | not full IdP lifecycle |
| Tenant policy | domain + tenant claim + strict schema + model/adapter allowlists | depends on trusted ingress and upstream isolation |
| Quota | local in-memory + Redis ZSET sliding-window reference | not full quota business system |
| Billing | batched JSONL + S3 Object Lock/DynamoDB reference | not invoice-grade or streaming-complete |
| Streaming | proxy + TTFT metrics | billing-required streaming is blocked, not solved |
| Adapter governance | allowlist + catalog + SHA256 verification utility | no cryptographic runtime enforcement |
| AWS | EKS/LBC/Pod Identity/Redis/S3/DynamoDB reference | not a full landing zone |
| Runtime isolation | isolation intent headers | no KV-cache proof |
