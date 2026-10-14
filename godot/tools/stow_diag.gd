extends SceneTree
# §STOW's instrument, and it is the source of the numbers quoted in `chain_visual.gd`.
#
# Reports the stow's layer-by-layer readings: how many links each layer actually draws,
# where those links land in NDC, how far the stow is from the safe band, and — the reading
# the whole design turns on — how many links of DIFFERENT layers overlap, with the per-pair
# clearance and the `d · n / rA / rB` breakdown that names WHY a failing pair fails.
#
# WHY IT IS NOT JUST A TEST. `chain_v4_slice`'s §STOW group asserts the three pass/fail
# claims (breach 0, 0 overlaps, the shed order) and is the thing that must stay green. What
# it cannot report is the SHAPE of the answer — the per-layer boxes, the tightest pair, the
# link half-edges, the seam-by-seam `n·t̂` that says whether a link is a run link or an arc
# link. Those are what a constant like `ARC_START` is actually chosen BY, so they need to be
# reproducible on demand rather than re-derived:
#
#     godot --headless --path godot --script res://tools/stow_diag.gd
#
# Run it before and after touching any `ARC_*` constant. The SEAMS table is the one that
# answers "is this link part of the run or part of the winding", which is the first question
# every stow failure so far has turned on.

const VIEW := Vector2(1280.0, 720.0)
const LAB_STAND := Vector3(0.0, 0.9, -33.0)

