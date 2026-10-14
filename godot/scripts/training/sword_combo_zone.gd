extends Node3D
class_name SwordComboZone
# THE SWORD COMBO TEST ZONE (§31).
#
# ===========================================================================
# WHY IT IS BUILT FROM THE MOVE DATA AND NOT FROM A LIST OF POSITIONS
# ===========================================================================
#
# The four beats of the basic sentence are told apart by DISTANCE. A zone that
# hard-codes 2m / 7m / 15m is a zone that goes quietly wrong the first time the
# sentence is retuned: the mid target would sit closer than A2's own reach and
# the "A2 hits at range" check would start passing for the wrong reason, then
# stop passing, and nobody would know which number had moved.
#
# So every distance here is DERIVED from the move that has to reach it, and the
# derivation is a fraction of that move's own authored range. Retune A2's reach
# and its target follows it.
#
# ===========================================================================
# AND WHY THERE ARE NEGATIVE CONTROLS
# ===========================================================================
#
# Feel V2 negative controls: far/off_axis lie beyond A2's wave, and behind
# lies outside A4's major arc. A3 now contacts the near target with its body box.
#
# A test zone with only positive examples cannot tell a mechanic from a bigger
# hitbox, which is the entire subject of this sentence.
#
# ===========================================================================
# WHAT A TARGET IS HERE
# ===========================================================================
#
# A target, NOT an opponent. The training dummy's AI is switched OFF rather than
# merely out-valued: a dummy that fights back during a combo test introduces a
# second source of motion, and then a miss could be the player's fault, the
# dummy's fault, or a stagger, and the measurement stops meaning anything. The
# hurtbox stays fully live — that is the only part being measured.

## The same dummy the game fights with. A test zone that spawns special test
## bodies is a test zone that cannot tell you anything about the real one.
const DUMMY_SCENE := preload("res://scenes/enemies/TechnicalDummy.tscn")

## The nearest target stands a little past A1's own box, so "A1 is arm's length"
## is a claim about the body and not about the arena's spacing.
const NEAR_FACTOR := 1.45
## Inside A2's reach, comfortably: the wave has to arrive, not to just barely
## stop short of it.
const MID_FACTOR := 0.83
## Beyond A2's reach: far targets must survive the body-led A3 uppercut.
const FAR_MARGIN := 3.0
## Inside A4's radius. The sweep has to reach it with room to spare, because the
## interesting failure is the arc being too narrow, not too short.
const SURROUND_FACTOR := 0.78
## Inset from the arc's endpoints so a rounding error at the very edge cannot
## turn a legitimate miss into a failure.
const SURROUND_INSET_DEG := 12.0
## How far outside the arc the negative control stands.
const BEHIND_MARGIN_DEG := 40.0
## And how far off the front axis the other negative control stands.
const OFF_AXIS_DEG := 60.0

## Faint ground rings naming each distance. §31 allows them "非常淡" and requires
## them to be hideable, because a debug ring in the delivery video is a debug
## ring in the delivery video.
@export var show_debug := true
## Ring colour. Pale and cold, the same family as the VFX palette — the zone must
## not introduce a second colour language into a frame that is about the sword.
@export var debug_color := Color(0.42, 0.62, 0.74, 0.16)
@export var ring_segments := 64

var _targets: Dictionary = {}
var _rings: Array[MeshInstance3D] = []
var _origin := Vector3.ZERO


## Spawns the zone around `eye`. Idempotent: calling it twice moves the targets
## rather than doubling them, because a stage that rebuilds on RESET must not
## leave the previous nine bodies standing there.
func build(eye: Node3D) -> void:
	if eye == null:
		return
	_origin = eye.global_position
	var a1 := SwordBasic.a1()
	var a2 := SwordBasic.a2()
	var a3 := SwordBasic.a3()
	var a4 := SwordBasic.a4()

	_place(&"near", _origin + Vector3.FORWARD * (absf(a1.hitbox_offset.z) * NEAR_FACTOR))
	_place(&"mid", _origin + Vector3.FORWARD * (a2.reach * MID_FACTOR))
	# Feel V2 A3 is a body uppercut. Far/off-axis now remain negative controls
	# beyond the retained A2 wave rather than collapsing to the player's feet.
	var far_distance := a2.reach + FAR_MARGIN
	_place(&"far", _origin + Vector3.FORWARD * far_distance)
	_place(&"off_axis", _origin + _polar(OFF_AXIS_DEG, far_distance))

	# The four the sweep has to catch, spread across the authored arc rather than
	# at round numbers.
	var radius := a4.reach_radius * SURROUND_FACTOR
	var low := a4.reach_arc_from + SURROUND_INSET_DEG
	var high := a4.reach_arc_to - SURROUND_INSET_DEG
	var count := 4
	var angles: Array[float] = []
	for i in count:
		angles.append(low + (high - low) * float(i) / float(count - 1))
	for i in count:
		_place(StringName("surround_%d" % i), _origin + _polar(angles[i], radius))
	# ...AND THE ONE THAT MUST SURVIVE. Just outside the arc's own start angle.
	_place(&"behind", _origin + _polar(a4.reach_arc_from - BEHIND_MARGIN_DEG, radius))

	_build_rings(a4.reach_radius * SURROUND_FACTOR, a2.reach * MID_FACTOR, far_distance)
	set_clean(not show_debug)


