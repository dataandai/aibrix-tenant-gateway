# 05 — Limitations

This repository is a reference MVP, not a production platform. The purpose is to show the architectural seam where a SaaS governance layer can sit in front of AIBrix/vLLM, not to claim enterprise readiness.

## Header-based routing is not a security boundary

The gateway strips client-supplied routing headers and injects trusted headers after policy allow. That is the correct pattern, but it is not sufficient by itself.

If clients or untrusted workloads can reach AIBrix/vLLM directly, they can bypass this gateway entirely. Production deployments need private networking, strict ingress paths, NetworkPolicies, service identity, and preferably mTLS or equivalent workload identity between trusted components.

## Runtime rate limiting is not billing-grade metering

The MVP emits structured events and token estimates. It does not implement durable billing ledgers, invoice reconciliation, idempotent usage events, replay protection, quota settlement, or model-specific tokenizer version controls.

The code deliberately labels token values as non-billing-grade. These fields are useful for observability demos, not for charging customers.

## Mock JWT mode is not production authentication

Mock mode accepts local demo tokens such as `mock:tenant-a:user-123`. This is intentionally unsafe for production.

The application now rejects `APP_AUTH_MODE=mock` outside local/dev/test/ci environments by default. This guardrail reduces accidental misuse, but it is not a substitute for production identity controls.

## LoRA allowlist is not full adapter governance

The gateway checks whether an adapter name is allowed for a tenant/model pair. It does not verify:

- artifact provenance,
- artifact signatures,
- malware/security scanning,
- adapter owner approval,
- model/adapter compatibility,
- version pinning,
- rollback safety,
- storage isolation,
- adapter lifecycle audit.

A YAML allowlist is a policy demonstration, not a complete LoRA governance system.

## KV-cache isolation is not solved by this MVP

The gateway can tag and route requests, but it does not prove or enforce tenant-level KV-cache isolation in vLLM/AIBrix.

This document does not claim that data leakage exists. It claims only that this MVP does not prove the opposite. Production systems must evaluate runtime isolation mode, batching behavior, LoRA interaction, cache eviction, memory reuse, and noisy-neighbor failure modes.

## SLO autoscaling loop is not implemented

The MVP records latency and request metadata, but it does not implement autoscaling based on LLM-specific signals such as:

- TTFT,
- queue time,
- decode latency,
- GPU utilization,
- GPU memory pressure,
- adapter load latency,
- prefill/decode imbalance,
- tenant SLO tier.

Kubernetes CPU/RAM scaling is not enough for serious LLM serving.

## Runtime quota enforcement is not implemented

Tenant limits exist in YAML for reference, but the gateway does not enforce requests-per-minute, tokens-per-minute, concurrency, or budget controls.

A production SaaS layer would need quota state, distributed counters, rejection behavior, customer/tier policy, and operational dashboards.

## AWS manifests are reference examples, not a full enterprise landing zone

The Kubernetes and AWS/EKS files are intentionally small. They do not include complete implementations for:

- ALB controller setup,
- WAF,
- AWS account structure,
- IAM boundaries,
- Pod Identity/IRSA role policies,
- Karpenter GPU node pools,
- Secrets Manager/ASCP integration,
- CloudWatch/OpenTelemetry pipelines,
- private subnets and VPC endpoints,
- image scanning,
- SBOM/signing,
- disaster recovery.

## No production OIDC lifecycle

OIDC/JWKS mode validates tokens, but the repo does not implement issuer onboarding workflows, advanced JWKS caching policy, key rotation drills, token revocation semantics, tenant migration, or identity-provider outage playbooks.

## No prompt/data governance

The gateway does not classify prompt content, redact PII, enforce data residency, implement DLP, or route based on data sensitivity.

## No proof of AIBrix/vLLM runtime behavior

This repository does not load real models, run vLLM, validate AIBrix adapter routing, measure TTFT, or test GPU exhaustion. The mock upstream is a local development aid only.

## Post-roast hardening additions and remaining gaps

The repository now includes reference implementations for quota enforcement, adapter
catalog checks, audit events, billing-required mode, security posture checks, and
metrics. These reduce the original MVP gap, but they do not remove it completely.

| Area | Added | Remaining limitation |
|---|---|---|
| Runtime quota | Per-process in-memory quota enforcement | Not distributed; not safe as the only quota system in multi-pod production |
| Billing | `ledger_required` mode with required upstream usage and JSONL ledger | Not immutable, not reconciled, not invoice-grade, not externally durable |
| Adapter governance | Catalog metadata checks for status/checksum/signer/model compatibility | No cryptographic verification, no malware scan, no real artifact lifecycle controller |
| Audit | stdout/jsonl audit events | No tamper evidence, retention policy, SIEM export, or break-glass workflow |
| Security posture | audit/enforce startup/request blocking for unsafe posture | Heuristic only; does not replace cloud policy/compliance controls |
| KV-cache isolation | registry-level isolation intent and internal headers | Still no AIBrix/vLLM runtime proof |
| SLO metrics | request/latency/upstream status metrics | No TTFT, queue-depth, GPU-aware autoscaling controller |
| mTLS/private networking | example manifests/placeholders | Not validated end-to-end in a real EKS cluster |

The safest description remains: **production-inspired reference implementation, not
production-ready platform**.
