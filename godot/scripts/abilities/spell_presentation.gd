extends Node3D
class_name SpellPresentation

@onready var combat: CombatController = get_node("../../../../../../CombatController")

var fire_orb: MeshInstance3D
var fire_shell: MeshInstance3D
var fire_light: OmniLight3D
var fire_trail: Array[MeshInstance3D] = []
var frost_stream: Array[MeshInstance3D] = []
var wind_ring: MeshInstance3D
var wind_dust: Array[MeshInstance3D] = []
var last_spell: StringName = &""
var was_casting := false


func _ready() -> void:
	fire_orb = _sphere("Fire White Core", 0.105, Color(1.0, 0.96, 0.76))
	fire_shell = _sphere("Fire Orange Shell", 0.18, Color(1.0, 0.32, 0.05, 0.65))
	fire_light = OmniLight3D.new()
	fire_light.name = "Fire Dynamic Light"
	fire_light.light_color = Color(1.0, 0.33, 0.08)
	fire_light.omni_range = 3.0
	fire_light.light_energy = 0.8
	add_child(fire_light)
	for i in 6:
		fire_trail.append(_sphere("Fire Trail %d" % i, 0.025 + i * 0.005, Color(1.0, 0.42 + i * 0.055, 0.06, 0.78)))
	for i in 10:
		frost_stream.append(_sphere("Frost Stream %d" % i, 0.035 + float(i % 3) * 0.012, Color(0.72, 0.94, 1.0, 0.62)))
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 0.77
	ring_mesh.outer_radius = 0.81
	wind_ring = MeshInstance3D.new()
	wind_ring.name = "Wind Pressure Ring"
	wind_ring.mesh = ring_mesh
	wind_ring.material_override = _material(Color(0.76, 0.98, 1.0, 0.72))
	wind_ring.rotation.x = PI * 0.5
	add_child(wind_ring)
	for i in 8:
		wind_dust.append(_sphere("Wind Dust %d" % i, 0.025, Color(0.83, 0.89, 0.82, 0.56)))
	_hide_all()


func _material(tint: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.no_depth_test = true
	material.albedo_color = tint
	return material


func _sphere(label: String, radius: float, tint: Color) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	var node := MeshInstance3D.new()
	node.name = label
	node.mesh = mesh
	node.material_override = _material(tint)
	add_child(node)
	return node


func _hide_all() -> void:
	for node in [fire_orb, fire_shell, wind_ring]:
		node.visible = false
	for node in fire_trail + frost_stream + wind_dust:
		node.visible = false
	fire_light.visible = false


func _process(_delta: float) -> void:
	if combat.state != CombatController.State.CAST:
		if was_casting:
			_hide_all()
		was_casting = false
		return
	was_casting = true
	last_spell = combat.casting_spell
	var age := combat.state_time
	var ability: AbilityData = combat._current_ability()
	var release := ability.startup
	match last_spell:
		&"fire": _fire(age, release, ability.active)
		&"frost": _frost(age, release, ability.active)
		&"wind": _wind(age, release, ability.active)


func _fire(age: float, release: float, active: float) -> void:
	_hide_all()
	var travel := clampf((age - release) / maxf(0.01, active + 0.19), 0.0, 1.0)
	var gathering := age < release
	var origin := Vector3(0.42, -0.2, -1.16)
	var location := origin.lerp(Vector3(0.0, -0.08, -5.8), travel)
	fire_orb.visible = true
	fire_shell.visible = true
	fire_light.visible = true
	fire_orb.position = location
	fire_shell.position = location
	fire_light.position = location
	var scale_now := smoothstep(0.0, release, age) * (1.0 + (0.7 if travel >= 0.99 else 0.0))
	fire_orb.scale = Vector3.ONE * maxf(0.05, scale_now)
	fire_shell.scale = Vector3.ONE * maxf(0.05, scale_now * (1.0 + sin(age * 34.0) * 0.08))
	for i in fire_trail.size():
		var fleck := fire_trail[i]
		fleck.visible = age > 0.03
		var offset := float(i + 1) * 0.17
		if gathering:
			fleck.position = origin + Vector3(cos(float(i) * 2.4), sin(float(i) * 2.4), 0.0) * (0.5 * (1.0 - smoothstep(0.0, release, age)))
		else:
			fleck.position = location + Vector3(sin(float(i) * 3.1) * 0.10, cos(float(i) * 2.3) * 0.09, offset)
		fleck.scale = Vector3.ONE * (0.7 + sin(age * 26.0 + i) * 0.2)


func _frost(age: float, release: float, active: float) -> void:
	_hide_all()
	var strength := smoothstep(0.02, release, age) * (1.0 - smoothstep(release + active, release + active + 0.2, age))
	for i in frost_stream.size():
		var mist := frost_stream[i]
		mist.visible = strength > 0.01
		var progress := fposmod(age * 3.8 + float(i) / frost_stream.size(), 1.0)
		mist.position = Vector3(0.42 * (1.0 - progress) + sin(float(i) * 2.7 + age * 15.0) * 0.15 * progress, -0.2 + cos(float(i) * 3.2 + age * 9.0) * 0.13, -1.15 - progress * 4.2)
		mist.scale = Vector3.ONE * strength * (0.7 + progress * 1.4)


func _wind(age: float, release: float, active: float) -> void:
	_hide_all()
	var progress := clampf((age - release) / maxf(0.01, active + 0.17), 0.0, 1.0)
	wind_ring.visible = age >= release and age < release + active + 0.17
	wind_ring.position = Vector3(0.0, -0.13, -2.2 - progress * 2.0)
	wind_ring.scale = Vector3.ONE * (0.18 + progress * 2.3)
	for i in wind_dust.size():
		var dust := wind_dust[i]
		dust.visible = wind_ring.visible
		var angle := TAU * float(i) / wind_dust.size() + age * 0.7
		dust.position = wind_ring.position + Vector3(cos(angle) * (0.28 + progress * 1.6), sin(angle) * (0.28 + progress * 1.6), float(i % 3) * 0.12)
		dust.scale = Vector3.ONE * (1.0 - progress * 0.5)
