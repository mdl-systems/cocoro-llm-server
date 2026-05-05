#!/usr/bin/env bash
# =============================================================================
# vllm/start_primary.sh
# Qwen3-Coder-Next-FP8 — vLLM起動スクリプト (Single-GPU構成)
#
# ポート       : 8000
# VRAM使用     : ~70GB (weights) + ~20GB (KV cache fp8) @ gpu_util=0.92
# アーキテクチャ: NVIDIA Blackwell RTX PRO 6000 (SM_120, CUDA 12.8)
# エイリアス   : qwen3-coder / gpt-4o / gpt-4o-mini (LiteLLM経由)
#
# 使用方法:
#   bash vllm/start_primary.sh          # 通常起動
#   bash vllm/start_primary.sh --check  # 環境チェックのみ
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "${SCRIPT_DIR}")"
ENV_FILE="${REPO_DIR}/.env"

# .env 読み込み
if [[ -f "${ENV_FILE}" ]]; then
    set -a
    # shellcheck disable=SC1090
    source "${ENV_FILE}"
    set +a
fi

# ---------------------------------------------------------------------------
# 設定値（.envで上書き可能）
# ---------------------------------------------------------------------------
MODEL_PATH="${PRIMARY_MODEL_PATH:-Qwen/Qwen3-Coder-Next-FP8}"
TOKENIZER_PATH="${PRIMARY_TOKENIZER_PATH:-${MODEL_PATH}}"
HOST="${PRIMARY_HOST:-0.0.0.0}"
PORT="${PRIMARY_PORT:-8000}"
GPU_UTIL="${PRIMARY_GPU_UTIL:-0.92}"
MAX_MODEL_LEN="${PRIMARY_MAX_MODEL_LEN:-262144}"
MAX_NUM_SEQS="${PRIMARY_MAX_NUM_SEQS:-32}"
LOG_DIR="${LOG_DIR:-/var/log/cocoro-llm}"
LOG_FILE="${LOG_DIR}/vllm-primary.log"
VENV_DIR="${VLLM_VENV_DIR:-/home/mdl/.venv/cocoro-llm}"
HF_HOME="${HF_CACHE_DIR:-/hf_cache}"

SERVED_MODEL_NAME="qwen3-coder"

# ---------------------------------------------------------------------------
# Blackwell SM_120 最適化: 環境変数
# ---------------------------------------------------------------------------
export CUDA_HOME="${CUDA_HOME:-/usr/local/cuda}"
export PATH="${CUDA_HOME}/bin:${PATH}"
export LD_LIBRARY_PATH="${CUDA_HOME}/lib64:${LD_LIBRARY_PATH:-}"
export HF_HOME="${HF_HOME}"

# vLLM Blackwell向け最適化
export VLLM_ATTENTION_BACKEND="${VLLM_ATTENTION_BACKEND:-FLASHINFER}"
export VLLM_WORKER_MULTIPROC_METHOD="${VLLM_WORKER_MULTIPROC_METHOD:-spawn}"
export VLLM_USE_V1="${VLLM_USE_V1:-1}"

# PyTorch メモリ断片化対策
export PYTORCH_CUDA_ALLOC_CONF="${PYTORCH_CUDA_ALLOC_CONF:-expandable_segments:True}"

# ---------------------------------------------------------------------------
# ロギング
# ---------------------------------------------------------------------------
mkdir -p "${LOG_DIR}"
_ts() { date '+%Y-%m-%dT%H:%M:%S%z'; }
log_info()  { echo "$(_ts) [INFO ] [vllm-primary] $*" | tee -a "${LOG_FILE}"; }
log_ok()    { echo "$(_ts) [OK   ] [vllm-primary] $*" | tee -a "${LOG_FILE}"; }
log_warn()  { echo "$(_ts) [WARN ] [vllm-primary] $*" | tee -a "${LOG_FILE}"; }
log_error() { echo "$(_ts) [ERROR] [vllm-primary] $*" | tee -a "${LOG_FILE}" >&2; }
die()       { log_error "$*"; exit 1; }

