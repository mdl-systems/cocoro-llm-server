"""
Anthropic → OpenAI 完全変換プロキシ（ツールサポート付き）
- /v1/messages (Anthropic) → /v1/chat/completions (OpenAI)
- ツール定義・ツール呼び出し・ツール結果を双方向変換
"""
import json
import sys
import uuid
import httpx
from fastapi import FastAPI, Request
from fastapi.responses import StreamingResponse, Response

app = FastAPI()
BACKEND = "http://litellm:4000"


# ── コンテンツ正規化 ──────────────────────────────────────────

def content_to_text(content) -> str:
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        parts = []
        for block in content:
            if isinstance(block, str):
                parts.append(block)
            elif isinstance(block, dict):
                btype = block.get("type", "")
                if btype in ("text", "input_text", "output_text") and "text" in block:
                    parts.append(block["text"])
        return "\n".join(filter(None, parts))
    return ""


def tool_result_content(content) -> str:
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        parts = []
        for block in content:
            if isinstance(block, dict) and block.get("type") == "text":
                parts.append(block.get("text", ""))
            elif isinstance(block, str):
                parts.append(block)
        return "\n".join(filter(None, parts))
    return str(content) if content else ""


def image_block_to_openai(block: dict):
    """Anthropic の image ブロックを OpenAI の image_url パートへ変換。失敗時 None。"""
    source = block.get("source", {})
    if not isinstance(source, dict):
        return None
    stype = source.get("type")
    if stype == "base64":
        media = source.get("media_type", "image/png")
        data = source.get("data", "")
        if not data:
            return None
        return {"type": "image_url",
                "image_url": {"url": f"data:{media};base64,{data}"}}
    if stype == "url":
        url = source.get("url", "")
        if not url:
            return None
        return {"type": "image_url", "image_url": {"url": url}}
    return None


# ── Anthropic → OpenAI メッセージ変換 ────────────────────────

def to_openai_messages(messages: list, system=None) -> list:
    result = []
    if system:
        sys_text = content_to_text(system) if isinstance(system, list) else system
        if sys_text:
            result.append({"role": "system", "content": sys_text})

    for msg in messages:
        role = msg.get("role", "user")
        content = msg.get("content", "")

        if isinstance(content, str):
            if content:
                result.append({"role": role, "content": content})
            continue

        if not isinstance(content, list):
            continue

        if role == "assistant":
            text_parts = []
            tool_calls = []
            for block in content:
                btype = block.get("type", "")
                if btype in ("text", "output_text") and block.get("text"):
                    text_parts.append(block["text"])
                elif btype == "tool_use":
                    tool_calls.append({
                        "id": block.get("id", f"call_{uuid.uuid4().hex[:8]}"),
                        "type": "function",
                        "function": {
                            "name": block.get("name", ""),
                            "arguments": json.dumps(block.get("input", {}), ensure_ascii=False),
                        },
                    })
            oai_msg = {"role": "assistant", "content": "\n".join(text_parts) or None}
            if tool_calls:
                oai_msg["tool_calls"] = tool_calls
            result.append(oai_msg)

        elif role == "user":
            tool_results = []
            text_parts = []
            image_parts = []
            for block in content:
                if isinstance(block, str):
                    if block:
                        text_parts.append(block)
                    continue
                btype = block.get("type", "")
                if btype == "tool_result":
                    tool_results.append({
                        "role": "tool",
                        "tool_call_id": block.get("tool_use_id", ""),
                        "content": tool_result_content(block.get("content", "")),
                    })
                elif btype in ("text", "input_text") and block.get("text"):
                    text_parts.append(block["text"])
                elif btype == "image":
                    img = image_block_to_openai(block)
                    if img:
                        image_parts.append(img)

            result.extend(tool_results)
            if image_parts:
                print(f"[proxy] IMAGE detected: {len(image_parts)} image part(s) in user message", flush=True)
                parts = []
                joined = "\n".join(text_parts)
                if joined:
                    parts.append({"type": "text", "text": joined})
                parts.extend(image_parts)
                result.append({"role": "user", "content": parts})
            elif text_parts:
                result.append({"role": "user", "content": "\n".join(text_parts)})
            elif not tool_results:
                text = content_to_text(content)
                if text:
                    result.append({"role": "user", "content": text})

    return result


def to_openai_tools(tools: list) -> list:
    result = []
    for tool in tools:
        result.append({
            "type": "function",
            "function": {
                "name": tool.get("name", ""),
                "description": tool.get("description", ""),
                "parameters": tool.get("input_schema", {"type": "object", "properties": {}}),
            },
        })
    return result


def to_openai_tool_choice(tool_choice) -> str | dict | None:
    if not tool_choice:
        return None
    tc_type = tool_choice.get("type", "auto")
    if tc_type == "auto":
        return "auto"
    if tc_type == "any":
        return "required"
    if tc_type == "tool":
        return {"type": "function", "function": {"name": tool_choice.get("name", "")}}
    return "auto"


# ── SSE ヘルパー ─────────────────────────────────────────────

