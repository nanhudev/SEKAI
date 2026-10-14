extends Node3D
#
# SEKAI VFX LAB — the one room all eleven rule-breaking prototypes are watched in.
#
# =============================================================================
# WHY THIS ROOM EXISTS RATHER THAN ELEVEN ROOMS
# =============================================================================
#
# The brief for this round is eleven separate concepts, each delivered as its own
# clip. The tempting shape is eleven scenes. It is the wrong shape, for one
# reason that shows up immediately and one that shows up late:
#
#   · The EARLY one: every concept is a claim about THE SAME WORLD. "The world is
#     pressed flat", "the world is missing a sphere", "the world folds like a
#     book" — these are only interesting if the world is recognisably the same
#     world in all eleven, or the viewer cannot tell a rule being broken from a
#     scene being different. Eleven rooms would each have their own idea of what
#     the world looks like and the set would read as eleven unrelated shots.
#
#   · The LATE one: the acceptance test for every one of them is the same
#     question — "is this legible as a rule being broken, from one still?" — and
#     that question can only be asked cheaply if there is one place to ask it.
#
# So there is ONE world, built once, and each prototype is a script that SITS ON
# IT. They do not build scenery. They do not own a camera. They take the world
# the others also get, break one rule in it, and put it back.
#
# =============================================================================
# THE WORLD IS DELIBERATELY GREYBOX, AND DELIBERATELY NOT EMPTY
# =============================================================================
#
# "灰盒也能成立" is the brief's own constraint, and it is the right one — a
# prototype that only reads because of its art is not a prototype of a rule. But
# a greybox that is three boxes on a plane cannot answer the question either,
# because a sphere-shaped absence in an empty world is just a sphere.
#
# What the world has to provide is REFERENCE: things whose size the eye already
# knows (a road, a person, a two-storey building), arranged at a range of
# distances so that a change of scale, a change of orientation, or a missing
# chunk is measurable against something. Each prop is here for a specific
# prototype:
#
#   the ROAD          gives 05 海啸 a line that tilts and 01 二相簿 a line that
#                     gets pressed flat — a straight line that stops being
#                     straight is the cheapest proof of a broken rule there is.
#   the BUILDINGS     are what 04 世界剑鞘 pulls its edges out of, what 11
#                     天地合页 has to fold, and what 06 地脉拔刀 has to carry up.
#   the HILLS         are the far depth that 02 天钉's nail has to be bigger than
#                     and 09 神罚雷's corridor has to span.
#   the TREES         hang off the crust blade in 06.
#   the TARGET        is the point every one of them is aimed at, standing on the
#                     road so its scale is fixed by the road's width.
#
# =============================================================================
# NOTHING HERE IS METALLIC AND NOTHING HERE WRITES `NORMAL`
# =============================================================================
#
# The project's standing rules, both of which this lab would have broken by
# accident: a metallic surface with no reflection source renders as a black
# silhouette, and a fragment shader in `gl_compatibility` that writes `NORMAL`
# does not do what the code reads like. Every material here is dielectric and the
# shading is carried by albedo, roughness and geometry.
#
# AND EVERY NORMAL IN THIS FILE IS COMPUTED, NOT GENERATED. `SurfaceTool.
# generate_normals()` derives them from triangle winding, so a mesh whose
# triangles came out wound the other way is lit from underneath and renders as a
# black sheet — a failure that looks like a lighting bug and is a winding bug, and
# that costs an hour to find. The terrain's normal is the analytic gradient of the
# height function that produced it, and the road's is the fall line of the same
# function. There is nothing to wind the wrong way.

const PROP_SHADER := preload("res://vfx/vfx_prop.gdshader")
const GLOW_SHADER := preload("res://vfx/vfx_glow.gdshader")
const SKY_SHADER := preload("res://vfx/vfx_sky_dome.gdshader")
const CLOUD_SHADER := preload("res://vfx/vfx_cloud.gdshader")

# -----------------------------------------------------------------------------
# THE REGISTRY. One line per prototype; one file per line.
# -----------------------------------------------------------------------------
const PROTOTYPES := {
	"01_dimensional_sheet": "res://scripts/vfx/p01_dimensional_sheet.gd",
	"02_heaven_nail": "res://scripts/vfx/p02_heaven_nail.gd",
	"03_black_sun": "res://scripts/vfx/p03_black_sun.gd",
	"04_world_scabbard": "res://scripts/vfx/p04_world_scabbard.gd",
	"05_tidal_tilt": "res://scripts/vfx/p05_tidal_tilt.gd",
	"06_continent_blade": "res://scripts/vfx/p06_continent_blade.gd",
	"07_star_pull": "res://scripts/vfx/p07_star_pull.gd",
	"08_white_world": "res://scripts/vfx/p08_white_world.gd",
	"09_divine_thunder_corridor": "res://scripts/vfx/p09_divine_thunder_corridor.gd",
	"10_chain_drag_star": "res://scripts/vfx/p10_chain_drag_star.gd",
	"11_world_hinge": "res://scripts/vfx/p11_world_hinge.gd",
}

# -----------------------------------------------------------------------------
# THE PALETTE. Kept in one place because all eleven clips have to look like the
# same world, and a colour typed into a prototype is a colour that will drift.
# -----------------------------------------------------------------------------
const C_GROUND := Color(0.235, 0.250, 0.215)
const C_ROAD := Color(0.300, 0.292, 0.272)
const C_ROAD_EDGE := Color(0.400, 0.383, 0.356)
const C_BUILDING := Color(0.415, 0.395, 0.358)
const C_BUILDING_2 := Color(0.355, 0.343, 0.318)
const C_TRIM := Color(0.300, 0.288, 0.264)
const C_DARK := Color(0.055, 0.062, 0.075)
const C_WOOD := Color(0.205, 0.168, 0.126)
const C_LEAF := Color(0.150, 0.222, 0.150)
const C_ROCK := Color(0.330, 0.322, 0.305)
const C_HILL := Color(0.300, 0.352, 0.428)
const C_STONE_LIGHT := Color(0.470, 0.455, 0.420)

# The player stands here and faces -Z down the road. Every prototype's camera
# plan starts from this because the compositions are aimed down the road.
const EYE := Vector3(0.0, 1.66, 0.0)

# The ground's two numbers. Named rather than local because `split_world` has to
# cut the terrain on exactly these grid lines — a split that lands mid-triangle
# leaves a ragged edge along the fold, and the fold's edge is the whole picture.
const TERRAIN_EXTENT := 760.0
const TERRAIN_CELLS := 76

var props: Array = []            # [{name, node, size, kind, home_pos, home_basis}]
var prop_materials: Array = []   # every WORLD ShaderMaterial, for broadcast
var groups: Dictionary = {}      # kind -> [prop dictionaries]

var world_root: Node3D           # everything greybox, so an effect can tilt it
var sky_root: Node3D
var sky_dome: MeshInstance3D
var sky_mat: ShaderMaterial
var ground: MeshInstance3D
var ground_mat: ShaderMaterial
var road: MeshInstance3D
var sun: DirectionalLight3D
var env: Environment

var target: Node3D               # the greybox body everything is aimed at
var player_proxy: Node3D         # the greybox figure, for external shots
var weapon_root: Node3D          # the first-person weapon, parented to the camera
var weapon_blade: MeshInstance3D

