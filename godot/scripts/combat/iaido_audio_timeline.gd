extends Node
class_name IaidoAudioTimeline
# Iaido audio timeline.
#
# Every trigger point lives here, keyed off IaidoTuning. The current streams
# are synthesised placeholders (see godot/tools/generate_iaido_placeholders.py);
# replacing them with Suno renders does not change any timing below.
#
# Timeline intent:
#   0.00 music pause        0.20 air disappears     0.80 sheath movement
#   1.20 reverse waveform   2.20 deep pressure      2.85 lock click
#   2.97 instant slash      3.10 world tear         3.40 void resonance
#   4.25 glass stress       4.58 glass cracking     4.60 sword spin
#   5.50 sheath friction    6.20 FINAL CLICK        6.25 large collapse
#   6.80 reality restore    7.00+ music resume

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
	_add(&"air_suck", 0.20, "res://audio/sfx/iaido_air_suck.wav", -6.0, 1.0)
	_add(&"sheath_move", tuning.sheath_move_cue, "res://audio/sfx/iaido_sheath_move.wav", -11.0, 1.0)
	_add(&"reverse_wave", tuning.wave_start, "res://audio/sfx/iaido_reverse_wave.wav", -7.0, 1.0)
	_add(&"pressure", tuning.hold_start, "res://audio/sfx/iaido_pressure.wav", -5.0, 1.0)
	_add(&"lock_click", tuning.first_click, "res://audio/sfx/iaido_lock_click.wav", -4.0, 1.0)
	_add(&"draw", tuning.draw_start + 0.02, "res://audio/sfx/iaido_draw.wav", -3.0, 1.0)
	_add(&"world_cut", tuning.cut_start + 0.02, "res://audio/sfx/iaido_world_cut.wav", -3.0, 1.0)
	_add(&"void_open", tuning.cut_end, "res://audio/sfx/iaido_void_open.wav", -5.0, 1.0)
	_add(&"glass_stress", tuning.glass_start, "res://audio/sfx/iaido_glass_stress.wav", -8.0, 1.0)
	_add(&"glass_break", tuning.shard_burst, "res://audio/sfx/iaido_glass_break.wav", -6.0, 1.0)
	_add(&"spin", tuning.spin_start + 0.20, "res://audio/sfx/iaido_spin.wav", -9.0, 1.0)
	_add(&"slow_sheathe", tuning.slow_sheathe_start + 0.15, "res://audio/sfx/iaido_slow_sheathe.wav", -10.0, 1.0)
	_add(&"final_click", tuning.final_click, "res://audio/sfx/iaido_final_click.wav", -2.0, 1.0)
	# The real glass collapse belongs to the final click, not to the draw.
	_add(&"collapse", tuning.collapse_start + 0.05, "res://audio/sfx/iaido_glass_break.wav", -2.5, 0.78)
	_add(&"reality_restore", tuning.restore_start + 0.15, "res://audio/sfx/iaido_reality_restore.wav", -7.0, 1.0)


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
