# 19 — PR9 Audit Remediation Notes

PR9 addresses the second external-audit pass. It does not certify the project as production-ready. It turns several previously “implemented-looking” controls into runnable reference controls with explicit guardrails.

## PR9-1: NetworkPolicy, Pod Identity, AWS egress

Implemented:

- `scripts/aws-danger/12-bootstrap-gateway-pod-identity.sh`
- EKS Pod Identity association for the `tenant-policy-gateway` ServiceAccount
- least-privilege reference IAM policy for S3 billing ledger writes and DynamoDB idempotency writes
- gateway ServiceAccount IRSA annotation placeholder for clusters that still use IRSA
- NetworkPolicy egress for DNS, internal AIBrix/Envoy, RFC1918 private endpoints, Redis, and optional public HTTPS for Cognito/JWKS through NAT

Caveat: standard Kubernetes NetworkPolicy cannot express FQDN egress. For strict production, replace the optional public HTTPS rule with Cilium/Calico FQDN policy, private endpoint routing where available, or a controlled egress proxy.

## PR9-2: Streaming billing gate and upstream status propagation

Implemented:

- `stream=true` is denied when `APP_BILLING_MODE=ledger_required` or `aws_native_reference`, unless `APP_ALLOW_STREAMING_WITHOUT_BILLING_USAGE=true` is explicitly set.
- The streaming proxy opens the upstream stream before constructing the downstream `StreamingResponse`, so upstream 4xx/5xx status can propagate instead of being masked as HTTP 200.

Caveat: streaming usage extraction is still not billing-grade. The safe default is to block streaming in billing-required modes.

## PR9-3: Redis Lua quota

Implemented:

- Redis quota uses Lua scripts for atomic check-and-record.
- User-level and tenant-level request counters.
- User-level and tenant-level input-token counters.
- User-level and tenant-level concurrency counters.
- `finish_request()` decrements concurrency on normal and streaming completion paths.

Caveat: output-token quota and cost-budget enforcement are not implemented. Regional Redis replication and failure-mode policy are out of scope.

## PR9-4: AWS-native billing via boto3 + DynamoDB idempotency

Implemented:

- AWS-native ledger no longer shells out to the AWS CLI.
- boto3 writes one object per request into the S3 Object Lock bucket.
- optional DynamoDB table provides request-id idempotency with conditional `PutItem` and completion update.
- `scripts/aws-danger/11-create-aws-native-billing-ledger.sh` creates the DynamoDB idempotency table.

Caveat: this is still a reference billing ledger. It is not a complete reconciliation, invoicing, dispute, or financial-control system.

## PR9-5: Adapter verification enforcement path

Implemented:

- adapter verifier supports `python -m tenant_policy_gateway.adapter_artifact_verifier`
- S3 verification uses boto3 instead of AWS CLI
- `scripts/aws-danger/10-verify-adapter-artifacts.sh` writes `.aws-danger-adapter-verification.env` evidence
- full-stack deploy refuses to continue if adapter verification evidence is missing and enforcement is required
- S3 artifact bootstrap creates placeholder adapter objects with matching SHA256 values so the reference verification path can run

Caveat: cryptographic signature verification is still metadata-only. A production implementation should add KMS/cosign verification, admission-control enforcement, and artifact quarantine workflows.

## Remaining blockers

- KV-cache isolation is still not proven.
- Streaming usage accounting is intentionally blocked in billing-required modes rather than solved.
- Adapter signature verification is still not cryptographic.
- Standard NetworkPolicy still cannot enforce domain-level egress.
- No GPU noisy-neighbor/load-test evidence is included.
- No full enterprise AWS landing zone is included.
