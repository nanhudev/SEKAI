extends Node3D
class_name SayaReviewBody
##
## A THIRD-PERSON BODY, FOR REVIEW ONLY. Not art, not shipped, not in any scene.
##
##   §30  "Body Mechanics -- 至少第三人称同步修 Left Arm"
##   §32  "...全屏 Third Person >= 2 机位"
##
## ===========================================================================
## WHY THERE IS NOTHING TO PHOTOGRAPH
## ===========================================================================
## Both of those ask for a body, and the project does not have one. Confirmed by
## reading the scene rather than assuming it: `scenes/player/Player.tscn` is a
## `CharacterBody3D` with a capsule collider, a `CameraRig` and a `WeaponRoot`.
## There is no mesh anywhere under the player. Every sword fix of the last four
## passes has therefore been a fix to a HAND THAT HAS NEVER BEEN DRAWN, and
## "does the hand read as holding the scabbard" has never been a question anyone
## could answer by looking.
##
## So this node is the cheapest thing that makes the question askable: a torso, a
## head and two arms, built from `CylinderMesh` and `SphereMesh` at runtime. It is
## a REVIEW INSTRUMENT in the same sense `probe_saya_control.gd` is one.
##
## ===========================================================================
## IT IS PARENTED TO `CameraRig` AND THAT PLACEMENT IS THE WHOLE DESIGN
## ===========================================================================
##   Player       position + YAW        <- the body faces where the player faces
##   CameraRig    (0, 0.65, 0)          <- no rotation of its own
##   LookPivot    PITCH                 <- the HEAD pitches; the body must not
##   MotionPivot  bob                   <- neither does it bob
##   ShakePivot   recoil/shake
##   Camera3D
##
## So the body hangs off `CameraRig`: it inherits the player's facing and the
## eye's height, and it is deliberately deaf to everything below `LookPivot`.
## Parenting it under `LookPivot` -- which is where all the weapon code points --
## would pitch the torso with the mouse, and a torso that pitches with the mouse
## is a torso that reads as camera-attached no matter what the arms do.
##
## ===========================================================================
## THE ARMS ARE SOLVED TO THE RIG'S OWN HAND POINTS, NOT ANIMATED
## ===========================================================================
## `SayaHandDriver` is the left hand (see its header). It is a child of
## `WeaponRoot` at identity, so `global_position` is exactly the point the
## scabbard's mouth is held at -- the point the whole of §1 is about. The arm's
## job here is to be the visible half of that same object: its wrist is SOLVED
## onto the hand point every frame, so the arm cannot disagree with the scabbard
## and a fix to one is a fix to both.
##
## The right wrist is solved onto `TempSwordVisual.global_position`, which is the
## sword's own rendered grip.
##
## ===========================================================================
## AND THE REACH IS REPORTED, BECAUSE THE ANSWER IS NOT "YES"
## ===========================================================================
## A human upper arm plus forearm is 0.57 m. The rig's scabbard rests at
## `SwordBasic.saya_home()` = mouth (-0.40, -0.40, -0.86) in WeaponRoot space,
## and WeaponRoot's origin is the eye. That is 0.86 m in FRONT of the eye, and
## the number `reach_report()["left_shortfall"]` says how far short the arm is.
##
## The arm is NOT stretched to hide it. Standard IK clamping is used -- the arm
## points at the target, fully extended, and the hand stops at the end of its
## reach -- so the picture shows a straight arm reaching for a scabbard it cannot
## touch, and the caption carries the millimetres. A first-person framing choice
## (hold the scabbard inside the lower edge of frame) is not an anatomy, and the
## only way that ever gets noticed is if a body is drawn beside it.

