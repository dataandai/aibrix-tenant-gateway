# 03 — Tenant Isolation Modes

This repo demonstrates policy-based request isolation. Production systems may combine multiple modes.

## Mode 1 — Shared gateway, shared model pool

```text
Tenant domains -> shared Tenant Policy Gateway -> shared AIBrix/vLLM pool
```

Useful for demos and lower-sensitivity workloads.

Weaknesses:

- noisy-neighbor risk,
- shared runtime blast radius,
- KV-cache isolation must be understood and validated separately,
- policy correctness becomes critical.

## Mode 2 — Shared gateway, tenant-segmented model pools

```text
Tenant domains -> shared Tenant Policy Gateway -> tenant/profile-specific AIBrix pools
```

The gateway can inject `external-filter` and `config-profile` so downstream routing chooses a tenant or tier-specific pool.

This is closer to production but still depends on downstream enforcement and scheduler behavior.

## Mode 3 — Tenant-dedicated namespaces and serving pools

```text
Tenant A domain -> gateway -> tenant-a namespace/service
Tenant B domain -> gateway -> tenant-b namespace/service
```

Stronger operational isolation. Kubernetes namespaces, NetworkPolicies, ResourceQuotas, and node-pool constraints can reduce blast radius.

Still not enough alone for strict regulated isolation unless combined with identity, network, storage, runtime, and audit controls.

## Mode 4 — Dedicated cluster/account per tenant

Highest isolation, highest cost and operational overhead.

Useful when tenants require strict compliance boundaries, dedicated GPU capacity, isolated logging, independent change windows, or separate AWS accounts.

## MVP position

The MVP primarily demonstrates Mode 1 with examples that point toward Mode 2 and Mode 3. It does not implement hard multi-tenant runtime isolation.

For production review, the team must explicitly decide whether shared model pools are acceptable, whether LoRA adapters can coexist in the same runtime, and whether KV-cache/batching behavior is safe for the tenant risk profile.
