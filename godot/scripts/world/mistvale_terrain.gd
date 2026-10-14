@tool
extends Node3D
class_name MistvaleTerrain
## GATE 1 / LEVEL ART PASS 02 terrain for the Mistvale Vertical Slice Region.
##
## Generates a mesh from the analytic field in MistvaleHeights and shades it with
## a zoned surface shader (resources/shaders/mistvale_terrain.gdshader).
##
## WHAT CHANGED IN PASS 02: this used to be a vertex-coloured sheet — one
## flat grey-green over the whole region, which is why the terrain read as a
## greybox even though the height field was already real. Now:
##
##   * the grid is 2 m instead of 4 m, so the relief layer in the field has
##     enough samples to actually show;
##   * the vertex stream carries the two masks the shader cannot infer —
##     road wear and the settlement footprint;
##   * the shader derives soil / grass / rock / cliff / gravel / wet / town from
##     slope + height per pixel.
##
## THIS IS STILL NOT FINAL ART. It is the ground, at a quality where the map
## reads as a map. Authored terrain, decals and real textures are later gates.

## Mesh grid resolution in metres. 2 m keeps interpolation errors beneath
## 0.4 m across the region after the height field discontinuities are removed.
const STEP := 2.0
const VISUAL_STEP := 1.0
const SLICE_X := Vector2(-80.0, 80.0)
const SLICE_Z := Vector2(80.0, 220.0)

const SHADER_PATH := "res://resources/shaders/mistvale_terrain.gdshader"

@export var build_collision: bool = true


func _ready() -> void:
	_build()


func _build() -> void:
	for child in get_children():
		child.queue_free()

	var body := MeshInstance3D.new()
	body.name = "TerrainMesh"
	body.mesh = _build_mesh(STEP, true, true)
	body.material_override = _terrain_material()
	# THE TERRAIN DOES NOT CAST. IT ONLY RECEIVES.
	#
	# A 660 x 760 m heightfield rendered into a directional shadow map covering
	# a few hundred metres has a texel far larger than a 3 m grid step, and the
	# surface shadows itself: the first render with a working sun came back with
	# the entire valley black under a dense moire of self-shadowing. No bias
	# value fixes that without opening a visible gap between every object and
	# its own shadow, because the correct bias is proportional to how much
	# terrain a single shadow texel spans.
	#
	# What is lost is the mountain casting onto the valley. That is a real
	# amount of drama, and it belongs to GATE 5 with an authored solution (a
	# low-resolution shadow proxy, or baked vertex AO on the slopes). What is
	# gained is a lit map today: rocks, trees, buildings and the bridge all
	# still cast onto it.
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(body)

	# This tile owns only the visual surface around the bridge reach. Physics
	# stays on the original complete 2 m gameplay heightfield.
	var slice := MeshInstance3D.new()
	slice.name = "GoldenPathVisualTerrainV2"
	slice.mesh = _build_visual_slice()
	slice.material_override = _terrain_material(true)
	slice.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(slice)

	if build_collision:
		var static_body := StaticBody3D.new()
		static_body.name = "TerrainBody"
		var col := CollisionShape3D.new()
		col.name = "TerrainCollision"
		# create_trimesh_shape() instead of assigning ConcavePolygonShape3D.faces.
		# The direct assignment is no longer accepted, and it fails LOUDLY in the
		# log while failing SILENTLY in the world: the region still rendered
		# perfectly, so every screenshot looked right and there was no ground to
		# stand on. Any GATE 1 walkthrough would have fallen through on step one.
		# Keep the complete 2 m gameplay mesh under both visual tiles. Godot's
		# concave physics faces use the reverse winding from the rendered mesh;
		# without flipping them a ray from above sees no floor and the walker
		# catches on triangle edges with a horizontal collision normal.
		col.shape = _collision_mesh(_build_mesh(STEP, false)).create_trimesh_shape()
		static_body.add_child(col)
		add_child(static_body)


static func _collision_mesh(visual: Mesh) -> ArrayMesh:
	var arrays := visual.surface_get_arrays(0)
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	for i in range(0, indices.size(), 3):
		var swap := indices[i + 1]
		indices[i + 1] = indices[i + 2]
		indices[i + 2] = swap
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _terrain_material(hero_bank: bool = false) -> Material:
	var sh := load(SHADER_PATH) as Shader
	if sh == null:
		# Loud, not silent. A missing shader that quietly falls back to a flat
		# material would look like "the terrain pass just did not help much",
		# which is a much harder thing to diagnose than a red line in the log.
		push_error("MistvaleTerrain: missing shader %s — using flat fallback" % SHADER_PATH)
		var fallback := StandardMaterial3D.new()
		fallback.albedo_color = Color(0.40, 0.43, 0.38)
		fallback.roughness = 1.0
		fallback.cull_mode = BaseMaterial3D.CULL_DISABLED
		return fallback
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("water_y", MistvaleHeights.RIVER_Y)
	m.set_shader_parameter("hero_bank_strength", 1.0 if hero_bank else 0.0)
	return m


