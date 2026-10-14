"""Minimal Chrome DevTools Protocol driver (audio line tool).

Used to drive Suno in a real, logged-in Chrome that was started with
`--remote-debugging-port=9222`. agent-browser's `--cdp` attach hangs in this
environment, so this speaks CDP directly over the WebSocket endpoint.

Usage:
    python audio_source/tools/cdp.py tabs
    python audio_source/tools/cdp.py shot out.png [--match suno]
    python audio_source/tools/cdp.py eval "document.title" [--match suno]
    python audio_source/tools/cdp.py nav https://suno.com/create
    python audio_source/tools/cdp.py click "button[type=submit]"
    python audio_source/tools/cdp.py clickxy 640 480
    python audio_source/tools/cdp.py type "text" [--submit]
    python audio_source/tools/cdp.py key Enter
    python audio_source/tools/cdp.py wait 3
"""

import argparse
import base64
import json
import sys
import time
import urllib.request

import websocket

PORT = 9222

# The host environment exports an HTTP proxy that answers 502 for localhost;
# CDP must always be reached directly.
_DIRECT = urllib.request.build_opener(urllib.request.ProxyHandler({}))


def http_json(path):
    with _DIRECT.open("http://127.0.0.1:%d%s" % (PORT, path), timeout=10) as r:
        return json.loads(r.read().decode("utf-8"))


def pick_target(match=None):
    targets = [t for t in http_json("/json/list") if t.get("type") == "page"]
    if not targets:
        sys.exit("no page targets")
    if match:
        for t in targets:
            if match.lower() in (t.get("url", "") + " " + t.get("title", "")).lower():
                return t
        sys.exit("no page matching %r" % match)
    for t in targets:
        if "suno" in t.get("url", "").lower():
            return t
    return targets[0]


class Page:
    def __init__(self, match=None):
        self.target = pick_target(match)
        self.ws = websocket.create_connection(self.target["webSocketDebuggerUrl"],
                                             timeout=30, max_size=64 * 1024 * 1024,
                                             suppress_origin=True)
        self.seq = 0
        self.send("Page.enable")
        self.send("Runtime.enable")

    def send(self, method, params=None):
        self.seq += 1
        self.ws.send(json.dumps({"id": self.seq, "method": method, "params": params or {}}))
        while True:
            msg = json.loads(self.ws.recv())
            if msg.get("id") == self.seq:
                if "error" in msg:
                    raise RuntimeError("%s -> %s" % (method, msg["error"]))
                return msg.get("result", {})

    def eval(self, expression):
        res = self.send("Runtime.evaluate", {
            "expression": expression,
            "returnByValue": True,
            "awaitPromise": True,
        })
        return res.get("result", {}).get("value")

    def screenshot(self, path):
        res = self.send("Page.captureScreenshot", {"format": "png"})
        with open(path, "wb") as f:
            f.write(base64.b64decode(res["data"]))
        return path

    def mouse(self, kind, x, y, button="left", clicks=1):
        self.send("Input.dispatchMouseEvent", {
            "type": kind, "x": x, "y": y, "button": button,
            "buttons": 1 if kind != "mouseReleased" else 0,
            "clickCount": clicks,
        })

    def click_xy(self, x, y):
        self.send("Input.dispatchMouseEvent", {"type": "mouseMoved", "x": x, "y": y, "buttons": 0})
        time.sleep(0.15)
        self.mouse("mousePressed", x, y)
        time.sleep(0.05)
        self.mouse("mouseReleased", x, y)

    def click_selector(self, selector):
        box = self.eval("""(() => {
            const el = document.querySelector(%s);
            if (!el) return null;
            el.scrollIntoView({block:'center'});
            const r = el.getBoundingClientRect();
            return {x: r.x + r.width/2, y: r.y + r.height/2, w: r.width, h: r.height};
        })()""" % json.dumps(selector))
        if not box or box["w"] == 0:
            return False
        self.click_xy(box["x"], box["y"])
        return True

    def insert_text(self, text):
        self.send("Input.insertText", {"text": text})

    def key(self, name):
        self.send("Input.dispatchKeyEvent", {"type": "keyDown", "key": name,
                                             "code": name, "windowsVirtualKeyCode": 13 if name == "Enter" else 0})
        self.send("Input.dispatchKeyEvent", {"type": "keyUp", "key": name,
                                             "code": name, "windowsVirtualKeyCode": 13 if name == "Enter" else 0})

    def close(self):
        try:
            self.ws.close()
        except Exception:
            pass


