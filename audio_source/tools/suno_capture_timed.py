"""Timed targeted capture: click a specific card's play, record fixed seconds.

Usage: suno_capture_timed.py <out.wav> <record_seconds> <needle> <occurrence_index>
"""

import base64
import json
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from cdp import Page  # noqa: E402
from suno_capture import TAP_JS, ATTACH_JS, WAV_ENCODE_JS  # noqa: E402

FIND_JS = r"""
(() => {
  const needle = %s.toLowerCase();
  const idx = %d;
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
    if (nth === idx) {
      b.scrollIntoView({block: 'center'});
      const r = b.getBoundingClientRect();
      return {x: Math.round(r.x + r.width/2), y: Math.round(r.y + r.height/2)};
    }
  }
  return null;
})()
"""


def main():
    out_path, seconds, needle, occ = sys.argv[1], float(sys.argv[2]), sys.argv[3], int(sys.argv[4])
    page = Page("suno")
    try:
        page.eval(TAP_JS)
        print("tap:", page.eval(ATTACH_JS))
        rect = page.eval(FIND_JS % (json.dumps(needle), occ))
        if not rect:
            sys.exit("button not found for %r #%d" % (needle, occ))
        page.eval("document.querySelectorAll('audio,video').forEach(e=>e.pause());"
                  "window.__tap.chunks = []; window.__tap.recording = true;")
        time.sleep(0.3)
        page.click_xy(rect["x"], rect["y"])
        time.sleep(seconds)
        page.eval("window.__tap.recording = false;")
        info = json.loads(page.eval(WAV_ENCODE_JS))
        with open(out_path, "wb") as f:
            f.write(base64.b64decode(info["b64"]))
        print("saved %s (%.2f s)" % (out_path, info["seconds"]))
    finally:
        page.close()


if __name__ == "__main__":
    main()
