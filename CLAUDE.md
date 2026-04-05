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

- クイックフィックス禁止 — 根本原因を特定してから修正する
- モデルウェイトをgitにコミットしない — .gitignore で除外済み
- APIキーを平文でコードに書かない — 必ず .env 経由
- VRAM配分を変える場合は docs/VRAM_LAYOUT.md を先に更新
- cocoro-core の .env 変更は docs/COCORO_INTEGRATION.md に記録

---

## テックスタック

| Component | Technology | Port |
|---|---|---|
| 推論エンジン | vLLM | :8080（Scout）/ :8081（Qwen） |
| APIゲートウェイ | LiteLLM Proxy | :8000（OpenAI互換） |
| リバースプロキシ | Nginx | :80 |
| モニタリング | Prometheus + Grafana | :9090 / :3000 |
| コンテナ管理 | Docker Compose | — |
| OS | Debian 13 | — |

---

## 環境変数（.env）

.env.example を参照してコピーして使う。
設定ファイル: ~/cocoro-llm-server/.env

---

## よく使うコマンド

```bash
# 全サービス起動
docker compose -f docker/docker-compose.yml up -d

# vLLM Primary起動
bash vllm/start_primary.sh

# vLLM Secondary起動
bash vllm/start_secondary.sh

# ヘルスチェック
bash scripts/health_check.sh

# 推論テスト
curl http://192.168.50.112:8000/v1/chat/completions \
  -H "Authorization: Bearer mdl-llm-2026" \
  -H "Content-Type: application/json" \
  -d '{"model":"gpt-4o","messages":[{"role":"user","content":"こんにちは"}]}'

# VRAM確認
nvidia-smi --query-gpu=memory.used,memory.free,memory.total --format=csv

# ログ確認
docker logs litellm -f
journalctl -u vllm-primary -f
```
