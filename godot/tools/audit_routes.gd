extends SceneTree
## LD-01 route audit — evaluated against the CONTINUOUS height field.
##
## WHY NOT THE CSV: the dumped grid is 4 m. Sampling a route on a 4 m lattice
## snaps the centreline up to ~2.8 m off true, and near a carved corridor edge
## that offset alone produces 70-80 deg readings that do not exist on the
## walking surface. Gradient has to be measured where the walker actually is.
##
## Run:
##   Godot --headless --path godot --script res://tools/audit_routes.gd


const SAMPLES_PER_SEGMENT := 240
## Calibrated against the ENGINE, not against taste. CharacterBody3D's default
## floor_max_angle is 45 deg — above that move_and_slide() treats the surface as
## a wall and the walk simply fails. 35 deg is a comfort line: fine for an
## authored stair, unacceptable as a surprise on a road.
const BLOCKED_DEG := 45.0
const STEEP_DEG := 35.0
const COMFORT_DEG := 25.0
const MONOTONY_LIMIT_M := 80.0

## Stair band = the ground is too steep for a road but still walkable. That
## ground must become an AUTHORED stair, so the kit needs to know exactly where
## those runs are and what step geometry matches them. A run shorter than this
## is a bump on a road, not a stair, and stays terrain.
const MIN_STAIR_RUN_M := 2.0
## Candidate risers for the geometry recommendation. The binding constraint is
## the TREAD: below about 0.28 m a descending player clips the next step edge,
## which reads as a stumble. Tread = riser / tan(slope), so a steep band forces a
## taller riser — that coupling is the whole reason this table exists.
const STAIR_RISERS := [0.18, 0.20, 0.22, 0.24, 0.26, 0.28, 0.30]
const TREAD_MIN_M := 0.28
## KIT-02a's module: seven steps per 2.00 m grid cell, so tread = 2.00/7.
## Locking the tread (rather than the riser) is what makes a stair stackable on
## the same 2 m grid as every other kit piece while still being steep enough for
## a 35-40 deg band. The riser then carries the slope, and the four riser
## variants 0.16 / 0.20 / 0.22 / 0.24 produce 29.3 / 35.0 / 37.6 / 40.0 deg.
const STAIR_TREAD_M := 2.0 / 7.0
const KIT_RISERS := [0.16, 0.20, 0.22, 0.24]

const SPINE := [
	["出生 Prologue", 200.0, 320.0],
	["V1 林隙", 155.0, 258.0],
	["损坏路标", 140.0, 235.0],
	["NAR-01 翻倒商队", 120.0, 205.0],
	["拖行痕迹末端", 85.0, 180.0],
	["河湾渔点 NEW", 45.0, 148.0],
	["桥 Bridge", 10.0, 122.0],
	["河岸阶梯 NEW", -30.0, 95.0],
	["下城西", -60.0, 75.0],
	["工坊巷道 NEW", -45.0, 45.0],
	["V4 市场", 0.0, 0.0],
	["公会高台", 0.0, -45.0],
	["上城", -20.0, -85.0],
	["V6 钟塔", -40.0, -95.0],
	["北门", 0.0, -135.0],
	["神龛回头弯 NEW", 30.0, -170.0],
	["崖路转折", 60.0, -200.0],
	["V8 崖台", 85.0, -265.0],
	["S-03 断梁 NEW", 70.0, -295.0],
	["崖路下行", 50.0, -330.0],
	["V9 遗迹前场", -10.0, -355.0],
]


