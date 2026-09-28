extends Node3D
# First-person weapon driver.
#
# This node no longer guesses a pose from the combat state with a fixed lerp.
# It reads the pose the CombatController sampled from the active sword move's
# Weight Curve (anticipation → strike → follow-through → settle) and applies a
# short exponential lag so the weapon still belongs to a body instead of being
# welded to the camera.
#
# When the Iaido / signature director is running it owns the transform directly
# and this node stays out of the way.

@onready var combat: CombatController = get_node("../../../../../../CombatController")
@onready var player: CharacterBody3D = combat.get_parent()
@onready var camera_feedback: CameraFeedbackController = player.get_node("CameraFeedbackController")
@onready var iaido: IaidoDirector = player.get_parent().get_node("IaidoDirector")

# Kept for IaidoDirector, which restores the weapon here after the ceremony.
const IDLE_POSITION := Vector3(0.52, -0.50, -0.94)
const IDLE_ROTATION := Vector3(0.0, 0.0, -0.18)

# §21 WEAPON LOCOMOTION. A blade welded to the camera is the single fastest way
# to make a body feel like a floating viewpoint, and it is invisible from a
# screenshot of the world: the camera is doing all the moving correctly. These
# are the six things the weapon has to inherit from the body it is attached to:
#   weapon lag       the blade arrives after the body does
#   turn lag         the blade trails a turn instead of being telepathic
#   sprint lower     a different carrying posture, entered and left smoothly
#   acceleration     leaving a stop tips it, arriving pushes it back
#   landing inertia  the body going down takes the weapon with it
#   stop settle      stopping overshoots slightly and comes back
# Every one of them is applied AFTER the combat pose, so nothing here can fight
# the move authoring — during a cut the pose dominates and this rides underneath.
@export_group("Locomotion")
@export var motion_lag := 0.10
@export var lateral_sway := 0.055
@export var forward_sway := 0.042
@export var turn_sway := 0.20
@export var sprint_drop := 0.10
@export var sprint_roll := -0.20
@export var landing_dip_gain := 0.008
@export var landing_spring_k := 120.0
@export var landing_spring_c := 13.0

# §27 / §30. THE BLADE HAS TO ANSWER CONTACT, NOT ONLY REPORT IT.
#
# The pose is a pure function of the move timeline, and the timeline does not
# know what happened. So a cut that met a body and a cut that met air were the
# same motion for the one channel that cannot be compensated for: the hand.
# Everything the player was told about contact arrived from somewhere else — an
# impact sound, a screen flash, a number — and all of those are things the player
# can be told ABOUT. The weapon itself said nothing, which is why whiffing read
# as hitting.
#
# So contact is authored as a FORCE rather than a pose: the blade was travelling,
# something stopped it, and the wrist could not hold its line. What follows is a
# deflection against the direction of travel and the arm winning the line back.
# Whiffing gets none of it, and the absence of the deflection IS the information.
@export_group("Contact")
# How far the TIP is knocked off its line by meeting something, in metres.
@export var contact_deflection := 0.05
@export var contact_spring_k := 190.0
@export var contact_spring_c := 21.0
# Radians of wrist break at full deflection. Small number, enormous lever: the
# tip is 0.95m away from the joint, so 0.3 rad here is twenty-six degrees of
# blade and forty-five centimetres of travel — the rotation was the entire effect
# and the translation was decoration. Authored against what the tip should MOVE,
# not against how much the wrist can lose.
@export var contact_roll := 0.05
# A blade that was barely moving when it met something should barely be stopped
# by it, otherwise blocking puts the same dent in the wrist as a full swing.
@export var contact_floor := 0.35
@export var contact_full_speed := 7.0

var _loc_vel := Vector3.ZERO
var _loc_turn := 0.0
var _prev_forward := Vector2.ZERO
var _have_forward := false
var _sprint_blend := 0.0
var _land_dip := 0.0
var _land_vel := 0.0
var _loc_offset := Vector3.ZERO
var _loc_rotation := Vector3.ZERO
var _accel_local := 0.0

var _contact_dir := Vector3.ZERO
var _contact_dip := 0.0
var _contact_vel := 0.0
var _contact_offset := Vector3.ZERO
var _contact_rotation := Vector3.ZERO
var _contact_wrist := Vector3.ZERO
var _tip_prev := Vector3.ZERO
# THE BLADE'S OWN LAST FRAME OF TRAVEL, recorded when it is computed rather
# than reconstructed later. Contact arrives as a SIGNAL, and a signal does not
# arrive at a convenient moment — by the time `_on_sword_hit` runs, `_tip_prev`
# has already been assigned this frame's tip, so asking for
# `_pose_tip() - _tip_prev` there asks for the distance the blade covered
# between the end of this frame and the end of this frame, which is always
# zero. The only thing that ever made it non-zero was the tremor, which is
# applied AFTER `_tip_prev` is sampled — so the sword had been taking its
# contact direction from the authored wobble, at random, for its whole life.
var _travel_step := Vector3.ZERO
var _tip_speed := 0.0
var _have_tip := false

