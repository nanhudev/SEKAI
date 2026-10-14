"""Talk to Suno's private studio API through a logged-in Chrome tab.

The sandbox cannot reach suno.com directly, so every call runs *inside* the
real page via CDP: the page already has the session and the CDN is reachable
through the browser's proxy. The bearer token is captured from the page's own
traffic and kept in memory only (never written to disk, never printed).

Usage:
    python audio_source/tools/suno_api.py list            # all My Workspace clips -> clip_index.json
    python audio_source/tools/suno_api.py today            # only clips created today
    python audio_source/tools/suno_api.py pull <clip_id> <out_path> [--wav]
"""

import argparse
import base64
import json
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from cdp import Page, set_download_path  # noqa: E402

API = "https://studio-api-prod.suno.com/api"
ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
INDEX = os.path.join(ROOT, "audio_source", "suno", "clip_index.json")

CAPTURE_JS = """
window.__sekaiFeed = (body, token) => fetch('%s/feed/v3', {
  method: 'POST',
  headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer ' + token},
  body: JSON.stringify(body),
}).then(r => r.text());
""" % API


def capture_token(page, timeout=40.0):
    """Reload the page and read the Authorization header off its own requests."""
    page.send("Network.enable")
    page.send("Page.reload", {"ignoreCache": False})
    deadline = time.time() + timeout
    page.ws.settimeout(1.0)
    while time.time() < deadline:
        try:
            msg = json.loads(page.ws.recv())
        except Exception:
            continue
        if msg.get("method") != "Network.requestWillBeSent":
            continue
        req = msg["params"]["request"]
        if "studio-api" not in req.get("url", ""):
            continue
        for k, v in req.get("headers", {}).items():
            if k.lower() == "authorization" and v.lower().startswith("bearer "):
                return v.split(" ", 1)[1]
    sys.exit("could not capture a bearer token")


def fetch_feed(page, token, cursor=None, limit=20):
    body = {
        "cursor": cursor,
        "limit": limit,
        "filters": {
            "disliked": "False",
            "trashed": "False",
            "fromStudioProject": {"presence": "False"},
            "stem": {"presence": "False"},
            "stemComplement": "False",
            "workspace": {"presence": "True", "workspaceId": "default"},
        },
    }
    page.eval(CAPTURE_JS)
    raw = page.eval("window.__sekaiFeed(%s, %s)" % (json.dumps(body), json.dumps(token)))
    return json.loads(raw)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("command")
    parser.add_argument("args", nargs="*")
    parser.add_argument("--wav", action="store_true", help="pull the wav variant when available")
    parser.add_argument("--proxy", default="socks5h://127.0.0.1:10808",
                        help="local proxy used by curl to reach the Suno CDN")
    ns = parser.parse_args()

    page = Page("suno")
    try:
        if ns.command in ("list", "today"):
            token = capture_token(page)
            clips = []
            cursor = None
            for _ in range(30):
                data = fetch_feed(page, token, cursor)
                batch = data.get("clips", [])
                clips.extend(batch)
                cursor = data.get("next_cursor")
                if not cursor or not batch:
                    break
            with open(INDEX, "w", encoding="utf-8") as f:
                json.dump(clips, f, ensure_ascii=False, indent=1)
            rows = [(c.get("id"), c.get("created_at", "")[:19], c.get("metadata", {}).get("duration"),
                     (c.get("title") or "")[:64]) for c in clips]
            if ns.command == "today":
                day = time.strftime("%Y-%m-%d")
                rows = [r for r in rows if r[1].startswith(day)]
            for r in rows:
                print("%s  %s  %ss  %s" % r)
            print("-- total %d clip(s), index -> %s" % (len(rows), INDEX))
        elif ns.command in ("pull", "pull_all"):
            clips = json.load(open(INDEX, encoding="utf-8"))
            if ns.command == "pull":
                wanted = [c for c in clips if c.get("id") == ns.args[0]]
                if not wanted:
                    sys.exit("clip %s not in index" % ns.args[0])
            else:
                day = ns.args[0] if ns.args else time.strftime("%Y-%m-%d")
                wanted = [c for c in clips if c.get("created_at", "").startswith(day)]
            raw_dir = os.path.join(ROOT, "audio_source", "suno", "raw")
            os.makedirs(raw_dir, exist_ok=True)
            ffmpeg = os.environ.get("FFMPEG", r"D:\oopz\ffmpeg.exe")
            for clip in wanted:
                media = (clip.get("media_urls") or [{}])[0].get("url")
                if not media:
                    print("skip %s (no media url)" % clip.get("id"))
                    continue
                m4a = os.path.join(raw_dir, clip["id"] + ".m4a")
                wav = os.path.join(raw_dir, clip["id"] + ".wav")
                if not os.path.exists(m4a):
                    import subprocess
                    subprocess.run(["curl", "-s", "--max-time", "60",
                                    "-x", ns.proxy, "-o", m4a, media], check=False)
                if os.path.exists(wav):
                    continue
                import subprocess
                subprocess.run([ffmpeg, "-hide_banner", "-loglevel", "error", "-y",
                                "-i", m4a, "-ar", "44100", "-ac", "1", wav], check=False)
                print("%s  %.1fs  %s" % (clip["id"], clip.get("metadata", {}).get("duration") or 0,
                                         (clip.get("title") or "")[:60]))
        elif ns.command == "fields":
            token = capture_token(page)
            data = fetch_feed(page, token)
            clip = data["clips"][0]
            print(json.dumps({k: (str(v)[:120] if not isinstance(v, (dict, list)) else type(v).__name__)
                              for k, v in clip.items()}, indent=1, ensure_ascii=False))
        elif ns.command == "probe":
            clip_id = ns.args[0]
            token = capture_token(page)
            page.eval("""window.__sekaiProbe = async (url, method, token) => {
                try {
                    const r = await fetch(url, {method: method, headers: {'Authorization': 'Bearer ' + token}});
                    const t = await r.text();
                    return r.status + ' ' + t.slice(0, 300);
                } catch (e) { return 'ERR ' + e.message; }
            };""")
            candidates = [
                ("POST", "%s/clip/%s/download/" % (API, clip_id)),
                ("GET", "%s/clip/%s/download/" % (API, clip_id)),
                ("POST", "%s/clips/%s/download/" % (API, clip_id)),
                ("POST", "%s/gen/%s/download/" % (API, clip_id)),
                ("GET", "%s/clips/%s/" % (API, clip_id)),
            ]
            for method, url in candidates:
                got = page.eval("window.__sekaiProbe(%s, %s, %s)" % (json.dumps(url), json.dumps(method), json.dumps(token)))
                print("%s %s -> %s" % (method, url.replace(API, ""), str(got)[:200]))
        else:
            sys.exit("unknown command %s" % ns.command)
    finally:
        page.close()


if __name__ == "__main__":
    main()
