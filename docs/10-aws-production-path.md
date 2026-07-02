# AWS Production Path

The AWS demo is intentionally easy to run. A production deployment should be different.

## Phase 1: Demo deployment

- EKS managed CPU nodes.
- Public LoadBalancer Service.
- Mock auth.
- Mock upstream.
- In-memory quota.
- Observability-mode billing.
- Stdout audit.

Purpose: reviewer can run curl tests and inspect logs.

## Phase 2: Production-like staging

- Private AIBrix upstream Service.
- Real OIDC/JWKS auth.
- `APP_SECURITY_POSTURE_MODE=enforce`.
- `APP_MOCK_UPSTREAM=false`.
- `APP_REQUIRE_PRIVATE_UPSTREAM=true`.
- JSONL or external audit sink.
- Ledger-required billing mode.
- Internal ALB or Gateway API controller.
- NetworkPolicy blocking all direct AIBrix access except from the gateway.

Purpose: validate governance controls before real tenants.

## Phase 3: Production platform work

- Private subnets for worker nodes.
- Controlled ingress through ALB, API Gateway, CloudFront, or VPC Lattice depending on enterprise constraints.
- TLS termination and cert lifecycle.
- mTLS/service identity between gateway and AIBrix.
- Redis/Envoy global rate limiting.
- Durable billing ledger, ideally Postgres/Kafka/S3 Object Lock style architecture.
- OpenTelemetry collector and SIEM export.
- EKS Pod Identity or IRSA for AWS access.
- Secrets Manager + ASCP for OIDC/client secrets.
- ECR image scanning, SBOM, signing, and admission policy.
- GPU node pools with Karpenter or managed node groups.
- AIBrix/vLLM deployment with real models and explicit LoRA/KV-cache isolation validation.

## Minimal production acceptance checklist

A real buyer or enterprise reviewer should ask for evidence of:

- OIDC issuer/audience/key rotation tests.
- No public route to AIBrix/vLLM.
- Header spoofing cannot change tenant routing.
- Cross-tenant requests fail closed.
- Quota is distributed across gateway replicas.
- Usage events are durable and idempotent.
- Billing reconciliation exists.
- Adapter artifacts are signed or otherwise validated.
- Runtime cache isolation has been tested.
- Load tests include TTFT, queue time, and streaming behavior.
- Logs do not contain bearer tokens.
- Destroy/runbook procedures exist.

## Why this repository now includes both demo and hardening modes

A repository that is only production-theory is hard to evaluate. A repository that is only a local mock is easy to dismiss.

The intended reviewer flow is:

1. Run locally.
2. Deploy the AWS demo.
3. Inspect policy and audit logs.
4. Read the production-hardening docs.
5. Decide which production integrations to replace first: auth, quota, billing, networking, AIBrix runtime, or observability.
