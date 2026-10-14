extends "res://scripts/vfx/vfx_prototype.gd"
#
# 04 · 万剑 · 世界剑鞘 / WORLD SCABBARD  ·  V2
#
# =============================================================================
# WHAT V1 GOT WRONG
# =============================================================================
#
# V1 put 180 blades in the ground and pulled them all out at once. In the
# thumbnail that read as a field of white lines, and in the full-size frame it read
# as a field of white lines — a LASER SWORD RAIN. The word for what was missing is
# ORIGIN. Nothing in the picture said the blades had come out of the world; the
# picture only said that blades existed, in the air, roughly everywhere.
#
# =============================================================================
# V2: THE EDGES COME OFF
# =============================================================================
#
# The world is a scabbard, so the blades have to be the world's own EDGES. Not
# generic swords buried in soil — the eaves, the wall corners, the road's kerb, the
# bridge's pillars, the trunks. Each one leaves along the single shared axis and
# each one leaves a SLOT where it was.
#
# The slot is the whole prototype. A light line in the air is a laser; the same
# line in the air with a dark groove left behind in the eave it came out of is an
# EXTRACTION, and the audience reads the second one without being told.
#
# The slot is a fake proxy, and deliberately so — there is no runtime mesh boolean
# in this project, and there does not need to be one. A dark slab laid along the
# edge's own footprint, a centimetre proud of the surface, is indistinguishable
# from a groove dug out of it at any range this clip is seen from, and it costs a
# `BoxMesh`.
#
# =============================================================================
# V2: THE ORDER IS THE STORY
# =============================================================================
#
#   0.9  one roof edge           <- the world moves first
#   1.3  one wall corner
#   1.7  the road's edge
#   2.2  a bridge pillar
#   2.6  a tree trunk
#   3.0  a second roof, and the field answers
#   3.3  THE PLAYER DRAWS          <- the gesture is a REPLY, not a command
#   4.3  everything detaches
#
# V1 had the player draw first and the world answer. V2 inverts it, because
# "why is the world's edge coming off?" is a question the audience asks for free,
# and a question is a much better hook than an announcement. The draw is then the
# player agreeing with something that has already started.
#
# =============================================================================
# WHY THE ENDING SURVIVES UNCHANGED
# =============================================================================
#
# One blade is left standing in the road at exactly the player's own sword length.
# It was the best sentence in V1 — the world telling the player what they are made
# of — and nothing about the V2 rework argues with it.

const FIELD_X := 76.0
const FIELD_Z_NEAR := 24.0
const FIELD_Z_FAR := -158.0
const FIELD_STEP := 9.0
## The lean every blade shares, including the edges. A scabbard is worn at an angle
## and everything in it comes out at that angle; this is why the extraction is a
## TRANSLATION and never a rotation, for a roof edge and a bridge pillar alike.
const LEAN := -0.20
const LEAN_SIDE := -0.085

const EDGE0 := 0.90
const EDGE_STEP := 0.42
const DRAW_START := 3.30
const DRAW_END := 4.20
const ANSWER_START := 3.05
const HERO_START := 6.20
const HERO_END := 8.30
const RETRACT_START := 8.70
const RETRACT_END := 10.80
## Where the player stands. The lone blade at the end is at their feet.
const FOOT := Vector3(0.40, 0.0, -1.70)

var blades: Array = []          # the unattributed field
var edges: Array = []           # the named edges, in the order they leave
var blade_mm: MultiMeshInstance3D
var mouth_mm: MultiMeshInstance3D
var mouth_mat: ShaderMaterial
var axis := Vector3.UP
var road_blade: Node3D
var lone_blade: Node3D


