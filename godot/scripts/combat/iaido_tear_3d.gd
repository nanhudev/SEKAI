extends Node3D
class_name IaidoTear3D
# World-space pre-cut omen.
#
# While the reverse wave compresses reality, a thin unstable line appears in
# the world exactly where the cut will land. It is faint, it breathes, and it
# dies the instant the real void opens. The cut itself is screen space; this
# only sells that the world knew where it was going to break.

const OMEN_DISTANCE := -1.2

var ivory_line: MeshInstance3D
var ink_line: MeshInstance3D
var flecks: Array[MeshInstance3D] = []
var fleck_materials: Array[StandardMaterial3D] = []
var ivory_material: StandardMaterial3D
var ink_material: StandardMaterial3D


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	ivory_line = _plane("Spatial Omen Ivory", Vector3(3.6, 0.010, 0.010), Color(1.0, 0.97, 0.88, 0.0), 0.0)
	ink_line = _plane("Spatial Omen Ink", Vector3(3.6, 0.030, 0.008), Color(0.02, 0.03, 0.05, 0.0), -0.008)
	ivory_material = ivory_line.mesh.material as StandardMaterial3D
	ink_material = ink_line.mesh.material as StandardMaterial3D
	for i in 6:
		var fleck := _plane("Omen Fleck %d" % i, Vector3(0.05, 0.012, 0.006), Color(0.92, 0.94, 0.90, 0.0), 0.006)
		flecks.append(fleck)
		fleck_materials.append(fleck.mesh.material as StandardMaterial3D)
	visible = false


func _plane(label: String, size: Vector3, tint: Color, z: float) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.no_depth_test = true
	material.albedo_color = tint
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.name = label
	instance.mesh = mesh
	instance.position.z = z
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)
	return instance


func stage(time: float, tuning: IaidoTuning) -> void:
	visible = time >= tuning.wave_start and time < tuning.cut_start + 0.02
	if not visible:
		return
	# The cut runs up and to the right; in view space that is -cut_angle.
	var screen_angle := deg_to_rad(-tuning.cut_angle_degrees)
	rotation.z = screen_angle
	ivory_line.position.z = OMEN_DISTANCE
	ink_line.position.z = OMEN_DISTANCE - 0.01

	var rise := IaidoTuning.ease_out_cubic(IaidoTuning.span(time, tuning.wave_start, tuning.wave_start + 0.45))
	var death := 1.0 - IaidoTuning.span(time, tuning.draw_start, tuning.cut_start)
	var compression := IaidoTuning.span(time, tuning.wave_start, tuning.hold_end)
	var breathe := 1.0 + 0.28 * compression * sin(time * 7.4)
	var alpha := rise * death * breathe

	ivory_material.albedo_color = Color(1.0, 0.97, 0.88, clampf(alpha * 0.38, 0.0, 1.0))
	ink_material.albedo_color = Color(0.02, 0.03, 0.05, clampf(alpha * 0.42, 0.0, 1.0))
	# The omen tightens as the compression builds.
	ivory_line.scale = Vector3(1.0, lerpf(1.6, 0.55, compression), 1.0)
	ink_line.scale = Vector3(1.0, lerpf(2.4, 0.80, compression), 1.0)

	for i in flecks.size():
		var phase := float(i) * 2.399
		var spread := lerpf(0.62, 0.10, compression)
		flecks[i].position = Vector3(
			cos(phase) * spread * 1.5,
			sin(phase) * spread,
			OMEN_DISTANCE + 0.006
		)
		flecks[i].rotation.z = phase
		fleck_materials[i].albedo_color = Color(0.92, 0.94, 0.90, clampf(alpha * 0.42, 0.0, 1.0))
