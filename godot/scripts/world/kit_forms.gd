extends RefCounted
##
## Shared procedural primitives for the Mistvale environment kits.
##
## DELIBERATELY NOT A class_name. Registering one requires a rewrite of
## .godot/global_script_class_cache.cfg, and this working tree has several
## parallel sessions importing at the same time — that file is exactly the one
## they fight over. Callers preload the script and use its statics:
##     const KitForms = preload("res://scripts/world/kit_forms.gd")
## which GDScript resolves on the script resource and needs no registry entry.
##
## WHY THIS EXISTS: mistvale_town.gd grew its own private _box / _rbox pair, and
## the landmark kit needs the same primitives plus a few the houses never needed
## — a battered tower shaft, a round plinth, a cone, a gable wall. Adding those
## as a fourth copy of the same twenty lines is how three kits end up with three
## different face-shading tables and the map reads as three different games.
##
## NORMALS ARE GENERATED, NOT WRITTEN. Every primitive here emits each face with
## its own vertices and no normals, and the caller calls SurfaceTool.
## generate_normals() before commit() — the same discipline mistvale_town.gd and
## mistvale_land.gd already use. Writing normals by hand was the first attempt
## and it is a trap: this kit rotates vertices with the 2D convention
## (x*cos - z*sin, x*sin + z*cos) while Godot's Basis rotates the other way in z,
## so a hand-written normal derived from Vector3.rotated(UP, yaw) disagrees with
## the winding it belongs to and the face lights from behind. Measured on the
## town meshes: generate_normals() produces correct, non-zero normals (see
## tools/probe_mesh_normals.gd). Do not "optimise" this into set_normal().
##
## All vertices are emitted in WORLD space. `local` is where a part sits
## relative to the building's own origin and (ox, oz) is that origin in the
## world, so a 40 m tower stays editable in its own build function.

# =============================================================================
# Triangles / quads
# =============================================================================

static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, col: Color) -> void:
	for v: Vector3 in [a, b, c]:
		st.set_color(col)
		st.add_vertex(v)


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		col: Color) -> void:
	for v: Vector3 in [a, b, c, a, c, d]:
		st.set_color(col)
		st.add_vertex(v)


# =============================================================================
# Boxes
# =============================================================================

## An axis-aligned box, yawed about `(ox, oz)`.
##
## THE ROTATION IS AROUND (ox, oz), NOT AROUND THE WORLD ORIGIN. Callers pass
## world coordinates in `local` and the building's own origin in (ox, oz); the
## offset from that origin is what turns. Getting this wrong is not a small
## error — the first version rotated `local` about the world origin, and the
## North Gate's voussoirs (which yaw by their own angle) threw the gate's z of
## -135 into x, stretching its bounding box to 157 m wide. Measure a new kit's
## world bounds before looking at a picture of it.
static func box(
	st: SurfaceTool, local: Vector3, size: Vector3, col: Color,
	yaw: float, ox: float, oz: float
) -> void:
	if size.x <= 0.0 or size.y <= 0.0 or size.z <= 0.0:
		return
	var hx := size.x * 0.5
	var hy := size.y * 0.5
	var hz := size.z * 0.5
	var cs := cos(yaw)
	var sn := sin(yaw)
	var v: Array[Vector3] = []
	for i in 8:
		var sx := -hx if (i & 1) == 0 else hx
		var sy := -hy if (i & 2) == 0 else hy
		var sz := -hz if (i & 4) == 0 else hz
		var dx := local.x + sx - ox
		var dz := local.z + sz - oz
		v.append(Vector3(ox + dx * cs - dz * sn, local.y + sy, oz + dx * sn + dz * cs))
	# Face order copied from mistvale_town.gd. The winding is not derivable by
	# eye and it is already proven to render outward-facing on the houses, so it
	# is reused rather than re-derived.
	var faces := [
		[0, 2, 6, 4], [1, 5, 7, 3], [0, 1, 3, 2],
		[4, 6, 7, 5], [0, 4, 5, 1], [2, 3, 7, 6],
	]
	for f in faces:
		_quad(st, v[f[0]], v[f[1]], v[f[2]], v[f[3]], col)