func build() -> void:
	super()
	t_end = 11.6
	lab.set_sky("day")
	lab.sun.light_energy = 1.10
	lab.player_proxy.visible = false

	# The shared axis, given as a direction rather than as three Euler numbers so
	# nothing can drift out of parallel.
	axis = Basis.from_euler(Vector3(LEAN, 0.0, LEAN_SIDE)) * Vector3.UP

	_build_edges()
	_collect_blades()

	# ---- THE FIELD -----------------------------------------------------------
	blade_mm = MultiMeshInstance3D.new()
	var blade_mesh := PrismMesh.new()
	blade_mesh.size = Vector3(0.19, 1.0, 0.055)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = blade_mesh
	mm.instance_count = blades.size()
	blade_mm.multimesh = mm
	# A blade is metal, and metal without a reflection probe is a black silhouette
	# in `gl_compatibility` — so 0.34 and a fairly rough surface, lit by the sky
	# ambient, which is the only thing in this lab that lights a vertical face
	# consistently.
	blade_mesh.surface_set_material(0, world_mat(Color(0.545, 0.585, 0.645), 0.40, 0.30))
	blade_mm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	stage.add_child(blade_mm)

	# ---- THE MOUTHS ----------------------------------------------------------
	# Flat discs lying in the ground at each blade's exit point. The mouths are why
	# the ground reads as a scabbard rather than as soil: a blade that leaves a hole
	# was forced, and a blade that leaves a clean lit seam was SHEATHED.
	mouth_mm = MultiMeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 0.62
	disc.bottom_radius = 0.62
	disc.height = 0.02
	disc.radial_segments = 12
	disc.rings = 1
	var mm2 := MultiMesh.new()
	mm2.transform_format = MultiMesh.TRANSFORM_3D
	mm2.mesh = disc
	mm2.instance_count = blades.size()
	mouth_mm.multimesh = mm2
	mouth_mat = lab.glow_mat(Color(0.62, 0.80, 1.00), 1.15, 0.0, 0.0)
	mouth_mat.set_shader_parameter("alpha", 0.0)
	disc.surface_set_material(0, mouth_mat)
	mouth_mm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	stage.add_child(mouth_mm)

	road_blade = _hero_blade(Vector3(0.0, lab.ground_height(0.0, -42.0), -42.0), 26.0)
	lone_blade = _hero_blade(Vector3(FOOT.x, lab.ground_height(FOOT.x, FOOT.z), FOOT.z), 1.15)


## =============================================================================
## THE NAMED EDGES, IN THE ORDER THE BRIEF ASKS FOR THEM
## =============================================================================
##
## Each entry is a line the world already owns: a building's eave, a building's
## vertical corner, the road's kerb, a bridge pillar, a tree trunk. They are built
## as long thin boxes lying exactly along those lines, with a dark slot laid into
## the same footprint one centimetre beneath them.
##
## Positions are DERIVED FROM `lab.props` rather than typed in, so if the greybox
## village moves the edges move with it. A hardcoded eave height would be correct
## until somebody made a building taller and then wrong in a way that renders as
## "the blade is floating next to the roof", which looks like a physics bug.
func _build_edges() -> void:
	var mats: Array = lab.group("building")
	# Building0 is the one the opening camera looks at, so it owns the first two.
	if mats.size() >= 1:
		var b0: Dictionary = mats[0]
		var home: Vector3 = b0["home_pos"]
		var size: Vector3 = b0["size"]
		var h := size.y - 0.60
		# THE ROOF EDGE. Along the eave's own width, at its front-top corner.
		_edge("RoofEdge", home + Vector3(0.0, h + 0.18, size.z * 0.5 - 0.10),
			Vector3.RIGHT, size.x, Vector3.FORWARD, 0)
		# THE WALL CORNER. Vertical, at the body's front-right corner.
		var bw := size.x - 1.20
		var bd := size.z - 1.20
		_edge("WallEdge", home + Vector3(bw * 0.5 - 0.05, h * 0.5, bd * 0.5 - 0.05),
			Vector3.UP, h * 0.96, Vector3(bw * 0.5, 0.0, bd * 0.5).normalized(), 1)
	# THE ROAD'S KERB, running with the road — and set out at x = 4.9 rather than
	# 3.55, because at 3.55 it was close enough to the opening camera to fill the
	# right third of the frame with a pale slab before anything had even happened.
	_edge("RoadEdge", lab.at_ground(4.90, -24.0, 0.10), Vector3.BACK, 17.0,
		Vector3.LEFT, 2)
	# A BRIDGE PILLAR. Vertical, at its own corner, and tall — the one edge in the
	# set that is obviously structural.
	_edge("PillarEdge", Vector3(-9.0, lab.ground_height(0.0, -68.0) + 1.4, -68.0 + 0.52),
		Vector3.UP, 8.4, Vector3(0.52, 0.0, 0.0), 3)
	# A TREE TRUNK, because the brief asks for one and because a living thing's edge
	# leaving is a different claim from a building's.
	var trees: Array = lab.group("tree")
	if trees.size() > 2:
		var tr: Dictionary = trees[2]
		var tp: Vector3 = tr["home_pos"]
		_edge("TrunkEdge", Vector3(tp.x + 0.20, lab.ground_height(tp.x, tp.z) + 1.7, tp.z),
			Vector3.UP, 3.0, Vector3(1.0, 0.0, 0.0), 4)
	# ...AND THEN THE SECOND ROOF, which is where "some edges are coming off" turns
	# into "this is happening to the whole world".
	if mats.size() >= 2:
		var b1: Dictionary = mats[1]
		var home1: Vector3 = b1["home_pos"]
		var size1: Vector3 = b1["size"]
		var h1 := size1.y - 0.60
		_edge("RoofEdge2", home1 + Vector3(0.0, h1 + 0.18, size1.z * 0.5 - 0.10),
			Vector3.RIGHT, size1.x, Vector3.FORWARD, 5)


