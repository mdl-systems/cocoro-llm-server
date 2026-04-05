#!/usr/bin/env bash
# =============================================================================
# scripts/setup_vllm.sh
# vLLM Blackwell (sm_120) ソースビルド + インストールスクリプト
#
# 対象環境:
#   OS  : Debian 13 Trixie
#   GPU : RTX PRO 6000 Blackwell (GB202 / sm_120)
#   CUDA: 12.8（setup_nvidia.sh 実行済み前提）
#   Venv: /opt/vllm-env
#
# ⚠️  なぜソースビルドが必要か:
#   Blackwell (sm_120) の公式 PyPI wheels は 2026年初頭時点で存在しない。
#   pip install vllm でインストールした場合、起動時に以下エラーが出る:
#     "no kernel image is available for execution on the device"
#   → TORCH_CUDA_ARCH_LIST="12.0" を指定してソースビルドが必要。
#
# 参考:
#   https://docs.vllm.ai/en/latest/getting_started/installation.html
#   https://github.com/vllm-project/vllm/issues/Blackwell
#
# 実行方法:
#   sudo bash scripts/setup_vllm.sh
#
# 所要時間: 約 30〜60 分（ビルド時間含む）
# =============================================================================

set -euo pipefail

# ── カラー出力 ────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info()  { echo -e "${BLUE}[INFO]${NC}  $*" | tee -a "$LOG_FILE"; }
log_ok()    { echo -e "${GREEN}[OK]${NC}    $*" | tee -a "$LOG_FILE"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $*" | tee -a "$LOG_FILE"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" | tee -a "$LOG_FILE" >&2; }
log_step()  { echo -e "\n${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; \
              echo -e "${CYAN}  $*${NC}"; \
              echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}" | tee -a "$LOG_FILE"; }

# ── 定数 ──────────────────────────────────────────────────────────────────────
VENV_DIR="/opt/vllm-env"
LOG_DIR="/var/log/cocoro-llm"
LOG_FILE="${LOG_DIR}/setup_vllm.log"
VLLM_BUILD_DIR="/opt/vllm-build"
CUDA_ARCH="12.0"           # RTX PRO 6000 Blackwell (sm_120) = "12.0"
PYTHON_BIN="python3"
MAX_JOBS=$(nproc)          # CPUコア数に合わせてビルドジョブ数を設定

# ── ログディレクトリ準備 ──────────────────────────────────────────────────────
setup_logging() {
    mkdir -p "$LOG_DIR"
    touch "$LOG_FILE"
    chmod 755 "$LOG_DIR"
    echo "========================================" >> "$LOG_FILE"
    echo "vLLM Setup Start: $(date '+%Y-%m-%d %H:%M:%S')" >> "$LOG_FILE"
    echo "========================================" >> "$LOG_FILE"
}

