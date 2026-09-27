extends CanvasLayer
# SEKAI · Combat Lab (F8)
#
# The lab exists so the sword can be judged by feel, quickly: switch the style,
# force a specific enemy attack, exaggerate or remove hitstop, and read the
# actual perfect-guard window while it is open.

@onready var sandbox: Node3D = get_parent()
@onready var player: CharacterBody3D = sandbox.get_node("Player")
@onready var combat: CombatController = player.get_node("CombatController")
@onready var camera_feedback: CameraFeedbackController = player.get_node("CameraFeedbackController")
@onready var dummy: Node3D = sandbox.get_node("TechnicalDummy")
@onready var iaido: IaidoDirector = sandbox.get_node("IaidoDirector")
@onready var ultimate: MomentOfNoMoonDirector = sandbox.get_node("MomentOfNoMoonDirector")
@onready var parry_debug: ParryDebugOverlay = sandbox.get_node("ParryDebugOverlay")
# NOT @onready: children are readied before the sandbox's own _ready(), which is
# where WindProps is built. Resolving it here would leave the whole environment
# section silently dead.
var wind_props: WindProps

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
var hitstop_button: Button
var unlock_button: Button
var style_label: Label
var status_label: Label
var skill_buttons: Array[Button] = []
var scrub_slider: HSlider
var scrub_label: Label
# The Lab is a MATRIX now, not a menu: style x magic x enemy state x environment.
# The point is that any row can be crossed with any column in a few seconds, so
# the 3x3 combat tendencies can actually be found rather than argued about.
var magic_label: Label
var enemy_label: Label
var world_label: Label
var spell_buttons: Array[Button] = []
var school_buttons: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	panel = PanelContainer.new()
	panel.position = Vector2(20, 20)
	panel.custom_minimum_size = Vector2(300, 0)
	panel.visible = false
	add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(300, 620)
	panel.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.custom_minimum_size = Vector2(280, 0)
	scroll.add_child(rows)

	var title := Label.new()
	title.text = "SEKAI · Combat Lab (F8)"
	rows.add_child(title)

	status_label = Label.new()
	status_label.custom_minimum_size = Vector2(280, 0)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rows.add_child(status_label)

	_add_section(rows, "STYLE")
	style_label = Label.new()
	style_label.custom_minimum_size = Vector2(280, 0)
	style_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rows.add_child(style_label)
	for style_id in SwordMovesetLibrary.all_styles():
		var moveset := SwordMovesetLibrary.build(style_id)
		_add_button(rows, "Style · " + moveset.display_name, func() -> void: combat.set_style(style_id, true))

	_add_section(rows, "STYLE SKILLS")
	for i in 3:
		var index := i
		var button := _add_button(rows, "Skill %d" % (i + 1), func() -> void: combat.trigger_skill(index))
		skill_buttons.append(button)
	_add_button(rows, "Reset Skill Cooldowns", combat.reset_skill_cooldowns)
	_add_button(rows, "聚合斩 · Signature (SIGNATURE)", func() -> void: combat.request(&"iaido"))
	_add_button(rows, "无明一刻 · Ultimate", func() -> void: combat.request(&"ultimate"))

	# --- MAGIC -------------------------------------------------------------
	# Magic is a school you carry, not a skill bar: pick the school, watch the
	# blade, and check that the three behave differently without reading numbers.
	_add_section(rows, "MAGIC")
	magic_label = Label.new()
	magic_label.custom_minimum_size = Vector2(280, 0)
	magic_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rows.add_child(magic_label)
	for school_id in MagicLibrary.all().keys():
		var school: MagicSchool = MagicLibrary.get_school(school_id)
		var id: StringName = school_id
		var button := _add_button(rows, "School · %s" % school.display_name, func() -> void: _select_school(id))
		button.set_meta("label", "School · %s" % school.display_name)
		school_buttons[id] = button
	for i in 3:
		var index := i
		var button := _add_button(rows, "-", func() -> void: _select_spell(index))
		spell_buttons.append(button)
	_add_button(rows, "Cast (Quick Magic, sword stays)", func() -> void: combat.request(&"cast"))
	_add_button(rows, "Wind Spread (blow fields + objects)", _wind_spread)

	_add_section(rows, "ENEMY")
	_add_button(rows, "Reset Enemy", _reset_enemy)
	_add_button(rows, "Attack · Sweep (dodge check)", func() -> void: _force_attack(0))
	_add_button(rows, "Attack · Heavy (parry check)", func() -> void: _force_attack(1))
	_add_button(rows, "Attack · Lunge (position check)", func() -> void: _force_attack(2))
	_add_button(rows, "Freeze Enemy", _freeze_enemy)
	_add_button(rows, "Spawn Enemy", _spawn_enemy)

	# --- ENEMY STATE -------------------------------------------------------
	# The states the Sword x Magic matrix is built out of. Each one goes through
	# the enemy's real hit path, so what the panel shows is what the player gets.
	_add_section(rows, "ENEMY STATE")
	enemy_label = Label.new()
	enemy_label.custom_minimum_size = Vector2(280, 0)
	enemy_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rows.add_child(enemy_label)
	for entry in [["Normal", &"normal"], ["Burning", &"burning"], ["Frosted", &"frosted"], ["Frozen", &"frozen"]]:
		var label: StringName = entry[1]
		_add_button(rows, "State · " + String(entry[0]), func() -> void: dummy.call("apply_debug_state", label))
	_add_button(rows, "Shatter (FROZEN + Heavy)", _shatter)
	_add_button(rows, "Brittle Break (FROSTED + Heavy)", _brittle_break)

	# --- ENVIRONMENT -------------------------------------------------------
	# A wall to be thrown into and light bodies that actually move. Without these
	# Wind is a knockback number; with them it converts position into damage.
	_add_section(rows, "ENVIRONMENT")
	world_label = Label.new()
	world_label.custom_minimum_size = Vector2(280, 0)
	world_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rows.add_child(world_label)
	_add_button(rows, "Place for Wall Impact (Wind)", _place_for_wall_impact)
	_add_button(rows, "Reset Wind Objects", _reset_wind_objects)

	_add_section(rows, "RESOURCES")
	unlock_button = _add_button(rows, "Unlimited Resources: ON", _toggle_unlimited)
	_add_button(rows, "Heal", func() -> void: player.set("health", 100.0))
	_add_button(rows, "Restore Mana", func() -> void: player.set("mana", 100.0))
	_add_button(rows, "Restore Stamina", func() -> void: player.set("stamina", 100.0))

	_add_section(rows, "FEEDBACK")
	hitstop_button = _add_button(rows, "Hitstop: Normal", _cycle_hitstop)
	camera_preset_button = _add_button(rows, "Camera: Normal", _cycle_camera_preset)
	_add_button(rows, "Parry Timing Debug", parry_debug.toggle)
	_add_button(rows, "Reset Action", combat.finish_action)
	_add_button(rows, "Reset Ultimate FX", ultimate.finish_moment)
	_add_button(rows, "Slow Motion", _toggle_slow_motion)

	_build_iaido_section(rows)


