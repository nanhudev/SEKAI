extends Node
class_name CameraFeedbackController

enum Preset { NORMAL, EXAGGERATED, OFF }

@export var base_fov := 75.0
@export var settle_speed := 9.0
@export var trauma_decay := 1.8
@export_range(0.0, 2.0, 0.05) var camera_motion_strength := 1.0
@export_range(0.0, 2.0, 0.05) var camera_shake_strength := 1.0

@onready var player: CharacterBody3D = get_parent()
@onready var motion_pivot: Node3D = player.get_node("CameraRig/LookPivot/MotionPivot")
@onready var shake_pivot: Node3D = player.get_node("CameraRig/LookPivot/MotionPivot/ShakePivot")
@onready var camera: Camera3D = player.get_node("CameraRig/LookPivot/MotionPivot/ShakePivot/Camera3D")

var impulse := Vector2.ZERO
var trauma := 0.0
var fov_offset := 0.0
var fov_hold := 0.0
var iaido_pitch := 0.0
var iaido_frozen := false
# 0 = normal combat feedback, 1 = the fight has stopped breathing (Iaido).
# Bob, sway, gait and micro tremor are all scaled away, but the cinematic
# iaido_pitch and iaido_frame survive so the director can still move us.
var iaido_still := 0.0
var iaido_frame := Vector2.ZERO
var roll := 0.0
var noise_time := 0.0
var preset := Preset.NORMAL
var gait_phase := 0.0
var gait_weight := 0.0
var step_pulse := 0.0
var sprint_fov := 0.0
var look_lag := Vector2.ZERO
var velocity_lag := Vector3.ZERO
var smoothed_position := Vector3.ZERO
var smoothed_rotation := Vector3.ZERO


func cycle_preset() -> String:
	preset = (preset + 1) % 3
	return preset_name()


func preset_name() -> String:
	match preset:
		Preset.EXAGGERATED: return "Exaggerated"
		Preset.OFF: return "Off"
		_: return "Normal"


func on_mouse_look(delta_radians: Vector2) -> void:
	look_lag += delta_radians
	look_lag = look_lag.limit_length(0.25)


func add_impulse(direction: Vector2, strength: float = 1.0) -> void:
	impulse += direction * strength


func add_trauma(amount: float) -> void:
	trauma = clampf(trauma + amount, 0.0, 1.0)


func add_iaido_frame(direction: Vector2, strength: float = 1.0) -> void:
	# A cinematic nudge that is NOT suppressed by iaido_still.
	#
	# DEPRECATED — NOTHING CALLS THIS ANY MORE. `iaido_frame` is now ASSIGNED
	# from the Iaido timeline every frame instead of being accumulated here.
	# Accumulating it decayed on real frame delta, which meant the Iaido camera
	# kept settling through a time stop that is supposed to freeze it mid-move,
	# and it made the frame a function of wall time so two renders of the same
	# ceremony instant differed — a frozen window could never then be proven
	# frozen. Do not reintroduce an accumulator; assign `iaido_frame` instead.
	iaido_frame += direction * strength


func set_iaido_still(amount: float) -> void:
	iaido_still = clampf(amount, 0.0, 1.0)


func fov_kick(degrees: float) -> void:
	fov_offset += degrees


# A SUSTAINED offset, as opposed to a kick. A system that holds a state (缚星链's
# orbit) sets this while the state lasts and clears it when it ends. Feeding an
# event into fov_offset was not an option: that accumulator decays at
# settle_speed, so calling it every frame would have made the orbit's FOV
# pressure depend on the framerate.
var sustain_fov := 0.0


func roll_impulse(degrees: float) -> void:
	roll += deg_to_rad(degrees)


func _ready() -> void:
	# The body owns landing now (§25). Subscribing rather than re-detecting means
	# there is exactly one idea of "that was a landing" in the game, and anything
	# else that reacts to it — weapon, footstep audio — reacts to the same frame.
	if player.has_signal("landed"):
		player.landed.connect(_on_landed)


func _on_landed(_impact_speed: float, tier: StringName) -> void:
	var weight: float = {&"light": 0.45, &"medium": 1.0, &"heavy": 1.7}.get(tier, 1.0)
	landing_impulse(weight)


func landing_impulse(strength: float = 1.0) -> void:
	add_impulse(Vector2(0.0, 0.035), strength)
	add_trauma(0.08 * strength)


