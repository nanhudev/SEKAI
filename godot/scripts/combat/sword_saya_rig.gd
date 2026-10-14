extends Node3D
class_name SwordSayaRig
# SEKAI · THE SECOND WEAPON ACTOR
#
# ===========================================================================
# THE OFF HAND IS NOT A PROP HOLDER
# ===========================================================================
#
# §21 is the requirement: the saya is a SECONDARY WEAPON ACTOR, not decoration.
# The sword line's whole identity is that the blade and the sheath are in a
# relationship — A1 opens by putting the blade back on the mouth and drawing it
# out again, A3 puts it home for real, and the weapon switch has to sheathe it
# before the sword can be put away. A version of this where the off hand holds a
# static mesh would make all three of those a lie about a picture.
#
# So this node is a small actor with one job and one input: WHERE THE SWORD IS.
# It has no state machine, because a scabbard has no opinions.
#
# ===========================================================================
# ALIGNMENT IS AN IDENTITY, NOT A DERIVATION (and this used to be wrong)
# ===========================================================================
#
# The seating is true by CONSTRUCTION, which is worth stating plainly because
# the code that used to be here tried to make it true by ARITHMETIC and lost:
#
#   mouth = sword_origin + sword_up * tsuba_mouth_y     (Registry)
#
# `tsuba_mouth_y` is the sword's own measurement of where its tsuba's mouth face
# is, and the saya's model is authored with its origin ON the mouth plane. So the
# two are one point, written twice — and if the sword is sitting at the anchor
# every seating beat is written at, the arithmetic returns that same point.
#
# WHICH IS THE POINT, AND ALSO THE PROBLEM. The derivation is only the mouth
# while the blade is IN the saya. Everywhere else it is the mouth-shaped point
# attached to a sword that has left, and the old code weighed it in by proximity
# — follow the blade once its root is within 16 cm of the anchor. Measured by
# `tools/probe_saya_motion.gd` on a live session, during an A1/A2/A3/A4 that
# bought **0.20-0.22 m of scabbard travel per cut**, wandering up to 63 mm off
# home and snapping in single updates of up to 76 mm. It bought nothing in
# return: at every instant the seating actually has to be true, the derived
# answer and the anchor's own answer are the same number.
#
# So the mouth is a FIXITY. A scabbard held in a hand is a point that does not
# go anywhere, and the blade is the actor that travels through it. The authored
# beats below are the only thing that ever moves it, and they are the draw —
# where the off hand really is doing something.
#
# (The one place a derivation would still be needed is a style that seats the
# blade somewhere other than the anchor. 藏锋 does exactly that, and it brings
# its own scabbard for it — see `CombatController._saya_has_the_stage`, which
# stands this whole rig down for that style. There is no frame in which this rig
# is on screen and the seating anchor is not the answer.)

## A hand's width. Kept as documentation of the gate that used to be here and the
## reason it is gone: proximity is not seatedness, and 16 cm of it was 63 mm of
## visible wander per cut.
const SEAT_FOLLOW_WAS := 0.16

## Where the saya sits when the sword is NOT in hand: lower, further back and
## further left than the combat position, because it is on a hip rather than in a
## raised left hand (§2's "Saya at left waist"). Reached only through `presence`,
## which is 1.0 in every frame this rig is on stage today — the draw's own beats
## cover the whole of the window where it is not.
const WAIST_OFFSET := Vector3(-0.055, -0.115, 0.075)

## The sword-class registry. Preloaded rather than named because it carries no
## `class_name` — it is read as a table, which is what it is.
const SwordClasses := preload("res://scripts/weapons/sword_classes.gd")

const LACQUER := Color(0.115, 0.105, 0.125)
const KOIGUCHI := Color(0.62, 0.54, 0.33)
const KURIKATA := Color(0.66, 0.58, 0.36)
## Memory's hard rule for this project: a `metallic` above ~0.35 with no
## reflection source renders as a black silhouette. The fittings are small and
## are the only bright parts of a very dark object, so they are kept well under.
const FITTING_METALLIC := 0.30

var weapon_id: StringName = &"iaito"

## 0 = the saya is on the hip and the sword is somewhere else; 1 = the saya is in
## the raised left hand, paired with the blade. Written by the WeaponManager's
## draw / sheathe sequence (§2's E0–E3).
var presence := 1.0
## The off hand's own exertion this frame, 0..1 — `SwordBasic.saya_pull`.
##
## NOT SPENT, AND THAT IS THE FIX. It used to slide the whole scabbard along its
## own axis by up to 75 mm, which was meant to read as "the mouth being pulled
## while the blade also moves" and measured as an invisible 41 mm traverse in and
## out during a single A1. A hand squeezing a scabbard does not displace it 7 cm;
## the number is still written here because it is a true statement about the off
## hand and the audio and the trail may yet want it, but nothing about the saya's
## POSE reads it.
var pull := 0.0

