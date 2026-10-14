#!/usr/bin/env python3
"""List / download files from a public Google Drive *folder* link (recursive).

Why this exists: several CC0 asset authors (e.g. quaternius.com pack pages)
distribute packs as "just give me the download" public Drive folders.  The
normal /drive/folders/<id> page is JS-only and yields nothing to a scraper, but
the legacy `embeddedfolderview` endpoint still returns a plain HTML listing.

Drive is unreachable directly from this sandbox -> route through the local
v2RayN SOCKS5 proxy.  Pass --proxy "" to go direct.

Usage:
    python tools/fetch_gdrive.py --url <folder-url> --list
    python tools/fetch_gdrive.py --url <folder-url> --list --tree
    python tools/fetch_gdrive.py --url <folder-url> --out <dir> [--filter re]
"""
import argparse
import os
import re
import subprocess
import sys
import urllib.parse

DEFAULT_PROXY = "socks5h://127.0.0.1:10808"
UA = ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36")

ENTRY_SPLIT = '<div class="flip-entry"'
ENTRY_ID = re.compile(r'id="entry-([A-Za-z0-9_\-]{10,})"')
TITLE = re.compile(r'<div class="flip-entry-title">(.*?)</div>', re.S)
FOLDER_HINT = re.compile(r'aria-label="Folder"')


def curl(url, proxy, out=None, timeout=120):
    cmd = ["curl", "-sL", "--max-time", str(timeout), "-A", UA,
           "--retry", "2", "--retry-delay", "2"]
    if proxy:
        cmd += ["-x", proxy]
    cmd += ["-o", out] if out else ["-o", "-"]
    cmd.append(url)
    return subprocess.run(cmd, capture_output=True).stdout


def folder_id(url):
    m = (re.search(r"/folders/([A-Za-z0-9_\-]{10,})", url)
         or re.search(r"[?&]id=([A-Za-z0-9_\-]{10,})", url))
    if not m:
        raise SystemExit("cannot parse folder id from %r" % url)
    return m.group(1)


def list_folder(fid, proxy, depth=0, max_depth=3, seen=None):
    """return list of {'id','name','is_dir','path'}"""
    seen = seen if seen is not None else set()
    if fid in seen or depth > max_depth:
        return []
    seen.add(fid)
    html = curl("https://drive.google.com/embeddedfolderview?id=%s#list" % fid,
                proxy, timeout=60).decode("utf-8", "replace")
    out = []
    for chunk in html.split(ENTRY_SPLIT)[1:]:
        mid = ENTRY_ID.search(chunk)
        if not mid:
            continue
        t = TITLE.search(chunk)
        if not t:
            continue
        name = re.sub(r"<[^>]+>", "", t.group(1)).strip()
        if not name:
            continue
        is_dir = bool(FOLDER_HINT.search(chunk))
        out.append({"id": mid.group(1), "name": name, "is_dir": is_dir, "path": name})
    # recurse into sub-folders
    for e in list(out):
        if e["is_dir"]:
            for sub in list_folder(e["id"], proxy, depth + 1, max_depth, seen):
                sub["path"] = e["name"] + "/" + sub["path"]
                out.append(sub)
    return out


def download(fid, dest, proxy):
    url = ("https://drive.usercontent.google.com/download?id=%s"
           "&export=download&confirm=t" % fid)
    blob = curl(url, proxy, timeout=900)
    if not blob:
        return "empty response"
    if blob[:200].lstrip()[:6].lower() in (b"<html>", b"<!doct"):
        txt = blob.decode("utf-8", "replace")
        if re.search(r"(quota|too many users)", txt, re.I):
            return "quota exceeded"
        act = re.search(r'action="([^"]+)"', txt)
        if act:
            qs = re.findall(r'name="([^"]+)"\s+value="([^"]*)"', txt)
            if qs:
                blob = curl(act.group(1).replace("&amp;", "&") + "?" +
                            urllib.parse.urlencode(qs), proxy, timeout=900)
        if blob[:200].lstrip()[:6].lower() in (b"<html>", b"<!doct"):
            return "html interstitial"
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    with open(dest, "wb") as f:
        f.write(blob)
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--url", required=True)
    ap.add_argument("--out")
    ap.add_argument("--filter", default="")
    ap.add_argument("--proxy", default=DEFAULT_PROXY)
    ap.add_argument("--list", action="store_true")
    ap.add_argument("--tree", action="store_true")
    a = ap.parse_args()
    proxy = a.proxy or None

    files = list_folder(folder_id(a.url), proxy)
    rx = re.compile(a.filter, re.I) if a.filter else None
    files.sort(key=lambda f: f["path"])
    print("[GDRIVE] %d entries" % len(files), flush=True)
    for f in files:
        if a.tree or not f["is_dir"]:
            print("   %s%-58s %s" % ("[D] " if f["is_dir"] else "    ",
                                     f["path"], f["id"] if a.tree else ""))
    if a.list:
        return
    if not a.out:
        raise SystemExit("--out required to download")

    picked = [f for f in files if not f["is_dir"] and (rx.search(f["path"]) if rx else True)]
    ok = 0
    for f in picked:
        dest = os.path.join(a.out, f["path"])
        err = download(f["id"], dest, proxy)
        if err:
            print("[GDRIVE] FAIL %-46s %s" % (f["path"][:46], err), flush=True)
        else:
            print("[GDRIVE] OK   %-46s %8.2f MB" % (f["path"][:46],
                                                    os.path.getsize(dest) / 1048576.0), flush=True)
            ok += 1
    print("[GDRIVE] %d/%d downloaded -> %s" % (ok, len(picked), a.out), flush=True)
    sys.exit(0 if ok == len(picked) else 1)


if __name__ == "__main__":
    main()