# --- the real model ---------------------------------------------------------
#
# WHAT IS IN THE HAND, AND WHY THE SWAP IS DONE INSIDE THIS NODE.
#
# This node is the carrier.  `iaido_director.gd` and
# `moment_of_no_moon_director.gd` both `get_node()` it and then WRITE ITS
# TRANSFORM for the length of a skill, and the trail, the glint band, the void
# rim, the contact springs and the five locomotion channels are all children of
# it.  So the real sword is added UNDER this node rather than replacing it: every
# pose, judgement and animation path keeps driving exactly the node it always
# drove, and the only thing that changes is which triangle soup is drawn.
#
# That is the whole of "换建模不影响位置和技能效果" on this side: no node path
# moves, no consumer learns the model changed, and if the GLB is ever missing the
# three placeholder boxes below are still there and still work.
#
# The numbers come from `sword_classes.gd`, never from this file.  `BLADE_LENGTH`
# in particular used to be 0.95 for everything, which drew 185 mm of trail past a
# tip that stops at 0.765.
const Registry := preload("res://scripts/weapons/sword_classes.gd")
const SWORD_RIG_SCENE := "res://scenes/weapons/Sword_FP.tscn"
const WEAPON_ID := &"iaito"
## Ablation switch.  False restores the placeholder boxes exactly as they were,
## which is the one-step way back if the real sword ever regresses a combat read.
@export var use_real_model := true

const BLADE_TINT := Color(0.84, 0.92, 1.0)
const VOID_TINT := Color(0.72, 0.85, 1.0)
const GLINT_TINT := Color(1.0, 0.98, 0.90)
const GRIP_TINT := Color(0.16, 0.12, 0.09)
const GUARD_TINT := Color(0.72, 0.62, 0.35)
const BLADE_LENGTH := 0.95
const TRAIL_SAMPLES := 14
const TRAIL_MIN_TIP_TRAVEL := 0.012

var click_flash: MeshInstance3D
var blade_material: StandardMaterial3D
var grip_material: StandardMaterial3D
var guard_material: StandardMaterial3D
var click_material: StandardMaterial3D
var blade_part: MeshInstance3D
var grip_part: MeshInstance3D
var guard_part: MeshInstance3D
var void_rim: MeshInstance3D
var void_rim_material: StandardMaterial3D
var sheath_prop: MeshInstance3D
var glint_band: MeshInstance3D
var glint_material: StandardMaterial3D
var trail: MeshInstance3D
var trail_mesh: ImmediateMesh
var trail_material: StandardMaterial3D
var trail_history: Array[Vector3] = []
var blade_length := BLADE_LENGTH

## The real rig, when it is in use.  Null means the placeholder boxes are what the
## player sees, and every guard in this file keys off exactly that.
var _real_rig: Node3D
## The real saya, when 藏锋's sheathed idle is showing a scabbard.
var _real_saya: Node3D
## The placeholder scabbard's box, held so the real saya can take its place
## without the box's own geometry being drawn on top of it.
var _sheath_box_mesh: Mesh

var pose_position := IDLE_POSITION
var pose_rotation := IDLE_ROTATION
var pose_time := 0.0
var glint := 0.0
var root_inverse := Transform3D.IDENTITY

# How strongly the cold void behind the cut is reflected on the blade.
var void_exposure := 0.0 : set = set_void_exposure

# 吞噬. How completely the emptiness has eaten the FOREGROUND — the hand, the
# sword, and every overlay that belongs to holding them.
#
# The devour used to stop at the world. That leaves the one object closest to the
# camera as the last solid thing in the frame, which reads as a prop left on top
# of a finished shot: the world is gone, the glass is gone, and there is still a
# sword being held by nobody. Taking the weapon layer out with the world is what
# makes it read as the whole reality going rather than as the backdrop going.
#
# Driven from the timeline, never accumulated.
var swallowed := 0.0 : set = set_swallowed

# Set for the duration of the Iaido ceremony. The director owns the transform
# and the scabbard then, and the moveset's own scabbard prop would otherwise be
# left frozen at whatever pose it held when the ceremony started, rotating with
# the blade like a second sword.
var ceremony_mode := false


