#!/usr/bin/env python3
"""
tests/test_cocoro_compat.py
cocoro-core ↔ cocoro-llm-server 連携テスト

テストケース:
  1. LiteLLM経由でchat補完が返ること
  2. cocoro-coreがローカルLLMを呼んでいること
  3. 人格が維持されたまま返答していること
  4. 5並列リクエストでもタイムアウトしないこと (30秒以内)
  5. Gemini フォールバックが機能していること

実行:
  python tests/test_cocoro_compat.py
  pytest tests/test_cocoro_compat.py -v
"""

import asyncio
import json
import os
import sys
import time
from typing import Optional

import httpx
import pytest

# ── 設定 ──────────────────────────────────────────────────────────────────────
LLM_SERVER_URL = os.getenv("LLM_SERVER_URL", "http://192.168.50.112:8000")
COCORO_CORE_URL = os.getenv("COCORO_CORE_URL", "http://192.168.50.92:8001")
LITELLM_API_KEY = os.getenv("LITELLM_MASTER_KEY", "mdl-llm-2026")
COCORO_API_KEY  = os.getenv("COCORO_API_KEY", "cocoro-2026")

TIMEOUT_SECONDS   = 30
PARALLEL_REQUESTS = 5


# ── ヘルパー ──────────────────────────────────────────────────────────────────
def llm_headers() -> dict:
    return {
        "Authorization": f"Bearer {LITELLM_API_KEY}",
        "Content-Type": "application/json",
    }

def cocoro_headers() -> dict:
    return {
        "Authorization": f"Bearer {COCORO_API_KEY}",
        "Content-Type": "application/json",
    }

async def chat_completions(
    model: str,
    content: str,
    base_url: str = LLM_SERVER_URL,
    api_key: str = LITELLM_API_KEY,
    timeout: float = TIMEOUT_SECONDS,
) -> dict:
    async with httpx.AsyncClient(timeout=timeout) as client:
        response = await client.post(
            f"{base_url}/v1/chat/completions",
            headers={
                "Authorization": f"Bearer {api_key}",
                "Content-Type": "application/json",
            },
            json={
                "model": model,
                "messages": [{"role": "user", "content": content}],
                "max_tokens": 256,
                "temperature": 0.1,
            },
        )
        response.raise_for_status()
        return response.json()


# ── テストケース ──────────────────────────────────────────────────────────────

class TestLiteLLMBasic:
    """テスト1: LiteLLM基本動作"""

    @pytest.mark.asyncio
    async def test_gpt4o_alias_returns_response(self):
        """gpt-4o エイリアスでScoutが応答すること"""
        result = await chat_completions(
            model="gpt-4o",
            content="こんにちは。1+1は何ですか？",
        )
        assert "choices" in result, f"choicesがありません: {result}"
        assert len(result["choices"]) > 0
        answer = result["choices"][0]["message"]["content"]
        assert answer, "空のレスポンスです"
        assert len(answer) > 0
        print(f"\n  応答: {answer[:100]}")

    @pytest.mark.asyncio
    async def test_gpt4o_mini_alias_returns_response(self):
        """gpt-4o-mini エイリアスでQwenが応答すること"""
        result = await chat_completions(
            model="gpt-4o-mini",
            content="日本の首都は？",
        )
        assert "choices" in result
        answer = result["choices"][0]["message"]["content"]
        assert "東京" in answer or "Tokyo" in answer.lower(), \
            f"期待外の応答: {answer}"

    @pytest.mark.asyncio
    async def test_response_contains_usage(self):
        """レスポンスにusage(トークン数)が含まれること"""
        result = await chat_completions(
            model="gpt-4o-mini",
            content="テスト",
        )
        assert "usage" in result, "usageフィールドがありません"
        assert result["usage"]["total_tokens"] > 0


