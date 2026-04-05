#!/usr/bin/env bash
# =============================================================================
# scripts/setup_nvidia.sh
# NVIDIAドライバ + CUDA 12.8 セットアップスクリプト
#
# 対象環境:
#   OS  : Debian 13 Trixie
#   GPU : RTX PRO 6000 Blackwell (GB202 / sm_120相当)
#   User: mdl (sudo権限あり)
#
# ⚠️  重要: CUDA 12.4 ではBlackwellアーキテクチャは動作しない
#           Blackwell (sm_120) の最小要件は CUDA 12.8
#           vLLM on Blackwell: https://docs.vllm.ai/en/latest/getting_started/installation.html
#
# 実行方法:
#   chmod +x scripts/setup_nvidia.sh
#   sudo bash scripts/setup_nvidia.sh
#
# 再起動が必要:
#   スクリプト完了後に "sudo reboot" を実行してください
#   再起動後に nvidia-smi で確認
# =============================================================================

set -euo pipefail

# ── カラー出力 ────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info()  { echo -e "${BLUE}[INFO]${NC}  $*"; }
log_ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# ── 前提条件チェック ───────────────────────────────────────────────────────────
check_prerequisites() {
    log_info "前提条件を確認しています..."

    # root権限チェック
    if [[ $EUID -ne 0 ]]; then
        log_error "このスクリプトはroot権限で実行する必要があります"
        log_error "実行方法: sudo bash scripts/setup_nvidia.sh"
        exit 1
    fi

    # Debianチェック
    if ! grep -qi "debian" /etc/os-release; then
        log_error "このスクリプトはDebian専用です"
        exit 1
    fi

    local distro_version
    distro_version=$(grep "VERSION_ID" /etc/os-release | cut -d'"' -f2)
    log_info "OS: Debian ${distro_version}"

    # アーキテクチャチェック
    local arch
    arch=$(dpkg --print-architecture)
    if [[ "$arch" != "amd64" ]]; then
        log_error "x86_64 (amd64) のみサポートしています。現在: ${arch}"
        exit 1
    fi

    # ネット接続チェック
    if ! curl -s --max-time 5 https://developer.download.nvidia.com > /dev/null 2>&1; then
        log_error "NVIDIAサーバーに接続できません。ネットワーク設定を確認してください"
        exit 1
    fi

    # ディスク空き容量チェック（最低8GB必要）
    local available_gb
    available_gb=$(df / --output=avail -BG | tail -1 | tr -d 'G')
    if [[ "$available_gb" -lt 8 ]]; then
        log_error "ディスク空き容量が不足しています: ${available_gb}GB (最低8GB必要)"
        exit 1
    fi
    log_info "ディスク空き容量: ${available_gb}GB ✓"

    log_ok "前提条件チェック完了"
}

# ── 既存NVIDIAドライバの削除 ──────────────────────────────────────────────────
remove_existing_nvidia() {
    log_info "既存のNVIDIAパッケージを確認しています..."

    local nvidia_pkgs
    nvidia_pkgs=$(dpkg -l | grep -i nvidia | awk '{print $2}' || true)

    if [[ -n "$nvidia_pkgs" ]]; then
        log_warn "既存のNVIDIAパッケージが見つかりました。削除します:"
        echo "$nvidia_pkgs"
        # shellcheck disable=SC2086
        apt-get remove --purge -y $nvidia_pkgs || true
        apt-get autoremove -y || true
        log_ok "既存パッケージを削除しました"
    else
        log_info "既存NVIDIAパッケージなし"
    fi
}

# ── Step 1: nouveau無効化 ─────────────────────────────────────────────────────
disable_nouveau() {
    log_info "Step 1: nouveauドライバを無効化しています..."

    local blacklist_file="/etc/modprobe.d/blacklist-nouveau.conf"

    cat > "$blacklist_file" << 'EOF'
# nouveauドライバを無効化（NVIDIA専用ドライバとの競合防止）
# cocoro-llm-server セットアップスクリプトにより生成
blacklist nouveau
options nouveau modeset=0
EOF

    log_ok "blacklistファイル作成: ${blacklist_file}"

    # initramfsを更新してnouveauを確実に排除
    update-initramfs -u -k all
    log_ok "initramfs更新完了"

    # 現在nouveauがロードされているか確認
    if lsmod | grep -q nouveau; then
        log_warn "nouveauが現在ロード中です。再起動後に無効化されます"
    else
        log_ok "nouveauは未ロード（または既に無効化済み）"
    fi
}

# ── Step 2: 依存パッケージのインストール ──────────────────────────────────────
install_dependencies() {
    log_info "Step 2: 依存パッケージをインストールしています..."

    apt-get update -y

    apt-get install -y \
        build-essential \
        dkms \
        linux-headers-"$(uname -r)" \
        curl \
        wget \
        gnupg2 \
        apt-transport-https \
        ca-certificates \
        pkg-config

    log_ok "依存パッケージのインストール完了"
}

