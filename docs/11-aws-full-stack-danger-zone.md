# AWS Full-Stack DANGER ZONE Runbook

This path is intentionally separate from the cheap AWS demo.

Use it only when you explicitly want to try a **real GPU-backed AIBrix/vLLM path** on AWS EKS and you accept the cost, quota, model-download, OIDC, private-networking, and cleanup responsibility.

## What this path attempts to create

- An EKS cluster with:
  - CPU managed node group for system/gateway pods.
  - GPU managed node group for vLLM inference pods.
- Amazon ECR repository and gateway image.
- Amazon Cognito user pool and app client used as a real OIDC issuer.
- Two Cognito test users:
  - `tenant-a-alice` with `custom:tenant_id=tenant-a`.
  - `tenant-b-bob` with `custom:tenant_id=tenant-b`.
- S3 model registry bucket.
- S3 LoRA artifact bucket.
- Envoy Gateway.
- AIBrix stable release components.
- NVIDIA device plugin manifest.
- A GPU vLLM OpenAI-compatible model Deployment with AIBrix model labels.
- Tenant Policy Gateway in OIDC mode.
- Tenant registry rendered from Cognito/S3/model values.
- Gateway upstream pointed to the internal AIBrix Envoy service.
- A full-stack smoke test using real Cognito ID tokens.

## Hard warnings

This path can create real AWS charges. EKS control plane, EC2 GPU nodes, EBS volumes, LoadBalancers, NAT/data transfer depending on your VPC behavior, ECR, S3, and Cognito can all cost money.

This path can fail for normal cloud reasons:

- Your account may not have GPU service quota.
- The selected region may not have GPU capacity.
- The selected model may not fit the selected GPU.
- A gated Hugging Face model may require `HF_TOKEN`.
- Model download can be large and slow.
- AIBrix upstream service names can change across releases.
- The reference NetworkPolicy may need adaptation to your CNI/network-policy engine.
- The path is not a production landing zone.

## Sources and version assumptions

The scripts default to AIBrix `v0.7.0` because the AIBrix installation documentation shows stable manifests for `aibrix-dependency-v0.7.0.yaml`, `aibrix-core-crds-v0.7.0.yaml`, and `aibrix-core-v0.7.0.yaml`. The AIBrix quickstart also shows a GPU vLLM Deployment shape with `model.aibrix.ai/name`, `model.aibrix.ai/port`, and `model.aibrix.ai/engine` labels.

If upstream AIBrix changes, pin or update these variables:

```bash
export AIBRIX_VERSION=v0.7.0
export VLLM_IMAGE=vllm/vllm-openai:v0.11.0
export MODEL_ID=deepseek-ai/DeepSeek-R1-Distill-Llama-8B
export SERVED_MODEL_NAME=deepseek-r1-distill-llama-8b
```

## Consent gate

The scripts refuse to run unless you explicitly export:

```bash
export I_UNDERSTAND_AWS_GPU_COST_AND_QUOTAS=yes
```

That variable exists to stop accidental GPU cluster creation.

## Recommended setup

Copy the example env file and edit it:

```bash
cp infra/aws/full-stack/full-stack.env.example .aws-danger.env
vim .aws-danger.env
source .aws-danger.env
```

At minimum, check:

```bash
AWS_REGION
CLUSTER_NAME
GPU_INSTANCE_TYPE
MODEL_ID
SERVED_MODEL_NAME
AWS_FULL_GATEWAY_SCHEME
```

For gated/private Hugging Face models:

```bash
export HF_TOKEN=hf_...
```

## Full path

```bash
export I_UNDERSTAND_AWS_GPU_COST_AND_QUOTAS=yes
export AWS_REGION=eu-west-1
export CLUSTER_NAME=aibrix-gateway-full-stack

make aws-danger-create-gpu-cluster
make aws-danger-oidc
make aws-danger-artifacts
make aws-danger-install-lbc
make aws-danger-install-aibrix
make aws-danger-redis-quota
make aws-danger-billing-ledger
make aws-danger-pod-identity
make aws-danger-verify-adapters
make aws-danger-deploy
make aws-danger-verify-private
make aws-danger-smoke
```

