# 13 — Advanced Path Audit Fixes

This document records the concrete fixes made after the first AWS-specific review of the advanced GPU path.

The Makefile still uses `aws-danger-*` target names as a warning label. In user-facing prose, this path is called the **advanced AWS GPU full-stack path**.

## Fixed findings

| Finding | Fix |
|---|---|
| Cost consent was pre-accepted in the example env | Example env now leaves `I_UNDERSTAND_AWS_GPU_COST_AND_QUOTAS` empty |
| Cognito tenant claim could become a security risk | `custom:tenant_id` is immutable and excluded from app client write attributes |
| Default Cognito test password could be reused | bootstrap script rejects missing/default-like passwords |
| Generated env/YAML files could be committed | `.gitignore` and `.dockerignore` cover `.aws-danger*` artifacts |
| Critical install steps were fail-open | Envoy, AIBrix, NVIDIA, GPU resource, and vLLM rollout checks fail fast |
| Remote manifests were applied directly | scripts download manifests locally and support checksum verification |
| GPU nodes were not clearly private by default | GPU node group defaults to private networking |
| Model cache was always ephemeral | optional PVC-backed cache mode was added |
| LoadBalancer behavior was under-specified | AWS Load Balancer Controller install and NLB verification were added |
| Gateway AWS API calls lacked identity path | Pod Identity/IRSA bootstrap was added |
| Adapter verification was manual only | deploy-time evidence gate was added |

## Remaining findings

- No complete private AWS landing zone.
- No cryptographic runtime adapter signature enforcement.
- No billing reconciliation system.
- No KV-cache isolation proof.
- No GPU load-test evidence.
- No production IdP federation lifecycle.
