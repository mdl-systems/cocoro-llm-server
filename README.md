# cocoro-llm-server

> **mdl-systems 社内 LLM 推論サーバー**
> OpenAI 互換 API — トークン制限なし・完全プライベート
> Host: `192.168.50.112` | GPU: RTX PRO 6000 Blackwell 94.96GB GDDR7

---

## アーキテクチャ概要

```
[クライアント群]
  AntGravity / OpenHands / cocoro-core / チームメンバー
        │
        ▼ http://192.168.50.112:4000/v1  (OpenAI互換)
  ┌──────────────────────────────────┐
  │  LiteLLM Proxy :4000             │
  │  smart-coder / qwen3-coder /     │
  │  claude-sonnet (fallback)        │
  └────────────┬─────────────────────┘
               │
       ┌───────┴────────┐
       ▼                ▼
  :8000 (local)    Anthropic API
  vLLM Primary     (fallback only)
  Qwen3-Coder-Next-FP8
  VRAM: 70GB+17GB KV
  Context: 256K tokens

  ┌─────────────────┐
  │ Open WebUI :3000 │ ← LiteLLM経由 (default: smart-coder)
  └─────────────────┘

  ┌─────────────────┐
  │ Prometheus :9090 │
  │ Grafana    :3100 │
  └─────────────────┘
```

---

## モデルルーティング

| モデル名 | バックエンド | 用途 |
|---|---|---|
| `smart-coder` | ローカル優先 → Claude自動フォールバック | **推奨デフォルト** |
| `qwen3-coder` | vLLM ローカル直結 | 高速・プライバシー重視 |
| `claude-sonnet` | Anthropic API直接 | 難タスク・品質最優先 |
| `gpt-4o` | qwen3-coderエイリアス | 後方互換 |
| `gpt-4o-mini` | qwen3-coderエイリアス | 後方互換 |

---

## クイックスタート（リモートサーバー側）

### 1. 初回セットアップ

```bash
# リポジトリ clone
git clone https://github.com/mdl-systems/cocoro-llm-server.git
cd cocoro-llm-server

# 環境変数設定（4つのキーを埋める）
cp .env.example .env
vim .env
# 必須: HF_TOKEN / ANTHROPIC_API_KEY / LITELLM_MASTER_KEY / OPEN_WEBUI_SECRET_KEY
```

### 2. 起動（Docker Compose）

```bash
# 全サービス起動（初回はモデルDLで5〜15分かかる）
docker compose up -d

# 起動ログ確認（モデルロード完了まで待つ）
docker compose logs -f vllm-primary
# "Application startup complete." が出たら準備完了
```

### 3. 動作確認

```bash
# ヘルスチェック
curl http://192.168.50.112:4000/health/liveliness

# 推論テスト
curl http://192.168.50.112:4000/v1/chat/completions \
  -H "Authorization: Bearer mdl-llm-2026" \
  -H "Content-Type: application/json" \
  -d '{"model":"qwen3-coder","messages":[{"role":"user","content":"こんにちは"}]}'

# VRAM確認
nvidia-smi --query-gpu=memory.used,memory.free,memory.total --format=csv
```

---

## Windowsから同期（deploy.ps1）

```powershell
# 通常同期
.\deploy.ps1

# 変更プレビューのみ（実際には転送しない）
.\deploy.ps1 -DryRun

# 同期後にDockerを自動再起動
.\deploy.ps1 -Restart
```

---

## チーム接続情報

### OpenHands / AntGravity

```
API Base URL : http://192.168.50.112:4000/v1
API Key      : <LITELLM_MASTER_KEY>
Model        : smart-coder  (または qwen3-coder / gpt-4o)
```

### cocoro-core (`192.168.50.92`)

```env
LLM_PROVIDER=openai
OPENAI_API_BASE=http://192.168.50.112:4000/v1
OPENAI_API_KEY=<LITELLM_MASTER_KEY>
OPENAI_MODEL=gpt-4o
```

### Open WebUI

```
http://192.168.50.112:3000
```

---

## ログ確認

```bash
docker compose logs vllm-primary -f
docker compose logs litellm -f
```

---

## VRAM配分 (94.96GB GDDR7)

| 用途 | 割当 | 備考 |
|---|---|---|
| Qwen3-Coder-Next-FP8 weights | ~70 GiB | FP8量子化 |
| KV キャッシュ (fp8) | ~17 GiB | gpu_util=0.92 |
| CUDA オーバーヘッド | ~8 GiB | バッファ |

> `PRIMARY_GPU_UTIL=0.92` で VRAM 94.96GB の92% ≈ 87.4GBを確保。

---

## トラブルシューティング

### vLLM起動に失敗する

```bash
# VRAM確認（他プロセスが残っていないか）
nvidia-smi
pkill -f "vllm" || true

# ポート確認
ss -tlnp | grep 8000

# ログ確認
docker compose logs vllm-primary --tail=50
```

### Blackwell SM_120でFlashInferがクラッシュ

```bash
# .envに追記してFlashInferを無効化
VLLM_ATTENTION_BACKEND=TRITON_ATTN

# 再起動
docker compose down && docker compose up -d
```

### LiteLLMのルーティング確認

```bash
docker compose logs litellm 2>&1 | grep -E "model|routing|error"
docker compose restart litellm
```

---

## 絶対ルール

- **クイックフィックス禁止** — 根本原因を特定してから修正する
- **モデルウェイトを git にコミットしない** — `.gitignore` で除外済み
- **API キーを平文でコードに書かない** — 必ず `.env` 経由
- **`--tool-call-parser qwen3_coder` を外さない** — OpenHandsが壊れる
- **`--enable-prefix-caching` を外さない** — Open WebUI共存の生命線
- **クライアントはポート4000経由** — 8000はLAN内デバッグのみ

---

## 関連リポジトリ

| リポジトリ | 役割 |
|---|---|
| [cocoro-core](https://github.com/mdl-systems/cocoro-core) | 人格 AI エンジン |
| [cocoro-console](https://github.com/mdl-systems/cocoro-console) | 管理 UI |
| [cocoro-agent](https://github.com/mdl-systems/cocoro-agent) | エージェント |
| [cocoro-docs](https://github.com/mdl-systems/cocoro-docs) | ドキュメント |