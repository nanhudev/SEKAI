from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path

TARGET = Path(r"F:\SEKAI\assets\chat2blender\fp_hand_blockout.py")

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        body = b'<html><body><form method="post"><textarea name="code" style="width:90vw;height:70vh"></textarea><button>Save to F drive</button></form></body></html>'
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self):
        from urllib.parse import parse_qs
        length = min(int(self.headers.get("Content-Length", "0")), 100000)
        code = parse_qs(self.rfile.read(length).decode("utf-8")).get("code", [""])[0]
        if not code.startswith("# C2B:CHUNK blockout") or "# C2B:END" not in code:
            self.send_error(400, "Invalid Chat2Blender chunk")
            return
        TARGET.parent.mkdir(parents=True, exist_ok=True)
        TARGET.write_text(code, encoding="utf-8")
        self.send_response(200)
        self.end_headers()
        self.wfile.write(f"Saved {len(code)} characters".encode())

HTTPServer(("127.0.0.1", 8765), Handler).serve_forever()
