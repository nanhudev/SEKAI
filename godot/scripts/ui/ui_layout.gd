extends RefCounted
## ============================================================================
## SEKAI · UI LAYOUT —— 12 栅结构（Launcher / BootSplash / MainMenu 共用）
## ----------------------------------------------------------------------------
## 网页侧这套版式是 CSS Grid：
##
##     .sk-menu { grid-template-columns: repeat(12, 1fr);
##                grid-template-rows: 1fr auto auto; }
##     .sk-menu__brand { grid-column: 3 / span 7; grid-row: 1; align-self: center }
##     .sk-menu__nav   { grid-column: 3 / span 3; grid-row: 2 }
##     .sk-meta-bar    { grid-column: 1 / -1;     grid-row: 3 }
##
## Godot 没有栅格布局，所以整块版式必须自己算。算错不会报错 —— 只会"看着差一点"，
## 而"差一点"正是这类界面最贵的问题。所以这里只做一件事：
## **把上面那张栅格表照抄成算术**，然后由 tools/audit_ui_layout.gd 拿网页实测值核对。
##
## 参考值来自对网页原型的 probe（1600×900，冻结在 t=4200ms 的终态）：
##
##     .sk-menu__brand   x=267  y=110  w=933  h=253
##     #nav              x=267  y=472  w=400  h=385
##     .sk-item          h=68   （padding 8/8、间距 8）
##     .sk-meta-bar      y=856.6  h=43.4
##
## 这几个数在下面全部能被**算出来**，不是写死的：
##   行高 1fr = 900 - 385 - 43.4 = 471.6  →  品牌高 253 居中 → y = 109.5 ✓
##   nav 高   = 1(border) + 24(pad-top) + 4×68 + 3×8(gap) + 64(pad-bottom) = 385 ✓
##
## 唯一对不齐的地方是 .sk-item__cn / __en 的 line-height: normal —— 那是**字体度量**
## 决定的，不是 token。Godot 换字体就会差几个像素，这是物理上限，不是疏忽。
## 其余每一项都是逐像素相等，audit 会逐项核对。
## ============================================================================

const T := preload("res://scripts/ui/ui_tokens.gd")

## 参考视口与网页实测值（audit 的比对基准，改版式时要重新 probe 并更新这里）
const REF_VP := Vector2(1600, 900)
const REF_NAV := Rect2(267.0, 472.0, 400.0, 385.0)
const REF_FOOTER_H := 43.4
const REF_BRAND_TOP := 110.0
const REF_BRAND_H := 253.0
const REF_ITEM_H := 68.0

## .sk-item__cn / __en 的 line-height 是 `normal`，即字体度量。
## 900px 参考视口下的实测比例（字号 → 行盒高）：
##   cn 24.03px → 34.97px = 1.455×      en 11.97px → 14.03px = 1.172×
## 这两个数**只在这一处**是"抄来的"，其余全部由 token 推出。
const CN_NORMAL_RATIO := 1.455
const EN_NORMAL_RATIO := 1.172

## .sk-item 的边框/内边距（CSS: padding: var(--sk-s2) 0 var(--sk-s2) calc(var(--sk-s5) + 14px)）
const ITEM_PAD_X := 14.0
const ITEM_EN_MARGIN_TOP := 3.0


# ---------------------------------------------------------------------------
# 横向：12 栅
# ---------------------------------------------------------------------------
## 第 column 列（1 起）的左边缘。grid-column: 3 → x = 宽 × 2/12。
static func col_x(vp: Vector2, column: int) -> float:
	return vp.x * float(column - 1) / 12.0


## span 跨列的宽度。grid-column: 3 / span 3 → 宽 × 3/12。
static func col_w(vp: Vector2, span: int) -> float:
	return vp.x * float(span) / 12.0


# ---------------------------------------------------------------------------
# 纵向：三行（1fr / auto / auto）
# ---------------------------------------------------------------------------
## 页脚高 = 内边距 s5 + 一行 micro 文字。
## CSS: .sk-meta-bar { padding: 0 var(--sk-gutter) var(--sk-s5) }
static func footer_h(vp: Vector2) -> float:
	return float(T.SPACE["s5"]) + T.type_px("micro", vp) * float(T.LINE["body"])


## 一个菜单项行高。CSS: padding s2 上下，中文一行、英文一行，英文上边距 3px。
static func item_h(vp: Vector2) -> float:
	var cn := T.type_px("head", vp) * CN_NORMAL_RATIO
	var en := T.type_px("micro", vp) * EN_NORMAL_RATIO
	return float(T.SPACE["s2"]) * 2.0 + cn + ITEM_EN_MARGIN_TOP + en


