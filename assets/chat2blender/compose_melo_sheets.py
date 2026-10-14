"""Compose the MELO audit contact sheets.

Reads the tiles rendered by melo_audit.py and tiles them into labelled sheets so
a reviewer can judge 84 candidates without opening 84 images. Each cell keeps the
Blender-rendered stamp (name | dimensions | triangles) and gains a printed caption
so the sheet stays readable when the tile is downscaled.

Run:  python compose_melo_sheets.py
"""
from pathlib import Path as _SekaiPath
import os as _sekai_os
_SEKAI_ROOT = _SekaiPath(_sekai_os.environ['SEKAI_ROOT']).resolve() if 'SEKAI_ROOT' in _sekai_os.environ else next(p for p in _SekaiPath(__file__).resolve().parents if (p / 'godot/project.godot').is_file())
_SEKAI_RUNTIME = _SekaiPath(_sekai_os.environ.get('SEKAI_RUNTIME_DIR', str(_SEKAI_ROOT / '.local')))

import json
import os
from PIL import Image, ImageDraw, ImageFont

TILE_DIR = str(_SEKAI_ROOT / '.render/melo_tiles')
OUT_DIR = str(_SEKAI_ROOT / 'assets_source/review/melo')
MEASURED = os.path.join(OUT_DIR, "melo_measured.json")

TILE = 380
LABEL_H = 34
COLS = 4
ROWS = 5
PER_SHEET = COLS * ROWS

FONT_PATHS = [r"C:\Windows\Fonts\consola.ttf", r"C:\Windows\Fonts\arial.ttf"]


def load_font(size):
    for p in FONT_PATHS:
        if os.path.exists(p):
            return ImageFont.truetype(p, size)
    return ImageFont.load_default()


def short(rel):
    """Trim to the part that identifies the piece."""
    base = os.path.basename(rel).replace(".glb", "")
    parts = rel.split("/")
    owner = ""
    if "architecture" in parts:
        owner = parts[parts.index("architecture") + 1]
    elif "characters" in parts:
        owner = "chr_melo"
    elif "creatures" in parts:
        owner = parts[parts.index("creatures") + 1]
    elif "props" in parts:
        owner = parts[parts.index("props") + 1]
    return base, owner


def tile_path(rel, prefix="S_"):
    base = os.path.basename(rel).replace(".glb", "")
    parts = rel.split("/")
    if parts[0] == "asset_library":
        group = parts[1] if len(parts) > 1 else "?"
    else:
        group = parts[0]
    return os.path.join(TILE_DIR, "%s%s__%s__34.png" % (prefix, group, base))


def compose(entries, prefix, out_name, title):
    sheets = []
    n = 0
    for start in range(0, len(entries), PER_SHEET):
        chunk = entries[start:start + PER_SHEET]
        sheet = Image.new("RGB", (TILE * COLS, LABEL_H + (TILE + LABEL_H) * ROWS),
                          (24, 25, 28))
        draw = ImageDraw.Draw(sheet)
        head = load_font(20)
        small = load_font(14)

        draw.text((10, 8), "%s   (%d-%d of %d)"
                  % (title, start + 1, start + len(chunk), len(entries)),
                  fill=(235, 235, 240), font=head)

        for i, item in enumerate(chunk):
            rel = item["rel"]
            col = i % COLS
            row = i // COLS
            x = col * TILE
            y = LABEL_H + row * (TILE + LABEL_H)

            tp = tile_path(rel, prefix)
            if os.path.exists(tp):
                im = Image.open(tp).convert("RGB")
                im = im.resize((TILE, TILE), Image.LANCZOS)
                sheet.paste(im, (x, y))
            else:
                draw.rectangle([x, y, x + TILE - 1, y + TILE - 1], fill=(60, 20, 20))
                draw.text((x + 8, y + 8), "no tile", fill=(255, 220, 220), font=small)

            base, owner = short(rel)
            m = item.get("measured") or {}
            dims = m.get("dims_m")
            tris = m.get("triangles")
            cap = base
            if dims:
                cap += "  %.2fx%.2fx%.2fm" % tuple(dims)
            if tris:
                cap += "  %dt" % tris
            if m.get("helper_objects"):
                cap += "  [helper stripped]"
            draw.text((x + 6, y + TILE + 3), cap[:64], fill=(225, 225, 232), font=small)
            draw.text((x + 6, y + TILE + 18), owner[:40], fill=(140, 150, 165), font=small)

        out = os.path.join(OUT_DIR, out_name % (n + 1))
        sheet.save(out)
        sheets.append(out)
        n += 1
    return sheets


def main():
    idx = json.load(open(os.path.join(OUT_DIR, "melo_glb_index.json"), encoding="utf-8"))
    meas = {}
    if os.path.exists(MEASURED):
        meas = json.load(open(MEASURED, encoding="utf-8"))
    for e in idx:
        e["measured"] = meas.get(e["rel"])

    sanctuary = [e for e in idx if "arc_ancient_sanctuary_kit" in e["rel"]]
    others = [e for e in idx if "arc_ancient_sanctuary_kit" not in e["rel"]]

    made = []
    made += compose(sanctuary, "S_", "SHEET_sanctuary_%02d.png",
                    "MELO / arc_ancient_sanctuary_kit")
    made += compose(others, "S_", "SHEET_others_%02d.png",
                    "MELO / hero + creatures + cinematic + props")

    lines = ["MELO CONTACT SHEETS", ""]
    for p in made:
        lines.append(os.path.basename(p))
    lines.append("")
    lines.append("sanctuary pieces: %d   others: %d   total: %d"
                 % (len(sanctuary), len(others), len(idx)))
    open(os.path.join(OUT_DIR, "SHEETS.txt"), "w", encoding="utf-8").write("\n".join(lines))
    print("\n".join(lines))


if __name__ == "__main__":
    main()
