# AWS Danger Zone Audit Fixes

This document tracks concrete fixes added after a reviewer roast of the AWS full-stack DANGER ZONE path.

## Findings addressed

| Finding | Fix |
|---|---|
| Consent flag was pre-enabled in the example env file | Removed the default `yes`; operator must export it manually |
| Hardcoded Cognito password placeholder | `COGNITO_TEST_PASSWORD` is now required and default placeholders are rejected |
| Cognito tenant claim could become a mutable security boundary | `tenant_id` custom attribute is created immutable and existing mutable pools fail closed |
| Cognito app client did not explicitly restrict writable attributes | App client `WriteAttributes` excludes `custom:tenant_id`; validation fails if it is writable |
| Generated env/YAML files could be committed accidentally | Added `.gitignore` and `.dockerignore` coverage for `.aws-danger*` artifacts |
| GPU nodes used public networking by default | `AWS_DANGER_PRIVATE_NETWORKING=true` is now the default in the GPU eksctl template |
| Critical runtime install commands used fail-open `|| true` | Envoy, AIBrix, NVIDIA device plugin, GPU resource discovery, and vLLM rollout now fail fast |
| Remote manifests were applied directly | Scripts download manifests to `.aws-danger-manifests/` and support optional SHA256 verification |
| NLB annotations were under-specified | Service now includes NLB type, scheme, and legacy internal-LB fallback annotations |
| vLLM model cache used only `emptyDir` | Still default, but optional PVC mode is implemented for persistent model cache experiments |
| vLLM pod security posture was weak | Added seccomp profile, dropped capabilities, disabled privilege escalation, and added PDB |

## Still not solved

These fixes do not turn the path into production infrastructure:

- There is no full AWS landing zone.
- There is no automated AWS Load Balancer Controller IAM setup.
- There is no Karpenter GPU autoscaling.
- There is no verified KV-cache isolation proof.
- There is no enterprise IdP federation.
- There is no immutable billing ledger.
- There is no real LoRA artifact signature verification pipeline.

The value of this PR is that the demo is harder to misuse and fails earlier when the environment is unsafe or incomplete.