func set_ceremony_mode(enabled: bool) -> void:
	ceremony_mode = enabled
	if not enabled:
		return
	trail.visible = false
	trail_history.clear()
	click_flash.visible = false
	if sheath_prop != null:
		sheath_prop.visible = false
	if glint_band != null:
		glint_band.visible = false


func _ready() -> void:
	position = IDLE_POSITION
	rotation = IDLE_ROTATION
	_build_sword()
	_build_sheath()
	_build_glint()
	_build_trail()
	_build_click_flash()
	_install_real_model()
	if player != null and player.has_signal("landed"):
		player.landed.connect(_on_player_landed)
	if combat != null:
		combat.hit_landed.connect(_on_sword_hit)


# ===========================================================================
# THE REAL MODEL
# ===========================================================================
#
# Nothing above this line changed to make the swap possible, and that is the
# point: the placeholder and the real sword are the same node graph, and this
# function only decides which one is drawn.
#
# It is deliberately ALL-OR-NOTHING.  A half-applied swap -- real blade, box
# guard still sticking out of it -- is worse than no swap, so if the registry's
# files are not both present this returns and the placeholder stays whole.
func _install_real_model() -> void:
	if not use_real_model:
		return
	if not Registry.assets_present(WEAPON_ID):
		push_warning(
			"TempSwordVisual: sword-class '%s' names a model or a scabbard that is not on "
			% WEAPON_ID
			+ "disk, so the placeholder is staying. See scripts/weapons/sword_classes.gd."
		)
		return
	var scene := load(SWORD_RIG_SCENE) as PackedScene
	if scene == null:
		return
	_real_rig = scene.instantiate()
	_real_rig.name = "Sword_FP"
	# Identity: the GLB is authored with its origin at the tsuba and +Y to the
	# tip, which is the same frame the placeholder boxes are laid out in.  The
	# importer confirms it -- neither GLB carries a root rotation or scale.
	_real_rig.transform = Transform3D.IDENTITY
	add_child(_real_rig)

	# The blade the trail, the glint and the contact model are drawn against is
	# now the real blade, so every one of those channels has to be resized to it.
	# `visual_length()` is origin -> tip, which is what a trail is measured from;
	# it is NOT `blade_reach()`, which is the ceremony's tsuba-face -> tip.
	blade_length = Registry.visual_length(WEAPON_ID)
	_resize_blade_overlays()
	_hide_placeholder_parts()
	_install_real_saya()


# ===========================================================================
# THE REAL SCABBARD, ON THE MOVESET SIDE
# ===========================================================================
#
# 藏锋's sheathed idle is a real mechanic, not a flourish: `sheath_enabled` is
# true for that style, the blade sits at `sheath_pose` while `sheath_prop` holds
# the scabbard at `sheath_scabbard_pose`, and starting from a full sheath scales
# the opening hit. So the box `_build_sheath()` makes is a live object and it is
# this function's job to put the real saya in its place WITHOUT moving anything.
#
# HOW THE SCABBARD IS PLACED, AND WHY IT IS DERIVED RATHER THAN AUTHORED.
# The two authored poses -- where the sword sits when sheathed, and where the
# scabbard sits -- are independent numbers, and nothing makes them agree.  With
# the placeholder that does not matter, because the blade is hidden by a
# `visible = false` once it is 55% home and the box never has to contain
# anything.  With a real closed-tube saya it matters completely: the blade has to
# be INSIDE the bore or the shot is a fake.
#
# Both GLBs are authored in one frame (origin at the mouth plane / at the tsuba,
# +Y down the bore / to the tip), so `Registry.saya_in_sword_frame()` IS the
# answer: park the saya at the sword's sheathed pose, translated by the tsuba
# setback.  Then "fully sheathed" is true by construction at any pose the
# moveset author picks, instead of being true because two hand-typed euler
# triples happened to line up.
#
# `move.sheath_scabbard_pose/rot` are therefore superseded while the real saya
# is in use, and remain the fallback the moment it is not.
func _install_real_saya() -> void:
	if sheath_prop == null:
		return
	var path := Registry.scabbard_path(WEAPON_ID)
	if not ResourceLoader.exists(path):
		return
	var scene := load(path) as PackedScene
	if scene == null:
		return
	_real_saya = scene.instantiate()
	_real_saya.name = "Saya"
	_real_saya.transform = Transform3D.IDENTITY
	sheath_prop.add_child(_real_saya)
	# `sheath_prop` stays the CARRIER -- it is still the node `_root_space()`
	# drives and whose `visible` the move toggles -- but a node whose origin is
	# the mouth cannot also be a box centred on the old pose's midpoint. So the
	# box geometry goes and the node becomes a pure transform.
	if sheath_prop.mesh != null:
		_sheath_box_mesh = sheath_prop.mesh
		sheath_prop.mesh = null


