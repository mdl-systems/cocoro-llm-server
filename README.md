# cocoro-llm-server

> ローカルGPU搭載サーバー上でLLMを動かし、OpenAI互換APIとして提供するサーバーリポジトリ。  
> `docker compose up -d` 1コマンドで推論サーバーが立ち上がります。

---

## アーキテクチャ

```
[OpenCode / Cursor / OpenHands]      [Claude Code]
              │                              │
              ▼ :4000/v1 (OpenAI互換)        ▼ :4001 (Anthropic互換)
        ┌──────────────┐              ┌─────────────────────┐
        │   LiteLLM    │◀─────────────│  anthropic-proxy    │
        │    :4000     │              │  :4001              │
        │              │              │  Anthropic ↔ OpenAI │
        │ smart-coder  │              │  双方向変換         │
        │ coco-local * │              └─────────────────────┘
        │ claude-sonnet│       * 公開名は SERVED_MODEL_NAME で変更可
        └──────┬───────┘
               │
       ┌───────┴────────┐
       ▼                ▼
  :8000 (内部)      Anthropic API
  vLLM Primary     (fallbackのみ)
  Qwen3.6-35B-A3B-FP8（マルチモーダル）
  VRAM: 35GB weights + ~24GB KV
  Context: 128K tokens
```

**ポート構成:**
- `:4000` LiteLLM — OpenAI互換 (OpenCode / Cursor 等)
- `:4001` anthropic-proxy — Anthropic互換 (Claude Code)
- `:8000` vLLM — サーバー内部デバッグのみ

---

## モデルルーティング

ローカルモデルの公開名は **`docker-compose.yml` の `x-served-model-name` アンカー1箇所で一元管理**されており、デフォルトは **`coco-local`**。下の表では `<MODEL>` と表記します。リネームは `docker-compose.yml` のその1行を書き換えて `docker compose down && docker compose up -d` するだけ。

| モデル名 | バックエンド | 用途 |
|---|---|---|
| `smart-coder` | ローカル優先 → Claude自動フォールバック | **推奨デフォルト** |
| `<MODEL>`（既定 `coco-local`） | vLLM ローカル直結 | 高速・プライバシー重視 |
| `claude-sonnet` | Anthropic API直接 | 難タスク・品質最優先（要 `ANTHROPIC_API_KEY`） |
| `interactive` / `worker` | ローカル(優先度付き) | サブエージェント並列向け |
| `claude-sonnet-4-6` / `claude-opus-4-7` / `claude-haiku-4-5-20251001` | ローカルエイリアス | **Claude Code 互換用**（内部はローカル vLLM） |
| `gpt-4o` / `gpt-4o-mini` | ローカルエイリアス | 後方互換 |

> **Claude Code 用エイリアスの仕組み**: Claude Code は接続先のモデルとして `claude-sonnet-4-6` 等を指定してきますが、anthropic-proxy → LiteLLM の経路で**実体はローカル vLLM に流される**ように設定済みです。Claude Code 側のUIには「Sonnet 4.6」と表示されますが、応答しているのはローカルモデルです。

> **リネームの影響範囲**: クライアントが `coco-local` を**直接**呼んでいる箇所だけ新名に更新が必要。`smart-coder` / `claude-*` / `gpt-*` エイリアスを使っているクライアントは**無修正で動く**(推奨デフォルトは `smart-coder` なので大体これで済む)。

---

## ハードウェア要件

| 項目 | 要件 |
|---|---|
| GPU | NVIDIA GPU（VRAM 24GB以上推奨） |
| VRAM（推奨） | 64GB以上（Qwen3.6-35B-A3B-FP8 + 128Kコンテキスト用） |
| OS | Linux（Ubuntu 22.04+ / Debian 12+） |
| Docker | Docker Engine + NVIDIA Container Toolkit |

---

## ネットワーク前提

クライアントPCがこのサーバーに到達できる必要があります。以下のどちらかの方法で接続環境を用意してください。

### 推奨：Tailscale 経由（場所を問わず使える）

