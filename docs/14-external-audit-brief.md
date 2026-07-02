# External Audit Brief

This document is the evidence pack entry point for AWS-certified security, authorization, and LLMOps reviewers.

## Audit posture

The repository has two AWS paths:

1. **Cheap AWS demo**: CPU-only, mock auth, mock upstream, low-friction reviewer demo.
2. **AWS Full-Stack DANGER ZONE**: GPU EKS, Cognito OIDC, Redis/ElastiCache quota reference, AIBrix/vLLM, internal NLB, S3 artifact buckets, AWS-native billing reference.

The full-stack path is still not a production-certified SaaS LLM platform. It is a deployable reference implementation with explicit warnings and guardrails.

## Implemented hardening after external-audit simulation

- AWS Load Balancer Controller bootstrap with IAM policy and service account binding.
- NLB scheme verification after gateway deployment.
- Redis/ElastiCache reference quota backend; full-stack deploy refuses in-memory quota.
- OIDC claim hardening: `token_use`, `nbf`, leeway, scopes, groups, and JWKS client cache.
- Supply-chain reference controls: pinned requirements, SBOM workflow, Trivy workflow, container workflow, Cosign signing note.
- Private networking evidence script: node ExternalIP check, NLB scheme check, VPC endpoint inventory.
- Streaming proxy path with TTFT metrics and stream token hints.
- Adapter artifact SHA256 verifier for local and S3 artifacts.
- AWS-native billing reference using S3 Object Lock bucket and per-request ledger objects.

## What auditors should not accept as solved

- KV-cache isolation is not proven.
- Adapter signature verification is metadata-only unless extended with KMS/cosign.
- Redis quota is reference-grade; production needs operational HA, alerts, and failure policy.
- S3 Object Lock billing is a reference ledger, not a full reconciliation platform.
- Private networking evidence is a script, not a complete enterprise landing zone proof.
- The full-stack path requires AWS quota, manual environment choices, and destructive cleanup discipline.
