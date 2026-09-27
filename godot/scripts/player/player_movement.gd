extends CharacterBody3D

@export var tuning: CombatTuning = preload("res://resources/tuning/CombatTuning.tres")
@export var mouse_sensitivity := 0.0024

var health := 100.0
var mana := 100.0
var stamina := 100.0
var unlimited_resources := false

@onready var look_pivot: Node3D = $CameraRig/LookPivot
@onready var hurtbox: CombatHurtbox = $Hurtbox


func _ready() -> void:
	_bind_key("move_forward", KEY_W)
	_bind_key("move_back", KEY_S)
	_bind_key("move_left", KEY_A)
	_bind_key("move_right", KEY_D)
	_bind_key("jump", KEY_SPACE)
	_bind_key("sprint", KEY_SHIFT)
	_bind_key("dodge", KEY_Q)
	hurtbox.owner_actor = self
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _bind_key(action: StringName, key: Key) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var event := InputEventKey.new()
	event.physical_keycode = key
	InputMap.action_add_event(action, event)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity)
		$CameraFeedbackController.on_mouse_look(event.relative * mouse_sensitivity)
		look_pivot.rotate_x(-event.relative.y * mouse_sensitivity)
		look_pivot.rotation.x = clampf(look_pivot.rotation.x, -1.45, 1.45)
	elif event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _physics_process(delta: float) -> void:
	if unlimited_resources:
		mana = 100.0
		stamina = 100.0
	if not is_on_floor():
		velocity.y -= 14.0 * delta
	elif Input.is_action_just_pressed("jump"):
		velocity.y = tuning.jump_velocity

	var input_vector := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := (transform.basis * Vector3(input_vector.x, 0, input_vector.y)).normalized()
	var combat: CombatController = $CombatController
	if combat.state == combat.State.DODGE:
		velocity.x = combat.dodge_direction.x * combat.dodge_speed_now()
		velocity.z = combat.dodge_direction.z * combat.dodge_speed_now()
		move_and_slide()
		return
	if combat.state in [combat.State.IAIDO, combat.State.ULTIMATE]:
		velocity = Vector3.ZERO
		return
	# Attacks do not lock movement: they scale it, and they add a lunge whose
	# shape is authored per move. Styles that steer more (回风) simply feel freer.
	# 风步 multiplies on top: momentum magic changes how fast you can reposition,
	# it never teleports you.
	var speed := (
		(tuning.sprint_speed if Input.is_action_pressed("sprint") else tuning.walk_speed)
		* combat.movement_scale()
		* combat.speed_multiplier()
	)
	var target := direction * speed
	var lunge := combat.attack_lunge_velocity()
	if lunge != Vector3.ZERO:
		# A lunge is an impulse, not an acceleration ramp, or it never lands.
		velocity.x = target.x + lunge.x
		velocity.z = target.z + lunge.z
	else:
		velocity.x = move_toward(velocity.x, target.x, tuning.acceleration * delta)
		velocity.z = move_toward(velocity.z, target.z, tuning.acceleration * delta)
	move_and_slide()
