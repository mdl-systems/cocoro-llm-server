# cocoro-llm-server — 開発仕様書 & AntGravity プロンプト集

> IP: 192.168.50.112 / GPU: RTX PRO 6000 Blackwell 96GB / CPU: i9 285K / RAM: 128GB / SSD: 4TB

---

## 1. リポジトリ構成

```
github.com/mdl-systems/cocoro-llm-server/
├── CLAUDE.md                    ← AntGravity用マスタープロンプト（本ファイル参照）
├── README.md
├── .env.example
├── .gitignore
│
├── docker/
│   ├── docker-compose.yml       ← vLLM + LiteLLM + Prometheus + Grafana
│   ├── docker-compose.dev.yml   ← 開発用（ポート開放）
│   └── nginx/
│       └── nginx.conf           ← リバースプロキシ + ロードバランス
│
├── vllm/
│   ├── start_primary.sh         ← Llama 4 Scout 109B Q4 起動スクリプト
│   ├── start_secondary.sh       ← Qwen 3.5 32B Q5 起動スクリプト
│   └── modelfile/
│       ├── scout.yaml           ← vLLM設定（GPU割当・コンテキスト長）
│       └── qwen32b.yaml
│
├── litellm/
│   ├── config.yaml              ← ルーティングルール（モデルエイリアス定義）
│   └── proxy_config.py          ← カスタムルーティングロジック
│
├── gateway/
│   ├── router.py                ← プロンプト複雑度判定 → モデル振分
│   ├── personality_cache.py     ← cocoro-core 人格状態キャッシュ
│   └── health.py                ← 全サービス死活監視
│
├── monitoring/
│   ├── prometheus.yml
│   ├── grafana/
│   │   └── dashboards/
│   │       └── llm_metrics.json ← トークン/秒・VRAM・レイテンシ
│   └── alerts.yml
│
├── scripts/
│   ├── setup.sh                 ← 初回セットアップ（CUDA・vLLM・モデルDL）
│   ├── model_download.sh        ← HuggingFace からモデル取得
│   ├── health_check.sh
│   └── rotate_model.sh          ← モデル切替（無停止）
│
├── tests/
│   ├── test_inference.py        ← 推論品質テスト
│   ├── test_throughput.py       ← 並列負荷テスト（5〜10同時）
│   ├── test_cocoro_compat.py    ← cocoro-core API互換確認
│   └── test_gateway.py          ← ルーティングロジックテスト
│
└── docs/
    ├── ARCHITECTURE.md
    ├── MODEL_SELECTION.md       ← モデル選定根拠
    ├── VRAM_LAYOUT.md           ← 96GB割当詳細
    └── COCORO_INTEGRATION.md    ← cocoro-coreとの接続手順
```

---

## 2. CLAUDE.md（AntGravityに読み込ませるマスタープロンプト）

以下をそのまま `CLAUDE.md` としてリポジトリルートに配置する。

---

```markdown
# CLAUDE.md — cocoro-llm-server

> mdl-systems / cocoro-OS プロジェクトの社内LLM推論サーバーです。
> プロジェクト全体の概要は cocoro-docs/CLAUDE.md を参照してください。

---

## このrepoの役割

**社内LLM推論サーバー** — AntGravity・cocoro-core・開発チーム全員が
トークン制限なしで使える、OpenAI互換のローカルLLM基盤。

- ハードウェア: 192.168.50.112（RTX PRO 6000 Blackwell 96GB / i9 285K / 128GB RAM / 4TB NVMe）
- Primary Model: Llama 4 Scout 109B Q4_K_M（VRAM 55GB）
- Secondary Model: Qwen 3.5 32B Q5_K_M（VRAM 22GB）
- KVキャッシュ: 10GB（5〜10同時セッション対応）
- Gateway: LiteLLM（OpenAI互換 API :8000）

---

## 絶対ルール

- **クイックフィックス禁止** — 根本原因を特定してから修正する
- **モデルウェイトをgitにコミットしない** — `.gitignore` で除外済み
- **APIキーを平文でコードに書かない** — 必ず `.env` 経由
- **VRAM配分を変える場合は `docs/VRAM_LAYOUT.md` を先に更新**
- **cocoro-core の `.env` 変更は `docs/COCORO_INTEGRATION.md` に記録**

---

## テックスタック

| Component | Technology | Port |
|---|---|---|
| 推論エンジン | vLLM 0.4.x | :8080（Scout）/ :8081（Qwen） |
| APIゲートウェイ | LiteLLM Proxy | :8000（OpenAI互換） |
| リバースプロキシ | Nginx | :80 / :443 |
| モニタリング | Prometheus + Grafana | :9090 / :3000 |
| コンテナ管理 | Docker Compose | — |
| OS | Debian 13（既存mdlホスト） | — |

---

## 環境変数（.env）

```
# モデルパス
PRIMARY_MODEL_PATH=/models/llama4-scout-q4_k_m
SECONDARY_MODEL_PATH=/models/qwen35-32b-q5_k_m

