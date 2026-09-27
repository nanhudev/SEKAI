extends Node3D
class_name IaidoTear3D

var edge: MeshInstance3D
var core: MeshInstance3D
var fractures: Array[MeshInstance3D] = []
var fragments: Array[MeshInstance3D] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	edge = _piece("Ink Edge", Vector3(3.2, 0.11, 0.015), Color(0.015, 0.025, 0.035), -0.02)
	core = _piece("Ivory Core", Vector3(3.05, 0.026, 0.02), Color(1.0, 0.96, 0.82), 0.0)
	for i in 4:
		var crack := _piece("Secondary Fracture %d" % i, Vector3(0.72 - i * 0.1, 0.009, 0.012), Color(0.9, 0.93, 0.95), 0.01)
		crack.position = Vector3(-0.9 + i * 0.65, (0.22 if i % 2 == 0 else -0.25), 0.01)
		crack.rotation.z = (-0.65 if i % 2 == 0 else 0.52)
		fractures.append(crack)
	for i in 10:
		var fleck := _piece("Ink Fragment %d" % i, Vector3(0.025 + float(i % 3) * 0.014, 0.08, 0.01), Color(0.025, 0.035, 0.045) if i % 2 == 0 else Color(0.92, 0.93, 0.87), 0.02)
		fleck.rotation.z = float(i) * 1.7
		fragments.append(fleck)
	visible = false


func _piece(label: String, size: Vector3, tint: Color, z: float) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.no_depth_test = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = tint
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.name = label
	instance.mesh = mesh
	instance.position.z = z
	add_child(instance)
	return instance


func stage(time: float) -> void:
	visible = time >= 0.49 and time < 1.16
	if not visible:
		return
	var opening := smoothstep(0.49, 0.58, time)
	var closing := 1.0 - smoothstep(0.86, 1.15, time)
	var width := opening * closing
	edge.scale = Vector3(width, maxf(0.12, opening * closing), 1.0)
	core.scale = Vector3(width, 1.0, 1.0)
	for i in fractures.size():
		fractures[i].visible = time >= 0.53 and time <= 0.93
		fractures[i].scale.x = width
	for i in fragments.size():
		var phase := float(i) * 2.399
		var burst := smoothstep(0.50, 0.68, time) * (1.0 - smoothstep(0.86, 1.12, time))
		fragments[i].position = Vector3(cos(phase) * (0.12 + burst * (0.45 + float(i % 4) * 0.13)), sin(phase) * (0.08 + burst * 0.33), 0.02)
		fragments[i].scale = Vector3.ONE * maxf(0.05, burst)
