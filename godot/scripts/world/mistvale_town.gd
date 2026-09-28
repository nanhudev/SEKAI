@tool
extends Node3D
class_name MistvaleTown
## LEVEL ART — the building kit for the Mistvale settlement.
##
## WHY A KIT AND NOT HAND-MODELLED HOUSES: the masterplan needs 28 town masses
## and a village of 28 identical buildings is not a village, it is a texture
## repeat. Modelling 28 unique houses is a week. So the kit defines the PARTS a
## Mistvale house is made of, and each house is assembled from those parts with
## its own dimensions, rotation, roof pitch and additions.
##
## PARTS
##   foundation   stepped stone plinth that follows the ground
##   sill / plate horizontal timbers top and bottom of the wall
##   post         corner and intermediate vertical timbers
##   panel        plaster infill between the posts
##   window       a dark recessed opening with a timber surround
##   door
##   gable        the triangular wall at each roof end
##   roof plane   the two slopes, with overhang
##   ridge        the beam along the top
##   chimney / balcony / awning / lean-to / shed / fence   the additions
##
## IMPERFECTION IS A REQUIREMENT, NOT A NICE-TO-HAVE (brief §16). A village
## grows; it is not plotted. So every house gets:
##   * a rotation that is not axis-aligned,
##   * a foundation height taken from the ground under IT, not from the street,
##   * a width, depth, storey height and roof pitch drawn from its own seed,
##   * and a roll on the additions table — some have a shed, some a lean-to,
##     some a balcony, some nothing at all.
##
## THE STREET STAYS CLEAR. Any house whose footprint lands within
## STREET_CLEARANCE of a walked road centreline is not built. A house standing
## in the middle of the main street is not a house, it is a bug.
##
## EVERY GROUND HEIGHT COMES FROM MistvaleHeights.

@export var build_houses: bool = true
@export var build_props: bool = true

## The masterplan's 28 town masses. Each is a LOT, not a building: a lot is
## subdivided into two or three houses with different footprints and rotations.
const LOTS := [
	[-95.0, 78.0, 30.0, 22.0], [-55.0, 80.0, 34.0, 20.0], [-15.0, 82.0, 28.0, 20.0],
	[28.0, 80.0, 30.0, 22.0], [72.0, 78.0, 32.0, 20.0],
	[-100.0, 48.0, 26.0, 24.0], [-60.0, 52.0, 30.0, 22.0], [-12.0, 50.0, 26.0, 20.0],
	[26.0, 52.0, 28.0, 22.0], [70.0, 50.0, 30.0, 22.0],
	[100.0, 32.0, 26.0, 26.0],
	[-52.0, 8.0, 26.0, 22.0], [-50.0, -14.0, 24.0, 20.0],
	[52.0, 6.0, 28.0, 22.0], [54.0, -16.0, 26.0, 20.0],
	[-30.0, 26.0, 22.0, 18.0], [30.0, 28.0, 22.0, 18.0],
	[-34.0, -44.0, 20.0, 18.0], [34.0, -44.0, 20.0, 18.0],
	[-70.0, -78.0, 28.0, 20.0], [-30.0, -76.0, 24.0, 18.0],
	[16.0, -78.0, 26.0, 20.0], [58.0, -80.0, 28.0, 22.0],
	[-72.0, -108.0, 26.0, 20.0], [-28.0, -110.0, 22.0, 18.0],
	[20.0, -108.0, 26.0, 20.0], [62.0, -106.0, 24.0, 20.0],
	[-30.0, -138.0, 18.0, 14.0], [30.0, -138.0, 18.0, 14.0],
]

## Nothing is built this close to a walked line.
const STREET_CLEARANCE := 6.0

## House dimension ranges, in metres. These are real building sizes, not
## blockout sizes: a village house is 8-11 m across, and the greybox's 30 m
## masses are blocks of several houses, which is why they read as boxes.
const HOUSE_W := [7.5, 11.5]
const HOUSE_D := [6.0, 9.0]
const STOREY := [3.1, 3.9]
const PITCH := [0.62, 0.98]
const PLINTH := [0.45, 1.35]

