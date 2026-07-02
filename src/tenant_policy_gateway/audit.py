from __future__ import annotations

from dataclasses import asdict, dataclass
import json
import logging
from pathlib import Path
from threading import Lock
from typing import Any

from .config import AuditSinkMode

logger = logging.getLogger("tenant_policy_gateway.audit")


@dataclass(frozen=True)
class AuditEvent:
    request_id: str
    tenant_id: str | None
    user_id: str | None
    domain: str | None
    model: str | None
    adapter: str | None
    decision: str
    status_code: int
    reason: str
    auth_mode: str
    quota_mode: str
    adapter_governance_mode: str
    billing_mode: str
    upstream_status_code: int | None = None
    security_boundary_claim: str = "gateway_policy_not_downstream_security_boundary"


class AuditSink:
    """Reference audit sink.

    stdout/jsonl are useful for demos and local tests. Enterprise audit pipelines
    normally need immutable storage, retention policy, SIEM export, idempotency,
    and tamper-evidence outside this process.
    """

    def __init__(self, *, mode: AuditSinkMode, jsonl_path: Path | None = None) -> None:
        self.mode = mode
        self.jsonl_path = jsonl_path
        self._lock = Lock()
        if self.mode == AuditSinkMode.JSONL and self.jsonl_path is None:
            raise ValueError("jsonl audit mode requires jsonl_path")
        if self.jsonl_path is not None:
            self.jsonl_path.parent.mkdir(parents=True, exist_ok=True)

    def emit(self, event: AuditEvent) -> None:
        payload = json.dumps(asdict(event), sort_keys=True, separators=(",", ":"))
        if self.mode == AuditSinkMode.DISABLED:
            return
        if self.mode == AuditSinkMode.STDOUT:
            logger.info(payload)
            return
        assert self.jsonl_path is not None
        with self._lock:
            with self.jsonl_path.open("a", encoding="utf-8") as handle:
                handle.write(payload + "\n")


def audit_event_from_metering(
    *,
    request_id: str,
    tenant_id: str | None,
    user_id: str | None,
    domain: str | None,
    model: str | None,
    adapter: str | None,
    decision: str,
    status_code: int,
    reason: str,
    auth_mode: str,
    quota_mode: str,
    adapter_governance_mode: str,
    billing_mode: str,
    upstream_status_code: int | None = None,
) -> AuditEvent:
    return AuditEvent(
        request_id=request_id,
        tenant_id=tenant_id,
        user_id=user_id,
        domain=domain,
        model=model,
        adapter=adapter,
        decision=decision,
        status_code=status_code,
        reason=reason,
        auth_mode=auth_mode,
        quota_mode=quota_mode,
        adapter_governance_mode=adapter_governance_mode,
        billing_mode=billing_mode,
        upstream_status_code=upstream_status_code,
    )
