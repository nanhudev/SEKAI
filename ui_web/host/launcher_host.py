#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""SEKAI · LAUNCHER HOST
==============================================================================
轻量桌面外壳。做三件事，只做三件事：

  1. 把 ui_web/ 用本地 HTTP 服务起来（页面用 ES module，必须走 http）
  2. 提供四个路由给页面调：/.host.json · /api/preflight · /api/launch · /api/quit
  3. 开一个无标签页的应用窗口（Edge/Chrome 的 --app）

点击「进入世界」时真的会拉起 Godot —— 这是 §43 的验收点。

------------------------------------------------------------------------------
为什么不用 pywebview / Electron / Tauri（§26 要求先审计）

  Tauri       需要 Rust 工具链 —— 本机未安装，且为一个启动器引入整个 Rust
              生态不值得。
  Electron    约 300MB 运行时，为一个三秒的启动页不值得。
  pywebview   在 Windows 上要靠 pythonnet 才有 WebView2 后端；pythonnet 是一层
              .NET 互操作依赖，挑 Python 版本（3.13 无轮子），是本项目里最容易
              坏掉的一环。
  **本方案**  零第三方依赖。宿主本来就要起 HTTP 服务，多四个路由就是完整的双向桥。
              窗口用系统已装的 WebView2/Edge，`--app=` 本身就是无标签页应用窗口。

------------------------------------------------------------------------------
失败处理（§44）

  Launcher 绝不允许死在无限 loading。preflight 会在开门之前检查
  Godot 可执行文件与工程目录；启动后还会**看着 Godot 头 1.2 秒**，
  如果它立刻退出，就把 stderr 尾部作为 detail 报回去，
  并且**不关闭 Launcher** —— 玩家看到的是克制的错误，不是黑屏。

用法
    python launcher_host.py                     # 正式玩家视角
    python launcher_host.py --dev               # 显示训练场 / 雾谷检视 / 战斗沙盒
    python launcher_host.py --no-window         # 只起服务，自己开浏览器（调试用）
    python launcher_host.py --godot <path> --project <dir>
