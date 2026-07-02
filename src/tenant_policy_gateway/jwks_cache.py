from __future__ import annotations

from dataclasses import dataclass
from threading import Lock
import time
from typing import Any

from jwt import PyJWKClient


@dataclass
class _CachedJwksClient:
    client: PyJWKClient
    expires_at: float


class JwksClientCache:
    """Small in-process JWKS client cache.

    This prevents creating a new PyJWKClient object for every request. It is not
    a replacement for full IdP lifecycle management, but it demonstrates the
    cache/TTL boundary expected in production OIDC validation.
    """

    def __init__(self, *, ttl_seconds: int) -> None:
        self.ttl_seconds = ttl_seconds
        self._lock = Lock()
        self._clients: dict[str, _CachedJwksClient] = {}

    def get(self, jwks_url: str) -> PyJWKClient:
        now = time.time()
        with self._lock:
            cached = self._clients.get(jwks_url)
            if cached is not None and cached.expires_at > now:
                return cached.client
            client = PyJWKClient(jwks_url)
            self._clients[jwks_url] = _CachedJwksClient(client=client, expires_at=now + self.ttl_seconds)
            return client

    def clear(self) -> None:
        with self._lock:
            self._clients.clear()


_DEFAULT_CACHE = JwksClientCache(ttl_seconds=300)


def get_jwks_client(jwks_url: str, *, ttl_seconds: int) -> PyJWKClient:
    global _DEFAULT_CACHE
    if _DEFAULT_CACHE.ttl_seconds != ttl_seconds:
        _DEFAULT_CACHE = JwksClientCache(ttl_seconds=ttl_seconds)
    return _DEFAULT_CACHE.get(jwks_url)
