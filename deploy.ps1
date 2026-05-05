# =============================================================================
# deploy.ps1 — cocoro-llm-server
# Windows → リモートサーバ (192.168.50.112) ファイル同期スクリプト
#
# 前提:
#   - WSL2 がインストール済み
#   - SSH鍵が ~/.ssh/id_rsa（またはid_ed25519）に設定済み
#   - リモートに rsync がインストール済み
#
# 使用方法:
#   .\deploy.ps1                   # 通常同期
#   .\deploy.ps1 -DryRun           # 変更内容をプレビューのみ（実際には同期しない）
#   .\deploy.ps1 -Restart          # 同期後にDockerサービスを再起動
# =============================================================================

param(
    [switch]$DryRun,
    [switch]$Restart,
    [string]$RemoteUser = "abtr1094",
    [string]$RemoteHost = "192.168.50.112",
    [string]$RemotePath = "~/cocoro-llm-server"
)

$ErrorActionPreference = "Stop"

# カラー出力
function Write-Info  { param($msg) Write-Host "[INFO ] $msg" -ForegroundColor Cyan }
function Write-Ok    { param($msg) Write-Host "[OK   ] $msg" -ForegroundColor Green }
function Write-Warn  { param($msg) Write-Host "[WARN ] $msg" -ForegroundColor Yellow }
function Write-Err   { param($msg) Write-Host "[ERROR] $msg" -ForegroundColor Red }

Write-Info "=== cocoro-llm-server デプロイスクリプト ==="
Write-Info "送信先: ${RemoteUser}@${RemoteHost}:${RemotePath}"

# WSL確認
try {
    $wslCheck = wsl --status 2>&1
    Write-Ok "WSL2 確認済み"
} catch {
    Write-Err "WSL2が見つかりません。WSL2をインストールしてください"
    exit 1
}

# ローカルパス（このスクリプトのディレクトリ）
$LocalPath = $PSScriptRoot
if (-not $LocalPath) {
    $LocalPath = Get-Location
}

# WSL形式のパスに変換
$WslLocalPath = wsl wslpath -u "$LocalPath"
$WslLocalPath = $WslLocalPath.Trim()

Write-Info "ローカルパス: $LocalPath"
Write-Info "WSLパス: $WslLocalPath"

# 除外パターン
$Excludes = @(
    "--exclude='.env'"
    "--exclude='.git/'"
    "--exclude='hf_cache/'"
    "--exclude='__pycache__/'"
    "--exclude='*.pyc'"
    "--exclude='*.log'"
    "--exclude='.DS_Store'"
    "--exclude='node_modules/'"
)

$ExcludeArgs = $Excludes -join " "

# rsyncオプション
$RsyncOpts = "-avz --progress --delete"
if ($DryRun) {
    $RsyncOpts += " --dry-run"
    Write-Warn "DRYRUNモード: 実際のファイル転送は行いません"
}

$RsyncCmd = "rsync $RsyncOpts $ExcludeArgs $WslLocalPath/ ${RemoteUser}@${RemoteHost}:${RemotePath}/"

Write-Info "実行コマンド: $RsyncCmd"
Write-Info "同期開始..."

try {
    wsl bash -c $RsyncCmd
    Write-Ok "ファイル同期完了"
} catch {
    Write-Err "同期失敗: $_"
    exit 1
}

# Docker再起動（--Restartフラグ時）
if ($Restart -and -not $DryRun) {
    Write-Info "Dockerサービスを再起動します..."
    $SshCmd = "ssh ${RemoteUser}@${RemoteHost} 'cd ${RemotePath} && docker compose down && docker compose up -d'"
    try {
        wsl bash -c $SshCmd
        Write-Ok "Dockerサービス再起動完了"
    } catch {
        Write-Err "Docker再起動失敗: $_"
        Write-Info "手動で再起動してください: ssh ${RemoteUser}@${RemoteHost}"
        Write-Info "  cd ${RemotePath} && docker compose down && docker compose up -d"
        exit 1
    }
}

Write-Ok "=== デプロイ完了 ==="
if (-not $DryRun) {
    Write-Info "Open WebUI: http://${RemoteHost}:3000"
    Write-Info "LiteLLM API: http://${RemoteHost}:4000"
    Write-Info "ヘルスチェック: curl http://${RemoteHost}:4000/health/liveliness"
}
