#!/usr/bin/env bash
# =============================================================================
# vllm/start_primary.sh
# Llama 4 Scout 109B Q4_K_M — vLLM起動スクリプト (Primary)
#
# ポート       : 8080
# VRAM上限     : ~55GB (gpu-memory-utilization 0.58)
# アーキテクチャ: NVIDIA Blackwell RTX PRO 6000 (SM_120, CUDA 12.8+)
# エイリアス   : gpt-4o (LiteLLM経由)
#
# 起動方法:
#   sudo systemctl start vllm-primary   ← 通常運用
#   bash vllm/start_primary.sh          ← 手動起動（デバッグ用）
#
# ログ:
#   /var/log/cocoro-llm/vllm-primary.log
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# パス解決
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "${SCRIPT_DIR}")"

# ---------------------------------------------------------------------------
# .env 読み込み
# ---------------------------------------------------------------------------
ENV_FILE="${REPO_DIR}/.env"
if [[ -f "${ENV_FILE}" ]]; then
    set -a
    # shellcheck disable=SC1090
    source "${ENV_FILE}"
    set +a
else
    echo "[ERROR] .env が見つかりません: ${ENV_FILE}" >&2
    echo "        cp ${REPO_DIR}/.env.example ${ENV_FILE} を実行してください" >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# 設定値（.envで上書き可能）
# ---------------------------------------------------------------------------
MODEL_PATH="${PRIMARY_MODEL_PATH:-/models/llama4-scout-q4_k_m.gguf}"
# GGUFを使う場合は tokenizer を明示指定（embedded tokenizer は不安定）
TOKENIZER_PATH="${PRIMARY_TOKENIZER_PATH:-meta-llama/Llama-4-Scout-17B-16E-Instruct}"
HOST="${PRIMARY_HOST:-0.0.0.0}"
PORT="${PRIMARY_PORT:-8080}"
GPU_UTIL="${PRIMARY_GPU_UTIL:-0.58}"
# 55GB VRAM予算 + FP8 KVキャッシュで 128K context を確保
# より長い context が必要な場合は .env で MAX_MODEL_LEN をオーバーライド
MAX_MODEL_LEN="${PRIMARY_MAX_MODEL_LEN:-131072}"
MAX_NUM_SEQS="${PRIMARY_MAX_NUM_SEQS:-32}"
MAX_NUM_BATCHED_TOKENS="${PRIMARY_MAX_NUM_BATCHED_TOKENS:-8192}"
LOG_DIR="${LOG_DIR:-/var/log/cocoro-llm}"
LOG_FILE="${LOG_DIR}/vllm-primary.log"
VENV_DIR="${VLLM_VENV_DIR:-/opt/vllm-env}"

# vLLM の served-model-name（LiteLLMルーティングと一致させること）
SERVED_MODEL_NAME="llama4-scout"

# ---------------------------------------------------------------------------
# Blackwell SM_120 最適化: 環境変数
#
# 参考: https://docs.vllm.ai/en/latest/deployment/env_vars.html
#       https://github.com/vllm-project/vllm/issues/blackwell
# ---------------------------------------------------------------------------
export CUDA_HOME="${CUDA_HOME:-/usr/local/cuda}"
export PATH="${CUDA_HOME}/bin:${PATH}"
export LD_LIBRARY_PATH="${CUDA_HOME}/lib64:${LD_LIBRARY_PATH:-}"

# Blackwell (SM_120) のカーネルコンパイル対象を明示
export TORCH_CUDA_ARCH_LIST="12.0"
export FLASHINFER_CUDA_ARCH_LIST="12.0"

# マルチプロセスワーカー: spawn が Blackwell + PyTorch で最も安定
export VLLM_WORKER_MULTIPROC_METHOD="spawn"

# アテンションバックエンド:
#   FLASHINFER → Blackwell対応済み（vLLM 0.6.0+）
#   TRITON_ATTN → FlashInferがクラッシュする場合のフォールバック
#   .env で VLLM_ATTENTION_BACKEND=TRITON_ATTN に変更可能
export VLLM_ATTENTION_BACKEND="${VLLM_ATTENTION_BACKEND:-FLASHINFER}"

# PCIe環境でのP2P通信問題を回避（RTX Pro 6000はNVLink非搭載）
# シングルGPU構成のため実質不要だが、念のため設定
export NCCL_P2P_DISABLE="${NCCL_P2P_DISABLE:-0}"

# コンパイルキャッシュ（初回起動が遅い場合は 1 にして無効化）
export VLLM_DISABLE_COMPILE_CACHE="${VLLM_DISABLE_COMPILE_CACHE:-0}"

# CUDA可視デバイス（デフォルト: GPU 0）
export CUDA_VISIBLE_DEVICES="${CUDA_VISIBLE_DEVICES:-0}"

# ---------------------------------------------------------------------------
# ログ・PIDディレクトリの準備
# ---------------------------------------------------------------------------
mkdir -p "${LOG_DIR}"
chmod 755 "${LOG_DIR}"

