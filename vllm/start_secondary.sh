#!/usr/bin/env bash
# =============================================================================
# vllm/start_secondary.sh
# Qwen 2.5 32B AWQ (Qwen/Qwen2.5-32B-Instruct-AWQ) — vLLM起動スクリプト (Secondary)
#
# ポート       : 8081
# VRAM上限     : ~22GB (gpu-memory-utilization 0.23)
# アーキテクチャ: NVIDIA Blackwell RTX PRO 6000 (SM_120, CUDA 12.8+)
# エイリアス   : gpt-4o-mini (LiteLLM経由)
# RAM          : 256GB DDR5 → CPUオフロード有効化可能
#
# 起動方法:
#   sudo systemctl start vllm-secondary   ← 通常運用
#   bash vllm/start_secondary.sh          ← 手動起動（デバッグ用）
#
# 注意: Primary (vllm-primary.service) を先に起動すること
#
# ログ:
#   /var/log/cocoro-llm/vllm-secondary.log
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
MODEL_PATH="${SECONDARY_MODEL_PATH:-/models/qwen35-32b}"
# AWQモデルはトークナイザー内ずみ→モデルディレクトリのローカルパスを使用
TOKENIZER_PATH="${SECONDARY_TOKENIZER_PATH:-${MODEL_PATH}}"
HOST="${SECONDARY_HOST:-0.0.0.0}"
PORT="${SECONDARY_PORT:-8081}"
GPU_UTIL="${SECONDARY_GPU_UTIL:-0.23}"
# Secondaryは短文・高速応答向け: 32K context
MAX_MODEL_LEN="${SECONDARY_MAX_MODEL_LEN:-32768}"
MAX_NUM_SEQS="${SECONDARY_MAX_NUM_SEQS:-32}"
MAX_NUM_BATCHED_TOKENS="${SECONDARY_MAX_NUM_BATCHED_TOKENS:-4096}"
LOG_DIR="${LOG_DIR:-/var/log/cocoro-llm}"
LOG_FILE="${LOG_DIR}/vllm-secondary.log"
VENV_DIR="${VLLM_VENV_DIR:-/opt/vllm-env}"

# vLLM の served-model-name（LiteLLMルーティングと一致させること）
SERVED_MODEL_NAME="qwen-32b"

# ---------------------------------------------------------------------------
# Blackwell SM_120 最適化: 環境変数
#
# 参考: https://docs.vllm.ai/en/latest/deployment/env_vars.html
# ---------------------------------------------------------------------------
export CUDA_HOME="${CUDA_HOME:-/usr/local/cuda}"
export PATH="${CUDA_HOME}/bin:${PATH}"
export LD_LIBRARY_PATH="${CUDA_HOME}/lib64:${LD_LIBRARY_PATH:-}"

# Blackwell (SM_120) のカーネルコンパイル対象を明示
export TORCH_CUDA_ARCH_LIST="12.0"
export FLASHINFER_CUDA_ARCH_LIST="12.0"

# マルチプロセスワーカー: spawn が Blackwell + PyTorch で最も安定
export VLLM_WORKER_MULTIPROC_METHOD="spawn"

# アテンションバックエンド: FlashInfer（Primaryと共通、Blackwell SM_120対応済み）
export VLLM_ATTENTION_BACKEND="${VLLM_ATTENTION_BACKEND:-FLASHINFER}"

# PCIe環境での設定（シングルGPU）
export NCCL_P2P_DISABLE="${NCCL_P2P_DISABLE:-0}"

# コンパイルキャッシュ
export VLLM_DISABLE_COMPILE_CACHE="${VLLM_DISABLE_COMPILE_CACHE:-0}"

# CUDA可視デバイス（デフォルト: GPU 0、Primary と同じ GPU を共用）
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
log_info()  { echo "$(_ts) [INFO ] [vllm-secondary] $*" | tee -a "${LOG_FILE}"; }
log_warn()  { echo "$(_ts) [WARN ] [vllm-secondary] $*" | tee -a "${LOG_FILE}"; }
log_error() { echo "$(_ts) [ERROR] [vllm-secondary] $*" | tee -a "${LOG_FILE}" >&2; }
die()       { log_error "$*"; exit 1; }