func _edge(name: String, at: Vector3, dir: Vector3, length: float,
		inward: Vector3, slot: int) -> void:
	var root := Node3D.new()
	root.name = name
	root.position = at
	# Orient the box so its LOCAL X runs along the edge and its Y/Z are the
	# cross-section — then a scale of (1, t, t) thins the edge into a blade without
	# changing its length, which is the "it becomes a blade" move.
	var d := dir.normalized()
	var up_ref := Vector3.UP if absf(d.dot(Vector3.UP)) < 0.92 else Vector3.BACK
	var side := d.cross(up_ref).normalized()
	var local_y := side.cross(d).normalized()
	var basis := Basis(d, local_y, side)
	root.transform = Transform3D(basis, at)
	stage.add_child(root)

	var thin := Vector3(length, 0.155, 0.105)
	var fat := Vector3(length, 0.235, 0.170)
	# DULLER THAN V1'S BLADES, AND THINNER. At the ranges V2's hero frame needs (the
	# damage has to be legible, so the camera is close), a bright 0.4 m-wide prism is
	# a white board rather than a sword. 0.19 m and a greyer metal read as blades at
	# 15 m, and the loss at 60 m does not matter because V2 has no shot at 60 m.
	var mat := world_mat(Color(0.545, 0.585, 0.645), 0.40, 0.30)
	var blade := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = fat
	blade.mesh = m
	blade.material_override = mat
	blade.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# 2 cm proud of the surface the edge belonged to, so the blade is outside the
	# wall it came from even at rest — an edge that has already been loosened.
	blade.position = inward.normalized() * 0.020
	root.add_child(blade)

	# ---- THE SLOT ------------------------------------------------------------
	# Dark, 8 mm proud, and a little wider than the blade, so a rim of it shows
	# around the blade even before anything moves. That rim is what tells the eye,
	# in the very first frame, that this line is a thing that comes OUT.
	var slot_mesh := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = fat * 1.34
	slot_mesh.mesh = sm
	slot_mesh.material_override = world_mat(Color(0.030, 0.033, 0.040), 0.99)
	slot_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	slot_mesh.position = inward.normalized() * 0.008
	slot_mesh.visible = false
	root.add_child(slot_mesh)

	edges.append({
		"node": root, "blade": blade, "slot": slot_mesh, "rest": at,
		"fat": fat, "thin": thin, "order": slot,
	})


