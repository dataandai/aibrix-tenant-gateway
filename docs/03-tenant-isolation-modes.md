# 03 — Tenant Isolation Modes

This repository demonstrates policy-based tenant governance. It does not claim that a single shared runtime is always safe. Real systems should choose an isolation mode based on tenant risk, compliance needs, cost, and operational maturity.

## Mode 1 — Shared gateway, shared model pool

```text
Tenant domains -> shared Tenant Policy Gateway -> shared AIBrix/vLLM pool
```

Useful for demos, internal tools, and lower-sensitivity workloads.

Weaknesses:

- noisy-neighbor risk,
- shared runtime blast radius,
- KV-cache and batching behavior must be validated separately,
- policy correctness becomes a critical control.

## Mode 2 — Shared gateway, segmented model pools

```text
Tenant domains -> shared Tenant Policy Gateway -> tier/tenant-specific AIBrix pools
```

The gateway injects trusted routing metadata such as `external-filter` and `config-profile`. AIBrix or the downstream scheduler can use that metadata to select a pool.

This is closer to production, but only if the downstream routing layer enforces the intended separation and the upstream service is not directly reachable.

## Mode 3 — Tenant-dedicated namespaces and serving pools

```text
Tenant A domain -> gateway -> tenant-a namespace/service
Tenant B domain -> gateway -> tenant-b namespace/service
```

This reduces blast radius through Kubernetes namespaces, NetworkPolicies, ResourceQuotas, service accounts, and node selectors/taints.

It is still not sufficient for strict regulated isolation unless combined with identity, network, storage, runtime, audit, and artifact controls.

## Mode 4 — Dedicated cluster or AWS account per tenant

Highest isolation and highest cost. Appropriate when tenants require separate change windows, dedicated GPU capacity, strict compliance boundaries, isolated logging, or account-level controls.

## Where this repo sits

- Local and CPU-only AWS demo paths are closest to Mode 1.
- The advanced AWS GPU path demonstrates pieces of Mode 2.
- The Kubernetes examples point toward Mode 3.
- Mode 4 is discussed only as a production design option.

## Required production decision

Before using a shared model pool, the platform owner must explicitly decide:

- whether tenants can share a vLLM runtime,
- whether LoRA adapters can coexist in one serving pool,
- how KV-cache and batching behavior are isolated or constrained,
- what evidence proves noisy-neighbor and data-boundary safety,
- which tenants require dedicated pools, nodes, clusters, or accounts.
