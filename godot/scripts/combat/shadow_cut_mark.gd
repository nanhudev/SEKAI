extends Node3D
class_name ShadowCutMark
# 无明一刻 · a cut that exists before it happens.
#
# PHASE MARK   a hair-thin white line appears on a valid target. It does
#              nothing. The point is that the world has not noticed it yet.
# PHASE ACTIVE every mark lights at the same instant, once, with a short
#              widening that reads as the cut opening.
# PHASE FADE   the line dissolves.

enum Stage { MARK, HOLD, ACTIVE, DONE }

const MARK_ALPHA := 0.42
const ACTIVE_ALPHA := 0.95

var stage: Stage = Stage.MARK
var timer := 0.0
var mark_in := 0.28
var hold := 0.30
var active_time := 0.16
var fade := 0.45
var line_length := 1.6
var line_material: StandardMaterial3D
var line: MeshInstance3D


func setup(length: float, tilt: float, tint: Color) -> void:
	line_length = length
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.012, length, 0.012)
	line_material = StandardMaterial3D.new()
	line_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	line_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	line_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	line_material.albedo_color = Color(tint.r, tint.g, tint.b, 0.0)
	mesh.material = line_material
	line = MeshInstance3D.new()
	line.name = "CutMark"
	line.mesh = mesh
	line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(line)
	rotation = Vector3(0.0, 0.0, tilt)


func activate() -> void:
	if stage == Stage.DONE:
		return
	stage = Stage.ACTIVE
	timer = 0.0


func _process(delta: float) -> void:
	timer += delta
	match stage:
		Stage.MARK:
			var u := clampf(timer / mark_in, 0.0, 1.0)
			_set_alpha(MARK_ALPHA * u)
			if u >= 1.0:
				stage = Stage.HOLD
				timer = 0.0
		Stage.HOLD:
			_set_alpha(MARK_ALPHA)
			if timer >= hold:
				pass
		Stage.ACTIVE:
			var u := clampf(timer / active_time, 0.0, 1.0)
			var alpha := lerpf(ACTIVE_ALPHA, MARK_ALPHA, u)
			_set_alpha(alpha)
			# A single widening beat: the cut opening, then closing again.
			var widen := 1.0 + sin(u * PI) * 2.6
			if line != null:
				line.scale.x = widen
				line.scale.z = widen
			if u >= 1.0:
				stage = Stage.DONE
				timer = 0.0
		Stage.DONE:
			var u := clampf(timer / fade, 0.0, 1.0)
			_set_alpha(MARK_ALPHA * (1.0 - u))
			if u >= 1.0:
				queue_free()


func _set_alpha(alpha: float) -> void:
	if line_material == null:
		return
	var c := line_material.albedo_color
	line_material.albedo_color = Color(c.r, c.g, c.b, alpha)
