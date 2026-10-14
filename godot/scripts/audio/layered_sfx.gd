extends Node
class_name LayeredSFX
## Plays a cue definition as a vertical stack of atoms.
##
## One cue in, N atoms out, each with its own gain, pitch and entry offset. No
## gameplay script builds its own AudioStreamPlayer stack, which is what stops
## every new skill from inventing a new audio shape.
##
## Voices are pooled: combat fires cues faster than any of them lasts, and
## allocating a player per layer per hit is how you get audio hitching.

const MAX_VOICES := 24
## PART M. Contacts are a separate, smaller pool: a contact is a POINT in the
## world, so it cannot reuse the player-layer players, and letting one family
## starve the other is how a busy fight goes silent on the half that matters more.
const MAX_SPATIAL_VOICES := 12

@export var bus: StringName = &"SFX"
## Where the CONTACT LAYER lives. Set by the director to the world the player is
## in, because this node is a plain Node and a plain Node has no position - an
## AudioStreamPlayer3D parented to it would sit at the origin and every contact
## would come from the middle of the map.
@export var spatial_parent: Node

var registry: SoundAtomRegistry
## Debug / test mirror of the last cue that was played.
var last_cue_id: StringName = &""
var last_layers: Array[Dictionary] = []
var played_cues := 0

var _players: Array[AudioStreamPlayer] = []
var _spatial_players: Array[AudioStreamPlayer3D] = []
var _started_msec: Dictionary = {}
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	process_mode = Node.PROCESS_MODE_ALWAYS
	if registry == null:
		registry = SoundAtomRegistry.new()
		registry.name = "AutoRegistry"
		add_child(registry)


## Returns the layers that actually sounded, so a test (or a tuning pass) can
## assert on the shape of the mix instead of on whether "a sound happened".
##
## `at` is only read when the cue is a CONTACT cue (`cue.spatial`). Pass it from
## the hit itself: the blurb is "the hit landed THERE", and a contact played at the
## origin is a lie the ear catches immediately in first person.
func play(cue: SfxCue, at := Vector3.ZERO, has_at := false) -> Array[Dictionary]:
	last_cue_id = cue.id
	last_layers.clear()
	played_cues += 1
	var spatial := cue.spatial and has_at and _can_spatial()
	for entry in cue.layers:
		var layer := entry as SfxLayer
		var played := _play_layer(cue, layer, spatial, at)
		if not played.is_empty():
			last_layers.append(played)
	return last_layers


func _can_spatial() -> bool:
	return spatial_parent != null and spatial_parent is Node3D and spatial_parent.is_inside_tree()


func _play_layer(cue: SfxCue, layer: SfxLayer, spatial: bool, at: Vector3) -> Dictionary:
	if registry == null or not registry.has_group(layer.group):
		if not layer.optional:
			push_warning("LayeredSFX: group '%s' has no atoms (cue '%s')" % [String(layer.group), String(cue.id)])
		return {}
	var atom := registry.pick(layer.group, _rng)
	if atom == null or atom.stream == null:
		return {}
	var gain := atom.base_gain_db + layer.gain_db + cue.gain_db
	if layer.gain_jitter > 0.0:
		gain += _rng.randf_range(-layer.gain_jitter, layer.gain_jitter)
	var pitch := layer.pitch * atom.pitch_random(_rng)
	if layer.pitch_jitter > 0.0:
		pitch += _rng.randf_range(-layer.pitch_jitter, layer.pitch_jitter)
	var entry := {
		"group": layer.group,
		"atom": atom.id,
		"gain_db": gain,
		"pitch": pitch,
		"delay": layer.delay,
		"spatial": spatial,
	}
	if layer.delay <= 0.0:
		_voice(atom, gain, pitch, cue.bus, spatial, at)
	else:
		_schedule(atom, gain, pitch, cue.bus, layer.delay, spatial, at)
	return entry


func _schedule(atom: SoundAtom, gain: float, pitch: float, bus_name: StringName,
		delay: float, spatial := false, at := Vector3.ZERO) -> void:
	# ignore_time_scale: hitstop must not smear a 40ms offset into a smear.
	var timer := get_tree().create_timer(delay, true, false, true)
	timer.timeout.connect(func() -> void:
		if is_instance_valid(self):
			_voice(atom, gain, pitch, bus_name, spatial, at)
	)