var fp_camera: Camera3D
var review_camera: Camera3D
var using_review := false

# The camera the prototype drives. The lab applies these every `set_time`.
var cam_eye := EYE
var cam_look := Vector3(0.0, 1.4, -20.0)
var cam_fov := 68.0
var cam_roll := 0.0

var prototype: Node3D = null
var prototype_id := ""

var review_points: Dictionary = {}

var _hold := -1.0


func _ready() -> void:
	_build_environment()
	_build_sky()
	_build_terrain()
	_build_road()
	_build_buildings()
	_build_boxes()
	_build_trees()
	_build_bridge()
	_build_rocks()
	_build_hills()
	_build_actors()
	# The cameras come before the weapon, because the weapon is parented to the
	# first-person camera. The first version of this file built them the other way
	# round and the weapon's parent was null.
	_build_cameras()
	_build_weapon()
	_apply_camera()


# =============================================================================
# THE WORLD
# =============================================================================

func _build_environment() -> void:
	var world_env := WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	env = Environment.new()
	# The dome is real geometry covering the whole sphere, so the background is
	# never seen — but it has to be a COLOUR and not BG_SKY, because BG_SKY with
	# no `Sky` resource set is a black background that shows the moment a
	# prototype hides or folds the dome.
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.145, 0.185, 0.255)
	# ONE light plus ambient. The ambient is a colour rather than the sky because
	# the sky here is geometry and not a `Sky` resource, and colour ambient is the
	# only honest way to say "the sky is lighting you" about a mesh.
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.455, 0.515, 0.600)
	env.ambient_light_energy = 0.62
	# `gl_compatibility` does not implement AGX, so FILMIC. The project rule.
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.0
	env.ssao_enabled = false
	env.glow_enabled = false
	# Aerial perspective. Without it the hills 300-500m out render at the same
	# contrast as the road and the frame has no far end — which is exactly the
	# depth 02 天钉 and 09 神罚雷 are measured against.
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = Color(0.505, 0.560, 0.640)
	env.fog_light_energy = 1.0
	env.fog_density = 0.0022
	env.fog_sky_affect = 0.0
	world_env.environment = env
	add_child(world_env)

	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	# Chosen by working backwards from the road: the player looks toward -Z, so
	# the light travels toward -Z and comes from behind the camera's right
	# shoulder. An earlier room in this project was yawed the other way and its
	# wall rendered as a black slab; that mistake is available here too.
	sun.rotation_degrees = Vector3(-44.0, -34.0, 0.0)
	sun.light_energy = 1.28
	sun.light_color = Color(1.0, 0.962, 0.905)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 120.0
	add_child(sun)


func _build_sky() -> void:
	sky_root = Node3D.new()
	sky_root.name = "SkyRoot"
	add_child(sky_root)

	sky_dome = MeshInstance3D.new()
	sky_dome.name = "SkyDome"
	var sphere := SphereMesh.new()
	sphere.radius = 1600.0
	sphere.height = 3200.0
	sphere.radial_segments = 48
	sphere.rings = 24
	sky_dome.mesh = sphere
	sky_mat = ShaderMaterial.new()
	sky_mat.shader = SKY_SHADER
	sky_dome.material_override = sky_mat
	sky_dome.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The dome is drawn before everything and never tested against depth: it is
	# the largest object in the scene and letting it write depth would make every
	# hill fight it for the same pixel.
	sky_dome.extra_cull_margin = 0.0
	sky_root.add_child(sky_dome)
	set_sky("day")


## Sky presets. Every prototype that cares about the sky calls this in `build()`,
## so a clip can never inherit another clip's night.
func set_sky(preset: String) -> void:
	sky_mat.set_shader_parameter("whiten", 0.0)
	match preset:
		"day":
			_sky(Vector3(0.185, 0.285, 0.445), Vector3(0.545, 0.565, 0.590),
				Vector3(0.155, 0.160, 0.175), 1.0)
			sky_mat.set_shader_parameter("star_amount", 0.0)
			sky_mat.set_shader_parameter("body_amount", 2.2)
			sky_mat.set_shader_parameter("body_face", 1.0)
			sky_mat.set_shader_parameter("body_radius", 0.075)
			sky_mat.set_shader_parameter("body_glow", 1.6)
			sky_mat.set_shader_parameter("body_color", Color(1.0, 0.965, 0.905))
			sky_mat.set_shader_parameter("body_direction", Vector3(0.42, 0.78, -0.46))
		"dusk":
			_sky(Vector3(0.115, 0.145, 0.250), Vector3(0.640, 0.430, 0.330),
				Vector3(0.120, 0.100, 0.105), 1.05)
			sky_mat.set_shader_parameter("star_amount", 0.12)
			sky_mat.set_shader_parameter("star_density", 46.0)
			sky_mat.set_shader_parameter("body_amount", 2.6)
			sky_mat.set_shader_parameter("body_face", 1.0)
			sky_mat.set_shader_parameter("body_radius", 0.085)
			sky_mat.set_shader_parameter("body_glow", 2.4)
			sky_mat.set_shader_parameter("body_color", Color(1.0, 0.80, 0.60))
			sky_mat.set_shader_parameter("body_direction", Vector3(-0.30, 0.14, -0.94))
		"night":
			_sky(Vector3(0.030, 0.042, 0.086), Vector3(0.100, 0.118, 0.170),
				Vector3(0.020, 0.024, 0.036), 1.0)
			sky_mat.set_shader_parameter("star_amount", 0.85)
			sky_mat.set_shader_parameter("star_density", 54.0)
			sky_mat.set_shader_parameter("body_amount", 3.0)
			sky_mat.set_shader_parameter("body_face", 1.0)
			sky_mat.set_shader_parameter("body_radius", 0.14)
			sky_mat.set_shader_parameter("body_glow", 0.30)
			sky_mat.set_shader_parameter("body_color", Color(0.90, 0.92, 0.86))
			sky_mat.set_shader_parameter("body_direction", Vector3(-0.46, 0.52, -0.72))
		"white":
			_sky(Vector3(0.900, 0.905, 0.915), Vector3(0.955, 0.955, 0.960),
				Vector3(0.780, 0.780, 0.785), 1.0)
			sky_mat.set_shader_parameter("star_amount", 0.0)
			sky_mat.set_shader_parameter("body_amount", 0.0)


func _sky(zenith: Vector3, horizon: Vector3, ground_c: Vector3, energy: float) -> void:
	sky_mat.set_shader_parameter("zenith_color", zenith)
	sky_mat.set_shader_parameter("horizon_color", horizon)
	sky_mat.set_shader_parameter("ground_color", ground_c)
	sky_mat.set_shader_parameter("energy", energy)


