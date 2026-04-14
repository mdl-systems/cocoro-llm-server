# cocoro-llm-server

> **mdl-systems 社内 LLM 推論サーバー**  
> OpenAI 互換 API — トークン制限なし・完全プライベート  
> Host: `192.168.50.112` | GPU: RTX PRO 6000 Blackwell 94.96GB GDDR7

---

## アーキテクチャ概要

```
クライアント (cocoro-core / 開発者 / チームメンバー)
        │
        ▼  http://192.168.50.112:8000  (OpenAI互換)
   ┌─────────────┐
   │  LiteLLM    │  ← モデルエイリアス / 認証 / レートリミット
   └──────┬──────┘
          │ openai/qwen25-72b
          ▼
       :8080
  Qwen 2.5 72B AWQ     ← vLLM (ホスト直接起動)
  Weights: ~38GB
  KV cache: ~47GB
  合計: ~85GB / 94.96GB

          +
   ┌─────────────┐
   │  Prometheus │ :9090  ← メトリクス収集
   │  Grafana    │ :3000  ← ダッシュボード
   └─────────────┘
```

---

## モデルエイリアス

| エイリアス | 実モデル | 備考 |
|---|---|---|
| `gpt-4o` | Qwen 2.5 72B Instruct AWQ | メインエイリアス |
| `gpt-4o-mini` | Qwen 2.5 72B Instruct AWQ | 互換性・既存クライアント対応 |
| `qwen25-72b` | Qwen 2.5 72B Instruct AWQ | 直接アクセス用 |
| `claude-sonnet` | Anthropic Claude | フォールバック (vLLM障害時) |

クライアントは `gpt-4o` / `gpt-4o-mini` をそのまま使用可能。

---

## クイックスタート

### 1. 初回セットアップ (サーバー側)

```bash
# リポジトリ clone
git clone git@github.com:mdl-systems/cocoro-llm-server.git
cd cocoro-llm-server

# 環境変数設定
cp .env.example .env
vim .env   # HF_TOKEN・LITELLM_MASTER_KEY・ANTHROPIC_API_KEY を設定

# モデルダウンロード (~20GB、1〜2時間)
source ~/.venv/cocoro-llm/bin/activate
mkdir -p /models/qwen25-72b
nohup huggingface-cli download \
  Qwen/Qwen2.5-72B-Instruct-AWQ \
  --local-dir /models/qwen25-72b \
  --resume-download \
  > ~/qwen72b_download.log 2>&1 &
echo "PID: $!"
```

### 2. 起動

```bash
# vLLM 起動 (モデルロード完了まで最大15分)
source ~/.venv/cocoro-llm/bin/activate
nohup bash vllm/start_primary.sh > /tmp/vllm_primary.log 2>&1 &

# 起動確認
curl -sf http://localhost:8080/health && echo "✅ vLLM Ready"

# Gateway + モニタリングを Docker で起動
docker compose -f docker/docker-compose.yml --env-file .env up -d
```

### 3. 動作確認

```bash
# vLLM 直接テスト
curl -s http://localhost:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"qwen25-72b","messages":[{"role":"user","content":"日本語で自己紹介してください"}],"max_tokens":100}' \
  | python3 -m json.tool | grep content

# LiteLLM 経由テスト
curl -s http://localhost:8000/v1/chat/completions \
  -H "Authorization: Bearer mdl-llm-2026" \
  -H "Content-Type: application/json" \
  -d '{"model":"gpt-4o","messages":[{"role":"user","content":"稼働確認。一言で答えて"}],"max_tokens":50}' \
  | python3 -c "import sys,json; d=json.load(sys.stdin); print('✅ 完成:', d['choices'][0]['message']['content'])"

# VRAM 確認
nvidia-smi
```

---

## 開発環境での起動

```bash
# vLLM をフォアグラウンドで起動してログを直接確認
source ~/.venv/cocoro-llm/bin/activate
bash vllm/start_primary.sh

# 本番の代わりに開発用 Compose を使用
docker compose -f docker/docker-compose.yml -f docker/docker-compose.dev.yml --env-file .env up -d
```

---

## ログ確認

```bash
# vLLM ログ
tail -f /var/log/cocoro-llm/vllm-primary.log
# または nohup 起動時は
tail -f /tmp/vllm_primary.log

# LiteLLM ログ
docker logs litellm -f

# ヘルスチェックログ
tail -f /var/log/cocoro-llm/health.log
```