==============================================================================
"""

from __future__ import annotations

import argparse
import json
import mimetypes
import os
import re
import shutil
import socket
import subprocess
import sys
import threading
import time
import webbrowser
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

# ---------------------------------------------------------------------------
# 路径
# ---------------------------------------------------------------------------
HERE = Path(__file__).resolve().parent
REPO = HERE.parent.parent                 # ui_web/host/ -> ui_web/ -> SEKAI/
UI_ROOT = HERE.parent                     # ui_web/

DEFAULT_GODOT = r"G:\Godot\Godot_v4.4.1-stable_win64.exe"
DEFAULT_PROJECT = str(REPO / "godot")
API_VERSION = "0.3.0-ui01"
BUILD = "2026-09-27"

# Godot 用户目录（存档在这里。工程名见 project.godot 的 application/config/name）
USERDATA = Path(os.environ.get("APPDATA", "")) / "Godot" / "app_userdata" / "SEKAI Combat Prototype"

# 启动目标。main 是正式玩家唯一能看到的。
TARGETS = [
    {"id": "main", "label": "进入世界", "en": "ENTER WORLD", "primary": True},
    {"id": "training", "label": "训练场", "en": "TRAINING GROUND", "dev": True},
    {"id": "mistvale", "label": "雾谷实机检视", "en": "MISTVALE REVIEW", "dev": True},
    {"id": "combat", "label": "战斗沙盒", "en": "COMBAT SANDBOX", "dev": True},
]

# 各目标对应的启动场景（Godot 侧读 --target= 决定去哪个场景；这里只传参）
TARGET_IDS = {t["id"] for t in TARGETS}


# ---------------------------------------------------------------------------
# 状态（被 HTTP 线程与主线程共享）
# ---------------------------------------------------------------------------
class State:
    def __init__(self, args: argparse.Namespace):
        self.args = args
        self.godot = Path(args.godot) if args.godot else Path(DEFAULT_GODOT)
        self.project = Path(args.project) if args.project else Path(DEFAULT_PROJECT)
        self.dev_mode = bool(args.dev)
        self.proc: subprocess.Popen | None = None
        self.log_path: Path | None = None
        self.httpd: ThreadingHTTPServer | None = None
        self.port = 0
        self.should_quit = threading.Event()
        self.lock = threading.Lock()
        self.log_lines: list[str] = []


STATE: State | None = None


# ---------------------------------------------------------------------------
# 宿主配置 -> 页面读的 .host.json
# ---------------------------------------------------------------------------
def read_save() -> dict:
    """读存档摘要。

    **只读**。真正的存档读写归 MAIN 线；这里只是让「继续」能显示
    「上一次停在哪里」。文件不存在就诚实地报 exists=False ——
    不要为了界面好看而谎报有存档（那样点进去会是新游戏，更糟）。

    约定路径：<app_userdata>/save/slot0.json
    可选键：  location / location_en / playtime / updated
    """
    p = USERDATA / "save" / "slot0.json"
    try:
        data = json.loads(p.read_text(encoding="utf-8"))
    except Exception:
        return {"exists": False}
    return {
        "exists": True,
        "location": data.get("location") or "—",
        "locationEn": data.get("location_en") or "",
        "playtime": data.get("playtime") or "—",
    }


def build_config(st: State) -> dict:
    return {
        "mode": "native",
        "version": API_VERSION,
        "build": BUILD,
        "devMode": st.dev_mode,
        "godot": str(st.godot),
        "project": str(st.project),
        "save": read_save(),
        "targets": TARGETS,
    }


# ---------------------------------------------------------------------------
# 预检
# ---------------------------------------------------------------------------
def do_preflight(st: State) -> dict:
    """必须在开门之前能回答：这台机器现在能不能进游戏。

    逐项检查并给出**具体**的缺失项（哪个路径不存在），因为「无法进入世界」
    这四个字本身没有任何可操作性。
    """
    problems = []
    if not st.godot.exists():
        problems.append(f"Godot 可执行文件不存在：{st.godot}")
    elif not os.access(st.godot, os.X_OK):
        problems.append(f"Godot 可执行文件不可执行：{st.godot}")

    if not st.project.is_dir():
        problems.append(f"工程目录不存在：{st.project}")
    elif not (st.project / "project.godot").exists():
        problems.append(f"不是 Godot 工程（没有 project.godot）：{st.project}")

    if problems:
        return {"ok": False, "error": "preflight failed", "detail": "；".join(problems)}
    return {"ok": True, "detail": f"{st.godot.name} · {st.project}"}


# ---------------------------------------------------------------------------
# 启动游戏
# ---------------------------------------------------------------------------
def do_launch(st: State, target: str) -> dict:
    """真的拉起 Godot。返回 {ok, error, detail}，**永不抛**。"""
    if target not in TARGET_IDS:
        return {"ok": False, "error": "unknown target", "detail": f"target={target!r}"}

    pre = do_preflight(st)
    if not pre.get("ok"):
        return pre

    with st.lock:
        if st.proc is not None and st.proc.poll() is None:
            return {"ok": False, "error": "already running", "detail": f"pid={st.proc.pid}"}

    log_dir = REPO / ".render"
    log_dir.mkdir(parents=True, exist_ok=True)
    log_path = log_dir / "launcher_godot.log"
    st.log_path = log_path

    # `--` 之后是用户参数。Godot 用 OS.get_cmdline_user_args() 取。
    cmd = [
        str(st.godot),
        "--path",
        str(st.project),
        "--",
        f"--target={target}",
    ]

    try:
        log_fh = open(log_path, "w", encoding="utf-8", errors="replace")
        proc = subprocess.Popen(
            cmd,
            cwd=str(st.project),
            stdout=log_fh,
            stderr=subprocess.STDOUT,
            # Windows: 不要弹出控制台窗口
            creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0),
        )
    except Exception as exc:  # noqa: BLE001 - 这里就是要兜住一切
        return {"ok": False, "error": "spawn failed", "detail": str(exc)}

    with st.lock:
        st.proc = proc

    # 看头 1.2 秒：立刻退出 = 起不来。这样玩家不会看到"启动器关了但什么都没发生"。
    deadline = time.time() + 1.2
    while time.time() < deadline:
        if proc.poll() is not None:
            break
        time.sleep(0.05)

    if proc.poll() is not None:
        tail = tail_of(log_path, 12)
        return {
            "ok": False,
            "error": f"Godot exited immediately (code {proc.returncode})",
            "detail": tail or "（没有输出）",
        }

    return {"ok": True, "detail": f"pid={proc.pid} target={target} log={log_path}"}


def tail_of(path: Path, n: int = 12) -> str:
    try:
        text = path.read_text(encoding="utf-8", errors="replace")
    except Exception:
        return ""
    lines = [ln for ln in text.splitlines() if ln.strip()]
    return "\n".join(lines[-n:])


# ---------------------------------------------------------------------------
# HTTP：静态文件 + 四个路由
# ---------------------------------------------------------------------------
class Handler(BaseHTTPRequestHandler):
    server_version = "SekaiLauncherHost"

    # 让日志安静一点，只报错误
    def log_message(self, fmt, *args):  # noqa: A003
        if self.server.verbose:  # type: ignore[attr-defined]
            sys.stderr.write("  %s\n" % (fmt % args))

    # --------------------------------------------------------------- 工具
    def _json(self, code: int, payload: dict) -> None:
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(code)
        self.send_header("content-type", "application/json; charset=utf-8")
        self.send_header("content-length", str(len(body)))
        self.send_header("cache-control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def _read_json(self) -> dict:
        length = int(self.headers.get("content-length") or 0)
        if length <= 0:
            return {}
        try:
            return json.loads(self.rfile.read(length).decode("utf-8"))
        except Exception:
            return {}

    def _serve_file(self, rel: str) -> None:
        st = STATE
        assert st is not None
        if rel in ("", "/"):
            rel = "/launcher/index.html"

        # 归一化并挡住目录穿越
        target = (UI_ROOT / rel.lstrip("/")).resolve()
        try:
            target.relative_to(UI_ROOT.resolve())
        except ValueError:
            self._text(403, "forbidden")
            return

        if not target.is_file():
            self._text(404, f"not found: {rel}")
            return

        ctype, _ = mimetypes.guess_type(str(target))
        if target.suffix == ".mjs":
            ctype = "text/javascript"
        if ctype and ctype.startswith("text/") or ctype in (
            "application/javascript",
            "application/json",
            "image/svg+xml",
        ):
            ctype = f"{ctype}; charset=utf-8"

        data = target.read_bytes()
        self.send_response(200)
        self.send_header("content-type", ctype or "application/octet-stream")
        self.send_header("content-length", str(len(data)))
        self.send_header("cache-control", "no-store")
        self.end_headers()
        self.wfile.write(data)

    def _text(self, code: int, text: str) -> None:
        body = text.encode("utf-8")
        self.send_response(code)
        self.send_header("content-type", "text/plain; charset=utf-8")
        self.send_header("content-length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    # --------------------------------------------------------------- 路由
    def do_GET(self):  # noqa: N802
        st = STATE
        assert st is not None
        path = self.path.split("?", 1)[0]

        if path == "/.host.json":
            self._json(200, build_config(st))
            return
        if path == "/api/preflight":
            self._json(200, do_preflight(st))
            return
        if path == "/api/health":
            alive = st.proc is not None and st.proc.poll() is None
            self._json(200, {"ok": True, "godotAlive": alive})
            return
        self._serve_file(path)

    def do_POST(self):  # noqa: N802
        st = STATE
        assert st is not None
        path = self.path.split("?", 1)[0]

        if path == "/api/launch":
            body = self._read_json()
            res = do_launch(st, str(body.get("target") or "main"))
            self._json(200 if res.get("ok") else 409, res)
            if res.get("ok"):
                # 门已经开了，而且 Godot 活着 —— 现在才收起启动器。
                # 失败时**不**退出，让玩家看见错误（§44）。
                if st.args.handover_delay >= 0:
                    threading.Timer(
                        st.args.handover_delay / 1000.0, st.should_quit.set
                    ).start()
            return

        if path == "/api/quit":
            self._json(200, {"ok": True})
            st.should_quit.set()
            return

        self._json(404, {"ok": False, "error": "no such api"})


# ---------------------------------------------------------------------------
# 窗口
# ---------------------------------------------------------------------------
def find_browser() -> Path | None:
    """找一个能开 --app 窗口的浏览器。优先 Edge（Windows 一定有）。"""
    candidates = [
        Path(os.environ.get("PROGRAMFILES(X86)", r"C:\Program Files (x86)"))
        / "Microsoft/Edge/Application/msedge.exe",
        Path(os.environ.get("PROGRAMFILES", r"C:\Program Files"))
        / "Microsoft/Edge/Application/msedge.exe",
        Path(os.environ.get("PROGRAMFILES", r"C:\Program Files"))
        / "Google/Chrome/Application/chrome.exe",
        Path(os.environ.get("PROGRAMFILES(X86)", r"C:\Program Files (x86)"))
        / "Google/Chrome/Application/chrome.exe",
    ]
    for c in candidates:
        if c.exists():
            return c
    for name in ("msedge", "chrome"):
        found = shutil.which(name)
        if found:
            return Path(found)
    return None


def open_window(url: str, w: int, h: int) -> subprocess.Popen | None:
    browser = find_browser()
    if browser is None:
        return None
    # --app = 无标签页、无地址栏的应用窗口。
    # 单独的 --user-data-dir 是必需的：否则会挂到玩家已经开着的浏览器进程上，
    # 变成一个普通标签页，而且关不掉。
    profile = REPO / ".render" / "launcher_profile"
    profile.mkdir(parents=True, exist_ok=True)
    return subprocess.Popen(
        [
            str(browser),
            f"--app={url}",
            f"--window-size={w},{h}",
            f"--user-data-dir={profile}",
            "--no-first-run",
            "--no-default-browser-check",
            "--disable-features=Translate,MediaRouter",
            "--window-position=80,60",
        ],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )


# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------
def parse_args(argv: list[str]) -> argparse.Namespace:
    p = argparse.ArgumentParser(description="SEKAI launcher host")
    p.add_argument("--dev", action="store_true", help="显示开发者入口（训练场 / 雾谷检视 / 战斗沙盒）")
    p.add_argument("--godot", default=None, help=f"Godot 可执行文件（默认 {DEFAULT_GODOT}）")
    p.add_argument("--project", default=None, help=f"工程目录（默认 {DEFAULT_PROJECT}）")
    p.add_argument("--w", type=int, default=1600)
    p.add_argument("--h", type=int, default=900)
    p.add_argument("--page", default="launcher/index.html", help="打开的页面（相对 ui_web/）")
    p.add_argument("--no-window", action="store_true", help="只起服务，不开窗口")
    p.add_argument("--open-browser", action="store_true", help="用默认浏览器代替 --app 窗口")
    p.add_argument("--verbose", action="store_true")
    p.add_argument(
        "--handover-delay",
        type=int,
        default=350,
        help="Godot 起来之后多久收起启动器（ms）；-1 = 不自动收",
    )
    return p.parse_args(argv)


def free_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def main(argv: list[str]) -> int:
    global STATE
    args = parse_args(argv)
    st = State(args)
    STATE = st

    pre = do_preflight(st)
    print("SEKAI · launcher host")
    print(f"  godot    {st.godot}")
    print(f"  project  {st.project}")
    print(f"  devMode  {st.dev_mode}")
    if pre.get("ok"):
        print("  preflight OK")
    else:
        # 注意：这里**不退出**。启动器要能开起来并把这个原因显示给玩家，
        # 而不是让玩家双击之后什么都没发生（§44）。
        print(f"  preflight FAILED: {pre.get('detail')}")

    port = free_port()
    st.port = port
    httpd = ThreadingHTTPServer(("127.0.0.1", port), Handler)
    httpd.verbose = args.verbose  # type: ignore[attr-defined]
    st.httpd = httpd
    threading.Thread(target=httpd.serve_forever, daemon=True).start()

    url = f"http://127.0.0.1:{port}/{args.page}?host=1"
    print(f"  serving  http://127.0.0.1:{port}/  (ui_web)")
    print(f"  open     {url}")

    win = None
    if not args.no_window:
        if args.open_browser:
            webbrowser.open(url)
        else:
            win = open_window(url, args.w, args.h)
            if win is None:
                print("  未找到 Edge/Chrome，改用默认浏览器")
                webbrowser.open(url)

    try:
        while not st.should_quit.is_set():
            if win is not None and win.poll() is not None:
                # 玩家自己把窗口关了
                break
            time.sleep(0.1)
    except KeyboardInterrupt:
        pass
    finally:
        httpd.shutdown()

    # 窗口收起来。只有 Godot 活着的时候才走到这里（失败时不会 set）。
    if win is not None and win.poll() is None:
        win.terminate()
    print("launcher host stopped")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