func _add_section(parent: VBoxContainer, caption: String) -> void:
	var label := Label.new()
	label.text = "— " + caption + " —"
	parent.add_child(label)


func _refresh_magic_label() -> void:
	if magic_label == null:
		return
	var school := combat.current_school()
	if school == null:
		magic_label.text = "no school selected"
		return
	var spell := combat.current_spell()
	magic_label.text = "%s · %s\nspell: %s (%.1f mana, cast %s)\nblade: %s" % [
		school.display_name, school.tagline,
		spell.display_name if spell != null else "-",
		spell.mana_cost if spell != null else 0.0,
		"quick" if (spell != null and spell.cast_mode == SpellDefinition.Cast.QUICK) else "full",
		"%s for %.1fs" % [combat.blade_element, combat.blade_infusion_left] if combat.is_infused() else "plain",
	]
	_refresh_school_buttons()


# Both button rows are refreshed from one place so the ▸ / ● markers can never
# disagree with the controller's actual selection.
func _refresh_school_buttons() -> void:
	var school := combat.current_school()
	for id in school_buttons:
		var button: Button = school_buttons[id]
		var active: bool = school != null and school.id == id
		button.text = ("▸ %s" % button.get_meta("label", String(id))) if active else ("   %s" % button.get_meta("label", String(id)))
	for i in spell_buttons.size():
		var button := spell_buttons[i]
		if school == null or i >= school.spells.size():
			button.visible = false
			continue
		button.visible = true
		var spell: SpellDefinition = school.spells[i]
		button.text = "%s %s" % [("●" if combat.spell_id == spell.id else "○"), spell.display_name]


func _refresh_enemy_label() -> void:
	if enemy_label == null:
		return
	var stages := PackedStringArray()
	for id in [ElementLibrary.FIRE, ElementLibrary.FROST, ElementLibrary.WIND]:
		var value := 0.0
		var stage := &""
		if dummy.has_method("element_stage"):
			stage = dummy.call("element_stage", id)
		if id == ElementLibrary.FIRE:
			value = float(dummy.get("burn"))
		elif id == ElementLibrary.FROST:
			value = float(dummy.get("frost"))
		stages.append("%s %s%s" % [
			id, ("%.0f" % value) if id != ElementLibrary.WIND else "-",
			(" " + stage) if stage != &"" else "",
		])
	var state_name: String = str(dummy.get("state"))
	enemy_label.text = "%s  ·  brittle=%s\n%s\nwall impact %.2f" % [
		state_name, str(dummy.call("is_brittle")), "  ·  ".join(stages), float(dummy.get("last_wall_impact")),
	]


func _build_iaido_section(rows: VBoxContainer) -> void:
	_add_section(rows, "SIGNATURE TIMELINE SCRUB")
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


