#!/usr/bin/env python3
"""
gateway/router.py
プロンプト複雑度判定 → モデル振り分けロジック

判定基準（仕様書より）:
  Primary (Scout 109B):
    - プロンプト 500トークン超
    - コード生成・アーキテクチャ設計
    - cocoro-core の personality/emotion 処理
  Secondary (Qwen 32B):
    - 短い質問・日本語会話
    - 高速レスポンスが必要なケース

使用方法（LiteLLM カスタムルーター経由）:
  from gateway.router import ComplexityRouter
  router = ComplexityRouter()
  model = router.select_model(messages)
"""

import re
import logging
from typing import Optional

logger = logging.getLogger(__name__)

# ── 定数 ──────────────────────────────────────────────────────────────────────
PRIMARY_MODEL   = "llama4-scout"    # Llama 4 Scout 109B
SECONDARY_MODEL = "qwen-32b"        # Qwen 2.5 32B AWQ

PRIMARY_TOKEN_THRESHOLD = 500       # このトークン数以上はPrimary
CODE_PATTERNS = re.compile(
    r'(def |class |import |#include|function |const |let |var |async |await |'
    r'docker|kubernetes|systemd|nginx|bash|python|typescript|rust|golang|'
    r'アーキテクチャ|設計|実装|リファクタリング|デバッグ)',
    re.IGNORECASE
)
PERSONALITY_PATTERNS = re.compile(
    r'(personality|emotion|気持ち|感情|人格|性格|ロールプレイ|キャラクター)',
    re.IGNORECASE
)


class ComplexityRouter:
    """プロンプト複雑度によってモデルを選択するルーター"""

    def __init__(
        self,
        primary_model: str = PRIMARY_MODEL,
        secondary_model: str = SECONDARY_MODEL,
        token_threshold: int = PRIMARY_TOKEN_THRESHOLD,
    ):
        self.primary_model = primary_model
        self.secondary_model = secondary_model
        self.token_threshold = token_threshold

    def estimate_tokens(self, text: str) -> int:
        """簡易トークン数推定（正確な計算はtiktokenを使うが軽量化のため概算）"""
        # 日本語: 1文字 ≈ 0.5トークン、英語: 1単語 ≈ 1.3トークン の概算
        japanese_chars = len(re.findall(r'[\u3000-\u9fff\uf900-\ufaff]', text))
        other_chars = len(text) - japanese_chars
        return int(japanese_chars * 0.5 + other_chars / 4)

    def extract_content(self, messages: list[dict]) -> str:
        """メッセージリストからテキストを結合"""
        parts = []
        for msg in messages:
            content = msg.get("content", "")
            if isinstance(content, str):
                parts.append(content)
            elif isinstance(content, list):
                for item in content:
                    if isinstance(item, dict) and item.get("type") == "text":
                        parts.append(item.get("text", ""))
        return " ".join(parts)

    def is_code_request(self, text: str) -> bool:
        """コード生成・技術的な内容かどうかを判定"""
        return bool(CODE_PATTERNS.search(text))

    def is_personality_request(self, text: str) -> bool:
        """cocoro-core の人格/感情処理かどうかを判定"""
        return bool(PERSONALITY_PATTERNS.search(text))

    def select_model(
        self,
        messages: list[dict],
        force_model: Optional[str] = None,
    ) -> str:
        """
        メッセージリストからモデルを選択する

        Args:
            messages: OpenAI形式のメッセージリスト
            force_model: 強制的に使用するモデル名（Noneの場合は自動判定）

        Returns:
            モデル名 ("llama4-scout" or "qwen-32b")
        """
        if force_model:
            logger.debug(f"強制モデル指定: {force_model}")
            return force_model

        text = self.extract_content(messages)
        token_count = self.estimate_tokens(text)

        # 判定ロジック（優先度順）
        reason = ""

        if self.is_personality_request(text):
            model = self.primary_model
            reason = "personality/emotion処理"

        elif self.is_code_request(text):
            model = self.primary_model
            reason = "コード生成・技術的内容"

        elif token_count >= self.token_threshold:
            model = self.primary_model
            reason = f"トークン数 {token_count} >= 閾値 {self.token_threshold}"

        else:
            model = self.secondary_model
            reason = f"短文・日本語会話 (トークン数: {token_count})"

        logger.info(f"モデル選択: {model} [{reason}]")
        return model

    def get_routing_info(self, messages: list[dict]) -> dict:
        """デバッグ用: ルーティング判定の詳細を返す"""
        text = self.extract_content(messages)
        token_count = self.estimate_tokens(text)
        selected = self.select_model(messages)

        return {
            "selected_model": selected,
            "estimated_tokens": token_count,
            "is_code_request": self.is_code_request(text),
            "is_personality_request": self.is_personality_request(text),
            "token_threshold": self.token_threshold,
            "primary_model": self.primary_model,
            "secondary_model": self.secondary_model,
        }


# ── シングルトンインスタンス ──────────────────────────────────────────────────
_router = ComplexityRouter()


def get_router() -> ComplexityRouter:
    return _router
