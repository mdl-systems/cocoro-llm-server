# =============================================================================
# CLAUDE.md — cocoro-llm-server
# AIエージェント（AntGravity / OpenHands等）向け引き継ぎ書
# 更新日: 2026-05-05
# =============================================================================

# CLAUDE.md — cocoro-llm-server

> mdl-systems / cocoro-OS プロジェクトの社内LLM推論サーバーです。
> プロジェクト全体の概要は cocoro-docs/CLAUDE.md を参照してください。

---

## このrepoの役割

**社内LLM推論サーバー** — AntGravity・OpenHands・cocoro-core・開発チーム全員が
トークン制限なしで使える、OpenAI互換のローカルLLM基盤。

- ハードウェア: 192.168.50.112（RTX PRO 6000 Blackwell 96GB GDDR7 / i9 285K / 256GB RAM / 4TB NVMe）
- Primary Model: **Qwen3-Coder-Next-FP8**（VRAM ~70GB weights + ~17GB KV fp8、256K context）
- Gateway: LiteLLM（OpenAI互換 API :4000）
- UI: Open WebUI（:3000）

---

## 絶対ルール

- **クイックフィックス禁止** — 根本原因を特定してから修正する
- **モデルウェイトをgitにコミットしない** — `.gitignore` で除外済み
- **APIキーを平文でコードに書かない** — 必ず `.env` 経由
- **`--tool-call-parser qwen3_coder` を外さない** — OpenHandsのツールコールが壊れる
- **`--enable-prefix-caching` を外さない** — Open WebUI共存の生命線
- **クライアントはポート4000（LiteLLM）経由** — 8000はLAN内デバッグ用のみ
- **VRAM配分を変える場合は docs/VRAM_LAYOUT.md を先に更新**
- **cocoro-core の .env 変更は docs/COCORO_INTEGRATION.md に記録**

---

## テックスタック

| Component | Technology | Port |
|---|---|---|
| 推論エンジン | vLLM (Blackwell build) | :8000（内部）|
| APIゲートウェイ | LiteLLM Proxy | :4000（OpenAI互換）|
| ローカルUI | Open WebUI | :3000 |
| モニタリング | Prometheus + Grafana | :9090 / :3100 |
| コンテナ管理 | Docker Compose | — |
| OS | Debian 13 | — |

---

## LiteLLMの3モデル使い分け

| モデル名 | バックエンド | 用途 |
|---|---|---|
| `qwen3-coder` | vLLM ローカル | 普段使い（コーディング）|
| `claude-sonnet` | Anthropic API | 難タスク・手動指定 |
| `smart-coder` | ローカル優先 → Claude自動フォールバック | 信頼性重視ワークフロー |
| `gpt-4o` | qwen3-coderエイリアス | 後方互換 |
| `gpt-4o-mini` | qwen3-coderエイリアス | 後方互換 |

---

## 環境変数（.env）

`.env.example` を参照してコピーして使う。
設定ファイル: `~/cocoro-llm-server/.env`

必須キー:
- `HF_TOKEN` — HuggingFace アクセストークン（モデルDL用）
- `ANTHROPIC_API_KEY` — Claude フォールバック用
- `LITELLM_MASTER_KEY` — チーム共有APIキー
- `OPEN_WEBUI_SECRET_KEY` — WebUI認証用シークレット

---

## よく使うコマンド

```bash
# 全サービス起動
docker compose up -d

# 初回: ログ確認（モデルDL含む5〜15分）
docker compose logs -f vllm-primary

# ヘルスチェック
curl http://192.168.50.112:4000/health/liveliness

# 推論テスト（LiteLLM経由）
curl http://192.168.50.112:4000/v1/chat/completions \
  -H "Authorization: Bearer ${LITELLM_MASTER_KEY}" \
  -H "Content-Type: application/json" \
  -d '{"model":"qwen3-coder","messages":[{"role":"user","content":"こんにちは"}]}'

# VRAM確認
nvidia-smi --query-gpu=memory.used,memory.free,memory.total --format=csv

# ログ確認
docker compose logs litellm -f
docker compose logs vllm-primary -f

# 再起動（設定変更後）
docker compose restart litellm
docker compose down && docker compose up -d  # フル再起動

# Windowsから同期（deploy.ps1）
./deploy.ps1
```

---

## OpenHands / AntGravity 接続設定

```
API Base URL: http://192.168.50.112:4000/v1
API Key: <LITELLM_MASTER_KEY>
Model: smart-coder  (または qwen3-coder / gpt-4o)
```

---

## cocoro-coreとの接続

```
LLM_PROVIDER=openai
OPENAI_API_BASE=http://192.168.50.112:4000/v1
OPENAI_API_KEY=<LITELLM_MASTER_KEY>
OPENAI_MODEL=gpt-4o
```

---

## 関連repo

| repo | 役割 | URL |
|---|---|---|
| cocoro-core | 人格AIエンジン | github.com/mdl-systems/cocoro-core |
| cocoro-console | 管理UI | github.com/mdl-systems/cocoro-console |
| cocoro-agent | エージェント | github.com/mdl-systems/cocoro-agent |
| cocoro-docs | ドキュメント | github.com/mdl-systems/cocoro-docs |

---

## 更新履歴

| 日付 | 更新内容 |
|---|---|
| 2026-04-05 | 初版作成 — vLLM + LiteLLM構成確定 |
| 2026-04-14 | Llama4 Scout FP8 VRAM超過判明 → Qwen2.5-72B-AWQ暫定運用 |
| 2026-05-05 | **Qwen3-Coder-Next-FP8に移行。Open WebUI追加。LiteLLM 3ルート構成。** |