# ---------------------------------------------------------------------------
# 起動バナー
# ---------------------------------------------------------------------------
print_banner() {
    log_info "======================================================"
    log_info "  vLLM Secondary: Qwen 2.5 32B AWQ"
    log_info "  Model     : Qwen/Qwen2.5-32B-Instruct-AWQ"
    log_info "  Endpoint  : http://${HOST}:${PORT}/v1"
    log_info "  GPU       : RTX PRO 6000 Blackwell (SM_120)"
    log_info "  VRAM予算  : ${GPU_UTIL} × 96GB ≈ 22GB"
    log_info "  Context   : ${MAX_MODEL_LEN} tokens"
    log_info "  MaxSeqs   : ${MAX_NUM_SEQS} 並列"
    log_info "  AttnBackend: ${VLLM_ATTENTION_BACKEND}"
    log_info "  KV dtype  : fp8 (Blackwell HW native)"
    log_info "  RAM       : 256GB DDR5 (CPUオフロード有効)"
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
}

# ---------------------------------------------------------------------------
# 事前チェック 2: Primary の稼働確認
# ---------------------------------------------------------------------------
check_primary() {
    log_info "--- Primary (port 8080) 稼働確認 ---"
    local primary_port="${PRIMARY_PORT:-8080}"
    if curl -sf --max-time 5 "http://localhost:${primary_port}/health" >/dev/null 2>&1; then
        log_info "Primary (port ${primary_port}): 稼働中 ✓"
    else
        log_warn "Primary (port ${primary_port}) が応答していません。"
        log_warn "推奨起動順序: vllm-primary → vllm-secondary → LiteLLM"
        log_warn "Secondary 単体での起動を続行します..."
    fi
}

# ---------------------------------------------------------------------------
# 事前チェック 3: GPU VRAM確認
#   Secondary 起動時: Primary が 55GB 使用済みの状態を想定。
#   残り ~41GB のうち 22GB (22,000 MiB) が利用可能かを確認。
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

    # Secondary に最低限必要な VRAM: 22,000 MiB
    # ※ Primary が 55GB 使用中でも、残り ~41GB があれば十分
    local required_mib=22000
    if (( mem_free < required_mib )); then
        die "VRAM 不足: 必要 ${required_mib} MiB, 空き ${mem_free} MiB。" \
            "Primary が想定以上の VRAM を使用している可能性があります。" \
            "'nvidia-smi' でプロセス別使用量を確認してください。"
    fi

    log_info "VRAM チェック OK: ${mem_free} MiB >= ${required_mib} MiB (Secondary 用)"
}

# ---------------------------------------------------------------------------
# 事前チェック 4: ポート確認
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
# 事前チェック 5: vLLM 仮想環境
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
# 事前チェック 6: モデルファイル確認
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
            ".env の SECONDARY_MODEL_PATH を確認してください。"
    fi
}

# ---------------------------------------------------------------------------
# メイン: vLLM サーバー起動
# ---------------------------------------------------------------------------
main() {
    print_banner
    check_nvidia_smi
    check_primary
    check_gpu_memory
    check_port
    check_venv
    check_model

    log_info "全チェック完了。vLLM Secondary を起動します..."

    PYTHON="${VENV_DIR}/bin/python"

    # ------------------------------------------------------------------
    # vLLM 起動引数
    #
    # Blackwell SM_120 最適化ポイント:
    #   --dtype bfloat16        : BF16はBlackwell推奨
    #   --kv-cache-dtype fp8    : Blackwell HW ネイティブ FP8演算
    #   --enable-chunked-prefill: メモリ効率向上
    #   --block-size 32         : 大VRAM環境での大ブロックサイズ
    #   VLLM_ATTENTION_BACKEND  : FlashInfer (SM_120対応済み)
    #
    # Qwen 3.5 32B MoE 固有:
    #   --enable-expert-parallel: MoEのExpert並列化を有効化
    #   --trust-remote-code     : Qwen カスタムアーキテクチャのため必要
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
        `# ---- Chunked Prefill ----` \
        --enable-chunked-prefill \
        \
        `# ---- Denseモデル設定 (Qwen 2.5 32BはMoEではなく Dense) ----` \
        --trust-remote-code \
        \
        `# ---- テンソル並列 (シングルGPU) ----` \
        --tensor-parallel-size        1 \
        \
        `# ---- ログ・メトリクス ----` \
        --no-enable-log-requests \
        \
        2>&1 | tee -a "${LOG_FILE}"
}

main "$@"
