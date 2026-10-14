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
# THE BODY BEING TESTED, resolved on first use rather than at load.
#
# Two reasons, and both of them were load-time errors in the Training Ground:
#   * the body does not exist yet. Children are readied before the stage's own
#     `_ready()`, which is where the room builds its dummies - the same trap the
#     WindProps note below describes.
#   * it is not called TechnicalDummy in every room. CombatSandbox has exactly one and
#     it has that name; the Training Ground has a LINE of them, built by the playtest
#     range, and none of them carry it. The panel's buttons are about "the body being
#     tested", so it asks the scene for a body, not for a name, and every button works
#     in either room.
# A computed property rather than a plain var, so the eighteen call sites below did not
# each have to learn to ask.
var dummy: Node3D:
	get:
		if _dummy == null or not is_instance_valid(_dummy):
			_dummy = _find_dummy()
		return _dummy

var _dummy: Node3D


func _find_dummy() -> Node3D:
	var named := sandbox.get_node_or_null("TechnicalDummy")
	if named != null:
		return named
	for node in sandbox.find_children("*", "StaticBody3D", true, false):
		if node.has_method("reset_dummy"):
			return node
	return null
@onready var iaido: IaidoDirector = sandbox.get_node("IaidoDirector")
@onready var ultimate: MomentOfNoMoonDirector = sandbox.get_node("MomentOfNoMoonDirector")
@onready var parry_debug: ParryDebugOverlay = sandbox.get_node("ParryDebugOverlay")
@onready var weapon: WeaponSlot = player.get_node("WeaponSlot")
@onready var chain: ChainDirector = player.get_node("ChainDirector")
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
var lethality_button: Button
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
var chain_label: Label
var chain_weight_buttons: Array[Button] = []
var weapon_buttons: Dictionary = {}


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

	# --- WEAPON ------------------------------------------------------------
	# A WEAPON is not a style. The sword's styles live in one data layer and the
	# chain is a second language entirely, so the switch sits above STYLE: it
	# decides whose input this is before anything else is asked.
	_add_section(rows, "WEAPON")
	weapon_buttons[WeaponSlot.SWORD] = _add_button(rows, "Weapon · 剑 Sword", func() -> void: _equip(WeaponSlot.SWORD))
	weapon_buttons[WeaponSlot.PHANTOM_CHAIN] = _add_button(
		rows, "Weapon · 虚链 PHANTOM CHAIN", func() -> void: _equip(WeaponSlot.PHANTOM_CHAIN)
	)
	weapon_buttons[WeaponSlot.MIRROR] = _add_button(
		rows, "Weapon · 镜 MIRROR", func() -> void: _equip(WeaponSlot.MIRROR)
	)
	weapon_buttons[WeaponSlot.CHAIN] = _add_button(
		rows, "Weapon · 缚星链 STAR-BIND CHAIN", func() -> void: _equip(WeaponSlot.CHAIN)
	)

	# --- CHAIN -------------------------------------------------------------
	# 缚星链, phase 0-1. Every button here goes through the same `request` the
	# keyboard uses, so nothing on this panel can do something the player cannot.
	_add_section(rows, "CHAIN")
	chain_label = Label.new()
	chain_label.custom_minimum_size = Vector2(280, 0)
	chain_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rows.add_child(chain_label)
	_add_button(rows, "Chain · Light 横缚/返扫/下砸", func() -> void: chain.request(&"light"))
	_add_button(rows, "Chain · Heavy (hold = 蓄势回旋)", func() -> void: chain.request(&"heavy"))
	_add_button(rows, "Chain · Release 甩星 (Launch)", func() -> void: chain.release_heavy())
	_add_button(rows, "Chain · 缠锁 Hook", func() -> void: chain.request(&"chain_hook"))
	_add_button(rows, "Chain · 缚 Lock (while hooked)", func() -> void: chain.request(&"chain_lock"))
	_add_button(rows, "Chain · 拨链 Guard", func() -> void: chain.request(&"block"))
	_add_button(rows, "Chain × Wind (real cast: spin boost)", _chain_wind)
	_add_button(rows, "Chain · Retract", func() -> void: chain.request(&"retract"))
	_add_button(rows, "Chain · Reset", chain.reset)
	# One button per weight the LAB actually placed, built from the lab's own slot
	# list: a stage that added a fourth weight grows a fourth button by itself.
	# Created here rather than lazily because SLOTS is a constant on the class and
	# does not need the lab to exist yet.
	for slot in ChainLab.SLOTS:
		var weight: StringName = slot["weight"]
		var button := _add_button(rows, "Hook Target · %s" % String(weight), func() -> void: _aim_at_weight(weight))
		button.set_meta("weight", weight)
		chain_weight_buttons.append(button)

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
	# One button per spell in the whole library, not just the current school's few.
	# A Lab that cannot arm a spell the player can arm will happily film a demo the
	# player cannot reproduce — which is exactly what happened while this row was
	# hardcoded to three slots and the wheel could only ever offer primaries.
	for school_id in MagicLibrary.all().keys():
		var school: MagicSchool = MagicLibrary.get_school(school_id)
		for spell in school.spells:
			var owned_by: StringName = school.id
			var wanted: StringName = spell.id
			var button := _add_button(
				rows,
				"Spell · %s" % spell.display_name,
				func() -> void: _select_spell(wanted)
			)
			button.set_meta("label", "Spell · %s" % spell.display_name)
			button.set_meta("spell_id", wanted)
			button.set_meta("school_id", owned_by)
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
	_add_button(rows, "Go to Movement Lane (clear run)", _go_to_movement_lane)
	_add_button(rows, "Go to Chain Lab (20m, 3 weights)", _go_to_chain_lab)

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
	_refresh_weapon_buttons()
	_refresh_chain_label()


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
	for button in spell_buttons:
		var wanted: StringName = button.get_meta("spell_id", &"")
		var owner_id: StringName = button.get_meta("school_id", &"")
		# ● armed, ▸ belongs to the current school, ○ somewhere else in the library.
		var marker := "○"
		if combat.spell_id == wanted:
			marker = "●"
		elif school != null and school.id == owner_id:
			marker = "▸"
		button.text = "%s %s" % [marker, button.get_meta("label", String(wanted))]


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
	# §T · DEBUG ONLY. Both halves of the execution contract have to be reachable
	# in a few seconds from the panel, because "does a non-lethal signature read as
	# a failed execution or as a broken one" is a question about a cut that DIDN'T
	# kill, and nothing in the game produces one on demand.
	lethality_button = _add_button(rows, "Iaido Lethality: AUTO", _cycle_lethality)
	# NOT an inline lambda, deliberately. A multi-line lambda passed as an argument
	# in the middle of a call takes Godot 4.4.1's analyser down with an access
	# violation — the whole file fails to parse and every scene that instances this
	# panel dies with it, which is a very expensive way to save one line.
	_add_button(rows, "Execution Slow Review (0.50x)", _execution_slow_review)
	_add_button(rows, "Go to Execution Lab", _go_to_execution_lab)
	_add_button(rows, "Reset Iaido FX", iaido.finish_iaido)


