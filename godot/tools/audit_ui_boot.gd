extends SceneTree
## UI-01 BOOT AUDIT — 交接合同与开场演出的自动验收（headless）。
##
## 为什么需要它：`--check-only` 只证明语法没错。它管不了下面这些事 ——
## 而这几件事全都是"看着像对的、跑起来是错的"那一类：
##   · 交接帧是不是真的等于 Launcher 的最后一帧（几何、颜色、透明度逐项）
##   · hold 那一拍画面是不是真的**完全不动**
##   · 演出的各个 beat 到点了没有（tween 的 delay 算错不会报错，只会不动）
##   · booted 有没有在预期时刻发出来
##   · show_settled() 落点是不是等于 home
##
## 本次它抓到的真问题：play_boot() 里按 MENU 的命名去读 BOOT 的表
## （letters / cn / scene 在 BOOT_SEQ / BOOT_DUR 里都不存在）。解析检查全绿，
## 一跑演出就断，后面所有 tween 都没建出来。
##
## 运行：
##   Godot --headless --path godot --script res://tools/audit_ui_boot.gd
## 退出码 0 = 全部通过，1 = 有 FAIL。
##
## 两个 headless 陷阱（都踩过）：
##   1. `add_child()` 之后 `_ready()` 还没跑 —— 必须等下一帧再读子节点。
##   2. headless 下 root viewport 固定 64×64 且**没有 vsync**，帧率上千。
##      "跑 N 帧"不等于"跑了几秒"，一切按累加的 delta 推进。


const T := preload("res://scripts/ui/ui_tokens.gd")
const EPS := 0.02

var _splash: Control
var _t := 0.0
var _setup := false
var _booted_at := -1.0
var _checks := 0
var _fails: Array[String] = []
var _vp := Vector2.ZERO
## 检查点：[到达时刻(秒), 名称, 回调]
var _cps: Array = []
var _cp := 0
## 退场阶段：起点时刻（-1 = 还没开始）与它自报的时长
var _exit_start := -1.0
var _exit_seconds := 0.0


func _initialize() -> void:
	root.size = Vector2i(1600, 900)
	var scr: GDScript = load("res://scripts/ui/boot_splash.gd")
	# 加载失败时必须当场判死。**第一次就是这样漏过去的**：脚本没编过 → splash 是 null
	# → 所有检查点都没跑 → 断言数 0 → 打印"全部通过"。绿色的假报告比红色的真错误危险。
	if scr == null:
		print("UI BOOT AUDIT 失败：boot_splash.gd 未能加载（语法/依赖错误）。")
		quit(1)
		return
	_splash = scr.new()
	if _splash == null:
		print("UI BOOT AUDIT 失败：boot_splash.gd 无法实例化。")
		quit(1)
		return
	root.add_child(_splash)
	_splash.booted.connect(func() -> void: _booted_at = _t)

	# 时间点都留了余量：headless 的帧可能吃到 ~10ms 的粒度。
	_cps = [
		[0.00, "交接帧", _check_handoff],
		[0.30, "hold 期画面完全不动", _check_hold],
		[1.45, "标记已归位", _check_mark_home],
		[2.95, "字标已逐字写出", _check_wordmark],
		[4.60, "演出结束 · booted 已发出", _check_finished],
	]


# ---------------------------------------------------------------------------
# 断言工具
# ---------------------------------------------------------------------------
func _ok(cond: bool, label: String, got: Variant, want: Variant) -> void:
	_checks += 1
	if cond:
		print("  PASS  %-34s %s" % [label, got])
	else:
		print("  FAIL  %-34s got=%s  want=%s" % [label, got, want])
		_fails.append(label)


func _near(a: float, b: float, eps := EPS) -> bool:
	return absf(a - b) <= eps


func _nearv(a: Vector2, b: Vector2, eps := EPS) -> bool:
	return a.distance_to(b) <= eps


func _mark() -> Control:
	return _splash.get("_mark")


