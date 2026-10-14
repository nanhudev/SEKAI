extends SceneTree
## S-B HERO ASCENT composition audit.
##
## WHY THIS TOOL EXISTS: the masterplan's S-B rule is an EXPERIENCE rule, not a
## geometry rule — "the town must feel like it is shrinking behind you, the
## ruins must feel like they are getting closer, you must feel you are leaving
## safety". Experience rules are the ones that usually get waved through. This
## tool turns the two checkable parts of it into numbers:
##
##   1. COMPOSITION — where are the flights, the landings, the flat walks?
##      A 56 step continuous run fails by construction; this prints the real
##      breakdown so the blockout can be authored against measured ground
##      instead of a guessed elevation. (Same lesson as the 68 deg Cliff Route
##      wall: never author elevations by hand.)
##
##   2. LOOK BACK — from every point on the climb, is Mistvale / the bell tower
##      / the river / the path you already walked actually visible? Brief §6
##      says the look-back must be a designed moment. This reports the blocked
##      metres per target per station so a failure names its own cause.
##
## Run:
##   Godot --headless --path godot --script res://tools/audit_ascent.gd

const SAMPLE := 1.0               # metres between field samples
const REPORT_M := 10.0            # metres between printed stations
const EYE := 1.6                  # player eye height
const RAY_STEP := 1.0
## Terrain this far below the ray still counts as clear: eye height + the fact
## that a 0.2 m lip does not actually occlude at 300 m.
const CLEARANCE := 0.25

const OUT_DIR := "F:/SEKAI/assets_source/review/"

## Platform rises tried by _deck_search, in metres.
const DECK_RISES := [0.0, 1.0, 2.0, 3.0, 5.0]

## Flights, walks and landings are classified from a 20 m grade (below) so a
## single erosion blip cannot invent a staircase. 30 deg is the brief's own
## threshold between "you walk this" and "this wants steps".
const FLIGHT_DEG := 30.0
const WALK_DEG := 12.0
const GRADE_WINDOW := 20.0

## Targets the look-back must resolve, per masterplan §6 and brief §6.
## Absolute Y where the target is a structure rather than ground.
const LOOK_TARGETS := [
	["Mistvale 市场", 0.0, 0.0, NAN],
	["钟塔 A 塔顶", -40.0, -95.0, 114.0],
	["河谷水面", 10.0, 122.0, 6.0],
	["公会台地 B", 0.0, -45.0, 64.0],
]
## Extra stations worth checking that are not on the ray to a look-back target.
const AHEAD_TARGETS := [
	["遗迹 Beacon E", 0.0, -360.0, 178.0],
	["斩痕 D", -30.0, -410.0, 196.0],
]


func _initialize() -> void:
	_header()
	_walk_profile(
		"CLIFF ROUTE 东线（S-B 所在）", MistvaleHeights.CLIFF_ROUTE, "ascent_profile.csv"
	)
	_walk_profile("GUILD APPROACH 市场 -> 公会", [
		Vector2(0.0, 0.0), Vector2(0.0, -45.0),
	], "guild_profile.csv")
	_composition("CLIFF ROUTE 东线", MistvaleHeights.CLIFF_ROUTE)
	_look_back()
	_deck_search()
	_spur_search()
	quit(0)


func _header() -> void:
	print("")
	print("================================================================================")
	print("S-B HERO ASCENT AUDIT  —— 剖面 / 构图分段 / 回头看视线")
	print("================================================================  eye +%.1f m" % EYE)


## Resample a polyline at SAMPLE metres and report the walking numbers.
func _walk_profile(label: String, pts: Array, csv_name: String) -> void:
	var s := _resample(pts)
	var total: float = s[-1].x
	print("")
	print("--- %s ---------------- 全长 %.1f m，爬升 %+.1f m，均坡 %.1f deg ---" % [
		label, total, s[-1].z - s[0].z,
		rad_to_deg(atan(absf(s[-1].z - s[0].z) / maxf(total, 0.001))),
	])
	print("  dist      x       z     ground Y   20m坡度   累计爬升")
	var next_report := 0.0
	for k in s.size():
		var d: float = s[k].x
		if d + 0.001 < next_report:
			continue
		next_report += REPORT_M
		var g := _grade20(s, k)
		print("  %6.1f  %6.1f  %6.1f   %8.2f   %6.1f    %+7.2f" % [
			d, s[k].y, s[k].w, s[k].z, g, s[k].z - s[0].z,
		])
	_dump_csv(s, csv_name)


