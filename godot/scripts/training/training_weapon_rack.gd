@tool
extends Node3D
# A physical weapon rack. Walk up to it, press E, and the thing in your hands
# changes.
#
# WHY A RACK AND NOT A MENU (brief §4)
# A menu that says "weapon: sword" proves nothing about the sword. A rack shows
# the actual mesh, at actual scale, in the actual lighting, and the player has to
# walk to it - which is the same motion they will make in the game. So the rack is
# the primary switcher and the developer panel stays as the fast path.
#
# WHAT IT DELIBERATELY DOES NOT DO
# It does not own the weapon decision. `WeaponSlot` owns it - one node, on the
# Player, written by exactly one thing at a time. This rack is a *caller*: it asks
# the slot to change and then reports whether it worked. If the slot is not
# mounted yet, the rack says so out loud instead of silently pretending, because
# an equip that quietly does nothing is the most expensive kind of bug to find.
#
# So this script also works before MAIN has wired anything: it prints a precise,
# actionable warning naming the node it could not find.
#
# Displayed meshes are shown at TRUE SCALE. A rack that scales its exhibits is a
# rack that lies about them, and scale is one of the four things the review hub
# exists to check.

const TB := preload("res://scripts/training/training_build.gd")

## Which weapon pressing E puts in the player's hands.
@export var weapon_id: StringName = &"sword"
## What the rack calls this weapon on its label.
@export var display_text: String = "剑 · SWORD"
## Shown on the rack when the finishing asset does not exist yet.
@export var asset_note: String = ""
## Reach at which the prompt appears.
@export var reach: float = 3.2

var _player: Node3D = null
var _slot: Node = null
var _prompt: Label3D = null
var _in_reach := false
var _warned := false
var _cooldown := 0.0

const RACK_H := 1.55
const BAR_LEN := 2.2

# HOW A SWORD-CLASS ASSET LIES ON THE BOARD.
#
# The GLBs are authored origin-at-the-tsuba, +Y toward the tip, -X on the cutting
# edge, +/-Z the flat (see scripts/weapons/sword_classes.gd). The rack lays them
# along world X with the edge UP, so a blade reads as a blade and not as a bar.
# Godot's `Basis(x, y, z)` takes the three AXES, so this maps:
#     local +Y (to the tip) -> world +X
#     local -X (the edge)   -> world +Y (up)
#     local +Z (the flat)   -> world +Z
#
# This line has been wrong once in each axis convention -- for the old -Z build it
# had to rotate about Z, which cannot move an axis that already lies along Z. The
# rule now is: whatever the GLB's own AABB says, three axes map onto (length -> X),
# (edge -> Y), (flat -> Z), and the same basis is used for the scabbard so the two
# are shown in ONE frame and the pairing can be judged.
const EXHIBIT_BASIS := Basis(
	Vector3(0.0, -1.0, 0.0), Vector3(1.0, 0.0, 0.0), Vector3(0.0, 0.0, 1.0)
)


func _ready() -> void:
	_geometry()
	if Engine.is_editor_hint():
		return
	_bind_interact()
	set_process(true)


