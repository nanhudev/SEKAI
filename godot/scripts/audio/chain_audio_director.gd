extends Node
class_name ChainAudioDirector
## The chain's voice. It listens; it never drives.
##
## ChainDirector owns the MOMENTS (§30: `chain_event`, `move_started`,
## `hit_landed`, `tug`). This node owns what they SOUND like. Nothing here can
## change how the weapon behaves - it has no way to reach into it - which is the
## property that lets the whole voice of the weapon be replaced without touching
## a line of combat code.
##
## WHERE THE TIMING COMES FROM, and this is the part that matters:
##
##   * an EVENT (contact, bite, tension, yank, retract, wall) is played the
##     instant it arrives. The weapon already placed it; re-timing it here would
##     be inventing a moment the state machine did not have.
##   * a PHASE BEAT (the swing whoosh, a slam's impact) cannot be an event, because
##     the weapon does not emit one at `startup` - the chain's "move_started" fires
##     at the INPUT (§30 says so out loud), and startup is not dead air: it is the
##     wind-up the player is watching. So phase beats are queued against the
##     chain's OWN clock (`state_time`) and fire when it crosses the authored time.
##     A wall-clock timer here would fire during hitstop and desync the sound from
##     the animation the player is watching - the exact bug the chain's windows
##     ride state_time to avoid.
##
## Hooked to a ChainDirector by NodePath, and by tree search when the path is
## empty, so a scene can host the weapon without also having to know about audio.

## Events kept for the debug readout (§PART K). Last few only - this is a HUD line,
## not a log file.
const EVENT_MEMORY := 5

@export var chain_path: NodePath = ^""
@export var player_path: NodePath = ^""
@export var enabled := true
@export var log_cues := false
## Idle is a noise floor (§4), so it is sparse ON PURPOSE. Two links clinking on a
## loop is the single fastest way to make a heavy weapon sound cheap.
@export var idle_interval_min := 2.4
@export var idle_interval_max := 4.8
@export var idle_enabled := true
@export var orbit_enabled := true
## A test may take the clock away, exactly as ChainDirector allows. With this on,
## `step()` is the only thing that advances the director and `_process` does
## nothing, so a capture is reproducible instead of being a function of how many
## frames this machine managed.
@export var manual_step := false
## Record and do not sound. Used by the offline mixer: the cue table and the beat
## timings are then the SAME code the game runs, instead of a transcription of it
## that can drift.
@export var capture_only := false

## `{"t": <director clock>, "cue": <id>}` in fire order. Only filled when
## `capture_only` is on.
var capture: Array[Dictionary] = []
var clock := 0.0

var registry: SoundAtomRegistry
var sfx: LayeredSFX
var cues: Dictionary = {}
var chain: ChainDirector

var last_cue_id: StringName = &""
var cue_log: Array[String] = []
var events: Array[String] = []

var _pending: Array[Dictionary] = []
var _timed: Array[Dictionary] = []
## Bumped on every `move_started`. A pending beat remembers the move INSTANCE it
## was queued for, so the only thing that can invalidate it is that move going
## away. Replaying the same id after a return to idle is a different instance, not
## the old beat finally arriving - which is why this is a counter and not the id.
var _move_serial := 0
var _prev_state_time := 0.0
var _prev_state := -1
var _idle_timer := 0.0
var _orbit_timer := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	# INJECTED WHEN POSSIBLE. This class works on its own, but in the game it is
	# handed the sword director's registry and voice pool: one atom table and one
	# pool for the whole weapon mix, which is the difference between extending the
	# audio system and starting a second one beside it (brief §K).
	if registry == null:
		registry = SoundAtomRegistry.new()
		registry.name = "ChainAtomRegistry"
		add_child(registry)
	if sfx == null:
		sfx = LayeredSFX.new()
		sfx.name = "ChainLayeredSFX"
		add_child(sfx)
	sfx.registry = registry
	cues = ChainAudioCues.build()
	_resolve()
	_idle_timer = _rng.randf_range(idle_interval_min, idle_interval_max)


