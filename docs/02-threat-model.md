# 02 — Threat Model

## Assets

- Tenant identity and routing context.
- OIDC/JWT claims used for tenant decisions.
- Model and LoRA adapter access policy.
- Billing, audit, quota, and metering events.
- AIBrix/vLLM serving capacity.
- Tenant prompt and response data.
- Model and adapter artifacts.

## Trust boundaries

```text
Public client            untrusted
DNS / NLB / ingress       infrastructure boundary, not app auth
Tenant Policy Gateway     policy enforcement point
AIBrix / Envoy / vLLM     serving substrate, not SaaS auth boundary
Model runtime / GPU       compute boundary requiring separate validation
AWS services              trusted only through scoped IAM and network controls
```

## Primary threat scenarios

| Threat | Reference control | Remaining production concern |
|---|---|---|
| Cross-tenant token use | Host tenant must match JWT tenant claim | IdP lifecycle and tenant claim source of truth remain external |
| Header spoofing | Client routing headers are stripped; trusted headers are regenerated | Direct-to-AIBrix bypass must be prevented by network/service controls |
| Unauthorized model use | tenant/model allowlist | Model registry as source of truth is still reference-only |
| Unauthorized LoRA adapter | tenant/model adapter allowlist + catalog checks | Runtime artifact signature enforcement is not complete |
| Quota abuse | local demo quota or Redis reference quota | HA/failover, regional consistency, and cost budgets remain out of scope |
| Billing bypass | ledger-required and AWS-native reference modes | streaming usage is blocked, not fully solved |
| AWS credential misuse | Pod Identity/IRSA reference path | IAM policy must be reviewed and scoped by deploying org |
| Public upstream bypass | private upstream expectation and NetworkPolicy examples | full VPC endpoint/egress proof is not included |

## Implemented controls

### Mock-auth environment guardrail

`APP_AUTH_MODE=mock` is rejected outside `local`, `dev`, `development`, `test`, and `ci` unless an explicitly unsafe override is set. This prevents accidental use of mock auth in production-like deployments. It does not make mock auth secure.

### OIDC/JWKS validation

OIDC mode validates issuer, audience, signature, temporal claims, tenant claim, and optional `token_use`, scope, and group requirements. JWKS clients are cached with TTL. This is a reference IdP integration, not a complete enterprise identity lifecycle.

### Header stripping

The gateway strips client-supplied routing headers before forwarding:

- `x-tenant-id`
- `x-user-id`
- `x-tier`
- `user`
- `external-filter`
- `config-profile`
- `x-internal-tenant-id`
- `x-internal-user-id`
- `x-internal-slo-tier`

A valid request with spoofed routing headers may still be allowed, but the spoofed values are ignored and removed.

### Quota and billing fail-closed hooks

The advanced path can use Redis-backed quota enforcement and AWS-native reference billing. Streaming is denied in billing-required modes unless an explicit unsafe override is set.

### Adapter verification evidence

The repository includes an adapter artifact verifier and a deploy-time evidence gate for the advanced AWS path. It verifies SHA256 for reference artifacts, but cryptographic signature enforcement remains a production gap.

## What is not a security boundary

- Header-based AIBrix routing is not a security boundary.
- Kubernetes namespaces alone are not a complete tenant isolation strategy.
- Mock JWT mode is not authentication.
- Approximate token estimates are not billing-grade usage records.
- A LoRA allowlist is not complete adapter supply-chain governance.
- The gateway cannot prove vLLM/AIBrix KV-cache isolation.
- The advanced AWS path is not an enterprise landing zone.

## Production hardening checklist

- Use real OIDC/JWKS validation with organization-approved issuer configuration.
- Define whether API authorization uses ID tokens, access tokens, or a service-to-service flow.
- Ensure tenant claims cannot be user-mutated.
- Restrict direct access to AIBrix/vLLM.
- Add service identity or mTLS between trusted components.
- Replace broad HTTPS egress with FQDN policy, VPC endpoints, or egress proxy controls.
- Use distributed quota with tested failure-mode behavior.
- Add billing reconciliation and immutable audit retention.
- Enforce model/adapter artifacts with signature verification and admission controls.
- Prove runtime isolation, batching, KV-cache behavior, and noisy-neighbor handling under load.
