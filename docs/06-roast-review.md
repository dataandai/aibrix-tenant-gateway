# 06 — Roast Review

This is the intentionally harsh review of the MVP. It should be read before anyone presents this repository as production-ready.

## What would break in production?

- Mock auth would be catastrophic if accidentally enabled in a real environment.
- Token estimates would be rejected for billing or financial reporting.
- Header injection is useful but insufficient unless AIBrix is reachable only from trusted paths.
- AIBrix/vLLM runtime isolation and KV-cache behavior are not validated here.
- No runtime rate limiter prevents a noisy tenant from consuming shared GPU capacity.
- No SLO autoscaling loop reacts to TTFT, queue time, decode latency, or GPU pressure.
- No adapter artifact governance prevents a bad or incompatible LoRA adapter from being registered upstream.
- No chaos/load tests prove behavior under GPU exhaustion, upstream failures, or JWKS outages.
- ConfigMap-based tenant registry updates are operationally weak for a real SaaS control plane.

## What is fake?

- Mock upstream responses.
- Mock bearer tokens.
- Token accounting estimates.
- EKS manifests without full AWS infrastructure.
- LoRA adapter governance reduced to string allowlists.
- Tenant limits in YAML without enforcement.
- Local `.example.local` domains.

## What is only a demo?

- Local shell examples.
- `tenant-a.example.local` / `tenant-b.example.local` hostnames.
- ConfigMap-based registry management.
- Placeholder Secret.
- AIBrix Service stub.
- Optional tokenizer-based estimation without a durable ledger.
- Gateway-level policy checks without real model-pool tests.

## What would an enterprise reviewer reject?

- No formal IAM design.
- No private CA/mTLS design.
- No centralized policy store or approval workflow.
- No billing ledger.
- No quota enforcement.
- No incident/audit retention policy.
- No SAST/container scanning pipeline.
- No SBOM or supply-chain signing.
- No GPU quota/capacity planning.
- No tenant-specific key management.
- No comprehensive threat model for prompt/data leakage.
- No evidence that AIBrix/vLLM cache, batching, and LoRA loading are tenant-safe.

## Why this repo is still useful

It demonstrates the most important architectural seam:

```text
public client -> explicit SaaS policy gateway -> AIBrix/vLLM serving substrate
```

The useful pattern is:

1. resolve tenant from domain,
2. validate tenant from JWT,
3. fail closed,
4. strip spoofable headers,
5. enforce model and adapter allowlists,
6. inject only trusted routing headers,
7. emit structured audit/metering events,
8. keep production caveats explicit.

## Final roast

This repository is a strong reference demo, not a deployable SaaS LLM platform. The biggest danger is that someone sees FastAPI, Gateway API, OIDC/JWKS, and AIBrix in the same tree and assumes the hard parts are solved.

They are not.

The hard parts are billing-grade metering, quota enforcement, runtime isolation, adapter governance, GPU-aware autoscaling, private networking, service identity, and operational proof under load. This repo is where that discussion starts, not where it ends.

## Roast after hardening implementation

The second implementation pass is better, but still roastable.

- The quota enforcer is in-memory. It will fail open across replicas because each
  pod has its own counters. A real SaaS system needs a distributed quota backend.
- The JSONL billing ledger is a useful local control, but it is not immutable,
  replicated, reconciled, or invoice-grade.
- Adapter catalog enforcement checks metadata, not the actual artifact. A malicious
  or stale artifact could still exist behind a trusted-looking URI unless signing
  and scanning are enforced outside this app.
- Security posture enforcement blocks obvious bad settings, but it is not cloud
  compliance. It cannot prove private networking or mTLS by itself.
- KV-cache isolation is still only an intent signal. The gateway cannot prove vLLM
  cache isolation.
- `/metrics` exposes request and latency counters, but production LLMOps needs TTFT,
  queue time, decode latency, GPU memory pressure, adapter load latency, and model
  pool saturation.

Verdict: the repo now demonstrates the right extension points and some concrete
fail-closed controls, but it is still a reference architecture until backed by real
infrastructure, runtime tests, and external control planes.
