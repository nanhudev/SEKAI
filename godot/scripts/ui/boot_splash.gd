extends Control
## ============================================================================
## SEKAI · BOOTSPLASH —— 交接帧 + 标题层
## ----------------------------------------------------------------------------
## 这个节点的**第一帧**就是 Launcher 的最后一帧：
##   纯 #060A10 + 屏幕正中、边长 8vmin 的品牌标记（环已写完、点已就位）。
## 这是"启动是一个连续过程"能被验收的唯一依据（HANDOFF 表见
## ui_web/launcher/launcher.config.js，Godot 侧的数值由 emit_tokens.mjs 直接读出，
## 不是手抄的）。
##
## 为什么它叫 BootSplash 却**长期存在**：
##   标记必须从屏幕正中**移动**到品牌位。如果把它拆成"B bootSplash 里一个、
##   菜单里再一个"，就变成了两个节点之间的硬切 —— 而硬切正是这段演出要避免的。
##   所以品牌（标记 + 字标 + 中文名 + 金线 + 副标题）整体归这里，
##   菜单（MainMenu）只管列表与页脚。
##   它同时充当标题画面的背景与世界层（环 / 规则线 / 刻度）。
##
## 不写 class_name：见 ui_theme.gd 的说明（class_name 会牵动被并行会话使用的
## global_script_class_cache.cfg）。
## ============================================================================

signal booted
## 退场跑完了。调用方等到它再切场景 —— 因为**最后一帧必须已经落在交接帧上**。
signal exited

const T := preload("res://scripts/ui/ui_tokens.gd")
const UITheme := preload("res://scripts/ui/ui_theme.gd")
const L := preload("res://scripts/ui/ui_layout.gd")

## 时间基准：交接帧之后先停 HANDOFF.hold_ms —— 这一拍就是"启动是连续的"
## 被人眼读到的地方。之后所有 beat 都以这一刻为 0。
const THIN_SPACE := "\u2009"


# ============================================================================
# 标记：开口的环 + 正中一点
# 几何与 ui_web/svg/library.js 的 mark() 同源（viewBox 128）。
# 角度换算：SVG 用数学角（y 向上），Godot 用屏幕角（y 向下），σ = -α。
# 缺口 = 数学 25°..91°（中心 58°，右上）→ 屏幕 269°..335°。
# 所以弧从屏幕 269° 逆时针画 294°，即 269° → -25°。
# draw_arc 要求 start < end，于是写成 [-25°, 269°]，点集完全相同。
# ============================================================================
class Mark:
	extends Control

	var sweep_deg := 294.0:
		set(v):
			sweep_deg = v
			queue_redraw()
	var dot_scale := 1.0:
		set(v):
			dot_scale = v
			queue_redraw()
	var arc_alpha := 1.0:
		set(v):
			arc_alpha = v
			queue_redraw()
	var dot_alpha := 1.0:
		set(v):
			dot_alpha = v
			queue_redraw()

	const ARC_START_DEG := 269.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var side := minf(size.x, size.y)
		if side <= 0.0:
			return
		var s := side / T.MARK_VIEWBOX
		var c := size * 0.5
		var r := T.MARK_ARC_RADIUS * s

		if sweep_deg > 0.5 and arc_alpha > 0.001:
			var a := Color(T.COLOR["text"], arc_alpha)
			# 线宽是**屏幕像素**，不随方框缩放（对应 SVG 的 non-scaling-stroke）。
			# 这也是交接帧能对上的前提之一。
			var w := maxf(1.0, float(T.HANDOFF["arc_stroke_px"]))
			draw_arc(
				c,
				r,
				deg_to_rad(ARC_START_DEG - sweep_deg),
				deg_to_rad(ARC_START_DEG),
				128,
				a,
				w,
				true
			)

		if dot_scale > 0.001 and dot_alpha > 0.001:
			var rr := T.MARK_DOT_RADIUS * s * dot_scale
			if rr > 0.1:
				draw_circle(c, rr, Color(T.COLOR["gold"], dot_alpha), true, -1.0, true)


