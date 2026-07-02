from __future__ import annotations

from dataclasses import dataclass
from typing import Any

import jwt

from .config import AppSettings, AuthMode
from .jwks_cache import get_jwks_client
from .tenant_registry import TenantConfig


class AuthError(RuntimeError):
    def __init__(self, reason: str, detail: str | None = None) -> None:
        super().__init__(detail or reason)
        self.reason = reason
        self.detail = detail or reason


@dataclass(frozen=True)
class AuthenticatedPrincipal:
    tenant_id: str
    user_id: str
    claims: dict[str, Any]
    auth_mode: AuthMode


def _extract_bearer_token(authorization: str | None) -> str:
    if not authorization:
        raise AuthError("missing_token", "Missing Authorization bearer token")
    scheme, _, token = authorization.partition(" ")
    if scheme.lower() != "bearer" or not token:
        raise AuthError("invalid_token", "Authorization must be a bearer token")
    return token.strip()


def _parse_mock_header(header_value: str) -> tuple[str, str]:
    parts: dict[str, str] = {}
    for segment in header_value.split(";"):
        key, separator, value = segment.partition("=")
        if separator:
            parts[key.strip().lower()] = value.strip()
    tenant_id = parts.get("tenant") or parts.get("tenant_id")
    user_id = parts.get("user") or parts.get("user_id")
    if not tenant_id or not user_id:
        raise AuthError("invalid_mock_header", "x-mock-auth must include tenant and user")
    return tenant_id, user_id


def validate_request_auth(
    *,
    authorization: str | None,
    mock_auth_header: str | None,
    tenant: TenantConfig,
    settings: AppSettings,
) -> AuthenticatedPrincipal:
    if settings.auth_mode == AuthMode.MOCK:
        return _validate_mock_auth(
            authorization=authorization,
            mock_auth_header=mock_auth_header,
            tenant=tenant,
            settings=settings,
        )
    return _validate_oidc_auth(authorization=authorization, tenant=tenant, settings=settings)


def _validate_mock_auth(
    *,
    authorization: str | None,
    mock_auth_header: str | None,
    tenant: TenantConfig,
    settings: AppSettings,
) -> AuthenticatedPrincipal:
    if mock_auth_header and settings.allow_mock_auth_header:
        tenant_id, user_id = _parse_mock_header(mock_auth_header)
        return AuthenticatedPrincipal(
            tenant_id=tenant_id,
            user_id=user_id,
            claims={tenant.tenant_claim: tenant_id, tenant.user_claim: user_id, "mock": True},
            auth_mode=AuthMode.MOCK,
        )

    token = _extract_bearer_token(authorization)
    # Local demo format only: Bearer mock:<tenant_id>:<user_id>
    if not token.startswith("mock:"):
        raise AuthError("invalid_mock_token", "Mock mode accepts only mock:<tenant_id>:<user_id> tokens")
    parts = token.split(":", 2)
    if len(parts) != 3 or not parts[1] or not parts[2]:
        raise AuthError("invalid_mock_token", "Mock token must be mock:<tenant_id>:<user_id>")
    tenant_id = parts[1]
    user_id = parts[2]
    return AuthenticatedPrincipal(
        tenant_id=tenant_id,
        user_id=user_id,
        claims={tenant.tenant_claim: tenant_id, tenant.user_claim: user_id, "mock": True},
        auth_mode=AuthMode.MOCK,
    )


def _validate_oidc_auth(
    *,
    authorization: str | None,
    tenant: TenantConfig,
    settings: AppSettings,
) -> AuthenticatedPrincipal:
    token = _extract_bearer_token(authorization)
    if not tenant.oidc_jwks_url:
        raise AuthError("jwks_not_configured", "Tenant OIDC JWKS URL is required in oidc mode")

    try:
        jwks_client = get_jwks_client(tenant.oidc_jwks_url, ttl_seconds=settings.jwks_cache_ttl_seconds)
        signing_key = jwks_client.get_signing_key_from_jwt(token)
        required_claims = ["exp", "iat"]
        if settings.oidc_require_nbf:
            required_claims.append("nbf")
        claims = jwt.decode(
            token,
            signing_key.key,
            algorithms=settings.oidc_algorithms,
            audience=tenant.oidc_audience,
            issuer=tenant.oidc_issuer,
            leeway=settings.oidc_leeway_seconds,
            options={"require": required_claims},
        )
        _enforce_required_oidc_claims(claims=claims, tenant=tenant, settings=settings)
    except AuthError:
        raise
    except jwt.PyJWTError as exc:
        raise AuthError("invalid_token", "OIDC token validation failed") from exc

    tenant_id = claims.get(tenant.tenant_claim)
    user_id = claims.get(tenant.user_claim) or claims.get("sub")
    if not isinstance(tenant_id, str) or not tenant_id:
        raise AuthError("tenant_claim_missing", f"Missing tenant claim {tenant.tenant_claim!r}")
    if not isinstance(user_id, str) or not user_id:
        raise AuthError("user_claim_missing", f"Missing user claim {tenant.user_claim!r}")
    return AuthenticatedPrincipal(
        tenant_id=tenant_id,
        user_id=user_id,
        claims=claims,
        auth_mode=AuthMode.OIDC,
    )


def _enforce_required_oidc_claims(*, claims: dict[str, Any], tenant: TenantConfig, settings: AppSettings) -> None:
    if settings.oidc_required_token_use is not None:
        if claims.get("token_use") != settings.oidc_required_token_use:
            raise AuthError("invalid_token_use", "OIDC token_use claim did not match required value")

    if settings.oidc_required_scopes:
        token_scopes = set(_split_claim_values(claims.get("scope")))
        missing = [scope for scope in settings.oidc_required_scopes if scope not in token_scopes]
        if missing:
            raise AuthError("required_scope_missing", "OIDC token is missing required scope")

    if settings.oidc_required_groups:
        token_groups = set(_split_claim_values(claims.get("cognito:groups") or claims.get("groups")))
        missing = [group for group in settings.oidc_required_groups if group not in token_groups]
        if missing:
            raise AuthError("required_group_missing", "OIDC token is missing required group")

    # Defense-in-depth: prevent accepting tokens where the tenant claim is present
    # but not a scalar string. The policy engine later compares this value to Host resolution.
    tenant_value = claims.get(tenant.tenant_claim)
    if tenant_value is not None and not isinstance(tenant_value, str):
        raise AuthError("tenant_claim_invalid", "Tenant claim must be a string")


def _split_claim_values(value: Any) -> list[str]:
    if value is None:
        return []
    if isinstance(value, str):
        return [part for part in value.split() if part]
    if isinstance(value, list):
        return [str(part) for part in value if str(part)]
    return []