func _initialize() -> void:
	print("=".repeat(74))
	print("LD-01 ROUTE AUDIT — continuous field, %.1f m sampling" % (1.0 / 2.0))
	print("=".repeat(74))

	_report("主脊 Prologue -> North Gate", _as_poly(SPINE, 0, 14))
	_report("主脊 North Gate -> Ruins", _as_poly(SPINE, 14, SPINE.size()))
	_report("Forest Trail 西线", MistvaleHeights.FOREST_TRAIL)
	_report("Cliff Route 东线", MistvaleHeights.CLIFF_ROUTE)

	print("")
	print("--- 楼梯带 Stair bands (%.0f-%.0f deg) — KIT-02a 的输入 -------" % [STEEP_DEG, BLOCKED_DEG])
	var stair_sites := 0
	var stair_rise := 0.0
	var stair_steps := 0
	for r in [
		["主脊 Prologue -> North Gate", _as_poly(SPINE, 0, 14)],
		["主脊 North Gate -> Ruins", _as_poly(SPINE, 14, SPINE.size())],
		["Forest Trail 西线", MistvaleHeights.FOREST_TRAIL],
		["Cliff Route 东线", MistvaleHeights.CLIFF_ROUTE],
	]:
		var s: Array = _stair_report(r[0], r[1])
		stair_sites += int(s[0])
		stair_rise += float(s[1])
		stair_steps += int(s[2])
	print(
		"  合计 total: %d 段楼梯 | 累计爬升 %.1f m | 模数级数 %d（东线与主脊在 (44,-333) 汇合，重复计一次）"
		% [stair_sites, stair_rise, stair_steps]
	)

	print("")
	print("--- 渡河点 River crossings ----------------------------------------")
	_crossing("桥 Bridge", 10.0, 122.0)
	_crossing("渡口 Lia Ferry", -95.0, 138.0)
	_crossing("东浅滩 East Ford", 120.0, 150.0)

	print("")
	print("--- 战斗空间 Combat space flatness --------------------------------")
	for e in [
		["C01 商队伏击", 120.0, 205.0, 16.0],
		["C02 河滩", 30.0, 175.0, 15.0],
		["C03 市场", 0.0, 0.0, 22.0],
		["C04 锻造院", -85.0, 60.0, 14.0],
		["C05 公会阶梯", 0.0, -30.0, 12.0],
		["C06 崖台", 85.0, -262.0, 13.0],
		["C07 林间空地", -62.0, -232.0, 20.0],
		["C08 遗迹前场", -10.0, -355.0, 32.0],
	]:
		_arena(e[0], e[1], e[2], e[3])

	print("")
	print("--- 行走密度 Monotony (limit %.0f m) ---------------------------" % MONOTONY_LIMIT_M)
	var over := 0
	for i in SPINE.size() - 1:
		var a: Array = SPINE[i]
		var b: Array = SPINE[i + 1]
		var d := Vector2(b[1] - a[1], b[2] - a[2]).length()
		var flag := "  <-- OVER" if d > MONOTONY_LIMIT_M else ""
		if d > MONOTONY_LIMIT_M:
			over += 1
		print("  %5.1f m  %s -> %s%s" % [d, a[0], b[0], flag])
	print("  超限段数 segments over limit: %d" % over)

	print("")
	print("--- 实测高程 Measured ground (THE AUTHORITY over authored values) --")
	_heights()

	print("")
	print("--- 地形总量 Terrain totals ---------------------------------------")
	var lo := 1e9
	var hi := -1e9
	var blocked := 0
	var total := 0
	var x := MistvaleHeights.MIN_X
	while x <= MistvaleHeights.MAX_X:
		var z := MistvaleHeights.MIN_Z
		while z <= MistvaleHeights.MAX_Z:
			var y := MistvaleHeights.height_at(x, z)
			lo = minf(lo, y)
			hi = maxf(hi, y)
			var s := _slope(x, z)
			if s > BLOCKED_DEG:
				blocked += 1
			total += 1
			z += 8.0
		x += 8.0
	print("  高程 elevation %.1f -> %.1f m  (高差 %.1f m)" % [lo, hi, hi - lo])
	print(
		"  不可通行 >%.0f deg: %.2f%% of region"
		% [BLOCKED_DEG, 100.0 * float(blocked) / float(total)]
	)
	print("=".repeat(74))
	quit(0)


