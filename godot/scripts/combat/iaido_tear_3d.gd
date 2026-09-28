extends Node3D
class_name IaidoTear3D
# World-space pre-cut omen.
#
# V1 switched this full-width line on at the start of the reverse compression
# and left it up until the cut — nearly two seconds of a dark diagonal band
# lying across the whole frame. It stole the eye from the sheath mouth, which
# is where the entire anticipation is supposed to live, and it pre-empted the
# cut by showing the player where the world would break long before the blade
# did anything.
#
# V2 is a premonition, not an announcement: it exists for the last half second
# before the draw, it grows out from the centre of the future cut, it is
# thinner, and it dies the instant the real void opens.

const OMEN_DISTANCE := -1.2
const HALF_WIDTH := 1.8          # the plane is 3.6 wide; screen-covering at fov 75

var ivory_line: MeshInstance3D
var ink_line: MeshInstance3D
var flecks: Array[MeshInstance3D] = []
var fleck_materials: Array[StandardMaterial3D] = []
var ivory_material: StandardMaterial3D
var ink_material: StandardMaterial3D


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	ivory_line = _plane("Spatial Omen Ivory", Vector3(3.6, 0.006, 0.010), Color(1.0, 0.97, 0.88, 0.0), 0.0)
	ink_line = _plane("Spatial Omen Ink", Vector3(3.6, 0.018, 0.008), Color(0.02, 0.03, 0.05, 0.0), -0.008)
	ivory_material = ivory_line.mesh.material as StandardMaterial3D
	ink_material = ink_line.mesh.material as StandardMaterial3D
	for i in 6:
		var fleck := _plane("Omen Fleck %d" % i, Vector3(0.035, 0.009, 0.006), Color(0.92, 0.94, 0.90, 0.0), 0.006)
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
	# THE OMEN IS NOT A LINE.
	#
	# V1 held a full-width dark band across the frame for two seconds. V2 shrank
	# it to the last half second and thinned it, and it was still a dark ruled
	# line — the exact motif this pass exists to delete, and worse, it TAUGHT the
	# eye that a line means the cut, which is the opposite of the new language
	# where the cut is made of the world sliding out of register.
	#
	# It also sat squarely inside the absolute stillness. §I allows only "nearly
	# invisible spatial pressure" in that window, and a 0.29-alpha bar is not
	# nearly invisible.
	#
	# So: the dark component is gone entirely, the window starts at the sheath
	# click instead of half a second early, and what is left is a barely-there
	# ivory tightening of the air in the ~240ms between the click and the cut.
	# If you can see it clearly on a still frame, it is wrong.
	# THE OMEN BELONGS TO THE SPLIT ONSET, NOT TO THE DRAW.
	#
	# V6 ran it through the last tenth of a second before the cut, which was fine
	# when the cut happened the instant the blade left. It is not fine now: the
	# 0.24s between the draw and the world's reaction is a beat the design asks
	# to have NOTHING in it, and a line growing across it is the opposite of
	# nothing. A sliver that exists for the first tenth of a second of the split
	# does the same job — it puts the eye on the axis the world is about to move
	# along — without spending the delay.
	var start := tuning.cut_start
	var end := start + 0.14
	visible = time >= start and time < end
	if not visible:
		return
	# The cut runs up and to the right; in view space that is -cut_angle.
	var screen_angle := deg_to_rad(-tuning.cut_angle_degrees)
	rotation.z = screen_angle
	ivory_line.position.z = OMEN_DISTANCE
	ink_line.position.z = OMEN_DISTANCE - 0.01

	# It grows with the split rather than with the draw, so it is the same event
	# the shader is drawing rather than a second, earlier guess at it.
	var grow := IaidoTuning.ease_out_cubic(IaidoTuning.span(time, start, tuning.cut_end))
	# Grows out from the centre of the future cut rather than being laid over
	# the frame: the world is deciding where it is going to break.
	var length := lerpf(0.06, 0.86, grow)
	var death := 1.0 - IaidoTuning.span(time, start, end)
	# Steady, not flickering. The 9Hz sine that used to be here is "particle
	# spam" by another name and it broke the stillness it was sitting in.
	var alpha := grow * death

	ivory_material.albedo_color = Color(1.0, 0.97, 0.88, clampf(alpha * 0.11, 0.0, 1.0))
	# The dark line is deliberately invisible. Kept as a node so the flecks and
	# the transform plumbing do not have to change, but it draws nothing.
	ink_material.albedo_color = Color(0.02, 0.03, 0.05, 0.0)
	ivory_line.scale = Vector3(length * 0.92, lerpf(1.1, 0.55, grow), 1.0)
	ink_line.scale = Vector3(length * 0.78, lerpf(1.4, 0.70, grow), 1.0)

	for i in flecks.size():
		var phase := float(i) * 2.399
		var spread := lerpf(0.10, 0.40, grow)
		flecks[i].position = Vector3(
			cos(phase) * spread * length * HALF_WIDTH,
			sin(phase) * spread * 0.06,
			OMEN_DISTANCE + 0.006
		)
		flecks[i].rotation.z = phase
		fleck_materials[i].albedo_color = Color(0.92, 0.94, 0.90, clampf(alpha * 0.10, 0.0, 1.0))
