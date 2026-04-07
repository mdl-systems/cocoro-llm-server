# cocoro-core 接続手順

> **変更時はこのファイルに記録すること**（CLAUDE.md 絶対ルール）

## アーキテクチャ

```
cocoro-core (192.168.50.92:8001)
    │
    │  OpenAI互換 API (HTTPS/HTTP)
    ▼
LiteLLM Gateway (192.168.50.112:8000)
    ├── gpt-4o       → Llama 4 Scout 109B Q4_K_M (port 8080)
    ├── gpt-4o-mini  → Qwen 2.5 32B AWQ         (port 8081)
    └── claude-sonnet→ Anthropic API (フォールバック)
```

## cocoro-core の .env 設定

cocoro-core（192.168.50.92）の `.env` を以下に変更する:

```env
# ── LLM設定（cocoro-llm-server に向ける）────────────────
# LiteLLM は OpenAI 互換エンドポイントを提供する
# ※ LLM_PROVIDER=ollama は使わないこと（Ollama互換ではない）
LLM_PROVIDER=openai
OPENAI_API_BASE=http://192.168.50.112:8000/v1
OPENAI_API_KEY=mdl-llm-2026

# モデルエイリアス（LiteLLMが内部でルーティング）
# gpt-4o       → Llama 4 Scout（複雑な推論・コード・長文）
# gpt-4o-mini  → Qwen 2.5 32B awq（短文・日本語・高速）
DEFAULT_MODEL=gpt-4o-mini      # 通常会話はQwen（高速）
COMPLEX_MODEL=gpt-4o           # 複雑なタスクはScout

# Anthropic フォールバック（任意）
# ANTHROPIC_API_KEY=sk-ant-xxx  ← LAN落ちの保険
```

## 動作確認手順

### 1. LiteLLM に直接 curl（最初に確認）

```bash
# gpt-4o (Llama 4 Scout) テスト
curl http://192.168.50.112:8000/v1/chat/completions \
  -H "Authorization: Bearer mdl-llm-2026" \
  -H "Content-Type: application/json" \
  -d '{"model":"gpt-4o","messages":[{"role":"user","content":"こんにちは"}],"max_tokens":50}'

# gpt-4o-mini (Qwen 2.5) テスト
curl http://192.168.50.112:8000/v1/chat/completions \
  -H "Authorization: Bearer mdl-llm-2026" \
  -H "Content-Type: application/json" \
  -d '{"model":"gpt-4o-mini","messages":[{"role":"user","content":"日本の首都は？"}],"max_tokens":20}'
```

### 2. cocoro-core からのリクエスト確認

```bash
# cocoro-core のチャットエンドポイントを叩く
curl http://192.168.50.92:8001/chat \
  -H "Authorization: Bearer cocoro-2026" \
  -H "Content-Type: application/json" \
  -d '{"message":"こんにちは"}'
```

レスポンスに `"model": "llama4-scout"` または `"model": "qwen-32b"` が含まれていれば接続成功。

### 3. 統合テストスクリプト

```bash
# サーバー上で実行
cd ~/cocoro-llm-server
pip install httpx pytest pytest-asyncio
python tests/test_cocoro_compat.py
```

## ストリーミング確認

cocoro-core がストリーミングを使う場合は以下で確認:

```bash
curl http://192.168.50.112:8000/v1/chat/completions \
  -H "Authorization: Bearer mdl-llm-2026" \
  -H "Content-Type: application/json" \
  -d '{"model":"gpt-4o-mini","messages":[{"role":"user","content":"1から5まで数えて"}],"stream":true}'
# data: {"choices":[{"delta":{"content":"1"}...}]} の形式で返ってくればOK
```

## よくある問題

| 症状 | 原因 | 対処 |
|---|---|---|
| `Connection refused` | vLLM/LiteLLMが起動していない | `bash scripts/start_all.sh` |
| `401 Unauthorized` | APIキー不一致 | `.env` の `LITELLM_MASTER_KEY` を確認 |
| `503 Service Unavailable` | モデルロード中（初回起動時） | `journalctl -u vllm-primary -f` でログ確認 |
| 応答が遅い | モデルウォームアップ中 | 初回リクエストは2〜3分かかる場合あり |
| Ollama互換エラー | `LLM_PROVIDER=ollama` になっている | `OPENAI_API_BASE` と `LLM_PROVIDER=openai` に変更 |

## 変更履歴

| 日付 | 変更内容 | 担当 |
|---|---|---|
| 2026-04-05 | 初版: LiteLLM → Ollama互換で接続（暫定） | matsuokan |
| 2026-04-07 | LLM_PROVIDER=openai に修正（LiteLLMはOpenAI互換が正しい）| matsuokan |
| 2026-04-07 | 動作確認手順・よくある問題を追記 | matsuokan |
