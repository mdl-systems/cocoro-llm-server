// ローカルプロキシ: OpenCode → このPC(localhost:4000) → サーバー(192.168.50.112:8000)
// tool_choice / tools パラメータを除去してvLLMのエラーを回避する

import http from "node:http";
import https from "node:https";

const TARGET = "http://192.168.50.112:8000";
const PORT = 4000;

const server = http.createServer((req, res) => {
  let body = "";
  req.on("data", (chunk) => (body += chunk));
  req.on("end", () => {
    // JSON bodyからtool関連パラメータを除去 & max_tokens制限
    if (body && req.headers["content-type"]?.includes("application/json")) {
      try {
        const json = JSON.parse(body);
        delete json.tool_choice;
        delete json.tools;
        // max_tokens を制限（サーバーのmax_model_len=32768に収める）
        if (json.max_tokens && json.max_tokens > 16000) {
          json.max_tokens = 16000;
        }
        body = JSON.stringify(json);
      } catch (e) {
        // パース失敗時はそのまま転送
      }
    }

    const url = new URL(req.url, TARGET);
    const options = {
      hostname: url.hostname,
      port: url.port,
      path: url.pathname + url.search,
      method: req.method,
      headers: {
        ...req.headers,
        host: url.host,
        "content-length": Buffer.byteLength(body),
      },
    };

    const proxyReq = http.request(options, (proxyRes) => {
      res.writeHead(proxyRes.statusCode, proxyRes.headers);
      proxyRes.pipe(res);
    });

    proxyReq.on("error", (e) => {
      res.writeHead(502);
      res.end(JSON.stringify({ error: { message: e.message } }));
    });

    proxyReq.write(body);
    proxyReq.end();
  });
});

server.listen(PORT, "127.0.0.1", () => {
  console.log(`Proxy running: localhost:${PORT} → ${TARGET}`);
  console.log("tool_choice/tools パラメータを自動除去します");
});
