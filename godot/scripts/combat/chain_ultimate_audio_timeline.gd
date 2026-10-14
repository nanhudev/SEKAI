extends Node
class_name ChainUltimateAudioTimeline
# 缚星链 I / ULTIMATE — the cue table for the nine beats, and the ONLY file in
# this ceremony that names a `.wav`.
#
# ---------------------------------------------------------------------------
# WHY THIS IS A SEPARATE FILE FROM THE DIRECTOR
# ---------------------------------------------------------------------------
#
# The combat line's rule, and it is not a style preference: `chain_ultimate_
# director.gd` emits EVENTS with names on them (`bite`, `cut`, `tear`, …) and
# never a file path. A director that knew a filename would be a director that
# cannot be re-voiced without editing combat code, and every cue time in the
# project would have two homes.
#
# So the director says WHAT HAPPENED and this file says WHAT IT SOUNDS LIKE.
#
# ---------------------------------------------------------------------------
# WHAT THE LAYERING IS DOING
# ---------------------------------------------------------------------------
#
# Every cue below is re-used from the two libraries that already exist — the
# chain's own metal (`audio/sfx/weapons/chain/`) and the iaido ceremony's world
# sounds (`audio/sfx/iaido/`). Nothing was generated for this pass, and that is
# deliberate: the brief asks for a LAYERED place-holder, and the honest way to
# prototype a weapon's ultimate is to prove the machine works with the vocabulary
# the project already has. The chain speaks metal; the world speaks iaido's
# reality layer; the two together are the whole point — 缚星链 does something to
# SPACE, and the space has already been given a voice.
#
# THE SILENCES ARE PART OF THE TABLE. There is one cue between 1.87 and 2.16 and
# there is nothing under PHASE 5 at all beyond a single low resonance. That gap
# is the effect: it is what makes the five strokes land as events rather than as
# a stream, and it is what the float exists for.
#
# ---------------------------------------------------------------------------
# THE TABLE IS ASKED FOR, NEVER COPIED
# ---------------------------------------------------------------------------
#
# `tools/dump_chain_ultimate_cues.gd` prints the live table and
# `tools/encode_chain_ultimate_movie.sh` consumes it. The iaido line learned this
# the expensive way: the encoder carried a hand-typed mirror that had drifted
# 0.36s, nothing failed, and the shipped movie's audio was a third of a second
# away from what the game plays.

const BUS_NAME := "ChainUltimate"

@export var tuning: ChainUltimateTuning

var players: Dictionary = {}
var cues: Array[Dictionary] = []
var fired: Dictionary = {}
var created_bus := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_bus()
	build()


func configure(next_tuning: ChainUltimateTuning) -> void:
	tuning = next_tuning
	if is_inside_tree():
		build()