# ── 前提条件チェック ───────────────────────────────────────────────────────────
check_prerequisites() {
    log_step "Step 0: 前提条件チェック"

    # root権限チェック
    if [[ $EUID -ne 0 ]]; then
        log_error "このスクリプトはroot権限で実行してください: sudo bash scripts/setup_vllm.sh"
        exit 1
    fi

    # CUDA 12.8チェック
    local cuda_version=""
    if [[ -f /usr/local/cuda/bin/nvcc ]]; then
        cuda_version=$(/usr/local/cuda/bin/nvcc --version 2>/dev/null | grep "release" | awk '{print $6}' | tr -d ',V')
    elif command -v nvcc &>/dev/null; then
        cuda_version=$(nvcc --version 2>/dev/null | grep "release" | awk '{print $6}' | tr -d ',V')
    fi

    if [[ -z "$cuda_version" ]]; then
        log_error "CUDAが見つかりません。先に setup_nvidia.sh を実行してください"
        exit 1
    fi

    local major minor
    major=$(echo "$cuda_version" | cut -d'.' -f1)
    minor=$(echo "$cuda_version" | cut -d'.' -f2)

    log_info "CUDA バージョン: ${cuda_version}"

    # Blackwell (sm_120) には CUDA 12.8+ が必須
    if [[ "$major" -lt 12 ]] || { [[ "$major" -eq 12 ]] && [[ "$minor" -lt 8 ]]; }; then
        log_error "CUDA ${cuda_version} は Blackwell (sm_120) に対応していません"
        log_error "最小要件: CUDA 12.8"
        log_error "先に sudo bash scripts/setup_nvidia.sh を実行してCUDA 12.8をインストールしてください"
        exit 1
    fi
    log_ok "CUDA ${cuda_version}: Blackwell対応 ✓"

    # nvidia-smiチェック
    if ! command -v nvidia-smi &>/dev/null; then
        log_error "nvidia-smiが見つかりません。NVIDIAドライバを先にインストールしてください"
        exit 1
    fi

    # GPU確認
    local gpu_name
    gpu_name=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1)
    log_info "검出されたGPU: ${gpu_name}"

    # Python 3.11以上チェック
    local python_version
    python_version=$($PYTHON_BIN --version 2>&1 | awk '{print $2}')
    local py_major py_minor
    py_major=$(echo "$python_version" | cut -d'.' -f1)
    py_minor=$(echo "$python_version" | cut -d'.' -f2)

    log_info "Python バージョン: ${python_version}"
    if [[ "$py_major" -lt 3 ]] || { [[ "$py_major" -eq 3 ]] && [[ "$py_minor" -lt 11 ]]; }; then
        log_error "Python 3.11以上が必要です。現在: ${python_version}"
        exit 1
    fi
    log_ok "Python ${python_version} ✓"

    # ディスク容量チェック（ビルドに最低20GB必要）
    local available_gb
    available_gb=$(df /opt --output=avail -BG | tail -1 | tr -d 'G')
    log_info "ディスク空き容量 (/opt): ${available_gb}GB"
    if [[ "$available_gb" -lt 20 ]]; then
        log_error "ディスク空き容量不足: ${available_gb}GB (最低20GB必要)"
        exit 1
    fi
    log_ok "ディスク容量 ✓"

    # RAM確認（ビルドに最低32GB推奨）
    local total_ram_gb
    total_ram_gb=$(awk '/MemTotal/ {printf "%d", $2/1024/1024}' /proc/meminfo)
    log_info "搭載RAM: ${total_ram_gb}GB"
    if [[ "$total_ram_gb" -lt 32 ]]; then
        log_warn "RAM ${total_ram_gb}GB: ビルドが遅くなる可能性あり（推奨: 32GB以上）"
        # MAX_JOBSを制限してOOMを防止
        if [[ "$MAX_JOBS" -gt 8 ]]; then
            MAX_JOBS=8
            log_warn "MAX_JOBS を ${MAX_JOBS} に制限します（OOM防止）"
        fi
    fi

    log_ok "前提条件チェック完了"
}

# ── Step 1: 依存パッケージのインストール ──────────────────────────────────────
install_build_deps() {
    log_step "Step 1: ビルド依存パッケージをインストール"

    apt-get update -y 2>&1 | tee -a "$LOG_FILE"

    apt-get install -y \
        python3-venv \
        python3-pip \
        python3-dev \
        git \
        git-lfs \
        build-essential \
        cmake \
        ninja-build \
        pkg-config \
        libssl-dev \
        libffi-dev \
        libnuma-dev \
        2>&1 | tee -a "$LOG_FILE"

    log_ok "ビルド依存パッケージのインストール完了"
}

# ── Step 2: Python仮想環境作成 ────────────────────────────────────────────────
create_venv() {
    log_step "Step 2: Python仮想環境を作成 (${VENV_DIR})"

    # 既存のvenvがあれば削除確認
    if [[ -d "$VENV_DIR" ]]; then
        log_warn "${VENV_DIR} が既に存在します。削除して再作成します"
        rm -rf "$VENV_DIR"
    fi

    $PYTHON_BIN -m venv "$VENV_DIR"
    log_ok "仮想環境作成: ${VENV_DIR}"

    # venv内バイナリへのパスを設定
    export PATH="${VENV_DIR}/bin:${PATH}"

    # pip・setuptools・wheel を最新化
    "${VENV_DIR}/bin/pip" install --upgrade pip setuptools wheel 2>&1 | tee -a "$LOG_FILE"
    log_ok "pip 最新化完了: $(${VENV_DIR}/bin/pip --version)"
}

