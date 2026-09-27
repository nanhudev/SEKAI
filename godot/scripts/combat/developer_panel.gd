extends CanvasLayer

@onready var sandbox: Node3D = get_parent()
@onready var player: CharacterBody3D = sandbox.get_node("Player")
@onready var combat: CombatController = player.get_node("CombatController")
@onready var camera_feedback: CameraFeedbackController = player.get_node("CameraFeedbackController")
@onready var dummy: Node3D = sandbox.get_node("TechnicalDummy")
@onready var iaido: IaidoDirector = sandbox.get_node("IaidoDirector")

const STAGES: Array[Array] = [
	["A · Freeze", 0.25],
	["B · Sheath", 0.85],
	["C · Reverse Wave", 1.70],
	["D · Hold", 2.50],
	["E · Lock Click", 2.86],
	["F · Draw", 3.02],
	["G · Void", 3.60],
	["H · Glass", 4.50],
	["I · Spin", 5.05],
	["J · Slow Sheathe", 5.85],
	["K · Final Click", 6.22],
	["L · Restore", 6.95],
]

const SPEEDS: Array[float] = [0.25, 0.5, 1.0, 2.0]

var panel: PanelContainer
var slow_motion := false
var camera_preset_button: Button
var iaido_speed_button: Button
var scrub_slider: HSlider
var scrub_label: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
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
	_build_iaido_section(rows)
	_add_button(rows, "Slow Motion", _toggle_slow_motion)
	camera_preset_button = _add_button(rows, "Camera: Normal", _cycle_camera_preset)
	_add_unavailable(rows, "Hitbox View · pending")


func _build_iaido_section(rows: VBoxContainer) -> void:
	var title := Label.new()
	title.text = "Iaido Timeline Scrub"
	rows.add_child(title)

	scrub_slider = HSlider.new()
	scrub_slider.min_value = 0.0
	scrub_slider.max_value = iaido.tuning.restore_end
	scrub_slider.step = 0.01
	scrub_slider.value = 0.0
	scrub_slider.custom_minimum_size = Vector2(240, 0)
	scrub_slider.value_changed.connect(_on_scrub)
	rows.add_child(scrub_slider)

	scrub_label = Label.new()
	scrub_label.text = "0.00 s / %.2f s" % iaido.tuning.restore_end
	rows.add_child(scrub_label)

	_add_button(rows, "Resume Iaido Timeline", iaido.release_debug_hold)

	var grid := GridContainer.new()
	grid.columns = 2
	rows.add_child(grid)
	for stage in STAGES:
		var label: String = stage[0]
		var time: float = stage[1]
		var button := Button.new()
		button.text = label
		button.pressed.connect(func() -> void: _jump(time))
		grid.add_child(button)

	iaido_speed_button = _add_button(rows, "Iaido Speed: 1.0x", _toggle_iaido_speed)
	_add_button(rows, "Reset Iaido FX", iaido.finish_iaido)


func _jump(time: float) -> void:
	iaido.set_debug_hold(time)
	scrub_slider.value = time
	scrub_label.text = "%.2f s / %.2f s" % [time, iaido.tuning.restore_end]


func _on_scrub(value: float) -> void:
	iaido.set_debug_hold(value)
	scrub_label.text = "%.2f s / %.2f s" % [value, iaido.tuning.restore_end]


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


func _toggle_iaido_speed() -> void:
	var index := SPEEDS.find(iaido.playback_speed)
	if index < 0:
		index = 2
	var speed: float = SPEEDS[(index + 1) % SPEEDS.size()]
	iaido.set_debug_speed(speed)
	iaido_speed_button.text = "Iaido Speed: %.2fx" % speed


func _exit_tree() -> void:
	Engine.time_scale = 1.0