## A box tilted about the world X axis at its own centre — roof planes, awnings,
## anything that has to lean without being yawed twice.
static func rbox(
	st: SurfaceTool, local: Vector3, size: Vector3, tilt: float, col: Color,
	yaw: float, ox: float, oz: float
) -> void:
	if size.x <= 0.0 or size.y <= 0.0 or size.z <= 0.0:
		return
	var hx := size.x * 0.5
	var hy := size.y * 0.5
	var hz := size.z * 0.5
	var ct := cos(tilt)
	var stt := sin(tilt)
	var cs := cos(yaw)
	var sn := sin(yaw)
	var v: Array[Vector3] = []
	for i in 8:
		var sx := -hx if (i & 1) == 0 else hx
		var sy := -hy if (i & 2) == 0 else hy
		var sz := -hz if (i & 4) == 0 else hz
		var ty := sy * ct - sz * stt
		var tz := sy * stt + sz * ct
		var dx := local.x + sx - ox
		var dz := local.z + tz - oz
		v.append(Vector3(ox + dx * cs - dz * sn, local.y + ty, oz + dx * sn + dz * cs))
	var faces := [
		[0, 2, 6, 4], [1, 5, 7, 3], [0, 1, 3, 2],
		[4, 6, 7, 5], [0, 4, 5, 1], [2, 3, 7, 6],
	]
	for f in faces:
		_quad(st, v[f[0]], v[f[1]], v[f[2]], v[f[3]], col)


## A box tilted about the world Z axis at its own centre. The mirror of rbox,
## and it exists because a roof ridge running along Z needs its planes to fall
## toward X — which rbox, tilting about X, physically cannot express.
static func rzbox(
	st: SurfaceTool, local: Vector3, size: Vector3, tilt: float, col: Color,
	yaw: float, ox: float, oz: float
) -> void:
	if size.x <= 0.0 or size.y <= 0.0 or size.z <= 0.0:
		return
	var hx := size.x * 0.5
	var hy := size.y * 0.5
	var hz := size.z * 0.5
	var ct := cos(tilt)
	var stt := sin(tilt)
	var cs := cos(yaw)
	var sn := sin(yaw)
	var v: Array[Vector3] = []
	for i in 8:
		var sx := -hx if (i & 1) == 0 else hx
		var sy := -hy if (i & 2) == 0 else hy
		var sz := -hz if (i & 4) == 0 else hz
		var tx := sx * ct - sy * stt
		var ty := sx * stt + sy * ct
		var dx := local.x + tx - ox
		var dz := local.z + sz - oz
		v.append(Vector3(ox + dx * cs - dz * sn, local.y + ty, oz + dx * sn + dz * cs))
	var faces := [
		[0, 2, 6, 4], [1, 5, 7, 3], [0, 1, 3, 2],
		[4, 6, 7, 5], [0, 4, 5, 1], [2, 3, 7, 6],
	]
	for f in faces:
		_quad(st, v[f[0]], v[f[1]], v[f[2]], v[f[3]], col)


# =============================================================================
# Battered forms — a tower shaft tapers, and a stack of shrinking boxes shows
# the steps. One primitive with real sloped walls does not.
# =============================================================================
## A square frustum: half-widths differ between the bottom and the top face.
## `half_bottom.x` / `.y` are the X and Z half-extents.
static func frustum(
	st: SurfaceTool, local: Vector3, half_bottom: Vector2, half_top: Vector2,
	height: float, col: Color, yaw: float, ox: float, oz: float
) -> void:
	if height <= 0.0 or half_bottom.x <= 0.0 or half_bottom.y <= 0.0:
		return
	var cs := cos(yaw)
	var sn := sin(yaw)
	var y0 := local.y
	var y1 := local.y + height
	var vb: Array[Vector3] = []
	var vt: Array[Vector3] = []
	# index bit0 = X sign, bit1 = Z sign, matching the box's own corner coding
	for i in 4:
		var sx := -1.0 if (i & 1) == 0 else 1.0
		var sz := -1.0 if (i & 2) == 0 else 1.0
		var lbx := local.x + sx * half_bottom.x
		var lbz := local.z + sz * half_bottom.y
		var ltx := local.x + sx * half_top.x
		var ltz := local.z + sz * half_top.y
		vb.append(Vector3(
			ox + (lbx - ox) * cs - (lbz - oz) * sn, y0,
			oz + (lbx - ox) * sn + (lbz - oz) * cs))
		vt.append(Vector3(
			ox + (ltx - ox) * cs - (ltz - oz) * sn, y1,
			oz + (ltx - ox) * sn + (ltz - oz) * cs))
	# Winding follows the box table's corner order, side by side.
	_quad(st, vb[0], vt[0], vt[1], vb[1], col)   # -Z
	_quad(st, vb[2], vb[3], vt[3], vt[2], col)   # +Z
	_quad(st, vb[0], vb[2], vt[2], vt[0], col)   # -X
	_quad(st, vb[1], vt[1], vt[3], vb[3], col)   # +X
	_quad(st, vt[0], vt[2], vt[3], vt[1], col)   # top


