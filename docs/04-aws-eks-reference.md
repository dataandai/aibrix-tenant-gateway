# 04 — AWS EKS Reference

This document describes the AWS shape used by the repository. It is a reference, not a full enterprise landing zone.

## AWS components represented in this repo

- **EKS** for Kubernetes control plane.
- **AWS Load Balancer Controller** for NLB management in the advanced path.
- **ECR** for container image push in the CPU-only AWS demo.
- **Cognito** as a reference OIDC provider for the advanced path.
- **ElastiCache/Redis** as the distributed quota reference backend.
- **S3 Object Lock** as the billing ledger reference store.
- **DynamoDB** as request-id idempotency reference storage.
- **Pod Identity / IRSA** as the gateway-to-AWS service identity pattern.
- **S3** for model/LoRA artifact references.
- **AIBrix/vLLM** as the serving substrate in the advanced GPU path.

## Reference network shape

```text
Client / reviewer
  -> DNS or explicit Host header
  -> AWS NLB
  -> Tenant Policy Gateway Service
  -> private AIBrix / Envoy / vLLM Service
  -> GPU node pool
```

The AIBrix upstream should be private. Direct client access to AIBrix/vLLM would bypass tenant policy and invalidate the security model.

## What the advanced path validates

The advanced path includes scripts for:

- GPU EKS cluster bootstrap,
- AWS Load Balancer Controller installation,
- Cognito OIDC bootstrap,
- S3 artifact buckets,
- Redis quota backend,
- S3/DynamoDB billing reference,
- gateway Pod Identity association,
- AIBrix/vLLM deployment,
- private networking evidence checks,
- adapter artifact verification evidence.

These are evidence-producing scripts, not a compliance-certified platform.

## Private networking caveat

The advanced path defaults to private GPU nodes and internal LoadBalancer scheme. That is not the same as a full private landing zone.

A production design should add:

- private EKS API endpoint strategy,
- VPC endpoints for ECR API/DKR, S3, STS, CloudWatch Logs, Secrets Manager, and any required AWS APIs,
- explicit NAT or egress proxy strategy for services without private endpoints,
- security group and route-table evidence,
- centralized network logging,
- policy-as-code controls for public exposure.

## GPU capacity and autoscaling

The advanced path is intentionally manual. It does not include a complete Karpenter GPU autoscaling design.

A production design should include:

- GPU instance family constraints,
- capacity type policy,
- interruption handling,
- image/model pre-pull or persistent cache strategy,
- node consolidation policy,
- per-pool budgets,
- quota alarms,
- `nvidia.com/gpu` validation,
- TTFT and queue-depth based scaling signals.

## Secrets and service identity

The repo uses Kubernetes Secrets for demo wiring and Pod Identity/IRSA references for AWS API access. Production deployments should prefer AWS Secrets Manager, External Secrets Operator or ASCP, scoped IAM roles, no static secrets in Git, and rotation playbooks.

## Observability

The gateway emits structured JSON logs and Prometheus-compatible metrics. Production systems should route these to CloudWatch, OpenTelemetry, SIEM/data lake, and durable audit retention with trace correlation.
