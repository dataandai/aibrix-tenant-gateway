# 09 — CPU-only AWS Demo Runbook

This CPU-only AWS demo is the cheapest AWS path in the repository. It is designed for reviewers who want to deploy the gateway to EKS without GPU quota, AIBrix installation, real OIDC, or model downloads.

## What it proves

- The gateway image can be built and pushed to ECR.
- The gateway can run on EKS.
- Tenant A and Tenant B requests can be smoke-tested through a LoadBalancer.
- Spoofed routing headers are ignored.
- The deployment emits structured logs and basic metrics.

## What it does not prove

- Real OIDC security.
- AIBrix/vLLM serving behavior.
- GPU scheduling.
- LoRA adapter runtime behavior.
- Production networking.
- Billing-grade metering.

This demo intentionally uses mock auth and mock upstream. It is not production-secure.

## Prerequisites

- AWS CLI configured.
- `eksctl` installed.
- `kubectl` installed.
- Docker installed.
- Sufficient IAM permissions to create EKS, ECR, LoadBalancer, and related resources.

## Run

```bash
export AWS_REGION=eu-west-1
export CLUSTER_NAME=aibrix-gateway-demo

make aws-check
make aws-create-cluster
make aws-build-push
make aws-deploy
make aws-smoke
```

## Inspect logs

```bash
make aws-logs
```

## Destroy

```bash
make aws-destroy
```

This target calls `scripts/aws/99-destroy-demo.sh`.

Destroying is important. Even the CPU-only EKS demo can create paid AWS resources.

## Security posture

The AWS demo manifest explicitly sets:

```text
APP_AUTH_MODE=mock
APP_UNSAFE_ALLOW_MOCK_AUTH_OUTSIDE_LOCAL=true
APP_MOCK_UPSTREAM=true
APP_SECURITY_POSTURE_MODE=audit
```

That combination is acceptable only because this path is a disposable demo. It is not a production configuration.

## When to use the advanced path instead

Use the advanced AWS GPU full-stack path only when you want to test Cognito OIDC, Redis quota, S3/DynamoDB billing references, AIBrix/vLLM, GPU scheduling, and model serving. That path is warning-gated and can be expensive.