## Masterplan elevations were authored against the base profile alone. The
## massif lowers its flanks, so several of them are wrong by 10-20 m. These are
## the numbers the document should carry.
func _heights() -> void:
	var pts := [
		["出生 Prologue", 200.0, 320.0],
		["V1 林隙", 155.0, 258.0],
		["NAR-01 翻倒商队", 120.0, 205.0],
		["河 River (中心)", 0.0, 122.0],
		["桥 Bridge", 10.0, 122.0],
		["东浅滩 East Ford", 120.0, 150.0],
		["渡口 Lia Ferry", -95.0, 138.0],
		["下城区 Low Town", 0.0, 70.0],
		["工坊 Forge", -85.0, 60.0],
		["Oren 后院", 95.0, 30.0],
		["V4 市场 Market", 0.0, 0.0],
		["公会高台 Guild", 0.0, -45.0],
		["V5 公会台地", 0.0, -40.0],
		["上城区 Upper Town", -20.0, -85.0],
		["A 钟塔基座 BellTower", -40.0, -95.0],
		["F 神殿候选 Temple", 55.0, -100.0],
		["C 北门 North Gate", 0.0, -135.0],
		["崖路转折", 60.0, -200.0],
		["V7 首个回头弯", -55.0, -250.0],
		["V8 崖台", 85.0, -262.0],
		["E 遗迹 Beacon", 0.0, -360.0],
		["V9 遗迹前场", -10.0, -355.0],
		["D 山脊斩痕 Scar", -30.0, -410.0],
	]
	print("  %-22s %8s" % ["点 point", "地面 (m)"])
	for p in pts:
		print("  %-22s %8.1f" % [p[0], MistvaleHeights.height_at(p[1], p[2])])


func _as_poly(list: Array, from_i: int, to_i: int) -> Array:
	var out := []
	for i in range(from_i, to_i):
		out.append(Vector2(list[i][1], list[i][2]))
	return out


## Gradient magnitude in degrees at a point, from central differences.
func _slope(x: float, z: float, h: float = 1.0) -> float:
	var dx := (MistvaleHeights.height_at(x + h, z) - MistvaleHeights.height_at(x - h, z)) / (2.0 * h)
	var dz := (MistvaleHeights.height_at(x, z + h) - MistvaleHeights.height_at(x, z - h)) / (2.0 * h)
	return rad_to_deg(atan(sqrt(dx * dx + dz * dz)))


func _report(label: String, pts: Array) -> void:
	var grades: Array[float] = []
	var where: Array[Vector2] = []
	var dist := 0.0
	var climb := 0.0
	var prev := Vector2(pts[0].x, pts[0].y)
	var prev_y := MistvaleHeights.height_at(prev.x, prev.y)
	for i in pts.size() - 1:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		for k in range(1, SAMPLES_PER_SEGMENT + 1):
			var t := float(k) / float(SAMPLES_PER_SEGMENT)
			var p := a.lerp(b, t)
			var y := MistvaleHeights.height_at(p.x, p.y)
			var d := p.distance_to(prev)
			if d > 0.0001:
				grades.append(rad_to_deg(atan(absf(y - prev_y) / d)))
				where.append(p)
				dist += d
				var dy := y - prev_y
				if dy > 0.0:
					climb += dy
			prev = p
			prev_y = y
	var blocked := 0
	var steep := 0
	var mean := 0.0
	for g in grades:
		mean += g
		if g > BLOCKED_DEG:
			blocked += 1
		elif g > STEEP_DEG:
			steep += 1
	mean /= maxf(float(grades.size()), 1.0)
	var n := maxf(float(grades.size()), 1.0)
	var blocked_pct := 100.0 * float(blocked) / n
	var steep_pct := 100.0 * float(steep) / n
	var verdict := "PASS" if blocked == 0 else ("MARGINAL" if blocked_pct < 1.0 else "FAIL")
	print("")
	print("[%s] %s" % [verdict, label])
	print(
		"   长度 %.0f m | 累计爬升 %.0f m | 平均坡度 %.1f deg" % [dist, climb, mean]
	)
	print(
		"   舒适 <%.0f: %.1f%% | 陡坡/楼梯 %.0f-%.0f: %.1f%% | 不可通行 >%.0f: %.1f%%"
		% [
			COMFORT_DEG, 100.0 - steep_pct - blocked_pct,
			STEEP_DEG, BLOCKED_DEG, steep_pct,
			BLOCKED_DEG, blocked_pct,
		]
	)
	if blocked > 0 or steep > 0:
		# Naming the offender matters: "3.3% too steep" is not actionable,
		# "too steep at (68, -196) next to C06" is.
		var idx := _worst_indices(grades, 3)
		for i in idx:
			print("      %.1f deg @ (%.0f, %.0f)" % [grades[i], where[i].x, where[i].y])


