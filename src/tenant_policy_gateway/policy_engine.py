from __future__ import annotations

from dataclasses import dataclass
from typing import Any

from .jwt_validation import AuthenticatedPrincipal
from .tenant_registry import TenantConfig, TenantRegistry


@dataclass(frozen=True)
class RequestAttributes:
    domain: str | None
    model: str | None
    adapter: str | None


@dataclass(frozen=True)
class PolicyDecision:
    allowed: bool
    status_code: int
    reason: str
    tenant: TenantConfig | None = None
    tenant_id: str | None = None
    user_id: str | None = None
    model: str | None = None
    adapter: str | None = None


def extract_adapter(request_body: dict[str, Any]) -> str | None:
    """Extract a LoRA adapter name from common demo shapes.

    This is deliberately conservative. Production systems should normalize adapter
    identity in a stable API contract rather than accepting every vendor-specific field.
    """

    candidates = [
        request_body.get("lora_adapter"),
        request_body.get("adapter"),
        request_body.get("lora"),
    ]
    metadata = request_body.get("metadata")
    if isinstance(metadata, dict):
        candidates.append(metadata.get("lora_adapter"))
        candidates.append(metadata.get("adapter"))
    for candidate in candidates:
        if isinstance(candidate, str) and candidate.strip():
            return candidate.strip()
    return None


def request_attributes_from_body(domain: str | None, request_body: dict[str, Any]) -> RequestAttributes:
    model = request_body.get("model")
    return RequestAttributes(
        domain=domain.lower() if domain else None,
        model=model.strip() if isinstance(model, str) and model.strip() else None,
        adapter=extract_adapter(request_body),
    )


def evaluate_policy(
    *,
    registry: TenantRegistry | None,
    attributes: RequestAttributes,
    principal: AuthenticatedPrincipal | None,
    auth_error_reason: str | None,
) -> PolicyDecision:
    if registry is None:
        return PolicyDecision(False, 503, "registry_unavailable")

    tenant = registry.resolve_by_host(attributes.domain)
    if tenant is None:
        return PolicyDecision(False, 403, "unknown_tenant", model=attributes.model, adapter=attributes.adapter)

    if principal is None:
        return PolicyDecision(False, 401, auth_error_reason or "missing_token", tenant=tenant, tenant_id=tenant.tenant_id)

    if principal.tenant_id != tenant.tenant_id:
        return PolicyDecision(
            False,
            403,
            "tenant_claim_mismatch",
            tenant=tenant,
            tenant_id=tenant.tenant_id,
            user_id=principal.user_id,
            model=attributes.model,
            adapter=attributes.adapter,
        )

    if attributes.model is None:
        return PolicyDecision(
            False,
            403,
            "unknown_model",
            tenant=tenant,
            tenant_id=tenant.tenant_id,
            user_id=principal.user_id,
            adapter=attributes.adapter,
        )

    model_policy = tenant.allowed_models.get(attributes.model)
    if model_policy is None:
        return PolicyDecision(
            False,
            403,
            "unknown_model",
            tenant=tenant,
            tenant_id=tenant.tenant_id,
            user_id=principal.user_id,
            model=attributes.model,
            adapter=attributes.adapter,
        )

    if attributes.adapter and attributes.adapter not in model_policy.allowed_lora_adapters:
        return PolicyDecision(
            False,
            403,
            "unknown_adapter",
            tenant=tenant,
            tenant_id=tenant.tenant_id,
            user_id=principal.user_id,
            model=attributes.model,
            adapter=attributes.adapter,
        )

    return PolicyDecision(
        True,
        200,
        "allowed",
        tenant=tenant,
        tenant_id=tenant.tenant_id,
        user_id=principal.user_id,
        model=attributes.model,
        adapter=attributes.adapter,
    )