## 菜单左内边距：CSS 里是 calc(s5 + 14px)，给左侧刻度留位。
static func item_pad_left() -> float:
	return float(T.SPACE["s5"]) + ITEM_PAD_X


## 导航块高。CSS: border-top 1px + padding s5 0 s8，项之间 gap s2。
## item_count 默认取 token 表 —— 菜单项的**唯一真相源**就是那张表，
## 所以这里不需要调用方传参，也就不可能两边算的不是同一件事。
static func nav_h(vp: Vector2, item_count: int = -1) -> float:
	var n := item_count if item_count >= 0 else T.MENU_ITEMS.size()
	if n <= 0:
		return 1.0 + float(T.SPACE["s5"]) + float(T.SPACE["s8"])
	var gaps := float(n - 1) * float(T.SPACE["s2"])
	return (
		1.0
		+ float(T.SPACE["s5"])
		+ float(n) * item_h(vp)
		+ gaps
		+ float(T.SPACE["s8"])
	)


## 导航块顶边。三行是 1fr / auto / auto，所以导航紧贴在页脚上方。
static func nav_top(vp: Vector2, item_count: int = -1) -> float:
	return vp.y - footer_h(vp) - nav_h(vp, item_count)


## 页脚顶边（= 导航底边，两者必须相等 —— audit 核对的就是这一条）。
static func footer_top(vp: Vector2) -> float:
	return vp.y - footer_h(vp)


# ---------------------------------------------------------------------------
# 品牌块
# ---------------------------------------------------------------------------
## 标记边长。CSS: width/height clamp(28px, 4.4vmin, 56px)
static func mark_side(vp: Vector2) -> float:
	return clampf(minf(vp.x, vp.y) * 0.044, 28.0, 56.0)


## 字标行高。CSS: .sk-menu__word { font-size: fs-display; line-height: lh-tight }
static func word_lh(vp: Vector2) -> float:
	return T.type_px("display", vp) * float(T.LINE["tight"])


## 中文名行高。**没有显式 line-height → 继承 body 的 1.62**，不是标题的 1.12/1.34。
## 按 1.34 算会让品牌块矮 15px、整块上移 7px。
static func cn_lh(vp: Vector2) -> float:
	return T.type_px("head", vp) * float(T.LINE["body"])


## 副标题行高。同样继承 body。
static func sub_lh(vp: Vector2) -> float:
	return T.type_px("micro", vp) * float(T.LINE["body"])


## 品牌块的**内容**高：标记 → 字标 → 中文名 → 金线 → 副标题，中间是 s5/s3/s4/s4。
static func brand_content_h(vp: Vector2) -> float:
	return (
		mark_side(vp)
		+ float(T.SPACE["s5"])
		+ word_lh(vp)
		+ float(T.SPACE["s3"])
		+ cn_lh(vp)
		+ float(T.SPACE["s4"])
		+ 1.0
		+ float(T.SPACE["s4"])
		+ sub_lh(vp)
	)


## 品牌块的**盒子**高 = 内容高 + padding-bottom s6。
## CSS 里 .sk-menu__brand 有 padding-bottom，居中算的是**盒子**，
## 所以漏掉这 32px 会让整块品牌上移 16px。
static func brand_box_h(vp: Vector2) -> float:
	return brand_content_h(vp) + float(T.SPACE["s6"])


## 品牌块盒子顶边：在第 1 行（1fr）里垂直居中。
static func brand_top(vp: Vector2, item_count: int = -1) -> float:
	return (nav_top(vp, item_count) - brand_box_h(vp)) * 0.5


## 品牌块内各元素的纵向位置（相对屏幕顶）。
static func brand_slots(vp: Vector2, item_count: int = -1) -> Dictionary:
	var top := brand_top(vp, item_count)
	var y_mark := top
	var y_word := y_mark + mark_side(vp) + float(T.SPACE["s5"])
	var y_cn := y_word + word_lh(vp) + float(T.SPACE["s3"])
	var y_rule := y_cn + cn_lh(vp) + float(T.SPACE["s4"])
	var y_sub := y_rule + 1.0 + float(T.SPACE["s4"])
	return {
		"mark": y_mark,
		"word": y_word,
		"cn": y_cn,
		"rule": y_rule,
		"sub": y_sub,
		"bottom": y_sub + sub_lh(vp),
	}


## 菜单项第 index 项（0 起）的顶边。
static func item_top(vp: Vector2, index: int) -> float:
	return nav_top(vp) + 1.0 + float(T.SPACE["s5"]) + float(index) * (item_h(vp) + float(T.SPACE["s2"]))