func _worst_indices(grades: Array[float], count: int) -> Array:
	var order := []
	for i in grades.size():
		if grades[i] > STEEP_DEG:
			order.append(i)
	order.sort_custom(func(a, b): return grades[a] > grades[b])
	if order.size() > count:
		order.resize(count)
	return order


## Walks a route and reports every contiguous run of stair-band ground, then
## derives the step geometry that actually fits it. This is the production input
## for KIT-02a: a stair piece is only correct at the slope it was cut for, so the
## kit cannot be specified without these numbers.
func _stair_report(label: String, pts: Array) -> Array:
	var pos: Array[Vector2] = []
	var grade: Array[float] = []
	var height: Array[float] = []
	var ds: Array[float] = []
	var prev := Vector2(pts[0].x, pts[0].y)
	var prev_y := MistvaleHeights.height_at(prev.x, prev.y)
	for i in pts.size() - 1:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		for k in range(1, SAMPLES_PER_SEGMENT + 1):
			var t := float(k) / float(SAMPLES_PER_SEGMENT)
			var p := a.lerp(b, t)
			var y := MistvaleHeights.height_at(p.x, p.y)
			var d := p.distance_to(prev)
			if d > 0.0001:
				pos.append(p)
				grade.append(rad_to_deg(atan(absf(y - prev_y) / d)))
				height.append(y)
				ds.append(d)
			prev = p
			prev_y = y

	var found := 0
	var blips := 0
	var rise_sum := 0.0
	var step_sum := 0
	var i := 0
	while i < grade.size():
		if grade[i] > STEEP_DEG and grade[i] <= BLOCKED_DEG:
			var j := i
			while (
				j + 1 < grade.size()
				and grade[j + 1] > STEEP_DEG
				and grade[j + 1] <= BLOCKED_DEG
			):
				j += 1
			var run_len := 0.0
			for k in range(i, j + 1):
				run_len += ds[k]
			if run_len >= MIN_STAIR_RUN_M:
				found += 1
				var e: Array = _emit_stair(found, pos, grade, height, i, j, run_len)
				rise_sum += float(e[0])
				step_sum += int(e[1])
			else:
				blips += 1
			i = j + 1
		else:
			i += 1
	print(
		"  %-26s 楼梯段 %d | 短凸起 <%.0f m 仍属地貌 %d | 累计爬升 %.1f m"
		% [label, found, MIN_STAIR_RUN_M, blips, rise_sum]
	)
	return [found, rise_sum, step_sum]


func _emit_stair(
	n: int,
	pos: Array[Vector2],
	grade: Array[float],
	height: Array[float],
	i: int,
	j: int,
	run_len: float
) -> Array:
	var rise := height[j] - height[i]
	# pos[] is XZ only, so run_len IS the horizontal run. Do not "correct" it with
	# sqrt(L^2 - rise^2): that treats it as a 3D hypotenuse and inflates the
	# reported slope by 15-20%, which is the difference between "a real stair"
	# and "impassable".
	var horiz := run_len
	var eff := rad_to_deg(atan(absf(rise) / maxf(horiz, 0.001)))
	var peak := 0.0
	var total_dh := 0.0
	for k in range(i, j + 1):
		peak = maxf(peak, grade[k])
		if k > i:
			total_dh += absf(height[k] - height[k - 1])
	var monotone := "单调" if absf(total_dh - absf(rise)) < 0.35 else "有起伏"
	print(
		"    [%d] (%.0f,%.0f) -> (%.0f,%.0f) | 水平 %.1f m | 净爬升 %+.1f m | 有效坡度 %.1f deg (最陡样本 %.1f, %s)"
		% [n, pos[i].x, pos[i].y, pos[j].x, pos[j].y, horiz, rise, eff, peak, monotone]
	)
	var fit: Array = _stair_geometry(absf(rise), horiz, eff)
	return [absf(rise), int(fit[0])]


