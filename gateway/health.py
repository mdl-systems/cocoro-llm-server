#!/usr/bin/env python3
"""
gateway/health.py
全サービス死活監視モジュール

FastAPI エンドポイントから呼び出すか、単体スクリプトとして実行可能。

実行:
  python -m gateway.health
  python gateway/health.py
"""

import asyncio
import logging
import os
import subprocess
import sys
import time
from dataclasses import dataclass
from typing import Optional

import httpx

logger = logging.getLogger(__name__)

# ── サービス定義 ──────────────────────────────────────────────────────────────
SERVICES = {
    "vllm_primary": {
        "url": "http://localhost:8080/health",
        "name": "vLLM Primary (Llama 4 Scout)",
        "timeout": 10,
        "required": True,
    },
    "vllm_secondary": {
        "url": "http://localhost:8081/health",
        "name": "vLLM Secondary (Qwen 2.5 32B AWQ)",
        "timeout": 10,
        "required": False,   # secondaryは任意
    },
    "litellm": {
        "url": "http://localhost:8000/health",
        "name": "LiteLLM Gateway",
        "timeout": 10,
        "required": True,
    },
    "cocoro_core": {
        "url": f"{os.getenv('COCORO_CORE_URL', 'http://192.168.50.92:8001')}/health",
        "name": "cocoro-core",
        "timeout": 5,
        "required": False,
    },
}


@dataclass
class ServiceStatus:
    name: str
    url: str
    is_healthy: bool
    status_code: Optional[int]
    latency_ms: float
    error: Optional[str]
    required: bool
    checked_at: float

    def to_dict(self) -> dict:
        return {
            "name": self.name,
            "url": self.url,
            "healthy": self.is_healthy,
            "status_code": self.status_code,
            "latency_ms": round(self.latency_ms, 1),
            "error": self.error,
            "required": self.required,
        }


@dataclass
class VramInfo:
    name: str
    used_mb: int
    free_mb: int
    total_mb: int
    utilization_pct: int
    temperature_c: int

    @property
    def used_pct(self) -> float:
        return (self.used_mb / self.total_mb * 100) if self.total_mb > 0 else 0

    def to_dict(self) -> dict:
        return {
            "name": self.name,
            "used_mb": self.used_mb,
            "free_mb": self.free_mb,
            "total_mb": self.total_mb,
            "used_pct": round(self.used_pct, 1),
            "gpu_utilization_pct": self.utilization_pct,
            "temperature_c": self.temperature_c,
        }


async def check_service(
    key: str,
    config: dict,
    client: httpx.AsyncClient,
) -> ServiceStatus:
    """単一サービスのヘルスチェック"""
    start = time.monotonic()
    url = config["url"]
    try:
        response = await client.get(url, timeout=config["timeout"])
        latency_ms = (time.monotonic() - start) * 1000
        is_healthy = 200 <= response.status_code < 300
        return ServiceStatus(
            name=config["name"],
            url=url,
            is_healthy=is_healthy,
            status_code=response.status_code,
            latency_ms=latency_ms,
            error=None if is_healthy else f"HTTP {response.status_code}",
            required=config["required"],
            checked_at=time.time(),
        )
    except httpx.ConnectError:
        return ServiceStatus(
            name=config["name"],
            url=url,
            is_healthy=False,
            status_code=None,
            latency_ms=(time.monotonic() - start) * 1000,
            error="Connection refused",
            required=config["required"],
            checked_at=time.time(),
        )
    except httpx.TimeoutException:
        return ServiceStatus(
            name=config["name"],
            url=url,
            is_healthy=False,
            status_code=None,
            latency_ms=config["timeout"] * 1000,
            error="Timeout",
            required=config["required"],
            checked_at=time.time(),
        )
    except Exception as e:
        return ServiceStatus(
            name=config["name"],
            url=url,
            is_healthy=False,
            status_code=None,
            latency_ms=(time.monotonic() - start) * 1000,
            error=str(e),
            required=config["required"],
            checked_at=time.time(),
        )


def get_vram_info() -> Optional[VramInfo]:
    """nvidia-smiからVRAM情報を取得"""
    try:
        result = subprocess.run(
            [
                "nvidia-smi",
                "--query-gpu=name,memory.used,memory.free,memory.total,"
                "utilization.gpu,temperature.gpu",
                "--format=csv,noheader,nounits",
            ],
            capture_output=True,
            text=True,
            timeout=5,
        )
        if result.returncode != 0:
            return None

        line = result.stdout.strip().split("\n")[0]
        parts = [p.strip() for p in line.split(",")]
        if len(parts) < 6:
            return None

        return VramInfo(
            name=parts[0],
            used_mb=int(parts[1]),
            free_mb=int(parts[2]),
            total_mb=int(parts[3]),
            utilization_pct=int(parts[4]),
            temperature_c=int(parts[5]),
        )
    except Exception as e:
        logger.warning(f"VRAM情報取得失敗: {e}")
        return None


async def run_health_check() -> dict:
    """全サービスのヘルスチェックを並列実行"""
    async with httpx.AsyncClient() as client:
        tasks = [
            check_service(key, config, client)
            for key, config in SERVICES.items()
        ]
        results = await asyncio.gather(*tasks)

    service_statuses = {
        key: result.to_dict()
        for key, result in zip(SERVICES.keys(), results)
    }

    vram = get_vram_info()
    all_required_healthy = all(
        r.is_healthy for r in results if r.required
    )

    return {
        "status": "healthy" if all_required_healthy else "degraded",
        "services": service_statuses,
        "vram": vram.to_dict() if vram else None,
        "checked_at": time.time(),
    }


# ── CLI実行 ───────────────────────────────────────────────────────────────────
async def main():
    import json
    result = await run_health_check()
    print(json.dumps(result, ensure_ascii=False, indent=2))

    # 必須サービスが落ちていたら終了コード1
    if result["status"] != "healthy":
        sys.exit(1)


if __name__ == "__main__":
    logging.basicConfig(level=logging.WARNING)
    asyncio.run(main())
