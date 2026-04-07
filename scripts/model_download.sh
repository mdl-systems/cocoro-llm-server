#!/usr/bin/env bash
# =============================================================================
# scripts/model_download.sh
# HuggingFaceからモデルをダウンロードするスクリプト
#
# ダウンロード対象:
#   1. Llama 4 Scout 17B-16E (MoE 109B相当, HuggingFace公式)
#      repo: unsloth/Llama-4-Scout-17B-16E-Instruct-GGUF
#      filter: *Q4_K_M* → /models/llama4-scout/ (推定: 65.4GB)
#      ※ gpu_util=0.72 → 69.1GB VRAM予算内に収まる
#   2. Qwen 2.5 32B AWQ量子化版 (22GB VRAM 予算に収まる)
#      repo: Qwen/Qwen2.5-32B-Instruct-AWQ
#      → /models/qwen35-32b/ (推定: 18〜20GB)
#
# 前提:
#   - huggingface-cli インストール済み
#   - HF_TOKEN が .env に設定済み
#   - /models/ に十分な空き容量（最低100GB）
#
# 実行方法:
#   bash scripts/model_download.sh
#   bash scripts/model_download.sh --primary-only
#   bash scripts/model_download.sh --secondary-only
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
fi

# ── 設定 ──────────────────────────────────────────────────────────────────────
HF_TOKEN="${HF_TOKEN:-}"
MODELS_BASE_DIR="/models"
PRIMARY_MODEL_DIR="${PRIMARY_MODEL_PATH:-/models/llama4-scout}"
SECONDARY_MODEL_DIR="${SECONDARY_MODEL_PATH:-/models/qwen35-32b}"
LOG_DIR="/var/log/cocoro-llm"
LOG_FILE="${LOG_DIR}/model_download.log"

# HuggingFaceリポジトリID
# Primary: Llama 4 Scout Q4_K_M GGUF (Unsloth, 65.4GB)
# ※ gpu_util=0.72 → 69.1GB VRAM予算内 ✅ (Q4_K_M は採用)
# ※ 旧設定(gpu_util=0.58, 55GB)では Q4_K_M 超過 → Q3_K_M を使用していたが
#    Primary=0.72 に変更したため Q4_K_M が収まるようになった
PRIMARY_HF_REPO="unsloth/Llama-4-Scout-17B-16E-Instruct-GGUF"
PRIMARY_INCLUDE="*Q4_K_M*"
# Secondary: Qwen 2.5 32B AWQ量子化版
# ※ Qwen 3.5 は未リリース。Qwen 2.5 AWQ が 22GB VRAM 予算に最適
# ※ vLLM が量子化を自動検出するため --quantization フラグ不要
SECONDARY_HF_REPO="Qwen/Qwen2.5-32B-Instruct-AWQ"
SECONDARY_INCLUDE=""

# 引数解析
DOWNLOAD_PRIMARY=true
DOWNLOAD_SECONDARY=true

for arg in "$@"; do
    case "$arg" in
        --primary-only)
            DOWNLOAD_SECONDARY=false ;;
        --secondary-only)
            DOWNLOAD_PRIMARY=false ;;
        --help|-h)
            echo "Usage: $0 [--primary-only | --secondary-only]"
            exit 0 ;;
    esac
done

# ── 色 ──────────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

mkdir -p "$LOG_DIR"

log()       { echo -e "$*" | tee -a "$LOG_FILE"; }
log_info()  { log "${BLUE}[INFO]${NC}  $*"; }
log_ok()    { log "${GREEN}[OK]${NC}    $*"; }
log_warn()  { log "${YELLOW}[WARN]${NC}  $*"; }
log_error() { log "${RED}[ERROR]${NC} $*" >&2; }