# ============================================================================
# 世界层：大环 + 两条规则线 + 金刻度 + 右下次刻度
# 与网页侧 scene_bg.js / scene.css 同一套比例，所以两个页面读起来是同一个世界。
# ============================================================================
class WorldLayer:
	extends Control

	## 环缺口转出的角度。退场时从 0 转到 -58°（= 缺口自己转出画面）。
	## 用 offset 而不是转整棵子树：这里所有几何都是 _draw 出来的，没有 transform 可用。
	var ring_rot_deg := 0.0:
		set(v):
			ring_rot_deg = v
			queue_redraw()

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var vp := size
		if vp.x <= 0.0 or vp.y <= 0.0:
			return
		var line: Color = T.COLOR["line"]
		var brand_x := T.grid_col(vp, 3)

		# 1. 世界的环。缺口与标记同角度 —— 这就是"同一个世界"的证据。
		var ring_c := Vector2(vp.x * 0.74, vp.y * 0.42)
		var ring_r := vp.y * 0.531
		draw_arc(
			ring_c,
			ring_r,
			deg_to_rad(-25.0 + ring_rot_deg),
			deg_to_rad(269.0 + ring_rot_deg),
			240,
			Color(line, 0.5),
			1.0,
			true
		)

		# 2. 上下两条规则线（很淡，只做"纸"的暗示）
		var y_up := vp.y * 0.10
		var y_dn := vp.y * 0.88
		draw_line(Vector2(0, y_up), Vector2(vp.x, y_up), Color(line, 0.10), 1.0, true)
		draw_line(Vector2(0, y_dn), Vector2(vp.x, y_dn), Color(line, 0.10), 1.0, true)

		# 3. 上规则线上的金色记号：标记"这一行被划上了"
		draw_line(
			Vector2(brand_x, y_up),
			Vector2(brand_x + 44.0, y_up),
			Color(T.COLOR["gold"], 0.5),
			1.0,
			true
		)

		# 4. 下规则线右段的刻度：给版面一个"度量"的暗示，从第 6 列起
		var x0 := T.grid_col(vp, 6)
		var n := 16
		for i in range(n):
			var f := float(i) / float(n - 1)
			var x := x0 + (vp.x - x0) * f
			# 两端淡出，避免出现一条硬的边界
			var a := 0.30 * (1.0 - pow(absf(f - 0.5) * 2.0, 2.0))
			draw_line(Vector2(x, y_dn - 2.0), Vector2(x, y_dn + 3.0), Color(line, a), 1.0, true)


# ============================================================================
# 单字母容器：真裁切，不是缩放
# 写字 = 把 Label 从左侧推进裁切窗口。所以笔画粗细不变 —— 用 scale 会变粗，
# 一眼假（这条纪律来自 docs/ui/MOTION_LANGUAGE.md 的 UNFOLD 一节）。
# ============================================================================
class LetterBox:
	extends Control

	var label: Label

	func setup(f: Font, fs_px: int, ch: String, col: Color, advance: float, line_h: float) -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		clip_contents = true
		custom_minimum_size = Vector2(advance, line_h)
		size = custom_minimum_size
		label = Label.new()
		label.text = ch
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.add_theme_font_override("font", f)
		label.add_theme_font_size_override("font_size", fs_px)
		label.add_theme_color_override("font_color", col)
		label.position = Vector2(-advance, 0.0)
		label.size = Vector2(advance * 2.0, line_h)
		add_child(label)

	func put(x: float, y: float) -> void:
		position = Vector2(x, y)

	func hide_glyph() -> void:
		label.position.x = -size.x

	func show_glyph() -> void:
		label.position.x = 0.0


# ============================================================================
# 主脚本
# ============================================================================
var _void: ColorRect
var _grad: TextureRect
var _world: WorldLayer
var _mark: Mark
var _word: Control
var _letters: Array[LetterBox] = []
var _cn: Label
var _rule: ColorRect
var _sub: Label

var _booted := false
var _tween: Tween


