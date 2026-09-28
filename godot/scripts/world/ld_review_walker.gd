extends CharacterBody3D
class_name LDReviewWalker
## Level-design review walker for the Mistvale greybox.
##
## WHY THIS EXISTS INSTEAD OF Player.tscn: CombatController reaches for six
## sibling presentation nodes (CombatScreenFX, TimeEffectManager, IaidoDirector,
## IaidoScreenFX, IaidoGlassLayer, IaidoAudioTimeline) and IaidoDirector in turn
## pulls in AudioStateController and WorldPauseManager. Dropping Player into the
## region scene would mean reconstructing half of CombatSandbox inside it — a
## MAIN-owned construct that would silently rot.
##
## So GATE 1 gets its own walker: real collision against the real terrain, at
## the real player speeds. Enough to prove "can you walk Prologue -> Ruins".
## Player.tscn integration is a MAIN hand-off (see masterplan §20).


# Speeds match combat_tuning.gd so traversal timings measured here transfer.
const WALK_SPEED := 5.0
const SPRINT_SPEED := 8.0
const GRAVITY := 22.0
const LOOK_SENSITIVITY := 0.0022

@export var start_position := Vector3(200.0, 40.0, 320.0)

var _yaw := 0.0
var _pitch := 0.0


@onready var _pivot: Node3D = $LookPivot
@onready var _camera: Camera3D = $LookPivot/Camera3D


func _ready() -> void:
	# THE SPAWN HEIGHT IS SAMPLED, NOT AUTHORED.
	#
	# start_position.y is ignored on purpose. The scene file asked for y = 42 at
	# (200, 320) and the ground there is 34.2 — so the player's first second in
	# the map was an 8 m fall, in the dark, before they had touched a key. That
	# is the same class of bug the masterplan calls out: a hand-written elevation
	# that disagrees with the height field. Only x/z are taken from the export,
	# and the field supplies the rest.
	position = Vector3(
		start_position.x,
		MistvaleHeights.height_at(start_position.x, start_position.z) + 1.2,
		start_position.z
	)
	# Face roughly north-west: from the East Forest spawn the player should be
	# looking toward the valley, not back into the trees.
	_yaw = deg_to_rad(140.0)
	_apply_look()


func _unhandled_input(event: InputEvent) -> void:
	# LOOK FOLLOWS MOUSE_MODE, NOT A PRIVATE FLAG.
	#
	# This used to keep its own `_captured` bool, set on the first left click and
	# cleared on Escape. That works when the scene is the whole game and breaks
	# the moment it is mounted under Main.tscn: the pause menu owns Escape, so
	# resuming re-captures the cursor through main_flow while the walker's flag
	# is still false — you come back from the pause menu unable to look around,
	# with no hint that a click would fix it. Deriving from Input.mouse_mode
	# means whoever captures the cursor — this walker, the pause menu, the
	# window regaining focus — gets a working camera.
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_yaw -= event.relative.x * LOOK_SENSITIVITY
		_pitch = clampf(
			_pitch - event.relative.y * LOOK_SENSITIVITY, deg_to_rad(-80.0), deg_to_rad(80.0)
		)
		_apply_look()
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _apply_look() -> void:
	if _pivot == null:
		return
	_pivot.rotation.x = _pitch
	rotation.y = _yaw


func _physics_process(delta: float) -> void:
	# Raw key codes, not Input actions. project.godot currently declares no
	# [input] map at all, so "move_forward" / "sprint" resolve to nothing and
	# any script depending on them is dead. Reading keys directly keeps this
	# review tool working regardless of MAIN's input map status.
	var input := Vector2(
		float(Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_A)),
		float(Input.is_key_pressed(KEY_S)) - float(Input.is_key_pressed(KEY_W))
	)
	if input == Vector2.ZERO:
		input = Vector2(
			float(Input.is_key_pressed(KEY_RIGHT)) - float(Input.is_key_pressed(KEY_LEFT)),
			float(Input.is_key_pressed(KEY_DOWN)) - float(Input.is_key_pressed(KEY_UP))
		)

	var basis := Basis(Vector3.UP, _yaw)
	var direction := (basis * Vector3(input.x, 0.0, input.y)).normalized()
	var speed := SPRINT_SPEED if Input.is_key_pressed(KEY_SHIFT) else WALK_SPEED

	velocity.x = direction.x * speed
	velocity.z = direction.z * speed

	# Space / Ctrl for vertical: a greybox review needs to get onto a terrace
	# without walking every stair, and to hover a Vista to check its framing.
	if Input.is_key_pressed(KEY_SPACE):
		velocity.y = speed * 0.6
	elif Input.is_key_pressed(KEY_CTRL):
		velocity.y = -speed * 0.6
	else:
		velocity.y -= GRAVITY * delta

	move_and_slide()
