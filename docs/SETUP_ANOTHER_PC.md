# 別のPCでのセットアップガイド

## 目的
ローカルにモデルをインストールする代わりに、サーバー（192.168.50.112）のQwen3-Coder-Next-FP8をAPI経由で利用する設定です。

---

## 手順

### 1. リポジトリをクローン

```bash
git clone https://github.com/mdl-systems/cocoro-llm-server.git
cd cocoro-llm-server
```

### 2. opencode.json を編集

`opencode.json` の `baseURL` をサーバーのIPアドレスに変更：

```json
{
  "provider": {
    "litellm": {
      "options": {
        "baseURL": "http://192.168.50.112:4000/v1",
        "apiKey": "sk-mdl-ea48b54600e342608ed9f417fcb310d3"
      }
    }
  }
}
```

### 3. 動作確認

```bash
# ヘルスチェック（サーバーに接続可能か確認）
curl http://192.168.50.112:4000/health/liveliness

# モデル一覧確認
curl http://192.168.50.112:4000/v1/models \
  -H "Authorization: Bearer sk-mdl-ea48b54600e342608ed9f417fcb310d3"
```

---

## 接続情報

| 項目 | 値 |
|---|---|
| サーバーIP | `192.168.50.112` |
| APIポート | `4000` |
| API Key | `sk-mdl-ea48b54600e342608ed9f417fcb310d3` |
| モデル名 | `qwen3-coder` |

---

## 補足

- **proxy.mjs** はローカル開発用です（tool_choice の互換性調整）
- 必要に応じて、`proxy.mjs` をローカルで起動して `localhost:4000` 経由に変更可能