サーバーPCに [Tailscale](https://tailscale.com/) をインストールし、クライアントPCと同じアカウントでログインします。物理ネットワークが違っても、外出先や別の家からも接続可能になります。

```bash
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up
# サーバーの Tailscale IP を確認（クライアントに伝える）
tailscale ip -4
```

> サブネットルーティングを使う場合は `sudo tailscale up --advertise-routes=192.168.x.0/24` で LAN サブネットを共有できます。

### 代替：同じLAN

サーバーPCとクライアントPCが**同じWiFi/同じルーター下**にあれば、追加設定なしで接続できます。サーバーPCの LAN IP（`192.168.x.x`）を使います。

> ⚠️ **インターネットへの直接公開は推奨しません。** APIキー漏洩・攻撃のリスクがあります。リモート利用は必ず Tailscale など VPN 経由にしてください。

---

## クイックスタート

### 0. Linux 初回構築（既に NVIDIA + Docker 動いている場合はスキップ可）

新規 Linux サーバーで初めて使う場合、ドライバと Docker を入れます。

```bash
# 1) NVIDIA ドライバ + CUDA 12.8（Blackwell には CUDA 12.8 必須）
sudo bash scripts/setup_nvidia.sh
sudo reboot   # 完了後に必ず再起動

# 2) Docker + NVIDIA Container Toolkit
sudo bash scripts/setup_docker.sh

# 3) （推奨）Tailscale をインストール — リモート接続用
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up
```

> **Tailscale を入れない場合は同じ LAN（同じ WiFi/ルーター下）からしか接続できません。**外出先や別ネットワークから使うなら、ここで入れておくのが楽です。詳細は下の「ネットワーク前提」を参照。

### 1. リポジトリをクローン

```bash
git clone https://github.com/mdl-systems/cocoro-llm-server.git
cd cocoro-llm-server
```

### 2. 初回セットアップ（1コマンドで完結）

```bash
bash scripts/first_setup.sh
```

実行すると対話式で以下を設定します:

| 設定 | 説明 | 必須 |
|---|---|---|
| `LITELLM_MASTER_KEY` | クライアント接続用APIキー | **自動生成** |
| `HF_TOKEN` | HuggingFaceトークン（モデルDL用） | モデル未DL時のみ |
| `ANTHROPIC_API_KEY` | Claudeフォールバック用 | 任意 |

セットアップ完了後、接続情報が自動表示されます:

```
╔══════════════════════════════════════════════════════════╗
║   ✅ セットアップ完了！                                  ║
╠══════════════════════════════════════════════════════════╣
║   クライアントPCに以下の情報を入力してください           ║
╠══════════════════════════════════════════════════════════╣
║  Server IP : 192.168.x.x                                 ║
║  API Key   : coco-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx       ║
╚══════════════════════════════════════════════════════════╝
```

> 接続情報は後から `bash scripts/show_connection_info.sh` で再確認できます。

### 3. 起動確認

```bash
# ヘルスチェック（vLLMの起動に5〜15分かかる場合があります）
curl http://localhost:4000/health/liveliness

# 起動ログを確認
docker compose logs -f vllm-primary
# "Application startup complete." が出たら準備完了
```

---

## 手動セットアップ（上級者向け）

`first_setup.sh` を使わず手動で設定する場合:

```bash
cp .env.example .env
vim .env
# 必須: LITELLM_MASTER_KEY（任意の文字列に変更）
# 任意: HF_TOKEN / ANTHROPIC_API_KEY
docker compose up -d
```

---

## Windowsから設定を同期する（deploy.ps1）

Windowsで設定ファイルを編集してサーバーに反映する場合：

```powershell
# サーバーのユーザー名とIPを指定して同期
.\deploy.ps1 -RemoteUser "your-user" -RemoteHost "192.168.x.x"

# 変更プレビューのみ（実際には転送しない）
.\deploy.ps1 -RemoteUser "your-user" -RemoteHost "192.168.x.x" -DryRun

# 同期後にDockerを自動再起動
.\deploy.ps1 -RemoteUser "your-user" -RemoteHost "192.168.x.x" -Restart
```

---

## クライアントからの接続

クライアント側の設定は **[cocoro-llm-client](https://github.com/mdl-systems/cocoro-llm-client)** リポジトリのスクリプト1本で完了します。OpenCode / Claude Code どちらでも対応。

### OpenCode / Cursor / OpenHands 等（OpenAI互換クライアント）

```
API Base URL : http://<SERVER_IP>:4000/v1
API Key      : <LITELLM_MASTER_KEY の値>
Model        : smart-coder
```

### Claude Code

```
ANTHROPIC_BASE_URL : http://<SERVER_IP>:4001
ANTHROPIC_API_KEY  : <LITELLM_MASTER_KEY の値>
```

`~/.claude/settings.json` の `env` ブロックにこの2つを書けば、PC全体・どのフォルダでも `claude` コマンドがローカルLLMを呼ぶようになります。クライアントリポジトリの `setup-claude-code.ps1` / `.sh` が自動でやってくれます。

---

## ログ確認

```bash
docker compose logs vllm-primary -f
docker compose logs litellm -f
```

---

## VRAM配分（参考: RTX PRO 6000 Blackwell 94.96GB）

| 用途 | 割当 | 備考 |
|---|---|---|
| Qwen3.6-35B-A3B-FP8 weights | ~35 GiB | FP8量子化、35B total / 3B active MoE |
| KV キャッシュ (fp8) | ~24 GiB | gpu_util=0.70・max-model-len=128K |
| CUDA オーバーヘッド | ~8 GiB | バッファ |
| **空き** | **~28 GiB** | 第2モデル増設や並列増強の余地 |

> VRAM配分は `docker-compose.yml` の `--gpu-memory-utilization` / `--max-model-len` で調整します（git管理）。

---

## モデルを変えたい場合

vLLM は起動時にモデルを HuggingFace から自動ダウンロードします（初回 5〜15分）。

**重要**: モデル設定は `docker-compose.yml` に直書きで一元化されています。
**`.env` には設定しません**（`.env` は秘密の値だけ）。
変更は **GitHub経由**（ローカルで編集 → commit → push → サーバーで `git pull && docker compose up -d`）が原則です。

### 🟢 同じ系統で別バージョン（Qwen3 の別サイズ等）

`docker-compose.yml` の `vllm-primary` コマンドの `--model` 行だけ編集:

```yaml
    command:
      - >
        exec python3 -m vllm.entrypoints.openai.api_server
        --model Qwen/Qwen3.6-35B-A3B-FP8   # ← ここを変更
        --served-model-name "$$SERVED_MODEL_NAME"  # ← 変更不要(公開名は anchor 管理)
        ...
```

そのあと:

```bash
git add docker-compose.yml && git commit -m "switch model" && git push
# サーバー側で:
git pull && docker compose down && docker compose up -d
```

> **公開名(クライアントから呼ぶ名前)を変えたい場合**は、`docker-compose.yml` 冒頭の
> `x-served-model-name: &served_model_name "SERVED_MODEL_NAME=coco-local"` の
> `coco-local` 部分を書き換えるだけ。vLLM と LiteLLM 両方に同じ値が伝搬される。

### 🟡 別の量子化方式（FP8以外: AWQ / GPTQ 等）

`docker-compose.yml` の vLLM フラグも調整:

| フラグ | 用途 | 例 |
|---|---|---|
| `--quantization` | 量子化方式 | `fp8` / `awq` / `gptq` |
| `--max-model-len` | 最大コンテキスト | モデルが対応する範囲 |
| `--gpu-memory-utilization` | VRAM 使用率 | 0.5〜0.95 |

### 🔴 別系統のモデル（Llama / Mistral / DeepSeek 等）

ツールコールの形式が違うので、追加で以下も修正:

1. `docker-compose.yml`:
   - `--tool-call-parser qwen3_coder` → モデル対応のものに変更（Llama なら `llama3_json` 等）
   - `--reasoning-parser qwen3` → モデルに合わせて変更 or 削除
   - 公開名(`--served-model-name`)は `x-served-model-name` anchor で管理されているので、
     変えたい場合は anchor 1 箇所のみ編集すれば vLLM と LiteLLM 両方に反映される
2. `litellm/config.yaml.tmpl`: LiteLLM 設定はテンプレ。`${SERVED_MODEL_NAME}` プレースホルダ
   を使っており、コンテナ起動時に `entrypoint.sh` が sed で実値展開する

### ⚠️ VRAM 上限

GPU の VRAM（このサーバーは 94GB）を**超えるモデルは起動しません**。
- ✅ ~35GB クラス（Qwen3.6-35B-A3B-FP8 = 現行）
- ✅ ~70GB クラス（Qwen3-Coder-Next-FP8 等の旧構成）
- ❌ ~104GB（Llama-4-Scout-FP8）→ VRAM 超過で起動失敗
- ❌ 数百GB級（DeepSeek-V3 671B 等）→ 動作不可

事前にモデルカード（HuggingFace）でファイルサイズを確認してください。

---

## トラブルシューティング

### vLLM起動に失敗する

```bash
# VRAM確認（他プロセスが残っていないか）
nvidia-smi
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

- **モデルウェイトを git にコミットしない** — `.gitignore` で除外済み
- **API キーを平文でコードに書かない** — 必ず `.env` 経由
- **`--tool-call-parser qwen3_coder` を外さない** — ツールコールが壊れる
- **OpenAI互換クライアントは :4000、Claude Code は :4001 経由** — :8000はサーバー内部デバッグのみ