# ---------------------------------------------------------------------------
# ロギング関数
# ---------------------------------------------------------------------------
_ts() { date '+%Y-%m-%dT%H:%M:%S%z'; }
log_info()  { echo "$(_ts) [INFO ] [vllm-primary] $*" | tee -a "${LOG_FILE}"; }
log_warn()  { echo "$(_ts) [WARN ] [vllm-primary] $*" | tee -a "${LOG_FILE}"; }
log_error() { echo "$(_ts) [ERROR] [vllm-primary] $*" | tee -a "${LOG_FILE}" >&2; }
die()       { log_error "$*"; exit 1; }

# ---------------------------------------------------------------------------
# 起動バナー
# ---------------------------------------------------------------------------
print_banner() {
    log_info "======================================================"
    log_info "  vLLM Primary: Llama 4 Scout 109B Q4_K_M"
    log_info "  Endpoint  : http://${HOST}:${PORT}/v1"
    log_info "  GPU       : RTX PRO 6000 Blackwell (SM_120)"
    log_info "  VRAM予算  : ${GPU_UTIL} × 96GB ≈ 69GB (Q4_K_M 65.4GB + KV 3.7GB)"
    log_info "  Context   : ${MAX_MODEL_LEN} tokens"
    log_info "  MaxSeqs   : ${MAX_NUM_SEQS} 並列"
    log_info "  AttnBackend: ${VLLM_ATTENTION_BACKEND}"
    log_info "  KV dtype  : fp8 (Blackwell HW native)"
    log_info "  Log       : ${LOG_FILE}"
    log_info "======================================================"
}

# ---------------------------------------------------------------------------
# 事前チェック 1: nvidia-smi / CUDA
# ---------------------------------------------------------------------------
check_nvidia_smi() {
    log_info "--- GPU ドライバ確認 ---"
    if ! command -v nvidia-smi &>/dev/null; then
        die "nvidia-smi が見つかりません。NVIDIAドライバ (>=560) が必要です。"
    fi

    local driver_version
    driver_version=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -1)
    log_info "NVIDIA Driver: ${driver_version}"

    local cuda_version
    cuda_version=$(nvidia-smi --query-gpu=cuda_version --format=csv,noheader | head -1)
    log_info "CUDA Version : ${cuda_version}"
}

# ---------------------------------------------------------------------------
# 事前チェック 2: GPU VRAM確認
#   Primary 起動前: GPU 全体の空きが 55,000 MiB (≈55GB) 以上あることを確認
# ---------------------------------------------------------------------------
check_gpu_memory() {
    log_info "--- GPU VRAM 事前チェック ---"

    local gpu_idx="${CUDA_VISIBLE_DEVICES:-0}"

    local raw
    raw=$(nvidia-smi --query-gpu=index,name,memory.total,memory.free,memory.used \
        --format=csv,noheader,nounits -i "${gpu_idx}" 2>/dev/null) \
        || die "nvidia-smi による GPU ${gpu_idx} の VRAM取得に失敗しました。"

    # CSV: "index, name, total, free, used"
    # IFS=',' のみ使用（スペースも区切りにすると GPU名が分割される）
    local idx gpu_name mem_total mem_free mem_used
    IFS=',' read -r idx gpu_name mem_total mem_free mem_used <<< "${raw}"
    # 先頭の空白をトリム（nvidia-smi は ", " で区切るため）
    idx=$(echo "$idx" | xargs)
    gpu_name=$(echo "$gpu_name" | xargs)
    mem_total=$(echo "$mem_total" | xargs)
    mem_free=$(echo "$mem_free" | xargs)
    mem_used=$(echo "$mem_used" | xargs)

    log_info "GPU ${idx}: ${gpu_name}"
    log_info "  Total : ${mem_total} MiB ($(( mem_total / 1024 )) GiB)"
    log_info "  Free  : ${mem_free} MiB ($(( mem_free  / 1024 )) GiB)"
    log_info "  Used  : ${mem_used} MiB ($(( mem_used  / 1024 )) GiB)"

    # Primary 単独起動時の最低要求: 55,000 MiB
    # ※ systemd で Primary → Secondary の順に起動するため、
    #    Primary起動時点では GPU は空きであることが前提
    local required_mib=55000
    if (( mem_free < required_mib )); then
        die "VRAM 不足: 必要 ${required_mib} MiB, 空き ${mem_free} MiB。" \
            "他のプロセスが GPU を専有していないか確認してください: nvidia-smi"
    fi

    log_info "VRAM チェック OK: ${mem_free} MiB >= ${required_mib} MiB"

    # 既存Computeプロセスの警告（異常終了の残骸など）
    local n_procs
    n_procs=$(nvidia-smi --query-compute-apps=pid --format=csv,noheader -i "${gpu_idx}" \
        2>/dev/null | grep -c '[0-9]' || echo 0)
    if (( n_procs > 0 )); then
        log_warn "GPU ${gpu_idx} に既存の計算プロセスが ${n_procs} 件あります。"
        log_warn "必要であれば 'sudo fuser -k /dev/nvidia${gpu_idx}' で解放してください。"
    fi
}

