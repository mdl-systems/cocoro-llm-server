#!/usr/bin/env python3
"""
tests/test_throughput.py
並列負荷テスト — vLLMのスループット計測

実行:
  python tests/test_throughput.py
  python tests/test_throughput.py --users 10 --duration 60
  python tests/test_throughput.py --model gpt-4o --users 5
"""

import argparse
import asyncio
import json
import os
import statistics
import sys
import time
from dataclasses import dataclass, field
from typing import Optional

import httpx

# ── 設定 ──────────────────────────────────────────────────────────────────────
LLM_SERVER_URL = os.getenv("LLM_SERVER_URL", "http://192.168.50.112:8000")
API_KEY = os.getenv("LITELLM_MASTER_KEY", "mdl-llm-2026")

TEST_PROMPTS = [
    "Pythonでフィボナッチ数列を計算する関数を書いてください。",
    "機械学習とは何ですか？簡単に説明してください。",
    "こんにちは！今日はどんなことを手伝えますか？",
    "Dockerとkubernetesの違いを教えてください。",
    "日本の四季について説明してください。",
    "HTTPとHTTPSの違いは何ですか？",
    "プログラミング初心者に勧める言語は何ですか？",
    "Linuxのパーミッション（chmod）について説明してください。",
    "SQLのJOINの種類を教えてください。",
    "Gitのrebaseとmergeの違いを教えてください。",
]


@dataclass
class RequestResult:
    success: bool
    latency_ms: float
    tokens_generated: int = 0
    error: Optional[str] = None


@dataclass
class BenchmarkResult:
    model: str
    users: int
    duration_s: float
    results: list[RequestResult] = field(default_factory=list)

    @property
    def total_requests(self) -> int:
        return len(self.results)

    @property
    def successful(self) -> int:
        return sum(1 for r in self.results if r.success)

    @property
    def failed(self) -> int:
        return self.total_requests - self.successful

    @property
    def success_rate(self) -> float:
        if self.total_requests == 0:
            return 0
        return self.successful / self.total_requests * 100

    @property
    def throughput_rps(self) -> float:
        if self.duration_s == 0:
            return 0
        return self.successful / self.duration_s

    @property
    def latencies_ms(self) -> list[float]:
        return [r.latency_ms for r in self.results if r.success]

    @property
    def p50_ms(self) -> float:
        if not self.latencies_ms:
            return 0
        return statistics.median(self.latencies_ms)

    @property
    def p95_ms(self) -> float:
        if not self.latencies_ms:
            return 0
        sorted_l = sorted(self.latencies_ms)
        idx = int(len(sorted_l) * 0.95)
        return sorted_l[min(idx, len(sorted_l) - 1)]

    @property
    def p99_ms(self) -> float:
        if not self.latencies_ms:
            return 0
        sorted_l = sorted(self.latencies_ms)
        idx = int(len(sorted_l) * 0.99)
        return sorted_l[min(idx, len(sorted_l) - 1)]

    @property
    def tokens_per_second(self) -> float:
        total_tokens = sum(r.tokens_generated for r in self.results if r.success)
        if self.duration_s == 0:
            return 0
        return total_tokens / self.duration_s

    def print_summary(self):
        print("\n" + "═" * 55)
        print(f"  スループット計測結果")
        print(f"  モデル   : {self.model}")
        print(f"  並列ユーザー: {self.users}人")
        print(f"  計測時間 : {self.duration_s:.1f}秒")
        print("═" * 55)
        print(f"  総リクエスト数 : {self.total_requests}")
        print(f"  成功           : {self.successful}")
        print(f"  失敗           : {self.failed}")
        print(f"  成功率         : {self.success_rate:.1f}%")
        print("─" * 55)
        print(f"  スループット : {self.throughput_rps:.2f} req/s")
        print(f"  生成速度     : {self.tokens_per_second:.1f} tok/s")
        print("─" * 55)
        print(f"  レイテンシ p50 : {self.p50_ms:.0f}ms")
        print(f"  レイテンシ p95 : {self.p95_ms:.0f}ms")
        print(f"  レイテンシ p99 : {self.p99_ms:.0f}ms")
        print("═" * 55)
        if self.failed > 0:
            errors = [r.error for r in self.results if not r.success and r.error]
            unique_errors = list(set(errors))[:3]
            print(f"  エラー例:")
            for e in unique_errors:
                print(f"    - {e}")


async def single_request(
    client: httpx.AsyncClient,
    model: str,
    prompt_idx: int,
    timeout: float = 60.0,
) -> RequestResult:
    """1リクエストを実行して結果を返す"""
    prompt = TEST_PROMPTS[prompt_idx % len(TEST_PROMPTS)]
    start = time.monotonic()

    try:
        response = await client.post(
            f"{LLM_SERVER_URL}/v1/chat/completions",
            headers={
                "Authorization": f"Bearer {API_KEY}",
                "Content-Type": "application/json",
            },
            json={
                "model": model,
                "messages": [{"role": "user", "content": prompt}],
                "max_tokens": 256,
                "temperature": 0.7,
            },
            timeout=timeout,
        )
        latency_ms = (time.monotonic() - start) * 1000
        response.raise_for_status()
        data = response.json()

        tokens = data.get("usage", {}).get("completion_tokens", 0)
        return RequestResult(
            success=True,
            latency_ms=latency_ms,
            tokens_generated=tokens,
        )

    except Exception as e:
        latency_ms = (time.monotonic() - start) * 1000
        return RequestResult(
            success=False,
            latency_ms=latency_ms,
            error=str(e)[:100],
        )


async def user_loop(
    model: str,
    duration_s: float,
    user_id: int,
    results: list,
):
    """仮想ユーザー: duration_s 秒間リクエストを送り続ける"""
    end_time = time.monotonic() + duration_s
    request_count = 0

    async with httpx.AsyncClient() as client:
        while time.monotonic() < end_time:
            result = await single_request(client, model, request_count + user_id)
            results.append(result)
            request_count += 1
            # リクエスト間隔（バーストを避ける）
            await asyncio.sleep(0.1)


async def run_benchmark(
    model: str,
    users: int,
    duration_s: float,
) -> BenchmarkResult:
    """並列ユーザーによる負荷テストを実行"""
    print(f"\n負荷テスト開始: {model} / {users}ユーザー / {duration_s}秒")
    print("待機中...")

    results: list[RequestResult] = []
    start = time.monotonic()

    tasks = [
        user_loop(model, duration_s, i, results)
        for i in range(users)
    ]
    await asyncio.gather(*tasks)

    actual_duration = time.monotonic() - start

    return BenchmarkResult(
        model=model,
        users=users,
        duration_s=actual_duration,
        results=results,
    )


def main():
    parser = argparse.ArgumentParser(description="vLLM スループット計測")
    parser.add_argument("--model", default="gpt-4o-mini",
                        help="テスト対象モデル (default: gpt-4o-mini)")
    parser.add_argument("--users", type=int, default=5,
                        help="並列ユーザー数 (default: 5)")
    parser.add_argument("--duration", type=int, default=60,
                        help="計測時間（秒）(default: 60)")
    args = parser.parse_args()

    result = asyncio.run(
        run_benchmark(args.model, args.users, args.duration)
    )
    result.print_summary()

    # 基準チェック
    if result.success_rate < 90:
        print(f"\n⚠️  成功率が90%未満: {result.success_rate:.1f}%")
        sys.exit(1)

    print("\n✓ テスト完了")


if __name__ == "__main__":
    main()
