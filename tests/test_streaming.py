#!/usr/bin/env python3
"""
tests/test_streaming.py
ストリーミングレスポンステスト

LiteLLM / vLLM の Server-Sent Events ストリーミングが
正しく動作することを確認する。

実行:
  pip install httpx pytest pytest-asyncio
  python tests/test_streaming.py
  pytest tests/test_streaming.py -v
"""

import asyncio
import json
import os
import sys
import time

import httpx
import pytest

LLM_SERVER_URL = os.getenv("LLM_SERVER_URL", "http://192.168.50.112:8000")
API_KEY = os.getenv("LITELLM_MASTER_KEY", "mdl-llm-2026")


async def stream_chat(model: str, content: str, max_tokens: int = 64) -> dict:
    """
    ストリーミングリクエストを送り、チャンクを収集して返す。

    Returns:
        dict: {
            "chunks": List[str],   # 各チャンクのcontent
            "full_text": str,      # 結合テキスト
            "chunk_count": int,    # チャンク数
            "elapsed": float,      # 秒
            "first_chunk_latency": float,  # 最初のチャンクまでの秒数
        }
    """
    chunks = []
    start = time.monotonic()
    first_chunk_time = None

    async with httpx.AsyncClient(timeout=120) as client:
        async with client.stream(
            "POST",
            f"{LLM_SERVER_URL}/v1/chat/completions",
            headers={
                "Authorization": f"Bearer {API_KEY}",
                "Content-Type": "application/json",
            },
            json={
                "model": model,
                "messages": [{"role": "user", "content": content}],
                "max_tokens": max_tokens,
                "stream": True,
                "temperature": 0.0,
            },
        ) as response:
            response.raise_for_status()
            async for line in response.aiter_lines():
                if not line.startswith("data: "):
                    continue
                data_str = line[len("data: "):]
                if data_str.strip() == "[DONE]":
                    break
                try:
                    chunk = json.loads(data_str)
                    delta = chunk["choices"][0]["delta"].get("content", "")
                    if delta:
                        if first_chunk_time is None:
                            first_chunk_time = time.monotonic() - start
                        chunks.append(delta)
                except (json.JSONDecodeError, KeyError, IndexError):
                    continue

    elapsed = time.monotonic() - start
    return {
        "chunks": chunks,
        "full_text": "".join(chunks),
        "chunk_count": len(chunks),
        "elapsed": elapsed,
        "first_chunk_latency": first_chunk_time or elapsed,
    }


class TestStreamingBasic:
    """基本ストリーミング動作テスト"""

    @pytest.mark.asyncio
    async def test_gpt4o_mini_streaming_returns_chunks(self):
        """gpt-4o-mini がストリーミングでチャンクを返すこと"""
        result = await stream_chat("gpt-4o-mini", "1から3まで数えてください。", max_tokens=32)
        print(f"\n  チャンク数: {result['chunk_count']}, テキスト: {result['full_text']!r}")
        assert result["chunk_count"] >= 1, "チャンクが1つもありません"
        assert len(result["full_text"]) > 0, "テキストが空です"

    @pytest.mark.asyncio
    async def test_gpt4o_streaming_returns_chunks(self):
        """gpt-4o (Llama 4 Scout) もストリーミングで返すこと"""
        result = await stream_chat("gpt-4o", "Hi, say one word.", max_tokens=16)
        print(f"\n  チャンク数: {result['chunk_count']}, テキスト: {result['full_text']!r}")
        assert result["chunk_count"] >= 1, "チャンクが1つもありません"
        assert len(result["full_text"]) > 0, "テキストが空です"

    @pytest.mark.asyncio
    async def test_streaming_chunks_reconstruct_coherent_text(self):
        """チャンクを結合すると意味のある文章になること"""
        result = await stream_chat(
            "gpt-4o-mini",
            "日本の首都を一言で答えてください。",
            max_tokens=20,
        )
        full = result["full_text"]
        print(f"\n  結合テキスト: {full!r}")
        assert "東京" in full or "Tokyo" in full.lower(), \
            f"期待するキーワードが含まれていません: {full!r}"


class TestStreamingPerformance:
    """ストリーミング性能テスト"""

    @pytest.mark.asyncio
    async def test_first_chunk_latency_within_10s(self):
        """最初のチャンクが 10 秒以内に届くこと（Qwen）"""
        result = await stream_chat("gpt-4o-mini", "こんにちは", max_tokens=20)
        latency = result["first_chunk_latency"]
        print(f"\n  初チャンクレイテンシ: {latency:.2f}秒")
        assert latency < 10, f"初チャンクまでが遅すぎます: {latency:.2f}秒"

    @pytest.mark.asyncio
    async def test_streaming_faster_than_blocking(self):
        """
        ストリーミングで初チャンクを受け取る方が
        非ストリーミング (max_tokens=full) より体感的に速いこと。
        初チャンクレイテンシが全体の完了時間より短いことだけ確認。
        """
        result = await stream_chat("gpt-4o-mini", "東京について3文で説明してください。", max_tokens=128)
        first = result["first_chunk_latency"]
        total = result["elapsed"]
        print(f"\n  初チャンク: {first:.2f}秒 / 合計: {total:.2f}秒")
        assert first < total, "初チャンクレイテンシが合計時間より長い（異常）"
        # 初チャンクは完了の 80% 以前に到達していること（ストリームの恩恵確認）
        assert first < total * 0.8, \
            f"ストリーミングの恩恵が薄い: 初チャンク={first:.2f}s / 合計={total:.2f}s"

    @pytest.mark.asyncio
    async def test_parallel_streaming_3_requests(self):
        """3並列ストリーミングが 60 秒以内に完了すること"""
        start = time.monotonic()
        tasks = [
            stream_chat("gpt-4o-mini", f"Q{i}: Pythonとは？", max_tokens=32)
            for i in range(3)
        ]
        results = await asyncio.gather(*tasks, return_exceptions=True)
        elapsed = time.monotonic() - start
        print(f"\n  3並列ストリーミング完了: {elapsed:.1f}秒")
        errors = [r for r in results if isinstance(r, Exception)]
        assert not errors, f"エラーあり: {errors}"
        assert elapsed < 60, f"60秒超過: {elapsed:.1f}秒"


async def run_all():
    print("=" * 55)
    print("  ストリーミングテスト")
    print(f"  {LLM_SERVER_URL}")
    print("=" * 55)

    tests = [
        ("gpt-4o-mini: チャンク受信",
         TestStreamingBasic().test_gpt4o_mini_streaming_returns_chunks),
        ("gpt-4o: チャンク受信",
         TestStreamingBasic().test_gpt4o_streaming_returns_chunks),
        ("テキスト整合性",
         TestStreamingBasic().test_streaming_chunks_reconstruct_coherent_text),
        ("初チャンクレイテンシ < 10秒",
         TestStreamingPerformance().test_first_chunk_latency_within_10s),
        ("3並列ストリーミング < 60秒",
         TestStreamingPerformance().test_parallel_streaming_3_requests),
    ]

    passed = failed = 0
    for name, fn in tests:
        try:
            await fn()
            print(f"  ✓ {name}")
            passed += 1
        except Exception as e:
            print(f"  ✗ {name}: {e}")
            failed += 1

    print(f"\n  結果: {passed}PASS / {failed}FAIL")
    return failed == 0


if __name__ == "__main__":
    ok = asyncio.run(run_all())
    sys.exit(0 if ok else 1)