func _ready() -> void:
	theme = UITheme.make()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_void = ColorRect.new()
	_void.color = T.COLOR["void"]
	_void.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_void.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_void)

	_grad = _build_gradient()
	add_child(_grad)

	_world = WorldLayer.new()
	_world.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_world.modulate.a = 0.0
	add_child(_world)

	_word = Control.new()
	_word.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_word)

	_cn = _make_label("", T.COLOR["text-2"], 0.0)
	add_child(_cn)

	_rule = ColorRect.new()
	_rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rule.modulate.a = 0.0
	add_child(_rule)

	_sub = _make_label("", T.COLOR["text-3"], 0.0)
	# 副标题是 500（中黑）+ 无衬线，与网页 .sk-menu__sub 一致。
	_sub.add_theme_font_override("font", UITheme.sans("medium"))
	add_child(_sub)

	_mark = Mark.new()
	_mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_mark)

	get_viewport().size_changed.connect(_on_viewport_resized)
	layout()
	reset_to_handoff()


func _make_label(text: String, col: Color, alpha: float) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_color_override("font_color", col)
	l.modulate.a = alpha
	return l


func _build_gradient() -> TextureRect:
	# 网页侧的 .sk-bg__grad 是一个 radil-gradient。Godot 用 GradientTexture2D
	# 的径向填充表达同一个东西（同一组颜色、同一个光源位置）。
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	grad.colors = PackedColorArray([
		Color("16232e"),
		Color("0c141a"),
		T.COLOR["void"],
	])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.72, 0.42)
	tex.fill_to = Vector2(1.15, 0.42)
	tex.width = 512
	tex.height = 512

	var tr := TextureRect.new()
	tr.texture = tex
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tr.modulate.a = 0.0
	return tr


# ---------------------------------------------------------------------------
# 版面 —— 全部走 ui_layout.gd（12 栅结构，与网页原型逐项对齐，audit 核对）
# ---------------------------------------------------------------------------
func layout() -> void:
	var vp := get_viewport_rect().size
	if vp.x <= 0.0 or vp.y <= 0.0:
		return

	var brand_x := L.col_x(vp, 3)
	var fs_word := T.type_px("display", vp)
	var lh_word := L.word_lh(vp)
	var fs_cn := T.type_px("head", vp)
	var lh_cn := L.cn_lh(vp)
	var fs_sub := T.type_px("micro", vp)
	var lh_sub := L.sub_lh(vp)
	var mark_home := L.mark_side(vp)

	# 品牌块在第 1 行（1fr）里垂直居中。以前这里是 vp.y * 0.5244 的魔数 ——
	# 那个值只在 900px 高的视口下成立（472/900），换分辨率就整体偏。
	# 现在由 ui_layout 按 CSS 的三行结构算出来。
	var slots := L.brand_slots(vp)
	var y_word: float = slots["word"]
	var y_cn: float = slots["cn"]
	var y_rule: float = slots["rule"]
	var y_sub: float = slots["sub"]
	var y_mark: float = slots["mark"]

	# 字标：逐字母排版。Godot 的 Label 没有 letter-spacing，
	# 而宽字距是本设计的主要呼吸手段，所以只能自己摆。
	_build_word(brand_x, y_word, fs_word, lh_word)

	_cn.text = T.COPY["wordmark_cn"]
	_cn.add_theme_font_size_override("font_size", int(round(fs_cn)))
	_cn.position = Vector2(brand_x, y_cn)
	_cn.size = Vector2(vp.x - brand_x, lh_cn)

	_rule.position = Vector2(brand_x, y_rule)
	_rule.size = Vector2(48.0, 1.0)
	_rule.color = T.COLOR["gold"]

	_sub.text = _spaced(String(T.COPY["subtitle"]))
	_sub.add_theme_font_size_override("font_size", int(round(fs_sub)))
	_sub.position = Vector2(brand_x, y_sub)
	_sub.size = Vector2(vp.x - brand_x, lh_sub)

	_mark.position = Vector2(brand_x, y_mark)
	_mark.size = Vector2(mark_home, mark_home)

	# 标记的"家"记下来 —— play_boot() 要从正中央飞到这里。
	set_meta("home_pos", Vector2(brand_x, y_mark))
	set_meta("home_size", Vector2(mark_home, mark_home))


