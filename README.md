# cocoro-llm-server

> **mdl-systems 社内 LLM 推論サーバー**  
> OpenAI 互換 API — トークン制限なし・完全プライベート  
> Host: `192.168.50.112` | GPU: RTX PRO 6000 Blackwell 96GB

---

## アーキテクチャ概要

```
クライアント (AntGravity / cocoro-core / 開発者)
        │
        ▼  http://192.168.50.112:8000  (OpenAI互換)
   ┌─────────────┐
   │  LiteLLM    │  ← モデルエイリアス / ルーティング / レートリミット
   └──────┬──────┘
          │
    ┌─────┴──────┐
    ▼            ▼
:8080          :8081
Llama 4 Scout  Qwen 3.5 32B     ← vLLM (ホスト直接起動)
109B Q4_K_M    32B Q5_K_M
≈55GB VRAM     ≈22GB VRAM

          +
   ┌─────────────┐
   │  Prometheus │ :9090  ← メトリクス収集
   │  Grafana    │ :3000  ← ダッシュボード
   └─────────────┘
```

---

## モデルエイリアス

| エイリアス | 実モデル | 用途 |
|---|---|---|
| `gpt-4o` | Llama 4 Scout 109B | コード・推論・長文 (>500トークン) |
| `gpt-4o-mini` | Qwen 3.5 32B | 短文・日本語会話・高速応答 |
| `claude-sonnet` | Anthropic Claude | フォールバック (vLLM障害時) |

ルーティングは自動判定。クライアントは `gpt-4o` / `gpt-4o-mini` を普通に使えばよい。

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

# NVIDIA ドライバ + CUDA 12.8 のセットアップ (初回のみ)
sudo bash scripts/setup_nvidia.sh

# vLLM 仮想環境のセットアップ (初回のみ、30分程度)
sudo bash scripts/setup_vllm.sh

# モデルダウンロード (初回のみ、時間がかかる)
bash scripts/model_download.sh

# systemd サービス登録
sudo bash scripts/install_systemd.sh
```

### 2. 起動

```bash
# vLLM を systemd で起動 (推奨)
sudo systemctl start vllm-primary
# モデルロード完了を待つ (Llama 4 Scout は最大10分)
sudo systemctl start vllm-secondary

# Gateway + モニタリングを Docker で起動
cd docker
docker compose up -d

# ヘルスチェック
bash scripts/health_check.sh
```

### 3. 動作確認

```bash
# LiteLLM 経由で推論テスト
curl http://192.168.50.112:8000/v1/chat/completions \
  -H "Authorization: Bearer <LITELLM_MASTER_KEY>" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gpt-4o",
    "messages": [{"role": "user", "content": "こんにちは"}]
  }'

# VRAM 確認
nvidia-smi

# サービス状態確認
sudo systemctl status vllm-primary vllm-secondary
docker compose ps
```

---

## 開発環境での起動

```bash
# 本番の代わりに開発用 Compose を使用
cd docker
docker compose -f docker-compose.yml -f docker-compose.dev.yml up -d

# vLLM は手動で起動して stdout を直接確認
bash vllm/start_primary.sh    # フォアグラウンドでログ確認可能
bash vllm/start_secondary.sh
```

---

## ログ確認

```bash
# vLLM ログ
sudo journalctl -u vllm-primary -f
sudo journalctl -u vllm-secondary -f
tail -f /var/log/cocoro-llm/vllm-primary.log
tail -f /var/log/cocoro-llm/vllm-secondary.log

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

# ルーティングロジックテスト
python tests/test_gateway.py

# カスタムルーター単体テスト
python litellm/proxy_config.py
```

---

## モニタリング

| サービス | URL | 認証 |
|---|---|---|
| Grafana ダッシュボード | http://192.168.50.112:3000 | admin / `GRAFANA_ADMIN_PASSWORD` |
| Prometheus | http://192.168.50.112:9090 | なし |
| LiteLLM Admin UI | http://192.168.50.112:8000/ui | `LITELLM_MASTER_KEY` |
| vLLM Primary metrics | http://192.168.50.112:8080/metrics | なし |
| vLLM Secondary metrics | http://192.168.50.112:8081/metrics | なし |

---

## VRAM 配分 (96GB)

| 用途 | 割当 | 備考 |
|---|---|---|
| Llama 4 Scout 109B Q4_K_M | 55GB (0.58) | Primary — コード・推論 |
| Qwen 3.5 32B Q5_K_M | 22GB (0.23) | Secondary — 高速・日本語 |
| KV キャッシュ (共用) | 10GB | 5〜10 同時セッション |
| 予備 | 9GB | LoRA 実験等 |

> **変更禁止**: VRAM 配分を変える場合は先に `docs/VRAM_LAYOUT.md` を更新すること。

---

## cocoro-core との接続

cocoro-core (`192.168.50.92`) の `.env` を以下に変更:

```env
LLM_PROVIDER=ollama
OLLAMA_BASE_URL=http://192.168.50.112:8000
OLLAMA_MODEL=gpt-4o
```

詳細は [docs/COCORO_INTEGRATION.md](docs/COCORO_INTEGRATION.md) を参照。

---

## トラブルシューティング

### vLLM が起動しない

```bash
# VRAM 確認
nvidia-smi

# ポート確認
ss -tlnp | grep -E '8080|8081'

# 詳細ログ確認
sudo journalctl -u vllm-primary --since "10 minutes ago"
```

### アテンションバックエンドのクラッシュ (Blackwell)

FlashInfer でクラッシュする場合、Triton バックエンドに切り替える:

```bash
# .env に追記
VLLM_ATTENTION_BACKEND=TRITON_ATTN

sudo systemctl restart vllm-primary vllm-secondary
```

### LiteLLM のルーティングを手動確認

```bash
# カスタムルーターのテスト
python litellm/proxy_config.py

# LiteLLM ログでルーティング判定を確認
docker logs litellm 2>&1 | grep "\[router\]"
```

---

## ディレクトリ構成

```
cocoro-llm-server/
├── vllm/               # vLLM 起動スクリプト・モデル設定
│   ├── start_primary.sh
│   ├── start_secondary.sh
│   └── modelfile/
├── litellm/            # LiteLLM API ゲートウェイ設定
│   ├── config.yaml
│   └── proxy_config.py  ← カスタムルーティングロジック
├── systemd/            # systemd サービスファイル
│   ├── vllm-primary.service
│   └── vllm-secondary.service
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
- **VRAM 配分を変える場合は `docs/VRAM_LAYOUT.md` を先に更新**

---

## 関連リポジトリ

| リポジトリ | 役割 |
|---|---|
| [cocoro-core](https://github.com/mdl-systems/cocoro-core) | 人格 AI エンジン |
| [cocoro-console](https://github.com/mdl-systems/cocoro-console) | 管理 UI |
| [cocoro-agent](https://github.com/mdl-systems/cocoro-agent) | エージェント |
| [cocoro-docs](https://github.com/mdl-systems/cocoro-docs) | ドキュメント |