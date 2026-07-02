# Known Production Blockers

The following items should remain blockers for production certification:

1. **KV-cache isolation proof**: the gateway expresses isolation intent but cannot prove vLLM/AIBrix runtime isolation.
2. **Adapter signature enforcement**: SHA256 can be verified, but signed artifact enforcement is still a reference hook.
3. **Redis quota operations**: the Redis backend is distributed, but not a full HA/failover/quota reconciliation system.
4. **Billing reconciliation**: S3 Object Lock objects are useful audit evidence, not a complete billing pipeline.
5. **Private landing zone**: private nodes and NLB scheme are not enough; production needs VPC endpoints, egress restrictions, and centralized network evidence.
6. **Streaming billing**: the stream path emits TTFT and token hints, not billing-grade stream usage.
7. **Supply chain finalization**: deploying org must pin base image digest, sign images, store SBOMs, and enforce registry admission policy.
8. **Load testing**: no GPU load test proves TTFT, queue depth, cache behavior, or noisy-neighbor isolation.