var world: Node3D
var player: CharacterBody3D
var chain: ChainDirector
var weapon: WeaponSlot
var visual: ChainVisual
var camera: Camera3D


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	world = (load("res://scenes/combat/CombatSandbox.tscn") as PackedScene).instantiate()
	root.add_child(world)
	await _wait(12)
	player = world.get_node("Player")
	chain = player.get_node("ChainDirector")
	weapon = player.get_node("WeaponSlot")
	visual = chain.chain_visual
	camera = player.get_node("CameraRig/LookPivot/MotionPivot/ShakePivot/Camera3D") as Camera3D
	weapon.equip(WeaponSlot.CHAIN)
	player.global_position = LAB_STAND
	player.rotation = Vector3.ZERO
	(player.get_node("CameraRig/LookPivot") as Node3D).rotation.x = 0.0
	chain.reset()
	await _wait(24)

	var seams: Array = visual.get("_stow_seams")
	var cuts: PackedInt32Array = visual.get("_arc_cuts")
	var stow_root: Node3D = visual.get("_coil_root")
	var loops: Array = visual.get("_coil_loops")

	print("")
	print("STOW DIAG · %d seams · cuts %s" % [seams.size(), str(cuts)])
	print("")

	# --- what each layer actually DRAWS, which is `[cut(layer), cut(layer+1))` --------
	var xf: Transform3D = stow_root.global_transform
	var to_eye := camera.global_transform.affine_inverse()
	var half := tan(deg_to_rad(camera.fov * 0.5))
	var aspect := VIEW.x / VIEW.y
	var joint: Vector3 = visual.call("_stow_eye")
	print("  %5s %7s %6s %8s %8s %8s %8s %7s" % [
		"layer", "seams", "links", "nx lo", "nx hi", "ny lo", "ny hi", "depth"
	])
	for c in cuts.size() - 1:
		var a: int = cuts[c]
		var b: int = cuts[c + 1] if c + 1 < cuts.size() else seams.size()
		var lnx := 99.0
		var hnx := -99.0
		var lny := 99.0
		var hny := -99.0
		var lz := 99.0
		var hz := -99.0
		for i in range(a, mini(b, seams.size())):
			var sv: Vector3 = seams[i]
			var loc: Vector3 = to_eye * (xf * sv)
			if loc.z >= -0.02:
				continue
			var nx: float = loc.x / (-loc.z * half * aspect)
			var ny: float = loc.y / (-loc.z * half)
			lnx = minf(lnx, nx)
			hnx = maxf(hnx, nx)
			lny = minf(lny, ny)
			hny = maxf(hny, ny)
			lz = minf(lz, -loc.z)
			hz = maxf(hz, -loc.z)
		var vis := "?"
		if c < loops.size():
			vis = "on" if (loops[c] as MeshInstance3D).visible else "OFF"
		print("  %5d %7d %6d %8.3f %8.3f %8.3f %8.3f %7.3f  %s" % [
			c, b - a, maxi(0, b - a - 1), lnx, hnx, lny, hny, hz, vis
		])

	# --- the reading the whole design turns on ---------------------------------------
	var hidden: int = visual.get("_coils")
	var boxes: Array = visual.call("_stow_link_boxes")
	print("")
	print("KNOT      interpenetration %d over %d boxes" % [
		visual.call("stow_interpenetration"), boxes.size()
	])
	print("          %5s %6s %8s %9s   %s" % ["a", "b", "hits", "min gap", "worst pair (stow space)"])
	var nlayers: int = maxi(1, (visual.get("_arc_cuts") as PackedInt32Array).size() - 1)
	for a in nlayers:
		for b in range(a + 1, nlayers):
			var hits := 0
			var best := 999.0
			var at := Vector3.ZERO
			var bt := Vector3.ZERO
			for i in boxes.size():
				for j in range(i + 2, boxes.size()):
					if int(boxes[i].layer) != a or int(boxes[j].layer) != b:
						continue
					var g: float = ChainVisual._obox_gap(boxes[i], boxes[j])
					if g <= 0.0:
						hits += 1
					if g < best:
						best = g
						at = boxes[i].c
						bt = boxes[j].c
			print("          %5d %6d %8d %9.4f   %s -> %s" % [
				a, b, hits, best, str(at.snappedf(0.001)), str(bt.snappedf(0.001))
			])
	var spacing := float(visual.get("link_spacing"))
	print("          (a link is %.4f wide across the rope and %.4f thick along its hole axis)"
		% [
			spacing * ChainVisual.LINK_FILL * ChainVisual.LINK_WIDTH_SCALE,
			spacing * ChainVisual.LINK_FILL * (1.0 - ChainVisual.LINK_TUBE_RATIO) * 0.5
		])
	# --- THE SAME QUESTION ASKED OF THE REAL GEOMETRY ---------------------------------
	# The box count above is the conservative proxy, and once links INTERLOCK it is the
	# wrong model for coplanar neighbours (see `_stow_link_rings`). This is the ring test:
	# true segment-to-segment distance between the drawn rings' centre-lines, minus the
	# two tube radii. `neighbour` is the chain's own interlock clearance and belongs to the
	# LINK; `layered` is what the stow has to get right and must not be near zero.
	var rings: Dictionary = visual.call("stow_ring_readings")
	var bounds: Dictionary = visual.call("chain_interlock_bounds")
	print("RINGS     over %d drawn rings, material clearance in metres (segment-to-segment):"
		% int(rings.links))
	print("            neighbour  %+.4f   (i,i+1 — threads BY DESIGN; belongs to the link)"
		% float(rings.neighbour))
	print("              worst at ring %d  %s" % [
		int(rings.n_at) + 1, str((rings.n_pos as Vector3).snappedf(0.001))
	])
	print("            layered    %+.4f   (i,j>=i+2 — the stow's own layering, plus the run)"
		% float(rings.layered))
	print("              worst at ring %d -> %d  %s" % [
		int(rings.l_at) + 1, int(rings.l_next) + 1, str((rings.l_pos as Vector3).snappedf(0.001))
	])
	print("            all        %+.4f" % float(rings.all))
	print("          chain interlock bounds: pitch %.4f in (%.4f, %.4f)  clearance %+.4f"
		% [
			float(bounds.pitch), float(bounds.min), float(bounds.max),
			float(bounds.clearance)
		])
	# THE CONTROL: the same link, on a dead straight run, with no stow involved. If this
	# is negative the LINK cannot be a chain at all and no stow shape can fix it.
	var straight: Dictionary = visual.call("chain_straight_clearance")
	print("STRAIGHT  the same link on a straight run (the control the stow is judged against):")
	print("            adjacent (i,i+1) %+.4f    skip-1 %+.4f    skip-2 %+.4f"
		% [float(straight.adjacent), float(straight.skip1), float(straight.skip2)])
	# HOW TIGHT THIS CHAIN MAY BE BENT, against how tight the fan actually is. The fan is a
	# squashed ellipse, so its tightest point is the end of its MAJOR axis: `b² / a`.
	var bend := float(visual.call("chain_min_bend_radius"))
	var fan := float(visual.call("stow_tightest_radius"))
	print("BEND      chain's min bend radius %.4f m   vs the drawn path's tightest turn %.4f m"
		% [bend, fan])
	var sa: float = ChainVisual.ARC_R_INNERMOST * ChainVisual.ARC_WIDE
	var sb: float = ChainVisual.ARC_R_INNERMOST * ChainVisual.ARC_SQUASH
	print("            (ellipse closed form b^2/a = %.4f m; a=%.4f b=%.4f)"
		% [sb * sb / sa, sa, sb])
	# WHERE the tight turn is, which is the question the fix depends on: the arc, the run,
	# or the tail. Same discrete curvature `stow_tightest_radius()` takes the min of.
	var turns := []
	for i in range(0, seams.size() - 2):
		var a1: Vector3 = (seams[i + 1] as Vector3) - (seams[i] as Vector3)
		var b1: Vector3 = (seams[i + 2] as Vector3) - (seams[i + 1] as Vector3)
		if a1.length() < 0.0001 or b1.length() < 0.0001:
			continue
		var turn: float = a1.normalized().angle_to(b1.normalized())
		if turn < 0.0001:
			continue
		turns.append({"i": i, "r": ((a1.length() + b1.length()) * 0.5) / turn, "deg": rad_to_deg(turn)})
	turns.sort_custom(func(x, y): return float(x.r) < float(y.r))
	print("TURNS     the %d tightest turns on the drawn path (seam index / layer / radius / turn):"
		% mini(5, turns.size()))
	for k in mini(5, turns.size()):
		var t: Dictionary = turns[k]
		var li := 0
		for c in cuts.size() - 1:
			if int(t.i) >= cuts[c]:
				li = c
		print("            seam %2d  L%d  r=%.4f m  turn %.1f deg" % [int(t.i), li, float(t.r), float(t.deg)])
	print("SAFE      breach %.4f   margin %+.4f   (band +/-0.38)"
		% [
			visual.call("stow_breach", camera, VIEW),
			visual.call("stow_margin", camera, VIEW)
		])
	# WHICH LINK sets that margin — the question the run/fan argument turns on.
	var tightest := 99.0
	var tight_at := Vector2.ZERO
	var tight_from := Vector3.ZERO
	for c in cuts.size() - 1:
		var a2: int = cuts[c]
		var b2: int = cuts[c + 1] if c + 1 < cuts.size() else seams.size()
		for i in range(a2, mini(b2, seams.size())):
			var sv: Vector3 = seams[i]
			if sv.distance_to(joint) < 0.16:
				continue
			var loc: Vector3 = to_eye * (xf * sv)
			if loc.z >= -0.02:
				continue
			var nx: float = loc.x / (-loc.z * half * aspect)
			var ny: float = loc.y / (-loc.z * half)
			var m := maxf(absf(nx), absf(ny))
			if m < tightest:
				tightest = m
				tight_at = Vector2(nx, ny)
				tight_from = sv
	print("          tightest drawn link: layer ? seam ?  ndc %s  (|max| %.3f)  %s"
		% [str(tight_at.snappedf(0.001)), tightest, str(tight_from.snappedf(0.001))])
	# THE OTHER HALF OF THE SAFE-ZONE RULE: leaving the picture. `breach` only asks
	# whether the surplus entered the MIDDLE; a stow too big does not breach, it walks
	# out of the left edge — and with circular arcs `breach` read 0.0000 while layer 3
	# sat at NDC x -1.382. `reach` is the farthest |max(nx,ny)| any drawn link reaches;
	# it must be < 1.0. The per-layer tail is what tells you WHICH layer to fix.
	var reach := float(visual.call("stow_frame_reach", camera, VIEW))
	print("FRAME     farthest drawn link |max(nx,ny)| %.3f   %s   (want < 1.0)"
		% [reach, "OK" if reach < 1.0 else "OFF-SCREEN"])
	var lay_reach: Array = []
	for c in cuts.size() - 1:
		var a3: int = cuts[c]
		var b3: int = cuts[c + 1] if c + 1 < cuts.size() else seams.size()
		var lo := Vector2(99.0, 99.0)
		var hi := Vector2(-99.0, -99.0)
		for i in range(a3, mini(b3, seams.size())):
			var sv2: Vector3 = seams[i]
			if sv2.distance_to(joint) < 0.16:
				continue
			var loc2: Vector3 = to_eye * (xf * sv2)
			if loc2.z >= -0.02:
				continue
			var nx2: float = loc2.x / (-loc2.z * half * aspect)
			var ny2: float = loc2.y / (-loc2.z * half)
			lo = Vector2(minf(lo.x, nx2), minf(lo.y, ny2))
			hi = Vector2(maxf(hi.x, nx2), maxf(hi.y, ny2))
		lay_reach.append(Vector4(lo.x, hi.x, lo.y, hi.y))
	for c in lay_reach.size():
		var b: Vector4 = lay_reach[c]
		var worst: float = maxf(maxf(absf(b.x), absf(b.y)), maxf(absf(b.z), absf(b.w)))
		print("            L%d  x %+.3f..%+.3f  y %+.3f..%+.3f   |max| %.3f  %s"
			% [c, b.x, b.y, b.z, b.w, worst, "OK" if worst < 1.0 else "OFF-SCREEN"])
	# ---- THE OTHER END OF THE SAME PATH: the joint with the HANDLE -------------------
	# Everything above judges the stow at the HIP and nothing judged the FIST. The rope's
	# first links are the weapon's joint with the hand, and the handle is a body of
	# revolution on its own axis — so ONE clearance number answers "does the rope leave
	# the hilt cleanly", and ONE angle answers "does it leave through the eye": the eye
	# is a torus and the rope has to pass through its HOLE, which means the torus axis
	# has to BE the direction the rope leaves in. MEASURED, and both were failing: the
	# leave direction came out 0.95 of the way DOWN THE SHAFT, so the rope ran inside
	# the collar, and the ring stood across it at 76 deg — a rope through a rim.
	var handle: Node3D = visual.get("_handle")
	if handle != null:
		var to_handle := handle.global_transform.affine_inverse()
		var hb := handle.global_transform.basis
		var stow_b: Basis = visual.call("_stow_basis")
		# the fan's own normal carried all the way into the camera: the number that says
		# whether the stow is seen face-on (which is a target disc, i.e. 几个圆盘) or
		# obliquely (which is loops hanging in space).
		var fan_n: Vector3 = (to_eye.basis * hb * (stow_b * (visual.call("_stow_normal") as Vector3))).normalized()
		var face := rad_to_deg(acos(clampf(absf(fan_n.dot(Vector3.FORWARD)), 0.0, 1.0)))
		# WHAT THE ANGLE MEANS, IN THE UNITS THE DESIGN USES. A fan whose normal makes an
		# angle `f` with the view axis projects to an ellipse `cos(f)` as wide as it is
		# long, so the number the look turns on is that ratio, not the angle — and the
		# word is only a label for it. 偏扁 is the user's ask and it wants a SMALL ratio.
		var flat_ratio := cos(deg_to_rad(face))
		var look := "face-on — 几个圆盘贴在镜头边"
		if face >= 35.0:
			look = "oblique — loops"
		if face >= 62.0:
			look = "lying over — 偏扁"
		if face >= 80.0:
			look = "edge-on — a line"
		print("HANDLE    fan normal in the camera %s  —  %.1f deg off the view axis  (%s)"
			% [str(fan_n.snappedf(0.001)), face, look])
		print("          ...so the fan projects %.2f as wide as it is long  (偏扁 wants this small)"
			% flat_ratio)
		var eye: Node3D = null
		for ch in handle.get_children():
			if ch is MeshInstance3D and (ch as MeshInstance3D).mesh is TorusMesh:
				eye = ch
		if eye != null:
			# THE VERDICTS COME FROM `ChainVisual`, NOT FROM HERE. These three readings are
			# the user's rule 不要穿模刀手柄, so they are ASSERTED in `chain_v4_slice` and a
			# diagnostic that recomputed them would be a second opinion that could disagree
			# — which is exactly how the ring-vs-rope reading lied the first time, when it
			# was measured against a second expression of the departure instead of the one.
			# What stays here is only what a reviewer needs and a test does not: WHERE.
			var leave: Vector3 = (visual.call("_handle_leave") as Vector3).normalized()
			var shaft := rad_to_deg(acos(clampf(absf(leave.dot(Vector3.UP)), 0.0, 1.0)))
			var ring := float(visual.call("stow_eye_threading"))
			print("JOINT     eye at %s   ring axis vs the rope %.1f deg  (%s)"
				% [
					str(eye.position.snappedf(0.001)), ring,
					"threads the hole" if ring < 20.0 else "crosses the rim — IT CLIPS"
				])
			print("          the rope leaves %.1f deg off the shaft axis  %s"
				% [shaft, str(leave.snappedf(0.001))])
			var rc := float(visual.call("stow_eye_clearance"))
			print("          eye ring vs the hilt: %+.4f m   %s"
				% [rc, "CLEAR" if rc > 0.0 else "CLIPS"])
		# Sub-sampled between seams: the worst point of the departure is where the rope
		# draws level with the collar's top rim, which falls BETWEEN two seams. The
		# clearance itself comes from `ChainVisual.stow_hilt_clearance()`; this scan only
		# names the seam, so the two can never disagree about the number.
		var runclear := float(visual.call("stow_hilt_clearance"))
		var runat := Vector3.ZERO
		var runi := -1
		for i in seams.size():
			var a4: Vector3 = seams[i]
			var b4: Vector3 = seams[mini(i + 1, seams.size() - 1)]
			for s in 9:
				var p: Vector3 = a4.lerp(b4, float(s) / 8.0)
				var hx: Vector3 = to_handle * (xf * p)
				if absf(hx.y) > 0.24:
					continue
				var c2 := sqrt(hx.x * hx.x + hx.z * hx.z) - float(visual.call("handle_radius_at", hx.y))
				if absf(c2 - runclear) < 0.0005:
					runat = hx
					runi = i
		print("          rope vs the hilt: min %+.4f m at seam %d %s   %s"
			% [runclear, runi, str(runat.snappedf(0.001)), "CLEAR" if runclear > 0.0 else "CLIPS"])
	print("EDGES     a link's 3 half-edges, first drawn box (want 0.0312 / 0.0114 / 0.0473):")
	for bi in mini(4, boxes.size()):
		var e: Array = boxes[bi].e
		print("            layer %d  %.4f %.4f %.4f  |  %.4f %.4f %.4f  ->  len %.4f %.4f %.4f" % [
			int(boxes[bi].layer),
			e[0].x, e[0].y, e[0].z, e[1].x, e[1].y, e[1].z,
			(e[0] as Vector3).length(), (e[1] as Vector3).length(), (e[2] as Vector3).length()
		])

	# why the failing pairs fail: how far apart are they ALONG THE LAYER NORMAL?
	# NB this section is the BOX model — `_obox_gap` — and it is the one to distrust when
	# the count above is dominated by `j - i == 2`. Read `RINGS` for the verdict.
	var norm: Vector3 = visual.call("_stow_normal")
	print("BOXPAIRS  the box model's failing pairs, a link against its neighbour+2:")
	print("NORMAL    %s   (the direction ARC_DEPTH steps along)" % str(norm.snappedf(0.0001)))
	var shown := 0
	for i in boxes.size():
		for j in range(i + 1, boxes.size()):
			if j - i <= 1:
				continue
			var g: float = ChainVisual._obox_gap(boxes[i], boxes[j])
			if g > 0.0 or shown >= 14:
				continue
			var d: Vector3 = boxes[j].c - boxes[i].c
			var ra := 0.0
			for e in boxes[i].e:
				ra += absf(norm.dot(e))
			var rb := 0.0
			for e in boxes[j].e:
				rb += absf(norm.dot(e))
			print("          %2d(L%d) %2d(L%d)  gap %.4f  d.n %+.4f  rA %+.4f rB %+.4f  %s -> %s" % [
				i, int(boxes[i].layer), j, int(boxes[j].layer), g,
				norm.dot(d), ra, rb,
				str((boxes[i].c as Vector3).snappedf(0.001)),
				str((boxes[j].c as Vector3).snappedf(0.001))
			])
			shown += 1
	# WHICH SEAM IS WHICH. Box index == seam index (`_arc_cut(0)` is 0 and the boxes are
	# appended layer by layer with no gap), so this table says whether a failing pair is a
	# RUN link or an ARC link — which is the only question the fix depends on.
	var nvec: Vector3 = visual.call("_stow_normal")
	print("SEAMS     i  layer   position                    |tangent|   n.t")
	for li in cuts.size() - 1:
		var ca: int = cuts[li]
		var cb: int = cuts[li + 1] if li + 1 < cuts.size() else seams.size()
		for i in range(ca, mini(cb, seams.size() - 1)):
			var tg: Vector3 = (seams[i + 1] as Vector3) - (seams[i] as Vector3)
			print("          %2d  %5d   %s  %8.4f  %+.3f" % [
				i, li, str((seams[i] as Vector3).snappedf(0.001)),
				tg.length(), nvec.dot(tg.normalized())
			])
	print("COILS     shown %s  drawn %d  loops %d" % [str(hidden), visual.call("links_drawn"), loops.size()])
	print("          eye overlap: %d seams within 0.16m of the fist joint" % _joint_count(seams, joint))
	print("")
	quit()


func _joint_count(seams: Array, joint: Vector3) -> int:
	var n := 0
	for s in seams:
		if (s as Vector3).distance_to(joint) < 0.16:
			n += 1
	return n


func _wait(frames: int) -> void:
	for i in frames:
		await process_frame