# ---------------------------------------------------------------------------
# 检查点
# ---------------------------------------------------------------------------
## 这一帧必须与 Launcher 的最后一帧逐项相同。这是"启动是一个连续过程"
## 唯一能被机器验收的地方 —— 不是靠看，是靠比对数值。
func _check_handoff() -> void:
	print("[t=%.2fs] 交接帧：必须等于 Launcher 最后一帧" % _t)
	var side := T.handoff_mark_side(_vp)
	var centre := T.handoff_mark_center(_vp)
	var m := _mark()

	_ok(_nearv(m.size, Vector2(side, side)), "标记边长 = 8vmin",
		m.size, Vector2(side, side))
	_ok(_nearv(m.position, centre - Vector2(side, side) * 0.5), "标记居中于屏幕正中",
		m.position, centre - Vector2(side, side) * 0.5)
	_ok(_near(m.get("sweep_deg"), float(T.HANDOFF["arc_progress"]) * T.MARK_ARC_SWEEP_DEG),
		"环已写完 (arc_progress × 294°)", m.get("sweep_deg"),
		float(T.HANDOFF["arc_progress"]) * T.MARK_ARC_SWEEP_DEG)
	_ok(_near(float(m.get("dot_scale")), float(T.HANDOFF["dot_progress"])),
		"点已就位 (dot_progress)", m.get("dot_scale"), T.HANDOFF["dot_progress"])
	_ok(_near(float(m.get("arc_alpha")), 1.0) and _near(float(m.get("dot_alpha")), 1.0),
		"环与点都不透明", [m.get("arc_alpha"), m.get("dot_alpha")], 1.0)

	var void_rect: ColorRect = _splash.get("_void")
	_ok(void_rect.color.is_equal_approx(T.HANDOFF["bg"]), "底色 = HANDOFF.bg",
		void_rect.color, T.HANDOFF["bg"])

	# 品牌其余部分必须**完全不可见** —— 否则"纯色 + 正中的标记"这句话就不成立。
	var all_hidden := _near(float(_splash.get("_grad").modulate.a), 0.0) \
		and _near(float(_splash.get("_world").modulate.a), 0.0) \
		and _near(float(_splash.get("_cn").modulate.a), 0.0) \
		and _near(float(_splash.get("_rule").modulate.a), 0.0) \
		and _near(float(_splash.get("_sub").modulate.a), 0.0)
	var letters: Array = _splash.get("_letters")
	var letters_hidden := true
	for b in letters:
		if not _near(b.label.position.x, -b.size.x):
			letters_hidden = false
	_ok(all_hidden, "渐变/世界/中文名/金线/副标题 全部不可见", all_hidden, true)
	_ok(letters_hidden, "字标 %d 个字母全部未写出" % letters.size(), letters_hidden, true)


## hold（markHomeDelay）这一拍是"连续"被人眼读到的地方：画面必须一动不动。
func _check_hold() -> void:
	print("[t=%.2fs] hold 期：飞行尚未开始，画面应完全静止" % _t)
	var side := T.handoff_mark_side(_vp)
	var centre := T.handoff_mark_center(_vp)
	var m := _mark()
	_ok(_nearv(m.position, centre - Vector2(side, side) * 0.5), "标记仍在正中",
		m.position, "centre")
	_ok(_near(float(_splash.get("_world").modulate.a), 0.0), "世界层仍未出现",
		_splash.get("_world").modulate.a, 0.0)


func _check_mark_home() -> void:
	print("[t=%.2fs] 飞行结束：标记应已在品牌位" % _t)
	var m := _mark()
	_ok(_nearv(m.position, _splash.get_meta("home_pos")), "标记落点 = home_pos",
		m.position, _splash.get_meta("home_pos"))
	_ok(_nearv(m.size, _splash.get_meta("home_size")), "标记尺寸 = home_size",
		m.size, _splash.get_meta("home_size"))


func _check_wordmark() -> void:
	print("[t=%.2fs] 字标：应已逐字写出" % _t)
	var letters: Array = _splash.get("_letters")
	var n := 0
	for b in letters:
		if _near(b.label.position.x, 0.0, 0.5):
			n += 1
	_ok(n == letters.size(), "全部 %d 个字母已写出" % letters.size(), n, letters.size())
	_ok(_near(float(_splash.get("_world").modulate.a), 1.0), "世界层已完全出现",
		_splash.get("_world").modulate.a, 1.0)


func _check_finished() -> void:
	print("[t=%.2fs] 收尾：品牌整体就位，booted 应已发出" % _t)
	# 各元素的结束时刻：世界 2.47s · 字标 2.92s · 中文名 3.32s · 金线 3.58s
	# · 渐变 3.62s · 副标题 3.90s。到 4.6s 全应到 1，booted 也应在 3.90s 前后。
	for pair in [["_grad", "渐变"], ["_world", "世界层"], ["_cn", "中文名"], ["_rule", "金线"], ["_sub", "副标题"]]:
		var a: float = _splash.get(pair[0]).modulate.a
		_ok(_near(a, 1.0), "%s 已到终值 a=1" % pair[1], a, 1.0)
	_ok(_booted_at > 0.0, "booted 信号已发出", _booted_at, ">0")
	_ok(_near(_booted_at, 3.90, 0.12), "booted 时刻 ≈ 3.90s", _booted_at, 3.90)

	# 回标题路径：必须直接落在终态，且落点等于 home。
	_splash.show_settled()
	var m := _mark()
	_ok(_nearv(m.position, _splash.get_meta("home_pos")), "show_settled 落点 = home_pos",
		m.position, _splash.get_meta("home_pos"))
	_ok(_nearv(m.size, _splash.get_meta("home_size")), "show_settled 尺寸 = home_size",
		m.size, _splash.get_meta("home_size"))


