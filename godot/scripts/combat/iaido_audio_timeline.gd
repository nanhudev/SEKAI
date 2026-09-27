extends Node
class_name IaidoAudioTimeline
# Iaido audio timeline.
#
# Every trigger point lives here, keyed off IaidoTuning. The current streams
# are synthesised placeholders (see godot/tools/generate_iaido_placeholders.py);
# replacing them with Suno renders does not change any timing below.
#
# Timeline intent (V3):
#   0.00 music pause        0.20 air disappears     0.85 sheath movement
#   1.35 reverse waveform   2.30 deep pressure      3.15 lock click
#   3.30 instant draw       3.40 world tear         3.78 void resonance
#   4.35 glass stress       4.90 sword spin         5.15 first panes detach
#   5.95 sheath friction    6.85 FINAL CLICK        6.95 large collapse
#   7.50 reality restore    7.85+ music resume
#
# Note where the noise is NOT: the 0.60s absolute hold (2.55 - 3.15) carries no
# cue at all. The silence is the effect.

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
	_add(&"glass_detach", tuning.shard_detach, "res://audio/sfx/iaido/glass_detach.wav", -11.0, 1.0)
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
