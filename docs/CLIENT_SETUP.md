# =============================================================================
# CLIENT_SETUP.md — cocoro-llm-server クライアントセットアップガイド
# 更新日: 2026-05-06
# =============================================================================

# CLIENT_SETUP.md — cocoro-llm-server クライアントセットアップガイド

> cocoro-llm-server（LLM推論サーバー）を使用するためのクライアントPCセットアップ手順です。
> Windows（WSL含む）とLinuxの両方をサポートします。

---

## 目次

1. [前提条件](#前提条件)
2. [リポジトリクローン](#リポジトリクローン)
3. [opencode.jsonのセットアップ](#opencodejsonのセットアップ)
4. [接続確認](#接続確認)
5. [Windows/WSLとLinuxの違い](#windowswslとlinuxの違い)
6. [自動セットアップスクリプト](#自動セットアップスクリプト)
7. [トラブルシューティング](#トラブルシューティング)

---

## 前提条件

### 共通要件

| 品目 | 最小バージョン | 用途 |
|------|---------------|------|
| Node.js | v18+ | opencode CLI実行 |
| Git | v2.30+ | リポジトリクローン |
| npm | v9+ | 依存関係インストール |

### サーバー接続要件

- サーバーPC（192.168.50.112）とのネットワーク接続
- LiteLLM APIポート（4000）へのアクセス可能
- LITELLM_MASTER_KEY（後述）

---

## リポジトリクローン

### Windows (PowerShell)

```powershell
# GitHubからリポジトリをクローン
git clone https://github.com/mdl-systems/cocoro-llm-server.git
cd cocoro-llm-server
```

### Linux / WSL

```bash
# GitHubからリポジトリをクローン
git clone https://github.com/mdl-systems/cocoro-llm-server.git
cd cocoro-llm-server
```

---

## opencode.jsonのセットアップ

### 手動セットアップ手順

#### 1. サンプルファイルをコピー

```bash
# Windows (PowerShell)
cp opencode.json.sample opencode.json

# Linux / WSL
cp opencode.json.sample opencode.json
```

#### 2. 設定ファイルを編集

```bash
# Windows (PowerShell)
notepad opencode.json

# Linux / WSL
nano opencode.json
# または
vim opencode.json
```

#### 3. 必須項目の設定

`opencode.json` を以下のように編集します：

```json
{
  "baseURL": "http://192.168.50.112:4000/v1",
  "apiKey": "YOUR_API_KEY_HERE",
  "model": "smart-coder",
  "maxRetries": 3,
  "timeout": 60000
}
```

**変更点**：

- ✅ `baseURL`: 変更不要（サーバーのLiteLLMアドレス）
- ❌ `apiKey`: **必ず実際のAPIキーに置き換える**
  - サーバー側の `.env` ファイルで設定した `LITELLM_MASTER_KEY` を使用
  - 例: `"apiKey": "sk-1234567890abcdef"`

#### 4. セキュリティ注意事項

⚠️ **絶対にやってはいけないこと**：

- ❌ `opencode.json` を git にコミットしない
- ❌ GitHub に公開しない
- ❌ チャット履歴にAPIキーを貼り付けない

✅ **推奨手順**：

1. `opencode.json` は `.gitignore` に追加済み
2. APIキーは `.env` ファイルで管理（後述）

---

## opencode.jsonの読み込み方法

### 方法1: 直接設定（シンプル）

```json
{
  "apiKey": "sk-yoursupersecretkeyhere"
}
```

### 方法2: 環境変数経由（推奨）

環境変数を読み込むために、以下のように `.env` ファイルを作成：

**`.env` ファイル（`opencode.json` と同じ場所）:**

```env
LITELLM_API_KEY=sk-your-actual-api-key-here
```

**`opencode.json`:**

```json
{
  "baseURL": "http://192.168.50.112:4000/v1",
  "apiKey": "${LITELLM_API_KEY}",
  "model": "smart-coder"
}
```

> Note: 環境変数経由の読み込みは、opencode CLIが対応している場合のみ有効です。未対応の場合は直接設定してください。

---

## 接続確認

### 1. vLLM APIのヘルスチェック

```bash
# Windows (PowerShell)
curl http://192.168.50.112:4000/health/liveliness

# Linux / WSL
curl http://192.168.50.112:4000/health/liveliness
```

**期待されるレスポンス:**

```json
{"status":"healthy"}
```

### 2. LiteLLM APIによる推論テスト

```bash
# Windows (PowerShell)
curl http://192.168.50.112:4000/v1/chat/completions `
  -H "Authorization: Bearer YOUR_API_KEY_HERE" `
  -H "Content-Type: application/json" `
  -d '{"model":"qwen3-coder","messages":[{"role":"user","content":"こんにちは"}]}'

# Linux / WSL
curl http://192.168.50.112:4000/v1/chat/completions \
  -H "Authorization: Bearer YOUR_API_KEY_HERE" \
  -H "Content-Type: application/json" \
  -d '{"model":"qwen3-coder","messages":[{"role":"user","content":"こんにちは"}]}'
```

**期待されるレスポンス（一部省略）:**

```json
{
  "id": "chatcmpl-xxx",
  "object": "chat.completion",
  ".choices": [{
    "message": {
      "role": "assistant",
      "content": "こんにちは！有什么可以帮您的？"
    }
  }]
}
```

### 3. opencode CLIのテスト（クライアント側）

```bash
# opencode CLIがインストールされている前提
opencode --version
```

---

## Windows/WSLとLinuxの違い

### Windows (PowerShell) の特徴

| 項目 | 内容 |
|------|------|
| `curl` コマンド | `curl` はエイリアス（Invoke-WebRequest） |
| クォート | 二重引用符 `"` を使用 |
| 改行コード | CRLF (`\r\n`) |
| 隠しファイル | `hidden` 属性で表示 |

**例（PowerShell）:**

```powershell
# APIテスト（PowerShell）
curl http://192.168.50.112:4000/health/liveliness `
  -Method GET `
  -Headers @{"Authorization"="Bearer YOUR_API_KEY_HERE"}
```

### Linux / WSL の特徴

| 項目 | 内容 |
|------|------|
| `curl` コマンド | `curl`（本物） |
| クォート | 複数の引用符が可能（`'` と `"`） |
| 改行コード | LF (`\n`) |
| 隠しファイル | `.`で始まる |

**例（Bash）:**

```bash
# APIテスト（Bash）
curl http://192.168.50.112:4000/health/liveliness \
  -H "Authorization: Bearer YOUR_API_KEY_HERE"
```

### WSL特有の設定

WSLからWindowsサーバーへ接続する場合:

```bash
# /etc/wsl.conf でDNSをWindowsにフォールバック
[network]
generateResolvConf = false

# /etc/resolv.conf に追加
nameserver 8.8.8.8
nameserver 192.168.50.1  # WindowsホストのIP
```

**WindowsホストのIPを固定する（任意）:**

PowerShellで実行（管理者権限不要）:

```powershell
# Windows側で実行
netsh interface ipv4 show addresses
```

---

## 自動セットアップスクリプト

### スクリプト名: `setup-client.ps1` / `setup-client.sh`

両方のOSで同じ機能を提供するスクリプトです。

#### 機能

1. `opencode.json.sample` を `opencode.json` にコピー
2. ユーザーにAPIキーを入力させる
3. 設定ファイルを更新
4. 接続テストを実行

### PowerShell版（Windows）

**`./scripts/setup-client.ps1`:**

```powershell
# =============================================================================
# setup-client.ps1 — cocoro-llm-server クライアント自動セットアップ
# =============================================================================

Write-Host "🚀 cocoro-llm-server クライアントセットアップ" -ForegroundColor Cyan

# APIキー入力
$apiKey = Read-Host -Prompt "Enter your LITELLM_MASTER_KEY"
if ([string]::IsNullOrWhiteSpace($apiKey)) {
    Write-Host "❌ API key is required" -ForegroundColor Red
    exit 1
}

# 設定ファイルコピー
Write-Host "📋 Copying opencode.json.sample to opencode.json..." -ForegroundColor Yellow
Copy-Item "opencode.json.sample" "opencode.json" -Force

# APIキー置換
$content = Get-Content "opencode.json" -Raw
$content = $content -replace '"YOUR_API_KEY_HERE"', "`"$apiKey`""
Set-Content "opencode.json" $content

Write-Host "✅ opencode.json created successfully" -ForegroundColor Green

# 接続テスト
Write-Host "🔍 Testing connection..." -ForegroundColor Yellow
try {
    $response =Invoke-RestMethod -Uri "http://192.168.50.112:4000/health/liveliness" -Method GET
    if ($response.status -eq "healthy") {
        Write-Host "✅ Connection successful!" -ForegroundColor Green
    } else {
        Write-Host "❌ Connection failed: $($response.status)" -ForegroundColor Red
        exit 1
    }
} catch {
    Write-Host "❌ Connection failed: $_" -ForegroundColor Red
    exit 1
}

Write-Host "🎉 Setup completed!" -ForegroundColor Green
Write-Host "Next: Run 'opencode --help' to see available commands" -ForegroundColor Cyan
```

**使用方法（PowerShell）:**

```powershell
# 実行ポリシーを設定（初回のみ）
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser

# スクリプト実行
.\scripts\setup-client.ps1
```

### Bash版（Linux / WSL）

**`./scripts/setup-client.sh`:**

```bash
#!/bin/bash
# =============================================================================
# setup-client.sh — cocoro-llm-server クライアント自動セットアップ
# =============================================================================

set -e

echo "🚀 cocoro-llm-server クライアントセットアップ"

# APIキー入力
read -p "Enter your LITELLM_MASTER_KEY: " API_KEY
if [ -z "$API_KEY" ]; then
    echo "❌ API key is required" >&2
    exit 1
fi

# 設定ファイルコピー
echo "📋 Copying opencode.json.sample to opencode.json..."
cp opencode.json.sample opencode.json

# APIキー置換
sed -i "s/YOUR_API_KEY_HERE/$API_KEY/g" opencode.json

echo "✅ opencode.json created successfully"

# 接続テスト
echo "🔍 Testing connection..."
if curl -s http://192.168.50.112:4000/health/liveliness | grep -q "healthy"; then
    echo "✅ Connection successful!"
else
    echo "❌ Connection failed" >&2
    exit 1
fi

echo "🎉 Setup completed!"
echo "Next: Run 'opencode --help' to see available commands"
```

**使用方法（Linux / WSL）:**

```bash
# 実行可能権限を付与
chmod +x scripts/setup-client.sh

# スクリプト実行
./scripts/setup-client.sh
```

---

## トラブルシューティング

### 1. 接続エラー

**症状:** `curl: (7) Failed to connect to 192.168.50.112 port 4000`

**原因:**
- サーバーPCがオフライン
- ネットワーク接続なし
- ファイアウォールでブロック

**解決策:**

```bash
# サーバーが応答しているか確認
ping 192.168.50.112

# ポートが開いているか確認
telnet 192.168.50.112 4000
# または
Test-NetConnection -ComputerName 192.168.50.112 -Port 4000
```

### 2. 認証エラー

**症状:** `"error":{"message":"Unauthorized","type":"auth_error"}}`

**原因:**
- APIキーが間違っている
- APIキーの有効期限が切れている
- 型ミス（スペースや改行）

**解決策:**

```bash
# APIキーの確認
cat opencode.json | grep apiKey

# 正しいAPIキーで再テスト
curl http://192.168.50.112:4000/v1/models \
  -H "Authorization: Bearer YOUR_ACTUAL_KEY"
```

### 3. WSLからサーバーに接続できない

**症状:** `connection refused` or `no route to host`

**解決策:**

1. WindowsホストのIPアドレスを確認:

```powershell
# Windows側で実行
ipconfig
```

2. WSL側で `/etc/resolv.conf` を更新:

```bash
# WSL側で実行
cat /etc/resolv.conf

# 必要に応じて更新
nameserver 8.8.8.8
nameserver 192.168.50.1  # WindowsホストのIP
```

3. Windows ファイアウォールでポート4000を開く:

```powershell
New-NetFirewallRule -DisplayName "LiteLLM" -Direction Inbound -LocalPort 4000 -Protocol TCP -Action Allow
```

### 4. APIキーが正しくても認証失敗

**サーバー側で確認:**

```bash
# サーバー側で実行
cd ~/cocoro-llm-server
cat .env | grep LITELLM_MASTER_KEY
```

**APIキーを再生成:**

```bash
# サーバー側で実行
openssl rand -base64 32
```

### 5. SSL/TLSエラー（まれに発生）

**症状:** `error:0A000126:SSL routines::unexpected eof while reading`

**解決策:**

`opencode.json` に以下を追加:

```json
{
  "baseURL": "http://192.168.50.112:4000/v1",
  "apiKey": "YOUR_API_KEY_HERE",
  "strictSSL": false
}
```

---

## 関連ドキュメント

| ドキュメント | 説明 |
|--------------|------|
| [CLAUDE.md](../CLAUDE.md) | サーバー構成概要 |
| [COCORO_INTEGRATION.md](../docs/COCORO_INTEGRATION.md) | cocoro-coreとの接続 |
| [LOCAL_DEV_GUIDE.md](../docs/LOCAL_DEV_GUIDE.md) | ローカル開発ガイド |

---

## お問い合わせ

- GitHub Issues: https://github.com/mdl-systems/cocoro-llm-server/issues
- 社内Slack: #dev-cocoro-llm
