# Hardening PR-8 Implementation Notes

This change set implements the requested audit remediation backlog:

1. AWS Load Balancer Controller + IAM/IRSA install + NLB verification.
2. Redis/ElastiCache quota backend reference and full-stack refusal of in-memory quota.
3. OIDC hardening with `token_use`, `nbf` support, scope/group checks, and JWKS cache.
4. Supply-chain hardening references: lockfile, SBOM, Trivy, container scan, Cosign signing note.
5. Private networking evidence script.
6. Streaming proxy and TTFT metrics.
7. Adapter artifact verification utility.
8. AWS-native S3 Object Lock billing ledger reference.

## Full-stack order

```bash
make aws-danger-create-gpu-cluster
make aws-danger-oidc
make aws-danger-artifacts
make aws-danger-install-lbc
make aws-danger-install-aibrix
make aws-danger-redis-quota
make aws-danger-billing-ledger # S3 Object Lock + DynamoDB idempotency reference
make aws-danger-pod-identity   # required for gateway S3/DynamoDB writes
make aws-danger-verify-adapters
make aws-danger-deploy
make aws-danger-verify-private
make aws-danger-smoke
```

## Remaining hard truth

These are real improvements, not proof of an enterprise platform. The deepest remaining engineering work is runtime isolation proof, streaming usage accounting, adapter signature enforcement, and complete AWS landing zone controls.


See also [PR9 Audit Remediation Notes](19-pr9-audit-remediation.md).