def _msg_start(msg_id: str, model: str) -> str:
    data = {"type": "message_start", "message": {
        "id": msg_id, "type": "message", "role": "assistant",
        "content": [], "model": model, "stop_reason": None, "stop_sequence": None,
        "usage": {"input_tokens": 0, "output_tokens": 0,
                  "cache_creation_input_tokens": 0, "cache_read_input_tokens": 0},
    }}
    return f"event: message_start\ndata: {json.dumps(data, ensure_ascii=False)}\n\n"


def _block_start(index: int) -> str:
    data = {"type": "content_block_start", "index": index,
            "content_block": {"type": "text", "text": ""}}
    return f"event: content_block_start\ndata: {json.dumps(data, ensure_ascii=False)}\n\n"


def _tool_block_start(index: int, tool_id: str, name: str) -> str:
    data = {"type": "content_block_start", "index": index,
            "content_block": {"type": "tool_use", "id": tool_id, "name": name, "input": {}}}
    return f"event: content_block_start\ndata: {json.dumps(data, ensure_ascii=False)}\n\n"


def _block_delta(index: int, text: str) -> str:
    data = {"type": "content_block_delta", "index": index,
            "delta": {"type": "text_delta", "text": text}}
    return f"event: content_block_delta\ndata: {json.dumps(data, ensure_ascii=False)}\n\n"


def _input_json_delta(index: int, partial_json: str) -> str:
    data = {"type": "content_block_delta", "index": index,
            "delta": {"type": "input_json_delta", "partial_json": partial_json}}
    return f"event: content_block_delta\ndata: {json.dumps(data, ensure_ascii=False)}\n\n"


def _block_stop(index: int) -> str:
    return f"event: content_block_stop\ndata: {json.dumps({'type': 'content_block_stop', 'index': index})}\n\n"


def _msg_delta(stop_reason: str, in_tok: int, out_tok: int) -> str:
    data = {"type": "message_delta",
            "delta": {"stop_reason": stop_reason, "stop_sequence": None},
            "usage": {"input_tokens": in_tok, "output_tokens": out_tok}}
    return f"event: message_delta\ndata: {json.dumps(data, ensure_ascii=False)}\n\n"


def _msg_stop() -> str:
    return 'event: message_stop\ndata: {"type": "message_stop"}\n\n'


# ── OpenAI SSE → Anthropic SSE 変換 ──────────────────────────

async def openai_stream_to_anthropic(resp: httpx.Response, model: str, msg_id: str):
    yield _msg_start(msg_id, model)

    next_idx = 0
    text_idx = None        # 現在開いているテキストブロックのindex
    tool_map = {}          # openai tool_call index → {block_idx, id, name}
    open_blocks = set()    # 開いているブロックのindex集合

    in_tok = out_tok = 0
    finish_reason = "end_turn"

    async for line in resp.aiter_lines():
        if not line.startswith("data: "):
            continue
        raw = line[6:].strip()
        if raw == "[DONE]":
            break
        try:
            chunk = json.loads(raw)
            choice = chunk.get("choices", [{}])[0]
            delta = choice.get("delta", {})

            # テキスト
            text = delta.get("content") or ""
            if text:
                if text_idx is None:
                    text_idx = next_idx
                    next_idx += 1
                    yield _block_start(text_idx)
                    open_blocks.add(text_idx)
                yield _block_delta(text_idx, text)

            # ツール呼び出し
            for tc in (delta.get("tool_calls") or []):
                oai_idx = tc.get("index", 0)
                if oai_idx not in tool_map:
                    # テキストブロックを閉じる
                    if text_idx is not None and text_idx in open_blocks:
                        yield _block_stop(text_idx)
                        open_blocks.remove(text_idx)

                    blk_idx = next_idx
                    next_idx += 1
                    tc_id = tc.get("id") or f"toolu_{uuid.uuid4().hex[:24]}"
                    tc_name = (tc.get("function") or {}).get("name", "")
                    tool_map[oai_idx] = {"block_idx": blk_idx, "id": tc_id, "name": tc_name}
                    yield _tool_block_start(blk_idx, tc_id, tc_name)
                    open_blocks.add(blk_idx)

                args = (tc.get("function") or {}).get("arguments", "")
                if args:
                    yield _input_json_delta(tool_map[oai_idx]["block_idx"], args)

            fr = choice.get("finish_reason")
            if fr == "length":
                finish_reason = "max_tokens"
            elif fr == "tool_calls":
                finish_reason = "tool_use"
            elif fr:
                finish_reason = "end_turn"

            usage = chunk.get("usage") or {}
            if usage:
                in_tok = usage.get("prompt_tokens", in_tok)
                out_tok = usage.get("completion_tokens", out_tok)
        except Exception:
            pass

    # 開いているブロックをすべて閉じる
    for idx in sorted(open_blocks):
        yield _block_stop(idx)

    yield _msg_delta(finish_reason, in_tok, out_tok)
    yield _msg_stop()


