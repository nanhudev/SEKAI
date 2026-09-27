extends Node3D

@export var shatter_scene: PackedScene = preload("res://scenes/combat/ShatterVFX.tscn")
@export var sandbox_unlimited_resources := true

@onready var dummy: Node3D = $TechnicalDummy
@onready var player: CharacterBody3D = $Player
@onready var camera_feedback: CameraFeedbackController = player.get_node("CameraFeedbackController")
@onready var screen_fx: CombatScreenFX = $CombatScreenFX
@onready var time_effects: TimeEffectManager = $TimeEffectManager
@onready var weapon: WeaponSlot = player.get_node("WeaponSlot")

# The first-person weapon rigs that have to get out of the way when the other
# language is in hand. TempSwordVisual is the placeholder; Sword_FP is the real
# rig ART is building to replace it (see scenes/weapons/Sword_FP.tscn), which is
# why this is a list and not a single path.
const SWORD_RIGS := [
	"CameraRig/LookPivot/MotionPivot/ShakePivot/WeaponRoot/TempSwordVisual",
]

# Placeholder wind environment: a wall to be thrown into and light bodies that
# actually move. Built in code so ART can replace it wholesale later.
var wind_props: WindProps
# A second stage, because movement and combat cannot share one: the dummy stands
# on the line the player walks down. See MovementLane.
var movement_lane: MovementLane
# A third stage, because a weapon about SPACE cannot be judged in a 24m box with an
# enemy on the walking line. See ChainLab.
var chain_lab: ChainLab


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
	weapon.changed.connect(_on_weapon_changed)
	_apply_weapon_visibility()
	screen_fx.reset()
	call_deferred("_check_visual_state")


func _on_weapon_changed(_previous: StringName, _current: StringName) -> void:
	_apply_weapon_visibility()


# 玩家没有职业，只有经历 — and the hands still hold ONE weapon at a time. Nothing took
# the sword's rig away when the slot changed, so a player holding 缚星链 kept a 95cm
# blade and its grip drawn in the other hand: at all times, in every frame, and
# invisibly to the chain's own tests, because a weapon that is not being asked about
# does not appear in anyone's failure message.
#
# The SCENE owns this rather than either weapon. A weapon that knew how to hide the
# other weapon would be the same class of mistake as a controller with style
# branches, and it would have to be un-taught the moment a third language arrives —
# which is exactly what this build is.
func _apply_weapon_visibility() -> void:
	var sword_in_hand := weapon.is_sword()
	for path in SWORD_RIGS:
		var rig := player.get_node_or_null(path) as Node3D
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