## Every target, in no particular order.
func all_targets() -> Array[Node3D]:
	var out: Array[Node3D] = []
	for key in _targets:
		var body: Node3D = _targets[key]
		if is_instance_valid(body):
			out.append(body)
	return out


## One named target, or null.
func target(id: StringName) -> Node3D:
	return _targets.get(id) as Node3D


## The four the sweep must catch.
func surround_targets() -> Array[Node3D]:
	var out: Array[Node3D] = []
	for key in _targets:
		if String(key).begins_with("surround_") and is_instance_valid(_targets[key]):
			out.append(_targets[key])
	return out


## Hides or shows the ground rings. §31's Clean Mode.
func set_clean(clean: bool) -> void:
	for ring in _rings:
		if is_instance_valid(ring):
			ring.visible = not clean


func clear() -> void:
	for key in _targets:
		var body: Node3D = _targets[key]
		if is_instance_valid(body):
			body.queue_free()
	_targets.clear()


# ---------------------------------------------------------------- internals

## A point at `degrees` from the player's forward, positive toward the player's
## right, `radius` metres out.
func _polar(degrees: float, radius: float) -> Vector3:
	var rad := deg_to_rad(degrees)
	# Camera space: +X right, forward is -Z. `sin` toward +X, `cos` toward -Z.
	return Vector3(sin(rad) * radius, 0.0, -cos(rad) * radius)


func _place(id: StringName, where: Vector3) -> void:
	var body: Node3D = _targets.get(id) as Node3D
	if not is_instance_valid(body):
		body = DUMMY_SCENE.instantiate()
		body.name = "Target_" + String(id)
		add_child(body)
		_targets[id] = body
		_arm(body)
	# The convention every other stage in this project already uses: a body is
	# spawned at the player's own height and the arena floor is assumed flat
	# between them.
	# The actor origin is its feet, while the player's origin is capsule centre.
	body.global_position = Vector3(where.x, 0.10, where.z)
	# Face the player, so a silhouette in the frame is a body and not a plate.
	var facing := Vector3(_origin.x, body.global_position.y, _origin.z)
	if body.global_position.distance_squared_to(facing)>0.000001:
		body.look_at(facing,Vector3.UP)


## Turns a dummy into a target: AI off, and no death.
##
## The AI is switched off rather than tuned down, and the health is raised rather
## than made invulnerable-because-damage-is-ignored: a body that dies mid-combo
## would remove the thing the next beat is supposed to hit, and then beat four
## would fail because beat one worked.
func _arm(body: Node3D) -> void:
	body.set_process(false)
	body.set_physics_process(false)
	body.set("max_health", 1.0e9)
	body.set("health", 1.0e9)
	body.set("poise_limit", 1.0e9)


# --- the rings ------------------------------------------------------------
#
# Built as lines rather than as a torus: a `TorusMesh` is a solid and needs a
# material to be faint, and this needs to be faint at the geometry level so an
# unshaded material and an alpha budget cannot turn it into a bright band.

func _build_rings(surround_r: float, mid_r: float, far_r: float) -> void:
	if not _rings.is_empty():
		return
	_ring(surround_r, 3.0)
	_ring(mid_r, 0.7)
	_ring(far_r, 0.7)


func _ring(radius: float, weight: float) -> void:
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	var color := Color(
		debug_color.r, debug_color.g, debug_color.b,
		clampf(debug_color.a * weight, 0.0, 1.0)
	)
	var steps := maxi(ring_segments, 12)
	for i in steps:
		var a0 := TAU * float(i) / float(steps)
		var a1 := TAU * float(i + 1) / float(steps)
		mesh.surface_set_color(color)
		mesh.surface_add_vertex(_ring_point(radius, a0))
		mesh.surface_set_color(color)
		mesh.surface_add_vertex(_ring_point(radius, a1))
	mesh.surface_end()

	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.vertex_color_use_as_albedo = true
	# A ring lying on the floor must not cast: it sits a few millimetres above the
	# surface and a shadow from it is a dark band under a debug circle. Set on the
	# instance rather than on the material, because the compatibility renderer
	# remaps a material's own `cast_shadow` and warns about it.
	material.cull_mode = BaseMaterial3D.CULL_DISABLED

	var node := MeshInstance3D.new()
	node.name = "DebugRing_%0.1f" % radius
	node.mesh = mesh
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	_rings.append(node)


func _ring_point(radius: float, angle: float) -> Vector3:
	return Vector3(
		_origin.x + cos(angle) * radius,
		_origin.y + 0.015,
		_origin.z + sin(angle) * radius
	)