## The ground profile. One function, used by the terrain mesh, the road ribbon and
## every prop that has to sit on the ground — so nothing floats and nothing sinks.
func ground_height(x: float, z: float) -> float:
	var h := 0.0
	h += 1.25 * sin(x * 0.0185) * cos(z * 0.0142)
	h += 0.62 * sin(x * 0.0410 + 1.3) * sin(z * 0.0370 - 0.6)
	# A rise to the east and a fall to the west, so the horizon is not level and a
	# world that tilts (05 / 11) tilts against a horizon that already has a slope.
	h += 11.0 * smoothstep(28.0, 180.0, x)
	h -= 7.0 * smoothstep(34.0, 200.0, -x)
	# A long, gentle fall away from the camera down the road, so the road recedes
	# instead of ending on the horizon line.
	h += 0.020 * z
	# THE ROAD CORRIDOR IS FLATTENED, so the road can be a ribbon and not a mesh
	# that has to follow every roll of the ground.
	h *= lerpf(0.10, 1.0, smoothstep(0.0, 24.0, absf(x)))
	return h


## The analytic normal of `ground_height`. Used for the terrain's own shading —
## see the header for why this is computed rather than generated.
func ground_normal(x: float, z: float) -> Vector3:
	var e := 0.35
	var dx := (ground_height(x + e, z) - ground_height(x - e, z)) / (2.0 * e)
	var dz := (ground_height(x, z + e) - ground_height(x, z - e)) / (2.0 * e)
	return Vector3(-dx, 1.0, -dz).normalized()


func _build_terrain() -> void:
	world_root = Node3D.new()
	world_root.name = "World"
	add_child(world_root)

	var mesh := _terrain_mesh(-TERRAIN_EXTENT * 0.5, TERRAIN_EXTENT * 0.5, TERRAIN_CELLS)
	ground_mat = _shader_mat(C_GROUND, 0.96)
	ground_mat.set_shader_parameter("vertex_color_mix", 1.0)
	ground = MeshInstance3D.new()
	ground.name = "Ground"
	ground.mesh = mesh
	ground.material_override = ground_mat
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world_root.add_child(ground)
	_add_prop(ground, Vector3(TERRAIN_EXTENT, 40.0, TERRAIN_EXTENT), "ground", ground_mat)
	print("  terrain: %d verts, %d tris" % [
		(TERRAIN_CELLS + 1) * (TERRAIN_CELLS + 1), TERRAIN_CELLS * TERRAIN_CELLS * 2])


## One slab of the ground, between two Z planes, in WORLD coordinates.
##
## THE ARRAYS ARE BUILT BY HAND RATHER THAN THROUGH `SurfaceTool`, AND THAT IS NOT
## A STYLE CHOICE. The first version of this world used `SurfaceTool` for the
## terrain, the road and the road edges, and all three rendered as NOTHING while
## every `BoxMesh` in the scene rendered correctly — props floating over the
## background colour, which reads as a lighting problem, a normals problem, or a
## camera problem, and is none of them. Building the arrays explicitly makes the
## vertex count, the normals and the index buffer all visible in the code that
## produces them.
##
## The slab is a parameter rather than the whole world because 11 天地合页 has to
## fold it in two, and a fold needs the two halves to be two meshes.
func _terrain_mesh(z_lo: float, z_hi: float, cells_z: int) -> ArrayMesh:
	var extent := TERRAIN_EXTENT
	var cells_x := TERRAIN_CELLS
	var step_x := extent / float(cells_x)
	var step_z := (z_hi - z_lo) / float(maxi(cells_z, 1))
	var row := cells_x + 1
	var vcount := row * (cells_z + 1)

	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	verts.resize(vcount)
	norms.resize(vcount)
	cols.resize(vcount)

	for iz in cells_z + 1:
		for ix in row:
			var x := -extent * 0.5 + float(ix) * step_x
			var z := z_lo + float(iz) * step_z
			var i := iz * row + ix
			verts[i] = Vector3(x, ground_height(x, z), z)
			# THE NORMAL IS THE ANALYTIC GRADIENT OF THE HEIGHT FUNCTION. Deriving
			# it from triangle winding would make a badly-wound quad a black
			# sheet, and the failure would look like a lighting bug.
			norms[i] = ground_normal(x, z)
			# A per-vertex tint keyed off position, so the ground is not a flat
			# wash. This is what the eye measures a flattening or a carve against.
			var n := 0.86 + 0.28 * (0.5 + 0.5 * sin(x * 0.11 + z * 0.07))
			n *= 0.92 + 0.16 * (0.5 + 0.5 * sin(x * 0.37 - z * 0.29))
			cols[i] = Color(n, n * 0.99, n * 0.92)

	var idx := PackedInt32Array()
	idx.resize(cells_x * cells_z * 6)
	var k := 0
	for iz in cells_z:
		for ix in cells_x:
			var a := iz * row + ix
			var b := a + 1
			var c := a + row + 1
			var d := a + row
			idx[k] = a
			idx[k + 1] = b
			idx[k + 2] = c
			idx[k + 3] = a
			idx[k + 4] = c
			idx[k + 5] = d
			k += 6

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


# =============================================================================
# SPLITTING THE WORLD IN TWO
# =============================================================================

## Cut the greybox world at the plane z = z_split and hand back the two halves as
## pivots standing ON that plane, so either half can be rotated about the cut.
##
## -----------------------------------------------------------------------------
## WHY THIS EXISTS, AND WHY IT IS NOT JUST "TILT THE WORLD"
## -----------------------------------------------------------------------------
##
## 11 天地合页 closes the world like a book, and a book is hinged at the EDGE of its
## pages. Rotating a terrain whose middle sits on the hinge line does something
## else entirely: the ground pivots about a line INSIDE itself, so the eye can see
## ground on BOTH sides of the line, and a line with ground on both sides is a
## RIDGE. It reads as "the world tilted", which is a different and much smaller
## claim. Cutting first gives each page an edge to be hinged on, and the cut costs
## nothing but a rebuild of two generated meshes.
##
## -----------------------------------------------------------------------------
## WHAT MOVES AND WHAT DOES NOT
## -----------------------------------------------------------------------------
##
## The terrain, the road and its edges are regenerated per side; every other prop
## is a small object that lies entirely on one side and is reparented by its REST
## position. `home_pos` is deliberately left as the WORLD-space resting position —
## every prototype reads it to mean "where this thing lives when the world is
## normal", and after the cut that is still true. Recomputing it from the new
## local transform would quietly redefine it as "where this thing is right now",
## which is the question `home_pos` exists to avoid asking.
##
## Returns `{ "front": <pivot>, "back": <pivot>, "z": <the snapped hinge Z> }`.
func split_world(z_split: float) -> Dictionary:
	var step := TERRAIN_EXTENT / float(TERRAIN_CELLS)
	var k := int(round((z_split + TERRAIN_EXTENT * 0.5) / step))
	k = clampi(k, 1, TERRAIN_CELLS - 1)
	var z := -TERRAIN_EXTENT * 0.5 + float(k) * step
	if absf(z - z_split) > 0.001:
		print("  split_world: snapped %.2f -> %.2f (terrain grid)" % [z_split, z])

	var front := Node3D.new()
	front.name = "WorldFront"
	front.position = Vector3(0.0, 0.0, z)
	world_root.add_child(front)
	var back := Node3D.new()
	back.name = "WorldBack"
	back.position = Vector3(0.0, 0.0, z)
	world_root.add_child(back)

	# ---- terrain, one slab per side ----------------------------------------
	_free_and_forget(ground)
	ground = MeshInstance3D.new()
	ground.name = "GroundFront"
	ground.mesh = _terrain_mesh(-TERRAIN_EXTENT * 0.5, z, k)
	ground.material_override = ground_mat
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ground.position = Vector3(0.0, 0.0, -z)
	front.add_child(ground)
	_add_prop_at(ground, Vector3(TERRAIN_EXTENT, 40.0, z - -TERRAIN_EXTENT * 0.5),
		"ground", Vector3(0.0, 0.0, (z - TERRAIN_EXTENT * 0.5) * 0.5), ground_mat)

	var ground_back := MeshInstance3D.new()
	ground_back.name = "GroundBack"
	ground_back.mesh = _terrain_mesh(z, TERRAIN_EXTENT * 0.5, TERRAIN_CELLS - k)
	ground_back.material_override = ground_mat
	ground_back.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ground_back.position = Vector3(0.0, 0.0, -z)
	back.add_child(ground_back)
	_add_prop_at(ground_back, Vector3(TERRAIN_EXTENT, 40.0, TERRAIN_EXTENT * 0.5 - z),
		"ground", Vector3(0.0, 0.0, (TERRAIN_EXTENT * 0.5 + z) * 0.5), ground_mat)

	# ---- road and its edges, one ribbon per side ---------------------------
	_drop_group("road")
	_free_and_forget(road)
	road = _road_into(front, z, -TERRAIN_EXTENT * 0.5, z)
	_road_into(back, z, z, TERRAIN_EXTENT * 0.5)

	# ---- everything else, by where it rests --------------------------------
	for e in props:
		var node: Node3D = e["node"]
		if not is_instance_valid(node):
			continue
		if node.get_parent() != world_root:
			continue
		var home: Vector3 = e["home_pos"]
		node.reparent((front if home.z <= z else back) as Node3D, true)

	print("  split_world: hinge z=%.1f  front=%d props  back=%d props" % [
		z, front.get_child_count(), back.get_child_count()])
	return {"front": front, "back": back, "z": z}


