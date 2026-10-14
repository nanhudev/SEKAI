extends Node3D
#
# VFX PROTOTYPE — what all eleven of these have in common, and nothing else.
#
# =============================================================================
# THE CONTRACT
# =============================================================================
#
#   `configure(lab)`   the lab hands itself over. Called once, before `build`.
#   `build()`          make whatever this prototype needs and add it to the
#                      scene. Called once. Nothing here may depend on time.
#   `apply(t)`         put the world into its state at ceremony time `t`.
#   `t_end()`          how long the clip is.
#   `phase_name(t)`    a word for what is happening, for the renderer's overlay
#                      and for the self-review. Never for logic — a prototype
#                      that branches on its own phase name has two owners of one
#                      decision.
#
# `apply(t)` IS A PURE FUNCTION OF `t`. This is the load-bearing rule of the whole
# round and it is not a style preference:
#
#   · The renderer must be able to ask for "t = 3.40" and get the frame that a
#     continuous take would have had at t = 3.40. If a prototype advances its own
#     state instead, then a still is a different picture from the same moment in
#     the clip — and the deliverable of this round IS the still.
#   · Holding a beat (the hero pause) is then free and exact: hold `t` and the
#     world stops without anything having to be told to stop.
#
# So a prototype stores NO time-dependent state between calls. It computes. If a
# value is needed next frame it is derived from `t` again, not cached.
#
# =============================================================================
# THE ONE THING PROTOTYPES DO SHARE
# =============================================================================
#
# Easing, and the phase helper. Eleven files each carrying their own copy of an
# ease curve is eleven chances for the same beat to feel different in two clips
# for no reason anyone can see. These are the project's own curves — the same ones
# `chain_ultimate_tuning.gd` uses — so a hold in 11 天地合页 lands like a hold in
# the chain ultimate.

## The lab. Set by `configure`.
var lab: Node3D = null

## How long this clip is. Overridden by every prototype; 10s is a placeholder that
## would be obvious.
var t_end := 10.0

## Everything a prototype builds goes under here, so `build` cannot accidentally
## add a node to the lab itself and have it survive a re-run.
var stage: Node3D = null


func configure(p_lab: Node3D) -> void:
	lab = p_lab


func build() -> void:
	stage = Node3D.new()
	stage.name = "Stage"
	add_child(stage)


func apply(_t: float) -> void:
	pass


func phase_name(_t: float) -> String:
	return ""


# =============================================================================
# TIME
# =============================================================================

## `t` mapped to 0..1 across [a, b]. Clamped, so a phase cannot run backwards
## past its own start or overshoot its own end and quietly invert an ease.
func span(t: float, a: float, b: float) -> float:
	if b <= a:
		return 1.0 if t >= b else 0.0
	return clampf((t - a) / (b - a), 0.0, 1.0)


## The same, unclamped — for the few places that want to know how far past the end
## something is.
func span_raw(t: float, a: float, b: float) -> float:
	if b <= a:
		return 0.0
	return (t - a) / (b - a)


func ease_in_out(u: float) -> float:
	var v := clampf(u, 0.0, 1.0)
	return v * v * (3.0 - 2.0 * v)


func ease_out_cubic(u: float) -> float:
	var v := clampf(u, 0.0, 1.0)
	return 1.0 - pow(1.0 - v, 3.0)


func ease_in_cubic(u: float) -> float:
	var v := clampf(u, 0.0, 1.0)
	return v * v * v


func ease_out_quint(u: float) -> float:
	var v := clampf(u, 0.0, 1.0)
	return 1.0 - pow(1.0 - v, 5.0)


## A rise and a fall, 0 -> 1 -> 0 across [a, b], peaking at the middle. The shape
## almost every "flash", "shock", "arc" and "kick" wants.
func pulse(t: float, a: float, b: float) -> float:
	var u := span(t, a, b)
	return sin(u * PI)