func _process(delta: float) -> void:
	# THE CEREMONY CLOCK IS OFF: NOTHING INTEGRATES, BUT THE POSE IS STILL
	# WRITTEN.
	#
	# This used to `return`, which pinned the frame by leaving the last pose in
	# place. That worked for the hero freeze frame and broke the time stops: the
	# director writes motion_pivot from inside this function, so an early return
	# also stopped the director's own camera moves from landing. Zeroing the
	# delta instead freezes every accumulator — bob, sway, tremor, trauma decay,
	# the cinematic `iaido_frame` impulse, `noise_time` — while still applying
	# the pose those frozen values describe. Same still frame, no blind spot.
	if iaido_frozen:
		delta = 0.0
	noise_time += delta * 27.0
	var decay := minf(1.0, settle_speed * delta)
	impulse = impulse.lerp(Vector2.ZERO, decay)
	# `iaido_frame` is NOT decayed here. The Iaido director assigns it from its
	# own timeline (three impulses, eased on ceremony time), and decaying it here
	# as well would both fight that assignment and leak wall time back into a
	# frame that has to be a pure function of the ceremony clock.
	fov_offset = lerpf(fov_offset, 0.0, decay)
	roll = lerpf(roll, 0.0, decay)
	look_lag = look_lag.lerp(Vector2.ZERO, minf(1.0, delta * 11.0))
	trauma = maxf(0.0, trauma - trauma_decay * delta)
	step_pulse = move_toward(step_pulse, 0.0, delta * 0.55)

	var horizontal_speed := Vector2(player.velocity.x, player.velocity.z).length()
	var grounded := player.is_on_floor()
	var sprinting := grounded and horizontal_speed > 1.0 and Input.is_action_pressed("sprint")
	var moving := grounded and horizontal_speed > 0.35
	# While the Iaido holds the world still, the gait itself unwinds so the
	# camera does not snap back to a bob the moment the skill ends.
	var still_weight := 1.0 - clampf(iaido_still, 0.0, 1.0)
	gait_weight = lerpf(gait_weight, (minf(1.0, horizontal_speed / 3.5) if moving else 0.0) * still_weight, minf(1.0, delta * 8.0))
	if moving:
		var old_step := floori(gait_phase / PI)
		gait_phase += delta * (15.0 if sprinting else 10.0)
		if floori(gait_phase / PI) > old_step:
			step_pulse = 0.028 if sprinting else 0.012

	var motion_scale := camera_motion_strength
	var gait_scale := 2.0 if sprinting else 1.0
	var local_velocity := player.global_basis.inverse() * player.velocity
	velocity_lag = velocity_lag.lerp(local_velocity, minf(1.0, delta * 7.0))
	var velocity_error := local_velocity - velocity_lag
	var target_position := Vector3(
		sin(gait_phase) * 0.018 * gait_weight * gait_scale - velocity_error.x * 0.002,
		-abs(sin(gait_phase)) * 0.025 * gait_weight * gait_scale - step_pulse,
		-velocity_error.z * 0.002
	)
	var target_rotation := Vector3(
		sin(gait_phase * 2.0) * 0.016 * gait_weight * gait_scale + step_pulse * 0.25 + look_lag.y * 0.10,
		sin(gait_phase) * 0.007 * gait_weight + look_lag.x * 0.06,
		sin(gait_phase) * 0.018 * gait_weight * gait_scale - local_velocity.x * 0.002
	)
	if sprinting:
		target_rotation.x += sin(gait_phase * 3.0) * 0.0015
	smoothed_position = smoothed_position.lerp(target_position, minf(1.0, delta * 13.0))
	smoothed_rotation = smoothed_rotation.lerp(target_rotation, minf(1.0, delta * 12.0))
	sprint_fov = lerpf(sprint_fov, 4.5 if sprinting else 0.0, minf(1.0, delta * 7.0))

	var feedback_scale := 3.0 if preset == Preset.EXAGGERATED else (0.0 if preset == Preset.OFF else 1.0)
	var still := 1.0 - clampf(iaido_still, 0.0, 1.0)
	var combat_rotation := smoothed_rotation * motion_scale + Vector3(impulse.y, impulse.x, roll) * feedback_scale * camera_shake_strength
	motion_pivot.position = smoothed_position * motion_scale * still
	motion_pivot.rotation = combat_rotation * still + Vector3(iaido_pitch + iaido_frame.y, iaido_frame.x, 0.0)
	var shake := trauma * trauma * 0.018 * feedback_scale * camera_shake_strength
	shake_pivot.position = Vector3(sin(noise_time * 1.7), cos(noise_time * 2.1), 0.0) * shake * still
	# The Iaido FOV push is a cinematic direction, not feedback, so it ignores
	# the camera preset. A player on "Off" still gets the full performance.
	camera.fov = base_fov + fov_hold + fov_offset * feedback_scale + sprint_fov * motion_scale * still + sustain_fov
