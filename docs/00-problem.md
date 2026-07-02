# 00 — Problem

Modern LLM SaaS platforms often need to serve many tenants through shared model-serving infrastructure. AIBrix/vLLM can provide the serving substrate, but a SaaS platform still needs governance in front of that substrate.

The problem this repo addresses:

- different customer domains should map to different tenants,
- tokens should be validated against the tenant implied by the domain,
- tenants should only access approved models,
- tenants should only use approved LoRA adapters,
- public clients must not be able to spoof routing headers,
- downstream AIBrix/vLLM should receive trusted internal routing headers,
- requests should emit structured logs for audit, metering, and operations.

This repo intentionally focuses on the control-plane edge around LLM serving, not on building a complete production AIBrix or AWS platform.
