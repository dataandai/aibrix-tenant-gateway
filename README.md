# aibrix-multitenant-llm-gateway

A production-inspired **reference architecture** for OAuth2/OIDC-based multi-tenant, multi-domain LLM serving on Kubernetes with AIBrix/vLLM as the serving substrate.

This repository demonstrates a small SaaS governance layer in front of AIBrix/vLLM. It is useful for learning and architecture review, but it is intentionally **not a production platform**.



## Latest audit-hardening additions

The AWS full-stack DANGER ZONE path now includes an optional audit-remediation layer:

```bash
make aws-danger-install-lbc        # AWS Load Balancer Controller + IAM/IRSA reference install
make aws-danger-redis-quota        # Redis/ElastiCache quota backend reference
make aws-danger-billing-ledger     # S3 Object Lock + DynamoDB idempotency reference
make aws-danger-pod-identity       # Gateway Pod Identity for S3/DynamoDB writes
make aws-danger-verify-adapters    # SHA256 adapter artifact verification evidence
make aws-danger-verify-private     # node ExternalIP + NLB scheme + VPC endpoint evidence
```

The gateway also includes OIDC claim hardening, JWKS client caching, streaming/SSE forwarding with TTFT metrics, Redis Lua quota checks, boto3-based AWS billing writes, supply-chain CI examples, and an external-audit evidence pack in `docs/14-*` through `docs/19-*`. These controls improve the reference implementation but still do not make it a production-certified SaaS LLM platform.

## AWS demo: deployable reviewer environment

This repository now includes a short-lived AWS/EKS demo path for reviewers who want to actually run the gateway outside localhost.

The AWS demo creates a CPU-only EKS cluster, pushes the gateway image to ECR, deploys the Tenant Policy Gateway, exposes it through a public LoadBalancer Service, and runs smoke tests with tenant-aware Host headers.

```bash
export AWS_REGION=eu-west-1
export CLUSTER_NAME=aibrix-gateway-demo

make aws-create-cluster
make aws-build-push
make aws-deploy
make aws-smoke
```

Destroy the demo when finished:

```bash
make aws-destroy
```

The AWS demo uses mock auth and mock upstream intentionally so it can run without GPU quota, a real IdP, or a real AIBrix deployment. It is not production-secure. See [`docs/09-aws-demo-runbook.md`](docs/09-aws-demo-runbook.md) and [`docs/10-aws-production-path.md`](docs/10-aws-production-path.md).



## AWS full-stack Danger Zone: real GPU/AIBrix/vLLM/OIDC path

The cheap AWS demo is still the recommended first path. For people who explicitly want the expensive, real-infrastructure path, the repo now includes a separate **Danger Zone** route.

This path attempts to create a GPU-backed EKS environment with Cognito OIDC, S3 model/LoRA artifact buckets, Envoy Gateway, AIBrix, a vLLM GPU model Deployment, and the Tenant Policy Gateway in OIDC mode with a private AIBrix upstream.

It is intentionally gated by an explicit consent variable:

```bash
export I_UNDERSTAND_AWS_GPU_COST_AND_QUOTAS=yes
```

Then the full path is:

```bash
cp infra/aws/full-stack/full-stack.env.example .aws-danger.env
# Edit .aws-danger.env first: set COGNITO_TEST_PASSWORD and review GPU/model/network values.
vim .aws-danger.env
source .aws-danger.env
export I_UNDERSTAND_AWS_GPU_COST_AND_QUOTAS=yes

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

Destroy it when finished:

```bash
make aws-danger-destroy
```

To also remove optional persistent resources:

```bash
DELETE_ECR_REPOSITORY=true \
DELETE_COGNITO_USER_POOL=true \
DELETE_ARTIFACT_BUCKETS=true \
make aws-danger-destroy
```

This route can fail or become expensive if you lack GPU quota, the model does not fit, the region lacks capacity, Hugging Face access is missing, or upstream AIBrix manifests change. The consent flag is intentionally not enabled in the example env file, Cognito tenant claims are created immutable, generated secret files are git-ignored, and critical runtime installs now fail fast instead of silently continuing. See [`docs/11-aws-full-stack-danger-zone.md`](docs/11-aws-full-stack-danger-zone.md).

## What this repo solves

The MVP implements a FastAPI **Tenant Policy Gateway** between public ingress and AIBrix/vLLM.

```text
Client
  -> Gateway API / Envoy Gateway / ALB-facing ingress
  -> Tenant Policy Gateway
  -> AIBrix Gateway / vLLM serving pool
