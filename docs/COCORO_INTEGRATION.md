# cocoro-core 接続手順

> **変更時はこのファイルに記録すること**（CLAUDE.md 絶対ルール）

## 接続設定

cocoro-core（192.168.50.92）の `.env` を以下に設定する:

```env
# LLM設定（cocoro-llm-server に向ける）
LLM_PROVIDER=ollama
OLLAMA_BASE_URL=http://192.168.50.112:8000
OLLAMA_MODEL=gpt-4o

# 認証
LLM_API_KEY=mdl-llm-2026
```

LiteLLMはOllama互換エンドポイント (`/api/generate`, `/api/chat`) も提供するため、
cocoro-coreの `local_llm.py` (C-4モジュール) は**変更不要**。

## 動作確認

```bash
# cocoro-coreのchatエンドポイントがローカルLLMを呼んでいることを確認
curl http://192.168.50.92:8001/chat \
  -H "Authorization: Bearer cocoro-2026" \
  -H "Content-Type: application/json" \
  -d '{"message":"こんにちは"}'

# レスポンスヘッダーで確認
# X-Model: llama4-scout が含まれていればOK
```

## 接続テスト

```bash
python tests/test_cocoro_compat.py
```

## 変更履歴

| 日付 | 変更内容 | 担当 |
|---|---|---|
| 2026-04-05 | 初版: LiteLLM → Ollama互換で接続 | matsuokan |
