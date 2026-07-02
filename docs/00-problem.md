# 00 — Problem

Modern LLM SaaS platforms often want to serve many customers through shared or semi-shared inference infrastructure. AIBrix/vLLM can provide the model-serving substrate, but it should not be treated as the SaaS authorization boundary.

This repository focuses on the layer that sits **before** AIBrix/vLLM:

- mapping customer domains to tenants,
- validating OIDC/JWT tokens against the resolved tenant,
- preventing cross-tenant requests,
- enforcing model and LoRA adapter allowlists,
- stripping spoofable routing headers,
- injecting trusted internal routing metadata for AIBrix,
- enforcing reference quota controls,
- emitting structured audit, metering, and TTFT events,
- showing AWS/EKS deployment paths for both a cheap demo and an advanced GPU lab.

## Why this matters

A common mistake is to assume that putting an API gateway or reverse proxy in front of vLLM is enough for SaaS governance. It is not. A real multi-tenant platform needs identity validation, tenant-policy decisions, quota, audit, billing controls, model/adapter governance, and a network design that prevents direct bypass of the policy gateway.

## Scope boundary

This repo is intentionally a reference implementation. It demonstrates the governance seam and the AWS/EKS integration points. It does not certify production isolation, billing, compliance, or runtime safety.
