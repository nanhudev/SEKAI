# ============================================================================
# SEKAI · UI TOKENS  （**本文件由工具生成，不要手改**）
# ----------------------------------------------------------------------------
# 生成器 : ui_web/tools/emit_tokens.mjs
# 来源   : ui_web/tokens/tokens.css             （颜色 / 间距 / 时长 / 缓动）
#          ui_web/launcher/launcher.config.js   （HANDOFF 交接合同 · 启动时序）
#          ui_web/main_menu/main_menu.config.js （主菜单进场时序 · 菜单项）
# 生成于 : 2026-09-27
#
# 为什么要生成而不是手抄：
#   HANDOFF、启动时序、主菜单时序本来就是"网页与 Godot 两侧必须逐项对上"的
#   东西。手抄的表一定会漂移，而且漂了没人会发现。生成的不可能抄错。
#   改数值请改上面三个源文件，然后重新运行 emitter。
#
# 注意：这里**不**生成字号。网页侧字号是 clamp(px, Nvmin, px)，
# 是"以 900px 高为基准的比例"，用 vmin 表达；Godot 侧应当用
# 视口高度换算（见 ui_scale()），而不是钉死一个 px。
# ============================================================================
extends RefCounted

# --- 颜色 -------------------------------------------------------------------
const COLOR := {
	"void": Color("060a10"),
	"ink": Color("0e1418"),
	"ink-soft": Color("16202a"),
	"ink-raise": Color("1d2933"),
	"smoke": Color("14202a", 0.72),
	"line": Color("2c3a44"),
	"line-soft": Color("2c3a44", 0.55),
	"line-faint": Color("2c3a44", 0.26),
	"text": Color("ede4d3"),
	"text-2": Color("b8ae9c"),
	"text-3": Color("7e8b95"),
	"text-4": Color("4a555e"),
	"gold": Color("c9a65c"),
	"gold-bright": Color("e8ce8c"),
	"gold-line": Color("c9a65c", 0.3),
	"hp": Color("c0563f"),
	"mp": Color("6fae9c"),
	"sp": Color("d8b45a"),
	"alert": Color("b3402f"),
	"fire": Color("d4763f"),
	"frost": Color("7fa8c9"),
	"gale": Color("8fbfa6"),
	"surface-hover": Color("191f26"),
	"surface-focus": Color("22201a"),
	"surface-primary": Color("2a2418"),
	"surface-press": Color("332c1e"),
	"fg": Color("ede4d3"),
	"fg-dim": Color("b8ae9c"),
	"fg-meta": Color("7e8b95"),
	"fg-ghost": Color("4a555e"),
	"accent": Color("c9a65c"),
	"accent-hi": Color("e8ce8c"),
	"surface": Color("0e1418"),
	"border": Color("2c3a44"),
	"border-focus": Color("c9a65c"),
}

# --- 间距 / 形体 ------------------------------------------------------------
const SPACE := {
	"s1": 4,
	"s2": 8,
	"s3": 12,
	"s4": 16,
	"s5": 24,
	"s6": 32,
	"s7": 48,
	"s8": 64,
	"s9": 96,
	"s10": 144,
	"radius": 2,
	"chamfer": 8,
	"chamfer-lg": 14,
	"stroke-hair": 1,
	"stroke": 1.5,
}

# --- 字号：[最小px, Nvmin, 最大px] ------------------------------------------
# 与 CSS 的 clamp(minPx, Nvmin, maxPx) 逐字对应。用 type_px() 求值。
const TYPE := {
	"mega": [38, 7.11, 120],
	"display": [28, 5.33, 92],
	"title": [21, 3.78, 62],
	"head": [17, 2.67, 44],
	"body": [14, 2, 32],
	"small": [12, 1.56, 25],
	"micro": [10.5, 1.33, 21],
	"nano": [9.5, 1.11, 18],
}

