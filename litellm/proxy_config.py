"""
litellm/proxy_config.py
-----------------------
LiteLLM カスタムルーティングロジック

役割:
  - プロンプトのトークン数・内容に基づいてモデルを自動選択
  - gpt-4o  → Primary (Llama 4 Scout 109B)  : 500トークン超 / コード / 推論
  - gpt-4o-mini → Secondary (Qwen 2.5 32B AWQ): 短文 / 日本語 / 高速応答

LiteLLM への組み込み方:
  litellm_settings:
    custom_router: litellm.proxy_config.CocoroDynamicRouter

参考: https://docs.litellm.ai/docs/proxy/custom_router
"""

from __future__ import annotations

import re
import logging
from typing import Any, Optional

logger = logging.getLogger("cocoro.router")

# ---------------------------------------------------------------------------
# 設定値 — 変更時は docs/MODEL_SELECTION.md も更新すること
# ---------------------------------------------------------------------------

# Primary に振り分けるプロンプトトークン数の閾値
# 仕様: 500トークン超は gpt-4o (Scout) へ
TOKEN_THRESHOLD_PRIMARY = 500

# コード・アーキテクチャ系キーワード（部分一致、大小文字無視）
CODE_KEYWORDS = [
    # 言語
    r"\bpython\b", r"\brust\b", r"\bgo\b", r"\btypescript\b",
    r"\bjavascript\b", r"\bjava\b", r"\bc\+\+\b", r"\bsql\b",
    # 行動
    r"\bcode\b", r"\bコード\b", r"\bプログラム\b", r"\b実装\b",
    r"\bデバッグ\b", r"\bリファクタ\b", r"\bアーキテクチャ\b",
    r"\bclass\b", r"\bfunction\b", r"\bdef\b", r"\breturn\b",
    r"\bimport\b", r"\bmodule\b",
    # インフラ
    r"\bdocker\b", r"\bkubernetes\b", r"\bgit\b", r"\bbash\b",
    r"\bsystemd\b", r"\bcurl\b", r"\bjson\b", r"\byaml\b",
]

# 推論・分析系キーワード（Primary 推奨）
REASONING_KEYWORDS = [
    r"\b分析\b", r"\b解析\b", r"\b論証\b", r"\b比較検討\b",
    r"\banalyze\b", r"\breason\b", r"\bexplain why\b",
    r"\bstep.by.step\b", r"\bchain.of.thought\b",
    r"\bまとめてください\b", r"\b整理してください\b",
    r"\bレポート\b", r"\b仕様書\b", r"\bドキュメント\b",
]

# 短文・会話系（Secondary を優先）
CONVERSATIONAL_KEYWORDS = [
    r"\bありがとう\b", r"\bこんにちは\b", r"\bよろしく\b",
    r"\bはい\b", r"\bいいえ\b", r"\bどう思う\b",
    r"\bhello\b", r"\bhi\b", r"\bthanks\b",
]

# ---------------------------------------------------------------------------
# モデルエイリアス
# ---------------------------------------------------------------------------
MODEL_PRIMARY   = "gpt-4o"       # Llama 4 Scout 109B
MODEL_SECONDARY = "gpt-4o-mini"  # Qwen 2.5 32B AWQ

_CODE_PATTERN         = re.compile("|".join(CODE_KEYWORDS), re.IGNORECASE | re.MULTILINE)
_REASONING_PATTERN    = re.compile("|".join(REASONING_KEYWORDS), re.IGNORECASE | re.MULTILINE)
_CONVERSATIONAL_PATTERN = re.compile("|".join(CONVERSATIONAL_KEYWORDS), re.IGNORECASE)


# ---------------------------------------------------------------------------
# トークン数推定 (heuristic)
#
# vLLM 本番環境では tiktoken 等でトークン化できるが、
# ルーター段階では tokenizer を呼ぶとレイテンシが生じるため、
# 「文字数 / 4」という一般的な近似式を使用する。
# 日本語は1文字≒1.3トークンなので若干の補正を入れる。
# ---------------------------------------------------------------------------

