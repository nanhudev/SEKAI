extends Node
class_name IaidoAudioTimeline
# Short combat casts use the locally regenerated Feel V2 material bank.
# The preserved long demo retains its original timeline and source assets.
# Both profiles read their physical cue times from the active IaidoTuning.

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


var combat_tails := false
var tail_limits: Dictionary = {}

func configure(profile: IaidoTuning, short_cast: bool) -> void:
	stop_all()
	tuning = profile
	combat_tails = short_cast
	_build()
	tail_limits.clear()
	if short_cast:
		for i in cues.size():
			var next := float(cues[i + 1].time) if i + 1 < cues.size() else tuning.restore_end
			tail_limits[cues[i].name] = clampf(next - float(cues[i].time) + 0.08, 0.12, 0.40)
	reset()

func _build() -> void:
	cues.clear()
	if combat_tails and ResourceLoader.exists("res://audio/sfx/weapons/sword/feel_v2/draw.wav"):
		var bank := "res://audio/sfx/weapons/sword/feel_v2/"
		# Quiet preparation, cold steel, cut/pressure, friction, final seated click.
		_add(&"sheath_move",tuning.sheath_move_cue,bank+"sheath_slide.wav",-13,1)
		_add(&"lock_click",tuning.first_click,bank+"sheath_click.wav",-8,1.05)
		_add(&"draw",tuning.draw_start+0.02,bank+"draw.wav",-1,1)
		_add(&"world_cut",tuning.cut_start+0.02,bank+"iaido_cut.wav",0,1)
		_add(&"pressure",tuning.cut_start+0.045,bank+"iaido_pressure.wav",-8,1)
		_add(&"spin",tuning.spin_start+0.15,bank+"swing_a1.wav",-16,0.95)
		_add(&"slow_sheathe",tuning.slow_sheathe_start+0.15,bank+"sheath_slide.wav",-5,1)
		_add(&"final_click",tuning.final_click,bank+"sheath_click.wav",-1,0.95)
		cues.sort_custom(func(a:Dictionary,b:Dictionary): return float(a.time)<float(b.time))
		return
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
	cues.sort_custom(func(a: Dictionary,b: Dictionary): return float(a.time) < float(b.time))


func _add(cue_name: StringName, time: float, path: String, volume_db: float, pitch: float) -> void:
	var stream: AudioStream = load(path)
	if stream == null:
		push_warning("Iaido cue missing: " + path)
		return
	if players.has(cue_name):
		(players[cue_name] as AudioStreamPlayer).stream = stream
		(players[cue_name] as AudioStreamPlayer).volume_db = volume_db
		(players[cue_name] as AudioStreamPlayer).pitch_scale = pitch
		cues.append({"name": cue_name, "time": time, "volume_db":volume_db})
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
	cues.append({"name": cue_name, "time": time, "volume_db":volume_db})


func update(elapsed: float) -> void:
	for cue in cues:
		var cue_name: StringName = cue["name"]
		if fired.has(cue_name):
			if combat_tails:
				var end_time := float(cue.time) + float(tail_limits.get(cue_name,0.4))
				var fade := clampf((elapsed-(end_time-0.04))/0.04,0,1)
				(players[cue_name] as AudioStreamPlayer).volume_db = float(cue.volume_db)-30.0*fade
			if combat_tails and elapsed >= float(cue.time) + float(tail_limits.get(cue_name, 0.4)):
				(players[cue_name] as AudioStreamPlayer).stop()
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