func _voice(atom: SoundAtom, gain: float, pitch: float, bus_name: StringName,
		spatial := false, at := Vector3.ZERO) -> void:
	var resolved := bus_name if AudioServer.get_bus_index(bus_name) != -1 else bus
	# ignore_time_scale on every voice: hitstop freezes the WORLD, and a contact
	# that also freezes stops being a contact.
	if spatial:
		var spatial_player := _take_spatial_player()
		spatial_player.stream = atom.stream
		spatial_player.volume_db = gain
		spatial_player.pitch_scale = pitch
		spatial_player.bus = resolved
		(spatial_player as Node3D).global_position = at
		spatial_player.play()
		_started_msec[spatial_player] = Time.get_ticks_msec()
		return
	var player := _take_player()
	player.stream = atom.stream
	player.volume_db = gain
	player.pitch_scale = pitch
	player.bus = resolved
	player.play()
	_started_msec[player] = Time.get_ticks_msec()


func _take_player() -> AudioStreamPlayer:
	for player in _players:
		if not player.playing:
			return player
	if _players.size() < MAX_VOICES:
		var created := AudioStreamPlayer.new()
		created.name = "Voice%d" % _players.size()
		created.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(created)
		_players.append(created)
		_started_msec[created] = Time.get_ticks_msec()
		return created
	# All voices busy: steal the oldest. Dropping the newest would cut the
	# transient the player is supposed to hear right now.
	var oldest: AudioStreamPlayer = _players[0]
	var oldest_msec := Time.get_ticks_msec()
	for player in _players:
		var started := int(_started_msec.get(player, 0))
		if started < oldest_msec:
			oldest_msec = started
			oldest = player
	oldest.stop()
	return oldest


func stop_all() -> void:
	for player in _players:
		player.stop()
	for player in _spatial_players:
		player.stop()


## Same steal-the-oldest rule as the player layer. A dropped NEWEST voice would
## cut the transient the player is supposed to hear right now.
func _take_spatial_player() -> AudioStreamPlayer3D:
	for player in _spatial_players:
		if not player.playing:
			return player
	if _spatial_players.size() < MAX_SPATIAL_VOICES:
		var created := AudioStreamPlayer3D.new()
		created.name = "SpatialVoice%d" % _spatial_players.size()
		created.process_mode = Node.PROCESS_MODE_ALWAYS
		# A contact is a nearby event, not a gunshot across a valley: the falloff
		# has to make a blade landing on a crate at 3 m still read as a contact.
		created.unit_size = 6.0
		created.max_distance = 42.0
		created.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		# AIR ABSORPTION IS THE MATERIAL, SO IT CANNOT EAT IT. Godot defaults these two
		# to a 5 kHz cutoff at -24 dB and applies them with distance, and on the contact
		# voices that was throwing away the one band the material layer exists to carry.
		# Measured on `sword_contact_stone @ahead pass 1`, same four layers, same span,
		# same window: a faithful offline rebuild puts 27.8% of the cue between 2-6.5 kHz
		# and 10.1% above 6.5 kHz; the recorded take had 5.6% and 2.9%. The table was not
		# wrong - the PLAYBACK was filtering it away, by an amount that also grew with
		# distance, which is why one material read differently at 3 m and at 8 m.
		# Keep a gentler version: distance still dulls a hit, it no longer removes it.
		created.attenuation_filter_cutoff_hz = 16000.0
		created.attenuation_filter_db = -6.0
		spatial_parent.add_child(created)
		_spatial_players.append(created)
		_started_msec[created] = Time.get_ticks_msec()
		return created
	var oldest: AudioStreamPlayer3D = _spatial_players[0]
	var oldest_msec := Time.get_ticks_msec()
	for player in _spatial_players:
		var started := int(_started_msec.get(player, 0))
		if started < oldest_msec:
			oldest_msec = started
			oldest = player
	oldest.stop()
	return oldest