const LETHALITY_LABELS: Array[String] = ["AUTO", "FORCE LETHAL", "FORCE NON-LETHAL"]


func _cycle_lethality() -> void:
	iaido.set_debug_lethality((iaido.debug_lethality + 1) % LETHALITY_LABELS.size())
	lethality_button.text = "Iaido Lethality: " + LETHALITY_LABELS[iaido.debug_lethality]


## §T · EXECUTION SLOW REVIEW. The release is 0.45s of fall inside a 0.75s window
## and it is the beat the whole feature exists for, so it needs to be watchable at
## a speed a human can follow. Debug only — this is the review tool, not a control.
func _execution_slow_review() -> void:
	iaido.set_debug_speed(0.5)
	iaido_speed_button.text = "Iaido Speed: 0.50x"


func _go_to_execution_lab() -> void:
	var lab := sandbox.get("execution_lab") as ExecutionLab
	if lab == null:
		return
	var start := lab.entry_position()
	player.global_position = start
	player.velocity = Vector3.ZERO
	player.look_at_from_position(start, start + Vector3(0.0, 0.0, -6.0), Vector3.UP)
	# The arena dummy is on the walking line; the lab owns its own three.
	dummy.global_position = Vector3(0.0, 0.6, 14.0)
	lab.reset()
	_refresh_world_label()


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
	_refresh_chain_label()
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


func _select_spell(spell_id: StringName) -> void:
	combat.select_spell(spell_id)


# Switching weapons is one call into the slot, and everything else reacts to it.
# The panel never tells the sword or the chain to stop — the slot is the single
# owner, and both systems read it.
func _equip(wanted: StringName) -> void:
	weapon.equip(wanted)
	combat.finish_action()
	_refresh_weapon_buttons()


func _refresh_weapon_buttons() -> void:
	if weapon_buttons.is_empty():
		return
	var labels := {
		WeaponSlot.SWORD: "Weapon · 剑 Sword",
		WeaponSlot.PHANTOM_CHAIN: "Weapon · 虚链 PHANTOM CHAIN",
		WeaponSlot.MIRROR: "Weapon · 镜 MIRROR",
		WeaponSlot.CHAIN: "Weapon · 缚星链 STAR-BIND CHAIN",
	}
	for id in weapon_buttons:
		var button: Button = weapon_buttons[id]
		button.text = "%s %s" % ["●" if weapon.kind == id else "○", labels.get(id, String(id))]