var _body: Node3D
var _placeholder: Node3D = null

## THE HAND. `SayaHandDriver`, a sibling under `WeaponRoot`. When it is present
## the scabbard's rest pose is read from it and the scabbard inherits a body's
## breath and inertia for free. When it is absent the rig falls back to the fixed
## rest, which is what every probe written before the hand existed expects.
var hand: Node3D = null

## The move's own small request for this frame — see `SwordMove.saya_ctrl_*`.
## `control_weight` is 0 for every act that asks for nothing, which is most of
## them, and the whole offset is scaled by it so "no request" is exactly no change
## rather than a request for zero.
var control_pos := Vector3.ZERO
var control_rot := Vector3.ZERO
var control_weight := 0.0

# The rest pose, DERIVED from the sentence's own anchor so that "at rest" and
# "fully seated" are the same pose. See the header: this is the reason the saya
# needs no state and no per-beat data.
var _rest_pos := Vector3.ZERO
var _rest_basis := Basis.IDENTITY
var _tsuba_mouth_y := 0.0042
var _body_len := 0.803


func _ready() -> void:
	_body = Node3D.new()
	_body.name = "SayaBody"
	add_child(_body)
	_install()


## Rebuilds the saya for a sword class. Called at setup and whenever the weapon
## changes; a saya sized for one blade does not fit another.
func set_weapon(id: StringName) -> void:
	weapon_id = id
	_tsuba_mouth_y = SwordClasses.guard_setback(id)
	_body_len = SwordClasses.saya_body_len(id)
	_rest_basis = Basis.from_euler(SwordBasic.SAYA_MOUTH_R)
	# The mouth rests exactly where the sword's tsuba face is when the sword is at
	# the sentence's touch anchor — because it is THE SAME EXPRESSION the anchor
	# beats are written with. `SwordBasic.saya_home()` takes the id so a second
	# sword class cannot silently inherit the first one's tsuba.
	_rest_pos = SwordBasic.saya_home(weapon_id)
	_install()


func _install() -> void:
	if _body == null:
		return
	for child in _body.get_children():
		child.queue_free()
	# The real scabbard when its row names a file that exists. A registry entry
	# pointing at a missing GLB is worse than no registry at all, so the check is
	# the row's own `assets_present` and the fallback is whole.
	var path := SwordClasses.scabbard_path(weapon_id)
	if ResourceLoader.exists(path):
		var scene := load(path) as PackedScene
		if scene != null:
			var real := scene.instantiate()
			real.name = "SayaReal"
			# Identity, and that is the point: the model is authored with its
			# origin on the mouth plane, so the node that means "the mouth" and
			# the node that means "the scabbard" are the same node.
			real.transform = Transform3D.IDENTITY
			_body.add_child(real)
			_placeholder = null
			return
	_build_placeholder()


## The fallback. Long and thin, dark, with two fittings — enough to read as a
## scabbard in the one place it is ever seen, which is the lower left of a
## first-person frame.
func _build_placeholder() -> void:
	var group := Node3D.new()
	group.name = "SayaPlaceholder"
	_body.add_child(group)
	_placeholder = group
	var half_w := maxf(SwordClasses.saya_mouth_outer(weapon_id).x, 0.018) * 0.5
	var half_t := maxf(SwordClasses.saya_mouth_outer(weapon_id).y, 0.012) * 0.5
	_add_box(group, "SayaShell", Vector3(half_w, _body_len * 0.5, half_t),
		Vector3(0.0, _body_len * 0.5, 0.0), LACQUER, 0.0)
	# The koiguchi: the one fitting the player actually looks at, because it is
	# the thing the blade touches.
	_add_box(group, "Koiguchi", Vector3(half_w * 1.22, 0.013, half_t * 1.22),
		Vector3(0.0, 0.010, 0.0), KOIGUCHI, FITTING_METALLIC)
	_add_box(group, "Kurikata", Vector3(half_w * 0.55, 0.009, half_t * 2.1),
		Vector3(0.0, _body_len * 0.14, half_t * 0.9), KURIKATA, FITTING_METALLIC)


func _add_box(parent: Node3D, box_name: String, half: Vector3, offset: Vector3,
		tint: Color, metallic: float) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = half * 2.0
	var material := StandardMaterial3D.new()
	material.albedo_color = tint
	material.metallic = metallic
	material.roughness = 0.55
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.name = box_name
	instance.mesh = mesh
	instance.position = offset
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)
	return instance


# ===========================================================================
# The one input: where the saya lives
# ===========================================================================
#
# The sword's pose is no longer an argument to anything here, and the signature
# says so. It used to be, and the cost of that being wrong is in the header: a
# held scabbard that is placed relative to a blade is a scabbard that moves when
# the blade does, which is the exact opposite of what a scabbard is.