# ── Step 3: PyTorch (nightly / cu128) インストール ────────────────────────────
install_pytorch() {
    log_step "Step 3: PyTorch nightly (CUDA 12.8 / cu128) をインストール"
    log_info "理由: Blackwell sm_120 は PyTorch stable wheels に含まれていないため nightly 必須"

    # PyTorch nightly (cu128)
    # --pre フラグで nightly ビルドを取得
    "${VENV_DIR}/bin/pip" install \
        --upgrade \
        --pre \
        torch \
        torchvision \
        torchaudio \
        --index-url https://download.pytorch.org/whl/nightly/cu128 \
        2>&1 | tee -a "$LOG_FILE"

    # インストール確認
    log_info "PyTorch インストール確認..."
    local torch_version
    torch_version=$("${VENV_DIR}/bin/python" -c "import torch; print(torch.__version__)" 2>&1)
    log_ok "PyTorch バージョン: ${torch_version}"

    # CUDA認識確認
    local cuda_available
    cuda_available=$("${VENV_DIR}/bin/python" -c "import torch; print(torch.cuda.is_available())" 2>&1)
    if [[ "$cuda_available" != "True" ]]; then
        log_error "PyTorchがCUDAを認識できません: ${cuda_available}"
        log_error "NVIDIAドライバと再起動を確認してください"
        exit 1
    fi
    log_ok "CUDA 認識: ${cuda_available}"

    # GPU名確認
    local gpu_name
    gpu_name=$("${VENV_DIR}/bin/python" -c "import torch; print(torch.cuda.get_device_name(0))" 2>&1)
    log_ok "検出GPU: ${gpu_name}"

    # Blackwell compute capability確認
    local compute_cap
    compute_cap=$("${VENV_DIR}/bin/python" -c \
        "import torch; p=torch.cuda.get_device_capability(0); print(f'{p[0]}.{p[1]}')" 2>&1)
    log_info "Compute Capability: ${compute_cap}"
    if [[ "$compute_cap" != "12.0" ]]; then
        log_warn "Compute Capability が 12.0 ではありません: ${compute_cap}"
        log_warn "RTX PRO 6000 Blackwell の場合は 12.0 が期待値です"
    fi

    # Triton（Blackwell対応版: >= 3.3.1）
    "${VENV_DIR}/bin/pip" install "triton>=3.3.1" 2>&1 | tee -a "$LOG_FILE"
    local triton_version
    triton_version=$("${VENV_DIR}/bin/pip" show triton 2>/dev/null | grep Version | awk '{print $2}')
    log_ok "Triton バージョン: ${triton_version}"
}

# ── Step 4: vLLM ソースビルド ─────────────────────────────────────────────────
build_vllm_from_source() {
    log_step "Step 4: vLLM をソースからビルド (sm_120 / Blackwell)"

    log_info "TORCH_CUDA_ARCH_LIST=${CUDA_ARCH} でビルドします"
    log_info "MAX_JOBS=${MAX_JOBS} (並列ビルドジョブ数)"
    log_warn "ビルドには 30〜60 分かかります"

    # ビルドディレクトリ準備
    if [[ -d "$VLLM_BUILD_DIR" ]]; then
        log_info "既存のビルドディレクトリを更新: ${VLLM_BUILD_DIR}"
        cd "$VLLM_BUILD_DIR"
        git fetch origin
        git checkout main
        git pull origin main
    else
        log_info "vLLM リポジトリをクローン: ${VLLM_BUILD_DIR}"
        git clone https://github.com/vllm-project/vllm.git "$VLLM_BUILD_DIR"
        cd "$VLLM_BUILD_DIR"
    fi

    local vllm_commit
    vllm_commit=$(git rev-parse --short HEAD)
    log_info "vLLM コミット: ${vllm_commit}"

    # ビルド環境変数
    export TORCH_CUDA_ARCH_LIST="${CUDA_ARCH}"
    export MAX_JOBS="${MAX_JOBS}"
    export VLLM_NCCL_SO_PATH=""         # NCCL自動検出
    export CUDA_HOME="/usr/local/cuda"
    # Blackwell FlashInfer対応
    export FLASHINFER_CUDA_ARCH_LIST="${CUDA_ARCH}f"

    # 既存 torch を流用してビルド時間を短縮
    if [[ -f "use_existing_torch.py" ]]; then
        log_info "既存 torch を流用 (use_existing_torch.py)"
        "${VENV_DIR}/bin/python" use_existing_torch.py 2>&1 | tee -a "$LOG_FILE"
    fi

    # ビルド依存パッケージ
    log_info "ビルド依存パッケージをインストール..."
    "${VENV_DIR}/bin/pip" install \
        -r requirements/build.txt \
        2>&1 | tee -a "$LOG_FILE"

    # コア依存パッケージ（vLLM実行時必要）
    "${VENV_DIR}/bin/pip" install \
        -r requirements/common.txt \
        2>&1 | tee -a "$LOG_FILE"

    # vLLM ビルド開始
    log_info "vLLM ビルド開始... (${vllm_commit})"
    log_info "開始時刻: $(date '+%H:%M:%S')"

    "${VENV_DIR}/bin/python" setup.py develop \
        2>&1 | tee -a "$LOG_FILE"

    log_info "終了時刻: $(date '+%H:%M:%S')"
    log_ok "vLLM ソースビルド完了"

    # バージョン確認
    local vllm_version
    vllm_version=$("${VENV_DIR}/bin/python" -c "import vllm; print(vllm.__version__)" 2>&1)
    log_ok "vLLM バージョン: ${vllm_version} (commit: ${vllm_commit})"
}

