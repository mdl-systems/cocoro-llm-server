# cocoro-llm-server — 設計書 & アーキテクチャ決定ログ

> 最終更新: 2026-05-05

---

## 1. システム概要

```
[クライアント群]
  AntGravity / OpenHands / cocoro-core / チームメンバー
         │
         ▼ :4000 (OpenAI互換)
  ┌─────────────────┐
  │   LiteLLM Proxy  │  ← smart-coder / qwen3-coder / claude-sonnet
  └────────┬────────┘
           │                      ┌───────────────────────┐
           ├──── qwen3-coder ────▶│  vLLM :8000           │
           │                      │  Qwen3-Coder-Next-FP8  │
           │                      │  256K context          │
           └──── claude-sonnet ──▶│  Anthropic API         │
                (fallback)        └───────────────────────┘

  ┌─────────────────┐
  │  Open WebUI :3000│  ← LiteLLM経由（smart-coder default）
  └─────────────────┘

  ┌─────────────────┐
  │ Prometheus :9090 │
  │ Grafana    :3100 │
  └─────────────────┘
```

---

## 2. ハードウェア構成

| 項目 | 値 |
|---|---|
| GPU | NVIDIA RTX PRO 6000 Blackwell Workstation Edition |
| GPU VRAM | 94.96 GiB (97,887 MiB) |
| GPU Driver | 595.58.03 |
| CUDA | 12.8 (Runtime) |
| CPU | Intel i9 285K |
| RAM | 256 GB DDR5 |
| SSD | 4 TB NVMe |
| IP | 192.168.50.112 |

---

## 3. モデル選定 — Qwen3-Coder-Next-FP8

### なぜQwen3-Coder-Next-FP8か

| 要件 | Qwen3-Coder-Next-FP8 | 旧Qwen2.5-72B-AWQ |
|---|---|---|
| コーディング特化 | ✅ Coder専用アーキテクチャ | ❌ 汎用モデル |
| VRAM効率 | ✅ FP8 ~70GB | ✅ AWQ ~38GB |
| コンテキスト長 | ✅ 256K tokens | ❌ 32K tokens |
| ツールコールサポート | ✅ qwen3_coder parser | ❌ 未対応 |
| OpenHands互換性 | ✅ ネイティブ | ⚠️ 要設定 |

### VRAM配分

```
GPU VRAM: 94.96 GiB
├── Qwen3-Coder-Next-FP8 ウェイト: ~70 GiB (FP8)
├── KV キャッシュ (fp8):            ~17 GiB (gpu_util=0.92)
└── CUDA オーバーヘッド:             ~8 GiB
```

---

## 4. LiteLLMルーティング設計

### 3ルート構成の根拠

```
smart-coder（推奨デフォルト）
  └── Primary: qwen3-coder (vLLM local)
      Fallback: claude-sonnet (Anthropic API)
  → コスト最小・信頼性最大

qwen3-coder（ローカル直結）
  └── vLLM :8000 直接
  → レイテンシ最小、プライバシー重視タスク

claude-sonnet（クラウド直結）
  └── Anthropic API直接
  → vLLMが不安定な場合・品質最優先タスク
```

### ポート設計

| ポート | 役割 | 公開範囲 |
|---|---|---|
| :8000 | vLLM生エンドポイント | LAN内デバッグのみ |
| :4000 | LiteLLM（本番用） | チーム全員 |
| :3000 | Open WebUI | チーム全員 |
| :9090 | Prometheus | 管理者のみ |
| :3100 | Grafana | 管理者のみ |

---

## 5. 重要な設定フラグと理由

### `--tool-call-parser qwen3_coder`（外してはいけない）

OpenHandsはLLMにツールコール（ファイル操作・コード実行）を指示するために
OpenAI互換のfunction callingを使用する。Qwen3-Coderは独自フォーマットで
ツールコールを出力するため、このパーサーなしではOpenHandsが機能しない。

### `--enable-prefix-caching`（外してはいけない）

Open WebUIは各リクエストに同一のシステムプロンプトを付加する。
Prefix Cachingなしでは毎回フルプリフィルが走り、レイテンシが3〜5倍になる。
256Kコンテキストでは特に致命的。

### `--kv-cache-dtype fp8`

FP8 KVキャッシュにより、同じVRAMで約2倍のバッチサイズを確保できる。
Blackwell SM120はFP8演算をネイティブサポートするため、精度劣化も最小限。

---

## 6. 変更履歴 (ADR — Architecture Decision Records)

| 日付 | 決定 | 理由 |
|---|---|---|
| 2026-04-05 | vLLM + LiteLLM構成採用 | OpenAI互換API、既存ツールとの親和性 |
| 2026-04-12 | Llama4-Scout-FP8を採用 | 当初計画 |
| 2026-04-14 | Llama4-Scout-FP8を一時停止 | VRAM超過（103.9GB > 94.96GB） |
| 2026-04-14 | Qwen2.5-72B-AWQ暫定運用 | VRAM内（38GB）、即時使用可能 |
| 2026-05-05 | **Qwen3-Coder-Next-FP8に移行** | コーディング特化・256K・OpenHands対応 |
| 2026-05-05 | **Open WebUI追加** | チーム向けUIとして採用 |
| 2026-05-05 | **LiteLLMを:8000→:4000に変更** | vLLMの8000と衝突回避 |
| 2026-05-05 | **smart-coderルート追加** | 自動フォールバックによる可用性向上 |

---

## 7. 社内ネットワーク構成

| ホスト | IP | 役割 |
|---|---|---|
| cocoro-llm-server | 192.168.50.112 | LLM推論（本repo） |
| miniPC A | 192.168.50.92 | cocoro-core / cocoro-console |
| miniPC B | 192.168.50.86 | cocoro-agent |