# The two overlays that are drawn along the blade.  Both were sized from
# `BLADE_LENGTH` and the placeholder's width; both are now sized from the
# registry, so they cannot be longer than the steel they are supposed to be on.
func _resize_blade_overlays() -> void:
	var d := Registry.get_class_def(WEAPON_ID)
	var half_w := float(d["blade_half_w_base"])
	var half_t := float(d["blade_half_t_base"])
	if void_rim != null and void_rim.mesh is BoxMesh:
		(void_rim.mesh as BoxMesh).size = Vector3(half_w * 2.0, blade_length * 1.07, half_t * 2.0)
		void_rim.position = Vector3(0.0, blade_length * 0.5, 0.0)
	if glint_band != null and glint_band.mesh is BoxMesh:
		(glint_band.mesh as BoxMesh).size = Vector3(half_w * 2.5, blade_length, half_t * 5.0)
		glint_band.position = Vector3(0.0, blade_length * 0.5, 0.0)


# The three boxes.  Kept, not freed: `_apply_fade`, `_update_sheath` and
# `_update_glint` all still reference them, and the fallback has to cost nothing
# to return to.
func _hide_placeholder_parts() -> void:
	for part in [blade_part, guard_part, grip_part, void_rim]:
		if part != null:
			part.visible = false


## True when a blade is being drawn, whichever blade it is.  The overlays ask
## this instead of `blade_part.visible`, which is false in the one case that
## matters.
func _blade_is_drawn() -> bool:
	if _real_rig != null:
		return true
	return blade_part != null and blade_part.visible


func _build_sword() -> void:
	grip_part = _add_part("TEMP Grip", Vector3(0.10, 0.28, 0.10), Vector3(0, -0.18, 0), GRIP_TINT)
	guard_part = _add_part("TEMP Guard", Vector3(0.36, 0.07, 0.11), Vector3(0, 0.01, 0), GUARD_TINT)
	blade_part = _add_part("TEMP Blade", Vector3(0.075, BLADE_LENGTH, 0.038), Vector3(0, 0.52, 0), BLADE_TINT)
	blade_material = blade_part.mesh.material as StandardMaterial3D
	grip_material = grip_part.mesh.material as StandardMaterial3D
	guard_material = guard_part.mesh.material as StandardMaterial3D
	blade_length = BLADE_LENGTH
	_add_void_rim()


func _add_void_rim() -> void:
	# Back faces only: a cold halo that keeps the blade readable against the
	# darkened world without ever lighting it like a torch.
	var rim_mesh := BoxMesh.new()
	rim_mesh.size = Vector3(0.075, 1.02, 0.035)
	void_rim_material = StandardMaterial3D.new()
	void_rim_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	void_rim_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	void_rim_material.cull_mode = BaseMaterial3D.CULL_FRONT
	void_rim_material.albedo_color = Color(0.55, 0.74, 0.95, 0.0)
	rim_mesh.material = void_rim_material
	void_rim = MeshInstance3D.new()
	void_rim.name = "VoidRim"
	void_rim.mesh = rim_mesh
	void_rim.position = Vector3(0, 0.52, 0)
	void_rim.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	void_rim.visible = false
	add_child(void_rim)


func _build_sheath() -> void:
	# The scabbard belongs to the body, not the weapon: it never moves, so the
	# blade sliding into it reads as a real sheathe.
	#
	# Both the scabbard and the trail must live in the WeaponRoot's space, not
	# in the blade's own rotating space. They are parented to this node (the
	# scene is still being built during _ready, so the parent cannot accept new
	# children) and compensated back into root space every frame.
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.10, 0.62, 0.075)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.13, 0.115, 0.13)
	mesh.material = material
	sheath_prop = MeshInstance3D.new()
	sheath_prop.name = "Scabbard"
	sheath_prop.mesh = mesh
	sheath_prop.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sheath_prop.visible = false
	add_child(sheath_prop)


func _build_glint() -> void:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.09, BLADE_LENGTH, 0.09)
	glint_material = StandardMaterial3D.new()
	glint_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glint_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glint_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	glint_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	glint_material.albedo_color = Color(1.0, 0.97, 0.88, 0.0)
	mesh.material = glint_material
	glint_band = MeshInstance3D.new()
	glint_band.name = "EdgeGlint"
	glint_band.mesh = mesh
	glint_band.position = Vector3(0, 0.52, 0)
	glint_band.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	glint_band.visible = false
	add_child(glint_band)