## Where the body sits, in `CameraRig` space -- i.e. relative to the EYE, since
## `CameraRig`'s own offset is what puts the eye at this node's origin.
##
## Human proportions for a 1.70 m figure, taken from the eye rather than from the
## floor, because the eye is the only origin this rig has: a 1.70 m person's eye
## is at 1.58 m, shoulder 1.42 m, hip 0.96 m. Subtracting: shoulder -0.16, hip
## -0.62. The head's CROWN is 0.115 m up from the eye.
##
## `HEAD_UP` IS THE HEAD'S CENTRE, AND IT WAS 0.110 -- WHICH FLOATED THE HEAD.
## 0.110 is the crown above the eye; the centre of a 0.21 m sphere whose crown is
## at +0.115 is at +0.010. Read as a centre it put the whole skull a decimetre above
## the shoulders, and the first third-person frame of this body showed a sphere
## hovering in the air 0.28 m above a torso with nothing joining them. The two
## readings are one character apart in the source and 0.10 m apart in the render,
## which is why the number now says which one it is and a neck draws the join.
const SHOULDER_DROP := 0.165
const SHOULDER_HALF := 0.190
const SHOULDER_FWD := 0.020
const HIP_DROP := 0.620
const HIP_HALF := 0.095
const HEAD_UP := 0.010
const HEAD_FWD := 0.030
const HEAD_RADIUS := 0.105
## The join from the shoulder line to the head, so the figure is one object. Short
## on purpose: this is a review body, and a long neck reads as a different creature.
const NECK_RADIUS := 0.049

## Segments, in metres. `UPPER_ARM + FOREARM` is the whole of what a left arm can
## do, and it is the number §30 has to live with.
const UPPER_ARM := 0.305
const FOREARM := 0.265

## Where the elbow is pushed. Down and out, which is where an elbow goes when a
## hand is holding something at hip height; a pole vector of zero would let the
## solver pick a plane and the elbow would flip between frames.
const POLE_LEFT := Vector3(-0.55, -0.80, -0.24)
const POLE_RIGHT := Vector3(0.55, -0.80, -0.24)

## §30's "Saya 向 前 Present：左肩 要 有 一点 Protraction", and its two siblings
## ("Tuck: 左肘 要 变化", "Counter Pull: 左肘 自然 后 走"), are one claim: the ARM
## is doing the holding, and the body is doing the arm.
##
## The elbow half of that came free the moment the hand started carrying the acts'
## own offsets -- a two-bone solve anchored at a fixed shoulder still moves its
## elbow when the target does. The shoulder half did not, and could not: a solve
## whose shoulder is a CONSTANT cannot show the body committing to a presentation,
## so the arm read as reaching out of a statue.
##
## One scalar, `_lean`, and everything above the hip reads it. The torso pitches
## about the hip line and the shoulder's forward shift is DERIVED from the same
## pitch, so the arm root and the torso top cannot disagree about how far the body
## has leaned. That is the "one expression, written twice" trick the weapon line
## uses for the seating anchor, for the same reason: two numbers that must agree
## are one number.
const PROTRACT_LEAN_MAX := 0.0436   # 2.5 degrees; §30 asks for "一点".
## How far forward of the shoulder plane the hand has to be for the FULL lean. A
## little over an arm's reach, so the response is proportional across the range the
## hand actually visits instead of saturating on the first centimetre.
const PROTRACT_SPAN := 0.30

const LIMB_RADIUS := 0.052
const JOINT_RADIUS := 0.058

## ===========================================================================
## THE LEGS, AND WHY A TORSO-ONLY BODY WAS NOT ENOUGH
## ===========================================================================
## The first version of this node stopped at the hip, on the argument that §30
## only asks for the LEFT ARM to be fixed. That argument is wrong in the one place
## it matters. `Player` turns by YAW, so "did the body turn with the cut" is a
## question about the hips and the feet, and a figure that ends at waist height
## answers it with a shape that has no orientation anyone can read -- worse, in a
## full-screen third-person shot it reads as a broken asset rather than as a
## deliberate omission, and a reviewer reports the wrong thing.
##
## So the legs are here for the MEASUREMENT, not for the beauty: they exist to
## stand the torso on the floor at the right height so the whole figure's facing
## is legible. They are built from `floor_drop`, which is MEASURED -- see
## `set_floor_drop` -- because the height of the eye above the floor is the one
## number this whole body is positioned from, and a hardcoded 1.58 was already
## wrong by 30 mm.
##
## Shares are fractions of the hip-to-floor distance, from human proportions:
## knee at 0.48 of it, ankle at 0.906.
const LEG_THIGH_SHARE := 0.479
const LEG_SHIN_SHARE := 0.906
const FOOT_LEN := 0.245
const FOOT_WIDE := 0.102
const FOOT_HEIGHT := 0.055
## A plausible eye-to-floor distance for something wearing this rig. Outside this
## band means the measurement is wrong, not that the character is unusual, and the
## caption says so instead of drawing a body floating a metre off the ground.
const FLOOR_MIN := 1.30
const FLOOR_MAX := 1.85