func _road_into(pivot: Node3D, z_pivot: float, z_lo: float, z_hi: float) -> MeshInstance3D:
	var a := maxf(z_lo, -300.0)
	var b := minf(z_hi, 40.0)
	if b - a < 2.0:
		return null
	var n := maxi(2, int(round(90.0 * (b - a) / 340.0)))
	var half := 4.6
	var lift := 0.045
	var road_mat := _shader_mat(C_ROAD, 0.90)
	var node := MeshInstance3D.new()
	node.name = "Road"
	node.mesh = _ribbon(a, b, n, -half, half, lift, 0.0)
	node.material_override = road_mat
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.position = Vector3(0.0, 0.0, -z_pivot)
	pivot.add_child(node)
	_add_prop_at(node, Vector3(9.2, 0.1, b - a), "road",
		Vector3(0.0, 0.0, (a + b) * 0.5), road_mat)

	for sign_x in [-1.0, 1.0]:
		var cx: float = float(sign_x) * (half - 0.34)
		var edge_mat := _shader_mat(C_ROAD_EDGE, 0.86)
		var edge := MeshInstance3D.new()
		edge.name = "RoadEdge"
		edge.mesh = _ribbon(a, b, n, cx - 0.15, cx + 0.15, lift + 0.010, 0.0)
		edge.material_override = edge_mat
		edge.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		edge.position = Vector3(0.0, 0.0, -z_pivot)
		pivot.add_child(edge)
		_add_prop_at(edge, Vector3(0.3, 0.1, b - a), "road",
			Vector3(0.0, 0.0, (a + b) * 0.5), edge_mat)
	return node


## Remove every prop entry of a kind and rebuild the group index. Used when a
## builder's output is replaced wholesale (the split terrain, the split road) and
## the old nodes are about to be freed — an entry pointing at a freed node is a
## crash inside `debug_hide`, which is exactly when it is needed.
func _drop_group(kind: String) -> void:
	var keep: Array = []
	for e in props:
		if String(e["kind"]) == kind:
			continue
		keep.append(e)
	props = keep
	groups.clear()
	for e in props:
		var k := String(e["kind"])
		if k != "":
			if not groups.has(k):
				groups[k] = []
			(groups[k] as Array).append(e)


func _free_and_forget(node: Node3D) -> void:
	if node == null or not is_instance_valid(node):
		return
	for e in props:
		if e["node"] == node:
			_drop_group(String(e["kind"]))
			break
	node.get_parent().remove_child(node)
	node.queue_free()


## `_add_prop`, but the resting position is stated instead of read off the node.
## After a split a node's own `position` is expressed in its pivot's frame, and
## the frame is the one thing this registry must not record.
func _add_prop_at(
	node: Node3D, size: Vector3, kind: String, home: Vector3, mat: Material = null
) -> void:
	_add_prop(node, size, kind, mat)
	(props[props.size() - 1] as Dictionary)["home_pos"] = home


func _build_road() -> void:
	var z0 := 40.0
	var z1 := -300.0
	var half := 4.6
	var n := 90
	var lift := 0.045

	var road_mesh := _ribbon(z0, z1, n, -half, half, lift, 0.0)
	var road_mat := _shader_mat(C_ROAD, 0.90)
	road = MeshInstance3D.new()
	road.name = "Road"
	road.mesh = road_mesh
	road.material_override = road_mat
	road.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world_root.add_child(road)
	_add_prop(road, Vector3(9.2, 0.1, 340.0), "road", road_mat)

	# THE ROAD'S EDGES. A straight line the eye can see stop being straight, which
	# is the cheapest and most honest proof that a rule was broken: 05 tilts it,
	# 01 presses it flat, 06 runs a blade along it.
	for sign_x in [-1.0, 1.0]:
		var cx: float = float(sign_x) * (half - 0.34)
		var edge_mesh := _ribbon(z0, z1, n, cx - 0.15, cx + 0.15, lift + 0.010, 0.0)
		var edge_mat := _shader_mat(C_ROAD_EDGE, 0.86)
		var edge := MeshInstance3D.new()
		edge.name = "RoadEdge"
		edge.mesh = edge_mesh
		edge.material_override = edge_mat
		edge.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		world_root.add_child(edge)
		_add_prop(edge, Vector3(0.3, 0.1, 340.0), "road", edge_mat)