# --- 字距（em）--------------------------------------------------------------
# 宽字距是本设计的主要"呼吸"手段。Godot 的 Label 没有 letter-spacing，
# 所以标题必须自己逐字排版（见 wordmark 的实现在 boot_splash.gd）。
const TRACK := {
	"mega": 0.42,
	"wide": 0.26,
	"title": 0.1,
	"body": 0.015,
	"figure": 0.04,
}

# --- 行高（无单位倍数）------------------------------------------------------
# CSS 里没写 line-height 的元素继承 body（body 值），不是继承标题值。
# 推算块高时必须照这个来，否则品牌块会整块偏移。
const LINE := {
	"tight": 1.12,
	"snug": 1.34,
	"body": 1.62,
}

# --- 字重 -------------------------------------------------------------------
# SystemFont 默认 400。字标是 300、元信息是 500 —— 不显式给就等于没对齐。
const WEIGHT := {
	"light": 300,
	"regular": 400,
	"medium": 500,
	"semi": 600,
}

# --- 版心边距：[最小px, Nvmin, 最大px] --------------------------------------
# 与 TYPE 同一套公式，用 gutter_px() 求值。
const GUTTER := [32, 5.2, 96]

# --- 时长（毫秒）------------------------------------------------------------
const DUR_MS := {
	"instant": 90,
	"fast": 140,
	"base": 240,
	"slow": 480,
	"crawl": 800,
	"write": 1400,
	"drift": 48000,
	"breathe": 6400,
	"stagger": 62,
}

# --- 缓动（cubic-bezier 控制点）---------------------------------------------
# Godot 的 Tween 只有 TRANS_/EASE_ 预设，没有任意贝塞尔。
# 这里保留原始控制点，是为了让"意图"能被查到，并按下面的对应关系选预设：
#   out      → TRANS_CUBIC + EASE_OUT
#   in       → TRANS_CUBIC + EASE_IN
#   io       → TRANS_SINE  + EASE_IN_OUT
#   snap     → TRANS_BACK  + EASE_OUT（或 QUINT）
#   write    → TRANS_CUBIC + EASE_OUT（慢起快走；入场用 EASE_IN 会更像"落笔"）
#   unfold   → TRANS_QUINT + EASE_OUT
#   drift    → TRANS_LINEAR
const EASE_BEZIER := {
	"out": Vector4(0.22, 0.61, 0.36, 1),
	"in": Vector4(0.55, 0.06, 0.68, 0.19),
	"io": Vector4(0.65, 0.05, 0.36, 1),
	"snap": Vector4(0.16, 0.84, 0.24, 1),
	"write": Vector4(0.33, 0, 0.15, 1),
	"unfold": Vector4(0.12, 0.72, 0.1, 1),
	"drift": "linear",
}

# --- 品牌标记几何（viewBox 128×128）----------------------------------------
# 实现见 web 侧 ui_web/svg/library.js 的 mark()。
# 「开口的环 + 正中一点」：环 302°，缺口 58° 落在右上；点是信标 / 观察者。
const MARK_VIEWBOX := 128.0
const MARK_ARC_RADIUS := 40.0
const MARK_ARC_SWEEP_DEG := 294.0
const MARK_ARC_GAP_CENTER_DEG := 58.0
const MARK_DOT_RADIUS := 5.0

# --- HANDOFF：Launcher 最后一帧 ≡ BootSplash 第一帧 ------------------------
# 这是"一个连续启动过程"能被验收的唯一依据。两侧逐项对齐。
# 验收方式：两侧最后一帧采样，四角与侧翼都必须是 bg，
# 最亮像素必须落在屏幕正中的那个点上。
const HANDOFF := {
	"bg": Color("060a10"),
	"mark_side_vmin": 8,
	"mark_side_min_px": 44,
	"mark_side_max_px": 92,
	"mark_center_x": 0.5,
	"mark_center_y": 0.5,
	"arc_progress": 1,
	"dot_progress": 1,
	"arc_color": Color("ede4d3"),
	"dot_color": Color("c9a65c"),
	"arc_stroke_px": 1.6,
	"hold_ms": 320,
	"exit_ms": 1200,
}