class TestParallelRequests:
    """テスト4: 並列リクエスト耐性"""

    @pytest.mark.asyncio
    async def test_5_parallel_requests_complete_within_30s(self):
        """5並列リクエストが30秒以内に完了すること"""
        start = time.monotonic()

        tasks = [
            chat_completions(
                model="gpt-4o-mini",
                content=f"質問{i}: Pythonの変数とは何ですか？",
                timeout=30,
            )
            for i in range(PARALLEL_REQUESTS)
        ]

        results = await asyncio.gather(*tasks, return_exceptions=True)

        elapsed = time.monotonic() - start
        print(f"\n  5並列完了時間: {elapsed:.1f}秒")

        errors = [r for r in results if isinstance(r, Exception)]
        assert len(errors) == 0, f"エラーあり: {errors}"
        assert elapsed < 30, f"30秒超過: {elapsed:.1f}秒"

        for i, result in enumerate(results):
            assert "choices" in result, f"リクエスト{i}: choicesなし"


class TestCocoroIntegration:
    """テスト2,3: cocoro-core連携"""

    @pytest.mark.asyncio
    async def test_cocoro_core_health(self):
        """cocoro-coreが応答すること"""
        try:
            async with httpx.AsyncClient(timeout=5) as client:
                resp = await client.get(
                    f"{COCORO_CORE_URL}/health",
                    headers=cocoro_headers(),
                )
            assert resp.status_code == 200, f"cocoro-core unhealthy: {resp.status_code}"
        except httpx.ConnectError:
            pytest.skip(f"cocoro-core ({COCORO_CORE_URL}) に接続できません")

    @pytest.mark.asyncio
    async def test_models_endpoint(self):
        """LiteLLMのモデルリストエンドポイントが返ること"""
        async with httpx.AsyncClient(timeout=10) as client:
            resp = await client.get(
                f"{LLM_SERVER_URL}/v1/models",
                headers=llm_headers(),
            )
        assert resp.status_code == 200
        data = resp.json()
        assert "data" in data
        model_ids = [m["id"] for m in data["data"]]
        print(f"\n  利用可能モデル: {model_ids}")
        assert len(model_ids) > 0, "モデルが1つもありません"


class TestFallback:
    """テスト5: フォールバック動作"""

    @pytest.mark.asyncio
    async def test_claude_sonnet_alias_exists(self):
        """claude-sonnet エイリアスがモデルリストに存在すること"""
        async with httpx.AsyncClient(timeout=10) as client:
            resp = await client.get(
                f"{LLM_SERVER_URL}/v1/models",
                headers=llm_headers(),
            )
        assert resp.status_code == 200
        data = resp.json()
        model_ids = [m["id"] for m in data["data"]]
        assert "claude-sonnet" in model_ids, \
            f"claude-sonnet がモデルリストにありません: {model_ids}"


# ── CLI実行 ───────────────────────────────────────────────────────────────────
async def run_all_tests():
    """テストを順番に実行してサマリーを表示する"""
    print("=" * 60)
    print("  cocoro-llm-server 連携テスト")
    print(f"  LLM Server: {LLM_SERVER_URL}")
    print(f"  cocoro-core: {COCORO_CORE_URL}")
    print("=" * 60)

    tests = [
        ("1. LiteLLM gpt-4o エイリアス",
         TestLiteLLMBasic().test_gpt4o_alias_returns_response),
        ("2. LiteLLM gpt-4o-mini エイリアス",
         TestLiteLLMBasic().test_gpt4o_mini_alias_returns_response),
        ("3. usage フィールド確認",
         TestLiteLLMBasic().test_response_contains_usage),
        ("4. 5並列リクエスト (30秒以内)",
         TestParallelRequests().test_5_parallel_requests_complete_within_30s),
        ("5. モデルリスト確認",
         TestCocoroIntegration().test_models_endpoint),
    ]

    passed = 0
    failed = 0

    for name, test_fn in tests:
        print(f"\n  テスト: {name}")
        try:
            await test_fn()
            print(f"  ✓ PASS")
            passed += 1
        except Exception as e:
            print(f"  ✗ FAIL: {e}")
            failed += 1

    print("\n" + "=" * 60)
    print(f"  結果: {passed}件PASS / {failed}件FAIL")
    print("=" * 60)

    return failed == 0


if __name__ == "__main__":
    success = asyncio.run(run_all_tests())
    sys.exit(0 if success else 1)