# ── Step 5: FlashInfer インストール ──────────────────────────────────────────
install_flashinfer() {
    log_step "Step 5: FlashInfer (Blackwell対応版) をインストール"
    log_info "FlashInfer: Attention計算の高速化ライブラリ（vLLMパフォーマンスに必須）"

    # FlashInfer の Blackwell 対応版インストール
    # 公式が sm_120 wheel をリリースしていない場合はソースビルド
    if "${VENV_DIR}/bin/pip" install \
        flashinfer-python \
        --find-links https://flashinfer.ai/whl/cu128/torch2.7/flashinfer-python/ \
        2>&1 | tee -a "$LOG_FILE"; then
        local fi_version
        fi_version=$("${VENV_DIR}/bin/pip" show flashinfer-python 2>/dev/null | grep Version | awk '{print $2}' || echo "unknown")
        log_ok "FlashInfer インストール完了: ${fi_version}"
    else
        log_warn "FlashInfer wheels が見つかりません。vLLMの --no-enable-flashinfer で代替します"
        log_warn "パフォーマンスへの影響: Prefillが約10〜20%低下する可能性があります"
    fi
}

# ── Step 6: サービス用ラッパースクリプト生成 ─────────────────────────────────
create_activation_helpers() {
    log_step "Step 6: activate ヘルパーとサービスファイルを生成"

    # venvアクティベート用の便利スクリプト
    cat > /usr/local/bin/vllm-activate << EOF
#!/usr/bin/env bash
# vLLM仮想環境をアクティベート
# 使用方法: source /usr/local/bin/vllm-activate
# または:   . /usr/local/bin/vllm-activate

export VIRTUAL_ENV="${VENV_DIR}"
export PATH="${VENV_DIR}/bin:\${PATH}"
export CUDA_HOME="/usr/local/cuda"
export LD_LIBRARY_PATH="/usr/local/cuda/lib64:\${LD_LIBRARY_PATH:-}"
export TORCH_CUDA_ARCH_LIST="${CUDA_ARCH}"
export FLASHINFER_CUDA_ARCH_LIST="${CUDA_ARCH}f"

# Blackwell最適化フラグ
export VLLM_WORKER_MULTIPROC_METHOD="spawn"
export NCCL_P2P_DISABLE=0                    # NVLinkなし環境では 1 に変更

echo "vLLM環境をアクティベートしました: ${VENV_DIR}"
echo "Python: \$(which python)"
echo "vLLM:   \$(python -c 'import vllm; print(vllm.__version__)' 2>/dev/null || echo 'not found')"
EOF
    chmod +x /usr/local/bin/vllm-activate
    log_ok "アクティベートスクリプト: /usr/local/bin/vllm-activate"

    # mdlユーザーの .bashrc にエイリアス追加
    local bashrc="/home/mdl/.bashrc"
    if [[ -f "$bashrc" ]] && ! grep -q "vllm-activate" "$bashrc"; then
        cat >> "$bashrc" << 'EOF'

# vLLM 仮想環境 (cocoro-llm-server)
alias vllm-env="source /usr/local/bin/vllm-activate"
EOF
        log_ok ".bashrc にエイリアス追加: alias vllm-env='source /usr/local/bin/vllm-activate'"
    fi
}

