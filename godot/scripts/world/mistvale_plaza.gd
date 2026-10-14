extends Node3D
class_name MistvalePlaza
# ============================================================================
# 雾栖镇 · 集市广场 — the first place SEKAI is a game rather than a test
# ============================================================================
#
# WHAT THIS FILE IS. It is the WIRING and the DRESSING for the first playable
# sequence, and it is deliberately not the story (that is `StoryDirector`), not
# the HUD (that is `StoryUI`), and not any of the actors. It has three jobs:
#
#   1. BUILD THE SQUARE. The environment stack (terrain, town, landmarks) comes
#      from the ART line's existing builders. What this file adds is the only
#      thing a 660 m region does not have: a CENTRE. A paved apron, the stele on
#      it, the market edge, the alley the hound comes out of, and the two roads
#      out of the square.
#   2. OWN THE INPUT PROFILE. This world has a sword and nothing else, so it
#      releases the keymap that belongs to the combat lab and binds Q to the one
#      skill. See `_apply_input_profile` - it is the most load-bearing 40 lines
#      in the file.
#   3. BE THE INTERACTION HUB. One place decides what E does, by finding the
#      nearest thing that has something to say about it.
#
# WHY THE DRESSING IS BUILT IN CODE. Same reason as `ArenaDressing` and every
# `mistvale_*` layer: a .tscn of sixty hand-placed boxes is unreviewable in a diff
# and cannot be re-derived when the height field moves. Everything placed here
# asks `MistvaleHeights.height_at()` where the ground is, which is the project's
# standing rule - a hand-written elevation that disagrees with the field shows up
# later as an unwalkable wall.
#
# EVERY GROUND HEIGHT COMES FROM THE FIELD. Nothing in this file types a "y".

const TB := preload("res://scripts/training/training_build.gd")
const PLAZA_SPAWN := Vector2(0.0, 4.8)
const MIRA_AT := Vector2(2.6, 2.4)
const RACK_AT := Vector2(-3.4, 3.0)
const POST_AT := Vector2(4.9, -1.2)
const ALLEY_AT := Vector2(17.0, 9.6)
const CRATE_AT := Vector2(13.2, 8.2)

## THE PAVING AND THE TIMBER COME FROM `MistvaleTown`, NOT FROM HERE. §22 of the
## art masterplan asks for ONE palette per settlement, and this square is part of
## the same town as the houses on the ridge. A locally-invented paving a value
## darker than the town's own stone is exactly how two files end up disagreeing
## about what this valley is made of - which is the defect that note exists for.
##
## `PAVE_WORN` IS THE SAME STONE WORN, and the step between the two is 0.076.
## It was 0.134, and at eye height a step that wide is read as a two-colour
## CHECKERBOARD rather than as stonework: the eye resolves the alternation as
## pattern long before it resolves it as wear, and an 8.6 m disc of visible
## squares reads as a rug on the square. Darker is not the same as worn.
const PAVE := MistvaleTown.STONE
const PAVE_WORN := Color(0.520, 0.510, 0.484)
const MARKET_WOOD := MistvaleTown.TIMBER

## How far the apron's stone stands above whatever it is laid on. The surface
## underneath is now `MistvaleLand.paving_height()` - the town's own market
## paving - so this is a 2.5 cm lip and nothing more. It used to be 0.14 m, and
## that number was doing a job no lift could do: see `_paving_base()`.
const PAVING_CLEARANCE := 0.025

@export var spawn_path: NodePath
@export var stele_path: NodePath
@export var npc_path: NodePath
@export var rack_path: NodePath
@export var post_path: NodePath
@export var director_path: NodePath
@export var ui_path: NodePath
@export var alley_marker_path: NodePath

var _player: CharacterBody3D = null
var _spawn: Node3D = null
var _stele: Node3D = null
var _npc: MiraActor = null
var _rack: Node3D = null
var _post: TrainingPost = null
var _director: StoryDirector = null
var _ui: StoryUI = null
var _combat: Node = null
var _hold: SwordHoldController = null
var _vfx: CombatScreenFX = null
var _hub_target: Node = null
var _hub_prompt := ""
var _profile_saved := {}

var _wind: AudioStreamPlayer = null
var _bell: AudioStreamPlayer = null
var _pave_nodes: Array[Node] = []
## The region's land layer, which owns the town's own paving surfaces. Resolved
## once in `_dress()`; see `_paving_base()` for why the apron needs it.
var _land: MistvaleLand = null


func _ready() -> void:
	_resolve()
	_apply_input_profile()
	_dress()
	_wire()
	# THE PLAYER IS PLACED AFTER THE DRESSING, not in the .tscn, because the
	# spawn's height is a property of the height field and the field is the
	# authority. A spawn coordinate typed into a scene file is a fifth source of
	# truth for where the ground is.
	_place_player()
	set_process(true)


