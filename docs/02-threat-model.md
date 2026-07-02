# 02 — Threat Model

## Assets

- Tenant identity and routing context.
- Model access policy.
- LoRA adapter access policy.
- Request/audit/metering events.
- AIBrix/vLLM serving capacity.
- Tenant-specific data in prompts and responses.

## Trust boundaries

```text
Public client       untrusted
Ingress/Gateway     semi-trusted infrastructure boundary
Tenant Gateway      policy enforcement point
AIBrix/vLLM         serving substrate, not SaaS auth boundary
Model/runtime       compute/data processing layer
```

## Implemented controls

### Mock-auth environment guardrail

`APP_AUTH_MODE=mock` is rejected outside `local`, `dev`, `development`, `test`, and `ci` unless an explicitly unsafe override is set. This is a guardrail against accidental demos becoming production incidents. It does not make mock auth secure.


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

This prevents client-provided routing hints from influencing policy or AIBrix-facing headers. A valid request with spoofed routing headers may still be allowed, but the spoofed values are stripped and ignored.

### Domain + tenant claim match

A request must satisfy both:

- `Host` resolves to tenant X,
- JWT tenant claim says tenant X.

If either side disagrees, the request is denied.

### Model and adapter allowlists

The request body must use a model allowed for the tenant. If a LoRA adapter is requested, it must be allowed for that tenant/model pair.

### Fail closed

If the tenant registry cannot be loaded, inference endpoints return `503 registry_unavailable`.

## What is not a security boundary

- Header-based AIBrix routing is not a security boundary.
- Kubernetes namespaces alone are not a complete tenant isolation strategy.
- Mock JWT mode is not authentication.
- Approximate token metering is not a billing ledger.
- LoRA allowlists are not complete adapter governance.
- This MVP does not prove KV-cache isolation.

## Production hardening checklist

- Use real OIDC/JWKS validation with issuer-specific configuration.
- Disable mock auth in all non-local environments.
- Add mTLS or trusted service identity between ingress, gateway, and AIBrix where appropriate.
- Ensure upstream AIBrix is not publicly reachable.
- Add egress restrictions and NetworkPolicies.
- Add runtime rate limiting and quota enforcement.
- Add tenant-specific audit retention and SIEM integration.
- Add adapter artifact signing/scanning/approval workflows.
- Add load tests and noisy-neighbor tests.
- Prove or explicitly constrain vLLM/AIBrix KV-cache and batching behavior under multi-tenant workloads.
- Add durable billing ledger and quota enforcement before charging customers.

## Additional controls added after roast

### Security posture enforcement

The app can run in `APP_SECURITY_POSTURE_MODE=enforce`. In that mode, critical/high
findings block readiness and request handling. Example findings include mock upstream
in production-like environments, disabled quota, disabled billing, disabled audit,
and an upstream URL that does not look private/internal.

This is a guardrail, not a formal compliance engine.

### Runtime quota abuse

The repo now includes an in-memory quota enforcer for request and input-token windows.
This mitigates abuse only inside one process. A multi-replica production deployment
needs a distributed quota backend.

### Adapter supply-chain abuse

`catalog_enforced` mode requires adapter metadata: active status, checksum, signer,
and compatible model list. This reduces accidental adapter misuse, but it does not
verify the downloaded artifact cryptographically.

### Billing bypass

`ledger_required` mode blocks successful responses if upstream usage fields are absent
or inconsistent. This prevents silent serving without usage records in the reference
flow, but the JSONL ledger is not tamper-proof or invoice-grade.

### Direct-to-AIBrix bypass

The core threat remains: if an attacker can reach AIBrix/vLLM directly, the gateway
policy can be bypassed. NetworkPolicy, private Services, service identity, and mTLS
must be enforced outside this FastAPI process.
