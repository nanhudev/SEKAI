"""Batch-capture all visible Suno Sounds clips via the WebAudio tap.

For every card in the workspace grid: locate its play button by
(title, duration), play the clip once, record PCM through the tap, and save
a 44.1 kHz stereo WAV named NN_<group>_<variant>.wav.

Usage:
    suno_capture_batch.py <output_dir>
"""

import base64
import json
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from cdp import Page  # noqa: E402
from suno_capture import TAP_JS, ATTACH_JS, WAV_ENCODE_JS  # noqa: E402

SCAN_JS = r"""
(() => {
  const bs = [...document.querySelectorAll('button,[role=button]')]
      .filter(b => ((b.getAttribute('aria-label') || '').toLowerCase().startsWith('play')));
  const out = [];
  bs.forEach((b) => {
    let p = b, txt = '';
    for (let k = 0; k < 8 && p; k++) {
      p = p.parentElement;
      if (p && p.innerText) { txt = p.innerText.trim(); if (txt.length > 10) break; }
    }
    const first = txt.split('\n')[0].trim();
    if (!/^\d+:\d\d$/.test(first)) return;   // skip miniplayer rows
    const title = txt.split('\n')[1] || '';
    out.push({ title: title.slice(0, 60), dur: first });
  });
  return JSON.stringify(out);
})()
"""

GROUPS = [
    ("reality_restore", "Isolated Fantasy Reality Restoration"),
    ("sword_handling", "Isolated Sword Handling"),
    ("glass_shatter", "Thick Glass Shattering"),
    ("glass_stress", "Glass Under Extreme Stress"),
    ("space_tear", "Dark Fantasy Space Tearing"),
    ("draw_slash", "Ultra-fast Sword Draw"),
    ("sheath_click", "Sword Sheath Click"),
    ("spatial_compress", "Fantasy Spatial Compression"),
    ("air_suck", "Air Sucked Away"),
]


def group_of(title):
    for gid, needle in GROUPS:
        if needle.lower() in title.lower():
            return gid
    return "unknown"


def scan(page):
    rows = json.loads(page.eval(SCAN_JS))
    counts = {}
    order = []
    for r in rows:
        gid = group_of(r["title"])
        if gid == "unknown":
            continue
        variant = chr(ord('A') + counts.get(gid, 0))
        counts[gid] = counts.get(gid, 0) + 1
        order.append({"title": r["title"], "dur": r["dur"], "gid": gid, "variant": variant})
    return order


def find_button(page, gid, variant_index):
    js = r"""
    (() => {
      const needle = %s.toLowerCase();
      const bs = [...document.querySelectorAll('button,[role=button]')]
          .filter(b => ((b.getAttribute('aria-label') || '').toLowerCase().startsWith('play')));
      let nth = -1;
      for (const b of bs) {
        let p = b, txt = '';
        for (let k = 0; k < 8 && p; k++) {
          p = p.parentElement;
          if (p && p.innerText) { txt = p.innerText.trim(); if (txt.length > 10) break; }
        }
        const first = txt.split('\n')[0].trim();
        const title = (txt.split('\n')[1] || '').toLowerCase();
        if (!/^\d+:\d\d$/.test(first) || !title.includes(needle)) continue;
        nth += 1;
        if (nth === %d) {
          b.scrollIntoView({block: 'center'});
          const r = b.getBoundingClientRect();
          return {x: Math.round(r.x + r.width/2), y: Math.round(r.y + r.height/2)};
        }
      }
      return null;
    })()
    """ % (json.dumps([n for g, n in GROUPS if g == gid][0]), variant_index)
    return page.eval(js)


def wait_done(page, cap_seconds=40):
    for _ in range(int(cap_seconds * 2)):
        time.sleep(0.5)
        state = page.eval("""(() => {
            const el = [...document.querySelectorAll('audio')].find(e => (e.src||'').startsWith('blob:'));
            if (!el) return 'no-el';
            return el.paused ? 'paused' : 'playing';
        })()""")
        if state in ("paused", "no-el"):
            return True
    return False


def main():
    out_dir = sys.argv[1]
    os.makedirs(out_dir, exist_ok=True)
    page = Page("suno")
    try:
        page.eval(TAP_JS)
        print("tap:", page.eval(ATTACH_JS))
        done = set()
        names = {}
        pass_no = 0
        while pass_no < 4:
            pass_no += 1
            rows = scan(page)
            print("pass %d: %d clips in DOM" % (pass_no, len(rows)))
            progressed = False
            for row in rows:
                key = (row["gid"], row["variant"])
                if key in done:
                    continue
                idx = sum(1 for r in rows[:rows.index(row)] if r["gid"] == row["gid"])
                rect = find_button(page, row["gid"], idx)
                if not rect:
                    continue
                name = "%02d_%s_%s" % (len(names), row["gid"], row["variant"])
                page.eval("document.querySelectorAll('audio,video').forEach(e=>e.pause());"
                          "window.__tap.chunks = []; window.__tap.recording = true;")
                time.sleep(0.4)
                page.click_xy(rect["x"], rect["y"])
                ok = wait_done(page, 45)
                time.sleep(0.6)
                page.eval("window.__tap.recording = false;")
                payload = page.eval(WAV_ENCODE_JS)
                info = json.loads(payload)
                path = os.path.join(out_dir, name + ".wav")
                with open(path, "wb") as f:
                    f.write(base64.b64decode(info["b64"]))
                done.add(key)
                names[key] = name
                progressed = True
                print("saved %s (%.2f s) for %s %s" % (name, info["seconds"], row["gid"], row["variant"]))
                if not ok:
                    print("  WARN: playback did not report paused")
            if len(done) >= 18 or not progressed:
                break
            # scroll the workspace to load more cards
            page.eval("""(() => {
                const els=[...document.querySelectorAll('div')].filter(e=>e.scrollHeight>e.clientHeight+50 && e.clientHeight>300);
                const el=els[els.length-1];
                if(el) el.scrollTop += el.clientHeight * 0.8;
                return 'scrolled';
            })()""")
            time.sleep(1.5)
        print("total captured: %d" % len(done))
    finally:
        page.close()


if __name__ == "__main__":
    main()