# ── Step 3: NVIDIAリポジトリ追加（cuda-keyring使用）─────────────────────────
add_nvidia_repo() {
    log_info "Step 3: NVIDIAリポジトリを追加しています..."

    local keyring_pkg="cuda-keyring_1.1-1_all.deb"
    local keyring_url="https://developer.download.nvidia.com/compute/cuda/repos/debian12/x86_64/${keyring_pkg}"
    local tmp_dir
    tmp_dir=$(mktemp -d)

    # cuda-keyring ダウンロード
    log_info "cuda-keyringをダウンロード中: ${keyring_url}"
    if ! wget -q --show-progress -O "${tmp_dir}/${keyring_pkg}" "$keyring_url"; then
        log_error "cuda-keyringのダウンロードに失敗しました"
        log_error "URL: ${keyring_url}"
        rm -rf "$tmp_dir"
        exit 1
    fi

    # インストール
    dpkg -i "${tmp_dir}/${keyring_pkg}"
    rm -rf "$tmp_dir"

    # Debian 12リポジトリはDebian 13 (Trixie)でも互換性あり
    # APTピンニングで優先度設定（安定版ドライバのみ取得）
    cat > /etc/apt/preferences.d/cuda-repository-pin-600 << 'EOF'
Package: nsight-compute
Pin: origin developer.download.nvidia.com
Pin-Priority: 100

Package: nsight-systems
Pin: origin developer.download.nvidia.com
Pin-Priority: 100

Package: *
Pin: origin developer.download.nvidia.com
Pin-Priority: 600
EOF

    # ── Debian 13 (Trixie) SHA1互換性ワークアラウンド ─────────────────────────
    # sqv (Sequoia PGP) が 2026-02-01以降 SHA1署名を拒否するため
    # NVIDIAリポジトリに対してのみ WeakSignatures を許可する
    cat > /etc/apt/apt.conf.d/99nvidia-weak-sig << 'APT_CONF'
# NVIDIA CUDA リポジトリの SHA1署名を許可 (Debian 13 Trixie sqv対策)
# 参照: https://bugs.debian.org/cgi-bin/bugreport.cgi?bug=1054941
Acquire::https::developer.download.nvidia.com::AllowWeakSignatures "true";
APT_CONF
    log_ok "SHA1署名ワークアラウンド設定: /etc/apt/apt.conf.d/99nvidia-weak-sig"

    apt-get update -y
    log_ok "NVIDIAリポジトリの追加完了"
}

# ── Step 4: CUDA 12.8 + NVIDIAドライバのインストール ─────────────────────────
install_cuda_and_driver() {
    log_info "Step 4: CUDA 12.8 と NVIDIAドライバをインストールしています..."
    log_info "⚠️  注意: Blackwell (sm_120) には CUDA 12.8 以上が必須です（12.4では不可）"

    # 利用可能な最新570系ドライバを確認
    log_info "利用可能なNVIDIAドライバを確認中..."
    apt-cache search nvidia-driver | grep "^nvidia-driver-[0-9]" | sort -t'-' -k3 -n | tail -5 || true

    # cuda-toolkit-12-8: CUDA本体（コンパイラ・ライブラリ）
    # nvidia-open-kernel-dkms: Blackwell推奨のオープンカーネルモジュール
    # nvidia-cuda-toolkit 含む cuda-12-8 メタパッケージ
    apt-get install -y \
        cuda-toolkit-12-8 \
        nvidia-open-kernel-dkms \
        nvidia-fabricmanager-570 \
        libcuda1 \
        cuda-drivers

    log_ok "CUDA 12.8 + NVIDIAドライバのインストール完了"
}

# ── Step 5: 環境変数設定 ─────────────────────────────────────────────────────
setup_environment() {
    log_info "Step 5: CUDA環境変数を設定しています..."

    # /etc/profile.d/cuda.sh — 全ユーザーに適用
    cat > /etc/profile.d/cuda.sh << 'EOF'
# CUDA 12.8 環境変数
# cocoro-llm-server セットアップスクリプトにより生成

export CUDA_HOME=/usr/local/cuda-12.8
export PATH="${CUDA_HOME}/bin:${PATH}"
export LD_LIBRARY_PATH="${CUDA_HOME}/lib64:${LD_LIBRARY_PATH:-}"

# Blackwell (sm_120) vLLM用コンパイルターゲット
# vLLMをソースビルドする際に使用
export TORCH_CUDA_ARCH_LIST="12.0"

# nvidia-smiをデフォルトで使用可能にする
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH}"
EOF

    chmod 644 /etc/profile.d/cuda.sh
    log_ok "環境変数設定ファイル作成: /etc/profile.d/cuda.sh"

    # mdlユーザーの .bashrc にも追記（sudoなしで使えるように）
    local target_user="mdl"
    local bashrc="/home/${target_user}/.bashrc"

    if [[ -f "$bashrc" ]]; then
        # 重複追記防止
        if ! grep -q "CUDA_HOME" "$bashrc"; then
            cat >> "$bashrc" << 'EOF'

