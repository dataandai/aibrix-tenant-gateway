# 12 — Remaining Gaps After the Advanced AWS GPU Path

The advanced AWS GPU path is runnable scaffolding, not a production guarantee. It is valuable because it exercises real AWS and AIBrix/vLLM components, but it does not prove that the system is safe, scalable, isolated, or cost-controlled under real tenant load.

## AWS platform gaps

- No complete AWS landing zone.
- No AWS Organizations/SCP design.
- No full VPC endpoint and egress-lockdown implementation.
- No WAF/Shield/TLS/certificate lifecycle.
- No centralized GuardDuty/Security Hub/SIEM integration.
- No disaster recovery plan.

## Identity gaps

- Cognito is used as a reference IdP, not enterprise federation.
- ID token vs access token API authorization must be decided by the deploying organization.
- Tenant claim lifecycle and ownership process are outside the repo.
- MFA, conditional access, and revocation playbooks are outside the repo.

## LLMOps runtime gaps

- KV-cache isolation is not proven.
- No GPU noisy-neighbor load test is included.
- No Karpenter GPU autoscaling loop is included.
- Model registry is not yet the runtime source of truth.
- Model cache strategy is only a reference.
- TTFT metrics exist, but queue time, prefill latency, decode latency, and tokens/sec are not complete.

## Billing and quota gaps

- Redis quota is a reference implementation, not a full commercial quota platform.
- AWS-native billing evidence is not invoice reconciliation.
- Streaming is blocked in billing-required modes rather than fully accounted.
- Output-token quota and cost-budget enforcement remain incomplete.

## Adapter governance gaps

- SHA256 verification is useful, but not full artifact trust.
- Cryptographic signature enforcement is not complete.
- No admission-controller policy blocks unverified runtime artifacts.
- No quarantine workflow or signed release lifecycle is included.

## Final assessment

An enterprise reviewer could still reject this as a production platform. That is expected. The value of the advanced path is that it makes the hard parts visible and gives reviewers a concrete lab to test and criticize.
