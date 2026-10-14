extends SceneTree
##
## Records the CHAIN'S VOICE as a timeline, without playing it.
##
## WHY NOT JUST RENDER THE VIDEO AND LISTEN: a video renderer runs in real time on
## wall clock, and the chain's windows run on its own delta-accumulated clock
## (chain_director.gd §"CLOCKS"). Driving the weapon by wall time to produce an
## audio stem would place every beat by luck of the frame rate. So this drives the
## weapon with a FIXED step, lets ChainAudioDirector decide what sounds when - the
## same object, the same cue table, the same scheduling code the game runs - and
## writes down the cue ids with the clock they fired on.
##
## The mixer then has the design, not a copy of it. A hand-written mirror of the
## cue table is exactly the kind of thing that drifts 0.36s and nobody notices.
##
## Usage:
##   godot --headless --path godot --script res://tools/capture_chain_audio.gd
##   godot --headless --path godot --script res://tools/capture_chain_audio.gd -- <out.json>

const DT := 1.0 / 60.0
# Stands are chosen so a beat cannot be spoiled by the stage. The lab's fixed
# ANCHOR sits at (6.5, 0, -26) and a sweep treats an anchor as a WALL unless the
# technique hooks - so the open-deck beats stand clear of it, and the wall beat is
# the only one with a surface inside a throw's reach (9.6m).
const WALL_STAND := Vector3(0.0, 0.9, -34.5)
const OPEN_STAND := Vector3(0.0, 0.9, -30.0)
# Sweeps are shot ACROSS the deck (28m wide) rather than down it, so no structure
# is inside their reach and a beat about the ARC cannot turn into a beat about a
# collision.
const SWEEP_YAW := 90.0
const PARKED := Vector3(0.0, 0.0, 300.0)

## The technique's OWN voice, per move. A take that requests a technique and then
## never fires that cue is the failure this capture exists to catch: the animation
## is right, the caption is right, the cue table is right, and the weapon still has
## no sound of its own. Mirrors `ChainAudioDirector._on_move_started`.
const MOVE_CUE := {
	&"ch_sweep": &"chain_a1_sweep",
	&"ch_return": &"chain_a2_return",
	&"ch_throw": &"chain_a3_throw",
	&"ch_hook": &"chain_a3_throw",
	&"ch_launch": &"chain_launch",
	&"ch_snap": &"chain_snap_cut",
	&"ch_deflect": &"chain_deflect",
	&"ch_yank": &"chain_swing_short",
	&"ch_pull_cut": &"chain_swing_short",
	&"ch_slam": &"chain_slam_swing",
	&"ch_ground_slam": &"chain_slam_swing",
}

var sandbox: Node3D
var player: CharacterBody3D
var combat: CombatController
var weapon: WeaponSlot
var chain: ChainDirector
var lab: ChainLab
var look_pivot: Node3D
var audio: ChainAudioDirector

