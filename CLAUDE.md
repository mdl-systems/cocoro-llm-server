# CLAUDE.md — cocoro-llm-server
# AIエージェント（Claude Code / OpenCode / OpenHands / Antigravity 等）向け引き継ぎ書

> ローカルGPUサーバー上でLLMを動かし、OpenAI互換APIとして提供するサーバーリポジトリです。

---

## このリポジトリの役割

**ローカルLLM推論サーバー** — OpenAI互換 API (:4000) と Anthropic互換 API (:4001) を提供し、
OpenCode・Claude Code・OpenHands等のAIコーディングツールから接続して使う基盤。

- Primary Model: **Qwen3.6-35B-A3B-FP8**（マルチモーダル: テキスト/コード + 画像/動画。VRAM ~35GB weights FP8、256K context）
- Gateway: LiteLLM（OpenAI互換 :4000）+ anthropic-proxy（Anthropic互換 :4001）
- コンテナ管理: Docker Compose（`docker compose up -d` で全サービス起動）

---

## 🤖 セットアップ実行順序（AIエージェント向け）

新しい Linux サーバー（Debian 13 推奨）に clone した直後から動かすまでの手順:

```
1. GPU 確認
   nvidia-smi
   → 動かない場合は ↓ Step 2

2. NVIDIA ドライバ + CUDA 12.8 セットアップ（未インストールの場合）
   sudo bash scripts/setup_nvidia.sh
   → 完了後に sudo reboot が必要

3. Docker + NVIDIA Container Toolkit セットアップ（未インストールの場合）
   sudo bash scripts/setup_docker.sh

4. （推奨）Tailscale インストール — リモート接続を可能にする
   curl -fsSL https://tailscale.com/install.sh | sh
   sudo tailscale up
   → 同じ tailnet にいないクライアントPCからは接続できないので、
     クライアント側にも同じ Tailscale アカウントでのログインが必要。

5. .env 生成 + Docker サービス起動
   bash scripts/first_setup.sh
   → 対話式で APIキー自動生成 / HF_TOKEN / ANTHROPIC_API_KEY を設定
   → 完了後、接続情報（Server IP / API Key）を表示

6. 起動確認
   curl http://localhost:4000/health/liveliness   # 起動には 5〜15 分（モデル DL）
   docker compose logs -f vllm-primary             # "Application startup complete." で完了

7. クライアントへ接続情報を伝える
   bash scripts/show_connection_info.sh
   → Tailscale IP（推奨）と LAN IP の両方を表示
```

**条件分岐の判断基準**:
- `nvidia-smi` がエラー → Step 2 から
- `docker --version` がエラー → Step 3 から
- 既に動いている設定（モデル/VRAM/並列数）を変えたいだけ → `docker-compose.yml` を git 経由で変更し、サーバーで `git pull && docker compose up -d`（「開発フロー」参照）

---

## 絶対ルール

- **GitHub が唯一の正（最重要）** — 編集は必ず commit & push。**サーバーで追跡ファイルを手編集しない**。サーバーは `git pull && docker compose up -d` で反映するだけ。詳細は下記「開発フロー」
- **クイックフィックス禁止** — 根本原因を特定してから修正する
- **モデルウェイトをgitにコミットしない** — `.gitignore` で除外済み
- **APIキーを平文でコードに書かない** — 必ず `.env` 経由（`.env` は git 管理外）
- **チューニング値を `.env` に置かない** — モデル/VRAM/並列数は `docker-compose.yml` に直書き（git管理で一元化）。`.env` は秘密の値専用
- **`--tool-call-parser qwen3_coder` を外さない** — ツールコール（ファイル操作等）が壊れる
- **`--reasoning-parser qwen3` を外さない** — Qwen3.6 の思考モード解釈に必要（Qwen公式推奨）
- **`--enable-prefix-caching` を外さない** — KVキャッシュ効率の生命線
- **OpenAI互換クライアントは :4000、Claude Code は :4001 経由** — :8000 はサーバー内部デバッグ用のみ
- **VRAM配分を変える場合は docs/ARCHITECTURE.md を先に更新**

---

## 開発フロー（厳守 — 次のエージェントへ）

このリポジトリは「ローカル/手元PC」「GitHub」「GPUサーバー」の3か所に存在しうる。
**両方を手で編集すると必ず乖離して事故る**（過去に発生し仕切り直し済み）。以下を厳守:

```
[編集する場所]              [GitHub: 唯一の正]            [GPUサーバー]
 ローカルクローン  ──push──▶  origin/main   ──git pull──▶  実行のみ
                                                          (手編集しない)
```

> 以下、`$REPO_DIR` はサーバー上でリポジトリをクローンしたパス（例: `~/cocoro-llm-server`）を指します。

1. **コード/設定の変更は必ず GitHub 経由**。ローカル or 手元PCで編集 → commit → push。
2. **サーバーは反映するだけ**: `cd $REPO_DIR && git pull && docker compose up -d`。
   サーバー上で `docker-compose.yml` 等の追跡ファイルを直接編集してはいけない。
3. **`.env` は秘密の値だけ**（`HF_TOKEN` / `LITELLM_MASTER_KEY` / `ANTHROPIC_API_KEY`）。
   git 管理外。サーバーで初回に1度だけ設定し、以後触らない。
   モデル選定・VRAM配分・並列数などのチューニングは `docker-compose.yml` に直書き。
4. サーバーの git が `dubious ownership` で止まる場合は
   `git config --global --add safe.directory $REPO_DIR`（root で1度）。
5. 破壊的な仕切り直しの前は必ずフルバックアップ:
   `tar czf /root/cocoro-backup-$(date +%Y%m%d-%H%M%S).tgz -C "$(dirname $REPO_DIR)" "$(basename $REPO_DIR)"`

