extends CharacterBody3D
class_name SekaiPlayer

@export var walk_speed := 6.0
@export var sprint_speed := 9.5
@export var acceleration := 18.0
@export var air_control := 4.0
@export var jump_velocity := 6.0
@export var gravity := 19.0

var camera: Camera3D
var head: Node3D
var yaw := 0.0
var pitch := 0.0
var hp := 100.0
var mana := 100.0
var stamina := 100.0
var weapon := "sword"
var spell := "fire"
var input_enabled := false
var bob := 0.0
var trauma := 0.0
var trauma_time := 0.0
var dodge_left := 0.0
var dodge_dir := Vector3.ZERO

func _ready() -> void:
	var shape := CapsuleShape3D.new()
	shape.radius = 0.34
	shape.height = 1.75
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.position.y = 0.88
	add_child(collision)
	head = Node3D.new()
	head.name = "CameraRig"
	head.position.y = 1.6
	add_child(head)
	camera = Camera3D.new()
	camera.current = true
	camera.fov = 76.0
	head.add_child(camera)
	floor_snap_length = 0.32
	floor_max_angle = deg_to_rad(48.0)

func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		yaw -= event.relative.x * 0.0021
		pitch = clampf(pitch - event.relative.y * 0.0021, -1.42, 1.42)
		rotation.y = yaw
		head.rotation.x = pitch

func _physics_process(delta: float) -> void:
	if not input_enabled:
		return
	var x := float(Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_A))
	var z := float(Input.is_key_pressed(KEY_S)) - float(Input.is_key_pressed(KEY_W))
	var wish := (transform.basis * Vector3(x, 0, z)).normalized()
	var running := Input.is_key_pressed(KEY_SHIFT) and stamina > 2.0 and wish.length() > 0.1
	var speed := sprint_speed if running else walk_speed
	if Input.is_key_pressed(KEY_CTRL):
		speed *= 0.48
	if running:
		stamina = maxf(0.0, stamina - 22.0 * delta)
	else:
		stamina = minf(100.0, stamina + 18.0 * delta)
	if dodge_left > 0.0:
		dodge_left -= delta
		velocity.x = dodge_dir.x * 14.0
		velocity.z = dodge_dir.z * 14.0
	else:
		var rate := acceleration if is_on_floor() else air_control
		velocity.x = move_toward(velocity.x, wish.x * speed, rate * delta)
		velocity.z = move_toward(velocity.z, wish.z * speed, rate * delta)
	if not is_on_floor():
		velocity.y -= gravity * delta
	elif Input.is_key_pressed(KEY_SPACE):
		velocity.y = jump_velocity
	else:
		velocity.y = -0.1
	move_and_slide()
	if is_on_floor() and wish.length() > 0.1:
		bob += delta * (12.0 if running else 8.0)
	else:
		bob = 0.0
	trauma_time = maxf(0.0, trauma_time - delta)
	trauma = move_toward(trauma, 0.0, delta * 3.0)
	camera.position.y = sin(bob) * 0.027 + randf_range(-trauma, trauma) * 0.055
	camera.position.x = randf_range(-trauma, trauma) * 0.035
	camera.fov = lerpf(camera.fov, 79.0 if running else 76.0, delta * 5.0)

func dodge() -> void:
	if stamina < 22.0 or dodge_left > 0.0:
		return
	stamina -= 22.0
	dodge_dir = -global_transform.basis.z
	dodge_left = 0.2
	add_trauma(0.1)

func add_trauma(amount: float) -> void:
	trauma = minf(1.0, trauma + amount)
	trauma_time = 0.12

func forward() -> Vector3:
	return -camera.global_transform.basis.z