def _estimate_tokens(text: str) -> int:
    """テキストのトークン数をヒューリスティックで推定する。"""
    # ASCII比率でen/ja判定
    ascii_chars = sum(1 for c in text if ord(c) < 128)
    ascii_ratio = ascii_chars / max(len(text), 1)

    if ascii_ratio > 0.8:
        # 主に英語: 1トークン ≈ 4文字
        return len(text) // 4
    else:
        # 主に日本語: 1文字 ≈ 1.3トークン
        return int(len(text) * 1.3)


def _extract_prompt_text(data: dict[str, Any]) -> str:
    """リクエストbodyからユーザープロンプトを抽出する。"""
    messages = data.get("messages", [])
    if not messages:
        return data.get("prompt", "")

    parts: list[str] = []
    for msg in messages:
        role    = msg.get("role", "")
        content = msg.get("content", "")

        if isinstance(content, str):
            parts.append(content)
        elif isinstance(content, list):
            # マルチモーダル形式 [{type: "text", text: "..."}, ...]
            for item in content:
                if isinstance(item, dict) and item.get("type") == "text":
                    parts.append(item.get("text", ""))

    return "\n".join(parts)


def _contains_code_block(text: str) -> bool:
    """Markdown コードブロック (```) が含まれるかどうか。"""
    return "```" in text or "\t" in text


# ---------------------------------------------------------------------------
# ルーティング判定ロジック
# ---------------------------------------------------------------------------

def select_model(
    data: dict[str, Any],
    requested_model: Optional[str] = None,
) -> str:
    """
    リクエストを解析して最適なモデルエイリアスを返す。

    判定優先順位:
      1. クライアントが llama4-scout / qwen-32b を直接指定 → そのまま使用
      2. claude-sonnet → そのまま Anthropic にフォールバック
      3. gpt-4o / gpt-4o-mini が指定されていても、内容で再判定
         a. トークン数 > TOKEN_THRESHOLD_PRIMARY → Primary
         b. コード系キーワード or コードブロック → Primary
         c. 推論・分析系キーワード → Primary
         d. 短文・会話系キーワード → Secondary
         e. 上記に該当しない場合: gpt-4o-mini が指定されていれば Secondary
         f. デフォルト: 指定モデルをそのまま使用

    Returns:
        str: LiteLLM model alias (gpt-4o / gpt-4o-mini / claude-sonnet / ...)
    """
    model = requested_model or data.get("model", MODEL_SECONDARY)

    # ── 直接指定モデルはルーティングをスキップ ──────────────────────────────
    if model in ("llama4-scout", "qwen-32b", "claude-sonnet"):
        logger.debug("[router] 直接指定モデル: %s → バイパス", model)
        return model

    # ── プロンプト抽出 ────────────────────────────────────────────────────
    prompt_text = _extract_prompt_text(data)
    estimated_tokens = _estimate_tokens(prompt_text)

    logger.debug(
        "[router] model=%s | tokens≈%d | len=%d",
        model, estimated_tokens, len(prompt_text)
    )

    # ── 判定 1: トークン数 ────────────────────────────────────────────────
    if estimated_tokens > TOKEN_THRESHOLD_PRIMARY:
        logger.info(
            "[router] Primary選択 (トークン数: %d > %d) → %s",
            estimated_tokens, TOKEN_THRESHOLD_PRIMARY, MODEL_PRIMARY
        )
        return MODEL_PRIMARY

    # ── 判定 2: コードブロック ────────────────────────────────────────────
    if _contains_code_block(prompt_text):
        logger.info("[router] Primary選択 (コードブロック検出) → %s", MODEL_PRIMARY)
        return MODEL_PRIMARY

    # ── 判定 3: コード・インフラ系キーワード ─────────────────────────────
    if _CODE_PATTERN.search(prompt_text):
        logger.info("[router] Primary選択 (コードキーワード検出) → %s", MODEL_PRIMARY)
        return MODEL_PRIMARY

    # ── 判定 4: 推論・分析系キーワード ───────────────────────────────────
    if _REASONING_PATTERN.search(prompt_text):
        logger.info("[router] Primary選択 (推論キーワード検出) → %s", MODEL_PRIMARY)
        return MODEL_PRIMARY

    # ── 判定 5: 短文・会話 ────────────────────────────────────────────────
    if _CONVERSATIONAL_PATTERN.search(prompt_text):
        logger.info("[router] Secondary選択 (会話キーワード検出) → %s", MODEL_SECONDARY)
        return MODEL_SECONDARY

    # ── デフォルト: 元のリクエストモデルを使用 ────────────────────────────
    logger.debug("[router] デフォルト選択 → %s", model)
    return model