func _resolve() -> void:
	if not chain_path.is_empty():
		chain = get_node_or_null(chain_path) as ChainDirector
	if chain == null:
		# A scene is allowed to host the weapon and not know that audio exists.
		chain = get_tree().root.find_child("ChainDirector", true, false) as ChainDirector
	if chain == null:
		# Not a warning: the sandbox hosts this node and the chain may simply not be
		# equipped in whatever scene loaded. Silence is the correct answer.
		set_process(false)
		return
	chain.move_started.connect(_on_move_started)
	chain.chain_event.connect(_on_chain_event)
	chain.hit_landed.connect(_on_hit_landed)
	_prev_state_time = chain.state_time


func _process(delta: float) -> void:
	if manual_step:
		return
	step(delta)


## One tick. Public so a capture tool can own the clock (see `manual_step`).
func step(delta: float) -> void:
	clock += delta
	if not enabled or chain == null:
		return
	if not chain.is_equipped():
		_pending.clear()
		_timed.clear()
		return
	# A new state began. `state_time` is the chain's own delta-accumulated clock, so
	# it going backwards means the previous beat is over.
	#
	# DO NOT CLEAR `_pending` HERE. `move_started` is emitted BEFORE this tick, so
	# the beat queued for the state that is just beginning - the technique's own
	# voice - is the very first thing a clear would throw away. That is every
	# `chain_a1_sweep`, `chain_a2_return`, `chain_a3_throw` and `chain_slam_swing`
	# there is, and because the event-driven cues (wall, bite, tension, hit) still
	# fired, a capture of the chain reported a healthy mix while the weapon had no
	# voice of its own at all. A beat is invalidated by ITS OWN move going away
	# (see `_fire_pending`), which is the property that actually matters.
	_prev_state_time = chain.state_time
	if chain.state != _prev_state:
		_prev_state = chain.state
		_orbit_timer = 0.0
	_fire_pending()
	_fire_timed()
	_tick_idle(delta)
	_tick_orbit(delta)


# ------------------------------------------------------------------- events

func _on_move_started(move: ChainMove) -> void:
	if not enabled or chain == null or move == null:
		return
	# New instance of a technique: everything still queued belongs to the previous
	# one and is now a lie, including a re-queued beat for the same move id.
	_move_serial += 1
	_note("MOVE %s" % String(move.id))
	var start := maxf(move.startup, 0.0)
	var active := move.active_seconds(chain.momentum)
	match move.id:
		# A1 左甩 - the wide heavy arc.
		&"ch_sweep":
			_queue(start, &"chain_a1_sweep", move.id)
		# A2 快右左 - ONE input, TWO arcs (§A2). The reversal is scheduled off the
		# move's own `arc_split` rather than baked into the cue, because how far
		# through the beat the turn happens is moveset data and moves when it moves.
		&"ch_return":
			_queue(start, &"chain_a2_return", move.id)
			var split := clampf(move.arc_split, 0.05, 0.95)
			_queue(start + active * split, &"chain_a2_reverse", move.id)
		# A3 直抛 and 缠锁 share the throw voice: one is aimed at a wall, one at a
		# body, and which it becomes is decided by the CONTACT, not by the input.
		&"ch_throw", &"ch_hook":
			_queue(start, &"chain_a3_throw", move.id)
		&"ch_launch":
			_queue(start, &"chain_launch", move.id)
		&"ch_snap":
			_queue(start, &"chain_snap_cut", move.id)
		&"ch_deflect":
			_queue(start, &"chain_deflect", move.id)
		&"ch_yank", &"ch_pull_cut":
			_queue(start, &"chain_swing_short", move.id)
		# A slam is two moments: the head falls, then it arrives. The second one is
		# at the END of the active phase, so it is queued there.
		&"ch_slam", &"ch_ground_slam":
			_queue(start, &"chain_slam_swing", move.id)
			_queue(start + active, &"chain_slam_impact", move.id)
		_:
			_queue(start, &"chain_swing_short", move.id)


