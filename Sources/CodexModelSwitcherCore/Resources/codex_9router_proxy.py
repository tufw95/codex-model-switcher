#!/usr/bin/env python3
import argparse
import http.client
import json
import os
import socket
import ssl
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlsplit

MODEL_ENDPOINTS = {"/models", "/v1/models"}

CHROME_TOOL_DISCOVERY_GUARD = """<chrome_tool_discovery_guard>
If the current user task asks for Chrome, Chrome/DOM, the Codex Chrome Extension, browser-client, node_repl, or mcp__node_repl__js, and the callable mcp__node_repl__js tool is not already in your current tool list while tool_search is available, you must call tool_search before claiming the tool or bridge is unavailable. First call tool_search with query "node_repl js" and no limit. If that does not expose mcp__node_repl__js, call tool_search again with query "node_repl js" and limit 10. Do not answer "mcp__node_repl__js tool unavailable" until both discovery attempts fail. Respect any user restriction against mouse, keyboard, or screenshots.
</chrome_tool_discovery_guard>"""
CHROME_TOOL_DISCOVERY_GUARD_MARKER = "<chrome_tool_discovery_guard>"
CHROME_TOOL_DISCOVERY_TERMS = (
    "chrome",
    "chrome/dom",
    "codex chrome extension",
    "browser-client",
    "node_repl",
    "mcp__node_repl__js",
)