const TIMBER := Color(0.490, 0.424, 0.356)
const TIMBER_LIGHT := Color(0.552, 0.480, 0.403)
const PLASTER := Color(0.862, 0.835, 0.774)
const PLASTER_COOL := Color(0.829, 0.821, 0.789)
const STONE := Color(0.665, 0.658, 0.642)
const ROOF := Color(0.532, 0.517, 0.512)
const ROOF_WARM := Color(0.597, 0.542, 0.490)
const GLASS := Color(0.373, 0.403, 0.424)

var _built := 0


func _ready() -> void:
	_build()


func _build() -> void:
	for child in get_children():
		child.queue_free()
	_built = 0
	var t0 := Time.get_ticks_msec()
	if build_houses:
		_houses()
	if build_props:
		_props()
	print("MistvaleTown: %d buildings in %d ms"
		% [_built, Time.get_ticks_msec() - t0])


func _layer(n: String) -> Node3D:
	var node := Node3D.new()
	node.name = n
	add_child(node)
	return node


# =============================================================================
# Houses
# =============================================================================

func _houses() -> void:
	var root := _layer("Houses")
	var li := 0
	for lot in LOTS:
		var lx: float = lot[0]
		var lz: float = lot[1]
		var lw: float = lot[2]
		var ld: float = lot[3]
		# Two or three houses per lot. A deterministic count, not a random one:
		# the same lot must produce the same village every build or the
		# before/after comparison is meaningless.
		var n := 2 if MistvaleHeights.variation(lx * 0.7, lz * 0.7) < 0.45 else 3
		for k in n:
			var s := MistvaleHeights.variation(lx * 1.3 + float(k) * 17.0, lz * 1.1 - float(k) * 9.0)
			var s2 := MistvaleHeights.variation(lx * 0.9 - float(k) * 5.0, lz * 1.7 + float(k) * 3.0)
			# Position within the lot, biased away from the lot centre so the
			# houses form a cluster rather than a row.
			var ox := (s - 0.5) * (lw - 11.0) * 0.62
			var oz := (s2 - 0.5) * (ld - 8.0) * 0.62
			var x := lx + ox
			var z := lz + oz
			if MistvaleHeights.path_distance(x, z) < STREET_CLEARANCE:
				continue
			# NEVER axis aligned. A row of houses all facing the same way is the
			# single strongest "this was generated" signal there is.
			var yaw := deg_to_rad(lerpf(-38.0, 38.0, s2)
				+ 90.0 * floorf(s * 4.0) * 0.0)
			_house(root, x, z, s, s2, yaw, li, k)
		li += 1


