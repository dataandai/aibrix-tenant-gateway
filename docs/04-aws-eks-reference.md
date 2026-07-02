# 04 — AWS EKS Reference

This is a reference shape, not a full enterprise landing zone.

## Suggested AWS components

- **EKS** for Kubernetes control plane.
- **AWS Load Balancer Controller** for ALB integration where needed.
- **Gateway API / Envoy Gateway** for host-based routing inside the cluster.
- **Karpenter** for GPU node pool provisioning for AIBrix/vLLM.
- **ECR** for container images.
- **Secrets Manager** for OIDC/JWKS/client configuration where secrets are needed.
- **ASCP or External Secrets Operator** to sync secrets into Kubernetes.
- **Pod Identity or IRSA** for least-privilege AWS access.
- **S3** for model/adapter artifacts if your model lifecycle uses S3.
- **CloudWatch / OpenTelemetry** for logs, metrics, and traces.
- **VPC endpoints** for private AWS API access from private subnets.

## Network shape

```text
Internet
  -> ALB / ingress
  -> Envoy Gateway / Gateway API
  -> Tenant Policy Gateway Service
  -> AIBrix internal Service
  -> vLLM pods on GPU node pools
```

The Tenant Policy Gateway and AIBrix should run in private subnets. The AIBrix service should not be publicly exposed.

## Karpenter GPU pools

AIBrix/vLLM workloads should use dedicated GPU node pools with explicit labels, taints, and resource requests. A reference production design should include:

- GPU instance family constraints,
- capacity type policy,
- interruption handling,
- image pre-pull strategy,
- node consolidation policy,
- per-pool budgets,
- quota alarms,
- runtime class or device plugin validation.

This repo does not include a complete Karpenter setup.

## Secrets

The example manifests include a placeholder Secret. For EKS, prefer:

- AWS Secrets Manager,
- ASCP or External Secrets Operator,
- Pod Identity/IRSA with least privilege,
- no static secrets committed to Git.

## Observability

The gateway logs structured JSON metering events. Production EKS designs should route these to:

- CloudWatch Logs,
- OpenTelemetry collector,
- SIEM/data lake,
- Prometheus-compatible metrics if converted to counters/histograms.

## Guardrails missing from this repo

- WAF and DDoS configuration.
- ALB TLS policy and certificate automation.
- Multi-account AWS boundaries.
- Centralized audit retention.
- PrivateLink/shared services design.
- End-to-end mTLS.
- Full GPU capacity planning.
- Disaster recovery strategy.