> 接続はサーバーが鍵認証を受け付けないため Python paramiko で SSH する（Windows標準sshは不可）。

---

## テックスタック

| Component | Technology | Port |
|---|---|---|
| 推論エンジン | vLLM (Docker, Blackwell最適化) | :8000（内部）|
| OpenAI互換ゲートウェイ | LiteLLM Proxy | :4000 |
| Anthropic互換プロキシ | anthropic-proxy (FastAPI) | :4001 |
| コンテナ管理 | Docker Compose | — |

---

## モデルルーティング（LiteLLM）

| モデル名 | バックエンド | 用途 |
|---|---|---|
| `qwen3-coder` | vLLM ローカル | 普段使い（コーディング）|
| `claude-sonnet` | Anthropic API | 難タスク・品質最優先（要 `ANTHROPIC_API_KEY`） |
| `smart-coder` | ローカル優先 → Claude自動フォールバック | 信頼性重視ワークフロー |
| `claude-sonnet-4-6` / `claude-opus-4-7` / `claude-haiku-4-5-20251001` | qwen3-coder エイリアス | **Claude Code 互換用**（内部はローカル vLLM） |
| `gpt-4o` / `gpt-4o-mini` | qwen3-coder エイリアス | 後方互換 |

> **Claude Code 用エイリアス**: Claude Code は `claude-sonnet-4-6` 等のモデル名を送ってきますが、LiteLLM 側で qwen3-coder にマップしているため、**実体はすべてローカルの vLLM が応答**します。Claude Code の UI に「Sonnet 4.6」と表示されてもローカル LLM 応答なのが正常動作。

---

## 環境変数（.env）— 秘密の値だけ

`.env` には**秘密の値のみ**を置く（チューニングは `docker-compose.yml` に直書き）:
- `LITELLM_MASTER_KEY` — **必須**。クライアントが接続するAPIキー（first_setup.sh で自動生成）
- `HF_TOKEN` — モデル未DL時のみ必須。HuggingFace アクセストークン
- `ANTHROPIC_API_KEY` — 任意。Claude フォールバック用
- `HF_CACHE_DIR` — 任意。未設定なら `/hf_cache`（通常変更不要）

> モデル名・`--gpu-memory-utilization`・`--max-model-len`・`--max-num-seqs` 等は
> `docker-compose.yml` の `vllm-primary` コマンドに直書き。変更は git 経由で行う。

---

## よく使うコマンド

```bash
# 全サービス起動
docker compose up -d

# 起動ログ確認（初回はモデルDLで5〜15分かかる）
docker compose logs -f vllm-primary
# "Application startup complete." が出たら準備完了

# ヘルスチェック（サーバー上で実行）
curl http://localhost:4000/health/liveliness   # LiteLLM
curl -I http://localhost:4001/                  # anthropic-proxy

# 推論テスト
curl http://localhost:4000/v1/chat/completions \
  -H "Authorization: Bearer ${LITELLM_MASTER_KEY}" \
  -H "Content-Type: application/json" \
  -d '{"model":"qwen3-coder","messages":[{"role":"user","content":"こんにちは"}]}'

# VRAM確認
nvidia-smi --query-gpu=memory.used,memory.free,memory.total --format=csv

# ログ確認
docker compose logs litellm -f
docker compose logs vllm-primary -f
docker compose logs anthropic-proxy -f

# 再起動（設定変更後）
docker compose restart litellm
docker compose down && docker compose up -d  # フル再起動

# 接続情報の再表示
bash scripts/show_connection_info.sh
```

---

## クライアントからの接続設定

クライアント側リポジトリ（[cocoro-llm-client](https://github.com/mdl-systems/cocoro-llm-client)）を参照してください。

### OpenCode / Cursor / OpenHands 等（OpenAI互換）

```
API Base URL: http://<SERVER_IP>:4000/v1
API Key:      <LITELLM_MASTER_KEY の値>
Model:        smart-coder  (または qwen3-coder / gpt-4o)
```

### Claude Code（Anthropic互換）

```
ANTHROPIC_BASE_URL: http://<SERVER_IP>:4001
ANTHROPIC_API_KEY:  <LITELLM_MASTER_KEY の値>
```

`<SERVER_IP>` は **Tailscale IP（推奨）** または **LAN IP**。`scripts/show_connection_info.sh` で両方表示される。

---

## 更新履歴

| 日付 | 更新内容 |
|---|---| 
| 2026-04-05 | 初版作成 — vLLM + LiteLLM構成確定 |
| 2026-04-14 | Qwen2.5-72B-AWQ暫定運用 |
| 2026-05-05 | Qwen3-Coder-Next-FP8に移行。LiteLLM 3ルート構成。 |
| 2026-05-07 | Open WebUI・モニタリングを最小構成から除外。 |
| 2026-05-08 | anthropic-proxy 追加（Claude Code 対応）。 |
| 2026-05-11 | リポジトリ最小構成へ整理。Tailscale をネットワーク前提に追加。AIエージェント向け実行順序を明記。 |
| 2026-05-16 | **Qwen3.6-35B-A3B-FP8 に移行**（マルチモーダル: 画像/動画対応、VRAM 70→35GB）。`--reasoning-parser qwen3` 追加。 |
| 2026-05-16 | サーバーを origin/main に仕切り直し（乖離解消）。**開発フロー＝GitHub唯一の正・サーバーpullのみ**を明文化。チューニング値を docker-compose.yml へ直書きし `.env` を秘密のみ化。エージェント並列向け再チューニング（`gpu_util` 0.92→0.70 / `max-model-len` 256K→128K / `max-num-seqs` 32→16 / `--scheduling-policy priority` / LiteLLM に interactive・worker ルート追加）。 |