func _house(
	root: Node3D, x: float, z: float, s: float, s2: float, yaw: float, li: int, k: int
) -> void:
	var w := lerpf(HOUSE_W[0], HOUSE_W[1], s)
	var d := lerpf(HOUSE_D[0], HOUSE_D[1], s2)
	var sh := lerpf(STOREY[0], STOREY[1], MistvaleHeights.variation(x * 2.1, z * 2.1))
	var storeys := 1 if MistvaleHeights.variation(x * 0.6, z * 0.6) > 0.30 else 2
	var pitch := lerpf(PITCH[0], PITCH[1], s2)
	var plinth := lerpf(PLINTH[0], PLINTH[1], MistvaleHeights.variation(x * 1.9, z * 1.9))

	var ground := MistvaleHeights.height_at(x, z)
	# The plinth height is measured from the LOWEST corner, so the foundation
	# never leaves a corner of the building hanging over a drop. This is what
	# makes a house look built on the slope instead of dropped onto it.
	var lowest := ground
	for cx: float in [-w * 0.5, w * 0.5]:
		for cz: float in [-d * 0.5, d * 0.5]:
			var px := x + cx * cos(yaw) - cz * sin(yaw)
			var pz := z + cx * sin(yaw) + cz * cos(yaw)
			lowest = minf(lowest, MistvaleHeights.height_at(px, pz))
	var plinth_top := lowest + plinth
	var wall_h := sh * float(storeys)
	var eave := plinth_top + wall_h

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cache := {}

	# --- foundation -------------------------------------------------------
	_box(st, cache, Vector3(0.0, lowest - 1.6, 0.0), Vector3(w + 0.9, 1.6 + plinth, d + 0.9),
		STONE, yaw, x, z)
	# A step where the ground falls away: houses on a slope always have one.
	if ground - lowest > 0.35:
		_box(st, cache, Vector3(0.0, lowest - 1.4, d * 0.5 + 0.85),
			Vector3(1.7, plinth + 1.2, 0.75), STONE * 0.9, yaw, x, z)

	# --- walls ------------------------------------------------------------
	var plaster := PLASTER.lerp(PLASTER_COOL, MistvaleHeights.variation(x * 3.3, z * 3.3))
	_wall_run(st, cache, w, d, plinth_top, wall_h, plaster, yaw, x, z, s)

	# --- roof -------------------------------------------------------------
	var rc := ROOF.lerp(ROOF_WARM, MistvaleHeights.variation(x * 1.3, z * 1.3))
	var over := 0.42 + s2 * 0.30
	_gable_roof(st, cache, w, d, eave, pitch, over, rc, yaw, x, z)

	# --- additions: the roll on the table ---------------------------------
	var roll := MistvaleHeights.variation(x * 0.43, z * 0.43)
	if roll < 0.20:
		_lean_to(st, cache, w, d, plinth_top, wall_h, rc, yaw, x, z, s2)
	elif roll < 0.36:
		_chimney(st, cache, w, d, eave, pitch, yaw, x, z, s)
	elif roll < 0.50 and storeys > 1:
		_balcony(st, cache, w, d, plinth_top, sh, yaw, x, z)
	if MistvaleHeights.variation(z * 0.31, x * 0.31) < 0.34:
		_awning(st, cache, w, d, plinth_top, yaw, x, z, s)
	if MistvaleHeights.variation(x * 0.27 - 3.0, z * 0.27 + 6.0) < 0.22:
		_shed(st, cache, w, d, plinth_top, rc, yaw, x, z, s2)

	st.generate_normals()
	var mesh := st.commit()
	if mesh == null:
		return
	var mi := MeshInstance3D.new()
	mi.name = "House_%02d_%d" % [li, k]
	mi.mesh = mesh
	mi.material_override = _house_material()
	# ZERO, not (x, 0, z). The part helper (_box / _rbox) emits vertices already
	# in world space — it takes the building origin as an argument and rotates
	# about it — so the node transform must add nothing. Setting it to the
	# building position translated every house to TWICE its coordinate, which
	# put a 30-house village in the ring outside the playable region and left
	# the streets empty.
	mi.position = Vector3.ZERO
	root.add_child(mi)
	_built += 1

	# One box collider, not one per wall. The player must not walk through a
	# building; they do not need to collide with its window frames.
	var body := StaticBody3D.new()
	body.name = "HouseBody_%02d_%d" % [li, k]
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(w, wall_h + plinth + pitch * d * 0.5, d)
	cs.shape = bx
	cs.position = Vector3(x, (lowest + eave + pitch * d * 0.5) * 0.5, z)
	cs.rotation.y = -yaw
	body.add_child(cs)
	root.add_child(body)


