from __future__ import annotations

from collections import Counter
from dataclasses import dataclass, field
from threading import Lock


@dataclass
class SloMetrics:
    """Tiny Prometheus-text metrics collector for reference deployments."""

    request_counts: Counter[tuple[str, str, str]] = field(default_factory=Counter)
    upstream_status_counts: Counter[int] = field(default_factory=Counter)
    latency_ms_sum: float = 0.0
    latency_ms_count: int = 0
    ttft_ms_sum: float = 0.0
    ttft_ms_count: int = 0
    stream_completion_token_hints: int = 0
    _lock: Lock = field(default_factory=Lock)

    def record(
        self,
        *,
        tenant_id: str | None,
        decision: str,
        reason: str,
        latency_ms: float,
        upstream_status_code: int | None,
    ) -> None:
        tenant = tenant_id or "unknown"
        with self._lock:
            self.request_counts[(tenant, decision, reason)] += 1
            if upstream_status_code is not None:
                self.upstream_status_counts[upstream_status_code] += 1
            self.latency_ms_sum += latency_ms
            self.latency_ms_count += 1

    def record_stream(self, *, tenant_id: str | None, ttft_ms: float | None, token_count_hint: int) -> None:
        with self._lock:
            if ttft_ms is not None:
                self.ttft_ms_sum += ttft_ms
                self.ttft_ms_count += 1
            self.stream_completion_token_hints += max(0, token_count_hint)

    def prometheus_text(self) -> str:
        lines = [
            "# HELP tenant_policy_gateway_requests_total Requests handled by the policy gateway.",
            "# TYPE tenant_policy_gateway_requests_total counter",
        ]
        with self._lock:
            for (tenant_id, decision, reason), count in sorted(self.request_counts.items()):
                lines.append(
                    'tenant_policy_gateway_requests_total{tenant_id="%s",decision="%s",reason="%s"} %d'
                    % (_escape(tenant_id), _escape(decision), _escape(reason), count)
                )
            lines.extend(
                [
                    "# HELP tenant_policy_gateway_latency_ms_sum Total observed gateway latency in milliseconds.",
                    "# TYPE tenant_policy_gateway_latency_ms_sum counter",
                    f"tenant_policy_gateway_latency_ms_sum {self.latency_ms_sum}",
                    "# HELP tenant_policy_gateway_latency_ms_count Count of latency observations.",
                    "# TYPE tenant_policy_gateway_latency_ms_count counter",
                    f"tenant_policy_gateway_latency_ms_count {self.latency_ms_count}",
                    "# HELP tenant_policy_gateway_ttft_ms_sum Total observed streaming time-to-first-token in milliseconds.",
                    "# TYPE tenant_policy_gateway_ttft_ms_sum counter",
                    f"tenant_policy_gateway_ttft_ms_sum {self.ttft_ms_sum}",
                    "# HELP tenant_policy_gateway_ttft_ms_count Count of TTFT observations.",
                    "# TYPE tenant_policy_gateway_ttft_ms_count counter",
                    f"tenant_policy_gateway_ttft_ms_count {self.ttft_ms_count}",
                    "# HELP tenant_policy_gateway_stream_completion_token_hints_total Token hints seen in streaming responses.",
                    "# TYPE tenant_policy_gateway_stream_completion_token_hints_total counter",
                    f"tenant_policy_gateway_stream_completion_token_hints_total {self.stream_completion_token_hints}",
                    "# HELP tenant_policy_gateway_upstream_status_total Upstream status codes observed.",
                    "# TYPE tenant_policy_gateway_upstream_status_total counter",
                ]
            )
            for status_code, count in sorted(self.upstream_status_counts.items()):
                lines.append(f'tenant_policy_gateway_upstream_status_total{{status_code="{status_code}"}} {count}')
        return "\n".join(lines) + "\n"


def _escape(value: str) -> str:
    return value.replace("\\", "\\\\").replace('"', '\\"')