func _resolve() -> void:
	_spawn = get_node_or_null(spawn_path) as Node3D
	_stele = get_node_or_null(stele_path) as Node3D
	_npc = get_node_or_null(npc_path) as MiraActor
	_rack = get_node_or_null(rack_path) as Node3D
	_post = get_node_or_null(post_path) as TrainingPost
	_director = get_node_or_null(director_path) as StoryDirector
	_ui = get_node_or_null(ui_path) as StoryUI
	_player = get_node_or_null("Player") as CharacterBody3D
	_vfx = get_node_or_null("CombatScreenFX") as CombatScreenFX
	if _player != null:
		_combat = _player.get_node_or_null("CombatController")
		_hold = _player.get_node_or_null("SwordHoldController") as SwordHoldController
		if _hold == null:
			# BUILT HERE RATHER THAN ADDED TO `Player.tscn`, AND THAT IS A
			# DELIBERATE BOUNDARY. `Player.tscn` is shared with the combat sandbox
			# and the training ground, where the draw is already owned by
			# `WeaponManager` as the arrival half of a weapon SWITCH. Mounting a
			# second owner of `equip_blend` in all three scenes would give the
			# sandbox two things animating one number. The first playable is the
			# only world where "draw the sword you are already holding" is a
			# player-facing action, so it is the only world that creates this node -
			# and the seam it needs on the Player (`CombatController.equip_blend`)
			# already existed.
			_hold = SwordHoldController.new()
			_hold.name = "SwordHoldController"
			_player.add_child(_hold)


# ============================================================ 1. input profile
#
# THE COMBAT LAB AND A TOWN SQUARE NEED DIFFERENT KEYS, AND THE PROJECT HAS NO
# `[input]` SECTION TO PUT EITHER IN. Every binding in this codebase is created
# at runtime by the script that owns it, which is fine until two scripts claim
# the same key for different things - and they do:
#
#   CombatController binds `cast_selected` to E and every rack in the project
#   binds `interact` to E. It binds `frost_cast` to R, which is where a player's
#   hand already expects a draw.
#
# In a world that mounts a Player AND an NPC, both actions fire on the same press
# and the winner would depend on node order in the tree - i.e. on nothing a reader
# can see. Rather than adding branch to either system, this world states its
# profile once, and RESTORES IT ON EXIT so leaving for the combat sandbox puts
# the lab's keymap back exactly as it was.
#
# WHAT THE FIRST PLAYABLE NEEDS, AND THEREFORE ALL THAT SURVIVES:
#
#   WASD / Space / Shift / Ctrl / Alt   move, jump, dodge→sprint, crouch, walk
#   LMB                                 attack            (§8)
#   RMB                                 block             (already in the sword)
#   F                                   heavy             (already in the sword)
#   E                                   interact          (§5)
#   R                                   draw / sheathe    (§7)
#   Q                                   the one skill     (§10)
#
# WHAT IS RELEASED. Magic (four actions), the two style skills the first playable
# does not grant, the 7-second Iaido ceremony, the ultimate, and BOTH weapon keys.
# §26 rules all of them out of scope, and an action that is bound but
# unimplemented is worse than an unbound one: the player presses it, gets nothing,
# and concludes the game is broken.
#
# `weapon_1` IS ON THE LIST AND THAT IS NOT AN OVERSIGHT. `WeaponManager` binds it
# to the sword, so leaving it live means the player can summon a sword out of
# nothing with the 1 key on the first frame of the game - which is §6's exact
# prohibition (剑瞬间进入 Inventory) reached by a different door, and it would
# happen before Mira has even spoken. The only sword in this world comes off the
# rack or it does not exist.
const RELEASED_ACTIONS := [
	&"cast_selected", &"fire_cast", &"frost_cast", &"wind_cast",
	&"style_skill_2", &"style_skill_3", &"iaido", &"skill_1", &"ultimate",
	&"weapon_1", &"weapon_2",
]

## INPUT CONTRACT V0.1: world interact is F. Plaza story skill (剑气) uses E as
## Skill 1 via style_skill_1 — iaido/skill_1 are released so E does not fire 居合.
const INTERACT_KEY := KEY_F
const SKILL_KEY := KEY_E


func _apply_input_profile() -> void:
	for action in RELEASED_ACTIONS:
		_save_and_clear(action)
	# R remains draw_sword (legacy story control; contract reserves R for NEW work).
	# E = Skill 1 for plaza 剑气 lesson (not interact, not iaido).
	_rebind(&"style_skill_1", SKILL_KEY)
	_rebind(&"draw_sword", KEY_R)
	_bind_interact()


## F IS WORLD INTERACT. InputContract binds it; plaza ensures the action exists
## in town scenes that load before / without the combat sandbox.
##
## THE ACTION IS CREATED IF ABSENT AND OTHERWISE LEFT ALONE, because in the combat
## sandbox InputContract already owns the same key, and a second identical event
## would be the duplicate this file's `_rebind` exists to prevent.
func _bind_interact() -> void:
	if not InputMap.has_action(&"interact"):
		InputMap.add_action(&"interact")
	_rebind(&"interact", INTERACT_KEY)