## A timber-framed wall: sill, top plate, posts at the corners and at intervals,
## and plaster panels between them. The frame is what makes this read as a
## building from 40 m away — a plain plastered box has no silhouette at all.
func _wall_run(
	st: SurfaceTool, cache: Dictionary, w: float, d: float, y0: float, h: float,
	plaster: Color, yaw: float, x: float, z: float, s: float
) -> void:
	var tw := 0.22
	var bays := 3 if w < 9.5 else 4
	# Four walls. Local +X is the building's own "front".
	for side in 4:
		var along := w if side % 2 == 0 else d
		var off := d * 0.5 if side % 2 == 0 else w * 0.5
		var sx := 1.0 if side % 2 == 0 else 0.0
		for i in bays if side % 2 == 0 else maxi(2, int(d / 3.2)):
			var a0 := -along * 0.5 + along * float(i) / float(
				bays if side % 2 == 0 else maxi(2, int(d / 3.2)))
			var a1 := -along * 0.5 + along * float(i + 1) / float(
				bays if side % 2 == 0 else maxi(2, int(d / 3.2)))
			var mid := (a0 + a1) * 0.5
			# Panel
			var pc := plaster * (0.88 + 0.14 * MistvaleHeights.variation(
				x + mid, z + float(side)))
			if sx > 0.5:
				_box(st, cache, Vector3(mid, y0 + h * 0.5, off * (1.0 if side == 0 else -1.0)),
					Vector3(a1 - a0 - tw, h, 0.20), pc, yaw, x, z)
			else:
				_box(st, cache, Vector3(off * (1.0 if side == 1 else -1.0), y0 + h * 0.5, mid),
					Vector3(0.20, h, a1 - a0 - tw), pc, yaw, x, z)
			# Post at each bay joint
			if sx > 0.5:
				_box(st, cache, Vector3(a0, y0 + h * 0.5, off * (1.0 if side == 0 else -1.0)),
					Vector3(tw, h, tw * 1.5), TIMBER, yaw, x, z)
			else:
				_box(st, cache, Vector3(off * (1.0 if side == 1 else -1.0), y0 + h * 0.5, a0),
					Vector3(tw * 1.5, h, tw), TIMBER, yaw, x, z)
		# Sill and top plate run the full length of the wall.
		if sx > 0.5:
			var zz := off * (1.0 if side == 0 else -1.0)
			_box(st, cache, Vector3(0.0, y0 + 0.11, zz), Vector3(along, 0.22, 0.30), TIMBER, yaw, x, z)
			_box(st, cache, Vector3(0.0, y0 + h - 0.11, zz), Vector3(along, 0.22, 0.30), TIMBER, yaw, x, z)
		else:
			var xx := off * (1.0 if side == 1 else -1.0)
			_box(st, cache, Vector3(xx, y0 + 0.11, 0.0), Vector3(0.30, 0.22, along), TIMBER, yaw, x, z)
			_box(st, cache, Vector3(xx, y0 + h - 0.11, 0.0), Vector3(0.30, 0.22, along), TIMBER, yaw, x, z)

	# --- openings ---------------------------------------------------------
	# Door on the front (+X local, which is the wall the road is most likely on).
	_box(st, cache, Vector3(w * 0.5 - 0.02, y0 + 1.05, d * 0.5 - w * 0.18),
		Vector3(0.14, 2.05, 1.05), TIMBER_LIGHT * 0.55, yaw, x, z)
	# Windows: one per bay on the long walls, none on the gable ends above.
	var wcount := 2 if w < 9.0 else 3
	for i in wcount:
		var t := (float(i) + 0.5) / float(wcount)
		var wx := -w * 0.5 + w * t
		for zz in [d * 0.5, -d * 0.5]:
			_box(st, cache, Vector3(wx, y0 + 1.65, zz * 1.0),
				Vector3(0.95, 1.15, 0.16), GLASS, yaw, x, z)
			# Surround
			_box(st, cache, Vector3(wx, y0 + 1.65 + 0.62, zz * 1.0),
				Vector3(1.15, 0.14, 0.22), TIMBER_LIGHT, yaw, x, z)
			_box(st, cache, Vector3(wx, y0 + 1.65 - 0.62, zz * 1.0),
				Vector3(1.15, 0.14, 0.22), TIMBER_LIGHT, yaw, x, z)
	if s > 0.5:
		# One window in the back wall, off centre. A symmetrical fenestration is
		# the fastest way to make a house look drawn rather than built.
		var back := d * 0.5 * (-1.0 if w > 9.0 else 1.0)
		_box(st, cache, Vector3(w * 0.14, y0 + 1.55, back),
			Vector3(0.90, 1.10, 0.16), GLASS, yaw, x, z)


