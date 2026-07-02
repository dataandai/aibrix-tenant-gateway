# 14 — External Audit Brief

This page is written for external reviewers. The correct assessment target is a reference lab, not a production SaaS platform.

## System under review

1. **Local demo**: mock auth and mock upstream.
2. **CPU-only AWS demo**: EKS, ECR, LoadBalancer, mock upstream.
3. **Advanced AWS GPU full-stack path**: GPU EKS, AWS Load Balancer Controller, Cognito OIDC, Redis/ElastiCache quota reference, AIBrix/vLLM, S3 artifact buckets, S3/DynamoDB billing reference, Pod Identity/IRSA, and private networking evidence.

The Makefile target prefix `aws-danger-*` marks the advanced path as cost-bearing and quota-dependent.

## Implemented controls to review

- Tenant resolution from Host domain.
- OIDC/JWT tenant claim matching.
- Header stripping and trusted header injection.
- Model and LoRA adapter allowlists.
- OIDC hardening controls.
- Redis quota reference.
- Streaming billing gate and TTFT metrics.
- AWS-native billing reference with S3 Object Lock and DynamoDB idempotency.
- Pod Identity/IRSA reference path.
- Adapter verification evidence gate.
- NetworkPolicy and private networking evidence scripts.

## Explicit non-claims

- Not production-certified.
- Not billing-grade for all modes.
- Not a full AWS landing zone.
- Not proof of KV-cache isolation.
- Not complete adapter supply-chain enforcement.
- Not a managed service.

## Desired audit output

Please classify findings as:

- implemented reference control,
- runtime integration risk,
- production blocker,
- documentation/positioning issue.
