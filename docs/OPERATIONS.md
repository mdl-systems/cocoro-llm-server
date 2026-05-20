# OPERATIONS.md — 運用と変更手順

> 「**何かを変えたい / 困った時はここを見る**」で完結するファイル。
> 全体像は [README.md](../README.md)、サーバー固有の事情は [SERVER.md](SERVER.md) を参照。

---

## 目次

- [絶対ルール](#絶対ルール)
- [変更パターン別の編集箇所](#変更パターン別の編集箇所)
- [よく使うコマンド](#よく使うコマンド)
- [ロールバック](#ロールバック)
- [トラブルシュート](#トラブルシュート)

---

## 絶対ルール

| ルール | 理由 |
|---|---|
| **API キーを平文でコードに書かない** | 必ず `.env` 経由（`.env` は git 管理外） |
| **チューニング値を `.env` に置かない** | モデル / VRAM / 並列数は `docker-compose.yml` の `x-config:` に集約 |
| **`--tool-call-parser` を外さない** | モデル固有のツールコール解釈に必要。外すとファイル操作系が全部壊れる |
| **`--reasoning-parser` を外さない** | 思考モード（`<think>` タグ）を解釈する。外すと応答に混入してツールコール出力も乱れる |
| **`--enable-prefix-caching` を外さない** | システムプロンプト再計算をスキップする KV キャッシュ効率の生命線 |
| **OpenAI 互換は :4000、Claude Code は :4001 経由** | `:8000` はサーバー内部デバッグ用のみ |

---

## 変更パターン別の編集箇所

> **原則: 変更はほぼ全て `docker-compose.yml` の冒頭 `x-config:` ブロックだけで完結する**。
> 下の `services:` 以下の本体は触らない設計。

### 🟢 ローカルモデルの公開名を変えたい（例: `coco-local` → `my-llm`）

| 編集箇所 | 値 |
|---|---|
| `docker-compose.yml` の `x-config:` | `SERVED_MODEL_NAME` |

ここ 1 箇所を書き換えるだけで、vLLM の `--served-model-name` と LiteLLM のローカル直結ルート名が同時に切り替わる。

**注意**: クライアント側で公開名を直接呼んでる箇所も新名に更新が必要。`smart-coder` / `claude-*` / `gpt-*` エイリアスはそのまま動くので、それらを使ってるクライアントは無修正で済む。

### 🟢 同じモデルファミリーで別バージョン（例: Qwen3.6 の別サイズ）

`docker-compose.yml` の `x-config:` の `HF_MODEL` だけを変える。parser や量子化方式はそのままで OK。

例:
```yaml
# Before
HF_MODEL: "Qwen/Qwen3.6-35B-A3B-FP8"
# After (小型版に変える)
HF_MODEL: "Qwen/Qwen3.6-7B-FP8"
```

### 🟡 別の量子化方式（FP8 → AWQ / GPTQ 等）

`HF_MODEL` / `QUANTIZATION` / `KV_CACHE_DTYPE` の 3 つをセットで変える。

例:
```yaml
# Before (FP8)
HF_MODEL:       "Qwen/Qwen3.6-35B-A3B-FP8"
QUANTIZATION:   "fp8"
KV_CACHE_DTYPE: "fp8"
# After (AWQ に変える)
HF_MODEL:       "Qwen/Qwen3.6-35B-A3B-AWQ"
QUANTIZATION:   "awq"
KV_CACHE_DTYPE: "auto"
```

### 🔴 別系統のモデル（Llama / Mistral / DeepSeek 等）

ツールコール形式が違うので `HF_MODEL` / `TOOL_CALL_PARSER` / `REASONING_PARSER` をまとめて差し替え:

例:
```yaml
# Before (Qwen系)
HF_MODEL:          "Qwen/Qwen3.6-35B-A3B-FP8"
TOOL_CALL_PARSER:  "qwen3_coder"
REASONING_PARSER:  "qwen3"
# After (Llama系に変える)
HF_MODEL:          "meta-llama/Llama-3.3-70B-Instruct"
TOOL_CALL_PARSER:  "llama3_json"
REASONING_PARSER:  ""                # 思考モード非対応モデルなら空文字
```

LiteLLM 側 (`litellm/config.yaml.tmpl`) は `${SERVED_MODEL_NAME}` プレースホルダ経由でモデル名を受け取るので、公開名を変えない限り**触らなくていい**。

### 🟢 コンテキスト総量を変えたい

| 値 | 意味 | 目安 |
|---|---|---|
| `MAX_MODEL_LEN` | 1 リクエストの最大コンテキスト（トークン数） | モデルが対応する範囲内 / 大きいほど長文を扱えるが KV メモリ消費が増える |

例:
```yaml
# Before (128K)
MAX_MODEL_LEN: "131072"
# 短文中心で並列を稼ぎたい
MAX_MODEL_LEN: "32768"     # 32K
# 長文を扱いたい
MAX_MODEL_LEN: "262144"    # 256K
```

> KV キャッシュ消費は `MAX_MODEL_LEN × MAX_NUM_SEQS` に比例。長くしすぎると並列数を下げないと OOM。

### 🟢 並列リクエスト数を変えたい

| 値 | 意味 | 目安 |
|---|---|---|
| `MAX_NUM_SEQS` | 同時に処理する最大リクエスト数 | 大きいほど並列性高いが各リクエストの KV 領域が圧縮される |

例:
```yaml
# Before
MAX_NUM_SEQS: "16"
# サブエージェントを大量並列にしたい
MAX_NUM_SEQS: "32"
# 1 リクエスト当たりの応答速度を優先したい
MAX_NUM_SEQS: "8"
```

### 🟢 VRAM 使用率を変えたい

| 値 | 意味 | 目安 |
|---|---|---|
| `GPU_MEMORY_UTIL` | vLLM が使う GPU メモリの割合 | 0.5 〜 0.95 / 大きいほど KV キャッシュ確保が増えて並列耐性向上、ただし OOM リスクも上がる |

例:
```yaml
# Before
GPU_MEMORY_UTIL: "0.70"
# 余裕を削って並列耐性を上げる
GPU_MEMORY_UTIL: "0.85"
# 他のプロセスにも GPU を譲りたい
GPU_MEMORY_UTIL: "0.50"
```

### 🟢 使う GPU を変えたい（複数 GPU 搭載時）

例:
```yaml
# Before (1 枚目)
CUDA_VISIBLE_GPU: "0"
# After (2 枚目に変える)
CUDA_VISIBLE_GPU: "1"
```

### 🟢 LiteLLM のルーティングや新エイリアスを追加したい

| 編集箇所 | 値 |
|---|---|
| `litellm/config.yaml.tmpl` | `model_list:` に新ルートを追記 |

### 🟢 秘密の値（API キー / トークン）を変えたい

| 編集箇所 | 注意 |
|---|---|
| サーバー上の `.env` | git 管理外なのでサーバー側で直接編集する |

---

### 変更の反映

上記いずれを変えた場合も:

```bash
docker compose down && docker compose up -d
```

---

## よく使うコマンド

```bash
# 全サービス起動
docker compose up -d

# 起動ログ確認（初回はモデル DL で 5〜15 分）
docker compose logs -f vllm-primary
# "Application startup complete." が出たら準備完了

# 全サービス停止
docker compose down

# 個別再起動（設定変更後）
docker compose restart litellm
docker compose restart anthropic-proxy

# フル再起動
docker compose down && docker compose up -d

# ヘルスチェック（一回 / 監視）
bash scripts/health_check.sh
watch -n 30 bash scripts/health_check.sh

# 接続情報の再表示
bash scripts/show_connection_info.sh

# VRAM 確認
nvidia-smi --query-gpu=memory.used,memory.free,memory.total --format=csv

# 推論テスト
curl http://localhost:4000/v1/chat/completions \
  -H "Authorization: Bearer ${LITELLM_MASTER_KEY}" \
  -H "Content-Type: application/json" \
  -d '{"model":"smart-coder","messages":[{"role":"user","content":"こんにちは"}]}'
```

---

## ロールバック

設定変更後にサービスが起動しなくなった等の時:

```bash
cd $REPO_DIR
git log --oneline -5                # 直近のコミットを確認
git checkout <前の安定コミットのハッシュ> -- docker-compose.yml
docker compose down && docker compose up -d
```

完全に戻す（最後の安定状態へ）:

```bash
git reset --hard <安定コミットのハッシュ>
docker compose down && docker compose up -d
```

> ⚠️ `git reset --hard` は未コミット変更を破棄する。事前にバックアップを推奨:
> `tar czf cocoro-backup-$(date +%Y%m%d-%H%M%S).tgz -C "$(dirname $REPO_DIR)" "$(basename $REPO_DIR)"`

---

## トラブルシュート

### vLLM が起動しない

```bash
# VRAM が他プロセスで埋まってないか
nvidia-smi

# ポート競合確認
ss -tlnp | grep 8000

# ログ確認
docker compose logs vllm-primary --tail=100
```

### Blackwell SM120 で FlashInfer がクラッシュする

`.env` に追記して FlashInfer を無効化:

```
VLLM_ATTENTION_BACKEND=TRITON_ATTN
```

その後 `docker compose down && docker compose up -d`。

### LiteLLM のルーティングがおかしい

```bash
docker compose logs litellm 2>&1 | grep -E "model|routing|error"
docker compose restart litellm
```

### モデル DL が終わらない

`HF_TOKEN` が正しいか確認。`.env` を見直して `docker compose down && docker compose up -d`。