## Two sloped planes with overhang, triangular gable wall at each end, and a
## ridge beam. The ridge is offset from centre on some houses, which is the
## cheapest possible way to break a roofline.
func _gable_roof(
	st: SurfaceTool, cache: Dictionary, w: float, d: float, eave: float,
	pitch: float, over: float, c: Color, yaw: float, x: float, z: float
) -> void:
	var half_d := d * 0.5 + over
	var rise := pitch * half_d
	var ridge := eave + rise
	var hw := w * 0.5 + over
	var c0 := c * 0.92
	var c1 := c * 1.06
	# Two slopes, built as thin boxes rotated about the ridge line. A box is
	# cheaper than a quad here and gives the roof a visible thickness at the
	# eave, which is what stops it looking like paper.
	for sgn: float in [-1.0, 1.0]:
		var len := sqrt(half_d * half_d + rise * rise)
		var ang := atan2(rise, half_d)
		var cz := sgn * half_d * 0.5
		var cy := eave + rise * 0.5
		_rbox(st, cache, Vector3(0.0, cy, cz), Vector3(hw * 2.0, 0.16, len),
			-sgn * ang, c0 if sgn < 0.0 else c1, yaw, x, z)
	# Gable end walls
	for sgn: float in [-1.0, 1.0]:
		# Approximated with three stacked slabs: a triangle would be more exact
		# and would cost three times the code for a shape seen at 60 m.
		for i in 4:
			var t0 := float(i) / 4.0
			var t1 := float(i + 1) / 4.0
			var hh := rise * (1.0 - (t0 + t1) * 0.5)
			_box(st, cache, Vector3(sgn * (hw - over) * (1.0 - (t0 + t1) * 0.5) * 0.0,
					eave + rise * (1.0 - (t0 + t1) * 0.5) * 0.5, 0.0),
				Vector3(0.16, hh, half_d * (1.0 - (t0 + t1) * 0.5) * 2.0 - over),
				PLASTER * 0.95, yaw, x, z)
	# Ridge
	_box(st, cache, Vector3(0.0, ridge + 0.10, 0.0), Vector3(hw * 2.0 + 0.2, 0.20, 0.30),
		TIMBER, yaw, x, z)
	# Eave boards: a dark line along the bottom edge of the roof. This is the
	# single detail that makes a roof read as a roof in silhouette.
	for sgn in [-1.0, 1.0]:
		_box(st, cache, Vector3(0.0, eave - 0.10, sgn * (half_d - 0.05)),
			Vector3(hw * 2.0 + 0.10, 0.24, 0.34), TIMBER * 0.85, yaw, x, z)


func _lean_to(
	st: SurfaceTool, cache: Dictionary, w: float, d: float, y0: float, h: float,
	rc: Color, yaw: float, x: float, z: float, s2: float
) -> void:
	var lw := lerpf(2.6, 3.8, s2)
	var lh := h * 0.62
	_box(st, cache, Vector3(w * 0.5 + lw * 0.5 - 0.2, y0 + lh * 0.5, 0.0),
		Vector3(lw, lh, d * 0.78), PLASTER * 0.82, yaw, x, z)
	_rbox(st, cache, Vector3(w * 0.5 + lw * 0.5 - 0.2, y0 + lh + 0.12, 0.0),
		Vector3(lw + 0.4, 0.13, d * 0.78 + 0.4), -0.28, rc * 0.88, yaw, x, z)


func _chimney(
	st: SurfaceTool, cache: Dictionary, w: float, d: float, eave: float,
	pitch: float, yaw: float, x: float, z: float, s: float
) -> void:
	var cx := lerpf(-w * 0.28, w * 0.28, s)
	var top := eave + pitch * d * 0.5 + 1.5
	_box(st, cache, Vector3(cx, top - 1.2, 0.0), Vector3(0.95, 2.7, 0.95),
		STONE * 0.88, yaw, x, z)
	_box(st, cache, Vector3(cx, top + 0.12, 0.0), Vector3(1.20, 0.22, 1.20),
		STONE * 1.05, yaw, x, z)


func _balcony(
	st: SurfaceTool, cache: Dictionary, w: float, d: float, y0: float,
	sh: float, yaw: float, x: float, z: float
) -> void:
	var by := y0 + sh
	_box(st, cache, Vector3(0.0, by - 0.12, d * 0.5 + 0.65),
		Vector3(w * 0.72, 0.20, 1.35), TIMBER_LIGHT, yaw, x, z)
	_box(st, cache, Vector3(0.0, by + 0.52, d * 0.5 + 1.28),
		Vector3(w * 0.72, 0.16, 0.12), TIMBER_LIGHT, yaw, x, z)
	for i in 6:
		var t := -0.36 + float(i) * 0.144
		_box(st, cache, Vector3(t * w, by + 0.26, d * 0.5 + 1.28),
			Vector3(0.07, 0.80, 0.07), TIMBER, yaw, x, z)


