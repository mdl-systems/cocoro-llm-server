#!/usr/bin/env bash
# =============================================================================
# vllm/start_primary.sh
# Llama 4 Scout 109B Q4_K_M — 起動スクリプト
#
# ポート  : 8080
# VRAM    : ~55GB (gpu-memory-utilization 0.58)
# モデル  : meta-llama/Llama-4-Scout-17B-16E-Instruct (Q4_K_M AWQ)
# エイリアス: gpt-4o (LiteLLM経由)
#
# 実行方法:
#   source /usr/local/bin/vllm-activate
#   bash vllm/start_primary.sh
#
# バックグラウンド起動:
#   bash vllm/start_primary.sh &
#   journalctl -u vllm-primary -f  (systemd経由の場合)
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
    echo "  cp ${REPO_DIR}/.env.example ${REPO_DIR}/.env を実行してください"
    exit 1
fi

# ── 設定値（.envで上書き可能）─────────────────────────────────────────────────
MODEL_PATH="${PRIMARY_MODEL_PATH:-/models/llama4-scout}"
PORT="${PRIMARY_PORT:-8080}"
GPU_UTIL="${PRIMARY_GPU_UTIL:-0.58}"
MAX_MODEL_LEN="${MAX_MODEL_LEN:-32768}"
MAX_NUM_SEQS="${MAX_NUM_SEQS:-16}"
LOG_DIR="/var/log/cocoro-llm"
LOG_FILE="${LOG_DIR}/vllm-primary.log"

# ── Blackwell 環境変数 ─────────────────────────────────────────────────────────
export CUDA_HOME="/usr/local/cuda"
export PATH="${CUDA_HOME}/bin:${PATH}"
export LD_LIBRARY_PATH="${CUDA_HOME}/lib64:${LD_LIBRARY_PATH:-}"
export TORCH_CUDA_ARCH_LIST="12.0"
export FLASHINFER_CUDA_ARCH_LIST="12.0f"
export VLLM_WORKER_MULTIPROC_METHOD="spawn"

# vLLM 仮想環境確認
VENV_DIR="/opt/vllm-env"
if [[ ! -f "${VENV_DIR}/bin/python" ]]; then
    echo "[ERROR] vLLM仮想環境が見つかりません: ${VENV_DIR}"
    echo "  sudo bash scripts/setup_vllm.sh を先に実行してください"
    exit 1
fi

PYTHON="${VENV_DIR}/bin/python"

# ── ログディレクトリ ──────────────────────────────────────────────────────────
mkdir -p "$LOG_DIR"

# ── 起動前チェック ─────────────────────────────────────────────────────────────
echo "[INFO] vLLM Primary (Llama 4 Scout) 起動チェック..."

# モデルパス確認
if [[ ! -d "$MODEL_PATH" ]]; then
    echo "[ERROR] モデルが見つかりません: ${MODEL_PATH}"
    echo "  bash scripts/model_download.sh を実行してモデルをダウンロードしてください"
    exit 1
fi
echo "[OK]   モデルパス: ${MODEL_PATH}"

# VRAM確認
VRAM_FREE=$(nvidia-smi --query-gpu=memory.free --format=csv,noheader,nounits | head -1)
VRAM_TOTAL=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits | head -1)
REQUIRED_VRAM=55000  # MB
echo "[INFO] VRAM空き: ${VRAM_FREE}MB / ${VRAM_TOTAL}MB"
if [[ "$VRAM_FREE" -lt "$REQUIRED_VRAM" ]]; then
    echo "[WARN] VRAM空き${VRAM_FREE}MBが推奨${REQUIRED_VRAM}MB未満です"
    echo "[WARN] Secondaryモデルが起動中の場合は正常です"
fi

# ポート確認
if ss -tlnp 2>/dev/null | grep -q ":${PORT} "; then
    echo "[ERROR] ポート ${PORT} は既に使用中です"
    echo "  kill \$(lsof -t -i:${PORT}) で停止してから再実行してください"
    exit 1
fi
echo "[OK]   ポート ${PORT}: 利用可能"

# ── vLLM サーバー起動 ─────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  vLLM Primary: Llama 4 Scout 109B"
echo "  Model : ${MODEL_PATH}"
echo "  Port  : ${PORT}"
echo "  VRAM  : ${GPU_UTIL} (${VRAM_TOTAL}MB の $(echo "scale=0; ${GPU_UTIL} * 100 / 1" | bc)%)"
echo "  MaxLen: ${MAX_MODEL_LEN} tokens"
echo "  MaxSeq: ${MAX_NUM_SEQS} 並列"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

exec "$PYTHON" -m vllm.entrypoints.openai.api_server \
    --model "${MODEL_PATH}" \
    --served-model-name "llama4-scout" \
    --host "0.0.0.0" \
    --port "${PORT}" \
    --gpu-memory-utilization "${GPU_UTIL}" \
    --max-model-len "${MAX_MODEL_LEN}" \
    --max-num-seqs "${MAX_NUM_SEQS}" \
    --tensor-parallel-size 1 \
    --dtype "bfloat16" \
    --trust-remote-code \
    --enable-chunked-prefill \
    --max-num-batched-tokens 8192 \
    --disable-log-requests \
    2>&1 | tee -a "$LOG_FILE"