```

The gateway demonstrates:

- domain-aware tenant resolution from the HTTP `Host`,
- JWT tenant claim validation against the resolved domain tenant,
- tenant-specific model allowlists,
- tenant/model-specific LoRA adapter allowlists,
- mandatory stripping of spoofable client routing headers,
- trusted header injection for AIBrix-facing routing metadata,
- structured JSON request/metering events,
- per-process reference quota enforcement,
- optional adapter artifact catalog checks,
- optional JSONL audit sink,
- optional reference billing ledger mode,
- security posture audit/enforce mode,
- Prometheus-text `/metrics` endpoint,
- Kubernetes and AWS EKS reference manifests.

## What this repo does not solve

This is not a billing, identity, runtime isolation, GPU capacity, or enterprise landing-zone product. It does not implement:

- complete billing-grade token accounting,
- enterprise durable usage ledger or invoice reconciliation,
- hard KV-cache isolation proof,
- full LoRA artifact governance and artifact signing verification,
- distributed runtime rate-limit or quota enforcement,
- TTFT/queue-time/GPU-aware autoscaling loops,
- enforced mTLS or service-mesh identity,
- full AWS landing-zone controls,
- complete AIBrix deployment automation for every topology, although a separate AWS full-stack Danger Zone path is included,
- production OIDC discovery/key-rotation lifecycle.

See [`docs/05-limitations.md`](docs/05-limitations.md), [`docs/06-roast-review.md`](docs/06-roast-review.md), and [`docs/07-production-hardening-implementation-plan.md`](docs/07-production-hardening-implementation-plan.md).

## Why AIBrix is treated as serving substrate, not auth boundary

AIBrix/vLLM is treated here as the LLM serving substrate: model serving, adapter routing, request scheduling, and runtime integration live behind the gateway.

The gateway does **not** assume AIBrix is the SaaS authorization boundary. Public identity, tenant policy, model allowlists, LoRA adapter allowlists, and routing header construction happen before requests reach AIBrix.

If clients or untrusted workloads can reach AIBrix directly, they can bypass this gateway. In production, AIBrix-facing services must be private and reachable only through trusted paths.

## Domain-aware routing

Each tenant has one or more domains in YAML config:

```yaml
tenants:
  - tenant_id: tenant-a
    domains:
      - tenant-a.example.local
```

At request time:

- `Host: tenant-a.example.local` resolves to `tenant-a`.
- The JWT tenant claim must also be `tenant-a`.
- A token for `tenant-a` sent to `tenant-b.example.local` is denied.

This prevents cross-domain tenant replay at the policy gateway.

## Trusted header injection

After a policy allow decision, the gateway injects AIBrix-facing headers:

```text
user: tenant-a:user-123
external-filter: tenant=tenant-a
config-profile: gold
x-internal-tenant-id: tenant-a
x-internal-user-id: user-123
```

These values are derived from:

- tenant registry,
- resolved host,
- validated JWT claims,
- policy engine decision.

They are **not** accepted from public clients.

## Why header stripping is mandatory

Headers such as `user`, `external-filter`, and `config-profile` are often used by gateways and serving stacks for routing, filtering, scheduling, or observability. If a public client can send them directly, a malicious request could attempt to:

- spoof another tenant,
- select another routing profile,
- bypass LoRA/model restrictions,
- poison observability or metering identity.

Therefore this gateway strips all client-supplied values for:

```text
x-tenant-id
x-user-id
x-tier
user
external-filter
config-profile
x-internal-tenant-id
x-internal-user-id
x-internal-slo-tier
```

Then it injects trusted internal values only after policy allow.

Important behavior: a valid request with spoofed routing headers is not automatically denied. The spoofed values are stripped and ignored. The request is allowed only if the tenant/domain/JWT/model/adapter policy still passes, and only gateway-derived trusted headers reach AIBrix.


## Hardening features added after the roast

The repo now includes a second hardening layer. These features are still reference implementations, but they make the architecture much closer to a production review shape:

| Area | New setting/module | What it does | Production caveat |
|---|---|---|---|
| Runtime quota | `APP_QUOTA_MODE=in_memory`, `quota_enforcer.py` | Enforces per-process request/input-token windows from tenant limits | Not distributed across pods |
| Adapter governance | `APP_ADAPTER_GOVERNANCE_MODE=catalog_enforced`, `adapter_governance.py` | Requires active adapter catalog metadata, checksum, signer, model compatibility | Does not cryptographically verify artifacts |
| Audit | `APP_AUDIT_SINK=stdout/jsonl`, `audit.py` | Emits decision audit events | JSONL is not immutable enterprise audit |
| Billing ledger | `APP_BILLING_MODE=ledger_required`, `billing_ledger.py` | Requires upstream usage tokens and writes a reference ledger entry | Not a real invoice/reconciliation pipeline |
| Security posture | `APP_SECURITY_POSTURE_MODE=audit/enforce`, `security_posture.py` | Blocks unsafe production-like posture in enforce mode | Heuristic checks, not full cloud compliance |
| SLO metrics | `/metrics`, `slo_metrics.py` | Exposes request/latency/upstream-status metrics | No TTFT/GPU autoscaling loop yet |
| KV-cache isolation intent | `runtime_isolation` registry block | Carries tenant isolation intent as internal headers | Does not prove vLLM KV-cache isolation |

Detailed notes are in [`docs/08-implemented-hardening.md`](docs/08-implemented-hardening.md).

## Local demo

Install dependencies:

```bash
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

