extends RefCounted
## ============================================================================
## SEKAI · UI 主题 / 字体
## ----------------------------------------------------------------------------
## 工程里**没有任何字体资产**：没有 .ttf/.otf，没有 Theme 资源，也没有
## default_font 覆盖。后果是所有中文都渲染成豆腐块 —— 这是 UI PASS 01
## 审计里优先级最高的一条缺陷。
##
## 修法：SystemFont + font_names 回退链。
##   · 不引入任何字体文件，所以没有任何授权问题（ASSET_LICENSES.md 不用改）
##   · 回退链里每一款 Windows 都至少装了一款（SimSun / Microsoft YaHei 是系统自带）
##   · 想换正式字体时，只需把 .ttf 放进 assets_source/ui/fonts/ 并在这里加一条
##
## 不写 class_name：加了 class_name 就必须跑一次 `--editor --quit` 去重建
## global_script_class_cache.cfg，而那个文件正被并行会话的 import 使用。
## 用 preload 引用这个脚本就没有这个问题。
## ============================================================================

const T := preload("res://scripts/ui/ui_tokens.gd")

## 衬线：标题 / 品牌 / 地点名。中文优先思源宋体，回退到系统宋体。
const SERIF_NAMES := [
	"Source Han Serif SC",
	"Noto Serif SC",
	"Songti SC",
	"SimSun",
	"serif",
]

## 无衬线：正文 / 菜单项 / 元信息。
const SANS_NAMES := [
	"Inter",
	"Noto Sans SC",
	"Microsoft YaHei",
	"PingFang SC",
	"Segoe UI",
	"sans-serif",
]


static func _sysfont(names: Array, weight: int = -1) -> SystemFont:
	var f := SystemFont.new()
	var packed := PackedStringArray()
	for n in names:
		packed.append(String(n))
	f.font_names = packed
	# 系统里第一款存在的就用它；一款都没有时 Godot 会自己回退，
	# 不会崩，只是字形可能不对。宁可这样也不要空指针。
	f.allow_system_fallback = true
	# 字重必须显式给：SystemFont 默认 400，而字标是 300、元信息是 500。
	# 300 与 400 的差别在宽字距大字上是一眼可见的 —— 那是"看起来就是不太对"
	# 的典型来源。数值来自 tokens.css 的 --sk-fw-*，由 emitter 生成。
	if weight > 0:
		f.font_weight = weight
	return f


## weight 传 T.WEIGHT 里的键（"light" / "regular" / "medium" / "semi"）；
## 不传或传了不存在的键 = 用字体默认字重。
static func serif(weight: String = "") -> SystemFont:
	return _sysfont(SERIF_NAMES, _weight_of(weight))


static func sans(weight: String = "") -> SystemFont:
	return _sysfont(SANS_NAMES, _weight_of(weight))


static func _weight_of(key: String) -> int:
	if key.is_empty() or not T.WEIGHT.has(key):
		return -1
	return int(T.WEIGHT[key])


## 根 Control 挂上这个主题，整棵子树就都有字体了。
## （Label / Button 都会从最近的 theme 继承 default_font。）
static func make() -> Theme:
	var th := Theme.new()
	# 正文默认按 regular，标题由各自 add_theme_font_override 覆盖。
	th.default_font = serif("regular")
	th.default_font_size = 18
	return th


## 给单个 Control 加字体覆盖。用于需要换字族的少数地方（例如元信息用无衬线）。
static func use_sans(c: Control, size_px: int, weight: String = "") -> void:
	c.add_theme_font_override("font", sans(weight))
	c.add_theme_font_size_override("font_size", size_px)


static func use_serif(c: Control, size_px: int, weight: String = "") -> void:
	c.add_theme_font_override("font", serif(weight))
	c.add_theme_font_size_override("font_size", size_px)
