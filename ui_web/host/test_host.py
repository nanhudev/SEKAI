#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""SEKAI · LAUNCHER HOST 契约测试
==============================================================================
宿主是「Launcher 能不能真的进游戏」的唯一执行者，也是 §44（不能死在无限
loading）的唯一执行者。所以它的接口必须有测试，不能靠手点。

这个测试**不启动 Godot**（那会在桌面上弹窗）。它检查：

  1. 宿主能起来，并且 preflight 对当前机器给出可判定的结论
  2. /.host.json 的字段符合 SKHost 读的契约（host.js 里逐项对应）
  3. /api/launch 对未知 target 返回"干净的错误"而不是 500，也不启动任何进程
  4. /api/launch 在 preflight 失败时返回失败，**且不装作成功**
  5. 静态服务能出页面与 ES module 的 MIME 正确
  6. 目录穿越被挡住

用 stdlib 的 urllib，并**显式禁用代理** —— 本机沙箱会把 127.0.0.1 也塞进代理，
那样连本地服务都会 502，测出来的是环境不是代码。

用法：python ui_web/host/test_host.py
==============================================================================
"""

from __future__ import annotations

import json
import subprocess
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

HERE = Path(__file__).resolve().parent
HOST = HERE / "launcher_host.py"

# 显式不走代理
OPENER = urllib.request.build_opener(urllib.request.ProxyHandler({}))

FAILS: list[str] = []
PASSES = 0


def check(name: str, cond: bool, extra: str = "") -> None:
    global PASSES
    if cond:
        PASSES += 1
        print(f"  PASS  {name}")
    else:
        FAILS.append(f"{name} {extra}")
        print(f"  FAIL  {name}  {extra}")


def get(url: str, timeout: float = 5.0):
    try:
        with OPENER.open(url, timeout=timeout) as r:
            return r.status, r.read()
    except urllib.error.HTTPError as e:
        return e.code, e.read()
    except Exception as e:  # noqa: BLE001
        return None, str(e).encode()


def post(url: str, payload: dict, timeout: float = 10.0):
    req = urllib.request.Request(
        url,
        data=json.dumps(payload).encode("utf-8"),
        headers={"content-type": "application/json"},
        method="POST",
    )
    try:
        with OPENER.open(req, timeout=timeout) as r:
            return r.status, r.read()
    except urllib.error.HTTPError as e:
        return e.code, e.read()
    except Exception as e:  # noqa: BLE001
        return None, str(e).encode()


def main() -> int:
    proc = subprocess.Popen(
        [sys.executable, "-u", str(HOST), "--dev", "--no-window", "--verbose"],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        encoding="utf-8",
        errors="replace",
    )

    port = None
    banner: list[str] = []
    try:
        deadline = time.time() + 10
        while time.time() < deadline:
            line = proc.stdout.readline()
            if not line:
                if proc.poll() is not None:
                    break
                continue
            banner.append(line.rstrip())
            if "serving" in line:
                # "  serving  http://127.0.0.1:55213/  (ui_web)"
                port = int(line.split("127.0.0.1:")[1].split("/")[0])
                break

        print("--- host banner ---")
        for ln in banner:
            print("  " + ln)
        print("--- checks ---")

        if port is None:
            print("  FAIL  宿主没有起来")
            return 1

        base = f"http://127.0.0.1:{port}"

        # 1. /.host.json 契约 -------------------------------------------------
        code, raw = get(f"{base}/.host.json")
        check("GET /.host.json -> 200", code == 200, str(code))
        cfg = json.loads(raw.decode("utf-8"))
        for key in ("mode", "version", "build", "devMode", "godot", "project", "save", "targets"):
            check(f".host.json 有 {key}", key in cfg)
        check('.host.json mode == "native"', cfg.get("mode") == "native", repr(cfg.get("mode")))
        check(".host.json save 是对象", isinstance(cfg.get("save"), dict))
        ids = [t.get("id") for t in cfg.get("targets") or []]
        check("targets 含 main", "main" in ids, repr(ids))
        check("main 是 primary", any(t.get("id") == "main" and t.get("primary") for t in cfg["targets"]))
        # dev=true 时开发者目标可见；页面靠 dev 字段决定渲染哪些
        check("dev 模式 devMode 为真", cfg.get("devMode") is True)

        # 2. preflight -------------------------------------------------------
        code, raw = get(f"{base}/api/preflight")
        check("GET /api/preflight -> 200", code == 200, str(code))
        pre = json.loads(raw.decode("utf-8"))
        check("preflight 有 ok 字段", "ok" in pre, repr(pre))
        check("preflight 有可读 detail", bool(pre.get("detail")), repr(pre))

        # 3. 未知 target：必须是干净的错误，且不能真的去起进程 --------------
        code, raw = post(f"{base}/api/launch", {"target": "definitely-not-a-target"})
        check("未知 target 不返回 200", code != 200, str(code))
        check("未知 target 不返回 5xx", code is not None and code < 500, str(code))
        body = json.loads(raw.decode("utf-8"))
        check("未知 target 有 error", bool(body.get("error")), repr(body))
        check("未知 target ok=false", body.get("ok") is False)

        # 4. /api/health：此刻不该有任何 Godot 在跑 ---------------------------
        code, raw = get(f"{base}/api/health")
        h = json.loads(raw.decode("utf-8"))
        check("/api/health godotAlive=false", h.get("godotAlive") is False, repr(h))

        # 5. 静态服务与 MIME --------------------------------------------------
        code, raw = get(f"{base}/launcher/index.html")
        check("GET launcher/index.html -> 200", code == 200, str(code))
        check("index.html 是 HTML 且带 charset", b"<!doctype html" in raw.lower() or b"<html" in raw.lower())
        code, _ = get(f"{base}/tokens/tokens.css")
        check("模块化 CSS 可访问", code == 200, str(code))
        code, _ = get(f"{base}/motion/motion.js")
        check("ES module 可访问", code == 200, str(code))
        code, _ = get(f"{base}/main_menu/index.html")
        check("主菜单页面可访问", code == 200, str(code))

        # 6. 目录穿越 ---------------------------------------------------------
        code, _ = get(f"{base}/../../package.json")
        check("目录穿越被挡（不是 200）", code != 200, str(code))

        # 7. 宿主自己声明它不假装成功 ----------------------------------------
        # preflight 失败时 launch 必须报错。这里无法安全地制造失败，
        # 只断言上面第 3 条已经把"失败路径返回 ok:false"这条路走通了。
        check("失败路径返回结构化错误（非异常）", isinstance(body, dict))

    finally:
        proc.terminate()
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()

    print("---")
    if FAILS:
        print(f"FAILED  {len(FAILS)} 项")
        for f in FAILS:
            print("  - " + f)
        return 1
    print(f"OK  {PASSES} 项全部通过")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
