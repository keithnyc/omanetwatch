#!/usr/bin/env python3
"""Run one OmaNetWatch HTTP, TCP, or structured JSON status check."""

from __future__ import annotations

import json
import socket
import ssl
import sys
import time
import urllib.error
import urllib.request

MAX_RESPONSE_BYTES = 1024 * 1024


def elapsed_ms(started: float) -> int:
    return max(1, round((time.monotonic() - started) * 1000))


def http_request(target: dict, read_body: bool = False) -> tuple[int, int, bytes, str]:
    started = time.monotonic()
    expected = int(target.get("expectedStatus", 200))
    request = urllib.request.Request(
        target["url"],
        headers={"User-Agent": "OmaNetWatch/0.1"},
        method="GET",
    )
    try:
        with urllib.request.urlopen(request, timeout=float(target["timeoutSeconds"])) as response:
            status = int(response.status)
            body = response.read(MAX_RESPONSE_BYTES + 1) if read_body else b""
            if read_body and len(body) > MAX_RESPONSE_BYTES:
                raise ValueError("Response exceeds 1 MiB limit")
            charset = response.headers.get_content_charset() or "utf-8"
            return status, elapsed_ms(started), body, charset
    except urllib.error.HTTPError as error:
        status = int(error.code)
        if status != expected:
            error.close()
            raise
        body = error.read(MAX_RESPONSE_BYTES + 1) if read_body else b""
        if read_body and len(body) > MAX_RESPONSE_BYTES:
            raise ValueError("Response exceeds 1 MiB limit")
        charset = error.headers.get_content_charset() or "utf-8"
        return status, elapsed_ms(started), body, charset


def check_http(target: dict) -> dict:
    started = time.monotonic()
    expected = int(target.get("expectedStatus", 200))
    try:
        status, latency, _, _ = http_request(target)
        return {
            "ok": status == expected,
            "state": "operational" if status == expected else "outage",
            "statusCode": status,
            "latencyMs": latency,
            "error": "" if status == expected else f"Expected HTTP {expected}, received {status}",
        }
    except urllib.error.HTTPError as error:
        status = int(error.code)
        return {
            "ok": False,
            "state": "outage",
            "statusCode": status,
            "latencyMs": elapsed_ms(started),
            "error": f"Expected HTTP {expected}, received {status}",
        }
    except (urllib.error.URLError, TimeoutError, socket.timeout, ssl.SSLError) as error:
        reason = getattr(error, "reason", error)
        return {"ok": False, "state": "outage", "latencyMs": elapsed_ms(started), "error": str(reason)}


def path_value(document: object, path: str) -> object:
    if path.startswith("/"):
        parts = [part.replace("~1", "/").replace("~0", "~") for part in path[1:].split("/")]
    else:
        parts = path.split(".")
    value = document
    for part in parts:
        if isinstance(value, dict) and part in value:
            value = value[part]
        elif isinstance(value, list) and part.isdigit() and int(part) < len(value):
            value = value[int(part)]
        else:
            raise KeyError(path)
    return value


def scalar_text(value: object, limit: int, field_name: str) -> str:
    if isinstance(value, (dict, list)):
        raise ValueError(f"{field_name} must select a scalar value")
    if value is None:
        text = "null"
    elif value is True:
        text = "true"
    elif value is False:
        text = "false"
    else:
        text = str(value)
    if len(text) > limit:
        raise ValueError(f"Selected JSON value exceeds {limit} character limit")
    return text


def check_json(target: dict) -> dict:
    started = time.monotonic()
    expected = int(target.get("expectedStatus", 200))
    try:
        status, latency, body, charset = http_request(target, read_body=True)
        if status != expected:
            return {
                "ok": False,
                "state": "unknown",
                "statusCode": status,
                "latencyMs": latency,
                "error": f"Expected HTTP {expected}, received {status}",
            }
        document = json.loads(body.decode(charset))
        reported = scalar_text(path_value(document, str(target["statusPath"])), 256, "statusPath")
        state = str(target.get("statusMap", {}).get(reported, "unknown")).lower()
        if state not in {"operational", "degraded", "outage", "unknown"}:
            state = "unknown"
        reason = ""
        if target.get("reasonPath"):
            reason = scalar_text(path_value(document, str(target["reasonPath"])), 512, "reasonPath")
        error = "" if state == "operational" else reason
        if state == "unknown" and not error:
            error = f"Unrecognized status value {reported!r}"
        return {
            "ok": state == "operational",
            "state": state,
            "statusValue": reported,
            "reason": reason,
            "statusCode": status,
            "latencyMs": latency,
            "error": error,
        }
    except urllib.error.HTTPError as error:
        error.close()
        return {
            "ok": False,
            "state": "unknown",
            "statusCode": int(error.code),
            "latencyMs": elapsed_ms(started),
            "error": f"Expected HTTP {expected}, received {int(error.code)}",
        }
    except KeyError as error:
        return {
            "ok": False,
            "state": "unknown",
            "latencyMs": elapsed_ms(started),
            "error": f"JSON field not found: {error.args[0]}",
        }
    except (UnicodeError, json.JSONDecodeError, ValueError) as error:
        return {"ok": False, "state": "unknown", "latencyMs": elapsed_ms(started), "error": str(error)}
    except (urllib.error.URLError, TimeoutError, socket.timeout, ssl.SSLError) as error:
        reason = getattr(error, "reason", error)
        return {"ok": False, "state": "unknown", "latencyMs": elapsed_ms(started), "error": str(reason)}


def check_tcp(target: dict) -> dict:
    started = time.monotonic()
    try:
        with socket.create_connection(
            (target["host"], int(target["port"])),
            timeout=float(target["timeoutSeconds"]),
        ):
            return {"ok": True, "latencyMs": elapsed_ms(started), "error": ""}
    except (OSError, TimeoutError, socket.timeout) as error:
        return {"ok": False, "latencyMs": elapsed_ms(started), "error": str(error)}


def main() -> int:
    if len(sys.argv) != 2:
        print(json.dumps({"ok": False, "error": "expected one target JSON argument"}))
        return 2

    target: dict = {}
    try:
        target = json.loads(sys.argv[1])
        target_type = target.get("type")
        if target_type == "http":
            result = check_http(target)
        elif target_type == "json":
            result = check_json(target)
        else:
            result = check_tcp(target)
    except Exception as error:  # A malformed local config should still yield a result row.
        result = {"ok": False, "error": str(error)}

    result["checkedAt"] = round(time.time() * 1000)
    result["type"] = target.get("type", "unknown") if isinstance(target, dict) else "unknown"
    print(json.dumps(result, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