func _on_chain_event(event: StringName, data: Dictionary) -> void:
	if not enabled or chain == null:
		return
	match event:
		# §13's FIRST beat. A damaging contact is announced through `hit_landed`
		# instead, so only the ARRIVAL of a hook is handled here - playing both
		# would double every enemy hit.
		&"CHAIN_CONTACT":
			# Type-tested rather than converted: `bool()` is the bool CONSTRUCTOR and it
			# rejects the `null` that `get()` returns when a key is absent. The `false`
			# default hides that today, and stops hiding it the moment a caller sends a
			# non-bool - which is a dictionary field, so nothing prevents one.
			var hooking: Variant = data.get("hooking", false)
			if hooking is bool and hooking:
				_note("CHAIN_CONTACT (head arrived)")
				_play(&"chain_hook_catch")
		# §13's THIRD beat, and it is not the same moment as the second.
		&"CHAIN_BITE":
			_note("CHAIN_BITE")
			_play(&"chain_bite")
		&"CHAIN_TENSION_START":
			_note("CHAIN_TENSION_START")
			_play(&"chain_tension_start")
		&"CHAIN_TENSION_FULL":
			_note("CHAIN_TENSION_FULL")
			_play(&"chain_tension_full")
		&"CHAIN_YANK":
			var amount := float(data.get("amount", 1.0))
			# `str()`, NOT `String()`. There is no `String(<Variant>)` constructor —
			# see `_on_hit_landed` for the measurement — so this line raised
			# "Nonexistent 'String' constructor" and ABORTED THE FUNCTION, one line
			# above the `_play` it exists to reach. The yank had no sound at all.
			_note("CHAIN_YANK %s" % str(data.get("step", "?")))
			_play(&"chain_yank_heavy" if amount >= 0.55 else &"chain_yank_light")
		&"CHAIN_RETRACT":
			var radius := float(data.get("radius", 0.0))
			var reach := float(chain.moveset.max_radius) if chain.moveset != null else 0.0
			_note("CHAIN_RETRACT %.2fm" % radius)
			_play(&"chain_retract_heavy" if reach > 0.0 and radius >= reach * 0.7
					else &"chain_retract_light")
		# §9's four beats: THROW (already played by move_started) - CONTACT - BITE -
		# TENSION. The wall only announces itself once, so the rest of the sentence
		# is placed here. Wall-clock timers are safe for these because a wall hit
		# asks for no hitstop (see chain_director._on_wall_hit).
		&"CHAIN_WALL":
			var strength := float(data.get("strength", 0.5))
			_note("CHAIN_WALL %.2f" % strength)
			_play(&"chain_wall_heavy" if strength >= 0.75 else &"chain_wall_light")
			_after(0.045, &"chain_bite")
			_after(0.130, &"chain_tension_start")
		&"CHAIN_RATTLE", &"CHAIN_THROW", &"CHAIN_SLAM":
			# Already covered by `move_started`, which additionally knows WHICH
			# technique it was. Playing these too is how a mix gets thick for no
			# reason: the same instant, described twice.
			pass


func _on_hit_landed(move: ChainMove, hit: Dictionary) -> void:
	if not enabled or chain == null:
		return
	var target: Node3D = hit.get("target")
	var weight := chain.weight_of(target)
	# `str()`, NOT `String()`. THIS ONE WAS SILENTLY KILLING EVERY IMPACT.
	#
	# `weight` is an `ElementLibrary.WEIGHT_*` enum, i.e. an int, and GDScript has no
	# `String(<Variant>)` constructor — `tools/_probe_string_ctor.gd` measured it:
	# `String(int)` is a parse error, and against a Variant it is a RUNTIME error. The
	# runtime error ABORTS `_on_hit_landed` at the `_note` line, so the `_play` on the
	# next line never ran and A1's enemy hit — the single most important beat in the
	# slice — had no sound. The matching bug was one branch up, on CHAIN_YANK.
	# `String(StringName)` (the `_play` and `_on_move_started` notes) is a real
	# constructor and is left alone.
	_note("HIT %s" % str(weight))
	_play(&"chain_hit_body_heavy" if weight == ElementLibrary.WEIGHT_HEAVY
			else &"chain_hit_body")


