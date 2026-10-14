extends CanvasLayer
# The Training Ground's whole interface. Four lines of state and two lighting
# modes, and that is deliberately all.
#
# WHY SO LITTLE (brief §25)
# This room exists to make art legible. Every pixel of interface that is not
# telling you what you are holding, in which style, is a pixel covering the thing
# you came to look at. So there is no menu, no inventory, no settings page. Weapon
# selection is a physical rack; this panel only reports the consequence.
#
# The two lighting modes are the one piece of real function here (brief §24):
#
#   DAY      the actual game light. Use this to answer "does it look right".
#   NEUTRAL  flat, even, no fog. Use this to answer "is the material right",
#            because a directionally-lit material review is a review of the light.
#
# Everything is read defensively: the panel reports what it can find and prints a
# dash for what it cannot, so it never becomes the reason a scene fails to run.

const KEY_DAY := KEY_F1
const KEY_NEUTRAL := KEY_F2

var _label: Label
var _light_label: Label
var _world_env: WorldEnvironment
var _sun: DirectionalLight3D
var _mode := "day"
var _player: Node = null
var _combat: Node = null
var _elements: Node = null
var _slot: Node = null
var _style_name := &""


func _ready() -> void:
	_build_ui()
	_find_scene_nodes()
	_apply_light("day")


# ------------------------------------------------------------------------------

func _build_ui() -> void:
	layer = 3
	var root := MarginContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	root.position = Vector2(14, 10)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(box)

	_label = Label.new()
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_font_size_override("font_size", 15)
	_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.75))
	_label.add_theme_constant_override("shadow_offset_x", 1)
	_label.add_theme_constant_override("shadow_offset_y", 1)
	box.add_child(_label)

	_light_label = Label.new()
	_light_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_light_label.add_theme_font_size_override("font_size", 13)
	_light_label.modulate = Color(0.86, 0.88, 0.92)
	_light_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.75))
	_light_label.add_theme_constant_override("shadow_offset_x", 1)
	_light_label.add_theme_constant_override("shadow_offset_y", 1)
	box.add_child(_light_label)


func _find_scene_nodes() -> void:
	var tree := get_tree()
	if tree == null:
		return
	var scene := tree.current_scene
	if scene == null:
		return
	_world_env = scene.find_child("WorldEnvironment", true, false) as WorldEnvironment
	_sun = scene.find_child("Sun", true, false) as DirectionalLight3D


func _resolve_player() -> void:
	if _player != null and is_instance_valid(_player):
		return
	var tree := get_tree()
	if tree == null:
		return
	_player = tree.get_first_node_in_group(&"player")
	if _player == null:
		var scene := tree.current_scene
		if scene != null:
			_player = scene.find_child("Player", true, false)
	if _player == null:
		return
	_slot = _player.find_child("WeaponSlot", true, false)
	_combat = _player.find_child("CombatController", true, false)
	var scene := tree.current_scene
	if scene != null:
		_elements = scene.find_child("ElementState", true, false)


# ------------------------------------------------------------------------------

func _process(_delta: float) -> void:
	_resolve_player()

	var weapon := "—"
	if _slot != null and _slot.has_method("display_name"):
		weapon = String(_slot.call("display_name"))
	elif _slot != null:
		weapon = String(_slot.get("kind"))

	var style := "—"
	if _combat != null:
		var s: Variant = _combat.get("style_id")
		if s != null:
			style = String(s)

	var spell := "—"
	if _elements != null and _elements.has_method("active_ids"):
		var ids: Array = _elements.call("active_ids")
		spell = ", ".join(PackedStringArray(ids.map(func(x): return String(x)))) if ids.size() > 0 else "none"

	_label.text = "SEKAI TRAINING GROUND\n武器  %s\n流派  %s\n元素  %s" % [weapon, style, spell]
	_light_label.text = "光照  %s   [F1] DAY  [F2] NEUTRAL\n[F] 交互 / 拿取      [F8] 开发面板" % _mode.to_upper()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var key := (event as InputEventKey).keycode
	if key == KEY_DAY:
		_apply_light("day")
	elif key == KEY_NEUTRAL:
		_apply_light("neutral")


# ------------------------------------------------------------------------------

## Switches between the game's real light and a flat material-review light.
func _apply_light(mode: String) -> void:
	_mode = mode
	if _world_env == null or _world_env.environment == null:
		return
	var env := _world_env.environment

	if mode == "neutral":
		# Flat and directionless on purpose: with one key light, every material
		# review is secretly a review of that key light's angle. Fog goes off too,
		# because fog at 20 m is a colour grade you did not ask for.
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color(0.74, 0.75, 0.78)
		env.ambient_light_energy = 1.35
		env.fog_enabled = false
		if _sun != null:
			_sun.light_energy = 0.65
			_sun.light_indirect_energy = 0.3
	else:
		env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
		env.ambient_light_energy = 1.0
		env.fog_enabled = false
		if _sun != null:
			_sun.light_energy = 2.0
			_sun.light_indirect_energy = 0.5