func _save_and_clear(action: StringName) -> void:
	if not InputMap.has_action(action):
		return
	# An EMPTY event list is stored as an empty array rather than as "absent", so
	# the restore knows the difference between "this world released it" and
	# "nothing ever bound it".
	_profile_saved[action] = InputMap.action_get_events(action).duplicate()
	for ev in InputMap.action_get_events(action):
		InputMap.action_erase_event(action, ev)


func _rebind(action: StringName, key: Key) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	if not _profile_saved.has(action):
		_profile_saved[action] = InputMap.action_get_events(action).duplicate()
	if action == &"style_skill_1":
		for ev in InputMap.action_get_events(action):
			InputMap.action_erase_event(action, ev)
	# IDEMPOTENT, AND IT HAS TO BE. `SwordHoldController._ready()` also binds R to
	# `draw_sword`, and it runs BEFORE this function does - the controller is a
	# child of the Player, and a child is ready before the plaza that parents it.
	# Without the check below the action ends up carrying two identical key
	# events, which behaves correctly and is still wrong twice over: it misstates
	# how many bindings exist, and the restore at `_exit_tree` would write the
	# duplicate back into the combat lab's keymap.
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey and (ev as InputEventKey).physical_keycode == key:
			return
	var e := InputEventKey.new()
	e.physical_keycode = key
	InputMap.action_add_event(action, e)


func _restore_input_profile() -> void:
	for action in _profile_saved.keys():
		if not InputMap.has_action(action):
			continue
		for ev in InputMap.action_get_events(action):
			InputMap.action_erase_event(action, ev)
		for ev in _profile_saved[action]:
			InputMap.action_add_event(action, ev)
	_profile_saved.clear()


func _exit_tree() -> void:
	_restore_input_profile()
	Engine.time_scale = 1.0


# ================================================================ 2. dressing

func _dress() -> void:
	_place_actors()
	_land = get_node_or_null("Land") as MistvaleLand
	# --- the paved apron -----------------------------------------------------
	#
	# A DISC, TESSELLATED ALONG THE SURFACE, not a flat slab. The square is on a
	# slope (the masterplan's market sits on a 0.90 relief factor), and a single
	# flat 15 m plate would bury its low edge and float its high one.
	#
	# AND IT IS LAID ON `_paving_base()`, WHICH IS THE TOWN'S OWN PAVING AND NOT
	# THE BARE FIELD. This is the fix for a whole round of "the paving does not
	# render": the apron was built from `MistvaleHeights.height_at` plus 14 cm,
	# and `MistvaleLand` lays its market ribbon 25.8 cm above that field, so the
	# apron was drawn every frame from 12 cm underneath it. Raising the lift would
	# have buried it deeper under the thing doing the burying. See `_paving_base`.
	_pave_disc(Vector2.ZERO, 8.6, 12, 48, PAVING_CLEARANCE)
	# --- the two roads out (§1) ---------------------------------------------
	# South: toward the gate and the lower town. North-east: back into the
	# residential streets. Both are stubs that hand off to the region's own road
	# geometry further out, which is why they are built to a length and a
	# direction rather than to a destination.
	_pave_strip(Vector2(0.0, 6.6), Vector2(-1.6, 26.0), 5.4, PAVING_CLEARANCE)
	_pave_strip(Vector2(5.4, -2.2), Vector2(12.0, -20.0), 4.6, PAVING_CLEARANCE)
	# --- the market edge ----------------------------------------------------
	_stalls()
	# --- the alley, and the crates the hound goes through -------------------
	_crates()
	_signpost(Vector2(-2.4, 15.0), "南 · 城门 / 下城区", Color(0.86, 0.82, 0.70))
	_signpost(Vector2(6.6, -6.4), "北 · 居民区 / 冒险者公会", Color(0.86, 0.82, 0.70))
	_ambient()


## PUTS EVERY ACTOR ON THE GROUND, AND THE LAYOUT LIVES HERE RATHER THAN IN THE
## .tscn.
##
## WHY THE POSITIONS ARE CONSTANTS IN THIS FILE. The alternative is XZ typed into
## the scene and a `y` typed into the scene, which makes the scene file a second
## source of truth for a layout that already exists in one, and lets the square
## drift out of agreement with the alley the hound enters from. Here the layout is
## five `Vector2`s at the top of the file, one of them is the spawn, and moving the
## rack moves the rack.
##
## AND WHY EVERY `y` COMES FROM `MistvaleHeights`. The terrain under this square is
## a height field sampled at 2 m; a hand-written elevation that disagrees with it by
## a hand's width is a prop buried to its ankles or floating over its own shadow, and
## that disagreement is invisible in the scene file and obvious in the game.
func _place_actors() -> void:
	_put(_stele, Vector2.ZERO)
	_put(_npc, MIRA_AT)
	_put(_rack, RACK_AT)
	_put(_post, POST_AT)
	_put(_spawn, PLAZA_SPAWN)
	var alley := get_node_or_null(alley_marker_path) as Node3D
	_put(alley, ALLEY_AT)


