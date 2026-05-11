# cocoro-llm-server — アーキテクチャ

> 設計詳細・決定理由のドキュメント。READMEより踏み込んだ内容を扱います。

---

## 1. システム全体図

```
[OpenCode / Cursor / OpenHands]      [Claude Code]
              │                              │
              ▼ :4000/v1 (OpenAI互換)        ▼ :4001 (Anthropic互換)
        ┌──────────────┐              ┌─────────────────────┐
        │   LiteLLM    │◀─────────────│  anthropic-proxy    │
        │    :4000     │              │  Anthropic ↔ OpenAI │
        │              │              │  双方向変換         │
        │ smart-coder  │              └─────────────────────┘
        │ qwen3-coder  │
        │ claude-sonnet│
        └──────┬───────┘
               │
       ┌───────┴────────┐
       ▼                ▼
  :8000 (内部)      Anthropic API
  vLLM Primary     (fallbackのみ)
  Qwen3-Coder-Next-FP8
```

**3つのコンテナ構成（docker-compose）**:
1. `vllm-primary` — 推論エンジン本体
2. `litellm` — OpenAI互換ゲートウェイ + ルーティング + フォールバック
3. `anthropic-proxy` — Claude Code 用に Anthropic API を OpenAI API に変換

---

## 2. ハードウェア前提

| 項目 | 値 |
|---|---|
| GPU | NVIDIA RTX PRO 6000 Blackwell Workstation Edition |
| GPU VRAM | 94.96 GiB (97,887 MiB) |
| GPU Driver | 595.58.03 |
| CUDA | 12.8（Blackwell sm_120 必須） |
| CPU | Intel i9 285K |
| RAM | 256 GB DDR5 |
| SSD | 4 TB NVMe（モデルウェイト格納） |
| OS | Debian 13 Trixie |

---

## 3. モデル — Qwen3-Coder-Next-FP8

### 採用理由

| 要件 | 評価 | 詳細 |
|---|---|---|
| コーディング特化 | ✅ | Coder専用アーキテクチャ |
| VRAM効率 | ✅ | FP8量子化で ~70 GiB |
| コンテキスト長 | ✅ | 256K tokens |
| ツールコール対応 | ✅ | `qwen3_coder` parser |
| OpenAI互換 | ✅ | vLLM の OpenAI互換APIで提供 |

### VRAM 配分

```
GPU VRAM: 94.96 GiB
├── Qwen3-Coder-Next-FP8 ウェイト : ~70 GiB  (FP8)
├── KV キャッシュ (fp8)            : ~17 GiB  (gpu_util=0.92)
└── CUDA オーバーヘッド            : ~8 GiB
```

設定変更時は `.env` の `PRIMARY_GPU_UTIL` で調整可能（デフォルト `0.92`）。

---

## 4. LiteLLM ルーティング設計

### 3つのルート

```
smart-coder（推奨デフォルト）
  ├─ Primary  : qwen3-coder (vLLM ローカル)
  └─ Fallback : claude-sonnet (Anthropic API)
  → コスト最小・信頼性最大

qwen3-coder（ローカル直結）
  └─ vLLM :8000 直接
  → レイテンシ最小、プライバシー重視

claude-sonnet（クラウド直結）
  └─ Anthropic API 直接
  → vLLM が不安定時・難タスク用
```

設定ファイル: [`litellm/config.yaml`](../litellm/config.yaml)

---

## 5. ポート設計

| ポート | サービス | 公開範囲 | 用途 |
|---|---|---|---|
| `:8000` | vLLM | サーバーローカルのみ | デバッグ用（外部公開しない） |
| `:4000` | LiteLLM | LAN / Tailscale | OpenAI互換クライアント全般 |
| `:4001` | anthropic-proxy | LAN / Tailscale | Claude Code 専用 |

---

## 6. 重要な設定フラグ（変更禁止）

### `--tool-call-parser qwen3_coder`

OpenCode / Claude Code はファイル操作・コマンド実行を「ツールコール」として LLM に指示します。Qwen3-Coder は独自フォーマットで出力するため、このパーサーがないとツール機能が完全に壊れます。

### `--enable-prefix-caching`

各クライアントは同一のシステムプロンプトを毎回送信します。Prefix Caching があれば再計算をスキップできるため、レイテンシが3〜5倍違います。256K コンテキストでは特に致命的。

### `--kv-cache-dtype fp8`

FP8 KV キャッシュにより、同じ VRAM で約 2 倍のバッチサイズが確保できます。Blackwell SM120 は FP8 演算をネイティブサポートするため精度劣化も最小限。

---

## 7. ネットワーク

サーバーへの接続経路は2通り。詳細は [README の「ネットワーク前提」](../README.md#ネットワーク前提) 参照。

| 方法 | 範囲 | 推奨度 |
|---|---|---|
| **Tailscale 経由** | 場所を問わず使える（外出先・別WiFi含む） | ★★★（推奨） |
| 同じ LAN | 同じルーター下のクライアントのみ | ★★ |

> ⚠️ **インターネットへの直接公開は禁止**。APIキー漏洩・攻撃のリスクがあるため、リモート利用は必ず Tailscale など VPN 経由にしてください。

---

## 8. 変更履歴 (ADR — Architecture Decision Records)

| 日付 | 決定 | 理由 |
|---|---|---|
| 2026-04-05 | vLLM + LiteLLM 構成採用 | OpenAI 互換、既存ツール親和性 |
| 2026-04-14 | Qwen2.5-72B-AWQ 暫定運用 | 当初の Llama 4 Scout が VRAM 超過 |
| 2026-05-05 | **Qwen3-Coder-Next-FP8 に移行** | コーディング特化・256K・ツールコール対応 |
| 2026-05-05 | smart-coder ルート追加 | 自動フォールバックで可用性向上 |
| 2026-05-08 | **anthropic-proxy 追加** | Claude Code 対応（Anthropic↔OpenAI 変換） |
| 2026-05-11 | Tailscale をネットワーク前提に追加 | リモート利用・サブネット間接続対応 |
