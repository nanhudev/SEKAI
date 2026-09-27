extends Node3D
class_name MagicCircle3D

@export var radius := 0.28
@export var circle_color := Color(0.55, 0.85, 1.0, 0.8)
@export var rotation_speed := 1.3
@export var spawn_time := 0.18
@export var collapse_time := 0.22
@export var pulse := 0.1

var outer_ring := Node3D.new()
var rune_ring := Node3D.new()
var inner_geometry := Node3D.new()
var energy_core := Node3D.new()
var shader_material := ShaderMaterial.new()
var casting := false
var age := 0.0


func _ready() -> void:
	visible = false
	var shader := Shader.new()
	shader.code = "shader_type spatial; render_mode unshaded, cull_disabled; uniform vec4 tint : source_color = vec4(0.55, 0.85, 1.0, 0.8); void fragment() { ALBEDO = tint.rgb; EMISSION = tint.rgb * 1.8; ALPHA = tint.a; }"
	shader_material.shader = shader
	shader_material.set_shader_parameter("tint", circle_color)
	add_child(outer_ring)
	add_child(rune_ring)
	add_child(inner_geometry)
	add_child(energy_core)
	outer_ring.name = "OuterRing"
	rune_ring.name = "RuneRing"
	inner_geometry.name = "InnerGeometry"
	energy_core.name = "EnergyCore"
	_add_torus(outer_ring, radius, 0.012)
	_add_torus(inner_geometry, radius * 0.52, 0.009)
	for index in 12:
		var marker := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.06, 0.008, 0.015)
		marker.mesh = box
		marker.material_override = shader_material
		var angle := TAU * float(index) / 12.0
		marker.position = Vector3(cos(angle), 0.0, sin(angle)) * radius * 0.77
		marker.rotation.y = -angle
		rune_ring.add_child(marker)
	var core := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.055
	sphere.height = 0.11
	core.mesh = sphere
	core.material_override = shader_material
	energy_core.add_child(core)


func _add_torus(parent: Node3D, ring_radius: float, tube_radius: float) -> void:
	var instance := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = ring_radius - tube_radius
	torus.outer_radius = ring_radius + tube_radius
	instance.mesh = torus
	instance.material_override = shader_material
	parent.add_child(instance)


func set_casting(enabled: bool) -> void:
	casting = enabled
	age = 0.0
	if enabled:
		shader_material.set_shader_parameter("tint", circle_color)
		visible = true
		scale = Vector3.ZERO


func _process(delta: float) -> void:
	if not visible:
		return
	age += delta
	outer_ring.rotation.y += rotation_speed * delta
	rune_ring.rotation.y -= rotation_speed * 0.72 * delta
	inner_geometry.rotation.y += rotation_speed * 1.35 * delta
	if casting:
		var grow := minf(1.0, age / maxf(spawn_time, 0.001))
		scale = Vector3.ONE * (grow + sin(age * 12.0) * pulse * grow)
	else:
		scale = Vector3.ONE * maxf(0.0, 1.0 - age / maxf(collapse_time, 0.001))
		if age >= collapse_time:
			visible = false
