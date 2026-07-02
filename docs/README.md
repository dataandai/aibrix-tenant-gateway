# Documentation Map

This documentation is written for reviewers who want to understand what the repository actually proves, what it only demonstrates, and what remains outside the scope of the reference implementation.

## Recommended reading order

1. [00 — Problem](00-problem.md)
2. [01 — Architecture](01-architecture.md)
3. [02 — Threat Model](02-threat-model.md)
4. [03 — Tenant Isolation Modes](03-tenant-isolation-modes.md)
5. [09 — CPU-only AWS Demo Runbook](09-aws-demo-runbook.md)
6. [11 — Advanced AWS GPU Full-Stack Path](11-aws-full-stack-danger-zone.md)
7. [15 — Security Controls Matrix](15-security-controls-matrix.md)
8. [16 — Known Production Blockers](16-known-production-blockers.md)
9. [19 — PR9 Audit Remediation](19-pr9-audit-remediation.md)
10. [20 — PR10 Core Hardening](20-pr10-core-hardening.md)

## Three deployment paths

| Path | Purpose | Cost/risk | Production claim |
|---|---|---:|---|
| Local demo | Fast policy-flow validation without cloud resources | Low | No |
| CPU-only AWS demo | Reviewer-friendly EKS deployment with mock upstream | Medium | No |
| Advanced AWS GPU full-stack path | Optional AIBrix/vLLM/GPU lab with real AWS resources | High | No |

The Makefile target prefix `aws-danger-*` is intentionally kept for the advanced GPU path. It is not a product name. It is a warning label: those commands may create paid AWS resources and may fail if GPU quota, networking, IAM, or regional capacity is not ready.

## What this documentation does not claim

The repository is not a production-certified SaaS LLM platform. It is an audit-hardened reference lab that shows how tenant governance can be implemented in front of AIBrix/vLLM, and where production systems still need deeper controls.

## Latest core-hardening note

PR10 hardened the runtime internals that earlier audit passes identified as risky: Redis quota is now sliding-window based, tokenizer estimation fails closed in production-like quota modes, the billing ledger batches writes instead of writing one S3 object per request, and the request body contract is strict Pydantic rather than loose field scavenging. See [20 — PR10 Core Hardening](20-pr10-core-hardening.md).
