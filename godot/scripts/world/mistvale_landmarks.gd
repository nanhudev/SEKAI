@tool
extends Node3D
## LEVEL ART — P1 hero landmarks: the Bell Tower, the Guild Hall, the North Gate.
##
## NO class_name HERE, ON PURPOSE: this working tree has several parallel
## sessions importing at once, and adding a class_name means rewriting
## .godot/global_script_class_cache.cfg, which is the file they conflict on. The
## scene references this script by path, so nothing needs the registry entry.
##
## WHY THESE THREE AND NOT ALL SIX: the masterplan's landmark table (§5) lists
## five plus the sky ring, but only three of them are architecture the player
## walks up to in the vertical slice — Bell Tower (A), Guild Terrace (B), North
## Gate (C). The Ridge Scar (D) and the Beacon (E) are on the mountain side of
## the slice and stay greybox for now; the Sky Ring is a post-process problem.
##
## WHAT THIS REPLACES: the greybox `Landmarks` layer, which is six yellow boxes.
## A yellow box at the right coordinate proves the SPACE is right and tells the
## player nothing about the place. The whole point of a landmark, per §5, is
## that the player can rebuild their position from it when lost — and a box that
## looks identical to five other boxes cannot do that. Each of these three now
## has a silhouette that survives being reduced to a shape against the sky:
##
##   Bell Tower  a round plinth under a battered square shaft under a spire,
##               with four corner pinnacles. Designed to be identifiable in mist.
##   Guild Hall  a long hall with its gable END to the market, a columned porch,
##               a stepped approach, and a small bell-cote on the ridge.
##   North Gate  a gatehouse with a genuine arched OPENING — two side walls, a
##               lintel block and voussoirs, so the north mountain is framed
##               through the hole, which is what "framing the exit" means.
##
## STILL PROCEDURAL, STILL BLOCKOUT-GRADE: this is the same technique as
## mistvale_town.gd — a kit assembled in code. It is a VISUAL CANDIDATE, not the
## P1 hero asset; the Chat2Blender line (docs/ART_KIT_PLAN.md ENV-02) owns the
## real Guild set. What this buys is a vertical slice that can be reviewed for
## composition NOW, instead of staring at yellow boxes until Blender catches up.
##
## EVERY GROUND HEIGHT COMES FROM MistvaleHeights, never from the masterplan's
## authored Y — the field is the truth and the tables are intent.
##
## CALLING CONVENTION, AND IT IS A TRAP: KitForms.box / rbox / rzbox / frustum /
## gable take `local` in WORLD coordinates and `(ox, oz)` as the point the part
## YAWS AROUND — always the building's own origin here. `local` is not added to
## `(ox, oz)`; only the offset from the origin is rotated.
##
## Two wrong versions of this shipped for an hour each, and both were caught by
## measuring the world bounds rather than by looking at a picture
## (tools/probe_aabb.gd):
##   1. passing world coordinates in `local` AND the origin in `(ox, oz)` as if
##      they were summed — put the North Gate at z=-270 instead of -135;
##   2. passing 0 for `(ox, oz)`, which is harmless while yaw = 0 and wrong the
##      moment it is not: the arch's voussoirs yaw by their own angle, so they
##      rotated the gate's z of -135 about the world origin and threw it into x,
##      stretching the bounding box to 157 x 280 m.
## Same failure mode as the town kit's `mi.position = Vector3.ZERO` fix. Check a
## new kit's world bounds before looking at a picture of it.

const KitForms = preload("res://scripts/world/kit_forms.gd")

## ============================================================================
## MISTVALE PALETTE — the hero landmarks' half of it.
## ============================================================================
##
## Kept in step with mistvale_town.gd by hand, because a shared palette file
## would need a `class_name` and the class registry is contended by the parallel
## sessions (see the kit_forms note above). If you change a colour here, change
## its twin there — the whole point of §22 is that the guild hall and the house
## next to it are built from the same materials.
##
## The one deliberate difference is that the landmarks run a stop LIGHTER on
## stone: they are civic, quarried and dressed, where the town is rubble and
## daub. They are not a different palette; they are the same palette at the
## public end of it.
const STONE := Color(0.600, 0.588, 0.556)
const STONE_DARK := Color(0.404, 0.398, 0.386)
const STONE_LIGHT := Color(0.664, 0.650, 0.612)
const ROOF_SLATE := Color(0.272, 0.314, 0.330)
const ROOF_TILE := Color(0.428, 0.330, 0.268)
const TIMBER := Color(0.430, 0.352, 0.268)
const DARK := Color(0.125, 0.137, 0.157)
const GLASS := Color(0.298, 0.345, 0.382)