# ---------------------------------------------------------------------------
# 事前チェック 3: ポート確認
# ---------------------------------------------------------------------------
check_port() {
    log_info "--- ポート ${PORT} 確認 ---"
    if ss -tlnp 2>/dev/null | grep -q ":${PORT}[[:space:]]"; then
        die "ポート ${PORT} はすでに使用中です。" \
            "'sudo lsof -i :${PORT}' で確認してください。"
    fi
    log_info "ポート ${PORT}: 利用可能"
}

# ---------------------------------------------------------------------------
# 事前チェック 4: vLLM 仮想環境
# ---------------------------------------------------------------------------
check_venv() {
    log_info "--- vLLM 仮想環境確認 ---"
    if [[ ! -f "${VENV_DIR}/bin/python" ]]; then
        die "vLLM仮想環境が見つかりません: ${VENV_DIR}/bin/python" \
            "'sudo bash scripts/setup_vllm.sh' を先に実行してください。"
    fi
    local vllm_version
    vllm_version=$("${VENV_DIR}/bin/python" -c "import vllm; print(vllm.__version__)" 2>/dev/null || echo "不明")
    log_info "vLLM バージョン: ${vllm_version}"
}

# ---------------------------------------------------------------------------
# 事前チェック 5: モデルファイル確認
# ---------------------------------------------------------------------------
check_model() {
    log_info "--- モデルファイル確認 ---"
    log_info "MODEL_PATH: ${MODEL_PATH}"

    # GGUFの場合はファイル、HuggingFace形式の場合はディレクトリ
    if [[ "${MODEL_PATH}" == *.gguf ]]; then
        [[ -f "${MODEL_PATH}" ]] \
            || die "GGUFファイルが見つかりません: ${MODEL_PATH}"
        local size
        size=$(du -sh "${MODEL_PATH}" | cut -f1)
        log_info "GGUF ファイル確認 OK: ${size}"
    elif [[ -d "${MODEL_PATH}" ]]; then
        [[ -f "${MODEL_PATH}/config.json" ]] \
            || die "モデルディレクトリに config.json がありません: ${MODEL_PATH}"
        log_info "HuggingFace モデルディレクトリ確認 OK"
    else
        die "モデルが見つかりません: ${MODEL_PATH}" \
            "GGUF ファイルまたは HuggingFace ディレクトリを指定してください。" \
            ".env の PRIMARY_MODEL_PATH を確認してください。"
    fi
}

# ---------------------------------------------------------------------------
# メイン: vLLM サーバー起動
# ---------------------------------------------------------------------------
main() {
    print_banner
    check_nvidia_smi
    check_gpu_memory
    check_port
    check_venv
    check_model

    log_info "全チェック完了。vLLM Primary を起動します..."

    PYTHON="${VENV_DIR}/bin/python"

    # ------------------------------------------------------------------
    # vLLM 起動引数
    #
    # Blackwell SM_120 最適化ポイント:
    #   --dtype bfloat16        : BF16はBlackwell推奨 (FP16より数値的に安定)
    #   --kv-cache-dtype fp8    : Blackwell HW ネイティブ FP8演算 → KVキャッシュ30%削減
    #   --enable-chunked-prefill: 長文コンテキストでのメモリ効率向上
    #   --block-size 32         : 大VRAM環境ではブロックサイズ32が有利
    #   VLLM_ATTENTION_BACKEND  : FlashInfer (SM_120対応済み)
    # ------------------------------------------------------------------
    exec "${PYTHON}" -m vllm.entrypoints.openai.api_server \
        --model                       "${MODEL_PATH}" \
        --tokenizer                   "${TOKENIZER_PATH}" \
        --served-model-name           "${SERVED_MODEL_NAME}" \
        --host                        "${HOST}" \
        --port                        "${PORT}" \
        \
        `# ---- メモリ・スループット ----` \
        --gpu-memory-utilization      "${GPU_UTIL}" \
        --max-model-len               "${MAX_MODEL_LEN}" \
        --max-num-seqs                "${MAX_NUM_SEQS}" \
        --max-num-batched-tokens      "${MAX_NUM_BATCHED_TOKENS}" \
        --block-size                  32 \
        \
        `# ---- Blackwell SM_120 精度最適化 ----` \
        --dtype                       bfloat16 \
        --kv-cache-dtype              fp8 \
        \
        `# ---- Chunked Prefill (長文コンテキスト効率化) ----` \
        --enable-chunked-prefill \
        \
        `# ---- Llama 4 Scout MoE 固有設定 ----` \
        --override-generation-config  '{"attn_temperature_tuning": true}' \
        --trust-remote-code \
        \
        `# ---- テンソル並列 (シングルGPU) ----` \
        --tensor-parallel-size        1 \
        \
        `# ---- ログ・メトリクス ----` \
        --enable-metrics \
        --disable-log-requests \
        \
        2>&1 | tee -a "${LOG_FILE}"
}

main "$@"