# ------------------------------------------------------------- idle / orbit

func _tick_idle(delta: float) -> void:
	if not idle_enabled or chain.state != ChainDirector.State.HELD:
		return
	_idle_timer -= delta
	if _idle_timer > 0.0:
		return
	_idle_timer = _rng.randf_range(idle_interval_min, idle_interval_max)
	var player: Node3D = chain.get_parent() as Node3D
	var moving := false
	if player is CharacterBody3D:
		moving = (player as CharacterBody3D).velocity.length() > 0.6
	# Moving gets a slightly busier settle; standing still gets almost nothing.
	_play(&"chain_idle_shift" if moving else &"chain_idle")


func _tick_orbit(delta: float) -> void:
	# The whirling chain is a continuous sound made of one-shots, re-fired rather
	# than looped: a loop would need its own player, its own fade and its own
	# release, and the cue pool already solves all three.
	if not orbit_enabled or chain.state != ChainDirector.State.ORBITING:
		return
	_orbit_timer -= delta
	if _orbit_timer > 0.0:
		return
	_orbit_timer = 0.78
	_play(&"chain_orbit")


# ------------------------------------------------------------------- output

## A beat that must ride the chain's clock. `at` is in seconds of `state_time`.
func _queue(at: float, cue_id: StringName, move_id: StringName) -> void:
	if at <= 0.0:
		_play(cue_id)
		return
	_pending.append({"at": at, "cue": cue_id, "move": move_id, "serial": _move_serial})


func _fire_pending() -> void:
	if _pending.is_empty():
		return
	var active := chain.active_move
	var active_id: StringName = active.id if active != null else &""
	var kept: Array[Dictionary] = []
	for beat in _pending:
		# A beat queued for an instance of the technique that is no longer playing
		# is not late, it is wrong - a 0.6s swing cancelled at 0.3s must not fire its
		# impact, and neither may a beat left over from the previous swing.
		if int(beat["serial"]) != _move_serial or beat["move"] != active_id:
			continue
		if chain.state_time >= float(beat["at"]):
			_play(beat["cue"])
		else:
			kept.append(beat)
	_pending = kept


## An event-driven follow-up a few tens of milliseconds later. Used only where the
## weapon emits one event for a multi-beat moment (the wall) and no hitstop runs
## in between, so a wall-clock offset cannot drift away from the animation.
func _after(delay: float, cue_id: StringName) -> void:
	if manual_step:
		_timed.append({"at": clock + delay, "cue": cue_id})
		return
	var timer := get_tree().create_timer(delay, true, false, true)
	timer.timeout.connect(func() -> void:
		if is_instance_valid(self) and enabled:
			_play(cue_id)
	)


func _fire_timed() -> void:
	if _timed.is_empty():
		return
	var kept: Array[Dictionary] = []
	for beat in _timed:
		if clock >= float(beat["at"]):
			_play(beat["cue"])
		else:
			kept.append(beat)
	_timed = kept


func _play(cue_id: StringName) -> void:
	var cue := cues.get(cue_id) as SfxCue
	if cue == null:
		push_warning("ChainAudioDirector: unknown cue '%s'" % String(cue_id))
		return
	last_cue_id = cue_id
	if capture_only:
		capture.append({"t": clock, "cue": String(cue_id)})
		return
	if log_cues:
		cue_log.append("%.2f %s" % [clock, String(cue_id)])
	sfx.play(cue)


func _note(text: String) -> void:
	events.append("%.2f %s" % [Time.get_ticks_msec() / 1000.0, text])
	while events.size() > EVENT_MEMORY:
		events.pop_front()


## §PART K / §29. What the training ground draws and the developer panel can solo.
func event_lines() -> Array[String]:
	return events.duplicate()


func play_cue(cue_id: StringName) -> void:
	_play(cue_id)


func cue_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for key in cues.keys():
		ids.append(key)
	ids.sort()
	return ids