# ── 前提チェック ──────────────────────────────────────────────────────────────
check_prerequisites() {
    log_info "前提条件を確認しています..."

    # huggingface-cli チェック
    if ! command -v huggingface-cli &>/dev/null; then
        log_error "huggingface-cli が見つかりません"
        log_error "インストール: pip install huggingface_hub"
        exit 1
    fi
    log_ok "huggingface-cli: $(huggingface-cli --version 2>/dev/null || echo 'installed')"

    # HF_TOKEN チェック
    if [[ -z "$HF_TOKEN" ]]; then
        log_error "HF_TOKEN が設定されていません"
        log_error ".env に HF_TOKEN=hf_xxxx を設定してください"
        log_error "  https://huggingface.co/settings/tokens"
        exit 1
    fi
    log_ok "HF_TOKEN: 設定済み"

    # ストレージ確認 (最低100GB)
    mkdir -p "$MODELS_BASE_DIR"
    local available_gb
    available_gb=$(df "$MODELS_BASE_DIR" --output=avail -BG | tail -1 | tr -d 'G')
    log_info "ストレージ空き容量 (${MODELS_BASE_DIR}): ${available_gb}GB"
    if [[ "$available_gb" -lt 100 ]]; then
        log_error "ストレージ空き容量不足: ${available_gb}GB (最低100GB必要)"
        exit 1
    fi
    log_ok "ストレージ容量: ${available_gb}GB ✓"
}

# ── モデルダウンロード関数 ────────────────────────────────────────────────────
download_model() {
    local model_name="$1"
    local hf_repo="$2"
    local target_dir="$3"
    local include_pattern="${4:-}"

    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_info "ダウンロード: ${model_name}"
    log_info "  HF Repo : ${hf_repo}"
    if [[ -n "$include_pattern" ]]; then
    log_info "  フィルタ  : ${include_pattern}"
    fi
    log_info "  保存先  : ${target_dir}"
    log_info "  開始時刻: $(date '+%H:%M:%S')"
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    mkdir -p "$target_dir"

    # ダウンロード引数構築（includeフィルタ指定時のみ追加）
    local dl_args=(
        "$hf_repo"
        --local-dir "$target_dir"
        --resume-download
    )
    if [[ -n "$include_pattern" ]]; then
        dl_args+=(--include "$include_pattern")
    fi

    if HUGGING_FACE_HUB_TOKEN="$HF_TOKEN" \
       huggingface-cli download "${dl_args[@]}" \
        2>&1 | tee -a "$LOG_FILE"; then

        log_ok "${model_name}: ダウンロード完了 ($(date '+%H:%M:%S'))"

        local total_size
        total_size=$(du -sh "$target_dir" 2>/dev/null | awk '{print $1}')
        log_ok "ダウンロードサイズ: ${total_size}"

        log_info "ダウンロードファイル:"
        ls -lh "$target_dir"/*.safetensors 2>/dev/null | head -10 | tee -a "$LOG_FILE" || true
        ls -lh "$target_dir"/*.gguf        2>/dev/null | head -5  | tee -a "$LOG_FILE" || true

    else
        log_error "${model_name}: ダウンロード失敗"
        log_error "再実行: bash scripts/model_download.sh"
        return 1
    fi
}

# ── メイン ──────────────────────────────────────────────────────────────────
main() {
    log ""
    log "══════════════════════════════════════════════"
    log "  cocoro-llm-server モデルダウンロード"
    log "  $(date '+%Y-%m-%d %H:%M:%S')"
    log "══════════════════════════════════════════════"

    check_prerequisites

    if [[ "$DOWNLOAD_PRIMARY" == "true" ]]; then
        download_model \
            "Llama 4 Scout Q4_K_M GGUF" \
            "$PRIMARY_HF_REPO" \
            "$PRIMARY_MODEL_DIR" \
            "$PRIMARY_INCLUDE"
    fi

    if [[ "$DOWNLOAD_SECONDARY" == "true" ]]; then
        download_model \
            "Qwen 2.5 32B AWQ" \
            "$SECONDARY_HF_REPO" \
            "$SECONDARY_MODEL_DIR" \
            "$SECONDARY_INCLUDE"
    fi

    log ""
    log "══════════════════════════════════════════════"
    log_ok "全モデルダウンロード完了！"
    log "  Primary  : ${PRIMARY_MODEL_DIR}"
    log "  Secondary: ${SECONDARY_MODEL_DIR}"
    log ""
    log "次のステップ:"
    log "  source /usr/local/bin/vllm-activate"
    log "  bash vllm/start_primary.sh &"
    log "  bash vllm/start_secondary.sh &"
    log "══════════════════════════════════════════════"
    log ""
}

main "$@"