func _build_word(x: float, y: float, fs: float, lh: float) -> void:
	for b in _letters:
		b.queue_free()
	_letters.clear()

	# 字标是 300（轻）。SystemFont 默认 400 —— 不给就会显得比网页"重"。
	var f: Font = UITheme.serif("light")
	var size_i := int(round(fs))
	var track := T.track_px("wide", fs)
	var word := String(T.COPY["wordmark"])
	var cur := x
	for i in range(word.length()):
		var ch := word.substr(i, 1)
		var advance := f.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, size_i).x
		var box := LetterBox.new()
		_word.add_child(box)
		box.setup(f, size_i, ch, T.COLOR["text"], advance, lh)
		box.put(cur, y)
		_letters.append(box)
		cur += advance + track


## 把 "ABC" 变成 "A B C"，用窄空格近似 letter-spacing。
## 元信息与副标题需要宽字距，但 Label 没有 letter-spacing —— 这是最省事的近似。
func _spaced(s: String) -> String:
	var out := ""
	for i in range(s.length()):
		if i > 0:
			out += THIN_SPACE
		out += s.substr(i, 1)
	return out


# ---------------------------------------------------------------------------
# 交接帧
# ---------------------------------------------------------------------------
## 把画面拨回 Launcher 的最后一帧。**第一帧必须由它决定。**
func reset_to_handoff() -> void:
	var vp := get_viewport_rect().size
	var side := T.handoff_mark_side(vp)
	var centre := T.handoff_mark_center(vp)
	_mark.size = Vector2(side, side)
	_mark.position = centre - Vector2(side, side) * 0.5
	_mark.sweep_deg = float(T.HANDOFF["arc_progress"]) * 294.0
	_mark.dot_scale = float(T.HANDOFF["dot_progress"])
	_mark.arc_alpha = 1.0
	_mark.dot_alpha = 1.0

	_grad.modulate.a = 0.0
	_world.modulate.a = 0.0
	# 环的缺口要转回原位 —— 退场把它转了 -58°，不复位的话第二次启动
	# 世界会长得和第一次不一样，而"不一样"没人会归因到上一次的退场。
	_world.ring_rot_deg = 0.0
	for b in _letters:
		b.hide_glyph()
	_cn.modulate.a = 0.0
	_rule.modulate.a = 0.0
	_sub.modulate.a = 0.0


# ---------------------------------------------------------------------------
# 开场演出
# ---------------------------------------------------------------------------
## 时间基准：交接帧之后 HANDOFF.hold_ms。秒。
## 换算本身在 ui_tokens.gd 的 boot_at() 里 —— MainMenu 用的是同一支时钟，
## 两处各写一遍就会错开 320ms，而错开是看不出来的（两边各自都"对"）。
func _at(ms: float) -> float:
	return T.boot_at(ms)