func _geometry() -> void:
	var timber := TB.material(TB.TIMBER)
	var accent := TB.material(TB.ACCENT, 0.8, 0.35)

	# Two uprights and a cross bar - the simplest object that reads as a rack from
	# across a courtyard.
	TB.post(self, "Upright_L", Vector3(-BAR_LEN * 0.5, 0.0, 0.0), RACK_H, 0.075, timber, true)
	TB.post(self, "Upright_R", Vector3(BAR_LEN * 0.5, 0.0, 0.0), RACK_H, 0.075, timber, true)
	TB.slab(self, "CrossBar", Vector3(0.0, RACK_H, 0.0), Vector3(BAR_LEN + 0.3, 0.10, 0.10), accent)

	# A backboard behind, so a pale weapon is legible against it -- which means
	# it has to be DARK.  It was STONE_COURT (0.44), and against a pale steel
	# blade at 0.735 the sword simply vanished: the six captures came back with
	# a grey slab and no sword in it, and the only reason that was diagnosable
	# at all is that the probe prints live world AABBs.  Dark oiled timber is
	# what a real weapon board is made of anyway, and it sits inside the rack's
	# own vocabulary instead of introducing a second material family.
	var board_mat := TB.material(Color(0.108, 0.098, 0.092), 0.74)
	TB.slab(self, "Board", Vector3(0.0, RACK_H * 0.62, 0.10), Vector3(BAR_LEN + 0.1, 0.95, 0.06), board_mat)

	# --- the exhibit -----------------------------------------------------------
	# The sword exists, so the rack shows the real mesh. The chain does not, so it
	# shows a silhouette and says so. Both are more useful than a generic prop:
	# one is the asset, the other is an honest statement about the schedule.
	# THE EXHIBIT HAS TO BE IN FRONT OF THE BACKBOARD, NOT BEHIND IT.
	# The rack's front faces +z (the board sits at local z = +0.10), so a negative
	# local z puts the weapon on the FAR side of the board -- which is where this
	# line had it, first at -0.02 and then at -0.12 once the bar clearance was
	# fixed.  Both are behind.  With the camera above the board's top edge the
	# board then occluded all but a ~10 px sliver of a 1.05 m sword, and three
	# capture sessions came back looking empty.  Move it to POSITIVE z, floating
	# just clear of the board's front face (z = +0.13), and lower it so the blade
	# hangs on the board under the bar instead of crossing it.
	var exhibit := Node3D.new()
	exhibit.name = "Exhibit"
	exhibit.position = Vector3(0.0, RACK_H - 0.16, 0.17)
	add_child(exhibit)

	match weapon_id:
		&"sword":
			_mount_sword_exhibit(exhibit)
			_mount_scabbard_exhibit()
		_:
			# No mesh yet: a stand with a label, not an invented object.
			TB.slab(exhibit, "EmptyStand", Vector3.ZERO, Vector3(0.9, 0.07, 0.16), accent, false)
		_:
			# No mesh yet: a stand with a label, not an invented object.
			TB.slab(exhibit, "EmptyStand", Vector3.ZERO, Vector3(0.9, 0.07, 0.16), accent, false)

	TB.label(self, "RackLabel", display_text, Vector3(0.0, RACK_H + 0.42, 0.0), 0.30)

	if asset_note != "":
		TB.label(self, "RackNote", asset_note, Vector3(0.0, RACK_H + 0.16, 0.0), 0.24, TB.ACCENT)

	# Prompt: hidden until the player is close enough that the key would work.
	_prompt = TB.label(self, "RackPrompt", "[E]  装备  " + display_text,
		Vector3(0.0, 1.05, 0.35), 0.26, Color(1.0, 0.98, 0.86))
	_prompt.visible = false


# ------------------------------------------------------------------------------

# ------------------------------------------------------------------ the sword
#
# THE RACK SHOWS THE SHIPPING RIG, NOT A COPY OF IT.
#
# This used to instantiate `fp_sword.glb` directly and apply a basis by hand --
# a second, divergent description of how the sword sits in the world, written by
# a file that is not the sword's own. It now instantiates
# `scenes/weapons/Sword_FP.tscn`, which is the same object the game hands the
# player, so a rack review and a first-person review are reviews of ONE thing.
# The two GLBs are unchanged either way; what the scene adds is the anchors and
# the blade's judgement volume, and what it guarantees is the frame.
#
# `SwordFPRig` is safe here by construction: its player-only step
# (`install_real_scabbard`) is gated on its parent being named `TempSwordVisual`,
# so off the player it is a no-op rather than a warning about a node that was
# never supposed to exist.
func _mount_sword_exhibit(exhibit: Node3D) -> void:
	var node := _exhibit_instance("res://scenes/weapons/Sword_FP.tscn",
		"res://models/weapons/fp_sword.glb")
	if node == null:
		TB.slab(exhibit, "SwordPlaceholder", Vector3.ZERO, Vector3(1.05, 0.09, 0.03),
			TB.material(TB.STONE_STRUCT), false)
		return
	node.name = "SwordFP"
	node.basis = EXHIBIT_BASIS
	exhibit.add_child(node)