## 退场必须**精确**落回交接帧 —— 与进场第一帧逐项相同。
## 这是"进入世界"和"回到标题"都能和启动链路无缝接上的唯一依据。
## 曾经这里是错的：只把标记移到正中、不改尺寸，于是退场停在一个 4.4vmin 的
## 居中标记上，而交接帧是 8vmin。两帧都"是纯色 + 正中一个标记"，肉眼看不出来。
func _check_exit_lands_on_handoff() -> void:
	print("[t=%.2fs] 退场：必须逐项等于交接帧" % _t)
	var side := T.handoff_mark_side(_vp)
	var centre := T.handoff_mark_center(_vp)
	var m := _mark()

	_ok(_nearv(m.position, centre - Vector2(side, side) * 0.5), "标记回到屏幕正中",
		m.position, centre - Vector2(side, side) * 0.5)
	_ok(_nearv(m.size, Vector2(side, side)), "标记尺寸 = 交接尺寸 8vmin",
		m.size, Vector2(side, side))
	_ok(_near(float(m.get("sweep_deg")), float(T.HANDOFF["arc_progress"]) * T.MARK_ARC_SWEEP_DEG),
		"环仍是写完状态", m.get("sweep_deg"), 294.0)
	_ok(_near(float(m.get("dot_scale")), float(T.HANDOFF["dot_progress"])),
		"点仍就位", m.get("dot_scale"), 1.0)

	var void_rect: ColorRect = _splash.get("_void")
	_ok(void_rect.color.is_equal_approx(T.HANDOFF["bg"]), "底色 = HANDOFF.bg",
		void_rect.color, T.HANDOFF["bg"])

	var all_gone := _near(float(_splash.get("_grad").modulate.a), 0.0) \
		and _near(float(_splash.get("_world").modulate.a), 0.0)
	for key in ["_cn", "_rule", "_sub"]:
		all_gone = all_gone and _near(float(_splash.get(key).modulate.a), 0.0)
	_ok(all_gone, "环境与品牌全部退下", all_gone, true)

	var letters: Array = _splash.get("_letters")
	var all_hidden := true
	for b in letters:
		if not _near(b.label.position.x, -b.size.x, 0.5):
			all_hidden = false
	_ok(all_hidden, "字标全部收回", all_hidden, true)


# ---------------------------------------------------------------------------
func _process(delta: float) -> bool:
	_t += delta

	if not _setup:
		_setup = true
		_vp = root.get_visible_rect().size
		print("=".repeat(72))
		print("UI-01 BOOT AUDIT   viewport=%s   参考基准 900px 高" % _vp)
		print("=".repeat(72))
		_splash.play_boot()

	while _cp < _cps.size() and _t >= float(_cps[_cp][0]):
		(_cps[_cp][2] as Callable).call()
		_cp += 1

	if _cp >= _cps.size() and _exit_start < 0.0:
		# 退场单独计时：它自己的时长由 exit_total_sec() 给出，
		# 不在上面的检查点表里（那张表是进场）。
		_exit_start = _t
		_exit_seconds = _splash.exit_total_sec()
		print("[t=%.2fs] 开始退场（play_exit），预计 %.2fs 后落到交接帧" % [_t, _exit_seconds])
		_splash.play_exit()

	if _exit_start >= 0.0 and _t >= _exit_start + _exit_seconds + 0.15:
		_check_exit_lands_on_handoff()
		print("-".repeat(72))
		# 检查点一个都没跑到 = 上面某处静默失败了，绝不能当通过。
		if _cp == 0 and _checks == 0:
			print("UI BOOT AUDIT 失败：没有任何检查点被执行。")
			quit(1)
			return true
		if _fails.is_empty():
			print("UI BOOT AUDIT 通过：%d 项断言全部成立。" % _checks)
			return true
		print("UI BOOT AUDIT 失败：%d/%d 项不成立 —— %s" % [_fails.size(), _checks, ", ".join(_fails)])
		quit(1)
		return true
	return false
