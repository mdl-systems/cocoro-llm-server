# VRAM割当詳細 — cocoro-llm-server

> **変更前にこのファイルを必ず更新すること**（CLAUDE.md 絶対ルール）

## 現在の配分（RTX PRO 6000 Blackwell 96GB）

| 用途 | GB | 使用率 | 変更日 |
|---|---|---|---|
| Llama 4 Scout 109B Q4_K_M | 69.1 | 0.72 | 2026-04-06 |
| Qwen 2.5 32B AWQ | 22.1 | 0.23 | 2026-04-06 |
| システム予備 | 4.8 | 0.05 | 2026-04-06 |
| **合計** | **96** | **1.00** | — |

## 設定ファイルとの対応

```bash
# .env
PRIMARY_GPU_UTIL=0.72    # 69.1GB / 96GB → Q4_K_M (65.4GB) + KV 3.7GB
SECONDARY_GPU_UTIL=0.23  # 22.1GB / 96GB → Qwen AWQ (~18GB) + KV 4.1GB
```

vLLMの `--gpu-memory-utilization` はモデルロード分 + KVキャッシュを含んだ割合。
両モデルを同一GPU上で動かすため、合計が 1.0 を超えてはならない。

## KVキャッシュの計算

```
KVキャッシュ = VRAM総量 × GPU_UTIL - モデルウェイトサイズ

Primary (Llama 4 Scout Q3_K_M):
  96,000MB × 0.58 = 55,680MB（vLLM管理域）
  モデルウェイト: 約51,800MB（Q3_K_M GGUFファイルサイズ）
  → KVキャッシュ: 約3,880MB（fp8 KVキャッシュで約12K〜32Kトークン分）

Secondary (Qwen 2.5 32B AWQ):
  96,000MB × 0.23 = 22,080MB（vLLM管理域）
  モデルウェイト: 約18,000〜19,000MB（AWQ safetensors）
  → KVキャッシュ: 約3,000〜4,000MB
```

両モデル同時使用時の合計: 55,680 + 22,080 = **77,760MB（96GB以内 ✅）**

## Q4_K_M を採用しない理由

| 量子化 | ファイルサイズ | 55GB予算 | 判定 |
|---|---|---|---|
| Q4_K_M (Unsloth) | 65.4GB | ❌ オーバー | **採用不可** |
| Q3_K_M (Unsloth) | 51.8GB | ✅ 余裕3.9GB | **採用** |

Llama 4 Scout は MoE アーキテクチャのため、Q3_K_M でも品質劣化は軽微。
ソース: `unsloth/Llama-4-Scout-17B-16E-Instruct-GGUF`（月間 46,000+ DL）

## Qwen を Q5_K_M から AWQ に変更した理由

`Qwen/Qwen3.5-32B-Instruct` は HuggingFace 上に存在しない（未リリース）。
`Qwen/Qwen2.5-32B-Instruct-AWQ` を使用（22GB VRAM 予算内 ✅）。
vLLM が AWQ を自動検出するため `--quantization` フラグ不要。

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
3. `vllm/start_*.sh` の `--model` パスを変更
4. `litellm/config.yaml` のエイリアスを確認

## 変更履歴

| 日付 | 変更内容 | 担当 |
|---|---|---|
| 2026-04-05 | 初版: Scout 55GB + Qwen 22GB | matsuokan |
| 2026-04-06 | Primary: Q4_K_M→Q3_K_M（65.4GB超過のため）| matsuokan |
| 2026-04-06 | Secondary: Qwen3.5→Qwen2.5 AWQ（Qwen3.5未リリース）| matsuokan |