# ------------------------------------------------------------------ the scabbard
#
# THE SAYA IS A SECOND EXHIBIT, IN THE SAME FRAME, DIRECTLY UNDER THE SWORD.
#
# Two reasons it is here rather than left to the Iaido ceremony. First, a
# scabbard is only reviewable against its own blade: this is the one place the
# two can be seen at true scale, one above the other, sharing an origin. Second,
# the mouth is where the whole fit lives and it is 43.5 x 13.7 mm -- measurable
# on a rack, and not measurable from a ceremony that is two and a half seconds
# long and moving.
#
# ITS ORIGIN IS THE MOUTH, so it is mounted at the SAME local X as the sword's
# tsuba: the blade's root is visually at the opening it has to pass. A scabbard
# rendered anywhere else on this board would be a picture of a scabbard rather
# than evidence about a fit.
func _mount_scabbard_exhibit() -> void:
	var node := _exhibit_instance("res://models/weapons/fp_saya.glb", "")
	if node == null:
		return
	var saya_bay := Node3D.new()
	saya_bay.name = "SayaExhibit"
	saya_bay.position = Vector3(0.0, RACK_H - 0.16 - 0.30, 0.17)
	add_child(saya_bay)
	node.name = "SayaFP"
	node.basis = EXHIBIT_BASIS
	saya_bay.add_child(node)
	# Under the BOARD, not on it. At -0.17 the label sat straight across the saya's
	# own body and covered the one thing it is there to name; the board's lower
	# edge is at saya-local y = -0.185, so a label below that reads as a caption
	# rather than as a sticker on the exhibit.
	TB.label(saya_bay, "SayaLabel", "剑鞘 · SAYA", Vector3(0.0, -0.32, 0.0), 0.18, TB.ACCENT)


func _exhibit_instance(primary: String, fallback: String) -> Node3D:
	for path in [primary, fallback]:
		if path == "" or not ResourceLoader.exists(path):
			continue
		var packed := load(path) as PackedScene
		if packed != null:
			return packed.instantiate() as Node3D
	return null


func _bind_interact() -> void:
	# Same convention the Player uses in `_ready()`: create the action if the
	# project does not define one. ART must not add an [input] section to
	# project.godot while COMBAT owns that file.
	if not InputMap.has_action(&"interact"):
		InputMap.add_action(&"interact")
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_E
		InputMap.action_add_event(&"interact", ev)


func _resolve() -> void:
	if _player != null and is_instance_valid(_player):
		return
	var tree := get_tree()
	if tree == null:
		return
	_player = tree.get_first_node_in_group(&"player") as Node3D
	if _player == null:
		var scene := tree.current_scene
		if scene != null:
			_player = scene.find_child("Player", true, false) as Node3D
	if _player == null:
		return
	_slot = _player.find_child("WeaponSlot", true, false)


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_cooldown = maxf(0.0, _cooldown - delta)
	_resolve()
	if _player == null:
		if _prompt != null:
			_prompt.visible = false
		return

	var near := _player.global_position.distance_to(global_position) <= reach
	if near != _in_reach:
		_in_reach = near
		if _prompt != null:
			# Only offer the key when the key will do something. A prompt that
			# appears over an unmounted slot teaches the reviewer to distrust it.
			_prompt.visible = near and _slot != null


func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint() or _player == null or _cooldown > 0.0:
		return
	if not event.is_action_pressed(&"interact"):
		return
	if _player.global_position.distance_to(global_position) > reach:
		return
	get_viewport().set_input_as_handled()
	_equip()


func _equip() -> void:
	if _slot == null:
		if not _warned:
			_warned = true
			# Loud, specific, and once - not a silent no-op (project hard rule).
			push_warning(
				"TrainingGround rack '%s': found the Player but no 'WeaponSlot' child, "
				% name
				+ "so equip('%s') was not attempted. MAIN/COMBAT needs to add the "
				% String(weapon_id)
				+ "WeaponSlot node to Player.tscn. See docs/ART_INTEGRATION_REQUESTS.md."
			)
		return

	if not _slot.has_method("equip"):
		push_warning("TrainingGround rack '%s': WeaponSlot has no equip() method." % name)
		return

	var ok: bool = _slot.call("equip", weapon_id)
	if ok:
		_cooldown = 0.35
		print("[TrainingGround] equipping %s from rack '%s'" % [String(weapon_id), name])


## What the rack currently believes is in the player's hands. Used by the HUD.
func current_weapon() -> StringName:
	if _slot != null and _slot.has_method("kind"):
		return _slot.get("kind")
	return &""