var moves: Array[String] = []
var notes: Array[String] = []
var frames := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out_path := String(args[0]) if args.size() > 0 else ""

	sandbox = load("res://scenes/combat/CombatSandbox.tscn").instantiate() as Node3D
	root.add_child(sandbox)
	for i in 3:
		await process_frame

	player = sandbox.get_node("Player") as CharacterBody3D
	combat = player.get_node("CombatController") as CombatController
	weapon = player.get_node("WeaponSlot") as WeaponSlot
	chain = player.get_node("ChainDirector") as ChainDirector
	look_pivot = player.get_node("CameraRig/LookPivot") as Node3D
	lab = sandbox.get_node_or_null("ChainLab") as ChainLab

	if chain == null:
		_fail("no ChainDirector")
		return
	# The director is spawned by CombatAudioDirector, and it is the OBJECT the game
	# plays through - not a copy of its logic.
	var combat_audio := sandbox.get_node_or_null("CombatAudioDirector")
	if combat_audio != null:
		audio = combat_audio.get("chain_audio") as ChainAudioDirector
	if audio == null:
		audio = ChainAudioDirector.new()
		audio.name = "StandaloneChainAudio"
		sandbox.add_child(audio)
		await process_frame

	# Take the clock. Both the weapon and its voice are stepped by hand from here,
	# so nothing depends on how many frames this machine manages.
	chain.manual_step = true
	audio.manual_step = true
	audio.capture_only = true
	audio.idle_interval_min = 1.1
	audio.idle_interval_max = 1.4
	audio.set_process(false)

	_equip_chain()
	await process_frame
	# A throw that lands on scenery turns a beat about the THROW into a beat about a
	# collision, so the staging is checked rather than assumed: this fires the same
	# ray the weapon's sweep does and names whatever is on the line.
	_probe_lanes()

	# ---------------------------------------------------------------- the takes
	# Every beat is followed long enough for the weapon to finish the sentence it
	# started, because a capture that cuts off a retract would report a weapon that
	# never lets go of anything.
	await _segment("IDLE 待机", 2.2,
		func() -> void:
			_stand(OPEN_STAND, SWEEP_YAW, -8.0)
			_park_targets(),
		func(t: float) -> void:
			# A step, so the idle SETTLE has something to answer - §4 asks for
			# near-silence at rest and a light settle when the weapon moves.
			if t > 0.7:
				player.velocity = Vector3(0.0, 0.0, -1.4)
	)
	await _segment("A1 左甩", 1.1, func() -> void:
		_park_targets()
		_light(&"ch_sweep"))
	await _segment("A2 快右左", 1.1, func() -> void:
		_light(&"ch_return"))
	await _segment("A3 直抛（落空 → 回收）", 2.4, func() -> void:
		# Level: the throw tilts toward the aim, so a downward look puts the head
		# into the deck and the beat becomes a collision. The whiff has to be a whiff.
		_stand(OPEN_STAND, SWEEP_YAW, 0.0)
		_light(&"ch_throw"))
	await _segment("BITE 撞墙 · 石头", 2.4, func() -> void:
		_stand(WALL_STAND, 0.0, 0.0)
		_park_targets()
		# The hook, not the light chain: it is the throw, and it can be taken
		# directly, so this beat does not depend on the previous take keeping the
		# combo warm.
		_press(&"chain_hook", &"ch_hook"))
	await _segment("HIT 命中敌人", 2.2, func() -> void:
		_stand(OPEN_STAND, SWEEP_YAW, -6.0)
		_place_target(ElementLibrary.WEIGHT_LIGHT, 3.4)
		_light(&"ch_sweep"))
	await _segment("HIT 命中重敌 → 回收", 2.6, func() -> void:
		_stand(OPEN_STAND, SWEEP_YAW, -6.0)
		_place_target(ElementLibrary.WEIGHT_HEAVY, 3.6)
		_light(&"ch_sweep"))

	var doc := {
		"events": audio.capture,
		"moves": moves,
		"notes": notes,
		"frames": frames,
		"clock": audio.clock,
		# The DESIGN travels with the recording. The mixer reads the cue table and
		# the atom groups out of the engine, so it cannot disagree with the game
		# about what a cue is made of - which is the failure mode a separate
		# hand-maintained copy of this table would have.
		"table": _table(),
	}
	var text := JSON.stringify(doc)
	print("SEKAI_CHAIN_CAPTURE_BEGIN")
	print(text)
	print("SEKAI_CHAIN_CAPTURE_END")
	print("capture: %d cues, %d frames, %.2fs" % [audio.capture.size(), frames, audio.clock])
	if not out_path.is_empty():
		var f := FileAccess.open(out_path, FileAccess.WRITE)
		if f != null:
			f.store_string(text)
			f.close()
			print("wrote %s" % out_path)
	quit()


# ------------------------------------------------------------------ driving