# ── Step 7: 動作確認 ───────────────────────────────────────────────────────────
verify_installation() {
    log_step "Step 7: インストール動作確認"

    echo "" | tee -a "$LOG_FILE"
    echo "═══════════════════════════════════════════════" | tee -a "$LOG_FILE"

    # GPU名
    log_info "GPU 名称:"
    "${VENV_DIR}/bin/python" -c "
import torch
print(f'  GPU: {torch.cuda.get_device_name(0)}')
cap = torch.cuda.get_device_capability(0)
print(f'  Compute Capability: {cap[0]}.{cap[1]}')
vram = torch.cuda.get_device_properties(0).total_memory / 1024**3
print(f'  VRAM: {vram:.1f} GB')
print(f'  CUDA: {torch.version.cuda}')
" 2>&1 | tee -a "$LOG_FILE"

    # vLLMバージョン
    log_info "vLLM バージョン:"
    "${VENV_DIR}/bin/python" -m vllm.entrypoints.openai.api_server --version \
        2>&1 | tee -a "$LOG_FILE" || \
    "${VENV_DIR}/bin/python" -c "import vllm; print(f'  vLLM: {vllm.__version__}')" \
        2>&1 | tee -a "$LOG_FILE"

    # インストール済みパッケージ一覧
    log_info "主要パッケージ バージョン:"
    "${VENV_DIR}/bin/pip" show \
        torch triton vllm \
        2>/dev/null | grep -E "^(Name|Version)" \
        | paste - - \
        | awk '{printf "  %-20s %s\n", $2, $4}' \
        | tee -a "$LOG_FILE" || true

    echo "═══════════════════════════════════════════════" | tee -a "$LOG_FILE"
    echo "" | tee -a "$LOG_FILE"
    log_ok "動作確認完了"
}

# ── 完了メッセージ ────────────────────────────────────────────────────────────
print_summary() {
    echo ""
    echo -e "${GREEN}╔═════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║   vLLM Blackwell セットアップ完了！                  ║${NC}"
    echo -e "${GREEN}╚═════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${YELLOW}【vLLM 環境のアクティベート】${NC}"
    echo "  # ターミナルで使う場合:"
    echo "  source /usr/local/bin/vllm-activate"
    echo ""
    echo "  # .bashrc エイリアス:"
    echo "  vllm-env"
    echo ""
    echo -e "${YELLOW}【次のステップ】${NC}"
    echo ""
    echo "  1️⃣  start_primary.sh の実行テスト:"
    echo "      source /usr/local/bin/vllm-activate"
    echo "      bash vllm/start_primary.sh"
    echo ""
    echo "  2️⃣  期待される動作確認:"
    echo "      curl http://localhost:8080/health"
    echo ""
    echo "  3️⃣  LiteLLM Gateway を起動:"
    echo "      docker compose -f docker/docker-compose.yml up -d litellm"
    echo ""
    echo -e "${YELLOW}【ログ】${NC}"
    echo "  ${LOG_FILE}"
    echo ""
    echo -e "${YELLOW}【vLLM on Blackwell 注意事項】${NC}"
    echo "  - TORCH_CUDA_ARCH_LIST=\"12.0\" が設定済み"
    echo "  - PyTorch nightly (cu128) を使用"
    echo "  - Triton >= 3.3.1 が必要 (インストール済み)"
    echo "  - 問題発生時: --enforce-eager フラグで CUDA Graph を無効化して起動"
    echo ""

    echo "Setup completed at: $(date '+%Y-%m-%d %H:%M:%S')" >> "$LOG_FILE"
}

# ── メイン処理 ────────────────────────────────────────────────────────────────
main() {
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║  cocoro-llm-server vLLM Blackwell ソースビルド           ║${NC}"
    echo -e "${CYAN}║  GPU: RTX PRO 6000 (sm_120) / CUDA: 12.8 / venv: /opt   ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""

    setup_logging
    check_prerequisites     # Step 0
    install_build_deps      # Step 1
    create_venv             # Step 2
    install_pytorch         # Step 3
    build_vllm_from_source  # Step 4
    install_flashinfer      # Step 5
    create_activation_helpers # Step 6
    verify_installation     # Step 7
    print_summary
}

main "$@"