## Every blade's rest data. Computed once, never again: `apply` reads this and `t`,
## and stores nothing.
func _collect_blades() -> void:
	var cols := int((FIELD_X * 2.0) / FIELD_STEP) + 1
	var rows := int((FIELD_Z_NEAR - FIELD_Z_FAR) / FIELD_STEP) + 1
	for gz in rows:
		for gx in cols:
			var s := float(gz * 131 + gx)
			# THINNED OUT BY HASH, NOT BY RANDOM. Two thirds of the grid goes, and
			# which two thirds is fixed by the cell index — so the field is the same
			# field in the still and in the take.
			if n1(s * 3.7, 0.0) < 0.52:
				continue
			var x := -FIELD_X + float(gx) * FIELD_STEP + n_signed(s * 1.3, 0.0) * FIELD_STEP * 0.46
			var z := FIELD_Z_NEAR - float(gz) * FIELD_STEP + n_signed(s * 2.1, 0.0) * FIELD_STEP * 0.46
			# NOT AT THE PLAYER'S FEET. A 16 m blade rising two metres from the lens
			# fills a third of the frame with a pale wash and hides the village behind
			# it — which is what the first V2 sheet showed. The clear patch costs
			# nothing: the retract already runs outward from the player, so the one
			# place the field should not be is the one place the camera would be
			# standing.
			if Vector2(x - FOOT.x, z - FOOT.z).length() < 7.5:
				continue
			# THE ROAD ITSELF IS NOT SPARED. A blade field with a clear road down the
			# middle is a blade field with a safe path in it.
			var length := lerpf(5.5, 16.5, n1(s * 5.9, 0.0))
			_add_blade(Vector3(x, lab.ground_height(x, z), z), length, s)
	# ...AND UNDER EVERY SOLID THING. This is the sentence the clip is actually
	# making, so it is not left to a scatter function to happen to cover.
	for e in lab.props:
		var kind := String(e["kind"])
		if kind == "ground" or kind == "road" or kind == "hill" or kind == "figure":
			continue
		var size: Vector3 = e["size"]
		if size.y < 1.2:
			continue
		var home: Vector3 = e["home_pos"]
		_add_blade(Vector3(home.x, lab.ground_height(home.x, home.z), home.z),
			clampf(size.y * 1.75, 6.0, 24.0), home.x * 7.1 + home.z * 3.3)


func _add_blade(pos: Vector3, length: float, seed: float) -> void:
	blades.append({"pos": pos, "len": maxf(length, 0.6), "seed": seed})


func _hero_blade(at: Vector3, length: float) -> Node3D:
	var root := Node3D.new()
	root.position = at
	root.set_meta("base", at)
	stage.add_child(root)
	var mat := world_mat(Color(0.640, 0.680, 0.735), 0.34, 0.34)
	var body_len := length * 0.78
	root.add_child(_part(_box(Vector3(0.20 + length * 0.020, body_len, 0.055 + length * 0.006)),
		mat, Vector3(0.0, body_len * 0.5, 0.0)))
	var tip := PrismMesh.new()
	tip.size = Vector3(0.20 + length * 0.020, length * 0.22, 0.055 + length * 0.006)
	root.add_child(_part(tip, mat, Vector3(0.0, body_len + length * 0.11, 0.0)))
	var guard := _box(Vector3(0.52 + length * 0.030, 0.075, 0.16 + length * 0.006))
	root.add_child(_part(guard, world_mat(Color(0.300, 0.290, 0.268), 0.55, 0.30),
		Vector3(0.0, length * 0.055, 0.0)))
	root.rotation = Vector3(LEAN, 0.0, LEAN_SIDE)
	return root