# vLLM設定
PRIMARY_PORT=8080
SECONDARY_PORT=8081
PRIMARY_GPU_UTIL=0.58       # 55GB / 96GB
SECONDARY_GPU_UTIL=0.23     # 22GB / 96GB
MAX_MODEL_LEN=32768
MAX_NUM_SEQS=16             # 同時リクエスト上限

# LiteLLM
LITELLM_MASTER_KEY=<key>    # チーム共有キー
LITELLM_PORT=8000

# cocoro-core連携
COCORO_API_KEY=cocoro-2026
COCORO_CORE_URL=http://192.168.50.92:8001

# モニタリング
GRAFANA_ADMIN_PASSWORD=<password>
```

---

## よく使うコマンド

```bash
# 全サービス起動
docker compose up -d

# Primaryモデルのみ起動（開発時）
bash vllm/start_primary.sh

# ヘルスチェック（全サービス）
bash scripts/health_check.sh

# 推論テスト（OpenAI互換）
curl http://192.168.50.112:8000/v1/chat/completions \
  -H "Authorization: Bearer <LITELLM_MASTER_KEY>" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gpt-4o",
    "messages": [{"role": "user", "content": "こんにちは"}]
  }'

# VRAM使用状況確認
nvidia-smi --query-gpu=memory.used,memory.free --format=csv

# ログ確認
docker logs vllm-primary -f
docker logs litellm -f

# Grafanaダッシュボード
open http://192.168.50.112:3000

# モデル切替（無停止）
bash scripts/rotate_model.sh <model_name>

# 負荷テスト
python tests/test_throughput.py --users 10 --duration 60
```

---

## ディレクトリ構成

```
cocoro-llm-server/
├── docker/          # Docker設定一式
├── vllm/            # vLLM起動スクリプト・モデル設定
├── litellm/         # LiteLLMゲートウェイ設定
├── gateway/         # ルーティング・キャッシュロジック
├── monitoring/      # Prometheus・Grafana設定
├── scripts/         # セットアップ・運用スクリプト
├── tests/           # テスト一式
└── docs/            # アーキテクチャ・運用ドキュメント
```

---

## VRAM配分（96GB）

| 用途 | GB | 備考 |
|---|---|---|
| Llama 4 Scout 109B Q4_K_M | 55 | Primary — 複雑な推論・コード |
| Qwen 3.5 32B Q5_K_M | 22 | Secondary — 高速・日本語 |
| KVキャッシュ（共用） | 10 | 5〜10同時セッション |
| 予備（LoRA実験等） | 9 | 変更時は VRAM_LAYOUT.md 更新 |

---

## LiteLLM ルーティングルール

```yaml
# AntGravity・チームは以下エイリアスをそのまま使う
gpt-4o      → Llama 4 Scout（複雑な推論・長文）
gpt-4o-mini → Qwen 3.5 32B（短文・高速レスポンス）
claude-sonnet → Anthropic Claude（フォールバック・品質保証）
```

複雑度の判定基準:
- プロンプト 500トークン超 → Primary（Scout）
- コード生成・アーキテクチャ設計 → Primary（Scout）
- 短い質問・日本語会話 → Secondary（Qwen）
- cocoro-core の personality/emotion 処理 → Primary（Scout）

---

## cocoro-coreとの接続

cocoro-core（192.168.50.92）の `.env` を以下に変更:

```
LLM_PROVIDER=ollama
OLLAMA_BASE_URL=http://192.168.50.112:8000
OLLAMA_MODEL=gpt-4o
```

LiteLLMがOllama互換エンドポイントとしても動作するため、
cocoro-coreのC-4モジュール（local_llm.py）は変更不要。

---

## 開発時の注意事項

- vLLM起動順序: Primary → Secondary → LiteLLM → Nginx（順序依存あり）
- GPUメモリ不足時は `MAX_NUM_SEQS` を下げる前に `KVキャッシュ` を削る
- モデルウェイトは `/models/` に配置（4TB NVMe直下）
- Qwen 3.5はMoEのため `--enable-expert-parallel` フラグ推奨
- テストは必ず `test_cocoro_compat.py` を先に実行してcocoro連携を確認

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
```