func _put(node: Node3D, at: Vector2) -> void:
	if node == null:
		return
	node.position = Vector3(at.x, MistvaleHeights.height_at(at.x, at.y), at.y)


## A tessellated disc of paving, sampled from the height field.
func _pave_disc(centre: Vector2, radius: float, rings: int, segments: int,
		lift: float) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for r in rings:
		var r0 := radius * float(r) / float(rings)
		var r1 := radius * float(r + 1) / float(rings)
		for s in segments:
			var a0 := TAU * float(s) / float(segments)
			var a1 := TAU * float(s + 1) / float(segments)
			var p00 := _paved_point(centre, r0, a0, lift)
			var p01 := _paved_point(centre, r0, a1, lift)
			var p10 := _paved_point(centre, r1, a0, lift)
			var p11 := _paved_point(centre, r1, a1, lift)
			# Alternating wear, so the apron is not one flat value. A single
			# colour across 8 m of ground reads as a decal; the difference between
			# PAVE and PAVE_WORN is small on purpose and is enough.
			# THE CHECKER IS DEPTH-LIMITED TOWARD THE RIM, not carried to it. A
			# two-value checker run out to the edge draws a hard circle of one
			# material inside another; at eye height that reads as a rug laid on
			# the square rather than as the square's own stone, which is what the
			# first render of this apron looked like. Fading the alternation out
			# over the outer two fifths keeps the stonework legible underfoot,
			# where the player is actually looking, and lets the apron meet the
			# town's paving underneath it without a rim to notice.
			var phase := float(r + 1) / float(rings)
			var wear := (0.0 if (r + s) % 2 == 0 else 1.0) \
					* (1.0 - smoothstep(0.58, 1.0, phase))
			_tri(st, p00, p10, p11, wear)
			_tri(st, p00, p11, p01, wear)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.name = "PavedApron"
	mi.mesh = st.commit()
	mi.material_override = _pave_material()
	# NO COLLISION, AND THAT IS STILL RIGHT. The `Terrain` node underneath has it,
	# and the motor settles the player on that field - which is 28 cm below this
	# stone, because the town's paving is a visual ribbon with no collider of its
	# own. A second surface up here would be a lip for the character controller to
	# catch on and a second answer to "where is the ground", which the project
	# already has exactly one of.
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	_pave_nodes.append(mi)


## THE SURFACE THE APRON IS LAID ON, AND IT IS NOT `MistvaleHeights.height_at`.
##
## A whole round went into why the paving did not render. The disc was
## well-formed - 1152 triangles, every normal facing up - stood 14 cm above the
## analytic field, was `visible` in a `visible` tree, and was drawn. The square
## still read as bare dirt, and hiding the `Terrain` node did not reveal it.
##
## It was there the whole time, 12 cm UNDERNEATH the market junction.
## `MistvaleLand` lays its own paving ribbon over the field, and that ribbon
## stands `LIFT + MARKET_PAVING_LIFT` = 25.8 cm up. Two paving layers, the upper
## one brown and semi-transparent, and the one you could see in every screenshot
## was the one doing the burying. Raising this apron's lift, which is the obvious
## repair and the one tried first, makes the burying layer bury it deeper.
##
## So the apron asks the town where the town's paving is, and stands on it. A
## tree with no `Land` node falls back to the same arithmetic by hand, because
## the junction's lift is a `static` function of its constants.
func _paving_base(x: float, z: float) -> float:
	if _land != null:
		return _land.paving_height(x, z)
	return MistvaleHeights.height_at(x, z) \
			+ MistvaleLand.LIFT + MistvaleLand.market_paving_lift(x, z)


func _paved_point(centre: Vector2, r: float, angle: float, lift: float) -> Vector3:
	var x := centre.x + cos(angle) * r
	var z := centre.y + sin(angle) * r
	return Vector3(x, _paving_base(x, z) + lift, z)


func _pave_strip(from: Vector2, to: Vector2, width: float, lift: float) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var span := from.distance_to(to)
	var steps := maxi(2, int(span / 2.0))
	var dir := (to - from).normalized()
	var side := Vector2(-dir.y, dir.x) * width * 0.5
	for i in steps:
		var t0 := float(i) / float(steps)
		var t1 := float(i + 1) / float(steps)
		var a := from + (to - from) * t0
		var b := from + (to - from) * t1
		# ABSOLUTE XZ, each corner sampled on its own. A strip whose four corners
		# share one height is a flat plate laid across a slope, which is exactly
		# the failure the disc above is tessellated to avoid - a road that buries
		# its downhill edge and floats its uphill one.
		var l0 := _paved_point_at(a.x - side.x, a.y - side.y, lift)
		var l1 := _paved_point_at(a.x + side.x, a.y + side.y, lift)
		var m0 := _paved_point_at(b.x - side.x, b.y - side.y, lift)
		var m1 := _paved_point_at(b.x + side.x, b.y + side.y, lift)
		var wear := 0.0 if i % 2 == 0 else 1.0
		_tri(st, l0, m0, m1, wear)
		_tri(st, l0, m1, l1, wear)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.name = "PavedPath"
	mi.mesh = st.commit()
	mi.material_override = _pave_material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	_pave_nodes.append(mi)