# CUDA 12.8 (cocoro-llm-server)
export CUDA_HOME=/usr/local/cuda-12.8
export PATH="${CUDA_HOME}/bin:${PATH}"
export LD_LIBRARY_PATH="${CUDA_HOME}/lib64:${LD_LIBRARY_PATH:-}"
export TORCH_CUDA_ARCH_LIST="12.0"
EOF
            log_ok "${bashrc} に環境変数を追記しました"
        else
            log_info "${bashrc} にはすでにCUDA設定があります（スキップ）"
        fi
    fi
}

# ── Step 6: systemdサービス設定（再起動後の自動ロード保証）──────────────────
setup_autoload() {
    log_info "Step 6: 再起動後の自動ロードを設定しています..."

    # nvidia-fabricmanagerサービスの有効化（マルチGPU/NVLink環境向けだが単体でも有効）
    if systemctl list-unit-files | grep -q nvidia-fabricmanager; then
        systemctl enable nvidia-fabricmanager
        log_ok "nvidia-fabricmanager: 自動起動有効"
    fi

    # nvidia永続化デーモン（低レイテンシ初期化のため推奨）
    if systemctl list-unit-files | grep -q nvidia-persistenced; then
        systemctl enable nvidia-persistenced
        log_ok "nvidia-persistenced: 自動起動有効"
    fi

    # DKMSモジュールの確認
    log_info "DKMSモジュール状態:"
    dkms status | grep nvidia || log_warn "DKMSモジュールがまだ登録されていません（再起動後に自動ビルドされます）"
}

# ── Step 7: インストール確認 ─────────────────────────────────────────────────
verify_installation() {
    log_info "Step 7: インストールを確認しています..."

    echo ""
    echo "═══════════════════════════════════════"
    log_info "インストール済みCUDAバージョン:"
    if [[ -f /usr/local/cuda/bin/nvcc ]]; then
        /usr/local/cuda/bin/nvcc --version
        log_ok "nvcc: インストール済み"
    else
        log_warn "nvcc がまだPATHに見つかりません（source /etc/profile.d/cuda.sh 後に確認）"
    fi

    echo ""
    log_info "NVIDIAドライバ確認（再起動前のため失敗する場合があります）:"
    if command -v nvidia-smi &>/dev/null; then
        nvidia-smi \
            --query-gpu=name,driver_version,memory.total,compute_cap \
            --format=csv,noheader,nounits
        log_ok "nvidia-smi: 動作確認済み"
    else
        log_warn "nvidia-smi が現在利用できません"
        log_warn "→ 再起動後に再確認してください: nvidia-smi"
    fi

    echo "═══════════════════════════════════════"
    echo ""
}

# ── 完了メッセージ ────────────────────────────────────────────────────────────
print_summary() {
    echo ""
    echo -e "${GREEN}╔═══════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║   セットアップ完了！                               ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${YELLOW}【必須】次のステップ:${NC}"
    echo ""
    echo "  1️⃣  再起動:"
    echo "      sudo reboot"
    echo ""
    echo "  2️⃣  再起動後に確認:"
    echo "      nvidia-smi"
    echo "      nvcc --version"
    echo "      nvidia-smi --query-gpu=name,driver_version,memory.total,compute_cap --format=csv"
    echo ""
    echo "  3️⃣  期待される出力例:"
    echo "      GPU: NVIDIA RTX PRO 6000 Blackwell"
    echo "      Driver: 570.x以上"
    echo "      VRAM: 98304 MiB (96GB)"
    echo "      Compute: 12.0"
    echo ""
    echo "  4️⃣  確認後、次のセットアップへ:"
    echo "      bash scripts/setup_vllm.sh"
    echo ""
    echo -e "${YELLOW}【注意】vLLM on Blackwell:${NC}"
    echo "  - CUDA 12.8 インストール済み ✓"
    echo "  - TORCH_CUDA_ARCH_LIST=\"12.0\" 設定済み ✓"
    echo "  - vLLMはソースビルドが必要 (scripts/setup_vllm.sh で対応予定)"
    echo ""
}

# ── メイン処理 ────────────────────────────────────────────────────────────────
main() {
    echo ""
    echo -e "${BLUE}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║  cocoro-llm-server NVIDIA + CUDA 12.8 セットアップ     ║${NC}"
    echo -e "${BLUE}║  GPU: RTX PRO 6000 Blackwell / OS: Debian 13 Trixie    ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════╝${NC}"
    echo ""

    check_prerequisites
    remove_existing_nvidia
    disable_nouveau        # Step 1
    install_dependencies   # Step 2
    add_nvidia_repo        # Step 3
    install_cuda_and_driver # Step 4
    setup_environment      # Step 5
    setup_autoload         # Step 6
    verify_installation    # Step 7
    print_summary
}

main "$@"