## Store the walking chain as Vector4(dist, x, ground_y, z).
func _resample(pts: Array) -> Array:
	var out := []
	var d := 0.0
	for i in pts.size() - 1:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var seg := a.distance_to(b)
		var n := maxi(int(ceil(seg / SAMPLE)), 1)
		for k in n:
			var t := float(k) / float(n)
			var p := a.lerp(b, t)
			out.append(Vector4(d, p.x, MistvaleHeights.height_at(p.x, p.y), p.y))
			d += seg / float(n)
	var last: Vector2 = pts[-1]
	out.append(Vector4(d, last.x, MistvaleHeights.height_at(last.x, last.y), last.y))
	return out


func _grade20(s: Array, k: int) -> float:
	var win := int(GRADE_WINDOW / SAMPLE)
	var i := maxi(k - win / 2, 0)
	var j := mini(k + win / 2, s.size() - 1)
	if j <= i:
		return 0.0
	var a: Vector4 = s[i]
	var b: Vector4 = s[j]
	var run: float = b.x - a.x
	if run < 0.01:
		return 0.0
	return rad_to_deg(atan(absf(b.z - a.z) / run))


## The composition breakdown: contiguous FLIGHT / WALK / LANDING regions, with
## the flight geometry KIT-02a would have to build for each.
func _composition(label: String, pts: Array) -> void:
	var s := _resample(pts)
	var kinds := PackedStringArray()
	for k in s.size():
		var g := _grade20(s, k)
		if g >= FLIGHT_DEG:
			kinds.append("FLIGHT")
		elif g >= WALK_DEG:
			kinds.append("WALK")
		else:
			kinds.append("LANDING")
	print("")
	print("--- %s 构图分段 (20 m 窗口, 阈值 flight>=%.0f / walk>=%.0f) ----" % [
		label, FLIGHT_DEG, WALK_DEG,
	])
	print("   #  种类      起点距   长度   爬升   均坡   起点(x,z) -> 终点(x,z)")
	var n := 0
	var i := 0
	var flights := 0
	var steps_total := 0
	while i < s.size():
		var j := i
		while j + 1 < s.size() and kinds[j + 1] == kinds[i]:
			j += 1
		var run: float = s[j].x - s[i].x
		var rise: float = s[j].z - s[i].z
		if run >= 3.0:
			n += 1
			var slope := rad_to_deg(atan(absf(rise) / maxf(run, 0.001)))
			print("  %2d  %-7s  %6.1f  %5.1f  %+6.2f  %5.1f   (%.0f,%.0f) -> (%.0f,%.0f)" % [
				n, kinds[i], s[i].x, run, rise, slope,
				s[i].y, s[i].w, s[j].y, s[j].w,
			])
			if kinds[i] == "FLIGHT":
				flights += 1
				steps_total += int(ceil(absf(rise) / 0.24))
		i = j + 1
	print("  => %d 段（其中 FLIGHT %d 段）｜ 若全按 riser 0.24 计，共约 %d 级" % [
		n, flights, steps_total,
	])
	print("  => 判据：连续 FLIGHT 段若只有一段且 >= 40 级 = 一条 56 级大楼梯，FAIL（brief §4）")


## §6: from stations along the climb, can you actually see where you came from?
func _look_back() -> void:
	var s := _resample(MistvaleHeights.CLIFF_ROUTE)
	print("")
	print("--- 回头看 / 前瞻 视线 (eye %.1f m, 采样 %.1f m) --------------------------" % [
		EYE, REPORT_M,
	])
	var heads := "  距离  "
	for t in LOOK_TARGETS:
		heads += "| %-13s" % t[0]
	for t in AHEAD_TARGETS:
		heads += "| %-12s" % t[0]
	print(heads)
	var fails := 0
	var checked := 0
	var next := 0.0
	for k in s.size():
		var d: float = s[k].x
		if d + 0.001 < next:
			continue
		next += REPORT_M
		# The last station is standing inside the forecourt pad; looking "back"
		# from there is not a moment the design claims.
		var row := "%6.1f" % d
		for t in LOOK_TARGETS:
			row += "| " + _cast(s, k, t[1], t[2], t[3])
			checked += 1
		for t in AHEAD_TARGETS:
			row += "| " + _cast(s, k, t[1], t[2], t[3])
		print(row)
	print("  => 判据：沿路 70%% 以上的站点必须能看见市场 / 钟塔 / 河谷（brief §6）")


