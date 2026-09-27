extends Node3D
class_name ArenaDressing
# Placeholder arena dressing for the combat sandbox.
#
# WHY THIS EXISTS: an Iaido ceremony that cuts the world in half cannot be
# judged — or even seen — in an empty box with a flat floor and a flat sky.
# The cut, the separation and the glass failure all act on whatever the world
# contains, so the sandbox needs silhouettes for them to act on.
#
# This is DETERMINISTIC placeholder geometry: blocky, untextured, no collision,
# no gameplay meaning. It is here so the presentation can be evaluated, and it
# is meant to be replaced wholesale by the ART line (see docs/asset_briefs).

const SEED := 20260927
const CENTER := Vector3(0.0, 0.0, -11.0)

const PALETTE := [
	Color(0.56, 0.53, 0.48),   # warm stone
	Color(0.43, 0.46, 0.51),   # cool stone
	Color(0.24, 0.25, 0.29),   # dark basalt
	Color(0.71, 0.67, 0.59),   # pale sandstone
]


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	_build_ring_of_pillars(rng)
	_build_near_pillars(rng)
	_build_far_wall()
	_build_floor_slabs(rng)


func _material(tint: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = tint
	material.roughness = 0.92
	return material


func _place(mesh: Mesh, tint: Color, pos: Vector3, yaw: float) -> void:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = _material(tint)
	instance.position = pos
	instance.rotation.y = yaw
	add_child(instance)


func _box(size: Vector3) -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = size
	return mesh


func _build_ring_of_pillars(rng: RandomNumberGenerator) -> void:
	for i in 10:
		var angle := TAU * float(i) / 10.0 + rng.randf_range(-0.18, 0.18)
		var distance := rng.randf_range(9.0, 17.0)
		var x := CENTER.x + sin(angle) * distance
		var z := CENTER.z - cos(angle) * distance * 0.55
		# Keep the middle of the shot (where the enemy and the sword read)
		# clear of clutter.
		if absf(x) < 1.8:
			x += 2.6 * (1.0 if x >= 0.0 else -1.0)
		var height := rng.randf_range(2.0, 7.0)
		var width := rng.randf_range(0.7, 1.9)
		var tint: Color = PALETTE[rng.randi_range(0, PALETTE.size() - 1)]
		_place(
			_box(Vector3(width, height, width * rng.randf_range(0.7, 1.3))),
			tint,
			Vector3(x, height * 0.5, z),
			rng.randf_range(-0.5, 0.5)
		)
		# A short cap stone breaks the silhouette so the cut has something to
		# sever rather than a clean top edge.
		if rng.randf() > 0.45:
			_place(
				_box(Vector3(width * 1.35, 0.35, width * 1.1)),
				PALETTE[2],
				Vector3(x, height + 0.17, z),
				rng.randf_range(-0.6, 0.6)
			)


func _build_far_wall() -> void:
	# One long wall behind everything: this is the piece that most clearly
	# shows the two halves of the world drifting apart. It is tall on purpose —
	# the cut has to cross something with real screen height, or the separation
	# happens entirely inside flat sky and flat floor and reads as nothing.
	var height := 5.6
	_place(_box(Vector3(34.0, height, 0.7)), PALETTE[1], CENTER + Vector3(0.0, height * 0.5, -6.0), 0.0)
	_place(_box(Vector3(34.0, 0.5, 1.0)), PALETTE[2], CENTER + Vector3(0.0, height + 0.2, -6.0), 0.0)


func _build_near_pillars(rng: RandomNumberGenerator) -> void:
	# Mid-ground pillars close enough that the diagonal cut runs THROUGH them.
	# The centre is left clear so the enemy and the sword still read.
	for i in 6:
		var side := -1.0 if i % 2 == 0 else 1.0
		var x := side * (2.7 + float(i / 2) * 1.6 + rng.randf_range(-0.25, 0.25))
		var z := rng.randf_range(-4.2, 0.4)
		var height := rng.randf_range(2.4, 4.6)
		var width := rng.randf_range(0.6, 1.25)
		var tint: Color = PALETTE[rng.randi_range(0, PALETTE.size() - 1)]
		_place(
			_box(Vector3(width, height, width * rng.randf_range(0.8, 1.2))),
			tint,
			Vector3(x, height * 0.5, z),
			rng.randf_range(-0.4, 0.4)
		)


func _build_floor_slabs(rng: RandomNumberGenerator) -> void:
	for i in 14:
		var x := rng.randf_range(-16.0, 16.0)
		var z := rng.randf_range(-22.0, -3.0)
		var size := Vector3(rng.randf_range(1.4, 4.2), rng.randf_range(0.12, 0.4), rng.randf_range(1.4, 4.2))
		var tint: Color = PALETTE[rng.randi_range(0, PALETTE.size() - 1)].darkened(rng.randf_range(0.0, 0.25))
		_place(_box(size), tint, Vector3(x, size.y * 0.5 + 0.06, z), rng.randf_range(0.0, TAU))