# --- 启动演出时序（毫秒，从画面出现算起）-----------------------------------
# 与 ui_web/launcher/index.html 同一支舞。Godot 侧跑同一张表。
const BOOT_SEQ := {
	"pulse": 180,
	"dot": 300,
	"markArc": 460,
	"runes": 1250,
	"bgMove": 1500,
	"wordmark": 1900,
	"wordmarkCN": 2480,
	"rule": 2640,
	"subtitle": 2880,
	"loading": 3150,
	"resolved": 3500,
	"skipHint": 1150,
}

const BOOT_DUR := {
	"pulse": 560,
	"dot": 420,
	"markArc": 1400,
	"rune": 900,
	"bgFade": 1800,
	"letter": 420,
	"letterStagger": 70,
	"wordmarkCN": 520,
	"rule": 620,
	"subtitle": 700,
	"loadingIn": 600,
}

const BOOT_SEQ_FAST := {
	"pulse": 50,
	"dot": 90,
	"markArc": 140,
	"runes": 0,
	"bgMove": 60,
	"wordmark": 400,
	"wordmarkCN": 610,
	"rule": 700,
	"subtitle": 780,
	"loading": 860,
	"resolved": 960,
	"skipHint": 400,
}

# --- 加载表现 ---------------------------------------------------------------
# **禁止假加载**：不显示百分比；真实进度只影响"线写到哪"，不影响数字。
const LOADING := {
	"ambient_line_ms": 1500,
	"ambient_gap_ms": 340,
	"ring_spin_ms": 24000,
	"stalled_after_ms": 6000,
}

# --- 文案（唯一真相源在 launcher.config.js 的 COPY）-------------------------
const COPY := {
	"wordmark": "SEKAI",
	"wordmark_cn": "世界之外",
	"subtitle": "Beyond the Written Fate",
	"skip": "跳过",
	"skip_en": "SKIP",
	"error_cn": "无法进入世界。",
	"error_en": "Unable to enter world.",
}

# --- 主菜单进场时序（毫秒，**启动时钟**：交接帧 = 0，与 BOOT_SEQ 同一支表）---
# 品牌段（标记 / 字标 / 中文名 / 金线 / 副标题 / 世界层）由 BootSplash 播，
# 用的是上面的 BOOT_SEQ —— 因为那才是"接着 Launcher 往下演"。
# 这里只有主菜单自己要负责的三拍。
#
# 换算方式：取 MENU_BOOT 里这三拍相对副标题的滞后，加到 BOOT_SEQ 的副标题时刻上。
# 换句话说，可移植的事实是"导航比副标题晚 160ms"，不是"导航在 1420ms"。
const MENU_SEQ := {
	"nav": 3040,
	"meta": 3180,
	"focus": 3480,
}

# --- 主菜单用到的时长（毫秒）------------------------------------------------
# 时长没有原点问题，所以原样生成，不做换算。
#
# 注意：网页版主菜单是**自包含**的（它自己从交接帧演到菜单出现），
# 所以这张表里的 letter / cn / rule / subtitle / scene / runes 属于"品牌段"，
# 在 Godot 里由 BootSplash 用 BOOT_DUR 表达 —— 两边数值不同是**故意的**：
# Launcher 那条链路上多出了 pulse / dot / markArc / loading 几拍。
# Godot 侧的 MainMenu **只消费**：markHome / markHomeDelay / navItem /
# navStagger / meta。
const MENU_DUR := {
	"markHomeDelay": 260,
	"markHome": 800,
	"scene": 1500,
	"runes": 1000,
	"letter": 300,
	"letterStagger": 46,
	"cn": 380,
	"rule": 420,
	"subtitle": 460,
	"navItem": 420,
	"navStagger": 88,
	"meta": 420,
}

# --- 主菜单退场（进入世界）--------------------------------------------------
# 终点与 Launcher 首帧 / BootSplash 首帧**完全相同**：纯色 + 屏幕正中的标记。
# 所以"进入世界"这个动作在三个场景里都能用同一句断言验收。
const MENU_EXIT := {
	"mark_delay_ms": 620,
	"mark_dur_ms": 780,
	"hold_ms": 320,
}

