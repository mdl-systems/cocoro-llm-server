# VRAM割当詳細 — cocoro-llm-server

> **変更前にこのファイルを必ず更新すること**（CLAUDE.md 絶対ルール）

## ハードウェア構成

| 項目 | 仕様 |
|---|---|
| GPU | NVIDIA RTX PRO 6000 Blackwell (SM_120) |
| VRAM | 96GB GDDR7 |
| RAM | 256GB DDR5（2026-04-11 増設完了） |
| Swap | 127GB |
| Driver | 595.58.03 |
| CUDA | 12.8 |

## 現在のVRAM配分（RTX PRO 6000 Blackwell 96GB）

| 用途 | モデル | VRAM | GPU_UTIL | 変更日 |
|---|---|---|---|---|
| Primary (port 8080) | Llama 4 Scout 17B-16E FP8 | ~55GB | 0.57 | 2026-04-12 |
| Secondary (port 8081) | Qwen 2.5 32B AWQ | ~22GB | 0.23 | 2026-04-06 |
| KVキャッシュ + 予備 | — | ~19GB | 0.20 | — |
| **合計** | — | **96GB** | **1.00** | — |

## 設定ファイルとの対応

```bash
# .env
PRIMARY_GPU_UTIL=0.57    # ~54.7GB / 96GB → FP8ウェイト(~47GB) + KV ~7.7GB
SECONDARY_GPU_UTIL=0.23  # ~22.1GB / 96GB → Qwen AWQ(~18GB) + KV ~4GB

# モデルパス
PRIMARY_MODEL_PATH=/models/llama4-scout       # FP8 safetensors ディレクトリ
SECONDARY_MODEL_PATH=/models/qwen35-32b       # AWQ safetensors ディレクトリ
```

vLLMの `--gpu-memory-utilization` はモデルウェイト + KVキャッシュを含んだ割合。
両モデルを同一GPU上で動かすため、合計が **1.0 を超えてはならない**。

## KVキャッシュの計算

```
VRAM KVキャッシュ = VRAM総量 × GPU_UTIL - モデルウェイトサイズ

Primary (Llama 4 Scout FP8):
  96,000MB × 0.57 = 54,720MB（vLLM管理域）
  モデルウェイト: ~47,000MB（FP8 safetensors 推定）
  → GPU KVキャッシュ: ~7,720MB（fp8 KVキャッシュで ~50K〜128Kトークン分）

Secondary (Qwen 2.5 32B AWQ, gpu_util=0.23):
  96,000MB × 0.23 = 22,080MB（vLLM管理域）
  モデルウェイト: ~18,000MB（AWQ safetensors）
  → GPU KVキャッシュ: ~4,000MB
```

両モデル同時使用時の合計: 54,720 + 22,080 = **76,800MB（96GB以内 ✅）**

## RAM 256GB 増設によるCPUオフロード設計

RAM 256GB（2026-04-11 増設済み）により、以下が有効化可能：

| 項目 | 内容 |
|---|---|
| GPU KVキャッシュ | ~11.7GB（Primary + Secondary 合計） |
| CPU KVキャッシュオフロード上限 | ~200GB（OS・その他用途に56GB残留） |
| 理論上の KVキャッシュ最大 | GPU 11.7GB + CPU 200GB = **~211.7GB** |
| Swap（補助） | 127GB |

### CPUオフロードの有効化方法

```bash
# .env に追記（必要に応じて）
PRIMARY_CPU_OFFLOAD_GB=40     # 40GB をCPU KVキャッシュとして確保
SECONDARY_CPU_OFFLOAD_GB=20   # 20GB をCPU KVキャッシュとして確保
```

```bash
# start_primary.sh の exec 引数に追加
--cpu-offload-gb "${CPU_OFFLOAD_GB:-0}" \
```

> ⚠️ CPUオフロードは GPU↔CPU 転送レイテンシが発生するため、
> 高スループット（バッチ処理）よりも**大量並列セッション対応**に適している。
> 現時点では無効（デフォルト 0）。必要に応じて有効化すること。

## モデル採用理由

### Primary: nvidia/Llama-4-Scout-17B-16E-Instruct-FP8

| 量子化 | VRAM | 速度目安 | 判定 |
|---|---|---|---|
| GGUF Q3_K_M | ~51.8GB | ~93 tok/s | ❌ 低速・分割非対応 |
| GGUF Q4_K_M | ~65.4GB | ~93 tok/s | ❌ VRAM超過 |
| **FP8 (HF)** | **~47GB** | **~300+ tok/s** | **✅ 採用** |

- Blackwell SM_120 は FP8をハードウェアネイティブサポート
- vLLM は分割GGUF非対応（シングルファイルのみ）
- FP8はGGUFと比べ 3〜5倍 のスループット向上

### Secondary: Qwen/Qwen2.5-32B-Instruct-AWQ

- `Qwen/Qwen3.5-32B-Instruct` は HuggingFace 上に存在しない（未リリース）
- `Qwen/Qwen2.5-32B-Instruct-AWQ` を採用（22GB VRAM予算内 ✅）
- vLLM が AWQ を自動検出するため `--quantization` フラグ不要

## 変更手順

### VRAMを増やす場合

1. `docs/VRAM_LAYOUT.md`（このファイル）の表を更新
2. `.env` の `PRIMARY_GPU_UTIL` または `SECONDARY_GPU_UTIL` を変更
3. 変更した値の合計が **1.0 を下回ること**を確認
4. vLLMを再起動: `bash vllm/start_primary.sh`
5. `nvidia-smi` でVRAM使用量を確認

### モデルを変更する場合

1. このファイルを更新
2. `vllm/modelfile/` の該当yamlを更新
3. `vllm/start_*.sh` の `MODEL_PATH` デフォルト値を変更
4. `litellm/config.yaml` のエイリアスを確認

## 変更履歴

| 日付 | 変更内容 | 担当 |
|---|---|---|
| 2026-04-05 | 初版: Scout 55GB + Qwen 22GB | matsuokan |
| 2026-04-06 | Primary: Q4_K_M→Q3_K_M（65.4GB超過のため）| matsuokan |
| 2026-04-06 | Secondary: Qwen3.5→Qwen2.5 AWQ（Qwen3.5未リリース）| matsuokan |
| 2026-04-12 | Primary: GGUF Q3_K_M → FP8（速度3〜5倍・Blackwell最適化）| matsuokan |
| 2026-04-12 | GPU_UTIL: 0.58 → 0.57（FP8ウェイト実測に合わせ調整）| matsuokan |
| 2026-04-11 | RAM: 64GB → 256GB DDR5増設 / CPUオフロード設計追記 | matsuokan |