func _cast(s: Array, k: int, tx: float, tz: float, ty: float) -> String:
	var a: Vector4 = s[k]
	var b := _blockage(a.y, a.z + EYE, a.w, tx, ty, tz)
	if b.y < 0.0:
		return "  --  "
	if b.x > CLEARANCE:
		return " X %4.1f@%3.0f" % [b.x, b.y]
	return " ok %4.1f@%3.0f" % [maxf(b.x, 0.0), b.y]


## How many metres of terrain stand above the ray between two points.
## Returns Vector2(blockage_m, distance along the ray to the worst point).
## y < 0 means the two points were too close for the ray to mean anything.
##
## This is the ONLY place the occlusion rule lives. The vista sheet, the
## look-back table and the spur search must all agree on what "blocked" means,
## or the three will contradict each other in the same review.
func _blockage(
	ax: float, ay: float, az: float, tx: float, ty: float, tz: float
) -> Vector2:
	var by := ty
	if is_nan(by):
		by = MistvaleHeights.height_at(tx, tz)
	var dist := Vector2(tx - ax, tz - az).length()
	if dist < 2.0:
		return Vector2(0.0, -1.0)
	var worst := 0.0
	var worst_d := 0.0
	var steps := maxi(int(dist / RAY_STEP), 2)
	for m in range(1, steps):
		var t := float(m) / float(steps)
		var over := (
			MistvaleHeights.height_at(lerpf(ax, tx, t), lerpf(az, tz, t))
			- lerpf(ay, by, t)
		)
		if over > worst:
			worst = over
			worst_d = t * dist
	return Vector2(worst, worst_d)


## The point you were standing at `back` metres earlier on the same route.
func _back_point(s: Array, d: float, back: float) -> Vector3:
	var target := d - back
	if target < 0.0:
		return Vector3.ZERO
	for k in s.size():
		if s[k].x >= target:
			return Vector3(s[k].y, s[k].z, s[k].w)
	return Vector3.ZERO


## MINIMUM RAISED DECK NEEDED FOR THE VALLEY TO OPEN.
##
## The look-back audit shows the corridor is blocked from the town by only
## 0.6-1.8 m for its first 90 m, and the blocker sits just 11-60 m away — a
## local hump, not a mountain. Cutting 1.5 m off a hillside is earthworks and
## would need its own bank. Standing 2.5 m higher is a stone platform.
##
## This prints the rise at which each target reopens, so the deck height in the
## blockout is a measured number instead of a guess. Same family of decision as
## V1 (a shelf cut into the old road bank) — when the view is short by a metre or
## two, the answer is a structure, not a landform.
func _deck_search() -> void:
	var s := _resample(MistvaleHeights.CLIFF_ROUTE)
	print("")
	print("--- 抬升平台需求：观察点需抬高多少米，目标才重新可见 ----------------------")
	print("  距离 站点(x,z)        地面Y   rise   市场    钟塔    河谷    公会")
	var next := 0.0
	for k in s.size():
		var d: float = s[k].x
		if d + 0.001 < next:
			continue
		next += 20.0
		if d < 40.0 or d > 220.0:
			continue
		var g := MistvaleHeights.height_at(s[k].y, s[k].w)
		for ri in DECK_RISES.size():
			var rise: float = DECK_RISES[ri]
			var row := ""
			for t in LOOK_TARGETS:
				var b := _blockage(s[k].y, g + EYE + rise, s[k].w, t[1], t[3], t[2])
				if b.x <= CLEARANCE:
					row += "  ok    "
				else:
					row += " X%5.1f " % b.x
			print("  %5.0f (%5.0f,%6.0f) %7.2f  %+5.1f  %s" % [
				d, s[k].y, s[k].w, g, rise, row,
			])