## ===========================================================================
## THE PALETTE, RE-READ FOR §32's MODE
## ===========================================================================
## The first version was near-black -- CLOTH 0.13, SKIN 0.24 -- on the argument
## that the blade and the lacquer must stay the brightest and darkest things in a
## review frame. That argument was written for the DETAIL camera, which shoots the
## weapon against a grey card. It is wrong for this mode for a plain reason: §32's
## camera stands in the ARENA, and the arena floor is pale. A 0.13 body against a
## 0.75 floor is a silhouette, and the first frame of the body clip showed exactly
## that -- a head, four limbs and two feet in one unbroken black, with no way to
## tell which limb was the left arm §30 is about.
##
## The constraint still holds, it just has to be read against the right background:
## the saya's lacquer is 0.052 and the blade is near white, so every tone below
## sits between them and the ordering in the frame is unchanged.
const SKIN := Color(0.395, 0.352, 0.320)
const CLOTH := Color(0.300, 0.308, 0.330)
## THE LEFT ARM IS A DIFFERENT COLOUR, ON PURPOSE.
##
## §30 is a claim about ONE LIMB. In a shot where a body is doing several things at
## once, "find the left arm" is the reviewer's first problem, and the cheapest
## honest answer is to colour it. This is ordinary practice in motion-capture
## review and it costs nothing: the tint is desaturated enough that the figure
## still reads as a body rather than as a marker, and it is used for the whole
## chain -- upper arm, forearm, elbow, hand -- so the limb traces in one glance.
const CLOTH_LEFT := Color(0.215, 0.330, 0.430)

## THE REVIEW LAYER, AND IT IS NOT A DETAIL.
##
## §32's camera culls the world: from `side_wide` and `rear_left` the arena's own
## pillars stand between the lens and the subject, and the first body clip arrived
## with a black column across a quarter of its A4 frame. Dropping bit 0 takes the
## pillars with it -- AND TAKES THIS BODY WITH IT, because a `MeshInstance3D`'s
## `layers` defaults to 1. The second body clip is what that looks like: a floor, a
## sword and a scabbard, and no figure at all, with every gate green.
##
## So the instrument names its own layer and the take builds the camera's mask from
## the answer (`review_layer()`), rather than both sides writing `1 << 17` and
## drifting the first time one of them is changed.
const REVIEW_LAYER := 1 << 17


## The layer this instrument is drawn on, asked for by the take rather than written
## there. See `REVIEW_LAYER`.
func review_layer() -> int:
	return REVIEW_LAYER


## Puts every mesh this body owns on `REVIEW_LAYER`.
##
## ONE CALL OVER THE CHILDREN RATHER THAN A LINE IN EVERY BUILDER. The body is
## assembled by three different functions and a part added to any of them by a
## later pass would otherwise default to layer 1 and vanish from §32's camera --
## which is a failure that renders as a floor and a sword and nothing else, with no
## error and every gate green. A sweep cannot forget.
func _stamp_layer() -> void:
	for child in get_children():
		if child is MeshInstance3D:
			(child as MeshInstance3D).layers = REVIEW_LAYER


## Set every frame by the reviewing take. World space.
var left_target := Vector3.ZERO
var right_target := Vector3.ZERO

## Metres from this node's origin down to the floor. Measured by the take from the
## player's own collision shape; zero means "not told yet" and no legs are drawn.
var floor_drop := 0.0
## The last thing `set_floor_drop` was told, so the take can report it rather than
## re-derive it and disagree.
var floor_source := ""

var _upper_l: MeshInstance3D
var _fore_l: MeshInstance3D
var _elbow_l: MeshInstance3D
var _hand_l: MeshInstance3D
var _upper_r: MeshInstance3D
var _fore_r: MeshInstance3D
var _elbow_r: MeshInstance3D
var _hand_r: MeshInstance3D

## §30's upper-body lean, and the three nodes that go through it. Held as members
## because their REST positions are what the pitch is applied TO, and a build-time
## local would mean recomputing those constants in two places.
var _torso: MeshInstance3D
var _neck: MeshInstance3D
var _head: MeshInstance3D
var _torso_rest := Vector3.ZERO
var _neck_rest := Vector3.ZERO
var _head_rest := Vector3.ZERO
var _lean := 0.0
## Rebuilt wholesale by `set_floor_drop`, so the legs are always exactly as long as
## the floor is far away. Nothing here is scaled: a limb is a unit cylinder whose
## Y scale is its length, and a leg that was stretched to reach the ground would
## change its own thickness by the same factor.
var _legs: Array[Node3D] = []

