# 16 — Known Production Blockers

These items should remain blockers for production certification.

1. **KV-cache isolation proof**: the gateway expresses isolation intent but cannot prove vLLM/AIBrix runtime isolation.
2. **Adapter signature enforcement**: SHA256 verification exists, but signed artifact enforcement is still a reference hook.
3. **Billing reconciliation**: S3 Object Lock and DynamoDB idempotency are useful evidence, not a complete billing pipeline.
4. **Streaming billing**: streaming is blocked in billing-required modes rather than fully accounted with final usage extraction.
5. **Private landing zone**: private nodes and NLB scheme are not enough; production needs VPC endpoints, egress restrictions, account boundaries, and centralized evidence.
6. **Quota maturity**: Redis quota is stronger than in-memory quota, but still lacks full HA/failure-mode policy, output-token quota, and cost budgets.
7. **Supply chain finalization**: the deploying org must pin base image digests, sign images, store SBOMs, and enforce registry admission policy.
8. **Load testing**: no GPU load test proves TTFT, queue depth, cache behavior, cold-start behavior, or noisy-neighbor isolation.
9. **Enterprise identity lifecycle**: tenant claim ownership, federation, MFA, revocation, and break-glass processes are outside the repo.