## One take: a fixed-length stretch of the weapon's own clock, with a per-frame
## hook for "what is the player doing right now".
## One take: a fixed-length stretch of the weapon's own clock.
##
## `once` runs on the FIRST frame only, and that is not a detail: a beat hook that
## ran every frame would re-request the technique the moment the weapon finished
## recovering, and a take claiming "A1" would render eight sweeps in a row. `each`
## exists for the one take that needs a per-frame condition (walking, so the idle
## settle has something to answer).
func _segment(label: String, seconds: float, once: Callable,
		each: Callable = Callable()) -> void:
	notes.append(label)
	print("--- %s" % label)
	var walls := chain.wall_hits
	var hits := chain.hits_landed
	var cue_from := audio.capture.size()
	var t := 0.0
	var steps := int(round(seconds / DT))
	for i in steps:
		if i == 0:
			once.call()
		if each.is_valid():
			each.call(t)
		chain.step(DT)
		audio.step(DT)
		frames += 1
		t += DT
		await process_frame
	# The technique has to have been HEARD, not just performed. Without this, a
	# `_queue`d move cue that gets dropped by the scheduler leaves a capture that
	# reports full health while the weapon's own voice is missing from every take.
	if _expect_cue != &"" and not _cue_fired(cue_from, _expect_cue):
		notes.append("  !! no %s - the technique had no voice" % String(_expect_cue))
		print("    !! no %s (the technique had no voice)" % String(_expect_cue))
	_expect_cue = &""
	# The weapon has to agree that this take happened. A beat that was staged and
	# refused is the one failure this capture must not report as a success.
	print("    walls +%d  hits +%d  cues +%d  r=%.2fm taut=%s head=%s" % [
		chain.wall_hits - walls, chain.hits_landed - hits, audio.capture.size() - _cue_mark,
		chain.radius, str(chain.is_taut()), str(chain.head_position().snapped(Vector3(0.1, 0.1, 0.1)))])
	_cue_mark = audio.capture.size()


var _cue_mark := 0
## Cue the take being staged is required to produce (from `MOVE_CUE`).
var _expect_cue: StringName = &""


## Did `cue_id` fire in the capture slice that starts at `from`?
func _cue_fired(from: int, cue_id: StringName) -> bool:
	for i in range(from, audio.capture.size()):
		if String(audio.capture[i]["cue"]) == String(cue_id):
			return true
	return false


## Which lanes are actually clear. The chain's own wall query is a ray on
## WALL_MASK=1 excluding targets and props, so the same query is the honest way to
## ask "will a throw down this line end on a surface?".
func _probe_lanes() -> void:
	var space := player.get_world_3d().direct_space_state
	if space == null:
		return
	var forward := -Vector3.RIGHT          # yaw 90: the sweep lane
	var down_deck := Vector3.FORWARD       # yaw 0: the throw lane
	for pair in [["across (yaw 90)", forward, OPEN_STAND],
			["down deck (yaw 0)", down_deck, OPEN_STAND],
			["at the wall", down_deck, WALL_STAND]]:
		var from: Vector3 = (pair[2] as Vector3) + Vector3.UP * 0.15
		var to: Vector3 = from + (pair[1] as Vector3) * 14.0
		var query := PhysicsRayQueryParameters3D.create(from, to, 1)
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			print("lane %-18s clear for 12.0m  (%s)" % [pair[0], from])
		else:
			var collider: Object = hit.get("collider")
			var node := collider as Node
			print("lane %-18s blocked at %.2fm by %s" % [
				pair[0], from.distance_to(hit["position"]),
				node.name if node != null else str(collider)])


func _stand(at: Vector3, yaw_deg: float, pitch_deg: float) -> void:
	player.global_position = at
	player.velocity = Vector3.ZERO
	player.rotation = Vector3(0.0, deg_to_rad(yaw_deg), 0.0)
	if look_pivot != null:
		look_pivot.rotation.x = deg_to_rad(pitch_deg)


func _light(expect: StringName) -> void:
	_press(&"light", expect)


