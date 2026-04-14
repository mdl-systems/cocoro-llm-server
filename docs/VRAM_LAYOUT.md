# VRAM_LAYOUT.md — cocoro-llm-server VRAM 設計書

最終更新: 2026-04-14 (FP8スカウト実測値反映・Qwen優先構成へ移行)

---

## ハードウェア構成

| 項目 | 値 |
|---|---|
| GPU | NVIDIA RTX PRO 6000 Blackwell Workstation Edition |
| GPU VRAM | 94.96 GiB (97,887 MiB) |
| GPU Driver | 595.58.03 |
| CUDA | 12.8 (Runtime 13.2) |
| CPU | Intel i9 285K |
| RAM | 256 GB DDR5 (249 GB 認識) |
| SSD | 4 TB NVMe |

---

## ⚠️ FP8 Llama 4 Scout の実態（重要）

`nvidia/Llama-4-Scout-17B-16E-Instruct-FP8` の実際のウェイトサイズ:

| 項目 | 値 |
|---|---|
| safetensors 合計（実測） | **103.9 GB** (26シャード × ~4.2 GB) |
| GPU VRAM 総量 | 94.96 GiB |
| **差分** | **▲ 9 GB 超過** |

**Llama 4 Scout は 17B "active" パラメータだが、全 MoE エキスパートを含む合計パラメータは ~110B。**  
FP8（1 byte/param）でも 103.9 GB となり、94.96 GiB の GPU には単独では収まらない。

### CPU オフロード設計（将来対応）

256 GB RAM を活用して `--cpu-offload-gb` で部分的に CPU に退避が可能だが、制約がある:

| オフロード量 | GPU上ウェイト | KV cache予算 | 同時起動 Secondary |
|---|---|---|---|
| 50 GB | 53.9 GB | ~0.2 GB ← KVが壊滅 | ✅ 可能 |
| 15 GB | 88.9 GB | KV確保困難 | ❌ 不可（VRAMなし）|

**結論**: CPU オフロードは KV キャッシュがほぼゼロになるか、Secondary が起動できないトレードオフがある。**現時点では Qwen 2.5 32B AWQ を優先する。**

---

## 現在の運用構成（2026-04-14 時点）

### Primary: Qwen 2.5 32B AWQ（`gpt-4o` エイリアス）

| 項目 | 値 |
|---|---|
| モデル | `Qwen/Qwen2.5-32B-Instruct-AWQ` |
| ウェイトサイズ（実測） | 18.14 GiB |
| パス | `/models/qwen35-32b/` |
| ポート | :8081 |
| served-model-name | `qwen-32b` |
| GPU 使用量 | 18.14 GiB + KV cache |
| gpu-memory-utilization | 0.23 |

### Llama 4 Scout FP8（一時休止）

| 項目 | 値 |
|---|---|
| モデル | `nvidia/Llama-4-Scout-17B-16E-Instruct-FP8` |
| ウェイトサイズ（実測） | 103.9 GB（26シャード）|
| パス | `/models/llama4-scout/` |
| 状態 | **GPU VRAM 超過のため停止中** |
| 将来対応 | CPU オフロードまたは追加 GPU |

---

## VRAM バジェット（現在・Qwen 単独）

```
GPU VRAM: 94.96 GiB
├── Qwen 2.5 32B AWQ ウェイト:  18.14 GiB
├── KV キャッシュ (fp8):         ~3.8 GiB (≈ 0.23 × 94.96 - 18.14)
└── 予備・CUDA オーバーヘッド:  残余
```

---

## LiteLLM エイリアスマッピング（現在）

| エイリアス | バックエンド | ポート | 注記 |
|---|---|---|---|
| `gpt-4o` | qwen-32b | :8081 | Llama 4 Scout 代替（一時措置） |
| `gpt-4o-mini` | qwen-32b | :8081 | 通常通り |
| `claude-sonnet` | Anthropic API | — | フォールバック |
| `llama4-scout` | llama4-scout | :8080 | Primary 復旧後に有効化 |

---

## 将来ロードマップ

### Option A: Llama 4 Scout をより強い量子化で再取得

- `unsloth/Llama-4-Scout-17B-16E-Instruct-GGUF` の Q4_K_XL (~60GB), Q2_K_XL (~40GB) を検討
- vLLM の GGUF 対応（`--load-format gguf`）で直接ロード
- 注意: 分割 GGUF（-of-00002 形式）はvLLM 0.19.0 でサポート要確認

### Option B: GPU 追加

- 2枚目の RTX PRO 6000 Blackwell（+96 GiB）で `--tensor-parallel-size 2` を使用
- 両モデルを同時運用可能

### Option C: CPU オフロード（性能を妥協して使う場合）

```bash
# start_primary.sh への追加フラグ（検証済みではない）
--dtype auto            # FP8ウェイトをFP8のまま保持（bfloat16ではなく）
--cpu-offload-gb 50     # 50GB をCPU RAMにオフロード（モデル: ~54GB on GPU）
--gpu-memory-utilization 0.62  # KV cache 確保
--max-model-len 8192    # KV cache圧力を下げる
```

期待スループット: ~10-30 tok/s（PCIe CPU↔GPU 転送ボトルネック）

---

## 変更履歴

| 日付 | 変更内容 |
|---|---|
| 2026-04-05 | 初版作成 (GGUF 想定) |
| 2026-04-06 | RAM 256GB増設後の CPU KV オフロード設計追加 |
| 2026-04-12 | FP8モデル切替。GPU_UTIL=0.57 設定 |
| 2026-04-14 | **FP8 実測 103.9GB 判明。Qwen 優先構成に移行。ルートマップ追記。** |