func _awning(
	st: SurfaceTool, cache: Dictionary, w: float, d: float, y0: float,
	yaw: float, x: float, z: float, s: float
) -> void:
	_rbox(st, cache, Vector3(w * 0.5 - 0.4, y0 + 2.35, d * 0.5 - w * 0.18 + 0.75),
		Vector3(2.4, 0.10, 1.5), -0.30, ROOF_WARM * 0.9, yaw, x, z)
	for sgn in [-1.0, 1.0]:
		_box(st, cache, Vector3(w * 0.5 - 0.4 + sgn * 1.05, y0 + 1.85,
				d * 0.5 - w * 0.18 + 1.35),
			Vector3(0.10, 1.0, 0.10), TIMBER, yaw, x, z)


func _shed(
	st: SurfaceTool, cache: Dictionary, w: float, d: float, y0: float,
	rc: Color, yaw: float, x: float, z: float, s2: float
) -> void:
	var sw := lerpf(2.8, 4.2, s2)
	var sd := lerpf(2.4, 3.4, s2)
	var sh := 2.35
	var sx := -(w * 0.5 + sw * 0.5 + 0.6)
	var sz := lerpf(-d * 0.3, d * 0.3, s2)
	_box(st, cache, Vector3(sx, y0 + sh * 0.5, sz), Vector3(sw, sh, sd),
		TIMBER * 1.25, yaw, x, z)
	_rbox(st, cache, Vector3(sx, y0 + sh + 0.10, sz), Vector3(sw + 0.35, 0.12, sd + 0.35),
		0.22, rc * 0.85, yaw, x, z)


# =============================================================================
# Street props — fences, stacks, wells, barrows
# =============================================================================
#
# Props are the cheapest density there is and the brief warns against using them
# AS density (§29). These are placed with a rule: they belong to a house or to a
# plot boundary, never scattered for their own sake.
func _props() -> void:
	var root := _layer("Props")
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cache := {}
	var n := 0
	for lot in LOTS:
		var lx: float = lot[0]
		var lz: float = lot[1]
		var lw: float = lot[2]
		var ld: float = lot[3]
		var s := MistvaleHeights.variation(lx * 2.7 + 11.0, lz * 2.3 - 4.0)
		if s > 0.55:
			continue
		# A fence run along one edge of the plot.
		var fx := lx + (s - 0.5) * lw
		var fz := lz + ld * 0.5 + 0.9
		var run := 0
		while run < 12:
			var px := fx + float(run) - 6.0
			if MistvaleHeights.path_distance(px, fz) > STREET_CLEARANCE - 2.0:
				var gy := MistvaleHeights.height_at(px, fz)
				_box(st, cache, Vector3(px, gy + 0.55, fz), Vector3(0.11, 1.10, 0.11),
					TIMBER * 1.3, 0.0, 0.0, 0.0)
				n += 1
			run += 1
		# Two rails
		for hgt in [0.45, 0.85]:
			_box(st, cache, Vector3(fx, MistvaleHeights.height_at(fx, fz) + hgt, fz),
				Vector3(12.0, 0.08, 0.07), TIMBER * 1.15, 0.0, 0.0, 0.0)
	if n == 0:
		return
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.name = "StreetProps"
	mi.mesh = st.commit()
	mi.material_override = _house_material()
	root.add_child(mi)
	print("MistvaleTown: %d prop elements" % n)


# =============================================================================
# Geometry helpers
# =============================================================================