var _built := 0


func _ready() -> void:
	_build()


func _build() -> void:
	for c in get_children():
		c.queue_free()
	_bell_tower(_layer("BellTower"))
	_guild_hall(_layer("GuildHall"))
	_north_gate(_layer("NorthGate"))
	print("MistvaleLandmarks: %d hero landmarks" % _built)


func _layer(n: String) -> Node3D:
	var node := Node3D.new()
	node.name = n
	add_child(node)
	return node


## Commit one mesh.
##
## `cast` is FALSE for every part that is founded below the ground: the terrain
## does not cast (mistvale_terrain.gd turns it off to kill heightfield self-shadow
## moire), so in the shadow map a plinth that buries 6 m into a slope is a 6 m
## tall wall standing in mid-air, and it throws a shadow onto ground that in the
## real scene is uphill of it. Measured on the walk rig: the guild plinth alone
## took a street 37 m away from luminance 32 to 21. Above-ground parts still cast
## normally — a tower's shadow across the town is wanted.
func _commit(parent: Node3D, name_: String, st: SurfaceTool, cast: bool = true) -> void:
	# generate_normals, never set_normal: see the header of kit_forms.gd for the
	# winding-vs-Basis trap that cost a debugging round.
	st.generate_normals()
	var mesh := st.commit()
	if mesh == null or mesh.get_surface_count() == 0:
		push_error("MistvaleLandmarks: empty mesh for " + name_)
		return
	var mi := MeshInstance3D.new()
	mi.name = name_
	mi.mesh = mesh
	mi.cast_shadow = (GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.93
	m.specular = 0.16
	mi.material_override = m
	parent.add_child(mi)
	_built += 1


func _st() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st


## The LOWEST ground inside a footprint, not the ground at its centre.
##
## WHY THIS IS NOT height_at(cx, cz): measured with tools/probe_ground.gd, the
## upper town and the guild terrace are continuous slopes — 10 to 15 m of fall
## inside a 15 m radius, 9 to 26 deg. There is no flat pad anywhere on them. A
## building stood on its centre height therefore floats on the downhill side by
## about half that range, which reads instantly as an asset dropped onto the map.
## Sizing the plinth from the lowest point is what makes the mass sit IN the hill.
func _low(cx: float, cz: float, hw: float, hd: float) -> float:
	var lo := 1e9
	var n := 5
	for i in n:
		var fx := cx + lerpf(-hw, hw, float(i) / float(n - 1))
		for j in n:
			var fz := cz + lerpf(-hd, hd, float(j) / float(n - 1))
			lo = minf(lo, MistvaleHeights.height_at(fx, fz))
	return lo


# =============================================================================
# A · Bell Tower — masterplan §5: "in mist, the silhouette alone still navigates"
# =============================================================================
#
# Authoring note: the masterplan puts the plinth at Y=72 and the top at 112, but
# the field's real surface at (-40,-95) is what gets used. The 40 m of shaft is
# the design intent and is kept; the datum is the ground.
func _bell_tower(parent: Node3D) -> void:
	# Moved east of the masterplan's (-40,-95). That coordinate is a WAYPOINT OF
	# THE WALKED SPINE, and an 18 m plinth centred on it swallows the road it
	# stands beside. (-26,-95) is 14 m off the line — enough for the plinth edge
	# to clear the carriageway — and clear of the Upper Town lots, which is what
	# the ground probe was run to check before moving it.
	var x := -26.0
	var z := -95.0
	var g := MistvaleHeights.height_at(x, z)
	var low := _low(x, z, 9.8, 9.8)

	# --- plinth: two round steps, its own mesh and NOT casting (see _commit) ---
	var sp := _st()
	KitForms.cyl(sp, Vector3(x, low - 0.6, z), 9.8, 9.8, (g + 0.8) - low + 0.6, 20, STONE_DARK)
	KitForms.cyl(sp, Vector3(x, g + 0.8, z), 8.8, 8.6, 1.6, 20, STONE)
	_commit(parent, "BellTower_Plinth", sp, false)

	var st := _st()

	# --- shaft: battered, which is the whole reason frustum exists ---
	var shaft_y := g + 2.4
	KitForms.frustum(st, Vector3(x, shaft_y, z),
		Vector2(4.0, 4.0), Vector2(3.2, 3.2), 21.5, STONE_LIGHT, 0.0, x, z)
	# corner buttresses, dark, so the shaft reads as four planes not one prism
	for i in 4:
		var sx := -1.0 if (i & 1) == 0 else 1.0
		var sz := -1.0 if (i & 2) == 0 else 1.0
		KitForms.box(st, Vector3(x + sx * 3.55, shaft_y + 10.75, z + sz * 3.55),
			Vector3(1.5, 21.5, 1.5), STONE_DARK, 0.0, x, z)
	# three string courses — without them a 21 m shaft is one flat colour
	for k in 3:
		var sy := shaft_y + 5.0 + k * 6.0
		KitForms.box(st, Vector3(x, sy, z), Vector3(8.6, 0.42, 8.6), STONE_DARK, 0.0, x, z)

	# --- belfry: wider stage, dark openings on four faces ---
	var bel_y := shaft_y + 21.5
	KitForms.frustum(st, Vector3(x, bel_y, z),
		Vector2(3.5, 3.5), Vector2(3.3, 3.3), 6.5, STONE, 0.0, x, z)
	for i in 4:
		var sx := -1.0 if (i & 1) == 0 else 1.0
		var sz := -1.0 if (i & 2) == 0 else 1.0
		# one tall louvred opening per face
		KitForms.box(st, Vector3(x + sx * 3.55, bel_y + 3.3, z + sz * 3.55),
			Vector3(3.4, 4.0, 3.4), DARK, 0.0, x, z)

	# --- cornice + corner pinnacles ---
	var cor_y := bel_y + 6.5
	KitForms.frustum(st, Vector3(x, cor_y, z),
		Vector2(4.4, 4.4), Vector2(4.0, 4.0), 1.1, STONE_DARK, 0.0, x, z)
	for i in 4:
		var sx := -1.0 if (i & 1) == 0 else 1.0
		var sz := -1.0 if (i & 2) == 0 else 1.0
		KitForms.cyl(st, Vector3(x + sx * 3.7, cor_y + 1.1, z + sz * 3.7),
			1.15, 1.0, 3.0, 8, STONE_LIGHT)
		KitForms.cone(st, Vector3(x + sx * 3.7, cor_y + 4.1, z + sz * 3.7),
			1.05, 2.6, 8, ROOF_SLATE)

	# --- spire + finial ---
	var spire_y := cor_y + 1.1
	KitForms.cone(st, Vector3(x, spire_y, z), 3.6, 8.5, 8, ROOF_SLATE)
	KitForms.cyl(st, Vector3(x, spire_y + 8.5, z), 0.34, 0.22, 2.8, 6, STONE_LIGHT)

	_commit(parent, "BellTower_Shaft", st)


# =============================================================================
# B · Guild Hall — masterplan §4 Z-06: the civic terrace, 80x60, "reads as the
# visual centre from the market". So its gable end faces the market (+Z).
# =============================================================================
func _guild_hall(parent: Node3D) -> void:
	# Beside the spine, not on it: the masterplan's (0,-45) is a point ON the
	# walked road, and sweeping a 26x15 hall across it puts a wall through the
	# main street. (12,-58) keeps the gable end toward the market while standing
	# clear of the carriageway, which at z=-58 runs at x=-6.5.
	var cx := 12.0
	var cz := -58.0
	var g := MistvaleHeights.height_at(cx, cz)
	var wall_y := g + 2.4
	var low := _low(cx, cz, 17.0, 11.5)

	# --- podium: from the lowest point of the footprint up to the floor level,
	# in its own mesh and NOT casting — the part below grade would shadow ground
	# that is uphill of it (see _commit) ---
	var sp := _st()
	KitForms.box(sp, Vector3(cx, (low - 0.6 + wall_y) * 0.5, cz),
		Vector3(34.0, wall_y - low + 0.6, 23.0), STONE_DARK, 0.0, cx, cz)
	_commit(parent, "GuildHall_Podium", sp, false)

	var st := _st()
	# --- hall body ---
	var wall_h := 11.0
	KitForms.box(st, Vector3(cx, wall_y + wall_h * 0.5, cz),
		Vector3(26.0, wall_h, 15.0), STONE, 0.0, cx, cz)
	# pilasters along both long walls — a 26 m blank wall is the giveaway that
	# something is blockout
	for k in 5:
		var px := -10.0 + k * 5.0
		for sz: float in [-1.0, 1.0]:
			KitForms.box(st, Vector3(cx + px, wall_y + wall_h * 0.5, cz + sz * 7.6),
				Vector3(1.1, wall_h, 0.9), STONE_DARK, 0.0, cx, cz)

	# --- gable ends + roof planes ---
	var eave_y := wall_y + wall_h
	var half_w := 13.4
	var rise := 6.2
	var z_half := 7.6
	KitForms.gable(st, Vector3(cx, eave_y, cz + z_half), half_w, rise, 0.9, STONE, 0.0, cx, cz)
	KitForms.gable(st, Vector3(cx, eave_y, cz - z_half), half_w, rise, 0.9, STONE, 0.0, cx, cz)
	var slope := atan2(rise, half_w)
	var plane_len := sqrt(half_w * half_w + rise * rise)
	var roof_z := 17.4
	for sx: float in [-1.0, 1.0]:
		KitForms.rzbox(st, Vector3(cx + sx * half_w * 0.5, eave_y + rise * 0.5, cz),
			Vector3(plane_len, 0.55, roof_z), sx * slope, ROOF_TILE, 0.0, cx, cz)
	# ridge beam
	KitForms.box(st, Vector3(cx, eave_y + rise + 0.32, cz),
		Vector3(0.7, 0.6, roof_z), STONE_DARK, 0.0, cx, cz)

	# --- bell-cote on the ridge: the small vertical that says "guild" ---
	KitForms.box(st, Vector3(cx, eave_y + rise + 2.0, cz - 5.6),
		Vector3(3.6, 3.4, 3.6), STONE, 0.0, cx, cz)
	KitForms.box(st, Vector3(cx, eave_y + rise + 2.4, cz - 5.6),
		Vector3(2.2, 2.2, 3.9), DARK, 0.0, cx, cz)
	KitForms.cone(st, Vector3(cx, eave_y + rise + 3.7, cz - 5.6), 2.8, 3.6, 4, ROOF_SLATE)

	# --- porch: columns + a lintel, on the market side ---
	var porch_z := cz + z_half + 2.6
	for k in 4:
		var px2 := -9.0 + k * 6.0
		KitForms.box(st, Vector3(cx + px2, wall_y + 4.4, porch_z),
			Vector3(1.3, 8.8, 1.3), STONE_LIGHT, 0.0, cx, cz)
	KitForms.box(st, Vector3(cx, wall_y + 9.2, porch_z), Vector3(21.0, 1.0, 3.6), STONE_DARK, 0.0, cx, cz)
	KitForms.rzbox(st, Vector3(cx - 10.5, wall_y + 9.9, porch_z), Vector3(3.4, 0.4, 3.6), -0.30, ROOF_TILE, 0.0, cx, cz)
	KitForms.rzbox(st, Vector3(cx + 10.5, wall_y + 9.9, porch_z), Vector3(3.4, 0.4, 3.6), 0.30, ROOF_TILE, 0.0, cx, cz)

	# --- door and windows on the market face ---
	KitForms.box(st, Vector3(cx, wall_y + 3.2, cz + z_half + 0.05),
		Vector3(5.2, 6.4, 0.5), TIMBER, 0.0, cx, cz)
	for k in 2:
		var px3 := -4.6 if k == 0 else 4.6
		for row in 2:
			KitForms.box(st, Vector3(cx + px3, wall_y + 5.2 + row * 3.6, cz + z_half + 0.05),
				Vector3(2.4, 2.6, 0.5), GLASS, 0.0, cx, cz)
	# side windows
	for k in 5:
		var px4 := -10.0 + k * 5.0
		for sz2: float in [-1.0, 1.0]:
			KitForms.box(st, Vector3(cx + px4, wall_y + 6.6, cz + sz2 * 7.65),
				Vector3(2.0, 3.0, 0.5), GLASS, 0.0, cx, cz)

	# --- the stepped approach, meeting C05_GuildStair at (0,-30) ---
	for i in 4:
		var fy := g + 2.4 - float(i) * 0.62
		var fz := cz + z_half + 3.4 + float(i) * 1.1
		KitForms.box(st, Vector3(cx, fy - 0.31, fz),
			Vector3(15.0 - float(i) * 1.6, 0.62, 1.2), STONE_DARK, 0.0, cx, cz)

	_commit(parent, "GuildHall", st)


# =============================================================================
# C · North Gate — masterplan §4 Z-08: "frames the north mountain", 60x30
# =============================================================================
#
# The one requirement that dictates the build: the opening must be a HOLE. Two
# side walls, a lintel block spanning them, and voussoirs above — no box in the
# middle, or the mountain is not framed, it is papered over.
func _north_gate(parent: Node3D) -> void:
	var cx := 0.0
	var cz := -135.0
	var g := MistvaleHeights.height_at(cx, cz)
	# The gate straddles the road, and the road keeps its own ground: the walls
	# are founded from the lowest point under them, while the OPENING is left with
	# nothing but terrain in it. That is the difference between a gate and a wall
	# with a doorway painted on it.
	var low := _low(cx, cz, 9.0, 4.5)

	# clear opening: 6 m wide, 6.2 m to the springing line
	var half_open := 3.0
	var spring := 6.2
	var depth := 8.0
	var body_h := 15.0

	# --- founded parts: their own mesh, and NOT casting — see _commit. These are
	# the pieces taken down to the lowest ground, so their below-grade volume
	# would otherwise shadow ground laid uphill of them.
	var sa := _st()
	var side_w := 4.0
	var wall_top := g + body_h
	for sx: float in [-1.0, 1.0]:
		KitForms.box(sa, Vector3(cx + sx * (half_open + side_w * 0.5), (low - 0.5 + wall_top) * 0.5, cz),
			Vector3(side_w, wall_top - low + 0.5, depth), STONE, 0.0, cx, cz)
	for sx2: float in [-1.0, 1.0]:
		KitForms.box(sa, Vector3(cx + sx2 * (half_open + 0.75), (low - 0.5 + g + spring) * 0.5, cz),
			Vector3(1.5, g + spring - low + 0.5, depth + 0.7), STONE_DARK, 0.0, cx, cz)
	var tower_top := g + 18.0
	for sx3: float in [-1.0, 1.0]:
		var tx := cx + sx3 * 10.6
		KitForms.frustum(sa, Vector3(tx, low - 0.6, cz),
			Vector2(4.6, 4.6), Vector2(4.2, 4.2), tower_top - low + 0.6, STONE, 0.0, cx, cz)
	_commit(parent, "NorthGate_Founding", sa, false)

	# --- above grade: the gate itself, and this part casts ---
	var st := _st()
	KitForms.box(st, Vector3(cx, g + spring + (body_h - spring) * 0.5, cz),
		Vector3(half_open * 2.0, body_h - spring, depth), STONE, 0.0, cx, cz)
	for sz: float in [-1.0, 1.0]:
		KitForms.arch(st, Vector3(cx, g, cz + sz * (depth * 0.5 + 0.3)),
			1.0, spring, 1.4, depth * 0.5 + 0.7, STONE_DARK, 0.0, cx, cz)
	var cap_y := g + body_h
	KitForms.box(st, Vector3(cx, cap_y + 0.6, cz), Vector3(17.5, 1.2, depth + 2.4), STONE_DARK, 0.0, cx, cz)
	for k in 5:
		var mx := -6.4 + k * 3.2
		KitForms.box(st, Vector3(cx + mx, cap_y + 2.1, cz),
			Vector3(1.8, 1.8, depth + 2.4), STONE, 0.0, cx, cz)
	for sx4: float in [-1.0, 1.0]:
		var tx2 := cx + sx4 * 10.6
		for k2 in 2:
			KitForms.box(st, Vector3(tx2 + sx4 * 4.2, g + 7.0 + float(k2) * 4.0, cz),
				Vector3(0.6, 2.4, 1.2), DARK, 0.0, cx, cz)
			KitForms.box(st, Vector3(tx2, g + 7.0 + float(k2) * 4.0, cz + 4.2),
				Vector3(1.2, 2.4, 0.6), DARK, 0.0, cx, cz)
		KitForms.box(st, Vector3(tx2, tower_top + 0.55, cz), Vector3(10.4, 1.1, 10.4), STONE_DARK, 0.0, cx, cz)
		KitForms.cone(st, Vector3(tx2, tower_top + 1.1, cz), 4.9, 6.4, 8, ROOF_SLATE)
	_commit(parent, "NorthGate", st)

	_commit(parent, "NorthGate", st)
