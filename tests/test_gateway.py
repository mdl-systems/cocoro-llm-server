#!/usr/bin/env python3
"""
tests/test_gateway.py
ゲートウェイルーティングロジックのユニットテスト

実行（依存パッケージ不要）:
  python tests/test_gateway.py
  pytest tests/test_gateway.py -v
"""

import sys
import os
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from gateway.router import ComplexityRouter

router = ComplexityRouter()


class TestComplexityRouter:

    def test_short_japanese_goes_to_secondary(self):
        msgs = [{"role": "user", "content": "こんにちは"}]
        assert router.select_model(msgs) == "qwen-32b"

    def test_long_prompt_goes_to_primary(self):
        long_text = "これは非常に長いプロンプトです。" * 50
        msgs = [{"role": "user", "content": long_text}]
        assert router.select_model(msgs) == "llama4-scout"

    def test_code_request_goes_to_primary(self):
        msgs = [{"role": "user", "content": "Pythonでクラスを実装してください。"}]
        assert router.select_model(msgs) == "llama4-scout"

    def test_personality_request_goes_to_primary(self):
        msgs = [{"role": "user", "content": "このキャラクターのpersonalityを設定してください"}]
        assert router.select_model(msgs) == "llama4-scout"

    def test_force_model_overrides(self):
        msgs = [{"role": "user", "content": "こんにちは"}]
        result = router.select_model(msgs, force_model="llama4-scout")
        assert result == "llama4-scout"

    def test_token_estimation(self):
        jp_text = "日本語テスト" * 20   # 140文字 → 70トークン相当
        en_text = "hello world " * 50   # 600文字 → 150トークン相当
        assert router.estimate_tokens(jp_text) < router.estimate_tokens(en_text)

    def test_routing_info_structure(self):
        msgs = [{"role": "user", "content": "テスト"}]
        info = router.get_routing_info(msgs)
        assert "selected_model" in info
        assert "estimated_tokens" in info
        assert "is_code_request" in info
        assert info["token_threshold"] == 500

    def test_architecture_keyword_triggers_primary(self):
        msgs = [{"role": "user", "content": "systemdサービスのアーキテクチャ設計をしてください"}]
        assert router.select_model(msgs) == "llama4-scout"

    def test_docker_keyword_triggers_primary(self):
        msgs = [{"role": "user", "content": "dockerのセットアップ方法は？"}]
        assert router.select_model(msgs) == "llama4-scout"


def run_all():
    import unittest
    loader = unittest.TestLoader()
    suite = loader.loadTestsFromTestCase(TestComplexityRouter)
    runner = unittest.TextTestRunner(verbosity=2)
    result = runner.run(suite)
    return result.wasSuccessful()


if __name__ == "__main__":
    ok = run_all()
    sys.exit(0 if ok else 1)
