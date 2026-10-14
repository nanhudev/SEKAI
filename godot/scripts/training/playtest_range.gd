extends Node3D
# THE PLAYTEST RANGE. Sword and chain, at the three distances a 10m rope needs.
#
# WHY IT EXISTS
# Chain V3's open questions are all SPATIAL - is the weapon obviously long, is the
# idle bundle countable, does A1 sweep wide enough, does A3 read in first person as a
# straight line - and none of them can be asked of a target standing two metres away,
# which is the only distance the arena ever offered. So this is a straight line with
# the three masses the brief names.
#
# 3 / 6 / 9 m, and the numbers are drawn from the weapon rather than picked (§10). The
# shortest sits inside A1's own arc (radius_to 4.30) so a lateral cut has something to
# land on; the longest sits at the edge of A3's throw (9.6 m) so the straight throw has
# a target that is genuinely far. The whole redesign started from "the chain must be
# long", and a range that only offers 3 m cannot tell a long chain from a short one.
#
# THE ZONE ANSWERS §9's LIST, and mostly by not building anything: the Chain Lab
# already IS the open bay (A) — a 32 x 30 m deck with a clear centre — and it already
# carries the pillar and the anchor post (F) and a wall (E). What was missing was the
# three weights at range (B/C/D), so that is all this adds. The movement lane (G) is
# COMBAT's own stage and is not touched.
#
# THE RANGE NOW STANDS ON THE LAB'S OWN DECK, at the lab's own door, which is the
# merge ART's compound asked for: one bay, one floor, one wall at the end of it. It is
# why `stand` is a host-supplied variable rather than a constant — see `STAND`.
#
# WHY THE DUMMIES DO NOT DIE (§14)
# A playtest is a sequence of combos, and a target that dies in two hits turns that
# sequence into a sequence of dummies. These carry a health figure no session will
# exhaust, and they keep the REAL hit reaction and the REAL attack - which is the half
# that matters, and the half a "training dummy" mode usually throws away. The nearest
# one being inside its own 3.4 m attack range is deliberate: it is the only body in
# this room that can be used to test Guard and Perfect Guard.
#
# DETERMINISM (the rule the rest of the room already follows)
# Every position is a literal and R puts all of it back. No RNG.

const TB := preload("res://scripts/training/training_build.gd")
const DUMMY_SCENE := "res://scenes/enemies/TechnicalDummy.tscn"

## §15 asks for a RESET. It suggests R; R is the frost quick-cast (frost_cast, bound in
## combat_controller), so the free key in the developer row is used instead rather than
## breaking a working cast to gain a convenience.
const RESET_KEY := KEY_F9

## Where the player stands when nothing has told this node otherwise: the Chain Lab's
## own door in the arena's coordinate frame (see `ChainLab.ENTRY`).
##
## THE RANGE STANDS AT THE LAB'S DOOR, so the number belongs to the lab and not to this
## file. A host with the lab somewhere else sets `stand` before `add_child()` and the
## range follows it, which is the only arrangement in which "the three masses are in
## front of you when you walk in" survives somebody moving the lab.
const STAND := Vector3(0.0, 0.0, -22.0)
## The player origin and the target origins both sit a hand's width above the floor,
## which is the convention every other station in this project already uses (see
## `training_ground._dummy_station`). Kept as two names because they are two things:
## one is where a person stands, the other is where a 2.1 m construct's feet are.
const STAND_Y := 0.10
const RANGES := [3.0, 6.0, 9.0]
const WEIGHTS := [&"light", &"medium", &"heavy"]
const RANGE_LABELS := ["3m  轻 LIGHT", "6m  中 MEDIUM", "9m  重 HEAVY"]
const TRAINING_HEALTH := 999999.0
const BACKSTOP_Z := -12.0
## Marks that lie ON the deck are stacked above the chain lab's own distance markings
## (which are at 0.02), because the bay's floor is a shared surface now and two paint
## layers at one height is z-fighting across a twenty-metre bay.
const DECK_TOP := 0.026
const DUMMY_Y := 0.10