## A one-sided spike: instant rise, exponential fall. `decay(t, at, tau)`.
func decay(t: float, at: float, tau: float) -> float:
	if t < at:
		return 0.0
	return exp(-(t - at) / maxf(tau, 0.0001))


# =============================================================================
# DETERMINISTIC NOISE
# =============================================================================
#
# Shake, jitter and scatter have to be reproducible from `t` alone, so there is no
# `randf()` anywhere in this round. This is a cheap value hash with a seed, which
# is all any of these need.

func n1(seed: float, t: float) -> float:
	var v := sin(seed * 12.9898 + t * 78.233) * 43758.5453
	return v - floor(v)


func n_signed(seed: float, t: float) -> float:
	return n1(seed, t) * 2.0 - 1.0


## A smooth deterministic shake vector, for camera kick. `freq` in Hz.
func shake(seed: float, t: float, amount: float, freq := 26.0) -> Vector3:
	if amount <= 0.0:
		return Vector3.ZERO
	var p := t * freq
	return Vector3(
		sin(p * 1.0 + seed) * 0.6 + sin(p * 2.7 + seed * 1.7) * 0.4,
		sin(p * 1.31 + seed * 2.3) * 0.6 + sin(p * 3.1 + seed * 0.9) * 0.4,
		0.0) * amount


# =============================================================================
# THE CAMERA
# =============================================================================
#
# A prototype never touches a camera node. It says where the eye is and what it is
# looking at, and the lab does the rest — because the lab is the only thing that
# knows which camera is current, and a prototype that called `look_at` on the
# wrong one would render a perfectly correct shot of nothing.

func camera(eye: Vector3, look: Vector3, fov := 68.0, roll := 0.0) -> void:
	lab.cam_eye = eye
	lab.cam_look = look
	lab.cam_fov = fov
	lab.cam_roll = roll


## The first-person eye at eye height over a ground point, looking at `look`.
func fp_eye(x: float, z: float, height := 1.66) -> Vector3:
	return Vector3(x, lab.ground_height(x, z) + height, z)


## A point expressed in the EYE'S OWN FRAME: +x right, +y up, -z forward. Used by
## the prototypes that have to put something in the player's hand (07 星坠 presses
## a star into the palm, 10 锁链拖星 throws the chain out of it) — the hand is not at
## a world position, it is at a fixed offset from wherever the camera is, and
## computing it from the eye's basis is the only way that stays true when the
## camera moves. Must be called AFTER `camera()`, or it describes last frame's eye.
func eye_point(right: float, up: float, forward: float) -> Vector3:
	var e: Vector3 = lab.cam_eye
	var f: Vector3 = ((lab.cam_look as Vector3) - e).normalized()
	var r: Vector3 = f.cross(Vector3.UP).normalized()
	var u: Vector3 = r.cross(f)
	return e + r * right + u * up + f * forward


# =============================================================================
# SPAWNING
# =============================================================================

func add_mesh(mesh: Mesh, mat: Material, at := Vector3.ZERO, rot := Vector3.ZERO) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = mat
	node.position = at
	node.rotation_degrees = rot
	stage.add_child(node)
	return node


func add_box(size: Vector3, mat: Material, at := Vector3.ZERO, rot := Vector3.ZERO) -> MeshInstance3D:
	var m := BoxMesh.new()
	m.size = size
	return add_mesh(m, mat, at, rot)


## A world material from the lab's own shader family, so anything a prototype adds
## to the world can be carved and whitened along with the world.
func world_mat(color: Color, rough := 0.9, metallic := 0.0) -> ShaderMaterial:
	return lab._shader_mat(color, rough, metallic)


## A glow material. `fresnel` keeps a hairline visible when the eye is level with
## it; `travel` puts a moving highlight along the line's own U.
func glow(color: Color, intensity: float, fresnel := 0.0, travel := 0.0) -> ShaderMaterial:
	return lab.glow_mat(color, intensity, fresnel, travel)