Run the gateway in local mock mode:

```bash
APP_TENANT_REGISTRY_PATH=./config/tenants.yaml \
APP_AUTH_MODE=mock \
APP_ENVIRONMENT=local \
APP_MOCK_UPSTREAM=true \
PYTHONPATH=src \
uvicorn tenant_policy_gateway.main:app --reload --host 0.0.0.0 --port 8080
```

Send demo requests:

```bash
make demo-a
make demo-b
make demo-cross
make demo-lora
make demo-spoof
```

Mock auth accepts local demo credentials such as:

```text
Authorization: Bearer mock:tenant-a:user-123
```

or, when enabled:

```text
x-mock-auth: tenant=tenant-a;user=user-123
```

Mock mode is **not production authentication**. The application now fails configuration validation if `APP_AUTH_MODE=mock` is used outside `local`, `dev`, `development`, `test`, or `ci`, unless `APP_UNSAFE_ALLOW_MOCK_AUTH_OUTSIDE_LOCAL=true` is explicitly set for a throwaway demo.

## Run tests

```bash
make test
```

or directly:

```bash
PYTHONPATH=src pytest -q
```

Test coverage includes:

- valid tenant A request,
- valid tenant B request,
- tenant A token against tenant B domain denied,
- forbidden LoRA adapter denied,
- unknown model denied,
- spoofed routing headers stripped and ignored,
- missing token denied,
- metering event emitted with non-billing-grade token source,
- fail-closed registry load failure,
- mock auth rejected outside local/dev/test/ci by default,
- in-memory quota denial,
- adapter catalog governance allow/deny,
- JSONL audit sink,
- ledger-required billing path,
- `/metrics` endpoint,
- security posture enforce mode.

## Real OIDC/JWKS mode

Set:

```bash
APP_AUTH_MODE=oidc
```

Each tenant config must include issuer, audience, tenant claim, user claim, and JWKS URL:

```yaml
oidc_issuer: https://issuer.example.local/tenant-a
oidc_audience: aibrix-gateway
oidc_jwks_url: https://issuer.example.local/tenant-a/jwks.json
tenant_claim: tenant_id
user_claim: sub
```

This reference implementation uses PyJWT/JWKS validation. Production systems should add explicit OIDC discovery lifecycle, JWKS caching policy, issuer onboarding controls, key-rotation tests, revocation semantics, outage playbooks, and audit trails.

## Metering and billing ledger modes

The gateway emits structured JSON events containing tenant, user, domain, model, adapter, decision, status, latency, upstream status, and token fields.

Default metering remains observability-oriented. Input token counts are best-effort estimates unless upstream usage is available. The event includes token source and `*_billing_grade=false` fields to avoid pretending local estimates are invoice-grade.

For stricter demos, set `APP_BILLING_MODE=ledger_required`. In that mode, the gateway requires upstream `usage.prompt_tokens`, `usage.completion_tokens`, and `usage.total_tokens`. If usage is missing or inconsistent, the gateway returns `502 billing_usage_missing`; if usage is valid, it writes a JSONL reference ledger record.

This is still not enterprise billing. Production billing would require model-specific tokenizer/version controls, usage reconciliation, idempotent event processing, durable external ledger storage, replay protection, and auditability.

## Kubernetes layout

```text
k8s/
  gateway-api/              # Gateway and HTTPRoute examples
  tenant-policy-gateway/    # Deployment, Service, ConfigMap, Secret placeholder, NetworkPolicy
  aibrix/                   # AIBrix-facing Service placeholder
  tenants/                  # Example namespaces, quotas, policies
```

## AWS EKS adaptation

For AWS EKS, the intended shape is:

- public or private ALB terminates TLS and forwards to Envoy Gateway / Gateway API,
- Tenant Policy Gateway runs in private subnets,
- AIBrix/vLLM services run behind cluster-internal Services,
- ECR hosts container images,
- Secrets Manager + ASCP or External Secrets injects OIDC config,
- Pod Identity or IRSA grants least-privilege AWS access,
- Karpenter provisions GPU node pools for AIBrix/vLLM,
- S3 stores model or adapter artifacts if your serving stack needs it,
- CloudWatch and/or OpenTelemetry collects structured gateway events.

These files are examples, not an enterprise landing zone. See [`docs/04-aws-eks-reference.md`](docs/04-aws-eks-reference.md).

## Repository structure

```text
aibrix-multitenant-llm-gateway/
├── README.md
├── config/
│   └── tenants.yaml
├── docs/
├── examples/
├── k8s/
├── prompts/
├── src/tenant_policy_gateway/
├── Makefile
├── pyproject.toml
└── requirements.txt
```

## Correct positioning

This repo is still not a production-ready LLM gateway.

It is a **production-inspired reference architecture** showing where to start when adding SaaS governance in front of AIBrix/vLLM. The second hardening layer adds real code-level hooks for quota, audit, billing-required mode, adapter catalog enforcement, security posture checks, and metrics, but those are still reference implementations unless backed by production infrastructure and validation.