## Drop everything and re-read the timeline. Public because the table depends on
## `tuning`, and a table built against the wrong tuning is a table that puts the
## whole mix at the wrong second.
func build() -> void:
	# Freed immediately rather than `queue_free`d: a deferred free would still be
	# in the tree while the new players are added, and every name would collide.
	for child in get_children():
		remove_child(child)
		child.free()
	players.clear()
	fired.clear()
	cues.clear()
	var t := tuning if tuning != null else ChainUltimateTuning.new()

	# ---- PHASE 0 · 起手 (0.00) -------------------------------------------
	# The world's own sound is being pulled out from under the shot. Quiet, and
	# it starts BEFORE anything has been thrown: the brief is explicit that
	# nothing has happened yet at 0.00-0.15.
	_add(&"charge", 0.00, "sfx/iaido/world_suck.wav", -11.0, 1.0)

	# ---- PHASE 1 · 前刺 (0.15-0.45) --------------------------------------
	# The head leaves the hand. A whoosh and the rope paying out behind it — the
	# same two-atom shape the chain uses for every throw, so this weapon does not
	# change its voice for the ultimate.
	_add(&"thrust", t.t_thrust_start + 0.01, "sfx/weapons/chain/metal_chain_whoosh_01_s1000.wav", -4.0, 1.0)
	_add(&"payout", t.t_thrust_start + 0.05, "sfx/weapons/chain/chain_payout_01_s1137.wav", -9.0, 1.0)

	# ---- PHASE 2 · 命中虚空锚点 (0.45-0.65) ------------------------------
	# THE BITE. Three things in the same frame, because they are one event: the
	# metal STOPS (heavy impact), the space is pierced (iaido's pressure thud,
	# which is the deepest sound the project has), and then the rope goes tight.
	# The stop and the pierce are 0.00 apart on purpose — a gap there would read
	# as the chain hitting two things.
	_add(&"bite_metal", t.t_bite, "sfx/weapons/chain/metal_chain_impact_heavy_01_s1000.wav", -6.0, 1.0)
	_add(&"bite_core", t.t_bite, "sfx/iaido/pressure_thud.wav", -4.5, 0.86)
	_add(&"bite_lock", t.t_bite + 0.09, "sfx/weapons/chain/chain_tension_lock_01_s1000.wav", -7.5, 1.0)

	# ---- PHASE 3 · 绕两圈, 越缠越紧 (0.65-1.25) ---------------------------
	# The two turns are a RITUAL, so they get a layer each rather than one loop:
	# the orbit at the start of the first turn, the rising tension under both, and
	# the tighten at the end of the second — which is the sound of the second turn
	# being the one at the limit.
	_add(&"coil_orbit", t.t_coil_start, "sfx/weapons/chain/chain_orbit_fast_01_s1137.wav", -10.0, 1.0)
	_add(&"coil_rise", t.t_coil_start + 0.06, "sfx/weapons/chain/chain_tension_rise_01_s1000.wav", -8.0, 1.0)
	_add(&"coil_tighten", t.t_pull_start - 0.14, "sfx/weapons/chain/metal_chain_tighten_01_s1000.wav", -6.0, 1.0)

	# ---- PHASE 4 · 世界被扯成一张膜 (1.25-1.85) --------------------------
	# THE HAUL. The yank is the heaviest atom the chain has; `reality_cut`
	# underneath it is the world being cut off its own surface, and it is pitched
	# DOWN (0.72) because it is not a blade cutting a body — it is a surface being
	# taken off. The drag then runs under the whole pull, so the haul is a
	# duration and not a single hit.
	_add(&"yank", t.t_pull_start, "sfx/weapons/chain/chain_yank_heavy_01_s1000.wav", -3.5, 1.0)
	_add(&"world_peel", t.t_pull_start + 0.04, "sfx/iaido/reality_cut.wav", -9.0, 0.72)
	_add(&"drag", t.t_pull_start + 0.16, "sfx/weapons/chain/metal_chain_slow_drag_01_s1137.wav", -9.5, 1.0)

	# ---- PHASE 5 · 漂浮停顿 (1.85-2.15) ----------------------------------
	# ONE sound, and it is the quietest thing in the table. The film has just come
	# free and the next thing that happens is five strokes; a busy float would
	# spend the attention the strokes need. This is the silence the brief asks for
	# with a single low resonance so it reads as held breath rather than as a bug.
	_add(&"float", t.t_float_start + 0.03, "sfx/iaido/void_open.wav", -14.0, 0.80)

	# ---- PHASE 6 · 高速斩碎 (2.15-2.85) ----------------------------------
	# FIVE STROKES, ONE VOICE EACH, AND THE LAST ONE IS THE HEAVY ONE. The first
	# stroke gets the reality cut again at full pitch — it is the moment the film
	# is first divided; the middle three get the link clink at rising gain, so the
	# rhythm is audible as a crescendo; the final one gets the heavy impact and
	# gets it 2dB hotter than the yank, because it is the strongest thing the
	# weapon does before the tear.
	for i in t.cuts.size():
		var at := t.cut_time(i)
		if i == 0:
			_add(&"cut_0_film", at, "sfx/iaido/reality_cut.wav", -7.0, 1.18)
		if i == t.cuts.size() - 1:
			_add(&"cut_last", at, "sfx/weapons/chain/metal_chain_impact_heavy_01_s1000.wav", -1.5, 0.94)
		else:
			_add(
				StringName("cut_%d_link" % i), at,
				"sfx/weapons/chain/metal_link_clink_01_s1000.wav",
				-8.0 + float(i) * 1.4, 1.0)

	# ---- PHASE 7 · 漫画撕裂 (2.85-3.20) ----------------------------------
	# The tear. The metal BREAKING is the headline and it is the only time this
	# file uses that atom, so the break means exactly one thing. Under it, the
	# glass detaching (the film's own pieces leaving) and the world collapse
	# pitched up slightly, because this is a bright climax and not the iaido
	# line's devouring one.
	_add(&"tear_metal", t.t_tear_start, "sfx/weapons/chain/metal_chain_break_01_s1000.wav", -3.0, 1.0)
	_add(&"tear_world", t.t_tear_start + 0.02, "sfx/iaido/reality_collapse.wav", -7.5, 1.14)
	_add(&"tear_snap", t.t_tear_start + 0.05, "sfx/weapons/chain/metal_chain_snap_release_01_s1137.wav", -5.5, 1.0)
	_add(&"tear_shards", t.t_tear_start + 0.10, "sfx/iaido/glass_detach.wav", -10.0, 1.10)

	# ---- PHASE 8 · 恢复世界 (3.20-3.55) ----------------------------------
	# The room coming back, and the chain reeling in. `reality_restore` is the
	# same atom the iaido ceremony closes on, which is the point: two ceremonies,
	# one world, one sound for it being put back.
	_add(&"restore_world", t.t_restore_start + 0.10, "sfx/iaido/reality_restore.wav", -8.0, 1.0)
	_add(&"restore_reel", t.t_restore_start + 0.06, "sfx/weapons/chain/chain_retract_heavy_01_s1137.wav", -10.0, 1.0)


func _ensure_bus() -> void:
	if AudioServer.get_bus_index(BUS_NAME) == -1:
		AudioServer.add_bus()
		AudioServer.set_bus_name(AudioServer.bus_count - 1, BUS_NAME)
		created_bus = true


func _add(
	cue_name: StringName, time: float, relative_path: String, volume_db: float, pitch: float
) -> void:
	if players.has(cue_name):
		return
	var path := "res://audio/" + relative_path
	var stream: AudioStream = load(path)
	if stream == null:
		push_warning("Chain ultimate cue missing: " + path)
		return
	var player := AudioStreamPlayer.new()
	player.name = "ChainUlt_" + String(cue_name)
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = pitch
	player.process_mode = Node.PROCESS_MODE_ALWAYS
	if AudioServer.get_bus_index(BUS_NAME) != -1:
		player.bus = BUS_NAME
	add_child(player)
	players[cue_name] = player
	cues.append({"name": cue_name, "time": time})


## Called every frame by whatever owns this ceremony, with the ceremony clock.
## Nothing here reads wall time: a cue is placed at a time IN THE TAKE.
func update(elapsed: float) -> void:
	for cue in cues:
		var cue_name: StringName = cue["name"]
		if fired.has(cue_name):
			continue
		if elapsed >= float(cue["time"]):
			fired[cue_name] = true
			var player := players.get(cue_name) as AudioStreamPlayer
			if player != null:
				player.play()


func stop_all() -> void:
	for cue_name in players:
		var player := players[cue_name] as AudioStreamPlayer
		if player != null and player.playing:
			player.stop()


func reset() -> void:
	fired.clear()
	stop_all()