---

## 3. AntGravity用 タスク別プロンプト集

### [A] セットアップ開始プロンプト

```
あなたはcocoro-llm-serverの開発を担当するエンジニアです。
CLAUDE.mdを読んで、このrepoの全体像を把握してください。

まず以下を実行してください:
1. `scripts/setup.sh` を作成（CUDA確認 → vLLMインストール → ディレクトリ作成）
2. `docker/docker-compose.yml` を作成（vLLM x2 + LiteLLM + Prometheus + Grafana）
3. `.env.example` を作成

制約:
- OS: Debian 13
- CUDA: 12.4以上が前提
- vLLMはpip install、Docker内ではなくホストで動かす（GPUドライバ直結のため）
- LiteLLM・Prometheus・GrafanaのみDockerで管理
- クイックフィックス禁止。各ファイルは完成形で作成すること
```

---

### [B] vLLM起動スクリプト作成プロンプト

```
cocoro-llm-server の vLLM起動スクリプトを作成してください。

環境:
- GPU: RTX PRO 6000 Blackwell 96GB GDDR7
- CUDA: 12.4
- vLLM: 最新安定版

作成するファイル:
1. vllm/start_primary.sh
   - モデル: Llama 4 Scout 109B（Q4_K_M GGUF または AWQ）
   - ポート: 8080
   - gpu-memory-utilization: 0.58（55GB）
   - max-model-len: 32768
   - served-model-name: llama4-scout
   - tensor-parallel-size: 1（シングルGPU）

2. vllm/start_secondary.sh
   - モデル: Qwen3.5-32B-Instruct（Q5_K_M）
   - ポート: 8081
   - gpu-memory-utilization: 0.23（22GB）
   - max-model-len: 16384
   - served-model-name: qwen-32b
   - --enable-expert-parallel フラグ追加

3. scripts/health_check.sh
   - 両vLLMのヘルスチェック
   - LiteLLMのヘルスチェック
   - VRAM使用量のログ出力
   - 異常時はSlackではなくファイルに記録（/var/log/cocoro-llm/health.log）

Blackwellアーキテクチャ固有の最適化フラグがあれば追加すること。
クイックフィックス禁止。動作保証できるスクリプトのみ作成。
```

---

### [C] LiteLLM設定プロンプト

```
cocoro-llm-server の LiteLLM設定を作成してください。

要件:
- OpenAI互換API（チーム全員・AntGravityがそのまま使える）
- モデルエイリアス:
  gpt-4o      → http://192.168.50.112:8080（Llama 4 Scout）
  gpt-4o-mini → http://192.168.50.112:8081（Qwen 3.5 32B）
  claude-sonnet → Anthropic API（フォールバック）
- 認証: LITELLM_MASTER_KEY環境変数
- レートリミット: ユーザーあたり100req/分
- ロギング: /var/log/cocoro-llm/litellm.log

作成するファイル:
1. litellm/config.yaml（メインルーティング設定）
2. docker/docker-compose.yml のlitellmサービス部分
3. AntGravityの接続設定手順（docs/ANTGRAVITY_SETUP.md）

AntGravity側の設定:
- API Base URL: http://192.168.50.112:8000
- API Key: <LITELLM_MASTER_KEY>
- Model: gpt-4o（そのまま使用可能）
```

