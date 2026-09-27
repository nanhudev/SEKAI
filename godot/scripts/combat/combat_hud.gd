extends CanvasLayer
class_name CombatHUD

@onready var player: CharacterBody3D = get_parent().get_node("Player")
@onready var combat: CombatController = player.get_node("CombatController")
@onready var time_effects: TimeEffectManager = get_parent().get_node("TimeEffectManager")

var health_bar: ProgressBar
var mana_bar: ProgressBar
var stamina_bar: ProgressBar
var status_label: Label
var wheel: RadialWheel
var wheel_open := false
var pending_spell: StringName = &""
var wheel_vector := Vector2.ZERO


func _ready() -> void:
	layer = 2
	var bars := VBoxContainer.new()
	bars.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	bars.position = Vector2(24, -120)
	bars.custom_minimum_size = Vector2(220, 100)
	add_child(bars)
	health_bar = _make_bar(bars, "HP", Color(0.75, 0.27, 0.25))
	mana_bar = _make_bar(bars, "MANA", Color(0.42, 0.7, 0.78))
	stamina_bar = _make_bar(bars, "STAMINA", Color(0.7, 0.73, 0.45))
	status_label = Label.new()
	status_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	status_label.position = Vector2(-250, -60)
	status_label.custom_minimum_size = Vector2(230, 42)
	add_child(status_label)
	wheel = RadialWheel.new()
	wheel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	wheel.position = Vector2(-140, -140)
	wheel.visible = false
	add_child(wheel)


func _make_bar(parent: VBoxContainer, caption: String, color: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(220, 24)
	bar.max_value = 100.0
	bar.value = 100.0
	bar.show_percentage = false
	bar.tooltip_text = caption
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	bar.add_theme_stylebox_override("fill", fill)
	parent.add_child(bar)
	return bar

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.keycode == KEY_TAB and not event.echo:
		if event.pressed and not wheel_open and combat.state != CombatController.State.IAIDO:
			open_wheel()
		elif not event.pressed and wheel_open:
			close_wheel()
		get_viewport().set_input_as_handled()
	elif wheel_open and event is InputEventMouseMotion:
		wheel_vector = (wheel_vector + event.relative).limit_length(180.0)
		wheel.set_direction(wheel_vector)
		pending_spell = wheel.selected_spell
		get_viewport().set_input_as_handled()
	elif wheel_open and event is InputEventMouseButton:
		get_viewport().set_input_as_handled()


func open_wheel() -> void:
	wheel_open = true
	pending_spell = &""
	wheel_vector = Vector2.ZERO
	wheel.set_direction(Vector2.ZERO)
	wheel.visible = true
	time_effects.request_slow_motion(0.3, 3600.0)


func close_wheel() -> void:
	wheel_open = false
	wheel.visible = false
	if pending_spell != &"":
		combat.selected_spell = pending_spell
	time_effects.reset()

func _process(_delta: float) -> void:
	health_bar.value = player.get("health")
	mana_bar.value = player.get("mana")
	stamina_bar.value = player.get("stamina")
	status_label.text = "SWORD  ·  %s  ·  E CAST" % String(combat.selected_spell).to_upper()
	var quiet := health_bar.value >= 100.0 and mana_bar.value >= 100.0 and stamina_bar.value >= 100.0 and combat.state == CombatController.State.IDLE
	var opacity := 0.45 if quiet else 1.0
	health_bar.modulate.a = opacity
	mana_bar.modulate.a = opacity
	stamina_bar.modulate.a = opacity
	status_label.modulate.a = opacity


func _exit_tree() -> void:
	if wheel_open:
		time_effects.reset()