# --- 菜单项 -----------------------------------------------------------------
# 文案（cn/en）属于 NARRATIVE 线，此处是**占位**。Godot 与网页读同一份表，
# 免得两边各写一套菜单然后逐渐说不一样的话。
#   needs_save : 没有存档时该项不可用 —— 灰掉并说明原因，不假装能用
#   note       : 本 PASS 未接入的功能。写清楚比弹个空的模态框诚实
const MENU_ITEMS := [
	{"id": "continue", "cn": "继续", "en": "CONTINUE", "needs_save": true, "note": ""},
	{"id": "new", "cn": "新的旅程", "en": "NEW JOURNEY", "needs_save": false, "note": ""},
	{"id": "settings", "cn": "设置", "en": "SETTINGS", "needs_save": false, "note": "设置面板在 UI PASS 02 接入。"},
	{"id": "exit", "cn": "退出", "en": "EXIT", "needs_save": false, "note": "Web 原型不关闭进程；桌面版会退出 Launcher 与游戏。"},
]

# ---------------------------------------------------------------------------
# 缩放：网页侧的字号是 clamp(px, Nvmin, px)，基准视口高 900px。
# Godot 侧用同一个基准换算，分辨率不同才不会把比例搞乱。
# ---------------------------------------------------------------------------
const REFERENCE_HEIGHT := 900.0

static func ui_scale(viewport_height: float) -> float:
	return viewport_height / REFERENCE_HEIGHT

## 网页侧字号是 clamp(minPx, Nvmin, maxPx)，vmin = min(视口宽, 高)。
## Godot 没有 vmin，所以这里用同一个公式算，而不是钉死一个 px。
static func type_px(name: String, viewport_size: Vector2) -> float:
	var t: Array = TYPE[name]
	var vmin := minf(viewport_size.x, viewport_size.y)
	return clampf(t[1] * vmin / 100.0, t[0], t[2])

## 字距（像素）。tracking 是 em，所以要乘字号。
static func track_px(name: String, font_size_px: float) -> float:
	return float(TRACK[name]) * font_size_px

## 版心边距（像素）。与 type_px() 同一个 clamp 公式。
static func gutter_px(viewport_size: Vector2) -> float:
	var vmin := minf(viewport_size.x, viewport_size.y)
	return clampf(GUTTER[1] * vmin / 100.0, GUTTER[0], GUTTER[2])

## 12 栅的第 column 列（1 起）距离左边的像素偏移。
static func grid_col(viewport_size: Vector2, column: int) -> float:
	return viewport_size.x * float(column - 1) / 12.0

## 8vmin（交接帧的标记方框边长）在当前视口下的像素值。
## **夹取上下限**：网页侧 CSS 的 .sk-brand__mark 是 clamp(44px, 8vmin, 92px)，
## 不夹的话超宽比例下 JS 与 CSS 会算出不同边长，交接帧就差几十像素。
static func handoff_mark_side(viewport_size: Vector2) -> float:
	var vmin := minf(viewport_size.x, viewport_size.y)
	var raw := vmin * HANDOFF["mark_side_vmin"] / 100.0
	return clampf(raw, HANDOFF["mark_side_min_px"], HANDOFF["mark_side_max_px"])

## 启动时钟 → "演出开始后第几秒"。BOOT_SEQ / MENU_SEQ 都是"交接帧 = 0"的表，
## BootSplash 与 MainMenu 都从同一刻开始播，所以换算只应该有这一处。
## 谁要是自己写 hold_ms + ms/1000，两段演出就会错开 320ms —— 而错开看不出来。
static func boot_at(ms: float) -> float:
	return (float(HANDOFF["hold_ms"]) + ms) / 1000.0

## 交接帧的标记中心（像素）。
static func handoff_mark_center(viewport_size: Vector2) -> Vector2:
	return Vector2(viewport_size.x * HANDOFF["mark_center_x"], viewport_size.y * HANDOFF["mark_center_y"])
