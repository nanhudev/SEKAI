extends SceneTree
## UI-01 LAYOUT AUDIT —— 12 栅结构是否与网页原型逐项相等（headless）。
##
## 这是"Godot 主菜单必须与网页原型对齐"（BRIEF §M）的**可执行版本**。
## 对齐不能靠"看起来差不多"：版式只要差 20px，两个页面就明显不是同一个界面，
## 而这种差没人会主动去查 —— 因为它不像 bug。
##
## 基准值是网页原型在 1600×900、冻结在 t=4200ms（终态）下的 probe 实测：
##   .sk-menu__brand  x=267  y=110  w=933  h=253
##   #nav             x=267  y=472  w=400  h=385
##   .sk-item         y=496.6 h=68   项间距 8
##   .sk-meta-bar     y=856.6 h=43.4
##   .sk-menu__word   h=53.73   .sk-menu__cn h=38.93   .sk-menu__sub h=19.39
##   .sk-menu__mark   w=40
##
## 运行：
##   Godot --headless --path godot --script res://tools/audit_ui_layout.gd
## 退出码 0 = 全部通过。
##
## 重新量网页的方法（改版式之后要重跑，并更新 ui_layout.gd 里的 REF_* 常量）：
##   node ui_web/tools/render.mjs probe --page main_menu --at 4200 \
##        --selectors ".sk-menu__brand,#mark,#word,#wordCN,#rule,#subtitle,#nav,.sk-meta-bar,.sk-item"

const T := preload("res://scripts/ui/ui_tokens.gd")
const L := preload("res://scripts/ui/ui_layout.gd")

## 位置类允差 0.5px（网页 probe 是四舍五入到 0.1 的），行盒类允差 0.2px。
const POS_EPS := 0.5
const LINE_EPS := 0.2

var _checks := 0
var _fails: Array[String] = []


func _eq(label: String, got: float, want: float, eps: float) -> void:
	_checks += 1
	var d := absf(got - want)
	if d <= eps:
		print("  PASS  %-32s 计算=%-9.2f 网页=%-9.2f Δ=%.2f" % [label, got, want, d])
	else:
		print("  FAIL  %-32s 计算=%-9.2f 网页=%-9.2f Δ=%.2f  > %.2f" % [label, got, want, d, eps])
		_fails.append(label)


func _inv(label: String, cond: bool, detail: String) -> void:
	_checks += 1
	if cond:
		print("  PASS  %-32s %s" % [label, detail])
	else:
		print("  FAIL  %-32s %s" % [label, detail])
		_fails.append(label)


