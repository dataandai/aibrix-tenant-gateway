# 16 — Known Production Blockers

These items should remain blockers for production certification.

1. **KV-cache isolation proof**: the gateway expresses isolation intent but cannot prove vLLM/AIBrix runtime isolation.
2. **Adapter signature enforcement**: SHA256 verification exists, but signed artifact enforcement is still a reference hook.
3. **Billing reconciliation**: S3 Object Lock and DynamoDB idempotency are useful evidence, not a complete billing pipeline.
4. **Streaming billing**: streaming is blocked in billing-required modes rather than fully accounted with final usage extraction.
5. **Private landing zone**: private nodes and NLB scheme are not enough; production needs VPC endpoints, egress restrictions, account boundaries, and centralized evidence.
6. **Quota maturity**: Redis quota now uses sliding-window Lua logic and request-id concurrency cleanup, but still lacks full HA/failure-mode policy, regional consistency, output-token quota, and cost budgets.
7. **Supply chain finalization**: the deploying org must pin base image digests, sign images, store SBOMs, and enforce registry admission policy.
8. **Load testing**: no GPU load test proves TTFT, queue depth, cache behavior, cold-start behavior, or noisy-neighbor isolation.
9. **Enterprise identity lifecycle**: tenant claim ownership, federation, MFA, revocation, and break-glass processes are outside the repo.

7. **Tokenizer artifact assurance**: PR10 fails closed when production-like quota modes lack a real tokenizer, but production deployments still need signed/pinned tokenizer assets and startup evidence.
8. **Schema evolution governance**: strict Pydantic request contracts protect the current API surface, but every newly forwarded upstream parameter must be intentionally modeled and policy-reviewed.