func _box(size: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	return m


func _part(mesh: Mesh, mat: Material, at: Vector3) -> MeshInstance3D:
	var n := MeshInstance3D.new()
	n.mesh = mesh
	n.material_override = mat
	n.position = at
	n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return n


func apply(t: float) -> void:
	# ---- THE NAMED EDGES, ONE AT A TIME --------------------------------------
	# Each one loosens (a 5 cm proud stand) and then, once the player has drawn,
	# detaches fully along the shared axis. The two stages are separate because the
	# brief asks for them separately: the world's edges first go WRONG, and only
	# afterwards do they go.
	var drawn := ease_in_out(span(t, DRAW_START, DRAW_END + 0.45))
	for e in edges:
		var order := int(e["order"])
		var start := EDGE0 + EDGE_STEP * float(order)
		var loose := ease_in_out(span(t, start, start + 0.50))
		var blade: MeshInstance3D = e["blade"]
		var slot: MeshInstance3D = e["slot"]
		var node: Node3D = e["node"]
		var offset := 0.05 * loose + 2.30 * loose * drawn
		node.position = (e["rest"] as Vector3) + axis * offset
		# The cross-section thins as it goes: an eave edge is a slab, and the thing
		# that leaves is a blade. Length is never touched, because the whole point is
		# that this line is the length of the building.
		var k := lerpf(1.0, 0.62, loose * drawn)
		blade.scale = Vector3(1.0, k, k)
		slot.scale = Vector3(1.0, k, k)
		# The slot appears the instant the edge stops covering it, and never goes
		# away — this is the damange half of the hero frame.
		slot.visible = offset > 0.012

	# ---- THE FIELD -----------------------------------------------------------
	var mm := blade_mm.multimesh
	var m2 := mouth_mm.multimesh
	var live := 0
	var peak := 0.0

	for i in blades.size():
		var b: Dictionary = blades[i]
		var pos: Vector3 = b["pos"]
		var length: float = b["len"]
		var seed: float = b["seed"]

		# THE ANSWER SPREADS OUTWARD FROM THE PLAYER. The delay is proportional to
		# distance from the player's feet, so the field is not switched on — it
		# propagates, and the player is standing at the centre of it.
		var d := Vector2(pos.x - FOOT.x, pos.z - FOOT.z).length()
		var rise_at := ANSWER_START + 0.42 * n1(seed, 1.0) + 0.0115 * d
		var rise := ease_out_cubic(span(t, rise_at, rise_at + 1.35 + 0.5 * n1(seed, 2.0)))
		var pull_at := RETRACT_START + 0.42 * n1(seed, 3.0) + 0.0042 * (150.0 - d)
		var pull := ease_in_out(span(t, pull_at, pull_at + 1.05))
		var out: float = rise * (1.0 - pull)
		peak = maxf(peak, out)

		# THE BLADE SLIDES ALONG ITS OWN AXIS. `out = 0` is fully sheathed with the
		# tip at ground level; `out = 1` is fully drawn.
		var centre := pos + axis * (length * (out - 0.5))
		var thick := 1.0 + 0.055 * length
		var basis := Basis(Quaternion(Vector3.UP, axis)).scaled(
			Vector3(thick, length * maxf(out, 0.0001), thick))
		mm.set_instance_transform(i, Transform3D(basis, centre))
		m2.set_instance_transform(i, Transform3D(
			Basis().scaled(Vector3.ONE), pos + Vector3.UP * 0.015))
		if out > 0.001:
			live += 1

	mouth_mat.set_shader_parameter("alpha", clampf(peak * 1.6, 0.0, 0.62))
	mouth_mm.visible = peak > 0.01

	var road_out := ease_out_cubic(span(t, ANSWER_START - 0.25, ANSWER_START + 2.6))
	road_out *= 1.0 - ease_in_out(span(t, RETRACT_START + 0.30, RETRACT_END))
	_place_hero(road_blade, 26.0, road_out)
	# The lone blade is drawn WITH THE PLAYER'S OWN HAND and the retract does not
	# touch it: it is the receipt.
	var lone_out := ease_in_out(span(t, DRAW_START + 0.30, DRAW_END + 0.55))
	_place_hero(lone_blade, 1.15, lone_out)

	lab.weapon_root.visible = t < HERO_END or (t > 8.75 and t < 10.00)
	_camera(t)
	_weapon(t)

	if fmod(maxf(t, 0.0), 1.0) < 0.02:
		print("世界剑鞘: %d / %d field blades out at t=%.1f" % [live, blades.size(), t])


func _place_hero(node: Node3D, length: float, out: float) -> void:
	var base: Vector3 = node.get_meta("base", node.position)
	node.visible = out > 0.01
	node.position = base + axis * (length * (out - 1.0))


func _camera(t: float) -> void:
	if t < HERO_START:
		# FIRST PERSON. The opening is a portrait of ONE ROOF: the camera looks at
		# the eave that is about to come apart, because "why is that edge moving" is
		# the question this prototype is built on and a wide shot asks it about
		# nothing in particular.
		lab.review_off()
		var widen := ease_in_out(span(t, EDGE0 + 1.6, HERO_START))
		var drift := sin(t * 0.21) * 0.9
		var eye := Vector3(FOOT.x + 0.30, lab.ground_height(FOOT.x, 0.0) + 1.74, 0.0)
		# It starts close on Building0's eave (13,-20) and pulls back and up as the
		# field arrives, so the frame goes from one edge to all of them.
		var aim := Vector3(-11.2, 6.3, -19.4).lerp(
			Vector3(drift, 7.60, -34.0), widen)
		camera(eye, aim, lerpf(38.0, 62.0, widen), sin(t * 0.33) * 0.008)
		return

	if t < HERO_END:
		# THE HERO FRAME. This is a MID shot and not a wide one, and that is the
		# correction V2 makes to V1: the claim is "the world's edges came off", so
		# the frame has to contain both the missing edges and the blades that used
		# to be them. A wide shot of a blade field is a laser rain; a building with
		# slots in its eaves and its own outline hanging in the air beside it is an
		# extraction.
		lab.review_off()
		var u := ease_in_out(span(t, HERO_START, HERO_END))
		var eye2 := Vector3(6.4, 6.2, -3.0).lerp(Vector3(9.8, 8.4, 1.6), u)
		camera(eye2, Vector3(-9.5, 4.4, -19.0), lerpf(52.0, 46.0, u), 0.0)
		return

	# BACK TO THE EYE FOR THE RETRACT, and held there, because the ending has to be
	# read at the player's own scale: a road, and one sword-length of blade standing
	# in it where they are standing.
	lab.review_off()
	var settle := ease_in_out(span(t, RETRACT_END - 1.60, t_end - 0.65))
	var eye3 := Vector3(FOOT.x + 0.30, lab.ground_height(FOOT.x, 0.0) + 1.74, 0.0)
	camera(eye3, Vector3(FOOT.x - 0.10, lerpf(6.40, 0.95, settle), lerpf(-34.0, FOOT.z, settle)),
		lerpf(60.0, 62.0, settle), 0.0)


## The player's own draw, which now answers the world instead of starting it.
func _weapon(t: float) -> void:
	var up := ease_in_out(span(t, DRAW_START, DRAW_END))
	up *= 1.0 - ease_in_out(span(t, RETRACT_START + 0.45, RETRACT_END + 0.20))
	lab.weapon_blend(Vector3(0.44, -0.36, -0.74), Vector3(-38.0, -30.0, 12.0), 0.92, up)


func phase_name(t: float) -> String:
	if t < EDGE0:
		return "起手 · 一切都还在原处"
	if t < DRAW_START:
		return "世界的边开始离开 %.0f/6" % floor((t - EDGE0) / EDGE_STEP + 1.0)
	if t < DRAW_END + 0.45:
		return "拔刀"
	if t < HERO_START:
		return "万物出鞘 %.0f%%" % (100.0 * span(t, ANSWER_START, ANSWER_START + 3.4))
	if t < HERO_END:
		return "缺了边的世界 · 悬着的刀"
	if t < RETRACT_END:
		return "归鞘"
	return "一把刀留在了原地"