func _paved_point_at(x: float, z: float, lift: float) -> Vector3:
	return Vector3(x, _paving_base(x, z) + lift, z)


func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, wear: float) -> void:
	var col := PAVE_WORN.lerp(PAVE, wear)
	for p in [a, b, c]:
		st.set_color(col)
		st.add_vertex(p)


func _pave_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	# VERTEX COLOUR AS ALBEDO, which is how every other builder in this project
	# paints a landscape surface. A texture would be a second asset to schedule.
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.88
	m.metallic = 0.0
	return m


## Market stalls along the west edge. Enough of them to say "people sell things
## here", few enough that nobody has to model a cabbage this round.
func _stalls() -> void:
	var row := Node3D.new()
	row.name = "MarketRow"
	add_child(row)
	var timber := TB.material(MARKET_WOOD, 0.86)
	var cloth := TB.material(Color(0.512, 0.404, 0.318), 0.92)
	for i in 3:
		var at := Vector2(-7.6 - float(i) * 0.4, -5.0 + float(i) * 3.4)
		var y := MistvaleHeights.height_at(at.x, at.y)
		var base := Vector3(at.x, y, at.y)
		var stall := Node3D.new()
		stall.name = "Stall%d" % i
		stall.position = base
		stall.rotation.y = 1.35
		row.add_child(stall)
		# Four legs, a counter, and a sloping cloth roof - the minimum that reads
		# as a stall from across a square.
		for sx in [-0.9, 0.9]:
			for sz in [-0.55, 0.55]:
				TB.post(stall, "Leg", Vector3(sx, 0.0, sz), 0.92, 0.045, timber)
		TB.slab(stall, "Counter", Vector3(0.0, 0.92, 0.0), Vector3(2.1, 0.07, 1.35), timber)
		var roof := TB.slab(stall, "Canopy", Vector3(0.0, 1.62, 0.0),
			Vector3(2.3, 0.06, 1.6), cloth, false)
		roof.rotation.x = 0.13


## The crates at the alley mouth, and the marker the hound enters by.
##
## WHY THE CRATES EXIST AT ALL. §13 asks for the monster's arrival to have a
## process, and "撞翻木箱" is that process made visible: a thing that knocks over
## what was standing there has VOLUME, and a player who hears that off to the
## right knows where to look before they have seen anything. The hound does not
## actually collide with them - it declares that it went through them, and they
## are already scattered - because a real physics collision between a monster and
## a stack of boxes is a whole afternoon for one second of screen time.
func _crates() -> void:
	var group := Node3D.new()
	group.name = "AlleyCrates"
	add_child(group)
	var timber := TB.material(Color(0.352, 0.266, 0.184), 0.9)
	var stack := [
		[0.0, 0.0, 0.0, 0.0],
		[0.34, 0.0, 0.62, 0.0],
		[0.16, 0.34, 0.30, 0.42],
		[0.52, 0.0, -0.30, -0.24],
	]
	for row in stack:
		var at := CRATE_AT + Vector2(row[0], row[2])
		var y := MistvaleHeights.height_at(at.x, at.y) + float(row[3])
		var size := 0.46
		var box := TB.slab(group, "Crate", Vector3(at.x, y + size * 0.5, at.y),
			Vector3(size, size, size), timber, true)
		box.get_parent().rotation.y = float(row[0]) * 2.2
	# The spawn marker itself is in the .tscn; this only draws the mouth of the
	# alley so the direction the hound comes from is legible.
	var mouth := get_node_or_null(alley_marker_path) as Node3D
	if mouth != null:
		var at := Vector2(mouth.global_position.x, mouth.global_position.z)
		var y := MistvaleHeights.height_at(at.x, at.y)
		# THE BEAM NEEDS SOMETHING TO STAND ON. It was a bare slab 2.6 m up and it
		# rendered as a plank floating in the sky, legible from most of the square
		# and reading as a bug rather than as architecture. Two uprights cost six
		# lines and turn the same geometry into a gate - which is more than
		# decoration here: §13 needs the direction the hound comes from to be a
		# PLACE, and a gate is a place.
		var gate := Node3D.new()
		gate.name = "AlleyGate"
		gate.position = Vector3(at.x, y, at.y)
		gate.rotation.y = 0.6
		add_child(gate)
		for sx in [-1.7, 1.7]:
			TB.post(gate, "GatePost", Vector3(sx, 0.0, 0.0), 2.6, 0.13, timber, true)
		TB.slab(gate, "GateBeam", Vector3(0.0, 2.62, 0.0),
			Vector3(3.9, 0.30, 0.42), timber, true)


