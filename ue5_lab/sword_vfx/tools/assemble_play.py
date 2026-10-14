"""Assemble the recorded play sections into ue5_sword_vfx_complete_v1.mp4.

Inputs   render/play/{normal,magic,angles}/f%04d.png   (24 fps)
Output   ue5_sword_vfx_complete_v1.mp4  (project root of sword_vfx)

Order (brief section 23/24):
    title NORMAL SWORD -> equip inspect a1 a2 a3 a4 combo iaido
    title MAGIC SWORD  -> idle equip inspect a1 a2 a3 a4 combo iaido
    title ALTERNATE ANGLES -> a3_side a4_top ma3_hero

Encoding: h264 yuv420p, cuts only - the project's UI language forbids
glow/gradient transitions, and a QA reel wants hard cuts anyway.
"""
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
PLAY = os.path.normpath(os.path.join(HERE, "..", "render", "play"))
OUT = os.path.normpath(os.path.join(HERE, "..", "ue5_sword_vfx_complete_v1.mp4"))
TMP = "F:/ue_temp/assemble"
FONT = "C\\:/Windows/Fonts/arial.ttf"
FF = "D:/oopz/ffmpeg.exe"

ORDER = [
    ("title", "NORMAL SWORD"),
    ("normal", "equip"), ("normal", "inspect"), ("normal", "a1"),
    ("normal", "a2"), ("normal", "a3"), ("normal", "a4"),
    ("normal", "combo"), ("normal", "iaido"),
    ("title", "MAGIC SWORD"),
    ("magic", "idle"), ("magic", "equip"), ("magic", "inspect"),
    ("magic", "a1"), ("magic", "a2"), ("magic", "a3"), ("magic", "a4"),
    ("magic", "combo"), ("magic", "iaido"),
    ("title", "ALTERNATE ANGLES"),
    ("angles", "a3_side"), ("angles", "a4_top"), ("angles", "ma3_hero"),
]


def run(args):
    r = subprocess.run(args, capture_output=True, text=True)
    if r.returncode != 0:
        print(r.stderr[-1500:])
        sys.exit("ffmpeg failed: %s" % " ".join(args[:6]))
    return r


def main():
    os.makedirs(TMP, exist_ok=True)
    parts = []
    for i, (kind, name) in enumerate(ORDER):
        part = os.path.join(TMP, "part%02d.mp4" % i)
        if kind == "title":
            src = ("-f", "lavfi", "-i",
                   "color=c=0x0a0a0c:s=1280x720:d=2.0:r=24")
            vf = ("drawtext=fontfile=%s:text='%s':fontcolor=0xE8E8EC:"
                  "fontsize=44:x=(w-text_w)/2:y=(h-text_h)/2" % (FONT, name))
            run([FF, "-y", "-loglevel", "error", src[0], src[1], src[2],
                 "-vf", vf, "-c:v", "libx264", "-pix_fmt", "yuv420p", part])
        else:
            d = os.path.join(PLAY, kind, name)
            if not os.path.isdir(d):
                print("SKIP missing section %s/%s" % (kind, name))
                continue
            n = len([f for f in os.listdir(d) if f.endswith(".png")])
            if n == 0:
                print("SKIP empty %s/%s" % (kind, name))
                continue
            run([FF, "-y", "-loglevel", "error", "-framerate", "24",
                 "-i", os.path.join(d, "f%04d.png"),
                 "-c:v", "libx264", "-pix_fmt", "yuv420p", part])
        parts.append(part)
        print("part %02d  %-14s %-10s  %s" % (i, kind, name,
                                              os.path.basename(part)))

    lst = os.path.join(TMP, "concat.txt")
    with open(lst, "w", encoding="ascii") as fh:
        for p in parts:
            fh.write("file '%s'\n" % p.replace("\\", "/"))
    run([FF, "-y", "-loglevel", "error", "-f", "concat", "-safe", "0",
         "-i", lst, "-c", "copy", OUT])
    sz = os.path.getsize(OUT) / 1e6
    print("WROTE %s  (%.1f MB, %d parts)" % (OUT, sz, len(parts)))


if __name__ == "__main__":
    main()
