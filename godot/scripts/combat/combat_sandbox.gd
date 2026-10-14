extends Node3D

@export var shatter_scene: PackedScene = preload("res://scenes/combat/ShatterVFX.tscn")
@export var sandbox_unlimited_resources := true

@onready var dummy: Node3D = $TechnicalDummy
@onready var player: CharacterBody3D = $Player
@onready var camera_feedback: CameraFeedbackController = player.get_node("CameraFeedbackController")
@onready var screen_fx: CombatScreenFX = $CombatScreenFX
@onready var time_effects: TimeEffectManager = $TimeEffectManager
@onready var weapon: WeaponSlot = player.get_node("WeaponSlot")

# --- WEAPON VISIBILITY MOVED ---------------------------------------------------
# The sword rig used to be hidden from here, and the reasoning below was right but
# the LOCATION was not: a second scene (the Training Ground's playtest) needs the same
# rule, and the only way to give it that without a second copy of the path list is for
# the rule to live in the node that does the switching. It is now
# `WeaponManager._apply_weapon_visibility()` on the Player, so every scene that mounts
# a Player gets it - including this one - and there is exactly one copy of the list.
#
# What it does, and why it is not either weapon's business: 玩家没有职业，只有经历 —
# and the hands still hold ONE weapon at a time. Nothing took the sword's rig away
# when the slot changed, so a player holding 缚星链 kept a 95cm blade and its grip
# drawn in the other hand: at all times, in every frame, and invisibly to the chain's
# own tests, because a weapon that is not being asked about does not appear in
# anyone's failure message. A weapon that knew how to hide the other weapon would be
# the same class of mistake as a controller with style branches.

# Placeholder wind environment: a wall to be thrown into and light bodies that
# actually move. Built in code so ART can replace it wholesale later.
var wind_props: WindProps
# A second stage, because movement and combat cannot share one: the dummy stands
# on the line the player walks down. See MovementLane.
var movement_lane: MovementLane
# A third stage, because a weapon about SPACE cannot be judged in a 24m box with an
# enemy on the walking line. See ChainLab.
var chain_lab: ChainLab
# A fourth, for the signature's execution: one body cannot answer "does a
# construct fail differently from a biological", and three enemies dying to one
# slash is the thing §P is about. See ExecutionLab.
var execution_lab: ExecutionLab


func _ready() -> void:
	dummy.shattered.connect(_on_shattered)
	player.unlimited_resources = sandbox_unlimited_resources
	wind_props = WindProps.new()
	wind_props.name = "WindProps"
	add_child(wind_props)
	movement_lane = MovementLane.new()
	movement_lane.name = "MovementLane"
	add_child(movement_lane)
	chain_lab = ChainLab.new()
	chain_lab.name = "ChainLab"
	add_child(chain_lab)
	execution_lab = ExecutionLab.new()
	execution_lab.name = "ExecutionLab"
	add_child(execution_lab)
	# The review labels are a developer tool. A frame anyone watches is rendered
	# with them off — the same rule the arena's own review markers follow.
	execution_lab.set_labels_visible(false)
	weapon.changed.connect(_on_weapon_changed)
	_apply_weapon_visibility()
	screen_fx.reset()
	call_deferred("_check_visual_state")


func _on_weapon_changed(_previous: StringName, _current: StringName) -> void:
	_apply_weapon_visibility()


# Kept as a thin pass-through because a stage is still allowed to ask "is the sword
# really out of the way" and because removing the call sites above would have made
# this file's diff larger than the move it is describing. The rule itself lives on the
# Player now; see the note above.
func _apply_weapon_visibility() -> void:
	var manager := player.get_node_or_null("WeaponManager")
	if manager != null and manager.has_method("apply_weapon_visibility"):
		manager.call("apply_weapon_visibility")
		return
	# No manager (a stage that predates the weapon switch): hide the sword whenever the
	# chain is in hand, which is the whole of the rule.
	var sword_in_hand := weapon.is_sword()
	var rig := player.get_node_or_null(
		"CameraRig/LookPivot/MotionPivot/ShakePivot/WeaponRoot/TempSwordVisual"
	) as Node3D
	if rig != null:
		rig.visible = sword_in_hand


func _on_shattered() -> void:
	var effect := shatter_scene.instantiate() as Node3D
	add_child(effect)
	effect.global_position = dummy.global_position
	camera_feedback.add_trauma(0.32)
	camera_feedback.add_impulse(Vector2(0.025, -0.035))
	screen_fx.flash_hit(0.22)
	time_effects.request_hitstop(0.085)

func _check_visual_state() -> void:
	var camera: Camera3D = player.get_node("CameraRig/LookPivot/MotionPivot/ShakePivot/Camera3D")
	if not camera.is_current():
		camera.make_current()
	var world_environment: WorldEnvironment = $WorldEnvironment
	print("SEKAI VISUAL camera_current=", camera.is_current(), " camera_pos=", camera.global_position, " camera_forward=", -camera.global_basis.z, " player_pos=", player.global_position, " environment=", world_environment.environment != null, " viewport=", get_viewport().get_visible_rect().size, " sandbox_visible=", is_visible_in_tree(), " fx_visible=", screen_fx.overlay.visible)