extends SceneTree
## Prints the resolved S-B / Guild composition table.
##
## The blockout and this report call the SAME MistvaleAscent.layout(), so the
## numbers printed here are the numbers in the scene. Any hand-written "rise" in
## a design document is a number that will drift; this one cannot.
##
## Run:
##   Godot --headless --path godot --script res://tools/dump_ascent_layout.gd
##
## PRELOAD, NOT THE GLOBAL CLASS NAME. Loading this tool with --script happens
## before the editor has refreshed global_script_class_cache.cfg, so a brand new
## class_name is not yet resolvable. Preloading the path sidesteps the cache
## entirely — and it also means this tool cannot rewrite the shared cache while
## a parallel session is importing.
const Ascent := preload("res://scripts/world/mistvale_ascent.gd")


func _initialize() -> void:
	_report("S-B HERO ASCENT  崖路东线 D=%.0f -> 296.9 m" % Ascent.CLIFF_START,
		Ascent.cliff_layout())
	_report("GUILD TERRACE  CIVIC 公共台阶", Ascent.guild_layout())
	quit(0)


func _report(title: String, rows: Array) -> void:
	print("")
	print("================================================================================")
	print(title)
	print("================================================================================")
	print("  #  种类      起点D  长度  地面0->1        构造Y  爬升 模块 级数 踢面   踏面   坡度    期望   偏差  构造偏离  说明")
	var steps := 0
	var flights := 0
	var worst_pitch := 0.0
	var worst_cut := 0.0
	var worst_dev := 0.0
	var worst_drift := 0.0
	var tread_bad := 0
	for i in rows.size():
		var r: Dictionary = rows[i]
		steps += int(r["steps"])
		var extra := ""
		var want := "--"
		var drift := "--"
		if r["steps"] > 0:
			flights += 1
			worst_pitch = maxf(worst_pitch, float(r["pitch"]))
			extra = "%.0f 级  %.3f %.4f  %5.1f deg" % [
				r["steps"], r["riser"], r["tread"], r["pitch"],
			]
			if float(r["want"]) > 0.0:
				want = "%.2f" % r["want"]
				drift = "%+.3f" % r["drift"]
				worst_drift = maxf(worst_drift, absf(float(r["drift"])))
			if absf(float(r["tread"]) - 0.285714) > 0.001:
				tread_bad += 1
		worst_cut = maxf(worst_cut, float(r["cut"]))
		worst_dev = maxf(worst_dev, float(r["dev"]))
		print("  %2d %-8s %6.0f %5.1f  %6.2f -> %6.2f  %7.2f %+5.2f %2d  %s  %s  %s  偏离%.2f  %s" % [
			i + 1, r["kind"], r["d0"], r["run"], r["g0"], r["g1"], r["sh1"],
			r["sh1"] - r["sh0"], r["modules"], extra, want, drift,
			r["dev"], r["label"],
		])
	print("  => %d 段 ｜ 台阶 %d 级 ｜ %d 段梯 ｜ 最陡 %.1f deg ｜ 最大挖方 %.2f m" % [
		rows.size(), steps, flights, worst_pitch, worst_cut,
	])
	print("  => 判据 brief §4：连续单段 >=40 级 = FAIL。最长单段 %d 级。" % _longest(rows))
	print("  => 模数：踏面非 0.2857 的梯段 %d 个（应为 0）｜ 踢面与设计意图最大偏差 %.3f m" % [
		tread_bad, worst_drift,
	])
	print("  => 土方：构造线偏离地面最大 %.2f m（>2.5 m 需要挡土墙/开挖，需人工复核）" % worst_dev)


func _longest(rows: Array) -> int:
	var m := 0
	for r in rows:
		m = maxi(m, int(r["steps"]))
	return m
