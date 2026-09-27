extends CanvasLayer
class_name CombatHUD

@onready var player: CharacterBody3D = get_parent().get_node("Player")
@onready var combat: CombatController = player.get_node("CombatController")
@onready var time_effects: TimeEffectManager = get_parent().get_node("TimeEffectManager")

var health_bar: ProgressBar
var mana_bar: ProgressBar
var stamina_bar: ProgressBar
var status_label: Label
var banner: Label
var banner_until := 0.0
var wheel: RadialWheel
var wheel_open := false
var pending_spell: StringName = &""
var wheel_vector := Vector2.ZERO
# Set by IaidoDirector. A signature skill is a performance, not a readout, so
# the HUD drops to a whisper for the duration and comes straight back.
var iaido_presence := 1.0


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
	status_label.position = Vector2(-330, -74)
	status_label.custom_minimum_size = Vector2(310, 60)
	add_child(status_label)
	# A style must be felt, not read off a damage number. This banner is only
	# for confirming that a window opened (ripposte, glint, enhance), and it
	# never shows damage.
	banner = Label.new()
	banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	banner.position = Vector2(-160, 74)
	banner.custom_minimum_size = Vector2(320, 30)
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.modulate.a = 0.0
	add_child(banner)
	combat.style_message.connect(_show_banner)
	wheel = RadialWheel.new()
	wheel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	wheel.position = Vector2(-140, -140)
	wheel.visible = false
	add_child(wheel)


func _show_banner(text: String) -> void:
	banner.text = text
	banner_until = Time.get_ticks_msec() / 1000.0 + 1.5


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

func _process(delta: float) -> void:
	health_bar.value = player.get("health")
	mana_bar.value = player.get("mana")
	stamina_bar.value = player.get("stamina")
	var chain := ""
	if combat.attack_kind in [&"light", &"sprint", &"retreat"] and combat.combo_index > 0:
		chain = "  ·  %d/%d" % [combat.combo_index, combat.moveset.light_chain.size()]
	var state_tag := String(CombatController.State.keys()[combat.state])
	status_label.text = "%s\n%s  ·  %s%s  ·  E CAST %s" % [
		combat.moveset.display_name,
		String(combat.selected_spell).to_upper(),
		state_tag,
		chain,
		("纳息 %.1fs" % combat.enhance_left) if combat.enhance_left > 0.0 else "",
	]
	if banner_until > 0.0:
		var left := banner_until - Time.get_ticks_msec() / 1000.0
		banner.modulate.a = clampf(left / 0.5, 0.0, 1.0)
		if left <= 0.0:
			banner_until = 0.0
			banner.modulate.a = 0.0
	var quiet := health_bar.value >= 100.0 and mana_bar.value >= 100.0 and stamina_bar.value >= 100.0 and combat.state == CombatController.State.IDLE
	var opacity := (0.45 if quiet else 1.0) * iaido_presence
	health_bar.modulate.a = opacity
	mana_bar.modulate.a = opacity
	stamina_bar.modulate.a = opacity
	status_label.modulate.a = opacity


func set_iaido_presence(value: float) -> void:
	iaido_presence = clampf(value, 0.0, 1.0)


func _exit_tree() -> void:
	if wheel_open:
		time_effects.reset()