func _signpost(at: Vector2, text: String, colour: Color) -> void:
	var y := MistvaleHeights.height_at(at.x, at.y)
	var post := Node3D.new()
	post.name = "Signpost"
	post.position = Vector3(at.x, y, at.y)
	add_child(post)
	var timber := TB.material(MARKET_WOOD, 0.86)
	TB.post(post, "Pole", Vector3.ZERO, 2.1, 0.055, timber, true)
	TB.label(post, "Sign", text, Vector3(0.0, 2.25, 0.0), 0.26, colour)


func _ambient() -> void:
	# §25: 禁止完全静音完成. The square has wind under it from the first frame.
	#
	# The wind is a LOOP, set here rather than in the .import file: the same
	# source asset is used one-shot elsewhere, and a stream resource is shared, so
	# turning on looping at the file level would change every other user of it.
	_wind = AudioStreamPlayer.new()
	_wind.name = "AmbientWind"
	var path := "res://audio/sfx/core/wind_pressure_01.wav"
	if ResourceLoader.exists(path):
		var s := load(path)
		if s is AudioStreamWAV:
			(s as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
			(s as AudioStreamWAV).loop_end = int((s as AudioStreamWAV).mix_rate * 2.5)
		_wind.stream = s
	_wind.volume_db = -22.0
	_wind.autoplay = true
	_wind.add_to_group("world_audio")
	add_child(_wind)

	# THE BELL, AND IT IS A PLACEHOLDER THAT SAYS SO.
	#
	# There is no bell asset in the project (174 audio files, none of them a
	# bell), so §2's 远处钟声 is stood in by `metal_sharp_02` pitched down to 0.34
	# - a struck metal resonance, an octave and a half below where it was
	# authored, at low volume. It reads as a struck object across a valley, which
	# is what the opening needs, and a real bell is on the AUDIO line as a
	# REQUEST rather than quietly faked here.
	_bell = AudioStreamPlayer.new()
	_bell.name = "DistantBell"
	var bell_path := "res://audio/sfx/core/metal_sharp_02.wav"
	if ResourceLoader.exists(bell_path):
		_bell.stream = load(bell_path)
	_bell.volume_db = -17.0
	_bell.pitch_scale = 0.34
	_bell.add_to_group("world_audio")
	add_child(_bell)


func ring_bell() -> void:
	if _bell != null and _bell.stream != null:
		_bell.play()


# ================================================================ 3. wiring

func _wire() -> void:
	if _director == null or _ui == null:
		push_warning("MistvalePlaza: no StoryDirector or StoryUI at the exported "
			+ "paths, so the first playable sequence will not run.")
		return
	# THE HUD LISTENS TO THE DIRECTOR AND NOTHING ELSE. It never asks a question
	# and never reads a stage, which is what lets the whole surface above the
	# world be one-directional: something happened, so something is said.
	_director.said.connect(_ui.subtitle)
	_director.dialogue_started.connect(_ui.open_dialogue)
	_director.objective_changed.connect(_ui.objective)
	_director.toasted.connect(_ui.toast)
	_director.quest_updated.connect(_ui.quest)
	_director.prompt_changed.connect(_ui.prompt)
	_director.hound_spawned.connect(_on_hound_spawned)
	_director.stage_changed.connect(_on_stage_changed)
	_director.anomaly.connect(_on_anomaly)

	# --- the sword ----------------------------------------------------------
	#
	# `has_signal`, NOT `has_method`. They are different questions and only one of
	# them is about signals: `has_method("taken")` is FALSE for a signal, so this
	# guard skipped the connection silently while the pick-up itself still worked
	# (the blade left the rack, the slot filled, the pose came home). The story
	# simply never heard about any of it - §6's beat, §22's flag and the whole
	# downstream chain were all waiting on a `connect()` that never ran, and no
	# error was ever printed.
	if _rack != null and _rack.has_signal("taken"):
		_rack.connect("taken", _on_sword_taken)
	if _hold != null:
		_hold.draw_finished.connect(_on_draw_finished)

	# --- combat facts the story advances on (§21) ---------------------------
	if _combat != null:
		_combat.connect("hit_landed", _on_hit_landed)
		_combat.connect("style_message", _on_style_message)
	if _post != null:
		_post.connect("struck", _on_post_struck)

	if _player != null:
		# §21 again: attacking the AIR is not the lesson. The post's own hurtbox
		# already reports being struck, and that is the only signal the story
		# listens to for BASIC_ATTACK.
		_player.unlimited_resources = true


## How far above the ground the body's ORIGIN belongs.
##
## IT USED TO BE A FLAT 0.12, AND THAT MADE THE GAME UNPLAYABLE. `Player.tscn`'s
## collision capsule is 1.8 m tall and centred on the body origin, so an origin
## 0.12 m above the ground puts the capsule's bottom 0.78 m BELOW it. A body
## embedded in the terrain collision answers `is_on_floor() == false` and resolves
## `move_and_slide()` to zero motion, so the player could not walk a single
## centimetre - and nothing else in the world looked wrong. The headless smoke
## test passed 71 checks while the first playable was a still image of a town.
##
## DERIVED FROM THE SHAPE, NOT WRITTEN AS 0.9: a taller player, or a capsule with
## an offset, must not be able to silently re-create the bug. The margin drops the
## body a few centimetres onto a terrain mesh that is not flat, so the first frame
## is a landing rather than a coincidence.
const STAND_MARGIN := 0.15


func _stand_height() -> float:
	var shape := _player.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if shape == null:
		return 0.9 + STAND_MARGIN
	var capsule := shape.shape as CapsuleShape3D
	if capsule != null:
		# Bottom of the capsule = origin + shape.position.y - height/2.
		return capsule.height * 0.5 - shape.position.y + STAND_MARGIN
	var box := shape.shape as BoxShape3D
	if box != null:
		return box.size.y * 0.5 - shape.position.y + STAND_MARGIN
	return 0.9 + STAND_MARGIN


func _place_player() -> void:
	if _player == null:
		return
	var where := PLAZA_SPAWN
	if _spawn != null:
		where = Vector2(_spawn.global_position.x, _spawn.global_position.z)
	var y := MistvaleHeights.height_at(where.x, where.y)
	_player.global_position = Vector3(where.x, y + _stand_height(), where.y)
	# Facing NORTH, which is -Z, because that is where the stele is: the player
	# wakes up lying at the foot of the thing this square is built around, and the
	# bell tower stands a hundred metres beyond it. §1 asks for a sense of arriving
	# at the centre of a world, and the composition delivers it before a word is
	# spoken. (A camera looks along -basis.z, so yaw 0 is already north.)
	_player.rotation.y = 0.0
	_prime_player_state()


## §2: 玩家没有拔剑。最好甚至一开始没有装备剑。
##
## THE PLAYER BEGINS WITH EMPTY HANDS, AND THE MECHANISM IS THE SLOT. Setting
## `kind` to `NONE` is what actually makes §2 true - see the note in
## `weapon_slot.gd` for why a story-layer boolean would not have been enough.
##
## ORDER MATTERS HERE AND IT IS THE WHOLE TRICK OF THIS FUNCTION. The slot is
## written BEFORE anything can render, so the first frame the player ever sees
## already has no sword in it; and writing it through `equip()` rather than by
## assignment means `WeaponManager`'s change handler runs and hides the rig, drops
## the buffered input and snaps `equip_blend` to 0 with no code of ours involved.
func _prime_player_state() -> void:
	# Annotated rather than inferred. `:=` here asks the compiler to derive the
	# type from `is_returning_player()`'s return value, so a parse problem in
	# `story_director.gd` reports itself a second time as "cannot infer the type
	# of returning" and sends you looking in the wrong file for the real error.
	var returning: bool = _director != null and _director.is_returning_player()
	var slot := _player.get_node_or_null("WeaponSlot") as WeaponSlot
	if not returning and slot != null:
		slot.equip(WeaponSlot.NONE)
	# §20: 开始几乎没有UI. The weapon manager's own bottom-right key legend is a
	# developer affordance from the combat line, and it is the only piece of HUD in
	# this game that exists before the game does. Its own key (F7) still brings it
	# back - this only changes what the first frame looks like.
	var manager := _player.get_node_or_null("WeaponManager")
	if manager != null:
		manager.call("_set_indicator_shown", false)
	if returning and _hold != null:
		_hold.force_drawn()


func _on_stage_changed(previous: int, current: int) -> void:
	print("[PLAZA] stage %d -> %d" % [previous, current])


func _on_anomaly(_strength: float) -> void:
	# The visible half of the world blinking. The SOUND half belongs to the
	# director, which ducks the world through `AudioStateController` - this only
	# draws the colour draining out of the frame.
	if _vfx != null:
		_vfx.set_world_drain(0.45)


## The pick-up, told to both halves of the game - and THE ORDER IS THE POINT.
##
## `force_sheathed()` first, so the story is told about a sword that is already
## where it belongs. Then the director, which is what advances the sequence,
## writes §22's `has_first_sword` flag and sets DRAW_SWORD. Every other hook in
## this file delegates to the director like this one; this one did not, and the
## result was the most expensive bug of the round: the ceremony played perfectly
## - the blade left the rack, the toast appeared, the slot filled - and the story
## never heard about it, so `on_sword_drawn` refused (it only advances FROM
## DRAW_SWORD), the training hit was refused, the skill was refused, and the
## hound never arrived. A visual beat that the systems do not know about is a
## cutscene, and §31 asks for a causal chain.
func _on_sword_taken() -> void:
	if _hold != null:
		_hold.force_sheathed()
	_ui.toast(SwordPickup.SWORD_NAME, "已装备")
	if _director != null:
		_director.on_sword_taken()


func _on_draw_finished() -> void:
	if _director != null:
		_director.on_sword_drawn()


func _on_post_struck() -> void:
	if _director != null:
		_director.on_training_hit()


func _on_hit_landed(_move: SwordMove, hit: Dictionary) -> void:
	if _post == null or _director == null or _combat == null:
		return
	var target = hit.get("target")
	if target != _post:
		return
	# THE SKILL LESSON NEEDS THE SKILL, NOT MERELY A HIT.
	#
	# `sb_a2` — which is what the 剑气 skill plays — is ALSO the second beat of the
	# light chain (A1 → A2 → A3 → A4). So "the move that landed was sb_a2" does not
	# distinguish the skill from an ordinary second light attack, and gating on the
	# move id would let a player finish the skill lesson with two left-clicks and
	# never touch Q. The controller already keeps the honest answer: `attack_kind`
	# is set to `skill` by `trigger_skill` and to `light` / `heavy` by the others,
	# and it is the only field that says WHY the blade is moving.
	if StringName(_combat.get("attack_kind")) == &"skill" \
			and _director.stage == StoryDirector.Stage.USE_SKILL:
		_director.on_skill_connected()


func _on_style_message(text: String) -> void:
	if _director == null:
		return
	# The skill announces its own name when it starts (`SwordSkill.display_name`)
	# and appends "· 冷却中" when it refuses. So the exact-match test is the
	# difference between "the player released the skill" and "the player pressed Q
	# into a cooldown", and the second one must not advance the story.
	if text == SKILL_LABEL and _director.stage == StoryDirector.Stage.USE_SKILL:
		_director.on_skill_released()


## The name the sword skill reports. It is the moveset's `display_name`, checked
## against the same string `moveset_library.gd` authors so the two cannot drift.
const SKILL_LABEL := "剑气"


func _on_hound_spawned() -> void:
	pass


# ============================================================ 4. interaction

func _process(delta: float) -> void:
	if _player == null:
		return
	_update_hub()
	if _ui == null or _director == null:
		return
	# §28: the overlay is always fed and never shown unless F3 asked for it. That
	# is the opposite of the usual arrangement and it is deliberate - a debug line
	# computed only when visible is a debug line that has never run on the frame
	# you needed it.
	_ui.set_debug_line(_debug_text())
	# §20: 第一战才显示 HP. The bar appears when there is something in the world
	# that can take it away, which is a property of the STORY, not of the player.
	if _director.stage >= StoryDirector.Stage.FIRST_COMBAT:
		_ui.show_health(_player.health, 100.0)


func _update_hub() -> void:
	var best: Node = null
	var best_d := 1e9
	for node in get_tree().get_nodes_in_group(&"interactable"):
		if not (node is Node3D) or not node.has_method("interact_label"):
			continue
		if node.has_method("can_interact") and not bool(node.call("can_interact")):
			continue
		if _prompt_for(node) == "":
			continue
		var reach := 3.0
		if node.has_method("interact_range"):
			reach = float(node.call("interact_range"))
		var d: float = _player.global_position.distance_to((node as Node3D).global_position)
		if d <= reach and d < best_d:
			best = node
			best_d = d
	var text := _prompt_for(best)
	# COMPARED, NOT JUST RE-ASSIGNED. The target can stay the same while its
	# prompt changes - Mira goes from "nothing to say" to "[F] 交谈" the moment the
	# opening beat finishes, and the player may already be standing next to her when
	# it does. Caching on the NODE alone (the obvious version) leaves the prompt on
	# screen saying the wrong thing precisely when it matters.
	if best == _hub_target and text == _hub_prompt:
		return
	_hub_target = best
	_hub_prompt = text
	if _ui != null:
		_ui.prompt(text)


## THE ONE PLACE THAT DECIDES WHAT E SAYS. Two kinds of interactable exist in this
## world and they answer differently:
##
##   Mira      her prompt is a property of the STORY, not of her. She has nothing
##             to say before she has noticed you, and she has nothing new to say
##             while you are mid-lesson - so the director is asked.
##   the rack  its prompt is a property of ITSELF, so it answers for itself.
func _prompt_for(node: Node) -> String:
	if node == null:
		return ""
	if node is MiraActor:
		if _director == null:
			return ""
		return _director.npc_prompt()
	return String(node.call("interact_label"))


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed(&"interact") or _hub_target == null:
		return
	if _ui != null and _ui.is_talking():
		# A conversation owns E. Because StoryUI takes key presses in `_input`,
		# which runs before this, reaching here while a dialogue is open would
		# mean the UI had already declined the key - and the honest answer then is
		# to do nothing rather than to start a second conversation.
		return
	var target := _hub_target
	if target is MiraActor:
		if _director != null and _director.try_talk():
			get_viewport().set_input_as_handled()
		return
	if target.has_method("interact"):
		if bool(target.call("interact", _player)):
			get_viewport().set_input_as_handled()


func _debug_text() -> String:
	var lines := PackedStringArray()
	if _director != null:
		lines.append(_director.debug_line())
	if _hold != null:
		lines.append(_hold.debug_line())
	if _npc != null:
		lines.append("MIRA  %s  %s" % [_npc.mode_name(),
			"in range" if _player != null
				and _npc.global_position.distance_to(_player.global_position)
					<= MiraActor.TALK_RANGE else "away"])
	lines.append("PROMPT  %s" % ("-" if _hub_target == null else _hub_target.name))
	return "\n".join(lines)
