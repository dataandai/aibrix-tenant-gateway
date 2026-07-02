# Auditor Response Plan

## How to reproduce demo controls

```bash
cp infra/aws/full-stack/full-stack.env.example .aws-danger.env
# Edit required values, including a non-default Cognito test password.
source .aws-danger.env
export I_UNDERSTAND_AWS_GPU_COST_AND_QUOTAS=yes

make aws-danger-create-gpu-cluster
make aws-danger-oidc
make aws-danger-artifacts
make aws-danger-install-lbc
make aws-danger-install-aibrix
make aws-danger-redis-quota
make aws-danger-billing-ledger   # optional, switches billing reference to S3 Object Lock
make aws-danger-deploy
make aws-danger-verify-private
make aws-danger-smoke
```

## Evidence to collect

```bash
kubectl get pods -A
kubectl -n kube-system get deployment aws-load-balancer-controller
kubectl -n tenant-gateway get svc tenant-policy-gateway-full-stack -o yaml
kubectl -n tenant-gateway logs deploy/tenant-policy-gateway
aws elbv2 describe-load-balancers
aws elasticache describe-replication-groups
aws s3api get-object-lock-configuration --bucket <billing-bucket>
```

## Expected audit answer style

Do not claim production readiness. Use this wording:

> This is a production-hardening reference implementation that demonstrates the controls and integration points required in front of AIBrix/vLLM. It includes deployable AWS paths and validation scripts, but it is not production-certified.