def openai_to_anthropic(openai_resp: dict, model: str, msg_id: str) -> dict:
    choice = openai_resp.get("choices", [{}])[0]
    msg = choice.get("message", {})
    text = msg.get("content", "") or ""
    usage = openai_resp.get("usage", {})

    content = []
    if text:
        content.append({"type": "text", "text": text})

    for tc in (msg.get("tool_calls") or []):
        try:
            input_data = json.loads(tc.get("function", {}).get("arguments", "{}"))
        except Exception:
            input_data = {}
        content.append({
            "type": "tool_use",
            "id": tc.get("id", f"toolu_{uuid.uuid4().hex[:24]}"),
            "name": tc.get("function", {}).get("name", ""),
            "input": input_data,
        })

    stop_reason = "tool_use" if msg.get("tool_calls") else "end_turn"
    return {
        "id": msg_id, "type": "message", "role": "assistant",
        "content": content, "model": model,
        "stop_reason": stop_reason, "stop_sequence": None,
        "usage": {
            "input_tokens": usage.get("prompt_tokens", 0),
            "output_tokens": usage.get("completion_tokens", 0),
        },
    }


# ── モックエンドポイント ─────────────────────────────────────

BOOTSTRAP_RESPONSE = {
    "auth_type": "api_key", "capabilities": [], "features": {"claude_code": True},
    "is_authenticated": True, "plan": "pro",
    "session": {"id": "local-session", "type": "api_key"},
    "user": {"id": "local-user", "email": "local@localhost"},
}


# ── メインルーター ───────────────────────────────────────────

@app.api_route("/{path:path}", methods=["GET", "POST", "PUT", "DELETE", "HEAD", "OPTIONS"])
async def proxy(request: Request, path: str):
    query = str(request.url.query)
    raw_body = await request.body()
    headers = {k: v for k, v in request.headers.items() if k.lower() != "host"}

    print(f"[REQ] {request.method} /{path}{'?'+query if query else ''}", flush=True)

    # モック: bootstrap / metrics
    if "bootstrap" in path:
        return Response(content=json.dumps(BOOTSTRAP_RESPONSE).encode(),
                        status_code=200, headers={"content-type": "application/json"})
    if "metrics" in path:
        return Response(content=b'{"enabled":false}',
                        status_code=200, headers={"content-type": "application/json"})

    # /v1/messages 以外はそのまま転送
    if path != "v1/messages":
        url = f"{BACKEND}/{path}" + (f"?{query}" if query else "")
        async with httpx.AsyncClient(timeout=httpx.Timeout(300)) as client:
            resp = await client.request(request.method, url, headers=headers,
                                        content=raw_body, timeout=300)
            return Response(content=resp.content, status_code=resp.status_code,
                            headers=dict(resp.headers))

    # /v1/messages を処理
    try:
        body = json.loads(raw_body)
    except Exception:
        url = f"{BACKEND}/{path}" + (f"?{query}" if query else "")
        async with httpx.AsyncClient(timeout=httpx.Timeout(300)) as client:
            resp = await client.request(request.method, url, headers=headers,
                                        content=raw_body, timeout=300)
            return Response(content=resp.content, status_code=resp.status_code,
                            headers=dict(resp.headers))

    model = body.get("model", "claude-sonnet-4-6")
    is_stream = body.get("stream", False)
    msg_id = f"msg_{uuid.uuid4().hex[:24]}"

    openai_messages = to_openai_messages(body.get("messages", []), body.get("system"))
    openai_tools = to_openai_tools(body.get("tools", []))
    openai_tool_choice = to_openai_tool_choice(body.get("tool_choice"))

    oai_body: dict = {
        "model": model,
        "messages": openai_messages,
        "max_tokens": body.get("max_tokens", 8192),
        "stream": is_stream,
    }
    if openai_tools:
        oai_body["tools"] = openai_tools
    if openai_tool_choice:
        oai_body["tool_choice"] = openai_tool_choice

    api_key = (headers.get("authorization") or
               f"Bearer {headers.get('x-api-key', '')}")
    oai_headers = {"Authorization": api_key, "Content-Type": "application/json"}
    oai_url = f"{BACKEND}/v1/chat/completions"

    print(f"[proxy] model={model} stream={is_stream} msgs={len(openai_messages)} "
          f"tools={len(openai_tools)} thinking={body.get('thinking')}", flush=True)

    if is_stream:
        async def generate():
            async with httpx.AsyncClient(timeout=httpx.Timeout(300)) as client:
                async with client.stream("POST", oai_url, headers=oai_headers,
                                         content=json.dumps(oai_body, ensure_ascii=False).encode(),
                                         timeout=300) as resp:
                    async for chunk in openai_stream_to_anthropic(resp, model, msg_id):
                        yield chunk
        return StreamingResponse(generate(), media_type="text/event-stream")
    else:
        async with httpx.AsyncClient(timeout=httpx.Timeout(300)) as client:
            resp = await client.post(oai_url, headers=oai_headers,
                                     content=json.dumps(oai_body, ensure_ascii=False).encode(),
                                     timeout=300)
        if resp.status_code == 200:
            result = openai_to_anthropic(resp.json(), model, msg_id)
            return Response(content=json.dumps(result, ensure_ascii=False).encode(),
                            status_code=200, headers={"content-type": "application/json"})
        return Response(content=resp.content, status_code=resp.status_code,
                        headers=dict(resp.headers))