func _build_trail() -> void:
	# A swept ribbon through the blade's own recent path. This is what makes a
	# first-person swing readable without a hand or arm model.
	trail_mesh = ImmediateMesh.new()
	trail_material = StandardMaterial3D.new()
	trail_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	trail_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	trail_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	trail_material.vertex_color_use_as_albedo = true
	trail = MeshInstance3D.new()
	trail.name = "BladeTrail"
	trail.mesh = trail_mesh
	trail.material_override = trail_material
	trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	trail.visible = false
	add_child(trail)


func _build_click_flash() -> void:
	var flash_mesh := SphereMesh.new()
	flash_mesh.radius = 0.045
	flash_mesh.height = 0.09
	var flash_material := StandardMaterial3D.new()
	flash_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flash_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flash_material.albedo_color = Color(1.0, 0.98, 0.86)
	click_material = flash_material
	click_flash = MeshInstance3D.new()
	click_flash.name = "Iaido Hilt Click"
	click_flash.mesh = flash_mesh
	click_flash.material_override = flash_material
	click_flash.position = Vector3(0.0, 0.02, 0.05)
	click_flash.visible = false
	add_child(click_flash)


func set_void_exposure(value: float) -> void:
	void_exposure = clampf(value, 0.0, 1.0)
	_apply_fade()


func _add_part(part_name: String, size: Vector3, offset: Vector3, tint: Color) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# Transparency is enabled at BUILD time, not switched on when the devour
	# starts. Toggling it per frame re-sorts the material every frame and can
	# stall on a shader recompile, and the fade has to be smooth to read as the
	# emptiness closing over the blade.
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = tint
	mesh.material = material
	var part := MeshInstance3D.new()
	part.name = part_name
	part.mesh = mesh
	part.position = offset
	add_child(part)
	return part


# --- the foreground fade ----------------------------------------------------
#
# EVERY ALPHA IN THIS FILE IS COMPUTED IN ONE PLACE.
#
# Three systems write this weapon's colours: the cold rim follows
# `void_exposure`, the edge glint follows `glint`, and the devour follows
# `swallowed`. The director and this node are separate _process callbacks, so
# whichever ran last used to win — and once the two are written in different
# order the result is a flicker rather than a fade. Everything now goes through
# `_apply_fade`, so any setter can be called in any order.
func _apply_fade() -> void:
	var keep := 1.0 - swallowed
	var blade_tint := BLADE_TINT.lerp(VOID_TINT, void_exposure * 0.55)
	if blade_material != null:
		blade_material.albedo_color = Color(blade_tint.r, blade_tint.g, blade_tint.b, keep)
	if grip_material != null:
		grip_material.albedo_color = Color(GRIP_TINT.r, GRIP_TINT.g, GRIP_TINT.b, keep)
	if guard_material != null:
		guard_material.albedo_color = Color(GUARD_TINT.r, GUARD_TINT.g, GUARD_TINT.b, keep)
	if void_rim_material != null:
		void_rim_material.albedo_color = Color(0.55, 0.74, 0.95, void_exposure * 0.55 * keep)
	# The rim is the one overlay that is also a BODY part of the void, so it is
	# gated on both: no exposure means no rim, and a swallowed weapon has no rim
	# to draw on. Decided here rather than in `set_void_exposure` so the devour
	# can take the rim with it without a second setter knowing about it.
	if void_rim != null:
		void_rim.visible = void_exposure > 0.01 and keep > 0.001
	if glint_material != null:
		glint_material.albedo_color = Color(GLINT_TINT.r, GLINT_TINT.g, GLINT_TINT.b, glint * 0.42 * keep)
	if click_material != null:
		click_material.albedo_color = Color(1.0, 0.98, 0.86, keep)
	if sheath_prop != null and sheath_prop.mesh != null:
		var sheath_material := sheath_prop.mesh.material as StandardMaterial3D
		if sheath_material != null:
			sheath_material.albedo_color = Color(0.13, 0.115, 0.13, keep)
	# Nothing left to draw once it is gone: stop submitting the body parts at
	# all, so the layer costs nothing and cannot flicker back on a stray alpha.
	#
	# `and _real_rig == null` is load-bearing: without it this function, which
	# runs on the first frame and on every fade, would switch the placeholder
	# boxes back ON on top of the real sword.
	var solid := keep > 0.001 and _real_rig == null
	if blade_part != null:
		blade_part.visible = solid
	if grip_part != null:
		grip_part.visible = solid
	if guard_part != null:
		guard_part.visible = solid


