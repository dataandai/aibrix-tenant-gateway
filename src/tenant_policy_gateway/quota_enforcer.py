from __future__ import annotations

from collections import defaultdict, deque
from dataclasses import dataclass
import time
from typing import Protocol

from .config import AppSettings, QuotaMode
from .tenant_registry import TenantLimits


@dataclass(frozen=True)
class QuotaDecision:
    allowed: bool
    status_code: int
    reason: str
    retry_after_seconds: int | None = None


@dataclass(frozen=True)
class UsageRecord:
    timestamp: float
    input_tokens: int
    output_tokens: int = 0


class QuotaEnforcer(Protocol):
    def check_and_record(
        self,
        *,
        tenant_id: str,
        user_id: str,
        limits: TenantLimits,
        estimated_input_tokens: int | None,
        now: float | None = None,
    ) -> QuotaDecision: ...

    def finish_request(self, *, tenant_id: str, user_id: str) -> None: ...


class InMemoryQuotaEnforcer:
    """Small per-process quota enforcer for local/reference use.

    This is intentionally not production-grade. It does not coordinate across
    pods, nodes, regions, or retries. Full-stack AWS deployments should use a
    distributed backend such as Redis/ElastiCache or Envoy Rate Limit Service.
    """

    def __init__(self, *, window_seconds: int = 60) -> None:
        self.window_seconds = window_seconds
        self._records: dict[tuple[str, str], deque[UsageRecord]] = defaultdict(deque)
        self._active: dict[tuple[str, str], int] = defaultdict(int)

    def check_and_record(
        self,
        *,
        tenant_id: str,
        user_id: str,
        limits: TenantLimits,
        estimated_input_tokens: int | None,
        now: float | None = None,
    ) -> QuotaDecision:
        now = now if now is not None else time.time()
        key = (tenant_id, user_id)
        records = self._records[key]
        self._drop_expired(records, now)

        request_count = len(records)
        input_tokens = sum(record.input_tokens for record in records)
        candidate_input_tokens = max(0, estimated_input_tokens or 0)

        if limits.concurrent_requests is not None and self._active[key] >= limits.concurrent_requests:
            return QuotaDecision(False, 429, "concurrency_quota_exceeded", 1)
        if limits.requests_per_minute is not None and request_count >= limits.requests_per_minute:
            return QuotaDecision(False, 429, "request_quota_exceeded", self._retry_after(records, now))
        if (
            limits.input_tokens_per_minute is not None
            and input_tokens + candidate_input_tokens > limits.input_tokens_per_minute
        ):
            return QuotaDecision(False, 429, "input_token_quota_exceeded", self._retry_after(records, now))

        records.append(UsageRecord(timestamp=now, input_tokens=candidate_input_tokens))
        self._active[key] += 1
        return QuotaDecision(True, 200, "quota_allowed")

    def finish_request(self, *, tenant_id: str, user_id: str) -> None:
        key = (tenant_id, user_id)
        if self._active[key] > 0:
            self._active[key] -= 1

    def _drop_expired(self, records: deque[UsageRecord], now: float) -> None:
        cutoff = now - self.window_seconds
        while records and records[0].timestamp <= cutoff:
            records.popleft()

    def _retry_after(self, records: deque[UsageRecord], now: float) -> int:
        if not records:
            return self.window_seconds
        age = now - records[0].timestamp
        return max(1, int(self.window_seconds - age))


_REDIS_CHECK_AND_RECORD_LUA = r"""
local user_requests_key = KEYS[1]
local user_input_key = KEYS[2]
local tenant_requests_key = KEYS[3]
local tenant_input_key = KEYS[4]
local user_concurrency_key = KEYS[5]
local tenant_concurrency_key = KEYS[6]

local ttl = tonumber(ARGV[1])
local candidate_input_tokens = tonumber(ARGV[2])
local user_request_limit = tonumber(ARGV[3])
local user_input_limit = tonumber(ARGV[4])
local user_concurrency_limit = tonumber(ARGV[5])
local tenant_request_limit = tonumber(ARGV[6])
local tenant_input_limit = tonumber(ARGV[7])
local tenant_concurrency_limit = tonumber(ARGV[8])

local user_requests = tonumber(redis.call('GET', user_requests_key) or '0')
local user_input = tonumber(redis.call('GET', user_input_key) or '0')
local tenant_requests = tonumber(redis.call('GET', tenant_requests_key) or '0')
local tenant_input = tonumber(redis.call('GET', tenant_input_key) or '0')
local user_concurrency = tonumber(redis.call('GET', user_concurrency_key) or '0')
local tenant_concurrency = tonumber(redis.call('GET', tenant_concurrency_key) or '0')

if user_concurrency_limit >= 0 and user_concurrency >= user_concurrency_limit then
  return {0, 'concurrency_quota_exceeded', ttl}
end
if tenant_concurrency_limit >= 0 and tenant_concurrency >= tenant_concurrency_limit then
  return {0, 'tenant_concurrency_quota_exceeded', ttl}
end
if user_request_limit >= 0 and user_requests + 1 > user_request_limit then
  return {0, 'request_quota_exceeded', ttl}
end
if tenant_request_limit >= 0 and tenant_requests + 1 > tenant_request_limit then
  return {0, 'tenant_request_quota_exceeded', ttl}
end
if user_input_limit >= 0 and user_input + candidate_input_tokens > user_input_limit then
  return {0, 'input_token_quota_exceeded', ttl}
end
if tenant_input_limit >= 0 and tenant_input + candidate_input_tokens > tenant_input_limit then
  return {0, 'tenant_input_token_quota_exceeded', ttl}
end

redis.call('INCR', user_requests_key)
redis.call('INCRBY', user_input_key, candidate_input_tokens)
redis.call('INCR', tenant_requests_key)
redis.call('INCRBY', tenant_input_key, candidate_input_tokens)
redis.call('INCR', user_concurrency_key)
redis.call('INCR', tenant_concurrency_key)
redis.call('EXPIRE', user_requests_key, ttl)
redis.call('EXPIRE', user_input_key, ttl)
redis.call('EXPIRE', tenant_requests_key, ttl)
redis.call('EXPIRE', tenant_input_key, ttl)
redis.call('EXPIRE', user_concurrency_key, ttl)
redis.call('EXPIRE', tenant_concurrency_key, ttl)
return {1, 'quota_allowed', 0}
"""