---

## テスト

```bash
# 推論品質テスト
python tests/test_inference.py

# 並列負荷テスト (10同時リクエスト、60秒)
python tests/test_throughput.py --users 10 --duration 60

# cocoro-core 連携テスト
python tests/test_cocoro_compat.py
```

---

## モニタリング

| サービス | URL | 認証 |
|---|---|---|
| Grafana ダッシュボード | http://192.168.50.112:3000 | admin / `GRAFANA_ADMIN_PASSWORD` |
| Prometheus | http://192.168.50.112:9090 | なし |
| LiteLLM Admin UI | http://192.168.50.112:8000/ui | `LITELLM_MASTER_KEY` |
| vLLM metrics | http://192.168.50.112:8080/metrics | なし |

---

## VRAM 配分 (94.96GB GDDR7)

| 用途 | 割当 | 備考 |
|---|---|---|
| Qwen 2.5 72B AWQ (weights) | ~38GB | AWQ Q4量子化 |
| KV キャッシュ | ~47GB | 64並列 × 32K context |
| 合計使用 | ~85GB (gpu_util=0.90) | 残り ~10GB バッファ |

> `PRIMARY_GPU_UTIL=0.90` で VRAM 94.96GB の90% ≈ 85.5GB を確保。

---

## チーム接続情報

```
OPENAI_API_BASE = http://192.168.50.112:8000/v1
OPENAI_API_KEY  = mdl-llm-2026
model           = "gpt-4o" または "gpt-4o-mini"
```

cocoro-core (`192.168.50.92`) の `.env`:

```env
LLM_PROVIDER=ollama
OLLAMA_BASE_URL=http://192.168.50.112:8000
OLLAMA_MODEL=gpt-4o
```

---

## トラブルシューティング

### vLLM が起動しない

```bash
# VRAM 確認 (他プロセスが残っていないか)
nvidia-smi
pkill -f "vllm" || true

# ポート確認
ss -tlnp | grep 8080

# 詳細ログ確認
tail -50 /var/log/cocoro-llm/vllm-primary.log
```

### アテンションバックエンドのクラッシュ (Blackwell SM_120)

FlashInfer でクラッシュする場合、Triton バックエンドに切り替える:

```bash
# .env に追記
VLLM_ATTENTION_BACKEND=TRITON_ATTN

# vLLM 再起動
pkill -f "vllm" && bash vllm/start_primary.sh
```

### LiteLLM のルーティングを確認

```bash
# LiteLLM ログでルーティング判定を確認
docker logs litellm 2>&1 | grep -E "model|routing|error"

# コンテナ再起動
docker compose -f docker/docker-compose.yml --env-file .env restart litellm
```

---

## ディレクトリ構成

```
cocoro-llm-server/
├── vllm/               # vLLM 起動スクリプト
│   ├── start_primary.sh    ← Qwen 2.5 72B AWQ 起動
│   └── modelfile/
├── litellm/            # LiteLLM API ゲートウェイ設定
│   ├── config.yaml         ← モデルエイリアス定義
│   └── proxy_config.py
├── docker/             # Docker Compose (LiteLLM・監視系)
│   ├── docker-compose.yml
│   ├── docker-compose.dev.yml
│   └── nginx/
├── monitoring/         # Prometheus・Grafana 設定
├── scripts/            # セットアップ・運用スクリプト
├── tests/              # テスト一式
└── docs/               # アーキテクチャ・運用ドキュメント
```

---

## 絶対ルール

- **クイックフィックス禁止** — 根本原因を特定してから修正する
- **モデルウェイトを git にコミットしない** — `.gitignore` で除外済み
- **API キーを平文でコードに書かない** — 必ず `.env` 経由
- **docker compose は必ず `--env-file .env` 付きで実行**

---

## 関連リポジトリ

| リポジトリ | 役割 |
|---|---|
| [cocoro-core](https://github.com/mdl-systems/cocoro-core) | 人格 AI エンジン |
| [cocoro-console](https://github.com/mdl-systems/cocoro-console) | 管理 UI |
| [cocoro-agent](https://github.com/mdl-systems/cocoro-agent) | エージェント |
| [cocoro-docs](https://github.com/mdl-systems/cocoro-docs) | ドキュメント |