# ---------------------------------------------------------------------------
# メイン
# ---------------------------------------------------------------------------
main() {
    log_info "======================================================================"
    log_info "  vLLM Primary: Qwen3-Coder-Next-FP8"
    log_info "  Model     : ${MODEL_PATH}"
    log_info "  Endpoint  : http://0.0.0.0:${PORT}/v1"
    log_info "  GPU       : RTX PRO 6000 Blackwell (SM_120, 96GB GDDR7)"
    log_info "  VRAM予算  : ${GPU_UTIL} × 94.96GB ≈ 87.4GB"
    log_info "  Weights   : ~70GB (FP8)"
    log_info "  KV cache  : ~17GB (FP8 KV cache)"
    log_info "  Context   : ${MAX_MODEL_LEN} tokens (256K)"
    log_info "  MaxSeqs   : ${MAX_NUM_SEQS} 並列"
    log_info "  RAM       : 256GB DDR5"
    log_info "  HF Cache  : ${HF_HOME}"
    log_info "  Log       : ${LOG_FILE}"
    log_info "======================================================================"

    # --check フラグ処理
    if [[ "${1:-}" == "--check" ]]; then
        log_info "--check モード: 環境チェックのみ実行"
    fi

    # --- GPU ドライバ確認 ---
    log_info "--- GPU ドライバ確認 ---"
    if command -v nvidia-smi &>/dev/null; then
        DRIVER=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -1)
        log_info "NVIDIA Driver: ${DRIVER}"
    else
        die "nvidia-smi が見つかりません"
    fi

    # --- VRAM 事前チェック ---
    log_info "--- GPU VRAM 事前チェック ---"
    GPU_INFO=$(nvidia-smi --query-gpu=name,memory.total,memory.free --format=csv,noheader | head -1)
    GPU_NAME=$(echo "${GPU_INFO}" | cut -d',' -f1 | xargs)
    GPU_TOTAL=$(echo "${GPU_INFO}" | cut -d',' -f2 | tr -d ' MiB')
    GPU_FREE=$(echo "${GPU_INFO}" | cut -d',' -f3 | tr -d ' MiB')
    log_info "GPU 0: ${GPU_NAME}"
    log_info "  Total : ${GPU_TOTAL} MiB ($(( GPU_TOTAL / 1024 )) GiB)"
    log_info "  Free  : ${GPU_FREE} MiB ($(( GPU_FREE / 1024 )) GiB)"
    REQUIRED_MIB=71680  # 70GB
    if [[ ${GPU_FREE} -lt ${REQUIRED_MIB} ]]; then
        die "VRAM不足: 空き ${GPU_FREE} MiB < 必要 ${REQUIRED_MIB} MiB (他のプロセスを停止してください)"
    fi
    log_ok "VRAM チェック OK: ${GPU_FREE} MiB >= ${REQUIRED_MIB} MiB"

    # --- ポート確認 ---
    log_info "--- ポート ${PORT} 確認 ---"
    if ss -tlnp 2>/dev/null | grep -q ":${PORT} "; then
        die "ポート ${PORT} は既に使用中です。既存のプロセスを停止してください"
    fi
    log_info "ポート ${PORT}: 利用可能"

    # --- vLLM 仮想環境確認 ---
    log_info "--- vLLM 仮想環境確認 ---"
    PYTHON="${VENV_DIR}/bin/python"
    if [[ ! -x "${PYTHON}" ]]; then
        die "Python が見つかりません: ${PYTHON}"
    fi
    VLLM_VER=$("${PYTHON}" -c "import vllm; print(vllm.__version__)" 2>/dev/null || echo "不明")
    log_info "vLLM バージョン: ${VLLM_VER}"

    [[ "${1:-}" == "--check" ]] && { log_ok "環境チェック完了"; exit 0; }

    log_ok "全チェック完了。vLLM Primary を起動します..."

    # ------------------------------------------------------------------
    # vLLM 起動引数
    #
    # Qwen3-Coder-Next-FP8 + Blackwell SM_120 最適化:
    #   --dtype auto                  : FP8ウェイトをそのまま使用
    #   --quantization fp8            : FP8量子化カーネル明示指定
    #   --kv-cache-dtype fp8          : KVキャッシュもFP8（VRAM節約）
    #   --gpu-memory-util 0.92        : ~87GB確保 (weights 70GB + KV 17GB)
    #   --max-model-len 262144        : 256K context（Qwen3-Coderの強み）
    #   --max-num-seqs 32             : 32並列リクエスト
    #   --enable-chunked-prefill      : 長コンテキスト時のOOM防止
    #   --enable-prefix-caching       : 繰り返しシステムプロンプトのKV再利用
    #   --tool-call-parser qwen3_coder: OpenHandsツールコール必須フラグ
    # ------------------------------------------------------------------
    exec "${PYTHON}" -m vllm.entrypoints.openai.api_server \
        --model                  "${MODEL_PATH}" \
        --tokenizer              "${TOKENIZER_PATH}" \
        --served-model-name      "${SERVED_MODEL_NAME}" \
        --host                   "${HOST}" \
        --port                   "${PORT}" \
        \
        `# ---- メモリ・スループット ----` \
        --gpu-memory-utilization "${GPU_UTIL}" \
        --max-model-len          "${MAX_MODEL_LEN}" \
        --max-num-seqs           "${MAX_NUM_SEQS}" \
        --block-size             32 \
        \
        `# ---- FP8量子化設定 ----` \
        --dtype                  auto \
        --quantization           fp8 \
        --kv-cache-dtype         fp8 \
        \
        `# ---- Chunked Prefill & Prefix Cache ----` \
        --enable-chunked-prefill \
        --enable-prefix-caching \
        \
        `# ---- ツールコール（OpenHands必須）----` \
        --tool-call-parser       qwen3_coder \
        \
        `# ---- モデル設定 ----` \
        --trust-remote-code \
        \
        `# ---- テンソル並列 (シングルGPU) ----` \
        --tensor-parallel-size   1 \
        \
        `# ---- ログ ----` \
        --no-enable-log-requests \
        \
        2>&1 | tee -a "${LOG_FILE}"
}

main "$@"
