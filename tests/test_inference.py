#!/usr/bin/env python3
"""
tests/test_inference.py
推論品質テスト

各モデルの出力品質を基本的な評価項目でチェックする。

実行:
  python tests/test_inference.py
  pytest tests/test_inference.py -v
"""

import asyncio
import os
import sys

import httpx
import pytest

LLM_SERVER_URL = os.getenv("LLM_SERVER_URL", "http://192.168.50.112:8000")
API_KEY = os.getenv("LITELLM_MASTER_KEY", "mdl-llm-2026")
TIMEOUT = 60


async def ask(model: str, prompt: str, max_tokens: int = 512) -> str:
    async with httpx.AsyncClient(timeout=TIMEOUT) as client:
        resp = await client.post(
            f"{LLM_SERVER_URL}/v1/chat/completions",
            headers={"Authorization": f"Bearer {API_KEY}", "Content-Type": "application/json"},
            json={
                "model": model,
                "messages": [{"role": "user", "content": prompt}],
                "max_tokens": max_tokens,
                "temperature": 0.0,  # 決定論的出力
            },
        )
        resp.raise_for_status()
        return resp.json()["choices"][0]["message"]["content"]


class TestScoutQuality:
    """gpt-4o (Llama 4 Scout) 品質テスト"""

    @pytest.mark.asyncio
    async def test_japanese_response(self):
        answer = await ask("gpt-4o", "日本語で返答してください。東京は日本の首都ですか？")
        assert any(c > '\u3000' for c in answer), "日本語文字が含まれていません"
        assert "東京" in answer or "はい" in answer

    @pytest.mark.asyncio
    async def test_code_generation(self):
        answer = await ask("gpt-4o", "Pythonで素数を判定する関数を書いてください。")
        assert "def " in answer, "関数定義(def)がありません"
        assert "return" in answer

    @pytest.mark.asyncio
    async def test_math_reasoning(self):
        answer = await ask("gpt-4o", "17 × 23 = いくつですか？数字だけ答えてください。")
        assert "391" in answer, f"計算結果が不正: {answer}"

    @pytest.mark.asyncio
    async def test_long_context(self):
        long_prompt = "以下の文章を要約してください。\n" + ("これはテスト文章です。" * 100)
        answer = await ask("gpt-4o", long_prompt, max_tokens=256)
        assert len(answer) > 10, "要約が短すぎます"


class TestQwenQuality:
    """gpt-4o-mini (Qwen 3.5 32B) 品質テスト"""

    @pytest.mark.asyncio
    async def test_japanese_fluency(self):
        answer = await ask("gpt-4o-mini", "こんにちは！自己紹介をしてください。")
        assert len(answer) > 20, "応答が短すぎます"
        assert any(c > '\u3000' for c in answer), "日本語が含まれていません"

    @pytest.mark.asyncio
    async def test_fast_response(self):
        import time
        start = time.monotonic()
        await ask("gpt-4o-mini", "1+1は？", max_tokens=10)
        elapsed = time.monotonic() - start
        print(f"\n  Qwen応答時間: {elapsed:.1f}秒")
        assert elapsed < 30, f"応答が遅すぎます: {elapsed:.1f}秒"

    @pytest.mark.asyncio
    async def test_multilingual(self):
        answer = await ask("gpt-4o-mini", "Say 'Hello' in Japanese.")
        assert "こんにちは" in answer or "ハロー" in answer or "hello" in answer.lower()


async def run_all():
    print("=" * 50)
    print("  推論品質テスト")
    print(f"  {LLM_SERVER_URL}")
    print("=" * 50)

    tests = [
        ("Scout: 日本語", TestScoutQuality().test_japanese_response),
        ("Scout: コード生成", TestScoutQuality().test_code_generation),
        ("Scout: 数学", TestScoutQuality().test_math_reasoning),
        ("Qwen: 日本語", TestQwenQuality().test_japanese_fluency),
        ("Qwen: 高速応答", TestQwenQuality().test_fast_response),
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
