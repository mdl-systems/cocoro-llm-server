#!/usr/bin/env bash
# =============================================================================
# vllm/start_secondary.sh
# Qwen 3.5 32B Q5_K_M — 起動スクリプト
#
# ポート  : 8081
# VRAM    : ~22GB (gpu-memory-utilization 0.23)
# モデル  : Qwen/Qwen3.5-32B-Instruct
# エイリアス: gpt-4o-mini (LiteLLM経由)
#
# 実行方法:
#   source /usr/local/bin/vllm-activate
#   bash vllm/start_secondary.sh
#
# 注意: Primary (start_primary.sh) を先に起動してから実行する
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

# .env 読み込み
if [[ -f "${REPO_DIR}/.env" ]]; then
    set -a
    # shellcheck disable=SC1091
    source "${REPO_DIR}/.env"
    set +a
else
    echo "[ERROR] .env が見つかりません: ${REPO_DIR}/.env"
    exit 1
fi

# ── 設定値 ────────────────────────────────────────────────────────────────────
MODEL_PATH="${SECONDARY_MODEL_PATH:-/models/qwen35-32b}"
PORT="${SECONDARY_PORT:-8081}"
GPU_UTIL="${SECONDARY_GPU_UTIL:-0.23}"
MAX_MODEL_LEN="${SECONDARY_MAX_MODEL_LEN:-16384}"
MAX_NUM_SEQS="${MAX_NUM_SEQS:-16}"
LOG_DIR="/var/log/cocoro-llm"
LOG_FILE="${LOG_DIR}/vllm-secondary.log"

# ── Blackwell 環境変数 ─────────────────────────────────────────────────────────
export CUDA_HOME="/usr/local/cuda"
export PATH="${CUDA_HOME}/bin:${PATH}"
export LD_LIBRARY_PATH="${CUDA_HOME}/lib64:${LD_LIBRARY_PATH:-}"
export TORCH_CUDA_ARCH_LIST="12.0"
export FLASHINFER_CUDA_ARCH_LIST="12.0f"
export VLLM_WORKER_MULTIPROC_METHOD="spawn"

VENV_DIR="/opt/vllm-env"
if [[ ! -f "${VENV_DIR}/bin/python" ]]; then
    echo "[ERROR] vLLM仮想環境が見つかりません: ${VENV_DIR}"
    echo "  sudo bash scripts/setup_vllm.sh を先に実行してください"
    exit 1
fi

PYTHON="${VENV_DIR}/bin/python"
mkdir -p "$LOG_DIR"

# ── 起動前チェック ─────────────────────────────────────────────────────────────
echo "[INFO] vLLM Secondary (Qwen 3.5 32B) 起動チェック..."

if [[ ! -d "$MODEL_PATH" ]]; then
    echo "[ERROR] モデルが見つかりません: ${MODEL_PATH}"
    echo "  bash scripts/model_download.sh を実行してください"
    exit 1
fi
echo "[OK]   モデルパス: ${MODEL_PATH}"

# Primaryが起動しているか確認
if ! curl -sf "http://localhost:8080/health" > /dev/null 2>&1; then
    echo "[WARN] Primaryモデル (port 8080) が応答していません"
    echo "[WARN] 推奨起動順序: Primary → Secondary → LiteLLM"
fi

# VRAM確認（Primary分を除いた空きを確認）
VRAM_FREE=$(nvidia-smi --query-gpu=memory.free --format=csv,noheader,nounits | head -1)
REQUIRED_VRAM=22000  # MB
echo "[INFO] VRAM空き: ${VRAM_FREE}MB"
if [[ "$VRAM_FREE" -lt "$REQUIRED_VRAM" ]]; then
    echo "[ERROR] VRAM空きが不足しています: ${VRAM_FREE}MB < ${REQUIRED_VRAM}MB"
    echo "  nvidia-smi で使用状況を確認してください"
    exit 1
fi

if ss -tlnp 2>/dev/null | grep -q ":${PORT} "; then
    echo "[ERROR] ポート ${PORT} は既に使用中です"
    exit 1
fi
echo "[OK]   ポート ${PORT}: 利用可能"

# ── vLLM サーバー起動 ─────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  vLLM Secondary: Qwen 3.5 32B"
echo "  Model : ${MODEL_PATH}"
echo "  Port  : ${PORT}"
echo "  VRAM  : ${GPU_UTIL} (~22GB)"
echo "  MaxLen: ${MAX_MODEL_LEN} tokens"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

exec "$PYTHON" -m vllm.entrypoints.openai.api_server \
    --model "${MODEL_PATH}" \
    --served-model-name "qwen-32b" \
    --host "0.0.0.0" \
    --port "${PORT}" \
    --gpu-memory-utilization "${GPU_UTIL}" \
    --max-model-len "${MAX_MODEL_LEN}" \
    --max-num-seqs "${MAX_NUM_SEQS}" \
    --tensor-parallel-size 1 \
    --dtype "bfloat16" \
    --trust-remote-code \
    --enable-chunked-prefill \
    --max-num-batched-tokens 4096 \
    --disable-log-requests \
    2>&1 | tee -a "$LOG_FILE"
