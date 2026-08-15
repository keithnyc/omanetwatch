#!/usr/bin/env python3
"""Run one OmaNetWatch HTTP or TCP check and print one JSON result."""

from __future__ import annotations

import json
import socket
import ssl
import sys
import time
import urllib.error
import urllib.request


def elapsed_ms(started: float) -> int:
    return max(1, round((time.monotonic() - started) * 1000))


def check_http(target: dict) -> dict:
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
            return {
                "ok": status == expected,
                "statusCode": status,
                "latencyMs": elapsed_ms(started),
                "error": "" if status == expected else f"Expected HTTP {expected}, received {status}",
            }
    except urllib.error.HTTPError as error:
        status = int(error.code)
        return {
            "ok": status == expected,
            "statusCode": status,
            "latencyMs": elapsed_ms(started),
            "error": "" if status == expected else f"Expected HTTP {expected}, received {status}",
        }
    except (urllib.error.URLError, TimeoutError, socket.timeout, ssl.SSLError) as error:
        reason = getattr(error, "reason", error)
        return {"ok": False, "latencyMs": elapsed_ms(started), "error": str(reason)}


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
        result = check_http(target) if target.get("type") == "http" else check_tcp(target)
    except Exception as error:  # A malformed local config should still yield a result row.
        result = {"ok": False, "error": str(error)}

    result["checkedAt"] = round(time.time() * 1000)
    result["type"] = target.get("type", "unknown") if isinstance(target, dict) else "unknown"
    print(json.dumps(result, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