# ---------------------------------------------------------------------------
# LiteLLM カスタムルーター クラス
#
# LiteLLM は custom_router として以下のインターフェースを期待する:
#   def async_route_request(self, llm_router, data, ...) -> dict
# ---------------------------------------------------------------------------

class CocoroDynamicRouter:
    """
    cocoro-llm-server のダイナミックモデルルーター。

    LiteLLM config.yaml に以下を追記して有効化:
      litellm_settings:
        custom_router: litellm.proxy_config.CocoroDynamicRouter
    """

    async def async_route_request(
        self,
        llm_router: Any,
        data: dict[str, Any],
        user_api_key_dict: Any,
        **kwargs: Any,
    ) -> dict[str, Any]:
        """
        受信リクエストのモデルを動的に書き換える。

        LiteLLM が実際の API コールを行う前に呼び出される。
        """
        original_model = data.get("model", "")
        selected_model = select_model(data, requested_model=original_model)

        if selected_model != original_model:
            logger.info(
                "[router] モデルを変更: %s → %s (caller=%s)",
                original_model,
                selected_model,
                getattr(user_api_key_dict, "user_id", "anonymous"),
            )
            data["model"] = selected_model

        return data


# ---------------------------------------------------------------------------
# 単体テスト用エントリポイント
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    import json

    logging.basicConfig(level=logging.DEBUG)

    test_cases = [
        # (description, messages, expected_model)
        (
            "短い挨拶 → Secondary",
            [{"role": "user", "content": "こんにちは！元気ですか？"}],
            MODEL_SECONDARY,
        ),
        (
            "コードキーワード → Primary",
            [{"role": "user", "content": "Pythonで二分探索を実装してください"}],
            MODEL_PRIMARY,
        ),
        (
            "コードブロック → Primary",
            [{"role": "user", "content": "以下のコードをレビューしてください:\n```python\ndef foo(): pass\n```"}],
            MODEL_PRIMARY,
        ),
        (
            "長文 (500トークン超) → Primary",
            [{"role": "user", "content": "あ" * 400}],  # 400文字 × 1.3 ≈ 520トークン
            MODEL_PRIMARY,
        ),
        (
            "短文で推論キーワード → Primary",
            [{"role": "user", "content": "このデータを分析してください"}],
            MODEL_PRIMARY,
        ),
        (
            "直接指定 claude-sonnet → バイパス",
            [{"role": "user", "content": "テスト"}],
            "claude-sonnet",
        ),
    ]

    print("=" * 60)
    print("  CocoroDynamicRouter — 単体テスト")
    print("=" * 60)

    all_pass = True
    for desc, messages, expected in test_cases:
        data = {"model": expected if expected == "claude-sonnet" else "gpt-4o", "messages": messages}
        result = select_model(data, requested_model=data["model"])
        status = "✅ PASS" if result == expected else "❌ FAIL"
        if result != expected:
            all_pass = False
        print(f"  {status}  {desc}")
        if result != expected:
            print(f"         expected={expected}, got={result}")

    print("=" * 60)
    print("  結果:", "全テスト通過 ✅" if all_pass else "テスト失敗あり ❌")
    print("=" * 60)
