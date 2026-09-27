extends CanvasLayer

@onready var sandbox: Node3D = get_parent()
@onready var player: CharacterBody3D = sandbox.get_node("Player")
@onready var combat: CombatController = player.get_node("CombatController")
@onready var camera_feedback: CameraFeedbackController = player.get_node("CameraFeedbackController")
@onready var dummy: Node3D = sandbox.get_node("TechnicalDummy")

var panel: PanelContainer
var slow_motion := false
var camera_preset_button: Button


func _ready() -> void:
	panel = PanelContainer.new()
	panel.position = Vector2(20, 20)
	panel.visible = false
	add_child(panel)
	var rows := VBoxContainer.new()
	panel.add_child(rows)
	var title := Label.new()
	title.text = "SEKAI · Combat Lab (F8)"
	rows.add_child(title)
	_add_button(rows, "Reset Enemy", _reset_enemy)
	_add_button(rows, "Spawn Enemy", _spawn_enemy)
	_add_button(rows, "Heal", func() -> void: player.set("health", 100.0))
	_add_button(rows, "Restore Mana", func() -> void: player.set("mana", 100.0))
	_add_button(rows, "Restore Stamina", func() -> void: player.set("stamina", 100.0))
	_add_button(rows, "Freeze Enemy", _freeze_enemy)
	_add_button(rows, "Reset Action", combat.finish_action)
	_add_button(rows, "Trigger Iaido", func() -> void: combat.request(&"iaido"))
	_add_button(rows, "Slow Motion", _toggle_slow_motion)
	camera_preset_button = _add_button(rows, "Camera: Normal", _cycle_camera_preset)
	_add_unavailable(rows, "Hitbox View · pending")


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F8:
		panel.visible = not panel.visible
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if panel.visible else Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()


func _add_button(parent: VBoxContainer, title: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = title
	button.pressed.connect(callback)
	parent.add_child(button)
	return button


func _cycle_camera_preset() -> void:
	camera_preset_button.text = "Camera: " + camera_feedback.cycle_preset()


func _add_unavailable(parent: VBoxContainer, title: String) -> void:
	var button := Button.new()
	button.text = title
	button.disabled = true
	parent.add_child(button)


func _reset_enemy() -> void:
	dummy.call("reset_dummy")


func _spawn_enemy() -> void:
	var scene: PackedScene = load("res://scenes/enemies/TechnicalDummy.tscn")
	var clone := scene.instantiate() as Node3D
	sandbox.add_child(clone)
	clone.global_position = dummy.global_position + Vector3(3, 0, 0)


func _freeze_enemy() -> void:
	dummy.call("freeze_for_debug")


func _toggle_slow_motion() -> void:
	slow_motion = not slow_motion
	Engine.time_scale = 0.3 if slow_motion else 1.0


func _exit_tree() -> void:
	Engine.time_scale = 1.0
