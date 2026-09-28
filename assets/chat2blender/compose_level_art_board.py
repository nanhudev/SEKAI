"""Compose the level-art progress board.

One image that answers "where is the level art": the masterplan, the greybox it
was drawn on, the kit that replaces it, and the training ground that reviews it.
Each tile carries its own maturity tag, because the single most misleading thing
this board could do is let a greybox block and a finished kit piece sit in the
same grid with no way to tell them apart.
"""
import os
from PIL import Image, ImageDraw, ImageFont

REV = r"F:\SEKAI\assets_source\review"
OUT = os.path.join(REV, "LEVEL_ART_BOARD.png")

COLS, TILE_W = 3, 520
GAP, PAD, LABEL_H = 14, 20, 46
HEAD_H = 96

# tag -> (rgb, label)
TAGS = {
    "DESIGN":  ((58, 110, 175), "设计 · DESIGN LOCKED"),
    "GREYBOX": ((96, 104, 118), "灰盒 · GREYBOX ONLY"),
    "GODOT":   ((42, 130, 92),  "Godot 实机 · IN GODOT"),
    "ASSET":   ((176, 106, 34), "正式资产 · KIT PIECE"),
}

# (path, title, subtitle, tag)
TILES = [
    (r"ld01_01_plan.png", "LD-01 区域总平面", "660×760 m · 高差 161 m", "DESIGN"),
    (r"ld01_04_3d.png", "LD-01 三维鸟瞰", "垂直夸大 2.6× · 等高距 20 m", "DESIGN"),
    (r"ld01_06_vista_sightlines.png", "Vista 视线可达性审计", "9/9 全部通畅（机器实测）", "DESIGN"),

    (r"compose\12_aerial_town_mountain.png", "区域航拍 — 城镇 / 河谷 / 北山", "GATE 1 灰盒 · 真实地形场", "GREYBOX"),
    (r"compose\01_sb_from_below.png", "崖路 S-B 从底部", "§14 必产生「我要爬上去」", "GREYBOX"),
    (r"compose\07_sb_arrival.png", "遗迹前场 + 信标", "崖路终点 · 中央为 RuinsBeacon", "GREYBOX"),

    (r"kit02a\kit02a_01_threequarter.png", "KIT-02a 楼梯 3/4 视", "踏面锁死 0.2857 m · 7 级", "ASSET"),
    (r"kit02a\kit02a_03_firstperson.png", "KIT-02a 第一人称", "眼高 1.62 m · 游戏内视距", "ASSET"),
    (r"kit02a\kit02a_04_nosing.png", "KIT-02a 踏面前缘细节", "故意磨损 / 冲刷刻槽", "ASSET"),

    (r"training\01_aerial.png", "训练场航拍", "7 区 · 60–100 m 连续空间", "GODOT"),
    (r"training\03_combat_court.png", "训练场 · 战斗场 B 区", "评审区 · CombatSandbox 全栈", "GODOT"),
    (r"training\07_showcase.png", "训练场 · ENV-01 展示区", "12 件正式套件实际落位", "GODOT"),
]


def font(size, bold=False):
    for p in (r"C:\Windows\Fonts\msyhbd.ttc" if bold else r"C:\Windows\Fonts\msyh.ttc",
              r"C:\Windows\Fonts\msyh.ttc",
              r"C:\Windows\Fonts\simhei.ttf",
              r"C:\Windows\Fonts\arial.ttf"):
        if os.path.exists(p):
            try:
                return ImageFont.truetype(p, size)
            except Exception:
                continue
    return ImageFont.load_default()


def main():
    rows = (len(TILES) + COLS - 1) // COLS
    tw = TILE_W
    th = int(TILE_W * 9 / 16)
    W = PAD * 2 + COLS * tw + (COLS - 1) * GAP
    H = HEAD_H + PAD + rows * (th + LABEL_H) + (rows - 1) * GAP + PAD

    board = Image.new("RGB", (W, H), (24, 26, 30))
    d = ImageDraw.Draw(board)

    f_title = font(30, True)
    f_sub = font(15)
    f_t1 = font(16, True)
    f_t2 = font(13)
    f_tag = font(12, True)

    d.text((PAD, 24), "SEKAI · 地编进度总览", font=f_title, fill=(238, 240, 244))
    d.text((PAD, 64), "LEVEL ART PROGRESS BOARD   ·   Mistvale 区域  ·   GATE 1 灰盒 → 正式套件",
           font=f_sub, fill=(150, 158, 170))

    missing = []
    for i, (rel, title, sub, tag) in enumerate(TILES):
        r, c = divmod(i, COLS)
        x = PAD + c * (tw + GAP)
        y = HEAD_H + PAD + r * (th + LABEL_H + GAP)

        src = os.path.join(REV, rel)
        if not os.path.exists(src):
            missing.append(rel)
            d.rectangle([x, y, x + tw, y + th], fill=(58, 30, 30))
            d.text((x + 12, y + 12), "MISSING\n" + rel, font=f_t2, fill=(220, 120, 120))
        else:
            im = Image.open(src).convert("RGB")
            # cover-fit, cropping rather than letterboxing so no tile reads as
            # "smaller" than its neighbours for a reason that is really just
            # aspect ratio.
            sr, tr = im.width / im.height, tw / th
            if sr > tr:
                nw = int(im.height * tr)
                im = im.crop(((im.width - nw) // 2, 0, (im.width + nw) // 2, im.height))
            else:
                nh = int(im.width / tr)
                im = im.crop((0, (im.height - nh) // 2, im.width, (im.height + nh) // 2))
            board.paste(im.resize((tw, th), Image.LANCZOS), (x, y))

        # Label strip
        ly = y + th
        d.rectangle([x, ly, x + tw, ly + LABEL_H], fill=(34, 37, 43))
        rgb, tlabel = TAGS[tag]
        d.rectangle([x, ly, x + 4, ly + LABEL_H], fill=rgb)
        d.text((x + 14, ly + 6), title, font=f_t1, fill=(232, 235, 240))
        d.text((x + 14, ly + 27), sub, font=f_t2, fill=(146, 154, 166))

        tb = d.textbbox((0, 0), tlabel, font=f_tag)
        tagw = tb[2] - tb[0] + 16
        d.rectangle([x + tw - tagw - 10, ly + 12, x + tw - 10, ly + 34], fill=rgb)
        d.text((x + tw - tagw - 2, ly + 15), tlabel, font=f_tag, fill=(255, 255, 255))

    board.save(OUT)
    print("saved", OUT, board.size)
    if missing:
        print("MISSING:", missing)


main()
