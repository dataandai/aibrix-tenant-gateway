# 18 — Hardening PR8 Implementation Notes

PR8 added the first major audit-remediation layer:

1. AWS Load Balancer Controller + IAM/IRSA install + NLB verification.
2. Redis/ElastiCache quota backend reference and full-stack refusal of in-memory quota.
3. OIDC hardening with `token_use`, `nbf` support, scope/group checks, and JWKS cache.
4. Supply-chain hardening references: lockfile, SBOM, Trivy, container scan, Cosign signing note.
5. Private networking evidence script.
6. Streaming proxy and TTFT metrics.
7. Adapter artifact verification utility.
8. AWS-native S3 Object Lock billing ledger reference.

PR9 then tightened several runtime integration gaps. See [PR9 Audit Remediation Notes](19-pr9-audit-remediation.md).

## Current advanced path order

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

## Remaining hard truth

These are real improvements, not proof of an enterprise platform. The deepest remaining work is runtime isolation proof, streaming usage accounting, cryptographic adapter signature enforcement, complete AWS landing zone controls, and live GPU load-test evidence.