func set_swallowed(value: float) -> void:
	swallowed = clampf(value, 0.0, 1.0)
	_apply_fade()


# Everything here is driven by the BODY's motion in the BODY's own frame, so it
# reads correctly whether you strafe, retreat or turn on the spot — the numbers
# are "how much is the world sliding past me", not "what key am I holding".
func _locomotion(delta: float) -> void:
	if delta <= 0.0:
		return
	# Where the body is going, expressed locally: +x is right, -z is forward.
	var local := player.global_basis.inverse() * player.velocity
	var smoothed := _loc_vel.lerp(local, 1.0 - exp(-delta / maxf(motion_lag, 0.001)))
	_accel_local = (local.z - smoothed.z) / delta
	_loc_vel = smoothed

	# Turn rate off the view vector rather than off mouse input: this has to work
	# identically for a mouse flick, a controller stick or anything that rotates
	# the body later, because the blade does not care why it is turning.
	var forward := Vector2(-player.global_basis.z.x, -player.global_basis.z.z).normalized()
	if _have_forward:
		var crossed := _prev_forward.cross(forward)
		var turned := wrapf(atan2(crossed, maxf(_prev_forward.dot(forward), -1.0)), -PI, PI)
		_loc_turn = lerpf(_loc_turn, turned / delta, 1.0 - exp(-delta / 0.09))
	_prev_forward = forward
	_have_forward = true

	# The blade ARRIVES LATE, so it leans away from where the body has got to.
	var sideways := clampf(-_loc_vel.x / 6.0, -1.0, 1.0) * lateral_sway
	var fore := clampf(-_loc_vel.z / 8.0, -1.0, 1.0) * forward_sway
	var yaw := clampf(-_loc_turn / 4.0, -1.0, 1.0) * turn_sway
	# And it tips with CHANGE in speed, which is the only part of acceleration a
	# held-still camera can still see: leaving a stop leans it forward, arriving
	# pushes it back onto the shoulder.
	var accel_tip := clampf(_accel_local / 40.0, -1.0, 1.0) * forward_sway * 0.55

	var want_sprint := (
		player.is_on_floor()
		and Input.is_action_pressed("sprint")
		and Vector2(player.velocity.x, player.velocity.z).length() > 1.0
	)
	# Asymmetric on purpose: dropping into a sprint carry is immediate, coming out
	# of it is a recovery — §23 asks for exactly that and forbids the snap back.
	_sprint_blend = lerpf(
		_sprint_blend, 1.0 if want_sprint else 0.0, 1.0 - exp(-delta / (0.10 if want_sprint else 0.34))
	)

	# Landing is a spring, not a lerp: the body stops and the blade keeps going,
	# so it dips past and comes back. A monotone decay would look like a nudge.
	_land_vel += (-landing_spring_k * _land_dip - landing_spring_c * _land_vel) * delta
	_land_dip += _land_vel * delta

	_loc_offset = Vector3(sideways, -sprint_drop * _sprint_blend + _land_dip, fore + accel_tip)
	_loc_rotation = Vector3(-accel_tip * 0.6, yaw, sprint_roll * _sprint_blend)


# The body owns landing (§25); the weapon just answers it. Graded so a hop barely
# moves the blade and a real drop takes it down.
func _on_player_landed(impact_speed: float, tier: StringName) -> void:
	var weight: float = {&"light": 0.45, &"medium": 1.0, &"heavy": 1.7}.get(tier, 1.0)
	_land_vel -= impact_speed * landing_dip_gain * weight * 8.0


# Where the tip is WITHOUT any of the forces above on it — the pose alone. This
# is the blade's own opinion of where it is going, and both the travel direction
# and its speed have to be read off that, never off the final drawn position:
# reading the result of the deflection back into the direction of travel makes
# the next contact argue with the last one.
func _pose_tip() -> Vector3:
	return pose_position + (Basis.from_euler(pose_rotation) * Vector3.UP) * blade_length