func _initialize() -> void:
	var vp := L.REF_VP
	print("=".repeat(78))
	print("UI-01 LAYOUT AUDIT   vp=%s   （基准 = 网页 probe 实测值）" % vp)
	print("=".repeat(78))

	print("\n[横向] 12 栅")
	# grid-column: 3 / span 7  →  .sk-menu__brand
	_eq("col_x(3) 品牌左缘", L.col_x(vp, 3), 267.0, POS_EPS)
	_eq("col_w(7) 品牌跨度", L.col_w(vp, 7), 933.0, POS_EPS)
	# grid-column: 3 / span 3  →  #nav、.sk-item
	_eq("col_x(3) 导航左缘", L.col_x(vp, 3), 267.0, POS_EPS)
	_eq("col_w(3) 导航跨度", L.col_w(vp, 3), 400.0, POS_EPS)

	print("\n[纵向] 三行 1fr / auto / auto")
	_eq("footer_h 页脚高", L.footer_h(vp), 43.4, POS_EPS)
	_eq("nav_h 导航高", L.nav_h(vp), 385.0, POS_EPS)
	_eq("nav_top 导航顶边", L.nav_top(vp), 472.0, POS_EPS)
	_eq("footer_top 页脚顶边", L.footer_top(vp), 856.6, POS_EPS)
	_eq("item_h 菜单项高", L.item_h(vp), 68.0, POS_EPS)
	_eq("item_top(0) 首项顶边", L.item_top(vp, 0), 496.6, POS_EPS)
	_eq("item_top(3) 末项顶边", L.item_top(vp, 3), 724.6, POS_EPS)

	print("\n[品牌块]")
	_eq("mark_side 标记边长", L.mark_side(vp), 40.0, POS_EPS)
	_eq("word_lh 字标行高", L.word_lh(vp), 53.73, LINE_EPS)
	_eq("cn_lh 中文名行高", L.cn_lh(vp), 38.93, LINE_EPS)
	_eq("sub_lh 副标题行高", L.sub_lh(vp), 19.39, LINE_EPS)
	_eq("brand_box_h 品牌盒高", L.brand_box_h(vp), 253.0, 1.0)
	_eq("brand_top 品牌盒顶边", L.brand_top(vp), 110.0, 1.0)

	print("\n[结构不变式] —— 这些是版式是否正确 的判据，不是具体数值")
	var slots := L.brand_slots(vp)
	_inv("导航底边 == 页脚顶边",
		absf((L.nav_top(vp) + L.nav_h(vp)) - L.footer_top(vp)) < 0.001,
		"%.2f == %.2f" % [L.nav_top(vp) + L.nav_h(vp), L.footer_top(vp)])
	# 品牌块必须在第 1 行里**垂直居中**：盒中心 == 行中心。
	_inv("品牌盒在第 1 行居中",
		absf((L.brand_top(vp) + L.brand_box_h(vp) * 0.5) - L.nav_top(vp) * 0.5) < 0.001,
		"盒中心=%.2f 行中心=%.2f" % [L.brand_top(vp) + L.brand_box_h(vp) * 0.5, L.nav_top(vp) * 0.5])
	_inv("品牌槽位自上而下递增",
		slots["mark"] < slots["word"] and slots["word"] < slots["cn"]
			and slots["cn"] < slots["rule"] and slots["rule"] < slots["sub"],
		"mark=%.1f word=%.1f cn=%.1f rule=%.1f sub=%.1f" % [
			slots["mark"], slots["word"], slots["cn"], slots["rule"], slots["sub"]])
	_inv("品牌内容底 == 槽位累加",
		absf((slots["bottom"] - slots["mark"]) - L.brand_content_h(vp)) < 0.001,
		"%.2f == %.2f" % [slots["bottom"] - slots["mark"], L.brand_content_h(vp)])
	# 菜单项之间不能重叠：项高 + 间距 == 下一项顶边 - 本项顶边
	_inv("菜单项不重叠",
		absf((L.item_top(vp, 1) - L.item_top(vp, 0)) - (L.item_h(vp) + float(T.SPACE["s2"]))) < 0.001,
		"步进=%.2f" % (L.item_top(vp, 1) - L.item_top(vp, 0)))
	# 菜单项数必须来自 token 表 —— 否则 BootSplash 与 MainMenu 会各算各的。
	_inv("菜单项数取自 token 表",
		L.nav_h(vp, T.MENU_ITEMS.size()) == L.nav_h(vp),
		"count=%d" % T.MENU_ITEMS.size())

	print("\n[其它分辨率] 结构不变式必须仍然成立（数值当然会变）")
	for size in [Vector2(1280, 720), Vector2(1920, 1080), Vector2(2560, 1440)]:
		var ok := (
			absf((L.nav_top(size) + L.nav_h(size)) - L.footer_top(size)) < 0.001
			and L.item_h(size) > 0.0
			and L.brand_top(size) >= 0.0
			and L.nav_top(size) > L.brand_top(size) + L.brand_box_h(size)
		)
		_inv("%s 结构自洽" % size, ok,
			"品牌底=%.1f 导航顶=%.1f 页脚顶=%.1f" % [
				L.brand_top(size) + L.brand_box_h(size), L.nav_top(size), L.footer_top(size)])

	print("-".repeat(78))
	if _fails.is_empty():
		print("UI LAYOUT AUDIT 通过：%d 项断言全部成立。" % _checks)
		quit(0)
		return
	print("UI LAYOUT AUDIT 失败：%d/%d —— %s" % [_fails.size(), _checks, ", ".join(_fails)])
	quit(1)