## A flat ribbon between two x offsets, following the ground's own fall line down
## the road. Built from explicit arrays for the reason in `_build_terrain`.
##
## AND ITS WINDING MATCHES THE TERRAIN'S, WHICH IS NOT COSMETIC. The first version
## ran z from the far end to the near end, which produces the same geometry with
## every triangle wound the other way. The material is `cull_disabled` — it has to
## be, so a carved hole shows the inside of its walls — so nothing disappeared and
## nothing errored: the road rendered as a DARK NAVY STRIP exactly where the road
## should be. A back-facing polygon in this material is lit by ambient alone, and
## this world's ambient is blue, so a wrong winding looks like a colour mistake.
## The fix was found by hiding the road and watching the green terrain appear
## underneath it. `z` therefore goes from LOW to HIGH, so that the quad's third
## vertex is the one with the larger z — the same relationship the terrain grid
## uses.
func _ribbon(
	z0: float, z1: float, n: int, x0: float, x1: float, lift: float, extra_y: float
) -> ArrayMesh:
	var z_lo := minf(z0, z1)
	var z_hi := maxf(z0, z1)
	z0 = z_lo
	z1 = z_hi
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var idx := PackedInt32Array()
	verts.resize((n + 1) * 2)
	norms.resize((n + 1) * 2)
	for i in n + 1:
		var z := lerpf(z0, z1, float(i) / float(n))
		var y := ground_height(0.0, z) + lift + extra_y
		verts[i * 2] = Vector3(x0, y, z)
		verts[i * 2 + 1] = Vector3(x1, y, z)
		norms[i * 2] = Vector3.UP
		norms[i * 2 + 1] = Vector3.UP
	idx.resize(n * 6)
	for i in n:
		var a := i * 2
		var b := a + 1
		var c := a + 3
		var d := a + 2
		idx[i * 6] = a
		idx[i * 6 + 1] = b
		idx[i * 6 + 2] = c
		idx[i * 6 + 3] = a
		idx[i * 6 + 4] = c
		idx[i * 6 + 5] = d
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


# -----------------------------------------------------------------------------
# BUILDINGS. Three-to-five of them, at a spread of distances, each with ROOFS,
# EAVES, a plinth and DARK WINDOWS — because 04 世界剑鞘 pulls its blades out of
# exactly those lines, and a featureless cube has no line to give.
# -----------------------------------------------------------------------------
func _build_buildings() -> void:
	var plan := [
		#  x,     z,     w,    d,    h,   colour
		[-13.0, -20.0, 8.0, 7.0, 5.2, C_BUILDING],
		[14.5, -27.0, 9.0, 8.0, 6.6, C_BUILDING_2],
		[-19.0, -46.0, 11.0, 9.0, 8.4, C_BUILDING],
		[17.0, -58.0, 8.5, 8.0, 5.8, C_BUILDING_2],
		[-8.0, -74.0, 13.0, 10.0, 10.0, C_BUILDING],
	]
	for i in plan.size():
		var p: Array = plan[i]
		_building("Building%d" % i, float(p[0]), float(p[1]),
			float(p[2]), float(p[3]), float(p[4]), p[5])


func _building(name: String, x: float, z: float, w: float, d: float, h: float, tint: Color) -> void:
	var root := Node3D.new()
	root.name = name
	root.position = Vector3(x, ground_height(x, z), z)
	world_root.add_child(root)

	_stick(root, "Body", _box_mesh(Vector3(w, h, d)), _shader_mat(tint, 0.92),
		Vector3(0.0, h * 0.5, 0.0))
	# An eave: a slab wider than the body, sitting on top. It is the single most
	# useful edge in the world for 04 — a long straight horizontal at eye-catching
	# height, unmistakably PART of the building.
	_stick(root, "Eave", _box_mesh(Vector3(w + 1.2, 0.36, d + 1.2)), _shader_mat(C_TRIM, 0.88),
		Vector3(0.0, h + 0.18, 0.0))
	_stick(root, "Plinth", _box_mesh(Vector3(w + 0.7, 0.42, d + 0.7)), _shader_mat(C_TRIM, 0.94),
		Vector3(0.0, 0.21, 0.0))

	# Dark window and door insets on the face the camera sees (+Z). They give the
	# building an INSIDE, so a missing chunk (03) reads as a piece of a solid.
	var dark := _shader_mat(C_DARK, 0.98)
	var cols := 2 if w < 9.0 else 3
	for c in cols:
		var wx := (float(c) - (float(cols) - 1.0) * 0.5) * (w / float(cols + 1)) * 1.4
		_stick(root, "Window", _box_mesh(Vector3(1.5, 2.0, 0.24)), dark,
			Vector3(wx, h * 0.58, d * 0.5 + 0.02))
	_stick(root, "Door", _box_mesh(Vector3(1.7, 2.6, 0.24)), dark,
		Vector3(0.0, 1.3, d * 0.5 + 0.02))

	_add_prop(root, Vector3(w + 1.2, h + 0.6, d + 1.2), "building")


func _build_boxes() -> void:
	var plan := [
		[-6.2, -9.5, 1.3, 1.0], [5.8, -12.0, 1.6, 1.2], [-8.4, -16.0, 2.0, 1.5],
		[7.4, -18.0, 1.2, 0.9], [-11.5, -25.0, 2.4, 1.8], [10.5, -30.0, 1.8, 1.3],
		[-15.0, -34.0, 1.5, 1.1], [3.2, -37.0, 2.6, 2.0], [-4.0, -42.0, 1.4, 1.0],
		[9.0, -45.0, 2.2, 1.6], [-13.0, -53.0, 1.9, 1.4], [12.0, -62.0, 2.8, 2.1],
		[-3.5, -66.0, 1.3, 1.0], [6.5, -70.0, 1.7, 1.2], [-9.0, -78.0, 2.1, 1.5],
		[16.0, -84.0, 2.5, 1.9],
	]
	for i in plan.size():
		var p: Array = plan[i]
		var x := float(p[0])
		var z := float(p[1])
		var w := float(p[2])
		var h := float(p[3])
		# Deterministic pseudo-random yaw, so the set is not a grid but is the same
		# set every run.
		var yaw := fmod(float(i) * 47.3, 61.0) - 30.0
		_box_prop("Crate%d" % i, Vector3(x, ground_height(x, z) + h * 0.5, z),
			Vector3(w, h, w * (0.7 + 0.3 * fmod(float(i) * 0.37, 1.0))),
			C_ROCK.lerp(C_WOOD, fmod(float(i) * 0.21, 1.0)), "crate", 0.92,
			Vector3(0.0, yaw, 0.0))


func _build_trees() -> void:
	var plan := [
		[-24.0, -14.0], [21.0, -18.0], [-28.0, -36.0], [26.0, -40.0],
		[-20.0, -60.0], [23.0, -64.0], [-33.0, -80.0], [31.0, -86.0],
		[-7.0, -96.0],
	]
	for i in plan.size():
		var p: Array = plan[i]
		var x := float(p[0])
		var z := float(p[1])
		_tree("Tree%d" % i, Vector3(x, ground_height(x, z), z),
			0.85 + 0.45 * fmod(float(i) * 0.61, 1.0), float(i))


func _tree(name: String, at: Vector3, scale: float, seed_i: float) -> void:
	var root := Node3D.new()
	root.name = name
	root.position = at
	root.rotation_degrees = Vector3(0.0, fmod(seed_i * 29.0, 360.0), 0.0)
	world_root.add_child(root)

	var trunk_h := 3.4 * scale
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.16 * scale
	trunk.bottom_radius = 0.26 * scale
	trunk.height = trunk_h
	trunk.radial_segments = 7
	_stick(root, "Trunk", trunk, _shader_mat(C_WOOD, 0.94), Vector3(0.0, trunk_h * 0.5, 0.0))

	# Three stacked cones, offset, so the canopy's silhouette changes with the
	# view angle. A single cone reads as a cone from every direction.
	for k in 3:
		var f := float(k)
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = (1.9 - f * 0.42) * scale
		cone.height = (2.5 - f * 0.35) * scale
		cone.radial_segments = 8
		_stick(root, "Canopy", cone, _shader_mat(C_LEAF.lerp(C_ROCK, f * 0.12), 0.98),
			Vector3(0.18 * scale * (1.0 if k % 2 == 0 else -1.0),
				trunk_h + (0.9 + f * 1.1) * scale, 0.0))

	_add_prop(root, Vector3(4.0, 7.5 * scale, 4.0), "tree")


