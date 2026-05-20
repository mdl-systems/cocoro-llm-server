# CLAUDE.md — cocoro-llm-server
# AI エージェント（Claude Code / OpenCode / Antigravity 等）向け作業ルール

> このファイルは **このリポジトリを clone した人全員のエージェント向け**の汎用ルール。
> リポジトリのメンテナ固有の運用ルールは `CLAUDE.local.md` (gitignore 対象) を参照。

| 知りたいこと | 参照先 |
|---|---|
| このリポジトリの正体・全体像・地図 | [README.md](README.md) |
| サーバーのスペック・固有事情 | [docs/SERVER.md](docs/SERVER.md) |
| 変更手順・コマンド・トラブルシュート | [docs/OPERATIONS.md](docs/OPERATIONS.md) |

---

## エージェントが守るべきルール

### 値の置き場所（絶対）

- **チューニング値**（モデル名 / VRAM / 並列数 / フラグ等）→ `docker-compose.yml` 冒頭の `x-config:` ブロックに集約
- **秘密の値**（API キー / トークン）→ `.env`（git 管理外）
- **サーバー固有の情報**（GPU 型番・実測値）→ `docs/SERVER.md`（テンプレ）
- `.env` にチューニング値を入れない

### 変更時の判断

- 「クイックフィックス」で対処しない。根本原因を特定してから修正する
- 設定を変える前に [OPERATIONS.md の変更パターン別の編集箇所](docs/OPERATIONS.md#変更パターン別の編集箇所) で該当パターンを確認

### 触ってはいけないフラグ

`docker-compose.yml` の `vllm-primary` コマンドで、以下のフラグは外さない:

- `--tool-call-parser` — モデル固有のツールコール解釈。外すとファイル操作系が全部壊れる
- `--reasoning-parser` — 思考モード解釈。外すと応答に `<think>` が混入してツールコールも乱れる
- `--enable-prefix-caching` — KV キャッシュ効率の生命線

（モデル系統を Llama 等に変える場合は `parser` の**値を**変える。フラグごと**外す**のは NG）

### ポート

- OpenAI 互換クライアント → `:4000`
- Claude Code → `:4001`
- `:8000`（vLLM 直接）は**サーバー内部デバッグのみ**、クライアントから直接呼ばない

---

## このファイルの更新

ここには「リポジトリ全体共通のエージェントルール」だけを書く。
固有値（モデル名・parser 名・VRAM 値）は `docker-compose.yml` を単一情報源にする（変更時に乖離するため）。
メンテナの個人運用ルール（GitHub 経由フロー等）は `CLAUDE.local.md` (gitignore 対象) に書く。