## WHERE DOES THE LOOK-BACK ACTUALLY WORK?
##
## Brief §6 requires that mid-climb you can turn around and see Mistvale, the
## bell tower, the river and the path you already walked. The straight-line
## audit above shows the corridor itself fails that for the town and the river:
## the flank it hugs stands between the climber and the valley, 7-16 m of it.
##
## That is correct mountain geography, not a bug. A view like that is a SPUR —
## a place where the ground sticks out. So rather than cutting 16 m off a
## mountain, search for the spurs and build a platform on one. Same method that
## fixed V7/V9: move the viewpoint, do not re-sculpt the terrain. A spur needs a
## deck and a rail; a cut-down mountain needs a level designer and a week.
func _spur_search() -> void:
	var s := _resample(MistvaleHeights.CLIFF_ROUTE)
	print("")
	print("--- 回头看观景点搜索 (横向 ±40 m / 步长 2.5 m, 坡度<=22 deg) ----------------")
	print("  距离 站点(x,z)      offset 观景点(x,z)     地面Y  局部坡  市场   河谷   公会   来路")
	var hits := []
	var next := 0.0
	for k in s.size():
		var d: float = s[k].x
		if d + 0.001 < next:
			continue
		next += 10.0
		if d < 120.0:
			continue
		# Route tangent, then its perpendicular. +offset is to the LEFT of the
		# direction of travel.
		var i0 := maxi(k - 5, 0)
		var i1 := mini(k + 5, s.size() - 1)
		var tang := Vector2(s[i1].y - s[i0].y, s[i1].w - s[i0].w)
		if tang.length() < 0.01:
			continue
		tang = tang.normalized()
		var perp := Vector2(-tang.y, tang.x)

		var best_score := -1
		var best_row := ""
		var best_off := 0.0
		var best_pt := Vector2.ZERO
		var best_g := 0.0
		var best_slope := 0.0
		for oi in range(-16, 17):
			var off := float(oi) * 2.5
			var qx: float = s[k].y + perp.x * off
			var qz: float = s[k].w + perp.y * off
			var g := MistvaleHeights.height_at(qx, qz)
			var dx := (
				MistvaleHeights.height_at(qx + 2.0, qz)
				- MistvaleHeights.height_at(qx - 2.0, qz)
			) / 4.0
			var dz := (
				MistvaleHeights.height_at(qx, qz + 2.0)
				- MistvaleHeights.height_at(qx, qz - 2.0)
			) / 4.0
			var slope := rad_to_deg(atan(sqrt(dx * dx + dz * dz)))
			if slope > 22.0:
				continue
			var score := 0
			var row := ""
			for t in LOOK_TARGETS:
				var b := _blockage(qx, g + EYE, qz, t[1], t[3], t[2])
				if b.x <= CLEARANCE:
					score += 1
					row += "  ok   "
				else:
					row += " X%4.1f " % b.x
			var back := _back_point(s, d, 80.0)
			if back == Vector3.ZERO:
				row += "  --  "
			else:
				var b2 := _blockage(qx, g + EYE, qz, back.x, back.y + EYE, back.z)
				if b2.x <= CLEARANCE:
					score += 1
					row += "  ok"
				else:
					row += " X%3.0f" % b2.x
			if score > best_score:
				best_score = score
				best_row = row
				best_off = off
				best_pt = Vector2(qx, qz)
				best_g = g
				best_slope = slope
		if best_score < 0:
			continue
		print("  %5.0f (%5.0f,%6.0f) %+6.1f (%6.1f,%7.1f) %7.2f %5.1f  %s" % [
			d, s[k].y, s[k].w, best_off, best_pt.x, best_pt.y,
			best_g, best_slope, best_row,
		])
		if best_score >= 3:
			hits.append([d, best_pt.x, best_pt.y, best_g, best_off, best_score])
	print("  => 命中 >=3/5 的站点 %d 个 —— 这些才是值得建挑台的位置：" % hits.size())
	for h in hits:
		print("     D=%.0f  (%.1f, %.1f)  地面 %.2f m  侧向 %+.1f m  命中 %d/5" % [
			h[0], h[1], h[2], h[3], h[4], h[5],
		])


func _dump_csv(s: Array, csv_name: String) -> void:
	var lines := PackedStringArray()
	lines.append("dist,x,z,ground,grade20")
	for k in s.size():
		lines.append("%.2f,%.2f,%.2f,%.3f,%.2f" % [
			s[k].x, s[k].y, s[k].w, s[k].z, _grade20(s, k),
		])
	var path := OUT_DIR + csv_name
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("cannot open %s" % path)
		return
	f.store_string("\n".join(lines))
	f.close()
	print("  WROTE %d rows -> %s" % [lines.size() - 1, path])