# MAGIC x CHAIN, through the REAL path: arm wind, cast it, and let the spell's own
# resolution hand the momentum to the chain. A Lab that called the boost directly
# could show a working interaction that is unreachable in play.
func _chain_wind() -> void:
	combat.select_school(&"wind")
	combat.request(&"cast")
	_refresh_magic_label()


# §38: the chain's internals, in debug mode only. The three variables the whole
# weapon runs on, plus what it is attached to and how heavy that thing is.
func _refresh_chain_label() -> void:
	if chain_label == null:
		return
	if not weapon.is_chain():
		chain_label.text = "当前：剑。切到缚星链后这里显示 State / Radius / Momentum / Tension / Hook / Weight。"
		return
	var target := "—"
	if chain.is_hooked():
		var hooked: Node3D = chain.get("_hook_actor")
		if hooked != null:
			target = "%s (%s)" % [hooked.name, String(chain.weight_of(hooked))]
	chain_label.text = "%s\n%s\n钩着：%s" % [
		chain.debug_state_line(),
		chain.debug_flags_line(),
		target,
	]
	_refresh_weight_buttons()


# The three weights, so a take can aim at one of them on purpose. The distance is
# shown because the distance IS the experiment: a hook has a length, and standing
# inside it or outside it is the difference between a hit and a whiff.
func _refresh_weight_buttons() -> void:
	var lab := sandbox.get_node_or_null("ChainLab") as ChainLab
	if lab == null or chain_weight_buttons.is_empty():
		return
	for button in chain_weight_buttons:
		var weight: StringName = button.get_meta("weight")
		var target := lab.target_for(weight)
		var distance := "—"
		if target != null:
			distance = "%.1fm" % player.global_position.distance_to(target.global_position)
		button.text = "Hook Target · %s (%s)" % [String(weight), distance]


func _aim_at_weight(weight: StringName) -> void:
	# Standing one chain-length and a bit from the target, looking at it: the
	# distance is the whole experiment, so the panel has to place the player rather
	# than leave them to walk it.
	var lab := sandbox.get_node_or_null("ChainLab") as ChainLab
	if lab == null:
		return
	var target := lab.target_for(weight)
	if target == null:
		return
	var toward := target.global_position
	var stand := toward + Vector3(0.0, 0.0, 3.4)
	stand.y = ChainLab.ENTRY.y
	player.global_position = stand
	player.velocity = Vector3.ZERO
	player.look_at_from_position(stand, toward + Vector3(0.0, 1.0, 0.0), Vector3.UP)
	chain.reset()
	_refresh_chain_label()


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


# Movement has its own stage because it cannot share the arena: the dummy stands
# on the line the player walks, so a straight run ends in a shove two metres in.
# Pressing this parks the enemy off the lane and stands the player on the start
# line, already facing down the run.
func _go_to_movement_lane() -> void:
	var lane := sandbox.get_node_or_null("MovementLane") as MovementLane
	if lane == null:
		return
	var start := lane.start_position()
	player.global_position = start
	player.velocity = Vector3.ZERO
	player.look_at_from_position(start, start + MovementLane.RUN_DIRECTION * 4.0, Vector3.UP)
	dummy.global_position = Vector3(0.0, 0.6, -9.0)
	_refresh_world_label()


# The chain needs a room, not a corner of one. Same reasoning as the movement
# lane, but the requirement is larger: 4.6m of chain plus a throw that is meant
# to MISS means the nearest thing worth hitting has to be a wall, and the three
# weight classes have to be far enough apart that one sweep cannot touch two of
# them by accident. Also stands the arena dummy out of the way, because the
# arena dummy is on the walking line and the chain lab owns its own three.
func _go_to_chain_lab() -> void:
	var lab := sandbox.get("chain_lab") as ChainLab
	if lab == null:
		return
	var start := lab.entry_position()
	player.global_position = start
	player.velocity = Vector3.ZERO
	player.look_at_from_position(start, start + Vector3(0.0, 0.0, -6.0), Vector3.UP)
	dummy.global_position = Vector3(0.0, 0.6, 14.0)
	lab.reset()
	chain.reset()
	_refresh_world_label()
	_refresh_chain_label()


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
	world_label.text = "Wall at z=%.1f  ·  light objects moving: %d/%d  ·  last wall impact %.2f\n移动平台 x=%.1f..%.1f  台面 y=%.2f  长 %.0fm" % [
		WindProps.WALL_POSITION.z,
		moved,
		props.light_objects.size(),
		float(dummy.get("last_wall_impact")),
		MovementLane.CENTER.x - MovementLane.LENGTH * 0.5,
		MovementLane.CENTER.x + MovementLane.LENGTH * 0.5,
		MovementLane.DECK_Y,
		MovementLane.LENGTH,
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