Logs:

```bash
make aws-danger-logs
```

Destroy the EKS cluster:

```bash
make aws-danger-destroy
```

Delete optional persistent resources too:

```bash
DELETE_ECR_REPOSITORY=true \
DELETE_COGNITO_USER_POOL=true \
DELETE_ARTIFACT_BUCKETS=true \
make aws-danger-destroy
```

## Why the gateway defaults to internal LoadBalancer here

The cheap AWS demo exposes a public LoadBalancer for reviewer convenience.

The full-stack path defaults to:

```bash
AWS_FULL_GATEWAY_SCHEME=internal
```

The smoke test then uses `kubectl port-forward` to reach the Tenant Policy Gateway.

This keeps the AIBrix/vLLM path private by default. You can set:

```bash
export AWS_FULL_GATEWAY_SCHEME=internet-facing
```

but that is for throwaway experiments only.

## What is implemented vs still reference-only

| Area | Implemented in this path | Still not production |
|---|---|---|
| GPU quota | GPU node group manifest and script | Quota/capacity must exist in your account |
| Large model download | vLLM Deployment pulls a configurable HF model | No pre-warmed model cache or artifact mirroring |
| AIBrix/vLLM | Installs Envoy Gateway + AIBrix stable manifests + vLLM Deployment | Does not cover every AIBrix production topology |
| Model registry | S3 bucket and `models.json` reference registry | Not a full model lifecycle system |
| LoRA artifact storage | S3 bucket and tenant registry references | Does not upload or verify real adapter artifacts |
| OIDC provider | Cognito user pool/client/users and real ID tokens | Not enterprise IdP federation or lifecycle |
| Private networking | Internal AIBrix upstream and internal gateway default | Not a full private VPC/endpoint/mesh landing zone |
| Billing | Gateway can run observability/ledger mode | No durable enterprise billing pipeline |
| KV cache | Tenant intent propagated via headers | No proof of runtime KV-cache isolation |

## Smoke test behavior

The full-stack smoke test:

1. Gets real Cognito ID tokens for tenant A and tenant B.
2. Calls `/healthz` and `/readyz`.
3. Sends a valid tenant A request through the gateway.
4. Sends tenant A token to tenant B domain and expects `403` before AIBrix.

The valid request is expected to hit the real AIBrix/vLLM upstream. If the model is still downloading, the vLLM pod is not healthy, or the AIBrix Envoy service name changed, this step can fail.

## Common debugging commands

```bash
kubectl get nodes -L nodepool,workload,accelerator
kubectl get pods -A
kubectl -n aibrix-system get pods
kubectl -n envoy-gateway-system get svc
kubectl -n default get deployment,pods -l model.aibrix.ai/name=$SERVED_MODEL_NAME
kubectl -n tenant-gateway logs deployment/tenant-policy-gateway --tail=200
```

Check GPU resources:

```bash
kubectl describe nodes | grep -A5 -i 'nvidia.com/gpu'
```

Check the rendered tenant registry:

```bash
cat .aws-danger-tenants.yaml
```

## Enterprise reviewer note

This path is intentionally more real than the cheap AWS demo, but still not a production platform. It exists to show how the reference gateway could be wired into a real AWS/AIBrix/vLLM experiment when the operator accepts GPU cost and cloud complexity.

## Audit fixes added after the DANGER ZONE roast

This path was tightened after an AWS-specific review of the danger-zone flow.

Implemented guardrails:

- The example env file no longer pre-sets `I_UNDERSTAND_AWS_GPU_COST_AND_QUOTAS=yes`; the operator must set it manually.
- `COGNITO_TEST_PASSWORD` must be explicitly set and cannot use the old placeholder/default value.
- Cognito `custom:tenant_id` is created as an immutable custom attribute.
- The Cognito app client explicitly excludes `custom:tenant_id` from `WriteAttributes`, so the tenant claim is not user-writable.
- Existing Cognito pools with mutable `tenant_id` fail closed instead of being reused.
- Generated `.aws-danger*.env` and rendered YAML/manifest files are covered by `.gitignore` and `.dockerignore`.
- The GPU eksctl template defaults node groups to private networking.
- Envoy Gateway rollout, AIBrix manifest application, NVIDIA device plugin install, GPU resource discovery, and vLLM rollout are now fail-fast steps.
- Remote AIBrix/NVIDIA manifests are downloaded to `.aws-danger-manifests/`; optional SHA256 environment variables can enforce checksum verification.
- The gateway Service includes explicit NLB and internal/external scheme annotations plus the legacy internal-LB fallback annotation.
- The vLLM model Deployment now includes a PodDisruptionBudget, seccomp profile, capability drop, and optional PVC-backed model cache mode.

Optional checksum variables:

```bash
export AIBRIX_DEPENDENCY_SHA256=...
export AIBRIX_CORE_CRDS_SHA256=...
export AIBRIX_CORE_SHA256=...
export NVIDIA_DEVICE_PLUGIN_SHA256=...
```

Optional persistent model cache mode:

```bash
export MODEL_CACHE_VOLUME_MODE=efs_pvc
export MODEL_CACHE_PVC_NAME=my-model-cache-pvc
```

If these are not set, the default is still `emptyDir`, which means a pod reschedule can trigger another large model download.

## Revised minimum setup

```bash
cp infra/aws/full-stack/full-stack.env.example .aws-danger.env
vim .aws-danger.env
# Set at least:
#   COGNITO_TEST_PASSWORD=<strong throwaway password>
#   AWS_REGION=<your region>
#   GPU_INSTANCE_TYPE=<instance type with quota>

source .aws-danger.env
export I_UNDERSTAND_AWS_GPU_COST_AND_QUOTAS=yes

make aws-danger-create-gpu-cluster
make aws-danger-oidc
make aws-danger-artifacts
make aws-danger-install-lbc
make aws-danger-install-aibrix
make aws-danger-redis-quota
make aws-danger-billing-ledger
make aws-danger-pod-identity
make aws-danger-verify-adapters
make aws-danger-deploy
make aws-danger-verify-private
make aws-danger-smoke
```

## Audit-hardened full-stack sequence

After the external-audit simulation, the recommended full-stack sequence is no longer just cluster → AIBrix → gateway. Run the guardrail/control steps as separate evidence-producing stages:

```bash
make aws-danger-create-gpu-cluster
make aws-danger-oidc
make aws-danger-artifacts
make aws-danger-install-lbc
make aws-danger-install-aibrix
make aws-danger-redis-quota
make aws-danger-billing-ledger   # S3 Object Lock + DynamoDB idempotency reference
make aws-danger-pod-identity     # required for gateway S3/DynamoDB writes
make aws-danger-verify-adapters  # required by default before deploy
make aws-danger-deploy
make aws-danger-verify-private
make aws-danger-smoke
```

Key changes:

- The full-stack gateway refuses `APP_QUOTA_MODE=in_memory`; it expects the Redis/ElastiCache reference backend.
- The LoadBalancer path expects AWS Load Balancer Controller to be installed and IAM-bound first.
- The deployment verifies the NLB scheme when AWS returns the LoadBalancer hostname.
- `APP_OIDC_REQUIRED_TOKEN_USE=id`, `nbf` validation, leeway, and JWKS cache are enabled in the full-stack template.
- The billing step creates an S3 Object Lock bucket plus a DynamoDB idempotency table when `APP_BILLING_MODE=aws_native_reference` is used.
- The Pod Identity step binds the gateway ServiceAccount to a least-privilege role for S3/DynamoDB billing writes.
- Adapter verification now writes evidence, and full-stack deploy refuses to continue when evidence is missing unless you explicitly relax enforcement.
- Streaming is blocked in billing-required modes until final usage extraction is implemented.

This is still a DANGER ZONE path. It can create paid AWS resources and still does not prove KV-cache isolation, streaming billing accuracy, or enterprise-grade private networking.

See also [`docs/19-pr9-audit-remediation.md`](19-pr9-audit-remediation.md).