func _build_bridge() -> void:
	# A bridge over a gully 68m out: the one structure with a SPAN, which makes it
	# the clearest thing to fold (11), to tilt (05) and to run a line along (04).
	var z := -68.0
	var deck_y := ground_height(0.0, z) + 5.2
	var root := Node3D.new()
	root.name = "Bridge"
	world_root.add_child(root)
	_stick(root, "Deck", _box_mesh(Vector3(26.0, 0.6, 3.6)), _shader_mat(C_BUILDING_2, 0.90),
		Vector3(0.0, deck_y, z))
	for sign_x in [-1.0, 1.0]:
		var rail_mat := _shader_mat(C_TRIM, 0.86)
		_stick(root, "Rail", _box_mesh(Vector3(26.0, 0.22, 0.22)), rail_mat,
			Vector3(0.0, deck_y + 1.15, z + sign_x * 1.7))
		for k in 5:
			_stick(root, "Post", _box_mesh(Vector3(0.20, 1.2, 0.20)), rail_mat,
				Vector3(-11.0 + float(k) * 5.5, deck_y + 0.6, z + sign_x * 1.7))
	for i in 4:
		_stick(root, "Pillar", _box_mesh(Vector3(1.1, 9.0, 1.1)), _shader_mat(C_ROCK, 0.93),
			Vector3(-9.0 + float(i) * 6.0, deck_y - 4.4, z))
	_add_prop(root, Vector3(26.0, 12.0, 4.0), "bridge")


func _build_rocks() -> void:
	var plan := [
		[-4.5, -14.0, 1.1], [6.0, -22.0, 1.5], [-9.5, -30.0, 1.3],
		[11.5, -36.0, 1.8], [-6.0, -50.0, 1.2], [8.5, -57.0, 1.6],
		[-11.0, -70.0, 1.4],
	]
	for i in plan.size():
		var p: Array = plan[i]
		var x := float(p[0])
		var z := float(p[1])
		var r := float(p[2])
		var sphere := SphereMesh.new()
		sphere.radius = r
		sphere.height = r * 1.5
		sphere.radial_segments = 9
		sphere.rings = 5
		var node := MeshInstance3D.new()
		node.name = "Rock%d" % i
		node.mesh = sphere
		node.position = Vector3(x, ground_height(x, z) + r * 0.32, z)
		# Squashed and turned, so seven spheres do not read as seven spheres.
		node.scale = Vector3(1.0, 0.55 + 0.25 * fmod(float(i) * 0.43, 1.0),
			0.8 + 0.3 * fmod(float(i) * 0.71, 1.0))
		node.rotation_degrees = Vector3(0.0, fmod(float(i) * 53.0, 360.0), 0.0)
		var mat := _shader_mat(C_ROCK.lerp(C_STONE_LIGHT, fmod(float(i) * 0.33, 1.0)), 0.95)
		node.material_override = mat
		world_root.add_child(node)
		_add_prop(node, Vector3(r * 2.2, r * 1.6, r * 2.2), "rock", mat)


func _build_hills() -> void:
	# Distant terrain masses at 260-560m. They exist so 02 天钉 has something to be
	# bigger than and 09 神罚雷 has something to span, and they are deliberately
	# flat-shaded: at that distance what the eye reads is silhouette and colour.
	#
	# The ellipsoid's top is placed at 0.62 of its own height above the ground, so
	# a "300m hill" is actually 180m of visible mass rather than an underground
	# dome with a bump showing. The first pass placed them at -0.30h and the whole
	# range came out as a low ridge.
	var plan := [
		#  x,      z,     width, height
		[-260.0, -420.0, 420.0, 210.0], [40.0, -520.0, 560.0, 300.0],
		[300.0, -430.0, 460.0, 190.0], [-520.0, -330.0, 380.0, 165.0],
		[540.0, -360.0, 400.0, 200.0], [-120.0, -700.0, 700.0, 380.0],
		[220.0, -760.0, 620.0, 330.0], [-460.0, -640.0, 520.0, 260.0],
	]
	for i in plan.size():
		var p: Array = plan[i]
		var w := float(p[2])
		var h := float(p[3])
		var sphere := SphereMesh.new()
		sphere.radius = w * 0.5
		sphere.height = h
		sphere.radial_segments = 16
		sphere.rings = 8
		var node := MeshInstance3D.new()
		node.name = "Hill%d" % i
		node.mesh = sphere
		node.position = Vector3(float(p[0]), h * 0.12, float(p[1]))
		node.scale = Vector3(1.0, 1.0, 0.75 + 0.45 * fmod(float(i) * 0.57, 1.0))
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var mat := _shader_mat(C_HILL.lerp(C_BUILDING, 0.06 * fmod(float(i) * 0.4, 1.0)), 1.0)
		node.material_override = mat
		world_root.add_child(node)
		_add_prop(node, Vector3(w, h, w), "hill", mat)


# =============================================================================
# THE ACTORS
# =============================================================================

func _build_actors() -> void:
	# THE TARGET. A greybox body standing on the road 22m out, so its height is
	# fixed against the road's width and the buildings behind it. Every prototype
	# aims at this node, so "the target was deleted" and "the target was lifted
	# with the crust" are the same sentence in eleven files.
	target = _figure("Target", Vector3(1.6, ground_height(1.6, -22.0), -22.0),
		Color(0.300, 0.270, 0.280), Color(0.420, 0.240, 0.220), 1.0)

	# THE PLAYER, as a greybox body. In first person it is out of frame; it exists
	# for the review camera, and for 01 二相簿 it is the whole point — that hero
	# frame is "the player is still 3D and the world is not".
	player_proxy = _figure("PlayerProxy", Vector3(-3.6, ground_height(-3.6, -1.5), -1.5),
		Color(0.340, 0.330, 0.360), Color(0.520, 0.460, 0.360), 1.04)


