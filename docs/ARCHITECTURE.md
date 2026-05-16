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
  Qwen3.6-35B-A3B-FP8 (マルチモーダル)
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

## 3. モデル — Qwen3.6-35B-A3B-FP8（マルチモーダル）

### 採用理由

| 要件 | 評価 | 詳細 |
|---|---|---|
| コーディング/ツール対応 | ✅ | `qwen3_coder` parser そのまま使える |
| 画像・動画入力 | ✅ | マルチモーダル（Vision Encoder 内蔵）。1モデルでテキスト+画像+動画 |
| VRAM効率 | ✅ | FP8量子化で ~35 GiB（旧 70GiB から半減）|
| コンテキスト長 | ✅ | 256K tokens（YaRN で最大 ~1M） |
| OpenAI互換 | ✅ | vLLM の OpenAI互換APIで提供（image_url 入力対応） |

> 旧構成では「テキスト用 + 画像用」を2モデル併設する想定だったが、本モデルが
> マルチモーダルのため **1モデル・1コンテナで画像/動画も処理可能**。構成を据え置いたまま差し替えできる。

### VRAM 配分（エージェント並列ワークロード向け / 過剰設定を現実値に）

```
GPU VRAM: 94.96 GiB
├── Qwen3.6-35B-A3B-FP8 ウェイト  : ~35 GiB  (FP8, 35B total / 3B active MoE)
├── CUDA オーバーヘッド            : ~8 GiB
├── 空き                          : ~28 GiB  (実測後に判断・将来の選択肢の余地)
└── KV キャッシュ (fp8)            : ~24 GiB  (gpu_util=0.70)
```

> MoE は active が 3B でも **全 35B を VRAM 常駐**させる必要がある（どの expert を使うかは
> トークンごとに変わるため）。容量計算はあくまで total 35B 基準。

> ⚠️ KV のトークン単価は実装依存のため、上記 KV/空きの数値は**概算**。確定には起動後に
> `docker compose logs vllm-primary` の KV cache usage を実測し `docker-compose.yml` を再調整すること。

> この再チューニングの**目的はサブエージェント並列をローカル単一モデルで快適に回すこと**。
> 空き ~28GB は「過剰設定を現実値に戻した副産物」であり、画像生成や特化モデル等を
> 入れるのは**未確定の将来オプション**（実測してから判断、既定路線ではない）。

設定変更時は `docker-compose.yml` の `vllm-primary` コマンド内 `--gpu-memory-utilization`
（現在 `0.70`）を git 経由で変更（「開発フロー」参照）。値を上げると KV プールが増え
並列耐性が上がるが、その分 空きは減る。`.env` には置かない。

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

### `--reasoning-parser qwen3`

Qwen3.6 は思考モード（`<think>` タグ）を持つため、このパーサーがないと思考過程が
そのまま応答に混入し、ツールコール出力も乱れる。Qwen 公式が明示的に推奨。

### `--enable-prefix-caching`

各クライアントは同一のシステムプロンプトを毎回送信します。Prefix Caching があれば再計算をスキップできるため、レイテンシが3〜5倍違います。256K コンテキストでは特に致命的。

### `--kv-cache-dtype fp8`

FP8 KV キャッシュにより、同じ VRAM で約 2 倍のバッチサイズが確保できます。Blackwell SM120 は FP8 演算をネイティブサポートするため精度劣化も最小限。

### `--scheduling-policy priority`

サブエージェント戦略では、人間が直接対話するリクエストの裏で多数のサブエージェント
リクエストが並列に走る。優先度スケジューリングが無いと、人間の対話が裏のバッチ処理の
後ろに詰まり体感が劣化する。LiteLLM 側の `interactive` ルートに高優先度を付与し、
人間のターンを待たせない（"余裕を見て開発できる" 設計の核心）。

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
| 2026-05-16 | **Qwen3.6-35B-A3B-FP8 に移行** | マルチモーダル（画像/動画）対応・VRAM 70→35GB・構成据え置きで差し替え可 |
| 2026-05-16 | **エージェント並列ワークロード向けに再チューニング** | 目的はサブエージェント戦略（並列ファンアウト）を単一ローカルモデルで快適に成立させること。`GPU_UTIL` 0.92→0.70（過剰設定を現実値に。空く ~28GB は副産物で第2モデル追加は未確定）、`MAX_MODEL_LEN` 256K→128K、`MAX_NUM_SEQS` 32→16（実測前提）。`--scheduling-policy priority` で人間の対話を優先。LiteLLM に `interactive`/`worker` 論理2ルートを追加（将来モデルを足す場合の再設計回避の保険であって追加前提ではない）。オーバーエンジニアリング回避のため段階的アプローチ（まず単一モデル高並列→必要なら物理隔離） |