var _reach: Dictionary = {"left_shortfall": 0.0, "right_shortfall": 0.0,
	"left_span": 0.0, "right_span": 0.0}


func _ready() -> void:
	_build()
	# In case `set_floor_drop` was called before this node had a parent.
	_rebuild_legs()
	set_process(true)
	# AFTER EVERYTHING THAT MOVES THE POSE. The weapon controller writes `pose_*`
	# in its own `_process` and `SayaHandDriver` runs at priority -10, so the hand
	# point this node solves onto is final before it is read.
	process_priority = 20


func _process(_delta: float) -> void:
	_solve()


# ===========================================================================
# GEOMETRY
# ===========================================================================

func _build() -> void:
	var cloth := _material(CLOTH, 0.78)
	var cloth_left := _material(CLOTH_LEFT, 0.78)
	var skin := _material(SKIN, 0.62)

	# --- torso: one tapered box from the hip to the shoulders -----------------
	#
	# A box rather than a capsule on purpose. A capsule's silhouette is the same
	# from every angle, and a reviewer judging "did the torso turn with the cut"
	# needs to see which way it is facing. Two flat faces and a defined shoulder
	# line do that with four corners.
	var torso := MeshInstance3D.new()
	torso.name = "Torso"
	var body := BoxMesh.new()
	body.size = Vector3(
		SHOULDER_HALF * 2.0, HIP_DROP - SHOULDER_DROP, 0.215)
	torso.mesh = body
	torso.position = Vector3(0.0, -(SHOULDER_DROP + HIP_DROP) * 0.5, SHOULDER_FWD)
	torso.material_override = cloth
	add_child(torso)
	_torso = torso
	_torso_rest = torso.position

	var hips := MeshInstance3D.new()
	hips.name = "Hips"
	var basin := BoxMesh.new()
	basin.size = Vector3(HIP_HALF * 2.0, 0.145, 0.195)
	hips.mesh = basin
	hips.position = Vector3(0.0, -HIP_DROP, SHOULDER_FWD)
	hips.material_override = cloth
	add_child(hips)

	var head := MeshInstance3D.new()
	head.name = "Head"
	var skull := SphereMesh.new()
	skull.radius = HEAD_RADIUS
	skull.height = HEAD_RADIUS * 2.0
	skull.radial_segments = 16
	skull.rings = 8
	head.mesh = skull
	head.position = Vector3(0.0, HEAD_UP, HEAD_FWD)
	head.material_override = skin
	add_child(head)
	_head = head
	_head_rest = head.position

	# The neck, and it is not decoration. Without it the head is a sphere with air
	# under it, and a figure whose head is not attached is a figure a reviewer stops
	# reading -- see `HEAD_UP`. Vertical, so it needs no basis solved.
	var neck := MeshInstance3D.new()
	neck.name = "Neck"
	var column := CylinderMesh.new()
	column.top_radius = NECK_RADIUS
	column.bottom_radius = NECK_RADIUS * 1.15
	column.height = 0.110
	column.radial_segments = 10
	column.rings = 1
	neck.mesh = column
	neck.material_override = skin
	neck.position = Vector3(0.0, -0.075, (SHOULDER_FWD + HEAD_FWD) * 0.5)
	add_child(neck)
	_neck = neck
	_neck_rest = neck.position

	_upper_l = _limb("UpperArm_L", cloth_left)
	_fore_l = _limb("Forearm_L", cloth_left)
	_elbow_l = _joint("Elbow_L", cloth_left)
	_hand_l = _joint("Hand_L", cloth_left)
	_upper_r = _limb("UpperArm_R", cloth)
	_fore_r = _limb("Forearm_R", cloth)
	_elbow_r = _joint("Elbow_R", skin)
	_hand_r = _joint("Hand_R", skin)
	_stamp_layer()