# The body was hit. Not "damage was dealt" — those are two different sentences
# and only one of them belongs to a hand: even a cut that lands for nothing is a
# cut that met something solid and got stopped by it.
func _on_sword_hit(_move: SwordMove, _hit: Dictionary) -> void:
	if not _have_tip:
		return
	# The travel the blade HAD, not the travel it can be asked for now. See
	# `_travel_step`: this handler runs whenever the hitbox decides to deliver,
	# which is not inside this node's `_process`, so the only honest answer is
	# the one that was recorded when the blade actually moved.
	var travel := _travel_step
	if travel.length() < 0.0004:
		return
	_contact_dir = travel.normalized()
	var into := _contact_dir
	var reach := clampf(_tip_speed / maxf(contact_full_speed, 0.001), contact_floor, 1.4)
	var kick := _peak_to_velocity(contact_deflection * reach)
	_contact_vel += kick
	# The wrist breaks ACROSS the cut: something with sideways travel rolls the
	# blade, something with vertical travel pitches it, because that is the only
	# direction the joint can lose. Aiming this by hand instead of by `contact_roll`
	# alone is what lets one number cover 直刺 and 斜斩 alike.
	_contact_wrist = Vector3(-into.y, 0.0, into.x) * contact_roll / maxf(contact_deflection, 0.0001)


# A spring authored in metres, not in "impulse units". Given the stiffness above,
# this is the kick velocity that peaks at exactly `peak` metres, so tuning the
# spring later cannot silently change how hard the sword reads.
func _peak_to_velocity(peak: float) -> float:
	var omega := sqrt(maxf(contact_spring_k, 1.0))
	var damping := contact_spring_c / maxf(2.0 * omega, 0.0001)
	var omega_d := omega * sqrt(maxf(1.0 - damping * damping, 0.0001))
	var t_peak := atan2(omega_d, maxf(damping * omega, 0.0001)) / maxf(omega_d, 0.0001)
	var metres_per_unit := exp(-damping * omega * t_peak) * sin(omega_d * t_peak) / omega_d
	if is_zero_approx(metres_per_unit):
		return 0.0
	return peak / metres_per_unit


func _contact_step(delta: float, posed_tip: Vector3) -> void:
	if not _have_tip:
		_tip_prev = posed_tip
		_have_tip = true
		return
	var step := posed_tip - _tip_prev
	# Recorded here, where the blade's own motion is actually known, and
	# deliberately BEFORE the tremor is added to `pose_position` below: the
	# tremor is authored wobble, not intent, and letting it into this number
	# hands the sword a contact direction that has nothing to do with the cut.
	_travel_step = step
	var instant := step / maxf(delta, 0.0001)
	_tip_prev = posed_tip
	_tip_speed = lerpf(_tip_speed, instant.length(), 1.0 - exp(-delta / 0.06))
	_contact_vel += (-contact_spring_k * _contact_dip - contact_spring_c * _contact_vel) * delta
	_contact_dip += _contact_vel * delta
	_contact_offset = -_contact_dir * _contact_dip
	_contact_rotation = _contact_wrist * _contact_dip


func locomotion_readout() -> Dictionary:
	return {
		"offset": _loc_offset,
		"rotation": _loc_rotation,
		"lateral": _loc_vel.x,
		"forward": _loc_vel.z,
		"turn": _loc_turn,
		"sprint": _sprint_blend,
		"land_dip": _land_dip,
		"contact": _contact_dip,
		"tip_speed": _tip_speed,
	}


func _process(delta: float) -> void:
	if combat.state == CombatController.State.IAIDO or combat.state == CombatController.State.ULTIMATE:
		# The signature / ultimate directors drive the transform directly,
		# including freeze frames.
		trail.visible = false
		trail_history.clear()
		if ceremony_mode and sheath_prop != null:
			sheath_prop.visible = false
		return
	pose_time += delta
	var snapshot := combat.pose_snapshot()
	var target: Vector3 = snapshot.position
	var target_rotation: Vector3 = snapshot.rotation
	var intensity: float = snapshot.intensity
	# Exponential lag, not a tween: the authored acceleration curve survives,
	# and the blade still belongs to a body. 藏锋 is tight, 回风 is loose.
	var tau := 2.2 / maxf(float(snapshot.stiffness), 1.0)
	var follow := 1.0 - exp(-delta / tau)
	pose_position = pose_position.lerp(target, follow)
	pose_rotation = pose_rotation.lerp(target_rotation, follow)
	_locomotion(delta)
	_contact_step(delta, _pose_tip())
	if intensity > 0.02:
		var amp := float(snapshot.tremor) * intensity
		pose_position += Vector3(
			sin(pose_time * 47.0),
			sin(pose_time * 39.0 + 1.7),
			sin(pose_time * 53.0 + 3.1),
		) * amp
	position = pose_position + _loc_offset + _contact_offset
	rotation = pose_rotation + _loc_rotation + _contact_rotation
	# Transform from this node's space back into the WeaponRoot's space, so the
	# scabbard and the trail can be authored in root space while parented here.
	root_inverse = Transform3D(Basis.from_euler(pose_rotation), pose_position).affine_inverse()
	_update_sheath(snapshot)
	_update_glint(snapshot, delta)
	_update_trail(snapshot)
	click_flash.visible = false