## A greybox humanoid: pelvis, torso, chest, head, arms, legs. About 1.75m tall.
## Deliberately simple — this round's constraints forbid character work, and what
## these have to do is provide SCALE, which a proportioned figure does and a
## capsule does not.
func _figure(name: String, at: Vector3, cloth: Color, accent: Color, scale: float) -> Node3D:
	var root := Node3D.new()
	root.name = name
	root.position = at
	root.scale = Vector3.ONE * scale
	world_root.add_child(root)

	var body := _shader_mat(cloth, 0.94)
	var trim := _shader_mat(accent, 0.90)
	var dark := _shader_mat(C_DARK, 0.98)
	_stick(root, "Hips", _box_mesh(Vector3(0.38, 0.26, 0.24)), body, Vector3(0.0, 0.98, 0.0))
	_stick(root, "Torso", _box_mesh(Vector3(0.46, 0.56, 0.28)), body, Vector3(0.0, 1.38, 0.0))
	_stick(root, "Chest", _box_mesh(Vector3(0.50, 0.20, 0.30)), trim, Vector3(0.0, 1.58, 0.0))
	_stick(root, "Neck", _box_mesh(Vector3(0.16, 0.10, 0.16)), dark, Vector3(0.0, 1.72, 0.0))
	_stick(root, "Head", _box_mesh(Vector3(0.24, 0.28, 0.26)), body, Vector3(0.0, 1.90, 0.0))
	_stick(root, "Hair", _box_mesh(Vector3(0.27, 0.11, 0.29)), dark, Vector3(0.0, 2.01, -0.01))
	for sign_x in [-1.0, 1.0]:
		_stick(root, "Arm", _box_mesh(Vector3(0.14, 0.58, 0.16)), body,
			Vector3(sign_x * 0.31, 1.34, 0.0))
		_stick(root, "Forearm", _box_mesh(Vector3(0.13, 0.50, 0.15)), trim,
			Vector3(sign_x * 0.31, 0.88, 0.02))
		_stick(root, "Leg", _box_mesh(Vector3(0.17, 0.72, 0.19)), body,
			Vector3(sign_x * 0.13, 0.49, 0.0))
		_stick(root, "Shin", _box_mesh(Vector3(0.15, 0.46, 0.17)), dark,
			Vector3(sign_x * 0.13, 0.14, 0.01))
	_add_prop(root, Vector3(0.7, 2.1, 0.5), "figure")
	return root


# -----------------------------------------------------------------------------
# THE FIRST-PERSON WEAPON.
# -----------------------------------------------------------------------------
# The brief's cause for almost every one of these skills is "the player raises /
# points / plants the weapon". That is the one piece of the player a first-person
# frame can show. It is a greybox blade on the camera, driven by the prototype with
# a single transform — no rig, no animation tree, nothing this round forbids.
func _build_weapon() -> void:
	weapon_root = Node3D.new()
	weapon_root.name = "WeaponRoot"
	weapon_pose(IDLE_POS, IDLE_ROT, IDLE_SCALE)
	fp_camera.add_child(weapon_root)

	# NOT registered with `prop_materials`: the weapon is not part of the world and
	# must not be carved, flattened or whitened along with it. Nothing in this
	# round wants the player's own sword to be a victim of its own skill.
	var grip := _unregistered_mat(Color(0.115, 0.100, 0.090), 0.86)
	_stick(weapon_root, "Grip", _box_mesh(Vector3(0.045, 0.20, 0.055)), grip,
		Vector3(0.0, -0.10, 0.0))
	_stick(weapon_root, "Guard", _box_mesh(Vector3(0.20, 0.035, 0.075)), grip,
		Vector3(0.0, 0.02, 0.0))
	var blade_mat := _unregistered_mat(Color(0.640, 0.670, 0.715), 0.34, 0.20)
	_stick(weapon_root, "Blade", _box_mesh(Vector3(0.055, 1.02, 0.018)), blade_mat,
		Vector3(0.0, 0.54, 0.0))
	weapon_blade = weapon_root.get_node("Blade") as MeshInstance3D


# -----------------------------------------------------------------------------
# THE WEAPON'S POSE.
# -----------------------------------------------------------------------------
# The blade is deliberately SHORTER AND ANGLED FORWARD, and the size of it was
# found the hard way: the first version stood straight up 0.44m from the eye and
# a one-metre blade at that distance subtends about 66 degrees of the frame — it
# was not a weapon in the corner of the shot, it was a white bar across the whole
# picture, in every clip, in every prototype. A first-person weapon has to be
# FORESHORTENED, and the further from the eye, the smaller the scale it needs.
const IDLE_POS := Vector3(0.42, -0.34, -0.80)
const IDLE_ROT := Vector3(-56.0, -22.0, 8.0)
const IDLE_SCALE := 0.66


## Set the first-person weapon's pose. Prototypes call this to raise, point or
## plant it — the one piece of the player a first-person frame can show.
func weapon_pose(pos: Vector3, rot_deg: Vector3, scale := 1.0) -> void:
	if weapon_root == null:
		return
	weapon_root.position = pos
	weapon_root.rotation_degrees = rot_deg
	weapon_root.scale = Vector3.ONE * scale


## The difference between the idle pose and `target`, by `u`. A prototype that
## wants "raise the weapon" blends from idle rather than inventing a frame.
func weapon_blend(target_pos: Vector3, target_rot: Vector3, target_scale: float, u: float) -> void:
	var v := clampf(u, 0.0, 1.0)
	weapon_pose(
		IDLE_POS.lerp(target_pos, v),
		IDLE_ROT.lerp(target_rot, v),
		lerpf(IDLE_SCALE, target_scale, v))


func _build_cameras() -> void:
	fp_camera = Camera3D.new()
	fp_camera.name = "FpCamera"
	fp_camera.near = 0.05
	fp_camera.far = 4200.0
	fp_camera.fov = cam_fov
	add_child(fp_camera)
	fp_camera.make_current()

	review_camera = Camera3D.new()
	review_camera.name = "ReviewCamera"
	review_camera.near = 0.05
	review_camera.far = 4200.0
	review_camera.fov = 50.0
	add_child(review_camera)

	# Named external placements. Deliberately a short list: an external shot has
	# exactly one job in this round — to answer a question the first-person frame
	# cannot ("is the player still 3D", "how big is it", "how far has the world
	# tilted") — and it should not become a second film.
	review_points = {
		"wide": [Vector3(0.0, 30.0, 80.0), Vector3(0.0, 4.0, -80.0), 48.0],
		"high": [Vector3(-52.0, 72.0, 50.0), Vector3(0.0, 2.0, -70.0), 54.0],
		"side": [Vector3(78.0, 11.0, -30.0), Vector3(0.0, 3.0, -36.0), 46.0],
		"low": [Vector3(-9.0, 1.5, -42.0), Vector3(0.0, 4.0, -66.0), 64.0],
		"far": [Vector3(0.0, 56.0, 170.0), Vector3(0.0, 6.0, -120.0), 42.0],
		"behind": [Vector3(-6.0, 6.0, 14.0), Vector3(0.0, 3.0, -30.0), 55.0],
	}


# =============================================================================
# THE PROTOTYPE
# =============================================================================

func start(id: String) -> bool:
	if not PROTOTYPES.has(id):
		push_error("SekaiVfxLab: no prototype called '%s'" % id)
		return false
	prototype_id = id
	var script: Script = load(String(PROTOTYPES[id]))
	if script == null:
		push_error("SekaiVfxLab: could not load %s" % PROTOTYPES[id])
		return false
	prototype = Node3D.new()
	prototype.name = "Prototype"
	prototype.set_script(script)
	add_child(prototype)
	prototype.call("configure", self)
	prototype.call("build")
	print("VFX LAB: started '%s' (t_end=%.2fs)" % [id, duration()])
	return true


func duration() -> float:
	# `get` and not `call`: `t_end` is a PROPERTY on the prototype, and `call`
	# only reaches methods — a distinction that produces a silent 0.0 and a
	# one-frame clip rather than an error.
	return float(prototype.get("t_end")) if prototype != null else 0.0


func phase_name(t: float) -> String:
	return String(prototype.call("phase_name", t)) if prototype != null else ""


