# 07 - Production Hardening Implementation Plan

This document turns the roast into an implementation roadmap. The repository now
contains a **reference implementation** for several hardening hooks, but it still
must not be described as a complete production platform.

## Multi-agent decision record

### Principal LLMOps Architect

The gateway can enforce tenant/model/adapter policy and emit routing metadata, but
it cannot prove vLLM/AIBrix runtime isolation by itself. KV-cache isolation must be
validated at the serving runtime and model-pool level. The gateway now forwards
explicit internal isolation intent headers, but those headers are not proof.

### AWS EKS Architect

The EKS layer needs private upstream access, least-privilege identity, private
networking, and audit export. The repo now includes service-mesh/mTLS and private
networking placeholders, but those are not a complete EKS landing zone.

### Kubernetes / Gateway API Engineer

The manifests stay minimal and readable. Hardening examples are additive: NetworkPolicy,
service account annotations, service mesh placeholders, and security context.

### Security Architect

The gateway now has security posture evaluation. In `enforce` mode, production-like
misconfigurations can block readiness and request handling. Mock auth remains local-only.

### Backend Engineer

The app now has separate modules for quota, adapter governance, audit, billing ledger,
security posture, and SLO-style metrics. These are deliberately small and testable.

### LLMOps Observability Engineer

The system now emits structured metering, audit events, and Prometheus-text metrics.
Billing ledger mode requires upstream usage fields before returning success.

### Self-Roasting Reviewer

In-memory quota is not distributed. JSONL audit is not immutable. The billing ledger
is only a reference ledger. mTLS manifests are placeholders. KV-cache isolation is
still not proven. This is improved, not production-complete.

## Implementation phases

## Phase 1: Implemented in this repo

| Area | Implemented reference capability | Still missing for production |
|---|---|---|
| Auth hardening | Mock auth guardrail, OIDC/JWKS validation path, security posture checks | OIDC discovery lifecycle, JWKS cache tuning, revocation, IdP integration tests |
| Billing-grade metering | `ledger_required` mode that requires upstream usage tokens and writes idempotent JSONL records | External durable ledger, reconciliation, tamper evidence, invoice pipeline |
| Runtime quota enforcement | Per-process in-memory request/input-token quota | Distributed quota backend such as Redis/Envoy Ratelimit/global cell-aware quotas |
| Adapter governance | Optional catalog enforcement: URI, checksum, status, signer, compatible models | Artifact signing verification, malware scanning, provenance attestation, lifecycle automation |
| KV-cache isolation | Tenant runtime isolation intent in registry and trusted internal headers | Runtime-level proof in AIBrix/vLLM, load tests, cross-tenant isolation validation |
| mTLS/private networking | NetworkPolicy and service-mesh placeholder manifests | Enforced mesh identity, certificates, policy tests, private ALB/NLB/VPC endpoints |
| SLO autoscaling | `/metrics` Prometheus-text counters and latency sums | TTFT/queue depth/GPU-aware autoscaling controller |
| Audit pipeline | stdout or JSONL audit sink | Immutable storage, SIEM export, retention, tamper evidence, break-glass controls |

## Phase 2: Next realistic engineering step

1. Replace `InMemoryQuotaEnforcer` with a distributed quota backend.
2. Replace JSONL audit and billing files with external append-only storage.
3. Add model-specific tokenizer/version registry.
4. Add signed adapter artifact verification before adapter activation.
5. Add OpenTelemetry traces and metrics export.
6. Add service-mesh identity and deny direct-to-AIBrix traffic in integration tests.
7. Add AIBrix/vLLM runtime tests for adapter routing and cache behavior.
8. Add Karpenter GPU node pools and SLO-driven scaling experiments.

## Phase 3: Enterprise readiness requirements

Before calling this a platform, require:

- production IdP onboarding runbooks,
- tenant lifecycle management,
- durable billing ledger and reconciliation,
- distributed rate limits and quota enforcement,
- signed/scanned adapter lifecycle,
- mTLS/service identity and private networking enforcement,
- KV-cache isolation evidence,
- incident/audit retention policy,
- CI/CD with SBOM, image scanning, and deployment gates,
- load and chaos testing against real AIBrix/vLLM pools.
