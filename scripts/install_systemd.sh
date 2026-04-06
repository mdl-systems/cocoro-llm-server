#!/usr/bin/env bash
# =============================================================================
# scripts/install_systemd.sh
# vllm-primary.service / vllm-secondary.service を systemd に登録するスクリプト
#
# 実行方法:
#   sudo bash scripts/install_systemd.sh
#
# 前提:
#   - /opt/cocoro-llm-server に本リポジトリが配置済み
#   - /opt/vllm-env に vLLM 仮想環境が存在する
#   - .env が /opt/cocoro-llm-server/.env に存在する
# =============================================================================

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SYSTEMD_DIR="/etc/systemd/system"
INSTALL_DIR="/opt/cocoro-llm-server"
LOG_DIR="/var/log/cocoro-llm"

log() { echo "[$(date '+%H:%M:%S')] $*"; }
die() { echo "[ERROR] $*" >&2; exit 1; }

# root確認
[[ "${EUID}" -eq 0 ]] || die "このスクリプトは root で実行してください: sudo bash $0"

log "=== vLLM systemd サービス インストール ==="

# ---- ログディレクトリ作成 ----
log "ログディレクトリを作成: ${LOG_DIR}"
mkdir -p "${LOG_DIR}"
chmod 755 "${LOG_DIR}"

# ---- リポジトリをインストールパスにリンク ----
# 開発環境では symlink で対応（本番は rsync や git clone を推奨）
if [[ "${REPO_DIR}" != "${INSTALL_DIR}" ]]; then
    if [[ -L "${INSTALL_DIR}" ]]; then
        log "既存のシンボリックリンクを更新: ${INSTALL_DIR} -> ${REPO_DIR}"
        ln -sfn "${REPO_DIR}" "${INSTALL_DIR}"
    elif [[ ! -e "${INSTALL_DIR}" ]]; then
        log "シンボリックリンクを作成: ${INSTALL_DIR} -> ${REPO_DIR}"
        ln -s "${REPO_DIR}" "${INSTALL_DIR}"
    else
        log "WARNING: ${INSTALL_DIR} はディレクトリとして既に存在します。スキップします。"
        log "         手動で確認してください: ls -la ${INSTALL_DIR}"
    fi
fi

# ---- スクリプトの実行権限付与 ----
log "起動スクリプトに実行権限を付与..."
chmod +x "${INSTALL_DIR}/vllm/start_primary.sh"
chmod +x "${INSTALL_DIR}/vllm/start_secondary.sh"

# ---- サービスファイルをコピー ----
log "systemd サービスファイルをコピー..."
for svc in vllm-primary.service vllm-secondary.service; do
    src="${REPO_DIR}/systemd/${svc}"
    dst="${SYSTEMD_DIR}/${svc}"
    [[ -f "${src}" ]] || die "サービスファイルが見つかりません: ${src}"
    cp "${src}" "${dst}"
    chmod 644 "${dst}"
    log "  コピー完了: ${dst}"
done

# ---- systemd リロード & 有効化 ----
log "systemd デーモンをリロード..."
systemctl daemon-reload

log "サービスを有効化 (boot時自動起動)..."
systemctl enable vllm-primary.service
systemctl enable vllm-secondary.service

log ""
log "=== インストール完了 ==="
log ""
log "次のコマンドで起動できます:"
log "  sudo systemctl start vllm-primary"
log "  sudo systemctl start vllm-secondary  # Primary起動後に実行"
log ""
log "ログ確認:"
log "  sudo journalctl -u vllm-primary -f"
log "  sudo journalctl -u vllm-secondary -f"
log "  tail -f ${LOG_DIR}/vllm-primary.log"
log "  tail -f ${LOG_DIR}/vllm-secondary.log"
log ""
log "ステータス確認:"
log "  sudo systemctl status vllm-primary vllm-secondary"