## Any action rather than only the light chain. `request(&"light")` walks
## `moveset.light_chain` by combo index, so the only way to reach A3 直抛 is to have
## pressed twice inside the combo window - which makes a take about the THROW
## depend on the take before it. `&"chain_hook"` takes `hook_id` directly, so the
## wall bite can be staged on its own instead of hoping the combo was still warm.
func _press(action: StringName, expect: StringName) -> void:
	if not chain.request(action):
		notes.append("  !! %s refused (wanted %s)" % [String(action), String(expect)])
		return
	var played := _played_move()
	moves.append(String(played))
	# Ask about the technique that ACTUALLY played, so a take whose move and caption
	# already disagree does not also get to skip the sound check.
	_expect_cue = MOVE_CUE.get(played, &"")
	if played != expect:
		# The caption and the animation have to be the same claim - the renderer
		# learned this the hard way (combat_movie_renderer §_chain_req_expect).
		notes.append("  !! played %s but this take claims %s" % [String(played), String(expect)])
	else:
		print("    %s" % String(played))


func _played_move() -> StringName:
	var move := chain.active_move
	return move.id if move != null else &""


# ------------------------------------------------------------------- the design

func _table() -> Dictionary:
	var registry := audio.registry
	var groups := {}
	for group in registry.groups.keys():
		var list: Array = []
		for atom_id in registry.groups[group]:
			var atom: SoundAtom = registry.atom(atom_id)
			if atom == null or atom.stream == null:
				continue
			list.append({
				"id": String(atom.id),
				"path": atom.stream.resource_path,
				"base_gain_db": atom.base_gain_db,
				"pitch_min": atom.pitch_min,
				"pitch_max": atom.pitch_max,
			})
		groups[String(group)] = list
	var cues: Array = []
	for cue_id in audio.cues.keys():
		var cue: SfxCue = audio.cues[cue_id]
		var layers: Array = []
		for entry in cue.layers:
			var layer := entry as SfxLayer
			layers.append({
				"group": String(layer.group),
				"gain_db": layer.gain_db,
				"delay": layer.delay,
				"pitch": layer.pitch,
				"optional": layer.optional,
				"note": layer.note,
			})
		# In the order the table was built, so the dry sheet plays the same
		# sentence the table reads like.
		cues.append({
			"id": String(cue_id),
			"gain_db": cue.gain_db,
			"intent": cue.intent,
			"layers": layers,
		})
	return {"groups": groups, "cues": cues, "missing": registry.missing}


func _place_target(weight: StringName, distance: float) -> void:
	if lab == null:
		notes.append("  !! no ChainLab; a body hit cannot be staged")
		return
	_park_targets(weight)
	var target := lab.target_for(weight)
	if target == null:
		notes.append("  !! the lab has no %s target" % String(weight))
		return
	var forward := -player.global_transform.basis.z
	target.global_position = player.global_position + forward * distance
	target.global_position.y = 0.0
	target.rotation = Vector3.ZERO
	target.call("reset_dummy")
	target.set("attack_cooldown", 9999.0)


## The lab stands light / medium / heavy in one place on purpose - that is how the
## weight table is meant to be compared. For a take about ONE beat, the other two
## would each register as a hit and turn a single contact into a drum roll, so they
## are moved out of reach. Only the ones this beat is about move back.
func _park_targets(keep: StringName = &"") -> void:
	if lab == null:
		return
	for weight in [ElementLibrary.WEIGHT_LIGHT, ElementLibrary.WEIGHT_MEDIUM,
			ElementLibrary.WEIGHT_HEAVY]:
		if weight == keep:
			continue
		var node := lab.target_for(weight)
		if node != null:
			node.global_position = PARKED


func _equip_chain() -> void:
	var mgr := player.get_node_or_null("WeaponManager")
	if mgr != null and mgr.has_method("equip_weapon"):
		mgr.call("equip_weapon", &"chain")
	else:
		weapon.equip(&"chain")
	combat.finish_action()


func _fail(why: String) -> void:
	print("SEKAI_CHAIN_CAPTURE_BEGIN")
	print(JSON.stringify({"error": why, "events": [], "moves": [], "notes": [why]}))
	print("SEKAI_CHAIN_CAPTURE_END")
	quit()