## The smallest riser that still keeps the tread at or above TREAD_MIN_M. Tread
## and riser are locked together by the slope, so "use a low riser" is not an
## option on a steep band — it buys comfort at the cost of a stumbling tread.
func _recommended_riser(eff: float) -> float:
	var t_slope := tan(deg_to_rad(eff))
	for r in STAIR_RISERS:
		if float(r) / maxf(t_slope, 0.001) >= TREAD_MIN_M:
			return r
	return float(STAIR_RISERS[STAIR_RISERS.size() - 1])


func _recommended_steps(rise: float, eff: float) -> int:
	return int(ceil(rise / _recommended_riser(eff)))


func _stair_geometry(rise: float, horiz: float, eff: float) -> Array:
	var t_slope := tan(deg_to_rad(eff))
	var rec_riser := _recommended_riser(eff)
	for r in STAIR_RISERS:
		var tread: float = r / maxf(t_slope, 0.001)
		var steps := int(ceil(rise / r))
		var total := float(steps) * tread
		var note := ""
		if tread < TREAD_MIN_M:
			note = "踏面过窄，下坡会绊"
		elif total > horiz * 1.08:
			note = "超出可用进深"
		elif absf(float(r) - rec_riser) < 0.001:
			note = "<== 推荐"
		print(
			"        riser %.2f / tread %.3f | %2d 步 | 总进深 %.2f m  %s"
			% [r, tread, steps, total, note]
		)
	return _module_fit(rise, horiz)


## Which KIT-02a module actually lands on top of this band.
##
## Rise error and run error are scored JOINTLY, weighted 2:1 toward the run.
## Judging by rise alone is degenerate: riser 0.16 matches a 13.6 m climb with 12
## modules and a 0.14 m residual, but that is 24 m of run for a 16 m band — a 29
## deg ramp where the band is 40 deg. Slope error alone is equally wrong: it picks
## a shallower riser that lands 0.6 m below the trail. What matters is arriving at
## the right height within the metres you actually have.
func _module_fit(rise: float, run_len: float) -> Array:
	var best_r := 0.0
	var best_n := 1
	var best_score := 1e9
	for r in KIT_RISERS:
		var rv: float = r
		var n := maxi(int(round(rise / (7.0 * rv))), 1)
		var rise_err := absf(7.0 * rv * float(n) - rise)
		var run_err := absf(2.0 * float(n) - run_len)
		var score := rise_err + 2.0 * run_err
		if score < best_score:
			best_score = score
			best_r = rv
			best_n = n
	var m_rise := 7.0 * best_r
	print(
		"        riser %.2f x %d 段 = %d 级 | 进深 %.2f m | 爬升 %.2f m | 坡度 %.2f deg | 残差 爬升 %+.2f m / 进深 %+.2f m"
		% [
			best_r, best_n, 7 * best_n, 2.0 * float(best_n), m_rise * float(best_n),
			rad_to_deg(atan(m_rise / 2.0)),
			m_rise * float(best_n) - rise, 2.0 * float(best_n) - run_len,
		]
	)
	return [7 * best_n]


## Perpendicular cross-section: is the corridor a path, or a trench?
func _crossing(label: String, x: float, z: float) -> void:
	var y := MistvaleHeights.height_at(x, z)
	var s := _slope(x, z)
	print("  %-18s 地面 %.1f m | 坡度 %.1f deg" % [label, y, s])


func _arena(label: String, x: float, z: float, radius: float) -> void:
	var lo := 1e9
	var hi := -1e9
	var worst := 0.0
	var samples := 0
	for r in range(int(radius)):
		var rr := float(r)
		for i in 16:
			var a := TAU * float(i) / 16.0
			var px := x + cos(a) * rr
			var pz := z + sin(a) * rr
			var y := MistvaleHeights.height_at(px, pz)
			lo = minf(lo, y)
			hi = maxf(hi, y)
			worst = maxf(worst, _slope(px, pz))
			samples += 1
	# Judged on SLOPE, not on total height spread. An arena tilted to follow its
	# hillside is 6-7 m across and perfectly fightable; the old 4 m spread test
	# called that UNEVEN while calling a 4 m dish on a cliff fine.
	var verdict := "OK" if worst <= 10.0 else ("MARGINAL" if worst <= 15.0 else "UNEVEN")
	print(
		"  %-14s 高差 %.2f m | 最陡 %.1f deg | %s"
		% [label, hi - lo, worst, verdict]
	)