func _process(_delta: float) -> void:
	if not panel.visible:
		return
	style_label.text = "%s\n%s\nPG window %.3fs  ·  riposte %.2fs\n%s" % [
		combat.moveset.display_name,
		combat.moveset.tagline,
		combat.moveset.guard.perfect_guard_window,
		combat.moveset.guard.riposte_window,
		combat.debug_state_line(),
	]
	_refresh_magic_label()
	_refresh_enemy_label()
	_refresh_world_label()
	var lines: Array[String] = []
	for i in combat.moveset.skills.size():
		var skill: SwordSkill = combat.moveset.skills[i]
		var left := combat.skill_cooldown_left(i)
		lines.append("%d %s %s" % [i + 1, skill.display_name, ("READY" if left <= 0.0 else "%.1fs" % left)])
		if i < skill_buttons.size():
			skill_buttons[i].text = "Skill %d · %s %s" % [i + 1, skill.display_name, ("READY" if left <= 0.0 else "%.1fs" % left)]
	var extra := ""
	if combat.moveset.skills.is_empty():
		extra = "此流派本版本没有风格技能"
	var signature_left := combat.signature_cooldown_left()
	var ultimate_left := combat.ultimate_cooldown_left()
	status_label.text = "%s\n%s\nSIGNATURE 聚合斩 %s   ULTIMATE 无明一刻 %s\nHP %.0f  MP %.0f  SP %.0f" % [
		"\n".join(lines),
		extra,
		("READY" if signature_left <= 0.0 else "%.1fs" % signature_left),
		("READY" if ultimate_left <= 0.0 else "%.1fs" % ultimate_left),
		float(player.get("health")), float(player.get("mana")), float(player.get("stamina")),
	]


func _add_button(parent: VBoxContainer, title: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = title
	button.pressed.connect(callback)
	parent.add_child(button)
	return button


func _cycle_camera_preset() -> void:
	camera_preset_button.text = "Camera: " + camera_feedback.cycle_preset()


func _cycle_hitstop() -> void:
	hitstop_button.text = "Hitstop: " + combat.cycle_hitstop_preset()


func _toggle_unlimited() -> void:
	player.unlimited_resources = not player.unlimited_resources
	unlock_button.text = "Unlimited Resources: " + ("ON" if player.unlimited_resources else "OFF")


func _reset_enemy() -> void:
	dummy.call("reset_dummy")


func _force_attack(variant: int) -> void:
	if dummy.has_method("force_attack"):
		dummy.call("force_attack", variant)


func _spawn_enemy() -> void:
	var scene: PackedScene = load("res://scenes/enemies/TechnicalDummy.tscn")
	var clone := scene.instantiate() as Node3D
	sandbox.add_child(clone)
	clone.global_position = dummy.global_position + Vector3(3, 0, 0)


func _freeze_enemy() -> void:
	dummy.call("freeze_for_debug")


# --- magic ---------------------------------------------------------------

func _select_school(school_id: StringName) -> void:
	combat.select_school(school_id)


func _select_spell(index: int) -> void:
	var school := combat.current_school()
	if school == null or index >= school.spells.size():
		return
	combat.spell_id = school.spells[index].id


func _wind_spread() -> void:
	# The mechanical half of Wind x Fire: widen whatever field is burning and
	# shove the light bodies, both through the same call the spell uses.
	var spread := combat.wind_spread()
	world_label.text = "Wind spread: %s" % ("yes" if spread else "nothing in front to move")
	_refresh_world_label()


func _shatter() -> void:
	dummy.call("apply_debug_state", &"frozen")
	await get_tree().process_frame
	var enemy_hitbox: CombatHitbox = dummy.get_node("AttackHitbox")
	enemy_hitbox.set_active(false)
	combat.finish_action()
	combat.set_state(CombatController.State.CHARGE)
	combat.release_heavy()


func _brittle_break() -> void:
	dummy.call("apply_debug_state", &"frosted")


# --- environment ---------------------------------------------------------

# Resolved on use, because the sandbox builds its environment in its own _ready.
func _wind() -> WindProps:
	if wind_props == null or not is_instance_valid(wind_props):
		wind_props = sandbox.get_node_or_null("WindProps") as WindProps
	return wind_props


func _place_for_wall_impact() -> void:
	player.global_position = WindProps.WALL_TEST_PLAYER
	dummy.global_position = WindProps.WALL_TEST_TARGET
	# Aim HORIZONTALLY at the target's centre: look_at from the eye to a target
	# below the eye tilts the whole body down, and the wind shot with it.
	player.look_at_from_position(
		player.global_position,
		dummy.global_position + Vector3(0.0, WindProps.WALL_TEST_PLAYER.y - WindProps.WALL_TEST_TARGET.y, 0.0),
		Vector3.UP
	)
	var props := _wind()
	if props != null:
		props.reset()
	_refresh_world_label()


func _reset_wind_objects() -> void:
	var props := _wind()
	if props != null:
		props.reset()
	_refresh_world_label()


func _refresh_world_label() -> void:
	if world_label == null:
		return
	var props := _wind()
	if props == null:
		world_label.text = "no wind environment in this scene"
		return
	var moved := 0
	for body in props.light_objects:
		if is_instance_valid(body) and body.linear_velocity.length() > 0.1:
			moved += 1
	world_label.text = "Wall at z=%.1f  ·  light objects moving: %d/%d  ·  last wall impact %.2f" % [
		WindProps.WALL_POSITION.z, moved, props.light_objects.size(), float(dummy.get("last_wall_impact")),
	]


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