func play_boot() -> void:
	reset_to_handoff()
	var beats: Dictionary = T.BOOT_SEQ
	var durs: Dictionary = T.BOOT_DUR

	var home_pos: Vector2 = get_meta("home_pos")
	var home_size: Vector2 = get_meta("home_size")

	_tween = create_tween().set_parallel(true)

	# 1. 标记回家。**先停一拍再动** —— 这一拍（markHomeDelay）就是"启动是连续的"
	#    被人眼读到的地方：在此之前画面与 Launcher 的最后一帧逐像素相同。
	#    这两个数不是这里写死的，来自 main_menu.config.js，由 emit_tokens.mjs 生成。
	var fly_ms: float = float(T.MENU_DUR["markHome"])
	var fly_delay: float = _at(float(T.MENU_DUR["markHomeDelay"]))
	var fly_sec := fly_ms / 1000.0
	_tween.tween_property(_mark, "position", home_pos, fly_sec).set_delay(fly_delay).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_property(_mark, "size", home_size, fly_sec).set_delay(fly_delay).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	# 2. 世界层与渐变随演出出现（不是一上来就在）。
	#    顺序与网页侧一致：先规则线（runes 1250），后光（bgMove 1500）。
	#    `_world` 一个节点同时画了环和规则线，网页侧是两次调用 ——
	#    中间那 250ms 的差别不值得再拆一个节点出来。
	_tween.tween_property(_world, "modulate:a", 1.0, float(durs["rune"]) / 1000.0).set_delay(_at(float(beats["runes"])))
	_tween.tween_property(_grad, "modulate:a", 1.0, float(durs["bgFade"]) / 1000.0).set_delay(_at(float(beats["bgMove"])))

	# 3. 字标逐字写出。BOOT_SEQ 里这一拍叫 wordmark（web 侧是 SEQUENCE.full.beats.wordmark）。
	var letter_dur := float(durs["letter"]) / 1000.0
	var stagger := float(durs["letterStagger"]) / 1000.0
	var word_at := float(beats["wordmark"])
	for i in range(_letters.size()):
		var b := _letters[i]
		_tween.tween_property(b.label, "position:x", 0.0, letter_dur).set_delay(
			_at(word_at + i * stagger * 1000.0)
		).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	# 4. 中文名 / 金线 / 副标题
	_tween.tween_property(_cn, "modulate:a", 1.0, float(durs["wordmarkCN"]) / 1000.0).set_delay(_at(float(beats["wordmarkCN"])))
	_tween.tween_property(_rule, "modulate:a", 1.0, float(durs["rule"]) / 1000.0).set_delay(_at(float(beats["rule"])))
	_tween.tween_property(_sub, "modulate:a", 1.0, float(durs["subtitle"]) / 1000.0).set_delay(_at(float(beats["subtitle"])))

	_tween.finished.connect(_on_boot_finished, CONNECT_ONE_SHOT)


func _on_boot_finished() -> void:
	if _booted:
		return
	_booted = true
	booted.emit()


# ---------------------------------------------------------------------------
# 退场 —— 终点与起点是**同一帧**
# ---------------------------------------------------------------------------
## 退场里各段动作的时长（秒）。与 ui_web/main_menu/main_menu.js 的 enterWorld()
## 是同一组数 —— 那边是"擦除 + 环转 58° + 环境退下 + 标记归位"。
const EXIT_BRAND_DELAY := 0.08
const EXIT_BRAND_DUR := 0.28
const EXIT_RING_DELAY := 0.24
const EXIT_RING_DUR := 1.70
const EXIT_ENV_DELAY := 0.48
const EXIT_ENV_DUR := 0.90


## 从调用 play_exit() 到**画面等于交接帧**所需的时间（秒）。
##
## 注意：交接帧成立的时刻是**最后一个动作**结束的时刻，不是标记飞完的时刻。
## 这里环的旋转最长（0.24 + 1.70 = 1.94s），比标记（0.62 + 0.78 = 1.40s）晚。
## 网页侧不等它 —— 窗口直接就关了；Godot 必须等，否则切场景时环还在转，
## 而那时目标场景的第一帧已经不是交接帧了。
func exit_total_sec() -> float:
	var d := float(T.MENU_EXIT["mark_delay_ms"]) / 1000.0
	var r := float(T.MENU_EXIT["mark_dur_ms"]) / 1000.0
	var h := float(T.MENU_EXIT["hold_ms"]) / 1000.0
	return maxf(
		maxf(d + r + h, EXIT_RING_DELAY + EXIT_RING_DUR),
		maxf(EXIT_ENV_DELAY + EXIT_ENV_DUR, EXIT_BRAND_DELAY + EXIT_BRAND_DUR)
	)


