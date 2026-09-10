#!/usr/bin/env python3
"""Run one OmaNetWatch HTTP, TCP, or structured JSON status check."""

from __future__ import annotations

import hashlib
from html.parser import HTMLParser
import json
import re
import socket
import ssl
import sys
import time
import urllib.error
import urllib.request
import xml.etree.ElementTree as ET

MAX_RESPONSE_BYTES = 1024 * 1024


class FeedTextParser(HTMLParser):
    """Turn the small HTML fragments commonly embedded in feeds into lines."""

    BLOCK_TAGS = {"br", "div", "h1", "h2", "h3", "h4", "h5", "h6", "li", "p", "hr"}

    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.parts: list[str] = []

    def handle_starttag(self, tag: str, _attrs: list[tuple[str, str | None]]) -> None:
        if tag.lower() in self.BLOCK_TAGS:
            self.parts.append("\n")

    def handle_endtag(self, tag: str) -> None:
        if tag.lower() in self.BLOCK_TAGS:
            self.parts.append("\n")

    def handle_data(self, data: str) -> None:
        self.parts.append(data)


def feed_item_status(content: str) -> str:
    """Extract an explicitly labelled incident status from an item body."""
    parser = FeedTextParser()
    parser.feed(content)
    parser.close()
    for line in "".join(parser.parts).splitlines():
        match = re.fullmatch(r"\s*status\s*:\s*(.{1,64}?)\s*", line, re.IGNORECASE)
        if match:
            value = " ".join(match.group(1).split())
            return value.title() if value.isupper() or value.islower() else value
    return ""


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


def local_name(tag: str) -> str:
    return tag.rsplit("}", 1)[-1].lower()


def child_text(element: ET.Element, *names: str) -> str:
    wanted = {name.lower() for name in names}
    for child in element:
        if local_name(child.tag) in wanted:
            return "".join(child.itertext()).strip()
    return ""


def item_link(element: ET.Element) -> str:
    for child in element:
        if local_name(child.tag) != "link":
            continue
        href = str(child.attrib.get("href", "")).strip()
        rel = str(child.attrib.get("rel", "alternate")).lower()
        if href and rel in {"", "alternate"}:
            return href
        text = "".join(child.itertext()).strip()
        if text:
            return text
    return ""


def parse_feed(body: bytes) -> tuple[str, list[dict]]:
    # ElementTree does not fetch external entities. The shared HTTP helper also
    # caps input at 1 MiB before XML parsing.
    root = ET.fromstring(body)
    root_name = local_name(root.tag)
    if root_name == "rss":
        container = next((child for child in root if local_name(child.tag) == "channel"), None)
        if container is None:
            raise ValueError("RSS feed has no channel")
        feed_title = child_text(container, "title")
        elements = [child for child in container if local_name(child.tag) == "item"]
    elif root_name == "feed":
        container = root
        feed_title = child_text(container, "title")
        elements = [child for child in container if local_name(child.tag) == "entry"]
    elif root_name == "rdf":
        channel = next((child for child in root if local_name(child.tag) == "channel"), None)
        feed_title = child_text(channel, "title") if channel is not None else ""
        elements = [child for child in root if local_name(child.tag) == "item"]
    else:
        raise ValueError("Response is not an RSS or Atom feed")

    items = []
    for element in elements[:50]:
        title = child_text(element, "title")[:512]
        link = item_link(element)[:2048]
        published = child_text(element, "updated", "pubdate", "published", "date")[:256]
        content = child_text(element, "content", "description", "summary", "encoded")
        item_status = feed_item_status(content)
        item_id = child_text(element, "guid", "id") or link
        if not item_id:
            item_id = hashlib.sha256((title + "\x1f" + published).encode()).hexdigest()
        fingerprint = hashlib.sha256(
            "\x1f".join((title, link, published, content)).encode()
        ).hexdigest()
        items.append({
            "id": item_id[:2048],
            "title": title or "Untitled feed item",
            "link": link,
            "published": published,
            "status": item_status,
            "fingerprint": fingerprint,
        })
    return feed_title[:512], items


def check_feed(target: dict) -> dict:
    started = time.monotonic()
    expected = int(target.get("expectedStatus", 200))
    try:
        status, latency, body, _ = http_request(target, read_body=True)
        if status != expected:
            return {
                "ok": False,
                "state": "unknown",
                "statusCode": status,
                "latencyMs": latency,
                "error": f"Expected HTTP {expected}, received {status}",
            }
        feed_title, items = parse_feed(body)
        return {
            "ok": True,
            "state": "operational",
            "statusCode": status,
            "latencyMs": latency,
            "feedTitle": feed_title,
            "items": items,
            "error": "",
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
    except (UnicodeError, ET.ParseError, ValueError) as error:
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
        elif target_type == "feed":
            result = check_feed(target)
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
