# cocoro-llm-server

> ローカル GPU サーバーで LLM を動かし、OpenAI 互換 / Anthropic 互換 API として提供するためのリポジトリ。

---

## このリポジトリの正体

このリポジトリは **「設定ファイル + セットアップ自動化スクリプト + 小さな自作プロキシ」のセット**です。
推論エンジン本体（vLLM）やゲートウェイ（LiteLLM）は Docker Hub にある**既製品**を呼び出してるだけで、
このリポジトリにはそれらを「**どう組み立てて動かすか**」の指示書しか入っていません。

サーバーへの「デプロイ」は `git pull && docker compose up -d` だけ。
バイナリを送り込んだりビルドしたりする工程はありません（自作プロキシのみコンテナビルドが走りますが自動）。

---

## ファイル構成の地図

```
cocoro-llm-server/
├── docker-compose.yml      ★ サーバー起動の指示書（本体）
├── .env.example            ← .env のひな型（秘密の値だけ入れる）
│
├── gateway/                ← 唯一の自作コード
│   ├── Dockerfile          　 anthropic-proxy コンテナのレシピ
│   └── anthropic_proxy.py  　 Anthropic ⇔ OpenAI 形式の変換
│
├── litellm/                ← LiteLLM の設定
│   ├── config.yaml.tmpl    　 ルーティング定義（テンプレ）
│   └── entrypoint.sh       　 起動時にテンプレを実値で展開
│
├── scripts/                ← セットアップ自動化
│   ├── setup_nvidia.sh     　 GPU ドライバ + CUDA インストール
│   ├── setup_docker.sh     　 Docker + NVIDIA Container Toolkit
│   ├── first_setup.sh      　 .env 生成 + 全サービス起動（初回用）
│   ├── show_connection_info.sh  接続情報を画面表示
│   └── health_check.sh     　 全サービスの死活確認
│
├── docs/
│   ├── SERVER.md           ← このサーバーのスペック・固有事情
│   └── OPERATIONS.md       ← 変更時の手順・絶対ルール・コマンド集
│
├── README.md               ← このファイル
└── CLAUDE.md               ← AI エージェント向けの作業ルール
```

---

## アーキテクチャ

```
[OpenCode / Cursor 等]         [Claude Code]
        │ :4000/v1                  │ :4001
        ▼ (OpenAI互換)              ▼ (Anthropic互換)
   ┌──────────┐              ┌──────────────────┐
   │ LiteLLM  │◀─────────────│ anthropic-proxy  │
   │  :4000   │              │ Anthropic→OpenAI │
   └────┬─────┘              └──────────────────┘
        │ ┌──────────────┐
        ├▶│ vLLM (:8000) │ ローカル LLM（既製品）
        └▶│ Anthropic API│ クラウド（フォールバック用）
          └──────────────┘
```

3 つのコンテナで構成: `vllm-primary` / `litellm` / `anthropic-proxy`。

---

## ネットワーク前提

クライアント PC がこのサーバーに到達できる必要があります。次のどちらかで接続環境を用意してください。

### 推奨: Tailscale 経由（場所を問わず使える）

サーバーとクライアントを同じ [Tailscale](https://tailscale.com/) アカウントでログインさせれば、物理ネットワークが違っても接続できます（外出先・別 WiFi・サブネット間も OK）。クイックスタートの Step 3 でインストールします。

サブネット越しに LAN 資源も共有したい場合は `sudo tailscale up --advertise-routes=192.168.x.0/24` でサブネットルーティングを有効化できます。

### 代替: 同じ LAN

サーバーとクライアントが同じルーター下にあれば追加設定なしで接続できます。Tailscale 不要、LAN IP（`192.168.x.x`）を使用。

> ⚠️ **インターネットへの直接公開は禁止**。API キー漏洩・攻撃のリスクがあります。リモート利用は必ず Tailscale 等の VPN 経由で。

---

## クイックスタート

新しい Linux サーバー（GPU 付き）で初めて立ち上げる手順:

```bash
# 1) GPU ドライバ + CUDA（未インストールの場合のみ）
sudo bash scripts/setup_nvidia.sh
sudo reboot

# 2) Docker + NVIDIA Container Toolkit（未インストールの場合のみ）
sudo bash scripts/setup_docker.sh

# 3) （リモートからも使いたい場合）Tailscale
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up

# 4) リポジトリをクローン
git clone https://github.com/mdl-systems/cocoro-llm-server.git
cd cocoro-llm-server

# 5) 対話式セットアップ（.env 自動生成 + docker compose up -d）
bash scripts/first_setup.sh

# 6) 起動を待つ（モデル DL で初回 5〜15 分）
docker compose logs -f vllm-primary
# "Application startup complete." が出たら準備完了
```

完了後、画面に表示される **Server IP** と **API Key** をクライアント PC に伝えれば接続できます。
（後から `bash scripts/show_connection_info.sh` でも再表示可能）

---

## クライアント側の接続設定

詳細は別リポジトリ [cocoro-llm-client](https://github.com/mdl-systems/cocoro-llm-client) を参照。
最低限の設定値だけ:

| クライアント | 設定項目 | 値 |
|---|---|---|
| OpenCode / Cursor / OpenHands | API Base URL | `http://<SERVER_IP>:4000/v1` |
| 〃 | API Key | `.env` の `LITELLM_MASTER_KEY` |
| 〃 | Model | `smart-coder` |
| Claude Code | `ANTHROPIC_BASE_URL` | `http://<SERVER_IP>:4001` |
| 〃 | `ANTHROPIC_API_KEY` | `.env` の `LITELLM_MASTER_KEY` |

`<SERVER_IP>` は Tailscale IP（推奨）か LAN IP。`show_connection_info.sh` で両方表示されます。

---

## こんなときどこを見る

| やりたいこと | 参照先 |
|---|---|
| サーバーのスペック・GPU 情報を確認したい | [docs/SERVER.md](docs/SERVER.md) |
| モデルを切り替えたい / 設定を変えたい | [docs/OPERATIONS.md](docs/OPERATIONS.md) |
| よく使うコマンドを調べたい | [docs/OPERATIONS.md](docs/OPERATIONS.md) |
| エージェント（Claude Code 等）に作業させたい | [CLAUDE.md](CLAUDE.md) |
| トラブルシュート | [docs/OPERATIONS.md](docs/OPERATIONS.md#トラブルシュート) |

---

## ハードウェア要件

| 項目 | 要件 |
|---|---|
| GPU | NVIDIA GPU（VRAM は使うモデルによる。詳細は [docs/SERVER.md](docs/SERVER.md)）|
| OS | Linux（Debian 12+ / Ubuntu 22.04+）|
| その他 | Docker Engine + NVIDIA Container Toolkit |

> ⚠️ **インターネットへの直接公開は禁止**。リモート利用は必ず Tailscale 等の VPN 経由で。