class ProxyHandler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    target = None
    rewrite_from = set()
    rewrite_map = {}
    rewrite_to = None
    rewrite_openai_models = False
    rewrite_all_unmapped = True
    model_catalog = None

    def log_message(self, fmt, *args):
        return

    def log_proxy_event(self, event, **fields):
        parts = [f"proxy event={event}"]
        for key, value in fields.items():
            parts.append(f"{key}={value}")
        print(" ".join(parts), flush=True)

    def do_GET(self):
        if self.path == "/health":
            body = b"ok\n"
            self.send_response(200)
            self.send_header("Content-Type", "text/plain")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        self.forward()

    def do_POST(self):
        self.forward()

    def do_PUT(self):
        self.forward()

    def do_PATCH(self):
        self.forward()

    def do_DELETE(self):
        self.forward()

    def read_body(self):
        length = self.headers.get("Content-Length")
        if not length:
            return b""
        return self.rfile.read(int(length))

    def rewritten_model(self, model):
        """Return the upstream model name for an incoming model, or None to leave unchanged.

        Precedence:
          1. Exact rewrite_map entry (e.g. gpt-5.5 -> cx/gpt-5.5).
          2. Explicit rewrite_from list.
          3. rewrite_openai_models: any gpt-* / openai/gpt-* name.
          4. rewrite_all_unmapped (default): any name that is not already a
             cx/* model. This guarantees aux/background models the catalog can
             request (e.g. codex-auto-review) never leak upstream unmapped.
        Models already prefixed cx/ are always left untouched.
        """
        if not isinstance(model, str) or not model:
            return None
        if model in self.rewrite_map:
            return self.rewrite_map[model]
        if model.startswith("cx/"):
            return None
        if model in self.rewrite_from:
            return self.rewrite_to
        if self.rewrite_openai_models and (
            model.startswith("gpt-") or model.startswith("openai/gpt-")
        ):
            return self.rewrite_to
        if self.rewrite_all_unmapped:
            return self.rewrite_to
        return None

    def maybe_rewrite_body(self, body):
        content_type = self.headers.get("Content-Type", "")
        if not body or "json" not in content_type.lower():
            return body
        try:
            payload = json.loads(body.decode("utf-8"))
        except Exception:
            return body
        if not isinstance(payload, dict):
            return body
        changed = False
        model = payload.get("model")
        new_model = self.rewritten_model(model)
        if new_model is not None and new_model != model:
            payload["model"] = new_model
            changed = True
        if self.maybe_inject_chrome_tool_discovery_guard(payload):
            changed = True
        if self.maybe_translate_tool_search_for_chrome(payload):
            changed = True
        if changed:
            return json.dumps(payload, separators=(",", ":")).encode("utf-8")
        return body

    def tool_names(self, payload):
        tools = payload.get("tools")
        if not isinstance(tools, list):
            return set()
        names = set()
        for tool in tools:
            if not isinstance(tool, dict):
                continue
            for key in ("name", "type"):
                value = tool.get(key)
                if isinstance(value, str) and value:
                    names.add(value)
        return names

    def user_input_text(self, payload):
        items = payload.get("input")
        if not isinstance(items, list):
            return ""
        parts = []
        for item in items:
            if not isinstance(item, dict) or item.get("role") != "user":
                continue
            content = item.get("content")
            if isinstance(content, str):
                parts.append(content)
                continue
            if not isinstance(content, list):
                continue
            for part in content:
                if not isinstance(part, dict):
                    continue
                text = part.get("text")
                if isinstance(text, str):
                    parts.append(text)
        return "\n".join(parts).casefold()

    def needs_chrome_tool_discovery_guard(self, payload):
        tool_names = self.tool_names(payload)
        if "tool_search" not in tool_names:
            return False
        if "mcp__node_repl__js" in tool_names:
            return False
        user_text = self.user_input_text(payload)
        return any(term in user_text for term in CHROME_TOOL_DISCOVERY_TERMS)

    def maybe_inject_chrome_tool_discovery_guard(self, payload):
        if not self.needs_chrome_tool_discovery_guard(payload):
            return False
        instructions = payload.get("instructions")
        if isinstance(instructions, str):
            if CHROME_TOOL_DISCOVERY_GUARD_MARKER in instructions:
                return False
            payload["instructions"] = instructions + "\n\n" + CHROME_TOOL_DISCOVERY_GUARD
        else:
            payload["instructions"] = CHROME_TOOL_DISCOVERY_GUARD
        self.log_proxy_event(
            "chrome_tool_discovery_guard_injected",
            method=self.command,
            path=urlsplit(self.path).path,
            incoming_model=self.model_from_body(json.dumps(payload).encode("utf-8")),
        )
        return True

    def maybe_translate_tool_search_for_chrome(self, payload):
        """Expose Codex's client-side tool_search as a normal function for
        providers that do not understand the Responses tool_search item.

        Codex expects the result back as a response.output_item.done item with
        type=tool_search_call. The SSE normalizer below converts the provider's
        function_call back into that shape before Codex sees it.
        """
        if not self.needs_chrome_tool_discovery_guard(payload):
            return False
        tools = payload.get("tools")
        if not isinstance(tools, list):
            return False

        changed = False
        for index, tool in enumerate(tools):
            if not isinstance(tool, dict) or tool.get("type") != "tool_search":
                continue
            description = tool.get("description")
            if not isinstance(description, str) or not description:
                description = "Search deferred tool metadata and expose matching tools for the next model call."
            tools[index] = {
                "type": "function",
                "name": "tool_search",
                "description": description,
                "parameters": {
                    "type": "object",
                    "properties": {
                        "query": {
                            "type": "string",
                            "description": "Search query for deferred tools, for example node_repl js.",
                        },
                        "limit": {
                            "type": "integer",
                            "description": "Optional maximum number of matching tool groups to return.",
                            "minimum": 1,
                        },
                    },
                    "required": ["query"],
                    "additionalProperties": False,
                },
                "strict": False,
            }
            changed = True

        if changed:
            self.translate_tool_search_function = True
            self.tool_search_function_call_active = False
            self.log_proxy_event(
                "chrome_tool_search_translated_to_function",
                method=self.command,
                path=urlsplit(self.path).path,
                incoming_model=self.model_from_body(json.dumps(payload).encode("utf-8")),
            )
        return changed

    def model_from_body(self, body):
        content_type = self.headers.get("Content-Type", "")
        if not body or "json" not in content_type.lower():
            return "-"
        try:
            payload = json.loads(body.decode("utf-8"))
        except Exception:
            return "-"
        if not isinstance(payload, dict):
            return "-"
        model = payload.get("model")
        return model if isinstance(model, str) and model else "-"

    def is_single_title_schema_request(self, body):
        """Detect Codex's structured title generation request.

        9Router currently streams a plain title even when Codex requests a
        JSON-schema object. Keep this narrowly scoped to the one-field title
        schema so normal chat and tool turns pass through unchanged.
        """
        content_type = self.headers.get("Content-Type", "")
        if not body or "json" not in content_type.lower():
            return False
        try:
            payload = json.loads(body.decode("utf-8"))
        except Exception:
            return False
        if not isinstance(payload, dict):
            return False

        text = payload.get("text")
        if not isinstance(text, dict):
            return False
        fmt = text.get("format")
        if not isinstance(fmt, dict) or fmt.get("type") != "json_schema":
            return False
        schema = fmt.get("schema")
        if not isinstance(schema, dict):
            return False

        props = schema.get("properties")
        required = schema.get("required")
        title_schema = props.get("title") if isinstance(props, dict) else None
        return (
            schema.get("type") == "object"
            and isinstance(title_schema, dict)
            and title_schema.get("type") == "string"
            and required == ["title"]
        )

    def title_json_text(self, text):
        if not isinstance(text, str):
            return text
        stripped = text.strip()
        if not stripped:
            return text
        try:
            parsed = json.loads(stripped)
            if isinstance(parsed, dict) and isinstance(parsed.get("title"), str):
                return text
        except Exception:
            pass
        self.title_schema_normalized_count = getattr(self, "title_schema_normalized_count", 0) + 1
        return json.dumps({"title": stripped}, ensure_ascii=False, separators=(",", ":"))

    def normalize_title_event(self, event):
        if not isinstance(event, dict):
            return event

        event_type = event.get("type")
        if event_type == "response.output_text.done" and "text" in event:
            event["text"] = self.title_json_text(event.get("text"))
            return event

        if event_type == "response.completed":
            response = event.get("response")
            output = response.get("output") if isinstance(response, dict) else None
            if isinstance(output, list):
                for item in output:
                    self.normalize_title_output_item(item)
            return event

        if event_type == "response.output_item.done":
            self.normalize_title_output_item(event.get("item"))
        return event

    def normalize_title_output_item(self, item):
        if not isinstance(item, dict) or item.get("type") != "message":
            return
        content = item.get("content")
        if not isinstance(content, list):
            return
        for part in content:
            if isinstance(part, dict) and part.get("type") == "output_text" and "text" in part:
                part["text"] = self.title_json_text(part.get("text"))

    def maybe_normalize_title_sse_line(self, line):
        prefix = b"data:"
        if not line.startswith(prefix):
            return line
        payload = line[len(prefix):].strip()
        if not payload or payload == b"[DONE]":
            return line
        try:
            event = json.loads(payload.decode("utf-8"))
        except Exception:
            return line
        normalized = self.normalize_title_event(event)
        return b"data: " + json.dumps(normalized, ensure_ascii=False, separators=(",", ":")).encode("utf-8") + b"\n"

    def tool_search_arguments(self, value):
        if isinstance(value, dict):
            return value
        if isinstance(value, str):
            try:
                parsed = json.loads(value)
                if isinstance(parsed, dict):
                    return parsed
            except Exception:
                pass
            if value.strip():
                return {"query": value.strip()}
        return {}

    def normalize_tool_search_output_item(self, item):
        if not isinstance(item, dict):
            return False
        if item.get("type") != "function_call" or item.get("name") != "tool_search":
            return False
        item["type"] = "tool_search_call"
        item["execution"] = "client"
        item["arguments"] = self.tool_search_arguments(item.get("arguments"))
        item.pop("name", None)
        return True

    def normalize_tool_search_function_event(self, event):
        if not isinstance(event, dict):
            return event

        event_type = event.get("type")
        if event_type in {"response.output_item.added", "response.output_item.done"}:
            item = event.get("item")
            if self.normalize_tool_search_output_item(item):
                self.tool_search_function_call_active = event_type != "response.output_item.done"
                self.log_proxy_event(
                    "chrome_tool_search_function_normalized",
                    method=self.command,
                    path=urlsplit(self.path).path,
                    event_type=event_type,
                )
            return event

        if event_type == "response.completed":
            response = event.get("response")
            output = response.get("output") if isinstance(response, dict) else None
            if isinstance(output, list):
                for item in output:
                    self.normalize_tool_search_output_item(item)
            return event

        return event

    def maybe_normalize_tool_search_sse_line(self, line):
        prefix = b"data:"
        if not line.startswith(prefix):
            return line
        payload = line[len(prefix):].strip()
        if not payload or payload == b"[DONE]":
            return line
        try:
            event = json.loads(payload.decode("utf-8"))
        except Exception:
            return line

        event_type = event.get("type") if isinstance(event, dict) else None
        if event_type and event_type.startswith("response.function_call_arguments.") and getattr(self, "tool_search_function_call_active", False):
            return b""

        normalized = self.normalize_tool_search_function_event(event)
        return b"data: " + json.dumps(normalized, ensure_ascii=False, separators=(",", ":")).encode("utf-8") + b"\n"

    def is_model_list_request(self):
        if self.command != "GET":
            return False
        path = urlsplit(self.path).path.rstrip("/")
        return path in MODEL_ENDPOINTS

    def upstream_path_and_headers(self, body):
        target = self.target
        path = self.path
        if target.path and path.startswith("/"):
            path = target.path.rstrip("/") + path
        headers = {}
        for key, value in self.headers.items():
            lower = key.lower()
            if lower in {"host", "content-length", "transfer-encoding"}:
                continue
            if lower == "accept-encoding":
                headers[key] = "identity"
                continue
            headers[key] = value
        headers["Host"] = target.netloc
        if body:
            headers["Content-Length"] = str(len(body))
        return path, headers

    def open_upstream(self):
        target = self.target
        port = target.port or (443 if target.scheme == "https" else 80)
        if target.scheme == "https":
            return http.client.HTTPSConnection(
                target.hostname, port, context=ssl.create_default_context(), timeout=300
            )
        return http.client.HTTPConnection(target.hostname, port, timeout=300)

    def maybe_serve_model_catalog(self):
        """Serve the local Codex-shaped model catalog ({"models": [...]}) for
        /models and /v1/models. This is the primary path and keeps the Codex
        model picker working even if the upstream returns an OpenAI-style
        {"data": [...]} list."""
        if not self.is_model_list_request():
            return False
        if not self.model_catalog or not os.path.exists(self.model_catalog):
            return False

        with open(self.model_catalog, "rb") as catalog:
            body = catalog.read()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Connection", "close")
        self.end_headers()
        self.wfile.write(body)
        self.close_connection = True
        return True

    def maybe_serve_models_reshaped(self):
        """Fallback catalog hardening: if the local catalog is missing, fetch the
        upstream model list and normalize an OpenAI-style {"data": [...]} body
        into the Codex-required {"models": [...]} shape so the picker never
        breaks with a 'missing field models' error."""
        if not self.is_model_list_request():
            return False
        try:
            path, headers = self.upstream_path_and_headers(b"")
            conn = self.open_upstream()
            try:
                conn.request("GET", path, headers=headers)
                response = conn.getresponse()
                raw = response.read()
                status = response.status
                reason = response.reason
                content_type = response.getheader("Content-Type", "application/json")
            finally:
                conn.close()
        except (OSError, http.client.HTTPException):
            return False

        out = raw
        try:
            data = json.loads(raw)
            if (
                isinstance(data, dict)
                and "models" not in data
                and isinstance(data.get("data"), list)
            ):
                out = json.dumps({"models": data["data"]}).encode("utf-8")
                content_type = "application/json"
        except Exception:
            pass

        self.send_response(status, reason)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(out)))
        self.send_header("Connection", "close")
        self.end_headers()
        self.wfile.write(out)
        self.close_connection = True
        return True

    def forward(self):
        if self.maybe_serve_model_catalog():
            return
        if self.maybe_serve_models_reshaped():
            return

        original_body = self.read_body()
        self.title_schema_normalized_count = 0
        self.translate_tool_search_function = False
        self.tool_search_function_call_active = False
        normalize_title_schema = self.is_single_title_schema_request(original_body)
        if normalize_title_schema:
            self.log_proxy_event(
                "title_schema_detected",
                method=self.command,
                path=urlsplit(self.path).path,
                incoming_model=self.model_from_body(original_body),
            )
        body = self.maybe_rewrite_body(original_body)
        path, headers = self.upstream_path_and_headers(body)
        conn = self.open_upstream()

        try:
            conn.request(self.command, path, body=body if body else None, headers=headers)
            response = conn.getresponse()
            content_type = response.getheader("Content-Type", "")
            self.send_response(response.status, response.reason)
            for key, value in response.getheaders():
                lower = key.lower()
                if lower in {"transfer-encoding", "content-length", "connection"}:
                    continue
                self.send_header(key, value)
            self.send_header("Connection", "close")
            self.end_headers()
            if "text/event-stream" in content_type.lower():
                while True:
                    line = response.readline()
                    if not line:
                        break
                    if normalize_title_schema:
                        line = self.maybe_normalize_title_sse_line(line)
                    if self.translate_tool_search_function:
                        line = self.maybe_normalize_tool_search_sse_line(line)
                        if not line:
                            continue
                    self.wfile.write(line)
                    self.wfile.flush()
                if normalize_title_schema:
                    self.log_proxy_event(
                        "title_schema_normalized",
                        method=self.command,
                        path=urlsplit(self.path).path,
                        status=response.status,
                        count=self.title_schema_normalized_count,
                    )
            else:
                while True:
                    chunk = response.read(8192)
                    if not chunk:
                        break
                    self.wfile.write(chunk)
                    self.wfile.flush()
        except (BrokenPipeError, ConnectionResetError):
            self.close_connection = True
        except (OSError, http.client.HTTPException) as exc:
            message = json.dumps({"error": {"message": f"9Router proxy error: {exc}"}}).encode("utf-8")
            try:
                self.send_response(502)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(message)))
                self.end_headers()
                self.wfile.write(message)
            except (BrokenPipeError, ConnectionResetError, OSError):
                self.close_connection = True
        finally:
            self.close_connection = True
            conn.close()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=9783)
    parser.add_argument("--target", default="https://9router.bigroll.vn")
    parser.add_argument("--rewrite-from", action="append", default=[])
    parser.add_argument("--rewrite-map", action="append", default=[])
    parser.add_argument("--rewrite-to", required=True)
    parser.add_argument("--rewrite-openai-models", action="store_true")
    parser.add_argument(
        "--no-rewrite-unmapped",
        dest="rewrite_all_unmapped",
        action="store_false",
        help="Disable the catch-all that maps any non-cx/ model to --rewrite-to.",
    )
    parser.set_defaults(rewrite_all_unmapped=True)
    parser.add_argument("--model-catalog")
    args = parser.parse_args()

    handler = ProxyHandler
    handler.target = urlsplit(args.target)
    handler.rewrite_from = set(args.rewrite_from)
    handler.rewrite_map = dict(item.split("=", 1) for item in args.rewrite_map if "=" in item)
    handler.rewrite_to = args.rewrite_to
    handler.rewrite_openai_models = args.rewrite_openai_models
    handler.rewrite_all_unmapped = args.rewrite_all_unmapped
    handler.model_catalog = args.model_catalog

    server = ThreadingHTTPServer((args.host, args.port), handler)
    server.socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.serve_forever()


if __name__ == "__main__":
    main()
