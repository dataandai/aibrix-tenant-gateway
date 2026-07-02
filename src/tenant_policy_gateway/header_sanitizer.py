from __future__ import annotations

from collections.abc import Mapping

CLIENT_SUPPLIED_ROUTING_HEADERS = {
    "x-tenant-id",
    "x-user-id",
    "x-tier",
    "user",
    "external-filter",
    "config-profile",
    "x-internal-tenant-id",
    "x-internal-user-id",
    "x-internal-slo-tier",
}

# Headers that should not be proxied from public clients to AIBrix/vLLM.
# Authorization is intentionally removed; AIBrix receives policy-derived identity only.
HOP_BY_HOP_OR_SENSITIVE_HEADERS = {
    "authorization",
    "connection",
    "keep-alive",
    "proxy-authenticate",
    "proxy-authorization",
    "te",
    "trailer",
    "transfer-encoding",
    "upgrade",
    "host",
    "content-length",
}


def sanitize_inbound_headers(headers: Mapping[str, str]) -> dict[str, str]:
    """Return headers safe to forward after removing spoofable routing and sensitive headers."""

    sanitized: dict[str, str] = {}
    blocked = CLIENT_SUPPLIED_ROUTING_HEADERS | HOP_BY_HOP_OR_SENSITIVE_HEADERS
    for key, value in headers.items():
        lower_key = key.lower()
        if lower_key in blocked:
            continue
        sanitized[key] = value
    return sanitized


def routing_headers_were_supplied(headers: Mapping[str, str]) -> bool:
    return any(key.lower() in CLIENT_SUPPLIED_ROUTING_HEADERS for key in headers)


def inject_trusted_headers(
    *,
    headers: Mapping[str, str],
    tenant_id: str,
    user_id: str,
    user_header_value: str,
    external_filter: str,
    config_profile: str,
) -> dict[str, str]:
    outbound = dict(headers)
    outbound.update(
        {
            "user": user_header_value,
            "external-filter": external_filter,
            "config-profile": config_profile,
            "x-internal-tenant-id": tenant_id,
            "x-internal-user-id": user_id,
        }
    )
    return outbound
