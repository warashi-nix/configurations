import json
import os
import platform
import subprocess
import tempfile
import threading
import unittest
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path


SCRIPT = Path(__file__).parents[1] / "slack-notify.sh"
HOST = platform.node().split(".")[0]


class Webhook(BaseHTTPRequestHandler):
    status = 200

    def do_POST(self):
        body = self.rfile.read(int(self.headers["Content-Length"]))
        self.server.received.append(
            {"path": self.path, "type": self.headers["Content-Type"], "body": json.loads(body)}
        )
        self.send_response(self.server.status)
        self.end_headers()
        self.wfile.write(b"ok")

    def log_message(self, *args):
        pass


class SlackNotifyTest(unittest.TestCase):
    def setUp(self):
        test_tmp = Path(os.environ.get("TEST_TMPDIR", Path.cwd() / ".test-tmp"))
        test_tmp.mkdir(parents=True, exist_ok=True)
        self.temporary = tempfile.TemporaryDirectory(dir=test_tmp)
        self.root = Path(self.temporary.name)
        self.server = HTTPServer(("127.0.0.1", 0), Webhook)
        self.server.received = []
        self.server.status = 200
        threading.Thread(target=self.server.serve_forever, daemon=True).start()
        self.url_file = self.root / "webhook-url"
        self.url_file.write_text(f"http://127.0.0.1:{self.server.server_port}/services/secret\n")

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self.temporary.cleanup()

    def notify(self, *args, stdin=""):
        return subprocess.run(
            ["bash", SCRIPT, *map(str, args)],
            input=stdin, capture_output=True, text=True, timeout=30,
        )

    def test_posts_stdin_as_json_text_prefixed_with_host(self):
        result = self.notify(self.url_file, stdin="依頼が 1 件\n- 鍵を替える\n")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            self.server.received,
            [{
                "path": "/services/secret",
                "type": "application/json",
                "body": {"text": f"[{HOST}] 依頼が 1 件\n- 鍵を替える"},
            }],
        )

    def test_arguments_replace_stdin_as_text(self):
        result = self.notify(self.url_file, "片付いた", "すべて", stdin="読まない")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.server.received[0]["body"]["text"], f"[{HOST}] 片付いた すべて")

    def test_escapes_slack_markup_so_text_cannot_form_links(self):
        result = self.notify(self.url_file, stdin="<https://evil.example|ここ> & <!channel>")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            self.server.received[0]["body"]["text"],
            f"[{HOST}] &lt;https://evil.example|ここ&gt; &amp; &lt;!channel&gt;",
        )

    def test_empty_body_still_notifies(self):
        result = self.notify(self.url_file)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.server.received[0]["body"]["text"], f"[{HOST}] (本文なし)")

    def test_fails_when_webhook_rejects(self):
        self.server.status = 404
        result = self.notify(self.url_file, stdin="x")
        self.assertNotEqual(result.returncode, 0)

    def test_does_not_leak_url_to_output_on_failure(self):
        self.server.status = 500
        result = self.notify(self.url_file, stdin="x")
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("/services/secret", result.stdout + result.stderr)

    def test_rejects_url_that_could_inject_curl_options(self):
        self.url_file.write_text('http://127.0.0.1/"\noutput = "/tmp/x"\n')
        result = self.notify(self.url_file, stdin="x")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.server.received, [])

    def test_fails_without_url_file(self):
        result = self.notify(self.root / "missing", stdin="x")
        self.assertNotEqual(result.returncode, 0)


if __name__ == "__main__":
    unittest.main()
