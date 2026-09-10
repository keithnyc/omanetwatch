#!/usr/bin/env python3

import importlib.util
import json
import pathlib
import threading
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


ROOT = pathlib.Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("omanetwatch_checker", ROOT / "scripts/check_endpoint.py")
CHECKER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CHECKER)


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        responses = {
            "/operational": (200, {"status": {"indicator": "none", "description": "All good"}}),
            "/degraded": (200, {"status": {"indicator": "minor", "description": "API delays"}}),
            "/unmapped": (200, {"status": {"indicator": "mystery"}}),
            "/missing": (200, {"other": "none"}),
        }
        if self.path == "/invalid":
            status, body = 200, b"not json"
        elif self.path == "/large":
            status, body = 200, b" " * (CHECKER.MAX_RESPONSE_BYTES + 1)
        elif self.path == "/error":
            status, body = 503, b"unavailable"
        else:
            status, document = responses.get(self.path, (404, {}))
            body = json.dumps(document).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *_):
        pass


class CheckerTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()
        cls.base = f"http://127.0.0.1:{cls.server.server_port}"

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()

    def target(self, path, **overrides):
        target = {
            "type": "json",
            "url": self.base + path,
            "expectedStatus": 200,
            "timeoutSeconds": 2,
            "statusPath": "status.indicator",
            "reasonPath": "status.description",
            "statusMap": {"none": "operational", "minor": "degraded"},
        }
        target.update(overrides)
        return target

    def test_operational_dot_path(self):
        result = CHECKER.check_json(self.target("/operational"))
        self.assertTrue(result["ok"])
        self.assertEqual(result["state"], "operational")
        self.assertEqual(result["reason"], "All good")

    def test_degraded_json_pointer(self):
        result = CHECKER.check_json(self.target(
            "/degraded", statusPath="/status/indicator", reasonPath="/status/description"
        ))
        self.assertFalse(result["ok"])
        self.assertEqual(result["state"], "degraded")
        self.assertEqual(result["reason"], "API delays")

    def test_unmapped_value_is_unknown(self):
        result = CHECKER.check_json(self.target("/unmapped", reasonPath=""))
        self.assertEqual(result["state"], "unknown")
        self.assertIn("mystery", result["error"])

    def test_missing_field_is_unknown(self):
        result = CHECKER.check_json(self.target("/missing"))
        self.assertEqual(result["state"], "unknown")
        self.assertIn("status.indicator", result["error"])

    def test_invalid_json_is_unknown(self):
        result = CHECKER.check_json(self.target("/invalid"))
        self.assertEqual(result["state"], "unknown")

    def test_http_error_is_unknown(self):
        result = CHECKER.check_json(self.target("/error"))
        self.assertEqual(result["state"], "unknown")
        self.assertEqual(result["statusCode"], 503)

    def test_oversized_response_is_unknown(self):
        result = CHECKER.check_json(self.target("/large"))
        self.assertEqual(result["state"], "unknown")
        self.assertIn("1 MiB", result["error"])

    def test_existing_http_success_behavior(self):
        result = CHECKER.check_http(self.target("/operational"))
        self.assertTrue(result["ok"])
        self.assertEqual(result["state"], "operational")

    def test_existing_http_failure_behavior(self):
        result = CHECKER.check_http(self.target("/error"))
        self.assertFalse(result["ok"])
        self.assertEqual(result["state"], "outage")


if __name__ == "__main__":
    unittest.main()