## `paint` controls whether the per-vertex masks are computed. The collision
## mesh does not need them, and computing them is the expensive part of this
## build — path distance and settlement distance are both multi-segment queries
## per vertex.
static func _build_mesh(step: float, paint: bool, omit_slice: bool = false) -> ArrayMesh:
	var nx := int((MistvaleHeights.MAX_X - MistvaleHeights.MIN_X) / step) + 1
	var nz := int((MistvaleHeights.MAX_Z - MistvaleHeights.MIN_Z) / step) + 1
	var count := nx * nz

	var verts := PackedVector3Array()
	var colors := PackedColorArray()
	verts.resize(count)
	colors.resize(count)

	for iz in nz:
		var z := MistvaleHeights.MIN_Z + float(iz) * step
		for ix in nx:
			var x := MistvaleHeights.MIN_X + float(ix) * step
			var i := iz * nx + ix
			verts[i] = Vector3(x, MistvaleHeights.height_at(x, z), z)
			if paint:
				# R = road/verge wear, G = settled footprint, B = variation seed.
				colors[i] = Color(
					MistvaleHeights.path_factor(x, z),
					MistvaleHeights.settlement_factor(x, z),
					MistvaleHeights.variation(x, z)
				)
			else:
				colors[i] = Color(0.0, 0.0, 0.0, 1.0)

	var idx := PackedInt32Array()
	idx.resize((nx - 1) * (nz - 1) * 6)
	var k := 0
	for iz in nz - 1:
		for ix in nx - 1:
			var cell_x := MistvaleHeights.MIN_X + (float(ix) + 0.5) * step
			var cell_z := MistvaleHeights.MIN_Z + (float(iz) + 0.5) * step
			if omit_slice and cell_x > SLICE_X.x and cell_x < SLICE_X.y \
					and cell_z > SLICE_Z.x and cell_z < SLICE_Z.y:
				continue
			var a := iz * nx + ix
			var b := a + 1
			var c := a + nx
			var d := c + 1
			# (a, c, b) / (b, c, d) — consistent winding throughout.
			idx[k] = a
			idx[k + 1] = c
			idx[k + 2] = b
			idx[k + 3] = b
			idx[k + 4] = c
			idx[k + 5] = d
			k += 6
	idx.resize(k)

	var normals := PackedVector3Array()
	normals.resize(count)
	for i in range(0, idx.size(), 3):
		var i0 := idx[i]
		var i1 := idx[i + 1]
		var i2 := idx[i + 2]
		var e1 := verts[i1] - verts[i0]
		var e2 := verts[i2] - verts[i0]
		var n := e1.cross(e2).normalized()
		normals[i0] += n
		normals[i1] += n
		normals[i2] += n
	for i in count:
		normals[i] = normals[i].normalized()

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = idx

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func _build_visual_slice() -> ArrayMesh:
	var nx := int((SLICE_X.y - SLICE_X.x) / VISUAL_STEP) + 1
	var nz := int((SLICE_Z.y - SLICE_Z.x) / VISUAL_STEP) + 1
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	verts.resize(nx * nz)
	cols.resize(nx * nz)
	for iz in nz:
		var z := SLICE_Z.x + float(iz) * VISUAL_STEP
		for ix in nx:
			var x := SLICE_X.x + float(ix) * VISUAL_STEP
			var i := iz * nx + ix
			var ground := MistvaleHeights.height_at(x, z)
			var from_edge := minf(minf(x - SLICE_X.x, SLICE_X.y - x),
				minf(z - SLICE_Z.x, SLICE_Z.y - z))
			var seam := smoothstep(0.0, 10.0, from_edge)
			var shore := absf(z - MistvaleHeights.river_center_z(x))
			var bank := smoothstep(14.0, 18.0, shore) * (1.0 - smoothstep(27.0, 35.0, shore))
			var shelves := 0.0
			for p in [Vector2(-53.0, 163.0), Vector2(-34.0, 184.0),
					Vector2(42.0, 160.0), Vector2(60.0, 193.0)]:
				var dist := Vector2(x, z).distance_to(p)
				shelves += (1.0 - smoothstep(2.0, 15.0, dist)) * 0.30
			var route_clear := 1.0 - smoothstep(0.12, 0.72,
				MistvaleHeights.path_factor(x, z))
			var signed_shore := MistvaleHeights.river_center_z(x) - z
			var bank_reach := smoothstep(-12.0, 2.0, x) \
				* (1.0 - smoothstep(58.0, 72.0, x))
			var cut_band := smoothstep(15.0, 19.0, signed_shore) \
				* (1.0 - smoothstep(27.0, 34.0, signed_shore))
			var erosion := seam * route_clear * bank_reach * cut_band
			var relief := minf(0.30, seam * route_clear * bank * shelves)
			verts[i] = Vector3(x, ground + relief, z)
			cols[i] = Color(MistvaleHeights.path_factor(x, z),
				MistvaleHeights.settlement_factor(x, z), MistvaleHeights.variation(x, z), erosion)
	var idx := PackedInt32Array()
	idx.resize((nx - 1) * (nz - 1) * 6)
	var k := 0
	for iz in nz - 1:
		for ix in nx - 1:
			var a := iz * nx + ix
			var b := a + 1
			var c := a + nx
			var d := c + 1
			idx[k] = a; idx[k + 1] = c; idx[k + 2] = b
			idx[k + 3] = b; idx[k + 4] = c; idx[k + 5] = d
			k += 6
	var normals := PackedVector3Array()
	normals.resize(verts.size())
	for i in range(0, idx.size(), 3):
		var a := idx[i]; var b := idx[i + 1]; var c := idx[i + 2]
		var n := (verts[b] - verts[a]).cross(verts[c] - verts[a]).normalized()
		normals[a] += n; normals[b] += n; normals[c] += n
	for i in normals.size():
		normals[i] = normals[i].normalized()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