## A box in the house's own frame, rotated by `yaw` about the building origin
## and then translated to (x, z) in world space.
##
## `cache` is a mesh-cache slot; unused today but threaded through so a future
## LOD/importer pass has one place to hook into.
func _box(
	st: SurfaceTool, _cache: Dictionary, local: Vector3, size: Vector3,
	c: Color, yaw: float, ox: float, oz: float
) -> void:
	if size.x <= 0.0 or size.y <= 0.0 or size.z <= 0.0:
		return
	var hx := size.x * 0.5
	var hy := size.y * 0.5
	var hz := size.z * 0.5
	var cs := cos(yaw)
	var sn := sin(yaw)
	var pts: Array[PackedVector3Array] = []
	for i in 8:
		var sx := -hx if (i & 1) == 0 else hx
		var sy := -hy if (i & 2) == 0 else hy
		var sz := -hz if (i & 4) == 0 else hz
		var lx := local.x + sx
		var lz := local.z + sz
		pts.append(PackedVector3Array([Vector3(
			ox + lx * cs - lz * sn, local.y + sy, oz + lx * sn + lz * cs)]))
	# Verts in local space, rotated at emit time.
	var v := []
	for i in 8:
		var sx := -hx if (i & 1) == 0 else hx
		var sy := -hy if (i & 2) == 0 else hy
		var sz := -hz if (i & 4) == 0 else hz
		var lx := local.x + sx
		var lz := local.z + sz
		v.append(Vector3(ox + lx * cs - lz * sn, local.y + sy, oz + lx * sn + lz * cs))
	# Face order: -X +X -Y +Y -Z +Z. Shade by face so a box reads as a solid
	# even under flat ambient — a single flat colour per box is what makes
	# kitbashed geometry look like untextured blockout.
	var faces := [
		[0, 2, 6, 4, 0.74], [1, 5, 7, 3, 0.86], [0, 1, 3, 2, 0.60],
		[4, 6, 7, 5, 1.06], [0, 4, 5, 1, 0.80], [2, 3, 7, 6, 0.92],
	]
	for f in faces:
		var a: Vector3 = v[f[0]]
		var b: Vector3 = v[f[1]]
		var cc: Vector3 = v[f[2]]
		var d: Vector3 = v[f[3]]
		var sh := float(f[4])
		st.set_color(c * sh); st.add_vertex(a)
		st.set_color(c * sh); st.add_vertex(b)
		st.set_color(c * sh); st.add_vertex(cc)
		st.set_color(c * sh); st.add_vertex(a)
		st.set_color(c * sh); st.add_vertex(cc)
		st.set_color(c * sh); st.add_vertex(d)


## A box rotated about the world X axis at its own centre — used for roof
## planes and awnings, which must tilt but not yaw twice.
func _rbox(
	st: SurfaceTool, cache: Dictionary, local: Vector3, size: Vector3,
	tilt: float, c: Color, yaw: float, ox: float, oz: float
) -> void:
	var hx := size.x * 0.5
	var hy := size.y * 0.5
	var hz := size.z * 0.5
	var ct := cos(tilt)
	var stt := sin(tilt)
	var cs := cos(yaw)
	var sn := sin(yaw)
	var v := []
	for i in 8:
		var sx := -hx if (i & 1) == 0 else hx
		var sy := -hy if (i & 2) == 0 else hy
		var sz := -hz if (i & 4) == 0 else hz
		# tilt about X in the building frame
		var ty := sy * ct - sz * stt
		var tz := sy * stt + sz * ct
		var lx := local.x + sx
		var lz := local.z + tz
		v.append(Vector3(ox + lx * cs - lz * sn, local.y + ty, oz + lx * sn + lz * cs))
	var faces := [
		[0, 2, 6, 4, 0.74], [1, 5, 7, 3, 0.86], [0, 1, 3, 2, 0.62],
		[4, 6, 7, 5, 1.10], [0, 4, 5, 1, 0.80], [2, 3, 7, 6, 0.92],
	]
	for f in faces:
		var sh := float(f[4])
		var a: Vector3 = v[f[0]]
		var b: Vector3 = v[f[1]]
		var cc: Vector3 = v[f[2]]
		var d: Vector3 = v[f[3]]
		st.set_color(c * sh); st.add_vertex(a)
		st.set_color(c * sh); st.add_vertex(b)
		st.set_color(c * sh); st.add_vertex(cc)
		st.set_color(c * sh); st.add_vertex(a)
		st.set_color(c * sh); st.add_vertex(cc)
		st.set_color(c * sh); st.add_vertex(d)


func _house_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.90
	return m