## The line's own origin, in this node's space. See `STAND`.
var stand := STAND
## A host that already ends the bay with a wall does not want a second one standing in
## the middle of it. ART's compound is exactly that host: this range is laid down the
## chain lab's deck, the lab's wall is 20 m away at the far end, and a 3 m plate at 12 m
## would both break the bay's clean centre (which the ART brief calls the lab's real
## deliverable) and put a fence in front of the thing the chain's §20 is about biting.
## It is left on by default so a range dropped somewhere with no wall still has one.
var build_backstop := true

var _player: CharacterBody3D
var _combat: Node
var _chain: Node
var _weapon_manager: Node
var _dummies: Array[Node3D] = []
var _homes: Array[Vector3] = []


func _ready() -> void:
	_build()
	_bind_reset()
	call_deferred("_resolve")


func _resolve() -> void:
	if _player != null and is_instance_valid(_player):
		return
	var tree := get_tree()
	if tree == null:
		return
	_player = tree.get_first_node_in_group(&"player") as CharacterBody3D
	if _player == null:
		var scene := tree.current_scene
		if scene != null:
			_player = scene.find_child("Player", true, false) as CharacterBody3D
	if _player == null:
		# Loud and specific rather than a silent inert range: a RESET that does nothing
		# is the most expensive kind of bug to find.
		push_warning("PlaytestRange: no Player found, so RESET (%s) will not be wired."
			% OS.get_keycode_string(RESET_KEY))
		return
	# §14: unlimited mana and stamina is a rule of this room, not a debug toggle that
	# someone has to remember to press. Set here rather than in the .tscn so it holds
	# for every entry point into the training ground.
	_player.unlimited_resources = true
	_combat = _player.get_node_or_null("CombatController")
	_chain = _player.get_node_or_null("ChainDirector")
	_weapon_manager = _player.get_node_or_null("WeaponManager")


# ---------------------------------------------------------------- geometry (§9/§10)

func _build() -> void:
	var deck := TB.material(TB.STONE_DARK)
	var plate := TB.material(TB.STONE_COURT)
	var accent := TB.material(TB.ACCENT, 0.8, 0.35)

	var mid_z := (stand.z + BACKSTOP_Z) * 0.5
	TB.flat_mark(self, "RangeDeck", Vector3(stand.x, DECK_TOP, mid_z),
		Vector2(8.0, stand.z - BACKSTOP_Z), deck)

	# The backstop. §9 E wants a wall and the throw needs something to arrive at that
	# is not a dummy: at 9.6 m the head reaches z = -6.6, so this stands 5.4 m further
	# out and catches everything the range can throw.
	if build_backstop:
		TB.slab(self, "RangeBackstop", Vector3(stand.x, DECK_TOP + 1.5, BACKSTOP_Z),
			Vector3(12.0, 3.0, 0.6), plate)

	# Where to stand, and the two keys. The only instructions in the room, and they are
	# on the floor where the player is already looking.
	TB.flat_mark(self, "StandPad", Vector3(stand.x, DECK_TOP, stand.z), Vector2(3.0, 3.0), plate)
	TB.label(self, "StandLabel", "1  剑 SWORD     2  虚链 PHANTOM",
		Vector3(stand.x, 1.9, stand.z + 0.9), 0.36, TB.ACCENT)

	# Three masses, in ascending order of how much they should resist, each with the
	# distance written on it - the distance IS the experiment (§10).
	var packed: PackedScene = null
	if ResourceLoader.exists(DUMMY_SCENE):
		packed = load(DUMMY_SCENE)
	else:
		push_warning("PlaytestRange: %s is missing, so the range has no targets." % DUMMY_SCENE)

	for i in RANGES.size():
		var z: float = stand.z - float(RANGES[i])
		TB.flat_mark(self, "RangePad_%d" % i, Vector3(stand.x, DECK_TOP, z), Vector2(2.6, 2.6), accent)
		TB.label(self, "RangeTag_%d" % i, RANGE_LABELS[i],
			Vector3(stand.x + 2.4, 1.35, z), 0.30, TB.ACCENT)
		if packed == null:
			continue
		var dummy: Node3D = packed.instantiate()
		dummy.name = "RangeDummy_%d" % i
		# Before add_child, because the dummy's _ready() copies max_health into health.
		dummy.set("max_health", TRAINING_HEALTH)
		dummy.set("weight", WEIGHTS[i])
		dummy.position = Vector3(stand.x, DUMMY_Y, z)
		add_child(dummy)
		_dummies.append(dummy)
		_homes.append(dummy.position)


