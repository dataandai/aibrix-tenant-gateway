# 10 — From Reference Lab to Production AWS Design

This document describes what an organization would need to add before treating the architecture as a production AWS platform.

## Current repository level

The repository provides:

- a local demo,
- a CPU-only AWS demo,
- an optional advanced GPU full-stack AWS path,
- tenant-policy gateway code,
- OIDC/JWKS validation,
- Redis quota reference,
- S3/DynamoDB billing reference,
- AIBrix/vLLM deployment templates,
- audit and metering hooks.

This is not enough for production certification.

## Production AWS requirements

### Account and governance

- AWS Organizations and account boundaries.
- SCPs and permission boundaries.
- Centralized security/audit accounts.
- IAM access review and break-glass process.

### Network

- Private subnets for workloads.
- Private EKS API endpoint strategy.
- VPC endpoints for ECR, S3, STS, CloudWatch Logs, Secrets Manager, and required AWS APIs.
- Controlled NAT or egress proxy for services without endpoints.
- WAF/Shield/TLS/certificate lifecycle where public ingress exists.
- Flow logs and network evidence retention.

### Identity

- Enterprise IdP federation.
- Tenant claim source-of-truth process.
- Access-token vs ID-token authorization decision.
- MFA/conditional-access policy.
- Token revocation and key-rotation playbooks.

### LLMOps runtime

- GPU node autoscaling through Karpenter or equivalent.
- Model cache strategy.
- Model registry as runtime source of truth.
- Adapter signing, scanning, quarantine, and admission controls.
- KV-cache and batching isolation proof.
- Load tests for TTFT, queue depth, decode latency, and noisy-neighbor behavior.

### Billing and audit

- Billing-grade usage extraction.
- Streaming usage accounting or explicit product decision to disallow streaming for billable workloads.
- Reconciliation jobs.
- Immutable audit retention.
- SIEM integration.
- Customer dispute workflow.

## Production decision gate

A buyer or enterprise reviewer should ask for evidence, not only architecture diagrams. Evidence should include live AWS deployment logs, security group/NLB proofs, IAM policy review, VPC endpoint inventory, OIDC claim tests, quota behavior tests, billing idempotency tests, and GPU load-test reports.