## Puts the mouth where the seating anchor says it is. Called every frame the
## sheath is on stage and no move has authored beats for it — which is every cut
## in the game, since a cut has nothing to say about a scabbard.
##
## `presence` still moves it between the hip and the off hand, which is what the
## field has always meant. It is 1.0 in every frame reachable today — the draw's
## own beats cover the whole window in which it climbs — and it is kept because
## the meaning is real and a style that hides the blade without taking the saya
## up would otherwise silently weld the scabbard to the waist.
##
## ===========================================================================
## AND IT IS PLACED FROM THE HAND, NOT FROM A CONSTANT
## ===========================================================================
## `hand` is the left hand's control point — see `SayaHandDriver`. When it is
## present the scabbard's base pose IS the hand's, which is the entire difference
## between a held object and an object parked at a coordinate: the hand carries
## the breath and the body's inertia, so the scabbard inherits both without a
## line of code here knowing what either is.
##
## `control_pos` / `control_rot` are the move's own small request (§7-§17), in
## the camera frame: metres and radians, zero for every act that has nothing to
## ask. They are deliberately not smoothed. An authored offset has already been
## designed, and the thing that used to degrade authored poses was a filter, not
## a lack of one.
##
## THEY ARE APPLIED TO THE HAND, NOT HERE. `CombatController._drive_hand` folds
## them into the hand's own base pose, so the scabbard reads a hand that is
## already where the act asked for and the arm solved onto that hand comes with
## it. This function only applies them itself in the no-hand fallback -- see the
## guard below, and `_drive_hand` for the measurement that moved them.
func seat_home() -> void:
	var pos := _rest_pos
	var basis := _rest_basis
	var from_hand := hand != null and is_instance_valid(hand)
	if from_hand:
		pos = hand.position
		basis = hand.basis
	# ...and the hip, which is the same offset the field has always carried,
	# expressed against the hand instead of against the fixed rest.
	pos += WAIST_OFFSET * (1.0 - presence)
	if control_weight > 0.0 and not from_hand:
		# ONLY WHEN THERE IS NO HAND. With one, the act's offset is carried by the
		# HAND -- see `CombatController._drive_hand`, which folds it into this
		# node's `base_position`. Applying it here as well would count it twice.
		#
		# This branch is what a probe with no `SayaHandDriver` falls back to, and
		# keeping it is why `control_pos` is still read here at all: the offset is
		# the MOVE's request, and where it is applied is a separate decision from
		# what it is. The two answers are the same transform -- the difference is
		# whether the arm that is solved onto the hand comes with it.
		basis = Basis.from_euler(control_rot * control_weight) * basis
		pos += control_pos * control_weight
	transform = Transform3D(basis, pos)


## Where the saya's mouth is, in the WeaponRoot's space. The test zone asserts
## against this rather than against a screenshot, because "the blade is in the
## sheath" is a distance and not a vibe.
func mouth_point() -> Vector3:
	return transform.origin


# ===========================================================================
# THE CHOREOGRAPHED POSE (§2: the sheath is a second actor)
# ===========================================================================
#
# `seat_home` above is the REST: the mouth in the off hand, going nowhere. It is
# the right answer for every cut in the game, because a cut has nothing to ask of
# a scabbard — the blade comes back to the mouth and leaves again, and both of
# those are the BLADE's travel through a point that never moved.
#
# It is the wrong answer for exactly one act, and that act is the draw. There the
# saya is not resting: it is being lifted by the off hand, held still against a
# blade sliding out of it, and pushed back the other way. None of those three is
# a function of where the blade is — the hold is specifically a stretch of time
# in which the blade moves and the saya does not — so nothing derived can express
# them and no scalar blend can either.
#
# So the equip-family moves author the sheath's poses directly, on the same clock
# and the same beat list as the blade (`SwordMove.saya_positions`), and this is
# the door they come in through. When a move has no saya beats, the caller uses
# `seat_home` and every cut in the game is untouched.
func place_absolute(position: Vector3, rotation: Vector3) -> void:
	transform = Transform3D(Basis.from_euler(rotation), position)


## How far the saya's mouth is from the sword's own mouth plane. Zero means the
## blade is home; the acceptance sheet prints this for A1's touch and A3's
## sheathe so a bad frame is a number rather than an opinion.
func seat_error(sword_position: Vector3, sword_rotation: Vector3) -> float:
	var sword_basis := Basis.from_euler(sword_rotation)
	return mouth_point().distance_to(sword_position + sword_basis * Vector3.UP * _tsuba_mouth_y)


func using_real_asset() -> bool:
	return _placeholder == null
