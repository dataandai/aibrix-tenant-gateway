from __future__ import annotations

from dataclasses import asdict, dataclass
import json
import logging

from .config import (
    AdapterGovernanceMode,
    AppSettings,
    AuditSinkMode,
    AuthMode,
    BillingMode,
    QuotaMode,
    SecurityPostureMode,
)

logger = logging.getLogger("tenant_policy_gateway.security")


@dataclass(frozen=True)
class SecurityFinding:
    severity: str
    code: str
    message: str


def evaluate_security_posture(settings: AppSettings) -> list[SecurityFinding]:
    findings: list[SecurityFinding] = []
    environment = settings.environment.strip().lower()
    production_like = environment in {"prod", "production", "stage", "staging"}

    if settings.auth_mode == AuthMode.MOCK:
        findings.append(SecurityFinding("critical", "mock_auth_enabled", "Mock auth is local/demo only."))
    if settings.mock_upstream and production_like:
        findings.append(SecurityFinding("critical", "mock_upstream_enabled", "Mock upstream cannot serve production traffic."))
    if settings.quota_mode == QuotaMode.DISABLED and production_like:
        findings.append(SecurityFinding("high", "quota_disabled", "Runtime quota enforcement is disabled."))
    if settings.quota_mode == QuotaMode.IN_MEMORY and production_like:
        findings.append(
            SecurityFinding(
                "high",
                "quota_in_memory_not_distributed",
                "In-memory quota is not valid for multi-replica or production-like deployments.",
            )
        )
    if settings.billing_mode == BillingMode.DISABLED and production_like:
        findings.append(SecurityFinding("high", "billing_disabled", "No billing ledger is configured."))
    if settings.audit_sink == AuditSinkMode.DISABLED and production_like:
        findings.append(SecurityFinding("high", "audit_disabled", "Audit sink is disabled."))
    if settings.adapter_governance_mode != AdapterGovernanceMode.CATALOG_ENFORCED and production_like:
        findings.append(
            SecurityFinding("medium", "adapter_catalog_not_enforced", "LoRA governance is allowlist-only.")
        )
    if settings.require_private_upstream and not _looks_private_upstream(settings.upstream_base_url):
        findings.append(
            SecurityFinding(
                "critical",
                "upstream_not_private",
                "AIBrix upstream URL does not look like an internal Kubernetes/private endpoint.",
            )
        )
    return findings


def emit_security_posture(findings: list[SecurityFinding]) -> None:
    for finding in findings:
        logger.warning(json.dumps({"event": "security_posture_finding", **asdict(finding)}, sort_keys=True))


def enforce_security_posture(settings: AppSettings, findings: list[SecurityFinding]) -> str | None:
    if settings.security_posture_mode != SecurityPostureMode.ENFORCE:
        return None
    blocking = [finding for finding in findings if finding.severity in {"critical", "high"}]
    if not blocking:
        return None
    return ",".join(finding.code for finding in blocking)


def _looks_private_upstream(url: str) -> bool:
    normalized = url.lower()
    return any(
        marker in normalized
        for marker in [
            ".svc",
            ".cluster.local",
            "localhost",
            "127.0.0.1",
            "10.",
            "192.168.",
            "172.16.",
            "172.17.",
            "172.18.",
            "172.19.",
            "172.20.",
            "172.21.",
            "172.22.",
            "172.23.",
            "172.24.",
            "172.25.",
            "172.26.",
            "172.27.",
            "172.28.",
            "172.29.",
            "172.30.",
            "172.31.",
        ]
    )