func _root_space(node: Node3D, target_position: Vector3, target_rotation: Vector3) -> void:
	node.transform = root_inverse * Transform3D(Basis.from_euler(target_rotation), target_position)


func _update_sheath(snapshot: Dictionary) -> void:
	var move: SwordMoveset = combat.moveset
	if move == null or not move.sheath_enabled:
		sheath_prop.visible = false
		if _real_rig == null:
			if blade_part != null:
				blade_part.visible = true
				guard_part.visible = true
		else:
			_real_rig.visible = true
		return
	sheath_prop.visible = true
	if _real_saya != null:
		# See `_install_real_saya`: the scabbard is FIXED and the blade travels
		# into it, so this is the pose the blade arrives at, not the one it is at.
		var seated := Transform3D(Basis.from_euler(move.sheath_pose_rot), move.sheath_pose) \
			* Registry.saya_in_sword_frame(WEAPON_ID)
		_root_space(sheath_prop, seated.origin, seated.basis.get_euler())
	else:
		_root_space(sheath_prop, move.sheath_scabbard_pose, move.sheath_scabbard_rot)
	var sheathed: float = snapshot.sheath
	# The blade is inside the scabbard, so only the hilt stays visible.
	#
	# Still a `visible = false` even now that the saya is a real closed tube, and
	# on purpose: the blade travels to `sheath_pose` along a straight lerp, and a
	# straight lerp to a pose that is inside the bore is not the same path as
	# sliding down the bore. Over the last 45% of the travel the real blade would
	# be seen cutting through the real saya's wall, and hiding it at exactly the
	# moment the two disagree is what keeps the shot honest. It is also what the
	# placeholder did, so the read is unchanged.
	var inside := sheathed > 0.55
	if _real_rig == null:
		if blade_part != null:
			blade_part.visible = not inside
			guard_part.visible = true
	else:
		_real_rig.visible = not inside


func _update_glint(snapshot: Dictionary, delta: float) -> void:
	var wanted := 0.0
	if combat.edge_glint:
		wanted = 1.0
	elif combat.state == CombatController.State.CHARGE:
		wanted = 0.35 + combat.charge_ratio * 0.5
	elif float(snapshot.intensity) > 0.5:
		wanted = 0.16
	glint = lerpf(glint, wanted, minf(1.0, delta * 9.0))
	var active := glint > 0.02
	glint_band.visible = active and _blade_is_drawn() and swallowed < 0.999
	if active:
		_apply_fade()


func _update_trail(snapshot: Dictionary) -> void:
	var intensity: float = snapshot.intensity
	var origin: Vector3 = pose_position
	var tip: Vector3 = origin + (Basis.from_euler(pose_rotation) * Vector3.UP) * blade_length
	var base: Vector3 = origin + (Basis.from_euler(pose_rotation) * Vector3.UP) * -0.12
	if intensity > 0.4:
		trail_history.push_front(tip)
		if trail_history.size() > TRAIL_SAMPLES:
			trail_history.resize(TRAIL_SAMPLES)
	else:
		if trail_history.size() > 0:
			trail_history.pop_back()
			trail_history.pop_back()
	if trail_history.size() < 3:
		trail.visible = false
		return
	var travel := 0.0
	for i in range(1, trail_history.size()):
		travel = maxf(travel, trail_history[i - 1].distance_to(trail_history[i]))
	if travel < TRAIL_MIN_TIP_TRAVEL:
		trail.visible = false
		return
	_rebuild_trail(base, tip)
	_root_space(trail, Vector3.ZERO, Vector3.ZERO)
	trail.visible = true


func _rebuild_trail(base: Vector3, tip: Vector3) -> void:
	trail_mesh.clear_surfaces()
	var count := trail_history.size()
	var width: float = combat.moveset.trail_width
	trail_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in count:
		var fade := float(i) / float(count)
		var alpha := (1.0 - fade) * (1.0 - fade) * 0.42
		var sample_tip: Vector3 = trail_history[i]
		var sample_base := sample_tip + (tip - base).normalized() * -0.95
		# Widen very slightly toward the tip so the ribbon reads as a blade.
		trail_mesh.surface_set_color(Color(0.80, 0.90, 1.0, alpha * 0.35))
		trail_mesh.surface_add_vertex(sample_base)
		trail_mesh.surface_set_color(Color(0.94, 0.97, 1.0, alpha))
		trail_mesh.surface_add_vertex(sample_tip + (sample_tip - sample_base).normalized() * width)
	trail_mesh.surface_end()
