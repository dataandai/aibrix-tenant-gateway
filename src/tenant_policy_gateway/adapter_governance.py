from __future__ import annotations

from dataclasses import dataclass

from .config import AdapterGovernanceMode
from .tenant_registry import TenantConfig


@dataclass(frozen=True)
class AdapterGovernanceDecision:
    allowed: bool
    status_code: int
    reason: str


ALLOWLIST_ONLY_DECISION = AdapterGovernanceDecision(True, 200, "adapter_allowlist_only")


def evaluate_adapter_governance(
    *,
    tenant: TenantConfig,
    model: str,
    adapter: str | None,
    mode: AdapterGovernanceMode,
) -> AdapterGovernanceDecision:
    """Validate adapter artifact metadata when catalog enforcement is enabled.

    The policy engine already checks that the adapter name is allowed for the
    tenant/model pair. This layer adds reference checks for artifact provenance,
    status, and model compatibility. It is still not a full artifact signing or
    malware scanning pipeline.
    """

    if adapter is None:
        return AdapterGovernanceDecision(True, 200, "no_adapter_requested")
    if mode == AdapterGovernanceMode.ALLOWLIST_ONLY:
        return ALLOWLIST_ONLY_DECISION

    artifact = tenant.adapter_artifacts.get(adapter)
    if artifact is None:
        return AdapterGovernanceDecision(False, 403, "adapter_not_governed")
    if artifact.status != "active":
        return AdapterGovernanceDecision(False, 403, f"adapter_{artifact.status}")
    if model not in artifact.compatible_models:
        return AdapterGovernanceDecision(False, 403, "adapter_model_incompatible")
    if not artifact.sha256 or len(artifact.sha256) < 32:
        return AdapterGovernanceDecision(False, 403, "adapter_checksum_missing")
    if not artifact.signed_by:
        return AdapterGovernanceDecision(False, 403, "adapter_signature_missing")
    return AdapterGovernanceDecision(True, 200, "adapter_governed")
