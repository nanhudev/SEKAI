"""Drive the Suno UI to download renders of specific workspace rows.

The public CDN stream is encrypted, so the only legitimate way to get audio is
the product's own download flow: row "..." -> Download -> (Unlock &) Download.
Chrome drops files in the OS download folder; this script renames them into
audio_source/suno/raw/ using the product's own title, so the mapping back to a
cue can be verified later.

Usage:
    python audio_source/tools/suno_download.py 5 7 9            # row indexes
"""

import os
import re
import shutil
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from cdp import Page  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
RAW = os.path.join(ROOT, "audio_source", "suno", "raw")
DOWNLOADS = os.path.expanduser("~/Downloads")
AUDIO_EXT = (".wav", ".mp3", ".m4a")

ROW_BUTTON = """(() => {
  const bs = [...document.querySelectorAll('button[aria-label="More options"]')];
  const b = bs[%d];
  if (!b) return null;
  b.scrollIntoView({block: 'center'});
  const r = b.getBoundingClientRect();
  return {x: Math.round(r.x + r.width / 2), y: Math.round(r.y + r.height / 2)};
})()"""

MENU_ITEM = """(() => {
  const target = %s;
  for (const e of [...document.querySelectorAll('button,[role=menuitem],div,span')]) {
    if ((e.innerText || '').trim() !== target) continue;
    const r = e.getBoundingClientRect();
    if (r.width > 0 && r.height > 0) return {x: Math.round(r.x + r.width / 2), y: Math.round(r.y + r.height / 2)};
  }
  return null;
})()"""

BIG_BUTTON = """(() => {
  for (const t of ['Unlock & Download', 'Download']) {
    for (const e of document.querySelectorAll('button')) {
      if ((e.innerText || '').trim() !== t) continue;
      const r = e.getBoundingClientRect();
      if (r.width > 300) return {x: Math.round(r.x + r.width / 2), y: Math.round(r.y + r.height / 2)};
    }
  }
  return null;
})()"""


def newest_audio(since):
    best = None
    for name in os.listdir(DOWNLOADS):
        if not name.lower().endswith(AUDIO_EXT):
            continue
        path = os.path.join(DOWNLOADS, name)
        if os.path.getmtime(path) > since and (best is None or os.path.getmtime(path) > os.path.getmtime(best)):
            best = path
    return best


def slug(title):
    slugged = re.sub(r"[^a-z0-9]+", "_", title.lower()).strip("_")
    return slugged[:48]


def main():
    rows = [int(a) for a in sys.argv[1:]]
    if not rows:
        sys.exit("usage: suno_download.py <row_index> [row_index ...]")
    os.makedirs(RAW, exist_ok=True)

    page = Page("suno")
    try:
        for index in rows:
            started = time.time() - 1
            rect = page.eval(ROW_BUTTON % index)
            if not rect:
                print("row %d: no menu button" % index)
                continue
            page.click_xy(rect["x"], rect["y"])
            time.sleep(1.8)
            item = page.eval(MENU_ITEM % "'Download'")
            if not item:
                page.key("Escape")
                time.sleep(1.0)
                page.click_xy(rect["x"], rect["y"])
                time.sleep(1.8)
                item = page.eval(MENU_ITEM % "'Download'")
            if not item:
                print("row %d: no Download item" % index)
                page.key("Escape")
                continue
            page.click_xy(item["x"], item["y"])
            time.sleep(2.0)
            # "Unlock & Download" unlocks and downloads; a clip that is already
            # unlocked just shows "Download". Try both, twice.
            for _ in range(2):
                button = page.eval(BIG_BUTTON)
                if not button:
                    break
                page.click_xy(button["x"], button["y"])
                time.sleep(3.0)
            found = None
            deadline = time.time() + 60
            while time.time() < deadline:
                time.sleep(2)
                found = newest_audio(started)
                if found:
                    time.sleep(2)
                    break
            page.key("Escape")
            time.sleep(0.5)
            if not found:
                print("row %d: nothing landed in %s" % (index, DOWNLOADS))
                continue
            title = os.path.splitext(os.path.basename(found))[0]
            dest = os.path.join(RAW, "%02d_%s%s" % (index, slug(title), os.path.splitext(found)[1]))
            shutil.move(found, dest)
            print("row %d -> %s (%.0f kB)" % (index, os.path.basename(dest), os.path.getsize(dest) / 1024))
    finally:
        page.close()


if __name__ == "__main__":
    main()
