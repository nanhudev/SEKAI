extends Node3D
class_name ShatterVFX

@export var lifetime := 0.85
@export var shard_count := 14

var age := 0.0
var shards: Array[MeshInstance3D] = []
var velocities: Array[Vector3] = []
var materials: Array[StandardMaterial3D] = []


func _ready() -> void:
	var random := RandomNumberGenerator.new()
	random.seed = 2718
	for index in shard_count:
		var shard := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(random.randf_range(0.06, 0.16), random.randf_range(0.14, 0.36), random.randf_range(0.05, 0.13))
		shard.mesh = mesh
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.64, 0.88, 1.0, 0.88)
		material.metallic = 0.15
		material.roughness = 0.2
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		shard.material_override = material
		shard.position = Vector3(random.randf_range(-0.3, 0.3), random.randf_range(0.6, 1.7), random.randf_range(-0.3, 0.3))
		shard.rotation = Vector3(random.randf(), random.randf(), random.randf()) * TAU
		add_child(shard)
		shards.append(shard)
		materials.append(material)
		var horizontal := Vector3(random.randf_range(-1.0, 1.0), 0.0, random.randf_range(-1.0, 1.0)).normalized()
		velocities.append(horizontal * random.randf_range(2.0, 4.0) + Vector3.UP * random.randf_range(1.5, 3.5))


func _process(delta: float) -> void:
	age += delta
	var progress := minf(1.0, age / lifetime)
	for index in shards.size():
		var shard := shards[index]
		var velocity := velocities[index]
		if progress < 0.58:
			shard.position += velocity * delta
			velocities[index] = velocity + Vector3.DOWN * 8.0 * delta
		else:
			shard.position = shard.position.lerp(Vector3(0, 1.1, 0), minf(1.0, delta * 8.0))
		shard.rotate_y(delta * 7.0)
		var color := materials[index].albedo_color
		color.a = 0.88 * (1.0 - progress)
		materials[index].albedo_color = color
	if age >= lifetime:
		queue_free()
