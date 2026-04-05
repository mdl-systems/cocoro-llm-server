# VRAM割当詳細 — cocoro-llm-server

> **変更前にこのファイルを必ず更新すること**（CLAUDE.md 絶対ルール）

## 現在の配分（RTX PRO 6000 Blackwell 96GB）

| 用途 | GB | 使用率 | 変更日 |
|---|---|---|---|
| Llama 4 Scout 109B Q4_K_M | 55 | 0.58 | 2026-04-05 |
| Qwen 3.5 32B Q5_K_M | 22 | 0.23 | 2026-04-05 |
| KVキャッシュ（共用） | 10 | 0.10 | 2026-04-05 |
| 予備（LoRA実験等） | 9 | 0.09 | 2026-04-05 |
| **合計** | **96** | **1.00** | — |

## 設定ファイルとの対応

```bash
# .env
PRIMARY_GPU_UTIL=0.58    # 55GB / 96GB
SECONDARY_GPU_UTIL=0.23  # 22GB / 96GB
```

vLLMの `--gpu-memory-utilization` はモデルロード分 + KVキャッシュを含んだ割合。
両モデルを同一GPU上で動かすため、合計が 1.0 を超えてはならない。

## KVキャッシュの計算

```
KVキャッシュ = VRAM総量 × GPU_UTIL - モデルウェイトサイズ

Primary:
  55000MB × 0.58 ≒ 31900MB（vLLM管理域）
  モデルウェイト: 約27000MB（109B × Q4_K_M）
  → KVキャッシュ: 約4900MB

Secondary:
  96000MB × 0.23 ≒ 22080MB（vLLM管理域）
  モデルウェイト: 約19000MB（32B × Q5_K_M）
  → KVキャッシュ: 約3080MB
```

両モデル合計 KVキャッシュ: 約8GB（5〜10同時セッションに対応）

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
