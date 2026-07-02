# AWS Demo Runbook

This runbook turns the repository into something a reviewer can actually deploy on AWS, call with curl, inspect, and destroy.

It is intentionally a **CPU-only AWS demo**. It does not deploy real AIBrix/vLLM GPU serving. The gateway runs in Kubernetes with mock authentication and mock upstream enabled so that the tenant policy, header stripping, trusted header injection, quota checks, adapter governance, audit events, and metrics can be tested without GPU quota or model download time.

## What the AWS demo creates

- An Amazon EKS cluster created with `eksctl`.
- A small managed CPU node group.
- An Amazon ECR repository for the gateway image.
- A `tenant-gateway` namespace.
- A `tenant-policy-gateway` Deployment with two replicas.
- A public AWS LoadBalancer Service for easy smoke testing.
- A ConfigMap-based tenant registry for `tenant-a.example.local` and `tenant-b.example.local`.

## What the AWS demo does not create

- No GPU node group.
- No real AIBrix/vLLM deployment.
- No real OIDC provider.
- No DNS records.
- No TLS certificate.
- No private ALB/NLB.
- No mTLS mesh.
- No production billing ledger.
- No distributed quota backend.

Those are covered by the production hardening docs as next integration steps.

## Cost warning

Running EKS and LoadBalancer resources can cost money even when the app is idle. This demo is intended for short-lived review clusters. Run the destroy script when finished.

## Prerequisites

Install and configure:

```bash
aws --version
eksctl version
kubectl version --client
docker --version
aws sts get-caller-identity
```

The scripts expect an AWS identity with permission to create EKS clusters, EC2/VPC resources, ECR repositories, IAM roles, and Elastic Load Balancers.

## One-path demo

From the repo root:

```bash
export AWS_REGION=eu-west-1
export CLUSTER_NAME=aibrix-gateway-demo

scripts/aws/01-create-cluster.sh
scripts/aws/02-build-push-ecr.sh
scripts/aws/03-deploy-demo.sh
scripts/aws/04-smoke-test.sh
```

Optional logs:

```bash
scripts/aws/05-logs.sh
```

Destroy everything:

```bash
scripts/aws/99-destroy-demo.sh
```

To also delete the ECR repository:

```bash
DELETE_ECR_REPOSITORY=true scripts/aws/99-destroy-demo.sh
```

## Smoke test behavior

The smoke test sends:

1. `GET /healthz`
2. `GET /readyz`
3. a valid tenant A chat completion request
4. a cross-tenant request that must return `403`

A valid demo response includes the mock upstream body and the internal trusted headers received by the upstream mock. This is useful because it proves that client-supplied routing headers do not control the AIBrix-facing headers.

## Why the demo uses mock auth on AWS

This is deliberately a throwaway demo mode. The deployment sets:

```yaml
APP_AUTH_MODE: mock
APP_ENVIRONMENT: aws-demo
APP_UNSAFE_ALLOW_MOCK_AUTH_OUTSIDE_LOCAL: "true"
APP_MOCK_UPSTREAM: "true"
APP_SECURITY_POSTURE_MODE: audit
```

That combination is **not production-secure**. It exists only so a reviewer can deploy the repo on AWS without setting up an identity provider and GPU serving stack first.

For a production-like deployment, change the posture toward:

```yaml
APP_AUTH_MODE: oidc
APP_MOCK_UPSTREAM: "false"
APP_SECURITY_POSTURE_MODE: enforce
APP_REQUIRE_PRIVATE_UPSTREAM: "true"
APP_BILLING_MODE: ledger_required
APP_AUDIT_SINK: jsonl or external
APP_QUOTA_MODE: redis or external rate-limit backend
```

The last line is an intended future extension; the current repository still ships only an in-memory quota backend.

## How to replace the mock upstream with AIBrix

1. Deploy AIBrix/vLLM into an internal namespace such as `aibrix-system`.
2. Expose the AIBrix gateway through an internal ClusterIP Service.
3. Change the gateway Deployment:

```yaml
APP_MOCK_UPSTREAM: "false"
APP_UPSTREAM_BASE_URL: http://aibrix-gateway.aibrix-system.svc.cluster.local
APP_REQUIRE_PRIVATE_UPSTREAM: "true"
```

4. Add NetworkPolicy so only `tenant-gateway` pods can call the AIBrix Service.
5. Add mTLS/service identity if using a mesh.
6. Keep the external LoadBalancer or ALB pointed only at the Tenant Policy Gateway, never directly at AIBrix.

## Troubleshooting

Check pods:

```bash
kubectl -n tenant-gateway get pods
kubectl -n tenant-gateway describe deployment tenant-policy-gateway
kubectl -n tenant-gateway logs deployment/tenant-policy-gateway --tail=100
```

Check the LoadBalancer:

```bash
kubectl -n tenant-gateway get svc tenant-policy-gateway-public
```

Manually call the gateway:

```bash
LB_HOST=$(kubectl -n tenant-gateway get svc tenant-policy-gateway-public -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

curl -sS \
  -H 'Host: tenant-a.example.local' \
  -H 'Authorization: Bearer mock:tenant-a:alice' \
  -H 'Content-Type: application/json' \
  -d '{"model":"meta-llama/Llama-3.1-8B-Instruct","messages":[{"role":"user","content":"hello"}],"lora_adapter":"tenant-a-support"}' \
  "http://${LB_HOST}/v1/chat/completions"
```

## Enterprise reviewer note

This AWS demo proves packaging, deployment, policy flow, and basic operational inspection. It does not prove production security, billing, scale, or tenant isolation. Treat it as a runnable reference environment, not a production architecture claim.
