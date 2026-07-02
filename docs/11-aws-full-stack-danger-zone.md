# 11 — Advanced AWS GPU Full-Stack Path

> **DANGER ZONE warning label:** the Makefile target prefix is still `aws-danger-*`. “Danger Zone” is not a product name. It means this path can create expensive AWS resources, requires GPU service quota, and is expected to fail unless your AWS account, region, IAM permissions, networking, and GPU capacity are ready.

This path is for users who intentionally want to try the full lab: EKS GPU nodes, Cognito OIDC, Redis quota, S3/DynamoDB billing references, AIBrix/vLLM, and a real model-serving deployment.

It is **not a production platform**.

## Use the cheaper path first

Most reviewers should start with:

```bash
make aws-create-cluster
make aws-build-push
make aws-deploy
make aws-smoke
```

Use the advanced path only after the CPU-only AWS demo works and you understand the cost and quota implications.

## What the advanced path creates

| Component | Purpose | Production caveat |
|---|---|---|
| EKS GPU node group | runs vLLM/AIBrix model pod | no Karpenter autoscaling design |
| AWS Load Balancer Controller | manages NLB service | IAM policy must be reviewed by org |
| Cognito User Pool | demo OIDC provider | not enterprise federation |
| Redis/ElastiCache | distributed quota reference | not full HA/failover quota platform |
| S3 artifact buckets | model/LoRA artifact references | not full model registry |
| S3 Object Lock + DynamoDB | AWS-native billing reference | not full billing system |
| Pod Identity/IRSA | gateway AWS API access | policies require org review |
| AIBrix/vLLM | serving substrate | runtime isolation still unproven |

## Required manual acknowledgement

The path refuses to run until you explicitly acknowledge cost and quota risk:

```bash
export I_UNDERSTAND_AWS_GPU_COST_AND_QUOTAS=yes
```

The example env file intentionally does not pre-set this value.

## Configuration

```bash
cp infra/aws/full-stack/full-stack.env.example .aws-danger.env
vim .aws-danger.env
source .aws-danger.env
```

At minimum, review:

```text
AWS_REGION
CLUSTER_NAME
GPU_INSTANCE_TYPE
COGNITO_TEST_PASSWORD
AWS_FULL_GATEWAY_SCHEME
APP_QUOTA_MODE
APP_BILLING_MODE
MODEL_ID
SERVED_MODEL_NAME
```

Do not use placeholder passwords. The Cognito bootstrap script rejects default-like values.

## Recommended command sequence

```bash
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

## Logs and cleanup

```bash
make aws-danger-logs
make aws-danger-destroy
```

Optional deeper cleanup is controlled by environment flags in the destroy script. Always inspect remaining AWS resources after deletion, especially GPU instances, LoadBalancers, EBS volumes, ECR repositories, S3 buckets, ElastiCache, and DynamoDB.

## Audit fixes included

The advanced path was tightened after AWS-specific review. Important fixes include:

- the cost consent flag is not pre-accepted,
- Cognito `custom:tenant_id` is immutable and not user-writable,
- default Cognito passwords are rejected,
- generated `.aws-danger*` files are ignored by Git and Docker,
- GPU nodes default to private networking,
- critical install steps fail fast,
- remote manifests are downloaded locally and can be checksum-verified,
- model cache can use PVC mode instead of only `emptyDir`,
- AWS Load Balancer Controller installation and NLB verification are included,
- Redis quota and AWS-native billing references are included,
- Pod Identity/IRSA bootstrap is included,
- adapter verification evidence is required by default before deployment.

## Security posture

The advanced path is safer than the original prototype, but it is still a lab. It does not prove:

- KV-cache isolation,
- complete private AWS landing zone,
- billing-grade streaming usage,
- cryptographic adapter signature enforcement,
- enterprise IdP lifecycle,
- GPU noisy-neighbor safety,
- production SLO autoscaling.

## Evidence to collect

```bash
kubectl get pods -A
kubectl -n kube-system get deployment aws-load-balancer-controller
kubectl -n tenant-gateway get svc tenant-policy-gateway-full-stack -o yaml
kubectl -n tenant-gateway logs deploy/tenant-policy-gateway
aws elbv2 describe-load-balancers
aws elasticache describe-replication-groups
aws s3api get-object-lock-configuration --bucket <billing-bucket>
aws dynamodb describe-table --table-name <billing-idempotency-table>
```

## Final warning

This remains the advanced AWS GPU full-stack path. It can create paid resources and still does not prove production readiness. Use it as an audit-focused lab, not as a customer-facing platform.