def set_download_path(path):
    """Browser-level command: send every download to `path`."""
    ws = websocket.create_connection(http_json("/json/version")["webSocketDebuggerUrl"],
                                     timeout=20, suppress_origin=True)
    try:
        ws.send(json.dumps({"id": 1, "method": "Browser.setDownloadBehavior",
                            "params": {"behavior": "allow", "downloadPath": path,
                                       "eventsEnabled": True}}))
        while True:
            msg = json.loads(ws.recv())
            if msg.get("id") == 1:
                return msg
    finally:
        ws.close()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("command")
    parser.add_argument("args", nargs="*")
    parser.add_argument("--match", default=None, help="substring of url/title to pick the tab")
    parser.add_argument("--filter", dest="filter_", default=None, help="url substring filter for the net command")
    parser.add_argument("--submit", action="store_true", help="press Enter after typing")
    ns = parser.parse_args()

    if ns.command == "tabs":
        for t in http_json("/json/list"):
            if t.get("type") == "page":
                print("%s | %s" % (t.get("title", "")[:60], t.get("url", "")[:110]))
        return

    if ns.command == "dl":
        print(set_download_path(ns.args[0]))
        return

    page = Page(ns.match)
    try:
        if ns.command == "grab":
            # capture the response body of a matching network request
            out_path, seconds = ns.args[0], float(ns.args[1])
            page.send("Network.enable")
            page.ws.settimeout(1.0)
            requests = {}   # requestId -> url
            finished = []   # requestIds that completed
            deadline = time.time() + seconds
            while time.time() < deadline:
                try:
                    msg = json.loads(page.ws.recv())
                except Exception:
                    continue
                m = msg.get("method", "")
                if m == "Network.requestWillBeSent":
                    p = msg["params"]
                    url = p["request"].get("url", "")
                    if ns.filter_ and ns.filter_ in url:
                        requests[p["requestId"]] = url
                elif m == "Network.loadingFinished":
                    rid = msg["params"]["requestId"]
                    if rid in requests:
                        finished.append(rid)
            if not finished:
                print("no matching response captured")
                return
            rid = finished[-1]
            body = page.send("Network.getResponseBody", {"requestId": rid})
            data = base64.b64decode(body["body"]) if body.get("base64Encoded") \
                else body["body"].encode("utf-8")
            with open(out_path, "wb") as f:
                f.write(data)
            print("saved %s (%d bytes) from %s" % (out_path, len(data), requests[rid][:120]))
        elif ns.command == "net":
            seconds = float(ns.args[0]) if ns.args else 8.0
            page.send("Network.enable")
            deadline = time.time() + seconds
            seen = []
            page.ws.settimeout(1.0)
            while time.time() < deadline:
                try:
                    msg = json.loads(page.ws.recv())
                except Exception:
                    continue
                m = msg.get("method")
                if m == "Network.requestWillBeSent":
                    req = msg["params"]["request"]
                    url = req.get("url", "")
                    if ns.filter_ and ns.filter_ not in url:
                        continue
                    seen.append((req.get("method"), url, req.get("headers", {}),
                                 (req.get("postData") or "")[:600]))
            out = []
            for method, url, headers, post in seen[-40:]:
                auth = ""
                for k, v in headers.items():
                    if k.lower() == "authorization":
                        auth = v
                out.append("%s %s%s%s" % (method, url[:150],
                                          ("  AUTH=" + auth[:40] + "...") if auth else "",
                                          ("  BODY=" + post) if post else ""))
            print("\n".join(out) if out else "no matching requests")
        elif ns.command == "shot":
            print("saved", page.screenshot(ns.args[0]))
        elif ns.command == "eval":
            print(json.dumps(page.eval(ns.args[0]), ensure_ascii=False))
        elif ns.command == "nav":
            page.send("Page.navigate", {"url": ns.args[0]})
            time.sleep(3)
        elif ns.command == "click":
            print("clicked" if page.click_selector(ns.args[0]) else "selector not found")
        elif ns.command == "clickjs":
            # evaluate a JS expression returning {x,y} and click it in the same
            # session, so React cannot re-render between lookup and click
            box = page.eval(ns.args[0])
            if not box:
                print("no target")
            else:
                page.click_xy(box["x"], box["y"])
                print("clicked %d,%d" % (box["x"], box["y"]))
        elif ns.command == "clickxy":
            page.click_xy(float(ns.args[0]), float(ns.args[1]))
        elif ns.command == "type":
            page.insert_text(ns.args[0])
            if ns.submit:
                time.sleep(0.3)
                page.key("Enter")
        elif ns.command == "key":
            page.key(ns.args[0])
        elif ns.command == "wait":
            time.sleep(float(ns.args[0]))
        else:
            sys.exit("unknown command %s" % ns.command)
    finally:
        page.close()


if __name__ == "__main__":
    main()