_REDIS_FINISH_LUA = r"""
local user_concurrency_key = KEYS[1]
local tenant_concurrency_key = KEYS[2]
local user_current = tonumber(redis.call('GET', user_concurrency_key) or '0')
local tenant_current = tonumber(redis.call('GET', tenant_concurrency_key) or '0')
if user_current > 0 then redis.call('DECR', user_concurrency_key) end
if tenant_current > 0 then redis.call('DECR', tenant_concurrency_key) end
return {math.max(user_current - 1, 0), math.max(tenant_current - 1, 0)}
"""


class RedisQuotaEnforcer:
    """Redis-backed quota reference implementation using Lua for atomicity.

    It enforces user-level and tenant-level request/input-token/concurrency
    limits in one script, avoiding the PR8 increment-before-check bug. This is
    still a reference implementation: production systems normally add output
    token budgets, regional replication, circuit breaking, dashboards, and load
    tests against the exact Redis/ElastiCache topology.
    """

    def __init__(self, *, redis_url: str, window_seconds: int = 60, key_prefix: str = "aibrix-gateway") -> None:
        try:
            import redis  # type: ignore
        except ImportError as exc:  # pragma: no cover - exercised only when redis mode is selected without dependency
            raise RuntimeError("APP_QUOTA_MODE=redis requires redis>=5 to be installed") from exc
        self.window_seconds = window_seconds
        self.key_prefix = key_prefix.rstrip(":")
        self.client = redis.Redis.from_url(redis_url, decode_responses=True)
        self._check_sha = self.client.script_load(_REDIS_CHECK_AND_RECORD_LUA)
        self._finish_sha = self.client.script_load(_REDIS_FINISH_LUA)

    def check_and_record(
        self,
        *,
        tenant_id: str,
        user_id: str,
        limits: TenantLimits,
        estimated_input_tokens: int | None,
        now: float | None = None,
    ) -> QuotaDecision:
        del now  # Redis TTL is authoritative for distributed mode.
        candidate_input_tokens = max(0, estimated_input_tokens or 0)
        minute_bucket = int(time.time() // self.window_seconds)
        tenant_base = f"{self.key_prefix}:quota:tenant:{tenant_id}:{minute_bucket}"
        user_base = f"{self.key_prefix}:quota:user:{tenant_id}:{user_id}:{minute_bucket}"
        concurrency_base = f"{self.key_prefix}:concurrency"
        keys = [
            f"{user_base}:requests",
            f"{user_base}:input_tokens",
            f"{tenant_base}:requests",
            f"{tenant_base}:input_tokens",
            f"{concurrency_base}:user:{tenant_id}:{user_id}",
            f"{concurrency_base}:tenant:{tenant_id}",
        ]
        args = [
            self.window_seconds + 5,
            candidate_input_tokens,
            _limit_arg(limits.requests_per_minute),
            _limit_arg(limits.input_tokens_per_minute),
            _limit_arg(limits.concurrent_requests),
            _limit_arg(limits.requests_per_minute),
            _limit_arg(limits.input_tokens_per_minute),
            _limit_arg(limits.concurrent_requests),
        ]
        allowed, reason, retry_after = self.client.evalsha(self._check_sha, len(keys), *keys, *args)
        if int(allowed) == 1:
            return QuotaDecision(True, 200, str(reason))
        return QuotaDecision(False, 429, str(reason), int(retry_after))

    def finish_request(self, *, tenant_id: str, user_id: str) -> None:
        keys = [
            f"{self.key_prefix}:concurrency:user:{tenant_id}:{user_id}",
            f"{self.key_prefix}:concurrency:tenant:{tenant_id}",
        ]
        self.client.evalsha(self._finish_sha, len(keys), *keys)


def _limit_arg(value: int | None) -> int:
    return int(value) if value is not None else -1


def create_quota_enforcer(settings: AppSettings) -> QuotaEnforcer | None:
    if settings.quota_mode == QuotaMode.DISABLED:
        return None
    if settings.quota_mode == QuotaMode.IN_MEMORY:
        return InMemoryQuotaEnforcer(window_seconds=settings.quota_window_seconds)
    if settings.quota_mode == QuotaMode.REDIS:
        return RedisQuotaEnforcer(
            redis_url=settings.redis_quota_url,
            window_seconds=settings.quota_window_seconds,
            key_prefix=settings.redis_quota_key_prefix,
        )
    raise ValueError(f"Unsupported quota mode: {settings.quota_mode}")
