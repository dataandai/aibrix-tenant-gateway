from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Any

import yaml
from pydantic import BaseModel, ConfigDict, Field, ValidationError, field_validator, model_validator


class RegistryLoadError(RuntimeError):
    """Raised when tenant configuration cannot be loaded or validated."""


class TenantLimits(BaseModel):
    requests_per_minute: int | None = Field(default=None, ge=1)
    input_tokens_per_minute: int | None = Field(default=None, ge=1)
    output_tokens_per_minute: int | None = Field(default=None, ge=1)
    concurrent_requests: int | None = Field(default=None, ge=1)


class ModelPolicy(BaseModel):
    allowed_lora_adapters: list[str] = Field(default_factory=list)




class AdapterArtifactPolicy(BaseModel):
    model_config = ConfigDict(extra="forbid")

    artifact_uri: str
    sha256: str
    signed_by: str | None = None
    status: str = "active"
    compatible_models: list[str]

    @field_validator("status")
    @classmethod
    def validate_status(cls, value: str) -> str:
        normalized = value.strip().lower()
        if normalized not in {"active", "deprecated", "quarantined"}:
            raise ValueError("adapter status must be active, deprecated, or quarantined")
        return normalized


class RuntimeIsolationPolicy(BaseModel):
    model_config = ConfigDict(extra="forbid")

    mode: str = "shared_pool"
    kv_cache_isolation_required: bool = False
    kv_cache_isolation_proven: bool = False
    evidence: str | None = None

    @model_validator(mode="after")
    def require_evidence_when_proven(self) -> "RuntimeIsolationPolicy":
        if self.kv_cache_isolation_proven and not self.evidence:
            raise ValueError("kv_cache_isolation_proven=true requires evidence")
        return self


class TenantConfig(BaseModel):
    model_config = ConfigDict(extra="forbid")

    tenant_id: str
    domains: list[str]
    oidc_issuer: str
    oidc_audience: str
    oidc_jwks_url: str | None = None
    tenant_claim: str = "tenant_id"
    user_claim: str = "sub"
    routing_external_filter: str = "tenant={tenant_id}"
    config_profile: str = "standard"
    user_header_template: str = "{tenant_id}:{user_id}"
    limits: TenantLimits = Field(default_factory=TenantLimits)
    runtime_isolation: RuntimeIsolationPolicy = Field(default_factory=RuntimeIsolationPolicy)
    adapter_artifacts: dict[str, AdapterArtifactPolicy] = Field(default_factory=dict)
    allowed_models: dict[str, ModelPolicy]

    @field_validator("domains")
    @classmethod
    def lower_domains(cls, values: list[str]) -> list[str]:
        cleaned = [value.strip().lower() for value in values if value.strip()]
        if not cleaned:
            raise ValueError("at least one domain is required")
        return cleaned

    @field_validator("allowed_models")
    @classmethod
    def require_models(cls, values: dict[str, ModelPolicy]) -> dict[str, ModelPolicy]:
        if not values:
            raise ValueError("at least one allowed model is required")
        return values


class TenantRegistryDocument(BaseModel):
    model_config = ConfigDict(extra="forbid")

    tenants: list[TenantConfig]


@dataclass(frozen=True)
class TenantRegistry:
    tenants_by_id: dict[str, TenantConfig]
    tenants_by_domain: dict[str, TenantConfig]

    @classmethod
    def load(cls, path: Path) -> "TenantRegistry":
        if not path.exists():
            raise RegistryLoadError(f"Tenant registry does not exist: {path}")
        try:
            data: Any = yaml.safe_load(path.read_text(encoding="utf-8"))
            document = TenantRegistryDocument.model_validate(data)
        except (OSError, yaml.YAMLError, ValidationError, TypeError) as exc:
            raise RegistryLoadError(f"Could not load tenant registry: {exc}") from exc

        tenants_by_id: dict[str, TenantConfig] = {}
        tenants_by_domain: dict[str, TenantConfig] = {}
        for tenant in document.tenants:
            if tenant.tenant_id in tenants_by_id:
                raise RegistryLoadError(f"Duplicate tenant_id: {tenant.tenant_id}")
            tenants_by_id[tenant.tenant_id] = tenant
            for domain in tenant.domains:
                if domain in tenants_by_domain:
                    owner = tenants_by_domain[domain].tenant_id
                    raise RegistryLoadError(
                        f"Domain {domain!r} maps to multiple tenants: {owner}, {tenant.tenant_id}"
                    )
                tenants_by_domain[domain] = tenant
        return cls(tenants_by_id=tenants_by_id, tenants_by_domain=tenants_by_domain)

    def resolve_by_host(self, host_header: str | None) -> TenantConfig | None:
        if not host_header:
            return None
        # Strip port if present; support IPv6 literals conservatively by only stripping :port for normal hostnames.
        host = host_header.strip().lower()
        if host.count(":") == 1:
            host = host.split(":", 1)[0]
        return self.tenants_by_domain.get(host)