## 把画面送回交接帧：环境全部退下，只剩纯色 + 正中的标记。
##
## 这是"进入世界"的第一步。它存在的意义是让**切换场景的那一刻**画面与
## 目标场景的第一帧是同一种画面 —— 否则切场景就是一次硬跳，
## 而硬跳正是整条启动链路一直在避免的东西。
func play_exit() -> void:
	var vp := get_viewport_rect().size
	if vp.x <= 0.0 or vp.y <= 0.0:
		return
	if _tween and _tween.is_valid():
		_tween.kill()

	var d_mark := float(T.MENU_EXIT["mark_delay_ms"]) / 1000.0
	var r_mark := float(T.MENU_EXIT["mark_dur_ms"]) / 1000.0

	var side := T.handoff_mark_side(vp)
	var centre := T.handoff_mark_center(vp)
	var target_pos := centre - Vector2(side, side) * 0.5

	_tween = create_tween().set_parallel(true)

	# 1. 品牌退下（字标 / 中文名 / 金线 / 副标题）。与网页一样是"擦除"不是"淡出"，
	#    这里用位移 + 淡出近似 —— Label 没有 clip，只能靠这个。
	for b in _letters:
		_tween.tween_property(b.label, "position:x", -b.size.x, EXIT_BRAND_DUR).set_delay(EXIT_BRAND_DELAY)
	_tween.tween_property(_cn, "modulate:a", 0.0, EXIT_BRAND_DUR).set_delay(EXIT_BRAND_DELAY)
	_tween.tween_property(_rule, "modulate:a", 0.0, EXIT_BRAND_DUR).set_delay(EXIT_BRAND_DELAY + 0.04)
	_tween.tween_property(_sub, "modulate:a", 0.0, EXIT_BRAND_DUR).set_delay(EXIT_BRAND_DELAY + 0.08)

	# 2. 世界"合上"：环的缺口转出画面。这是唯一一处允许有仪式感的动作。
	_tween.tween_property(_world, "ring_rot_deg", -58.0, EXIT_RING_DUR).set_delay(EXIT_RING_DELAY).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	# 3. 环境退下 → 只剩纯色（= HANDOFF.bg）
	_tween.tween_property(_world, "modulate:a", 0.0, EXIT_ENV_DUR).set_delay(EXIT_ENV_DELAY)
	_tween.tween_property(_grad, "modulate:a", 0.0, EXIT_ENV_DUR).set_delay(EXIT_ENV_DELAY)

	# 4. 标记归位：移到正中**并缩放到交接尺寸**。
	#    尺寸必须一起动 —— 品牌位是 4.4vmin，交接帧是 8vmin，
	#    只动位置会停在一个"大小不对的居中标记"上，而那和正确的帧看着一样居中。
	_tween.tween_property(_mark, "position", target_pos, r_mark).set_delay(d_mark).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_property(_mark, "size", Vector2(side, side), r_mark).set_delay(d_mark).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	# 全部结束之后再落点校正并报出去。chain() = 等前面所有 tweener 结束。
	_tween.chain().tween_callback(_on_exit_finished)


func _on_exit_finished() -> void:
	# 落点校正：tween 有浮点误差，而"交接帧"这个词要求精确等值。
	reset_to_handoff()
	exited.emit()


## 直接落到演出终态，不播。用于"从游戏回到标题"。
## （那时演出早就该结束了，再播一次会读成卡顿。）
func show_settled() -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	visible = true
	_grad.modulate.a = 1.0
	_world.modulate.a = 1.0
	for b in _letters:
		b.show_glyph()
	_cn.modulate.a = 1.0
	_rule.modulate.a = 1.0
	_sub.modulate.a = 1.0
	# 标记回到"家"。**不要**在这里重算位置 —— layout() 已经把家记下来了，
	# 重算一遍等于把同一件事写两处，迟早会不一致。
	_mark.position = get_meta("home_pos")
	_mark.size = get_meta("home_size")
	_booted = true


func _on_viewport_resized() -> void:
	layout()
	# 演出跑完之后再改窗口：直接落到终态，不要跳着播一遍。
	if _booted:
		show_settled()
	else:
		reset_to_handoff()
