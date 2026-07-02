# Remaining Gaps After the AWS Full-Stack Danger Zone

The danger-zone path is runnable infrastructure scaffolding, not a production guarantee.

## Auth

Implemented:

- Cognito user pool.
- OIDC issuer and JWKS URL.
- Tenant claim validation using `custom:tenant_id`.
- `custom:tenant_id` created immutable for the demo pool.
- App client `WriteAttributes` excludes `custom:tenant_id`.
- Existing mutable tenant-claim pools fail closed.

Still missing:

- Enterprise federation.
- Conditional access policy.
- JWKS cache hardening and rotation tests.
- Automated IdP lifecycle management.
- Scope/role/entitlement enforcement beyond tenant claim.

## GPU and model serving

Implemented:

- GPU node group.
- NVIDIA device plugin install as a fail-fast step unless explicitly skipped.
- vLLM GPU Deployment with AIBrix labels.
- AIBrix stable manifest install.

Still missing:

- GPU capacity planning.
- Karpenter GPU node pools.
- Model warm cache by default; optional PVC cache mode is available but not provisioned automatically.
- Multi-replica load tests.
- TTFT and queue-depth autoscaling loop.
- Verified KV-cache isolation.

## Model registry and LoRA artifacts

Implemented:

- S3 model registry bucket.
- S3 LoRA artifact bucket.
- Tenant registry references to adapter artifact URIs.

Still missing:

- Real adapter upload pipeline.
- SHA verification against downloaded artifacts.
- KMS signature verification.
- Security scanning.
- Rollback and lifecycle workflows.

## Networking

Implemented:

- Tenant gateway calls an internal Kubernetes DNS name for AIBrix Envoy.
- The full-stack gateway LoadBalancer defaults to internal.
- GPU node groups default to private networking.
- Service annotations include NLB type/scheme and legacy internal-LB fallback.

Still missing:

- Fully private EKS control plane and complete VPC endpoint set.
- VPC endpoint set.
- mTLS between gateway and AIBrix.
- Service mesh policy validation.
- Egress controls for Hugging Face/model downloads.

## Billing and audit

Implemented:

- Structured gateway audit/metering events.
- Reference ledger mode still available.

Still missing:

- Durable central ledger.
- Reconciliation job.
- Immutable audit storage.
- SIEM export.
- Usage-based invoice pipeline.

## Self-roast

An enterprise reviewer could still reject this because it proves deployment wiring, not operational maturity. The danger-zone path is valuable because it can run real components, but it does not prove that those components are safe, scalable, isolated, or cost-controlled under real tenant load.