# =============================================================================
# Round forms — the bell tower has to read as a silhouette from 400 m, and a
# square shaft does not.
# =============================================================================
## A cylinder standing at `base`, tapering from radius_bottom to radius_top.
static func cyl(
	st: SurfaceTool, base: Vector3, radius_bottom: float, radius_top: float,
	height: float, segs: int, col: Color, cap: bool = true
) -> void:
	var seg := maxi(3, segs)
	for i in seg:
		var a0 := TAU * float(i) / float(seg)
		var a1 := TAU * float(i + 1) / float(seg)
		var c0 := cos(a0)
		var s0 := sin(a0)
		var c1 := cos(a1)
		var s1 := sin(a1)
		var b0 := Vector3(base.x + c0 * radius_bottom, base.y, base.z + s0 * radius_bottom)
		var b1 := Vector3(base.x + c1 * radius_bottom, base.y, base.z + s1 * radius_bottom)
		var t0 := Vector3(base.x + c0 * radius_top, base.y + height, base.z + s0 * radius_top)
		var t1 := Vector3(base.x + c1 * radius_top, base.y + height, base.z + s1 * radius_top)
		_tri(st, b0, t0, t1, col)
		_tri(st, b0, t1, b1, col)
		if cap:
			_tri(st, t0, t1, Vector3(base.x, base.y + height, base.z), col)


## A cone — spires, finials, the tower's roof.
static func cone(
	st: SurfaceTool, base: Vector3, radius: float, height: float,
	segs: int, col: Color
) -> void:
	var seg := maxi(3, segs)
	var apex := Vector3(base.x, base.y + height, base.z)
	for i in seg:
		var a0 := TAU * float(i) / float(seg)
		var a1 := TAU * float(i + 1) / float(seg)
		var p0 := Vector3(base.x + cos(a0) * radius, base.y, base.z + sin(a0) * radius)
		var p1 := Vector3(base.x + cos(a1) * radius, base.y, base.z + sin(a1) * radius)
		_tri(st, p0, apex, p1, col)


# =============================================================================
# Walls and openings
# =============================================================================

## A gable: the triangular wall under a pitched roof. Centre is the middle of the
## base; apex stands `rise` above it; thickness is along the wall normal.
static func gable(
	st: SurfaceTool, centre: Vector3, half_w: float, rise: float, thickness: float,
	col: Color, yaw: float, ox: float, oz: float
) -> void:
	var cs := cos(yaw)
	var sn := sin(yaw)
	var hz := thickness * 0.5
	var pts: Array[Vector3] = []
	for side: float in [-1.0, 1.0]:
		var zz := side * hz
		var prof := [Vector2(-half_w, 0.0), Vector2(half_w, 0.0), Vector2(0.0, rise)]
		for p: Vector2 in prof:
			var dx := centre.x + p.x - ox
			var dz := centre.z + zz - oz
			pts.append(Vector3(ox + dx * cs - dz * sn, centre.y + p.y, oz + dx * sn + dz * cs))
	# front (-Z side), back (+Z side), the sloped cheeks, and the underside
	_tri(st, pts[0], pts[1], pts[2], col)
	_tri(st, pts[5], pts[4], pts[3], col)
	_quad(st, pts[1], pts[4], pts[5], pts[2], col)
	_quad(st, pts[0], pts[2], pts[5], pts[3], col)
	_quad(st, pts[0], pts[3], pts[4], pts[1], col)


## An arched opening built as voussoirs. A SurfaceTool cannot boolean a hole, and
## a flat dark rectangle reads as a painted-on door; a ring of blocks reads as a
## gate. `half_w` is the clear half-width of the opening, `spring` the height of
## the springing line, measured from `base`.
static func arch(
	st: SurfaceTool, base: Vector3, half_w: float, spring: float, thickness: float,
	depth: float, col: Color, yaw: float, ox: float, oz: float
) -> void:
	var seg := 7
	for i in seg:
		var a0 := PI * float(i) / float(seg)
		var a1 := PI * float(i + 1) / float(seg)
		var am := (a0 + a1) * 0.5
		# am = 0 at the left springing point, PI at the right, apex in between
		var px := -cos(am) * half_w
		var py := spring + sin(am) * half_w
		var w := half_w * absf(cos(a0) - cos(a1)) + 0.30
		var h := half_w * absf(sin(a1) - sin(a0)) + 0.55
		box(st, Vector3(base.x + px, base.y + py, base.z), Vector3(w, h, depth),
			col, yaw + am, ox, oz)
	# jambs, just outside the clear opening
	box(st, Vector3(base.x - half_w - thickness * 0.5, base.y + spring * 0.5, base.z),
		Vector3(thickness, spring, depth), col, yaw, ox, oz)
	box(st, Vector3(base.x + half_w + thickness * 0.5, base.y + spring * 0.5, base.z),
		Vector3(thickness, spring, depth), col, yaw, ox, oz)