---

### [D] cocoro-core連携テストプロンプト

```
cocoro-llm-server と cocoro-core の連携テストを作成してください。

テスト対象:
- cocoro-core: http://192.168.50.92:8001
- llm-server: http://192.168.50.112:8000
- API KEY: cocoro-2026

作成するファイル: tests/test_cocoro_compat.py

テストケース:
1. LiteLLM経由でchat補完が返ること
2. cocoro-coreの /chat エンドポイントがローカルLLMを呼んでいること
   （レスポンスヘッダーまたはログで確認）
3. 人格（Personality Engine）が維持されたまま返答していること
4. 5並列リクエストでもタイムアウトしないこと（30秒以内）
5. Gemini フォールバックが機能していること（vLLMを落とした状態で確認）

cocoro-coreの既存CLAUDE.mdにある認証方式:
  Authorization: Bearer <COCORO_API_KEY>

テスト実行方法もREADMEに追記すること。
```

---

### [E] Grafanaダッシュボード作成プロンプト

```
cocoro-llm-server の Grafanaダッシュボードを作成してください。

monitoring/grafana/dashboards/llm_metrics.json として作成。

表示するメトリクス:
1. VRAM使用量（Primary / Secondary / 合計）リアルタイム
2. トークン生成速度（tok/s）モデル別
3. 同時リクエスト数
4. リクエストレイテンシ（p50/p95/p99）
5. モデル別リクエスト数（Primary vs Secondary 比率）
6. エラー率

データソース: Prometheus（http://prometheus:9090）
vLLMのメトリクスエンドポイント: /metrics（Prometheusフォーマット）

加えて monitoring/prometheus.yml のスクレイプ設定も作成すること。
```

---

### [F] モデルダウンロードスクリプトプロンプト

```
cocoro-llm-server のモデルダウンロードスクリプトを作成してください。

作成するファイル: scripts/model_download.sh

ダウンロード対象:
1. Llama 4 Scout 109B Q4_K_M
   - HuggingFace: meta-llama/Llama-4-Scout-17B-16E-Instruct（AWQ quantized版を優先）
   - 保存先: /models/llama4-scout/
   
2. Qwen 3.5 32B Q5_K_M
   - HuggingFace: Qwen/Qwen3.5-32B-Instruct-GPTQ-Int5 または GGUF版
   - 保存先: /models/qwen35-32b/

要件:
- huggingface-cli 使用（tokenログイン済み前提）
- ダウンロード進捗をログに記録
- チェックサム検証
- 中断再開対応（resume-download）
- ストレージ空き容量確認（最低100GB必要）
- 4TB NVMeに十分な空きがあることを確認してから開始

HF_TOKEN は .env から読み込むこと。
```

---

## 4. 初回セットアップ手順（開発者向け）

```bash
# 1. repo clone
git clone git@github.com:mdl-systems/cocoro-llm-server.git
cd cocoro-llm-server

# 2. 環境変数設定
cp .env.example .env
vim .env  # キー類を設定

# 3. セットアップ実行
bash scripts/setup.sh

# 4. モデルダウンロード（時間がかかる）
bash scripts/model_download.sh

# 5. vLLM起動（Primary → Secondary の順）
bash vllm/start_primary.sh &
bash vllm/start_secondary.sh &

# 6. Gateway・監視系起動
docker compose up -d

# 7. ヘルスチェック
bash scripts/health_check.sh

# 8. cocoro-core の .env 更新
# LLM_PROVIDER=ollama
# OLLAMA_BASE_URL=http://192.168.50.112:8000
# OLLAMA_MODEL=gpt-4o

# 9. 連携テスト
python tests/test_cocoro_compat.py
```

---

## 5. IPアドレス対応表（社内ネットワーク）

| ホスト | IP | 役割 |
|---|---|---|
| cocoro-llm-server | 192.168.50.112 | LLM推論（本repo） |
| miniPC A | 192.168.50.92 | cocoro-core / cocoro-console |
| miniPC B | 192.168.50.86 | cocoro-agent |
| Debian mdl | — | AntGravity / 開発環境 |
