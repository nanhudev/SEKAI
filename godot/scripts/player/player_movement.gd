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
		velocity.x = combat.dodge_direction.x * combat.dodge_speed
		velocity.z = combat.dodge_direction.z * combat.dodge_speed
		move_and_slide()
		return
	if combat.state == combat.State.IAIDO and combat.state_time >= 0.32 and combat.state_time < 0.49:
		velocity.x = -transform.basis.z.x * 19.0
		velocity.z = -transform.basis.z.z * 19.0
		move_and_slide()
		return
	var speed := tuning.sprint_speed if Input.is_action_pressed("sprint") else tuning.walk_speed
	var target := direction * speed
	if combat.state == combat.State.ATTACK and combat.attack_kind == &"light" and combat.combo_index == 3 and combat.state_time >= 0.09 and combat.state_time < 0.21:
		target += -transform.basis.z * 4.0
	velocity.x = move_toward(velocity.x, target.x, tuning.acceleration * delta)
	velocity.z = move_toward(velocity.z, target.z, tuning.acceleration * delta)
	move_and_slide()
