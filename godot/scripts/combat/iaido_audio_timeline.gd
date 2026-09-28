extends Node
class_name IaidoAudioTimeline
# Iaido audio timeline.
#
# Every trigger point lives here, keyed off IaidoTuning. The current streams
# are synthesised placeholders (see godot/tools/generate_iaido_placeholders.py);
# replacing them with Suno renders does not change any timing below.
#
# Timeline intent (V6, 9.90s total). Every time below is READ OFF IaidoTuning —
# this list is a description, not a table, and the numbers are the values at the
# time of writing. `godot/tools/dump_iaido_cues.gd` prints the live table that
# `encode_iaido_movie.sh` mixes from, which is the only reason a stale copy of it
# cannot desync the movie any more.
#
#   0.20  air disappears          0.52  sheath movement       1.06  reverse waveform
#   2.14  deep pressure           3.68  lock click (first)    4.70  instant draw
#   4.78  glass stress            4.80  world cut             4.90  first panes detach
#   5.30  void resonance          6.45  spin                  7.45  sheath friction
#   8.40  FINAL CLICK             8.70  large collapse        9.30  reality restore
#
# Note where the noise is NOT. The dead windows — 3.24-3.58 (the grey and the
# stop) and 3.68-4.68 (the full second with the blade already home) — carry NO
# cue after the click that opens the second one. Nor is there any music under the
# two seconds of charging. Those silences are the effect: they are what makes the
# 100ms draw read as instantaneous against them.

const BUS_NAME := "Iaido"

@export var tuning: IaidoTuning = preload("res://resources/tuning/IaidoTuning.tres")

var players: Dictionary = {}
var cues: Array[Dictionary] = []
var fired: Dictionary = {}
var created_bus := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_bus()
	_build()


func _ensure_bus() -> void:
	if AudioServer.get_bus_index(BUS_NAME) == -1:
		AudioServer.add_bus()
		AudioServer.set_bus_name(AudioServer.bus_count - 1, BUS_NAME)
		created_bus = true


func _build() -> void:
	cues.clear()
	# Suno-rendered cues (audio_source/suno/raw -> build_iaido_cues.py).
	# Relative hierarchy lives in volume_db; baked peaks sit at -3..-8 dBFS.
	_add(&"air_suck", 0.20, "res://audio/sfx/iaido/world_suck.wav", -6.0, 1.0)
	_add(&"sheath_move", tuning.sheath_move_cue, "res://audio/sfx/iaido/sheath_move.wav", -11.0, 1.0)
	_add(&"reverse_wave", tuning.wave_start, "res://audio/sfx/iaido/reverse_compression.wav", -7.0, 1.0)
	_add(&"pressure", tuning.suck_start, "res://audio/sfx/iaido/pressure_thud.wav", -5.0, 1.0)
	# Signature click pair: the prepare click is brighter, the final click is
	# the same identity pitched down with more body - one sword language.
	_add(&"lock_click", tuning.first_click, "res://audio/sfx/iaido/sheath_lock.wav", -4.0, 1.1)
	_add(&"draw", tuning.draw_start + 0.02, "res://audio/sfx/iaido/draw.wav", -3.0, 1.0)
	_add(&"world_cut", tuning.cut_start + 0.02, "res://audio/sfx/iaido/reality_cut.wav", -3.0, 1.0)
	_add(&"void_open", tuning.cut_end, "res://audio/sfx/iaido/void_open.wav", -5.0, 1.0)
	_add(&"glass_stress", tuning.glass_start, "res://audio/sfx/iaido/glass_stress.wav", -8.0, 1.0)
	# The first panes coming loose is a small break. The world collapsing is the
	# big one, and it belongs to the final click, not to the draw.
	_add(&"glass_detach", tuning.loosen_start, "res://audio/sfx/iaido/glass_detach.wav", -11.0, 1.0)
	_add(&"spin", tuning.spin_start + 0.15, "res://audio/sfx/iaido/spin.wav", -9.0, 1.0)
	_add(&"slow_sheathe", tuning.slow_sheathe_start + 0.15, "res://audio/sfx/iaido/slow_sheathe.wav", -10.0, 1.0)
	_add(&"final_click", tuning.final_click, "res://audio/sfx/iaido/final_sheathe.wav", -2.0, 0.92)
	# The real glass collapse belongs to the final click, not to the draw.
	_add(&"collapse", tuning.collapse_start + 0.05, "res://audio/sfx/iaido/reality_collapse.wav", -2.5, 1.0)
	_add(&"reality_restore", tuning.restore_start + 0.15, "res://audio/sfx/iaido/reality_restore.wav", -7.0, 1.0)


func _add(cue_name: StringName, time: float, path: String, volume_db: float, pitch: float) -> void:
	if players.has(cue_name):
		return
	var stream: AudioStream = load(path)
	if stream == null:
		push_warning("Iaido cue missing: " + path)
		return
	var player := AudioStreamPlayer.new()
	player.name = "Iaido_" + String(cue_name)
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = pitch
	player.process_mode = Node.PROCESS_MODE_ALWAYS
	if AudioServer.get_bus_index(BUS_NAME) != -1:
		player.bus = BUS_NAME
	add_child(player)
	players[cue_name] = player
	cues.append({"name": cue_name, "time": time})


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


func seek(elapsed: float) -> void:
	# Scrubbing should not spray every passed cue at once; only arm the future.
	fired.clear()
	for cue in cues:
		if elapsed >= float(cue["time"]):
			fired[cue["name"]] = true


func _exit_tree() -> void:
	stop_all()
	if created_bus:
		var index := AudioServer.get_bus_index(BUS_NAME)
		if index > 0:
			AudioServer.remove_bus(index)
