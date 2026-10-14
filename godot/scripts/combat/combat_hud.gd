extends CanvasLayer
class_name CombatHUD

@onready var player: CharacterBody3D = get_parent().get_node("Player")
@onready var combat: CombatController = player.get_node("CombatController")
@onready var time_effects: TimeEffectManager = get_parent().get_node("TimeEffectManager")
@onready var weapon: WeaponSlot = player.get_node("WeaponSlot")
@onready var chain: ChainDirector = player.get_node("ChainDirector")

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
	# 缚星链 says when the chain goes taut, when it catches something and when a
	# bind opens, and it does it through the same banner the sword uses for its
	# windows. A state the player must not need a gauge for still has to be
	# announced once, or TENSION would be invisible.
	chain.message.connect(_show_banner)
	wheel = RadialWheel.new()
	wheel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	wheel.position = Vector2(-140, -140)
	wheel.visible = false
	add_child(wheel)
	_feed_wheel()
	wheel.armed = combat.spell_id
	# INPUT CONTRACT: Tab Hold = Combat UI (this wheel). Tab Tap = Backpack hook.
	var input_contract := get_node_or_null("/root/InputContract")
	if input_contract != null:
		input_contract.combat_ui_hold_started.connect(_on_combat_ui_hold_started)
		input_contract.combat_ui_hold_ended.connect(_on_combat_ui_hold_ended)
		input_contract.backpack_requested.connect(_on_backpack_requested)


# One sector per SPELL, built from the library rather than written out here.
# Adding a spell to MagicLibrary therefore adds a sector for free — and, more to
# the point, the wheel can no longer be structurally incapable of offering a
# spell that exists, which is how half the magic content went missing.
func _feed_wheel() -> void:
	var entries: Array = []
	for school_id in combat.schools:
		var school: MagicSchool = combat.schools[school_id]
		var tint := Color(0.80, 0.88, 0.95)
		if school.element != null:
			tint = school.element.tint
		for spell in school.spells:
			entries.append({
				"id": spell.id,
				"label": spell.display_name,
				"color": tint,
				"group": school.display_name,
			})
	wheel.set_entries(entries)


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
	# Tab open/close is owned by InputContract (tap vs hold). While the wheel is
	# open, mouse aim still lives here.
	if wheel_open and event is InputEventMouseMotion:
		aim_wheel(wheel_vector + event.relative)
		get_viewport().set_input_as_handled()
	elif wheel_open and event is InputEventMouseButton:
		get_viewport().set_input_as_handled()


func _on_combat_ui_hold_started() -> void:
	if wheel_open or combat.state == CombatController.State.IAIDO:
		return
	open_wheel()


func _on_combat_ui_hold_ended() -> void:
	if wheel_open:
		close_wheel()


func _on_backpack_requested() -> void:
	# No formal inventory yet — safe prototype hook only. Do not flash Combat UI.
	if wheel_open:
		return
	_show_banner("背包 · Backpack (prototype)")


# The pointer, in one place, so a test drives the same function the mouse does.
# Duplicating "move the pointer then read the sector" in the test would let the
# test pass while _input itself was broken.
func aim_wheel(direction: Vector2) -> void:
	wheel_vector = direction.limit_length(180.0)
	wheel.set_direction(wheel_vector)
	pending_spell = wheel.selected_spell


func open_wheel() -> void:
	wheel_open = true
	pending_spell = &""
	wheel_vector = Vector2.ZERO
	wheel.set_direction(Vector2.ZERO)
	wheel.armed = combat.spell_id
	wheel.visible = true
	time_effects.request_slow_motion(0.3, 3600.0)


# The readout has to name the armed SPELL. Showing only the school made 寒流 and
# 凝霜 look identical on screen, so nothing could reveal that the wheel was
# always arming the primary.
func _armed_label() -> String:
	var spell := combat.current_spell()
	if spell == null:
		return String(combat.selected_school).to_upper()
	return "%s %s" % [String(combat.selected_school).to_upper(), spell.display_name]


func close_wheel() -> void:
	wheel_open = false
	wheel.visible = false
	# Arms the SPELL the pointer rested on, not a school. Every source of "what
	# is in my hand" goes through this one call.
	if pending_spell != &"":
		combat.select_spell(pending_spell)
		wheel.armed = combat.spell_id
	time_effects.reset()

func _process(delta: float) -> void:
	health_bar.value = player.get("health")
	mana_bar.value = player.get("mana")
	stamina_bar.value = player.get("stamina")
	# A weapon switch changes what the readout is about, not just its words: the
	# sword reports a style and a chain count, the chain reports the three numbers
	# it actually runs on. Neither is a damage table.
	if weapon != null and not weapon.is_sword():
		status_label.text = "缚星链\n%s  ·  %s" % [chain.debug_state_line(), _armed_label()]
	else:
		var chain_text := ""
		if combat.attack_kind in [&"light", &"sprint", &"retreat"] and combat.combo_index > 0:
			chain_text = "  ·  %d/%d" % [combat.combo_index, combat.moveset.light_chain.size()]
		# §16 PLAYTEST CLEAN MODE. The state machine's own vocabulary - IDLE, ATTACK,
		# RIPOSTE, CHARGE - was on screen for the same reason a developer readout is:
		# it is how you tell one window from another while authoring. It is not what a
		# player may know, and this line is now the two things they may: what is in the
		# hand and what is armed. Everything numeric is one F8 away.
		status_label.text = "%s\n%s%s" % [
			combat.moveset.display_name,
			_armed_label(),
			chain_text,
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