## The single entry point the renderer uses. Everything in the picture is a pure
## function of `t`: a frame the renderer is TOLD is 3.40s and frame 102 of a
## continuous take have to be the same picture, or a still lies about the clip.
func set_time(t: float) -> void:
	if prototype == null:
		return
	prototype.call("apply", t)
	_apply_camera()


func _apply_camera() -> void:
	fp_camera.global_position = cam_eye
	# `look_at` writes the whole basis, so the roll is applied AFTER it — set
	# before, it is silently undone.
	var look := cam_look
	if absf(look.x - cam_eye.x) < 0.0001 and absf(look.z - cam_eye.z) < 0.0001:
		look.z -= 0.001
	fp_camera.look_at(look, Vector3.UP)
	if absf(cam_roll) > 0.0001:
		fp_camera.rotate_object_local(Vector3(0.0, 0.0, 1.0), cam_roll)
	fp_camera.fov = cam_fov
	# The dome follows the eye in X/Z and stays centred vertically, so the player
	# never walks out from under the stars and the horizon never drops.
	if sky_dome != null:
		sky_dome.global_position = Vector3(cam_eye.x, 0.0, cam_eye.z)
	if using_review:
		review_camera.make_current()
	else:
		fp_camera.make_current()


## Switch to a named external placement. Returning to first person is
## `review_off()` — two named operations rather than a boolean to remember.
func review_on(point: String) -> void:
	if not review_points.has(point):
		push_warning("SekaiVfxLab: no review point '%s'" % point)
		return
	var p: Array = review_points[point]
	review_camera.global_position = p[0]
	review_camera.look_at(p[1], Vector3.UP)
	review_camera.fov = float(p[2])
	using_review = true


func review_off() -> void:
	using_review = false


# =============================================================================
# MATERIAL BROADCAST
# =============================================================================

## Set one uniform on EVERY world material. This is how a prototype carves a hole
## in the world rather than in one box: the carve is a property of the world at
## this instant, and every surface has to agree about it.
func broadcast(name: String, value: Variant) -> void:
	for m in prop_materials:
		(m as ShaderMaterial).set_shader_parameter(name, value)


## Every distinct material under a subtree. Needed by the prototypes whose claim is
## "the world does this and ONE THING does not" — 01 二相簿 keeps the player solid
## while the world goes flat, and the only way to express that is to find the
## player's own materials and set them back every frame. Collecting them once at
## build time and re-applying an override is cheaper and less error-prone than
## rebuilding the figure with different materials.
func materials_under(root: Node) -> Array:
	var found: Array = []
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D:
			var m: Material = (n as MeshInstance3D).material_override
			if m is ShaderMaterial and not found.has(m):
				found.append(m)
		for c in n.get_children():
			stack.append(c)
	return found


func _shader_mat(color: Color, rough: float, metallic := 0.0, register := true) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = PROP_SHADER
	mat.set_shader_parameter("base_color", color)
	mat.set_shader_parameter("roughness", rough)
	mat.set_shader_parameter("metallic", metallic)
	if register and not prop_materials.has(mat):
		prop_materials.append(mat)
	return mat


func _unregistered_mat(color: Color, rough: float, metallic := 0.0) -> ShaderMaterial:
	return _shader_mat(color, rough, metallic, false)


func glow_mat(
	color: Color, intensity: float, fresnel := 0.0, travel := 0.0, width := 0.2
) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = GLOW_SHADER
	mat.set_shader_parameter("line_color", color)
	mat.set_shader_parameter("intensity", intensity)
	mat.set_shader_parameter("fresnel_power", fresnel)
	mat.set_shader_parameter("travel", travel)
	mat.set_shader_parameter("travel_width", width)
	return mat


func cloud_mat(
	tint: Color, deep: Color, alpha: float, scale: float, bottom := 0.0, rim := 0.0
) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = CLOUD_SHADER
	mat.set_shader_parameter("tint", tint)
	mat.set_shader_parameter("tint_deep", deep)
	mat.set_shader_parameter("alpha", alpha)
	mat.set_shader_parameter("scale", scale)
	mat.set_shader_parameter("bottom_weight", bottom)
	mat.set_shader_parameter("rim", rim)
	return mat


func sky_material() -> ShaderMaterial:
	return sky_mat


# =============================================================================
# GEOMETRY HELPERS
# =============================================================================

func _box_mesh(size: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	return m


func _stick(parent: Node3D, name: String, mesh: Mesh, mat: Material, at: Vector3) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = name
	node.mesh = mesh
	node.material_override = mat
	node.position = at
	parent.add_child(node)
	return node


func _box_prop(
	name: String, at: Vector3, size: Vector3, color: Color, kind: String,
	rough := 0.9, rot := Vector3.ZERO
) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = name
	node.mesh = _box_mesh(size)
	var mat := _shader_mat(color, rough)
	node.material_override = mat
	node.position = at
	node.rotation_degrees = rot
	world_root.add_child(node)
	_add_prop(node, size, kind, mat)
	return node


## Register a node as a thing the prototypes can act on. Materials are collected
## by `_shader_mat` as they are created, so a material that was built but not
## registered is a material the world-wide broadcast will not reach.
func _add_prop(node: Node3D, size: Vector3, kind: String, _mat: Material = null) -> void:
	var entry := {
		"name": node.name,
		"node": node,
		"size": size,
		"kind": kind,
		"home_pos": node.position,
		"home_basis": node.transform.basis,
	}
	props.append(entry)
	if kind != "":
		if not groups.has(kind):
			groups[kind] = []
		(groups[kind] as Array).append(entry)


func group(kind: String) -> Array:
	return groups.get(kind, [])


## APPEND-ONLY DEBUG HOOK. Hide every prop whose name contains one of `needles`.
##
## This exists because "the road is not rendering" is a question that has three
## plausible answers — it is not there, it is behind something, it is there and
## the wrong colour — and they are indistinguishable by looking at the frame. A
## named hide turns the frame into an experiment: the thing that disappears is the
## thing that was being looked at.
func debug_hide(needles: Array) -> void:
	var hidden := 0
	for e in props:
		var name := String(e["name"])
		for needle in needles:
			var n := String(needle).strip_edges()
			if n != "" and name.findn(n) >= 0:
				(e["node"] as Node3D).visible = false
				hidden += 1
				break
	print("  debug_hide %s -> hid %d props" % [str(needles), hidden])


## Report each prop's real bounds. A mesh whose AABB is degenerate, or whose size
## is not what it was asked for, is a mesh that will render as nothing and give no
## error while doing it.
func debug_report() -> void:
	for e in props:
		var node := e["node"] as Node3D
		var line := "  prop %-14s kind=%-8s size=%s" % [String(e["name"]), String(e["kind"]), str(e["size"])]
		if node is MeshInstance3D:
			var mesh := (node as MeshInstance3D).mesh
			if mesh != null:
				line += " aabb=%s surf=%d" % [str(mesh.get_aabb().size), mesh.get_surface_count()]
		print(line)


## A node position in the world at a ground-relative height, for a prototype that
## wants to place something without re-deriving the terrain.
func at_ground(x: float, z: float, lift := 0.0) -> Vector3:
	return Vector3(x, ground_height(x, z) + lift, z)
