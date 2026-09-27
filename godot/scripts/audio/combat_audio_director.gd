extends Node
class_name CombatAudioDirector
## Wires the Universal Sword Layer to the sound language.
##
## The director does not know any style. It reads what the controller DID -
## which attack kind, which combo step, whether it connected, whether the guard
## was late or perfect - and asks the cue table for the matching stack of
## atoms. A new style changes timing and layering, not this file.
##
## Hook policy: everything here rides on signals and on public controller
## state. Nothing in the combat controller was edited to make audio work.

@export var controller_path: NodePath = ^"../Player/CombatController"
@export var hurtbox_path: NodePath = ^"../Player/Hurtbox"
@export var wind_hitbox_path: NodePath = ^"../Player/CameraRig/LookPivot/MotionPivot/ShakePivot/VFXRoot/WindHitbox"
## The old single-file dodge sound. Muted at runtime until MAIN removes it;
## see the INTEGRATION REQUEST in docs/AUDIO_STATUS.md.
@export var legacy_dodge_path: NodePath = ^"../Player/DodgeAudio"
@export var enabled := true
@export var log_cues := false

var registry: SoundAtomRegistry
var sfx: LayeredSFX
var cues: Dictionary = {}
var controller: CombatController

var last_cue_id: StringName = &""
var cue_log: Array[String] = []

var _wind_was_active := false
var _perfect_guard_fired := false
var _hurtbox: CombatHurtbox
var _wind_hitbox: Node


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	registry = SoundAtomRegistry.new()
	registry.name = "SoundAtomRegistry"
	add_child(registry)
	sfx = LayeredSFX.new()
	sfx.name = "LayeredSFX"
	add_child(sfx)
	sfx.registry = registry
	cues = CombatAudioCues.build()
	_resolve()
	_mute_legacy_dodge()


func _resolve() -> void:
	controller = get_node_or_null(controller_path) as CombatController
	if controller != null:
		# NOT `move_started`. That signal fires on the INPUT, and startup is not
		# dead air — it is the wind-up the player is watching. A whoosh released
		# 0.085s before the blade departs (0.185s on a charged heavy) is sound
		# describing an event that has not happened yet, and the ear believes the
		# sound: the sword feels late even though nothing is wrong with it.
		# `swing_started` is the departure itself.
		if controller.has_signal(&"swing_started"):
			controller.swing_started.connect(_on_move_started)
		else:
			push_warning("CombatAudioDirector: this CombatController has no swing_started; falling back to input time")
			controller.move_started.connect(_on_move_started)
		controller.hit_landed.connect(_on_hit_landed)
		controller.perfect_guard_landed.connect(_on_perfect_guard)
		controller.state_changed.connect(_on_state_changed)
	else:
		push_warning("CombatAudioDirector: no CombatController at %s" % String(controller_path))
	_hurtbox = get_node_or_null(hurtbox_path) as CombatHurtbox
	if _hurtbox != null:
		# Deferred: a perfect guard emits its own signal first, and by the time
		# this runs we know whether the hit was deflected or merely blocked.
		_hurtbox.hit_received.connect(_on_player_hit, CONNECT_DEFERRED)
	_wind_hitbox = get_node_or_null(wind_hitbox_path)


func _mute_legacy_dodge() -> void:
	var legacy := get_node_or_null(legacy_dodge_path)
	if legacy != null and "volume_db" in legacy:
		legacy.set("volume_db", -80.0)


# ------------------------------------------------------------------- events

func _on_move_started(_move: SwordMove) -> void:
	if not enabled or controller == null:
		return
	var kind := String(controller.attack_kind)
	match kind:
		&"heavy", &"skill", &"followup":
			_play(&"heavy_swing")
		&"riposte":
			# The answer out of a perfect guard is a short, sharp cut.
			_play(&"light_1")
		_:
			var index := clampi(controller.combo_index, 1, 3)
			_play(StringName("light_%d" % index))


func _on_hit_landed(_move: SwordMove, _hit: Dictionary) -> void:
	if not enabled or controller == null:
		return
	var kind := String(controller.attack_kind)
	# Whiffing already played the swing cue; contact adds the body layer. The
	# two must never be one baked file, or the sword stops reporting the world.
	if kind in [&"heavy", &"skill", &"followup"]:
		_play(&"hit_heavy")
	else:
		_play(&"hit_light")


func _on_perfect_guard() -> void:
	if not enabled:
		return
	_perfect_guard_fired = true
	_play(&"perfect_guard")


func _on_player_hit(_hit: Dictionary) -> void:
	if not enabled or controller == null:
		return
	if _perfect_guard_fired:
		_perfect_guard_fired = false
		return
	if controller.state == CombatController.State.BLOCK:
		_play(&"guard")


func _on_state_changed(_previous: int, current: int) -> void:
	if not enabled:
		return
	if current == CombatController.State.DODGE:
		_play(&"dodge")


func _process(_delta: float) -> void:
	if not enabled or _wind_hitbox == null:
		return
	# Wind has no signal of its own; the hitbox going live IS the event.
	var active := bool(_wind_hitbox.get("active"))
	if active and not _wind_was_active:
		_play(&"wind_burst")
	_wind_was_active = active


# -------------------------------------------------------------------- output

func _play(cue_id: StringName) -> void:
	var cue := cues.get(cue_id) as SfxCue
	if cue == null:
		push_warning("CombatAudioDirector: unknown cue '%s'" % String(cue_id))
		return
	last_cue_id = cue_id
	if log_cues:
		cue_log.append("%.2f %s" % [Time.get_ticks_msec() / 1000.0, String(cue_id)])
	sfx.play(cue)


## Fire a cue by id from anywhere (debug panel, scripted moments, magic).
func play_cue(cue_id: StringName) -> void:
	_play(cue_id)


func cue_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for key in cues.keys():
		ids.append(key)
	ids.sort()
	return ids