## A limb segment as a cylinder of unit height, so its length is a SCALE and the
## caps do not smear. `CapsuleMesh` stretched in Y was the first version and the
## joints read as bulges rather than as joints.
func _limb(name: String, mat: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = name
	var mesh := CylinderMesh.new()
	mesh.top_radius = LIMB_RADIUS
	mesh.bottom_radius = LIMB_RADIUS * 0.88
	mesh.height = 1.0
	mesh.radial_segments = 12
	mesh.rings = 1
	node.mesh = mesh
	node.material_override = mat
	add_child(node)
	return node


func _joint(name: String, mat: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = name
	var mesh := SphereMesh.new()
	mesh.radius = JOINT_RADIUS
	mesh.height = JOINT_RADIUS * 2.0
	mesh.radial_segments = 10
	mesh.rings = 5
	node.mesh = mesh
	node.material_override = mat
	add_child(node)
	return node


func _material(colour: Color, rough: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = colour
	mat.roughness = rough
	# `metallic` is left at zero and that is not a default. §"金属陷阱": 0.75+ with
	# no reflection probe renders as a black silhouette, and a review body that
	# reads as a hole in the frame is worse than no body.
	mat.metallic = 0.0
	mat.cull_mode = BaseMaterial3D.CULL_BACK
	# A FLOOR UNDER THE DARKNESS, BECAUSE THE WORLD HAS ONE SUN AND IT IS BEHIND
	# THE CAMERA ON SOME OF THESE SHOTS.
	#
	# The body is lit by whatever light the stage has, and §32's cameras orbit it:
	# `side_wide` and `rear_left` both look toward the sun, and the first body clip's
	# A4 frame arrived with the whole figure reading as a flat dark shape. The number
	# is 0.70 rather than the 0.40 it started at, because 0.40 was chosen against a
	# pale floor and a floor that bright makes any figure look black -- see the
	# ground's own material for the other half of that pair. At 0.70 a limb in full
	# shadow still sits above the ground's tone and a limb in sun is brighter still,
	# so the sun shapes the figure without being able to extinguish it. This is an
	# instrument, not a character: legibility beats lighting fidelity.
	mat.emission_enabled = true
	mat.emission = colour
	mat.emission_energy_multiplier = 0.70
	return mat


# ===========================================================================
# THE FLOOR, AND THE LEGS THAT REACH IT
# ===========================================================================

## How far below this node's origin the floor is, in metres, and where that number
## came from.
##
## MEASURED, NOT ASSUMED. The class comment used to say the eye sits 1.58 m up,
## which is right for a 1.70 m person and was 30 mm wrong for this rig: `Player`
## puts `CameraRig` at y = +0.65 and the capsule under it is centred on the
## player's origin, so the eye is 0.65 + 0.90 = 1.55 m up. The take derives the
## figure from the collision shape it actually finds and hands it in -- so if
## somebody re-tunes the capsule, the legs follow, and if nobody can find the
## capsule the legs are simply not drawn rather than drawn in the wrong place.
##
## Safe to call before or after `_ready`; idempotent.
func set_floor_drop(drop: float, source: String) -> void:
	floor_drop = drop
	floor_source = source
	_rebuild_legs()


func floor_is_plausible() -> bool:
	return floor_drop >= FLOOR_MIN and floor_drop <= FLOOR_MAX


## Removes whatever legs exist and builds new ones from the current `floor_drop`.
func _rebuild_legs() -> void:
	if not is_inside_tree():
		# Called before the node was parented. `_place` writes `global_transform`,
		# which has no meaning until there is a tree to be global in, and a leg
		# solved against an identity parent is a leg in the wrong place that looks
		# fine in the log. `_ready` rebuilds from the stored value instead.
		return
	for leg in _legs:
		if is_instance_valid(leg):
			leg.queue_free()
	_legs.clear()
	if floor_drop <= 0.0:
		return
	# The hip is a fixed distance under the eye; everything below it is derived
	# from what is left, so the feet land ON the floor rather than near it. If
	# `HIP_DROP` and the floor ever disagree about how tall this body is, the legs
	# absorb the difference instead of the body floating or sinking.
	var leg_len := floor_drop - HIP_DROP
	if leg_len <= 0.05:
		return
	var cloth := _material(CLOTH, 0.78)
	var skin := _material(SKIN, 0.62)
	var floor_y := -floor_drop
	var hip_y := -HIP_DROP
	var knee_y := hip_y - leg_len * LEG_THIGH_SHARE
	var ankle_y := hip_y - leg_len * LEG_SHIN_SHARE
	for side_raw in [-1.0, 1.0]:
		# Typed on the way out of the literal: iteration over an untyped array
		# yields Variant, and a Variant in this expression makes `var x := ...`
		# uninferable, which is a parse error rather than a runtime one.
		var side := float(side_raw)
		# The stance is slightly wider than the hips and the feet toe out a
		# little, which is what stops a solved figure from reading as a doll on a
		# stand. Both are small on purpose: this is a reference pose, not a pose.
		var x := HIP_HALF * 1.12 * side
		var tag := _side_name(side)
		var thigh := _limb("Thigh_%s" % tag, cloth)
		var shin := _limb("Shin_%s" % tag, cloth)
		var knee := _joint("Knee_%s" % tag, skin)
		_legs.append(thigh)
		_legs.append(shin)
		_legs.append(knee)
		var hip := Vector3(x, hip_y, SHOULDER_FWD)
		var knee_at := Vector3(x * 1.06, knee_y, SHOULDER_FWD - 0.010)
		var ankle := Vector3(x * 1.12, ankle_y, SHOULDER_FWD - 0.020)
		# THE POINTS ABOVE ARE IN THIS NODE'S OWN FRAME AND `_place` TAKES WORLD.
		#
		# This body hangs off `CameraRig`, so its `global_transform` is the eye's
		# position and the player's yaw -- not identity. Handing `_place` a raw
		# local point builds the limb at the WORLD origin, which is several metres
		# from the camera in the arena and therefore simply not in the picture. The
		# first version did exactly that, and the tell was which parts DID show:
		# the knees (`global_transform * knee_at`) and the feet (plain `position`)
		# were both correct, so the figure had joints and shoes and no bones
		# between them -- a reading that no amount of staring at the code produces,
		# and one that a wrong-looking render makes obvious.
		_place(thigh, global_transform * hip, global_transform * knee_at,
			leg_len * LEG_THIGH_SHARE)
		_place(shin, global_transform * knee_at, global_transform * ankle,
			leg_len * (LEG_SHIN_SHARE - LEG_THIGH_SHARE))
		knee.global_position = global_transform * knee_at
		var foot := MeshInstance3D.new()
		foot.name = "Foot_%s" % tag
		var shoe := BoxMesh.new()
		shoe.size = Vector3(FOOT_WIDE, FOOT_HEIGHT, FOOT_LEN)
		foot.mesh = shoe
		foot.material_override = cloth
		# Sits ON the floor, and reaches FORWARD from the ankle -- forward is -Z
		# in this frame, the same direction `SwordBasic.SAYA_MOUTH.z` is negative
		# in, so a foot pointing the other way would be a body facing backwards.
		foot.position = Vector3(ankle.x, floor_y + FOOT_HEIGHT * 0.5,
			ankle.z - FOOT_LEN * 0.38)
		add_child(foot)
		_legs.append(foot)
	_stamp_layer()


func _side_name(side: float) -> String:
	if side < 0.0:
		return "L"
	return "R"


# ===========================================================================
# THE SOLVE
# ===========================================================================

## The shoulder's own world position. `SHOULDER_HALF` is +X = the character's
## right, matching the weapon line: `IDLE_POSITION.x` is +0.52 and that is the
## sword hand, so the left arm is -X.
## ...and it is put through `_about_hip` first, so the shoulder FOLLOWS the lean
## instead of being the constant it used to be. See `PROTRACT_LEAN_MAX`.
func shoulder(side: float) -> Vector3:
	return global_transform * _about_hip(Vector3(
		SHOULDER_HALF * side, -SHOULDER_DROP, SHOULDER_FWD))


## §30's protraction, as ONE signed angle about the hip line.
##
## Forward of the shoulder plane is +Z -- Godot's character forward is +Z in this
## project, which is the same convention `shoot_fp_sword.gd` and the chain rig
## use. A hand presented in front of the shoulders protracts them; a hand tucked
## behind retracts them; at rest the hand sits at the shoulder plane and the lean
## is zero, which is what makes this add no motion to the idle frames.
func _protraction() -> float:
	if left_target == Vector3.ZERO:
		return 0.0
	var local := global_transform.affine_inverse() * left_target
	var forward := local.z - SHOULDER_FWD
	return clampf(forward / PROTRACT_SPAN, -1.0, 1.0) * PROTRACT_LEAN_MAX


func _lean_basis() -> Basis:
	return Basis(Vector3.RIGHT, _lean)


## A point on the body, after the torso's pitch about the hip line. The HIP is the
## hinge, so the hip is what does not move -- which is also why the hips box and
## the legs are not put through this: they are below the hinge.
func _about_hip(p: Vector3) -> Vector3:
	var hinge := Vector3(0.0, -HIP_DROP, SHOULDER_FWD)
	return hinge + _lean_basis() * (p - hinge)


## Puts the torso, neck and head through the same lean the shoulder is derived
## from, so the upper body reads as ONE object that committed rather than as an
## arm reaching out of a statue.
func _slant() -> void:
	if _torso != null:
		_torso.position = _about_hip(_torso_rest)
		_torso.basis = _lean_basis()
	if _neck != null:
		_neck.position = _about_hip(_neck_rest)
	if _head != null:
		_head.position = _about_hip(_head_rest)


func _solve() -> void:
	# §30 FIRST, because the shoulder the arms hang from is derived from it.
	# Solving the arms and leaning afterwards would place their roots at last
	# frame's pose, which is the one thing this file's process priority exists to
	# prevent -- see `_ready`.
	_lean = _protraction()
	_slant()
	var ls := shoulder(-1.0)
	var rs := shoulder(1.0)
	var lb := global_transform.basis * POLE_LEFT
	var rb := global_transform.basis * POLE_RIGHT
	var l := _two_bone(ls, left_target, ls + lb)
	var r := _two_bone(rs, right_target, rs + rb)
	_place(_upper_l, ls, l["elbow"], UPPER_ARM)
	_place(_fore_l, l["elbow"], l["hand"], FOREARM)
	_elbow_l.global_position = l["elbow"]
	_hand_l.global_position = l["hand"]
	_place(_upper_r, rs, r["elbow"], UPPER_ARM)
	_place(_fore_r, r["elbow"], r["hand"], FOREARM)
	_elbow_r.global_position = r["elbow"]
	_hand_r.global_position = r["hand"]
	_reach = {
		"left_shortfall": float(l["shortfall"]),
		"right_shortfall": float(r["shortfall"]),
		"left_span": ls.distance_to(left_target),
		"right_span": rs.distance_to(right_target),
		# §30, as numbers. A reviewer looking at one frame of the body clip cannot
		# tell a 2.5-degree lean from a solver that happens to be pointing the same
		# way, and these are cheap.
		"lean_deg": rad_to_deg(_lean),
		"shoulder_fwd": (HIP_DROP - SHOULDER_DROP) * sin(_lean),
	}


## Two-bone IK by the law of cosines, in WORLD space, with no bone hierarchy.
##
## Written from the triangle rather than from an angle solver because the whole
## quantity of interest is `shortfall`: `|shoulder -> target|` minus the arm's
## own length. A solver that quietly rescales the bones to reach reports zero and
## is the reason nobody notices the rig asks for a 0.95 m arm. Here the hand is
## CLAMPED to the end of the 0.57 m it has, and how far it fell short is returned
## so the caption can say it.
func _two_bone(shoulder_pos: Vector3, target: Vector3, pole: Vector3) -> Dictionary:
	var delta := target - shoulder_pos
	var span := delta.length()
	var reach := UPPER_ARM + FOREARM
	var shortfall := maxf(0.0, span - reach)
	var dist := clampf(span, 0.02, reach - 0.0005)
	var dir := delta / maxf(span, 0.0001)

	var side := pole - shoulder_pos
	side -= dir * side.dot(dir)
	if side.length() < 0.0001:
		# Degenerate pole: pick any perpendicular rather than returning NaN.
		var fallback := Vector3.FORWARD - dir * dir.dot(Vector3.FORWARD)
		if fallback.length() < 0.0001:
			fallback = Vector3.RIGHT - dir * dir.dot(Vector3.RIGHT)
		side = fallback
	side = side.normalized()

	var cos_a := (UPPER_ARM * UPPER_ARM + dist * dist - FOREARM * FOREARM) \
		/ maxf(2.0 * UPPER_ARM * dist, 0.000001)
	var a := acos(clampf(cos_a, -1.0, 1.0))
	var elbow := shoulder_pos + (dir * cos(a) + side * sin(a)) * UPPER_ARM
	return {"elbow": elbow, "hand": shoulder_pos + dir * dist, "shortfall": shortfall}


## Points a unit-height cylinder from A to B. `global_transform` is written
## rather than `position`/`basis` so the arm is solved in the same space the hand
## points are handed in, whatever the parent chain happens to be.
func _place(node: MeshInstance3D, from: Vector3, to: Vector3, length: float) -> void:
	var delta := to - from
	var span := delta.length()
	if span < 0.0001:
		node.visible = false
		return
	node.visible = true
	var up := delta / span
	var ref := Vector3.UP if absf(up.dot(Vector3.UP)) < 0.98 else Vector3.RIGHT
	var right := ref.cross(up).normalized()
	# `fwd := right.cross(up)`, NOT `up.cross(right)`. A Basis's columns are
	# (x, y, z) and a right-handed basis wants x*y = z; `up.cross(right)` is the
	# negative of that, which makes the determinant -1 and Godot refuses a
	# mirrored basis outright -- the chain line paid for this once already at ~400
	# errors a run. See the "禁负缩放" note in the project memory.
	var fwd := right.cross(up)
	# ...and NOT `.orthonormalized()`. That call renormalises every column, and
	# the Y column's length IS this limb's length. It would silently turn every
	# arm into a 1 m cylinder.
	node.global_transform = Transform3D(
		Basis(right, up * (span / length), fwd),
		from + up * (span * 0.5))


# ===========================================================================
# THE READING
# ===========================================================================

## The arms' own measurement, from the frame that was just solved.
##
## `shortfall` is metres the hand could not cover. Zero is a body that can hold
## what the rig believes it is holding; 0.38 is a body reaching for something
## that is not there.
func reach_report() -> Dictionary:
	var out := _reach.duplicate()
	out["floor_drop"] = floor_drop
	out["floor_source"] = floor_source
	out["floor_plausible"] = floor_is_plausible()
	return out


## The one line a caption wants, so the movie tool does not re-word it.
##
## Written as an `if`/`return` pair rather than as a one-line ternary with a line
## continuation: `--check-only` is known to segfault with no diagnostic on
## multi-line expressions in this project, and a caption helper is not worth a
## silent exit 139.
# ===========================================================================
# ACCESSORS FOR `probe_saya_body_lean.gd`
# ===========================================================================
#
# The body is asked rather than read, for the same reason `_body_reach_line` in
# the movie asks this node instead of reading `_reach`: a probe that reaches into
# private state and re-derives the answer can disagree with the thing it is
# measuring, and then there are two answers and no way to choose.

## The plane the shoulder rests on. Zero lean has to mean "the hand is HERE", and
## a probe that hardcodes this number would keep agreeing with an old one.
func shoulder_rest_fwd() -> float:
	return SHOULDER_FWD


func protract_lean_max_deg() -> float:
	return rad_to_deg(PROTRACT_LEAN_MAX)


func reach() -> Dictionary:
	return _reach


## The top edge of the torso in world space, so the probe can check the claim the
## lean depends on: that the shoulder and the torso's top are one angle at two
## lever arms, and at this body's proportions the two arms are the same length.
func torso_top_world() -> Vector3:
	if _torso == null:
		return global_transform.origin
	var half := (HIP_DROP - SHOULDER_DROP) * 0.5
	return global_transform * (_torso.position
		+ _torso.basis * Vector3(0.0, half, 0.0))


func reach_line() -> String:
	var arms := "both arms reach"
	if maxf(float(_reach["left_shortfall"]), float(_reach["right_shortfall"])) > 0.001:
		arms = "left arm %.0f mm short of the saya · right %.0f mm short of the grip" % [
			float(_reach["left_shortfall"]) * 1000.0,
			float(_reach["right_shortfall"]) * 1000.0]
	# §30's own number, said in the caption. The ELBOW half of §30 is the solver's
	# business and moves as soon as the hand does; the SHOULDER half is this file's,
	# and a reader looking at one frame cannot tell a 2.5-degree lean from a solver
	# that happens to be pointing the same way.
	return "%s · torso lean %+.1f° · left shoulder %+.0f mm fwd" % [
		arms, float(_reach.get("lean_deg", 0.0)),
		float(_reach.get("shoulder_fwd", 0.0)) * 1000.0]


## Where the floor was taken from, said in the caption rather than kept in a
## comment. If the number is wrong the picture shows a body at the wrong height and
## nothing else will say why.
func floor_line() -> String:
	if floor_drop <= 0.0:
		return "NO FLOOR MEASURED -- this body has no legs"
	if not floor_is_plausible():
		return "floor at %.0f mm from the eye is OUTSIDE %.0f-%.0f mm -- the measurement is wrong, not the character" % [
			floor_drop * 1000.0, FLOOR_MIN * 1000.0, FLOOR_MAX * 1000.0]
	return "floor %.0f mm below the eye (%s)" % [floor_drop * 1000.0, floor_source]