# ---------------------------------------------------------------- RESET (§15)

func _bind_reset() -> void:
	# Same convention as every other binding in the project: create the action if the
	# project has no [input] section to add it to, which it has not.
	if not InputMap.has_action(&"training_reset"):
		InputMap.add_action(&"training_reset")
	var event := InputEventKey.new()
	event.keycode = RESET_KEY
	event.physical_keycode = RESET_KEY
	InputMap.action_add_event(&"training_reset", event)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"training_reset"):
		reset_training()
		get_viewport().set_input_as_handled()


## Puts the room back to a known state without reloading it. §15's list, in the order
## that leaves nothing half-undone: the weapon goes away first, because a hitbox or a
## chain that is still in the air would otherwise outlive the reset that was supposed
## to clear it.
func reset_training() -> void:
	_release_weapons()
	_restore_dummies()
	_restore_fixtures()
	_restore_player()
	_clear_effects()


## Fixtures that own their own recovery are ASKED rather than listed.
##
## The three weights below are this file's own children, so it can hold their home
## positions. A 居合桩 is not: it is a room fixture that happens to be re-cuttable,
## and the two things it needs reset — a severed half still lying on the floor and a
## recovery timer halfway through — are its own business. A duck-typed method plus a
## group means the fourth fixture added to this room is a new file and a new
## `add_to_group`, and nothing in the reset path has to know it exists.
func _restore_fixtures() -> void:
	var tree := get_tree()
	if tree == null:
		return
	for node in tree.get_nodes_in_group("training_fixture"):
		if node.has_method("reset_fixture"):
			node.call("reset_fixture")


func _release_weapons() -> void:
	if _weapon_manager != null and _weapon_manager.has_method("reset_weapons"):
		_weapon_manager.call("reset_weapons")
	elif _combat != null and _combat.has_method("stow"):
		# No manager (a stage that predates it): the sword's half is still available.
		_combat.call("stow")
	# The chain is reset by its own subscription to the slot, which a RESET does not
	# fire (no weapon changes hands), so it is asked directly. Without this, R during a
	# throw leaves the head flying with nothing holding it.
	if _chain != null and _chain.has_method("reset"):
		_chain.call("reset")


func _restore_dummies() -> void:
	for i in _dummies.size():
		var dummy := _dummies[i]
		if dummy == null or not is_instance_valid(dummy):
			continue
		dummy.global_position = _homes[i]
		if dummy.has_method("reset_dummy"):
			# The dummy's own reset, not a copy of it: health, poise, elements, the
			# attack latch and the scar a debug cut left behind all have one owner and
			# it is the dummy.
			dummy.call("reset_dummy")


func _restore_player() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	_player.velocity = Vector3.ZERO
	_player.global_position = Vector3(stand.x, STAND_Y, stand.z)


func _clear_effects() -> void:
	var tree := get_tree()
	if tree == null:
		return
	var scene := tree.current_scene
	if scene == null:
		return
	_finish(scene, "IaidoDirector", "active")
	_reset(scene, "CombatScreenFX")
	_reset(scene, "TimeEffectManager")


func _finish(scene: Node, node_name: String, flag: String) -> void:
	var node := scene.find_child(node_name, true, false)
	if node == null:
		return
	if bool(node.get(flag)):
		node.call("finish_iaido")


func _reset(scene: Node, node_name: String) -> void:
	var node := scene.find_child(node_name, true, false)
	if node != null and node.has_method("reset"):
		node.call("reset")


## How many targets the range actually built. A playtest that reports "the dummy did
## not react" is worth nothing if the dummy was never there.
func target_count() -> int:
	return _dummies.size()
