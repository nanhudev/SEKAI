extends Node
class_name CombatAudioDirector
## Wires the Universal Sword Layer to the sound language.
##
## The director does not know any STYLE and it does not know any FILE. It reads
## what the controller DID - which attack kind, which combo step, whether it
## connected, what it connected WITH, whether the guard was late or perfect - and
## asks the cue table for the matching stack of atoms. A new style changes timing
## and layering, not this file.
##
## Hook policy: everything here rides on signals and on public controller state.
## Nothing in the combat controller was edited to make audio work. The one place
## this file has to reach INTO the game is the target of a hit, and it does that
## by duck-typing (`surface`, `is_frozen`) rather than by asking combat to carry a
## field for audio's benefit.
##
## PART L, in one sentence: gameplay says WHAT HAPPENED, audio decides WHAT IT
## SOUNDS LIKE - `play_event(&"sword_contact", 0.8, &"stone")`, never a wav path.

@export var controller_path: NodePath = ^"../Player/CombatController"
@export var hurtbox_path: NodePath = ^"../Player/Hurtbox"
@export var wind_hitbox_path: NodePath = ^"../Player/CameraRig/LookPivot/MotionPivot/ShakePivot/VFXRoot/WindHitbox"
## The old single-file dodge sound. Muted at runtime until MAIN removes it;
## see the INTEGRATION REQUEST in docs/AUDIO_STATUS.md.
@export var legacy_dodge_path: NodePath = ^"../Player/DodgeAudio"
## The chain is a second weapon with its own vocabulary, so it gets its own
## director instead of a growing `if kind == CHAIN` branch in here. It is SPAWNED
## from this node rather than added to a scene file because this node is already
## the audio line's presence wherever a world loads - which means a new weapon can
## be given a voice without any other line's scene being edited to make room for
## it. The registry and the voice pool are passed down, not re-created: one atom
## table, one pool (brief §K).
@export var spawn_chain_director := true
@export var enabled := true
@export var log_cues := false
## PART 18. Off by default: the labels are for the person tuning the mix, and a
## frame anyone watches is rendered with them off.
@export var show_debug_overlay := false

## The event vocabulary. Gameplay asks for one of these (or for `sword_contact`,
## which is resolved through the material table) and never names a cue or a file.
const EVENTS: Dictionary = {
	&"SWORD_LIGHT_1": &"sword_light_1",
	&"SWORD_LIGHT_2": &"sword_light_2",
	&"SWORD_LIGHT_3": &"sword_light_3",
	&"SWORD_LIGHT_SWING": &"sword_light_1",
	&"SWORD_HEAVY_WINDUP": &"sword_heavy_windup",
	&"SWORD_HEAVY_RELEASE": &"sword_heavy_release",
	&"SWORD_BLOCK": &"sword_block",
	&"SWORD_PERFECT_GUARD": &"sword_perfect_guard",
	&"SWORD_RIPOSTE": &"sword_riposte",
	&"SWORD_SHATTER": &"sword_shatter",
	&"SWORD_DODGE": &"sword_dodge",
	&"WIND_BURST": &"wind_burst",
	# The basic sentence (§25). Its four beats declare their own identities and
	# then name their own instants, so none of these is a combo step.
	&"SWORD_SAYA_TOUCH": &"sword_saya_touch",
	&"SWORD_IAIDO_DRAW": &"sword_iaido_draw",
	&"SWORD_WAVE_CUT": &"sword_wave_cut",
	&"SWORD_SPACE_CUT_1": &"sword_space_cut_1",
	&"SWORD_SPACE_CUT_2": &"sword_space_cut_2",
	&"SWORD_SPACE_CUT_3": &"sword_space_cut_3",
	&"SWORD_ARC_WIDE": &"sword_arc_wide",
}
## Surfaces an actor can declare. The value is a GROUP name because a target that
## has no script at all (a crate, a rock) must still be able to say what it is.
const SURFACE_GROUPS: Dictionary = {
	&"surface_body": &"flesh",
	&"surface_stone": &"stone",
	&"surface_metal": &"metal",
	&"surface_wood": &"wood",
	&"surface_ice": &"ice",
}
## How many fired cues the debug overlay remembers.
const HISTORY_MAX := 8
## The poise a hit needs before a frozen body BREAKS rather than merely takes extra
## damage. It is the world's number, not audio's: `technical_dummy.gd` calls a hit
## "shatter" at `poise_damage >= 35.0`, and the blade must never announce a shatter
## the body decided not to do.
##
## Duplicated as a constant only because of WHERE the question can be asked:
## `combat_controller._on_hitbox_landed` emits `hit_landed` BEFORE the target has
## resolved the hit (the body's own verdict, `take_hit_outcome()`, is read one line
## later), so at the moment the sound is chosen there is no verdict to read.
const SHATTER_POISE := 35.0

var registry: SoundAtomRegistry
var sfx: LayeredSFX
var cues: Dictionary = {}
var controller: CombatController

var last_cue_id: StringName = &""
var cue_log: Array[String] = []
## PART 18 mirror, in fire order, newest last. Bounded so a long session cannot
## grow it forever.
var history: Array[Dictionary] = []
## Fire order, monotonic. A take has to be able to say "the cue I am waiting for has
## not happened YET", and the bounded history above cannot answer that: once it is
## eight entries long `history.size()` stops moving, so every later beat would be
## checked against whatever still happens to be in the window - a stale match that
## reads exactly like a pass.
var cue_seq := 0
## Set when `spawn_chain_director` is on. Kept as a typed member so the developer
## panel and tests can reach the chain's cue list without a tree search.
var chain_audio: ChainAudioDirector

var _wind_was_active := false
var _perfect_guard_fired := false
var _hurtbox: CombatHurtbox
var _wind_hitbox: Node
var _overlay: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	registry = SoundAtomRegistry.new()
	registry.name = "SoundAtomRegistry"
	add_child(registry)
	sfx = LayeredSFX.new()
	sfx.name = "LayeredSFX"
	add_child(sfx)
	sfx.registry = registry
	# PART M. The contact layer is a point in the world, so the pool that plays it
	# has to live in the world. This node is a plain Node on purpose (it must
	# survive a scene that has no Node3D root).
	sfx.spatial_parent = _find_spatial_parent()
	cues = CombatAudioCues.build()
	_resolve()
	_mute_legacy_dodge()
	_spawn_chain_audio()


func _find_spatial_parent() -> Node:
	var node: Node = self
	while node != null:
		if node is Node3D:
			return node
		node = node.get_parent()
	return get_tree().current_scene if is_inside_tree() else null


func _spawn_chain_audio() -> void:
	if not spawn_chain_director:
		return
	chain_audio = ChainAudioDirector.new()
	chain_audio.name = "ChainAudioDirector"
	# Shared, so a chain cue and a sword cue draw voices from the same pool and sit
	# on the same atom table. A separate pool would also swallow a separate
	# MAX_VOICES budget and let the two weapons fight over the mix in the dark.
	chain_audio.registry = registry
	chain_audio.sfx = sfx
	chain_audio.log_cues = log_cues
	add_child(chain_audio)


func _resolve() -> void:
	controller = get_node_or_null(controller_path) as CombatController
	if controller != null:
		# `move_started` is the INPUT being accepted and `swing_started` is the
		# blade DEPARTING. Both are needed and they are not the same beat:
		#   * a wind-up belongs on the input - it is the body coiling, and it has to
		#     be heard BEFORE the blade moves or the heavy has no anticipation;
		#   * a cut belongs on the departure - a whoosh released 0.085s before the
		#     blade moves (0.185s on a charged heavy) describes an event that has
		#     not happened, and the ear believes the sound, so the sword feels late.
		if controller.has_signal(&"move_started"):
			controller.move_started.connect(_on_move_started)
		if controller.has_signal(&"swing_started"):
			controller.swing_started.connect(_on_swing_started)
		else:
			push_warning("CombatAudioDirector: this CombatController has no swing_started; falling back to input time")
			controller.move_started.connect(_on_swing_started)
		controller.hit_landed.connect(_on_hit_landed)
		controller.perfect_guard_landed.connect(_on_perfect_guard)
		controller.state_changed.connect(_on_state_changed)
		var manager := controller.player.get_node_or_null("WeaponManager")
		if manager != null:
			manager.sword_sheathe_started.connect(func(): _play(&"sword_saya_slide"))
			manager.sword_seated.connect(func(): _play(&"sword_saya_click"))
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

## THE ENTRY POINT (PART L). Anything - a spell, a scripted moment, a debug panel,
## a future enemy - says what happened and this decides what it sounds like.
##
## `intensity` is 0..1+ and only means "how hard". `material` is read by the
## contact family. `at` is only read by cues that are spatial.
func play_event(event: StringName, intensity := 0.5, material: StringName = &"",
		at := Vector3.ZERO, has_at := false) -> void:
	if not enabled:
		return
	# Contact is the one event whose cue is chosen by the WORLD rather than by the
	# table, so it is resolved before the table lookup instead of being a key.
	if event == &"SWORD_CONTACT":
		var surface := material if material != &"" else &"flesh"
		var cue_id: StringName = CombatAudioCues.MATERIAL_CUE.get(surface, &"sword_contact_body")
		_play(cue_id, intensity, at, has_at)
		# "What it hit" and "how hard it hit" are two independent decisions: the
		# accent is added on top of the material layer, never instead of it.
		if intensity >= 0.75:
			_play(&"sword_hit_weight", intensity, at, has_at)
		return
	var mapped: StringName = EVENTS.get(event, &"")
	if mapped == &"":
		push_warning("CombatAudioDirector: unknown audio event '%s'" % String(event))
		return
	_play(mapped, intensity, at, has_at)


func _on_move_started(_move: SwordMove) -> void:
	if not enabled or controller == null:
		return
	# ONLY the heavy family has a wind-up worth hearing. Firing one on a light
	# input would put a cloth-and-pressure beat in front of every quick cut.
	#
	# AND THE HEAVY IS NOT FIRED FROM HERE. The controller enters CHARGE on the
	# input and does NOT call `_begin_move` to do it - so `move_started` for a
	# heavy is emitted by `release_heavy()`, i.e. on the way OUT. Playing the
	# wind-up from here put cloth, grip and rising pressure UNDER the release they
	# exist to precede, which is the one contrast PART B is about. The charge's own
	# state change is the honest hook: see `_on_state_changed`.
	if String(controller.attack_kind) == "skill":
		_play(&"sword_heavy_windup")


func _on_swing_started(_move: SwordMove) -> void:
	if not enabled or controller == null:
		return
	match String(controller.attack_kind):
		"heavy", "skill", "followup":
			_play(&"sword_heavy_release")
		"riposte":
			# The answer out of a perfect guard is its own event, not "light_1".
			# It is the advantage being spent, and it must sound like it.
			_play(&"sword_riposte")
		"signature":
			# The signature has its own timeline (IaidoDirector). Silence here is
			# deliberate: two systems describing one moment is one too many.
			pass
		_:
			# A MOVE MAY SPEAK FOR ITSELF. The basic sentence's four beats are told
			# apart by distance and the saya, not by a combo step, so they declare
			# their own voice on the move. The generic ladder stays for every other
			# style, which is exactly what keeps `sword_light_1/2/3` meaning the
			# same thing for 一文字 and 回风 as it always did.
			var own := _own_cue(_move)
			if own != &"":
				# A named move event already supplies this exact voice. One departure
				# has one sound, even when both swing and event occur in this frame.
				if controller.sword_vfx != null and controller.sword_vfx.is_inside_tree():
					for event in _move.events:
						var spoken := SwordBasic.audio_for_event(event.get("id", &""))
						if EVENTS.get(spoken, &"") == own:
							return
				_play(own)
				return
			var index := clampi(controller.combo_index, 1, 3)
			_play(StringName("sword_light_%d" % index))


## The cue a move declares for itself, or &"" when it has none. Read through a
## duck-typed check rather than a hard cast so a caller from a line that predates
## this contract cannot crash the audio system.
func _own_cue(move: SwordMove) -> StringName:
	if move == null:
		return &""
	return move.audio_cue


func _on_hit_landed(_move: SwordMove, hit: Dictionary) -> void:
	if not enabled or controller == null:
		return
	var target: Node = hit.get("target") as Node
	var at := Vector3.ZERO
	var has_at := false
	if target is Node3D:
		# The target's own position IS the direction the contact came from.
		at = (target as Node3D).global_position
		has_at = true
	# A frozen body hit by a blade does not "take an ice contact" - it SHATTERS.
	# That is a different event with a different shape, and it is the only reason
	# FROZEN is worth knowing about from the audio side.
	#
	# ONLY at or above `SHATTER_POISE`, because that is the world's own rule: a
	# light landing on frozen matter adds damage, it does not break the shell. A
	# blade must never announce a shatter the body decided not to do.
	if _is_frozen(target) and float(hit.get("poise_damage", 0.0)) >= SHATTER_POISE:
		_play(&"sword_shatter", 1.0, at, has_at)
		return
	var heavy := String(controller.attack_kind) in ["heavy", "skill", "followup"]
	var surface := _surface_of(target)
	play_event(&"SWORD_CONTACT", 0.9 if heavy else 0.4, surface, at, has_at)


func _on_perfect_guard() -> void:
	if not enabled:
		return
	_perfect_guard_fired = true
	_play(&"sword_perfect_guard")


func _on_player_hit(_hit: Dictionary) -> void:
	if not enabled or controller == null:
		return
	if _perfect_guard_fired:
		_perfect_guard_fired = false
		return
	# Deferred, so this runs AFTER the controller finished resolving the hit: a
	# hit that turned out to be perfect has already claimed the moment and this
	# must not also play a block underneath it.
	if controller.state == CombatController.State.BLOCK:
		_play(&"sword_block")


func _on_state_changed(_previous: int, current: int) -> void:
	if not enabled:
		return
	# CHARGE is the heavy's INPUT - the body coiling, before the air has moved.
	if current == CombatController.State.CHARGE:
		_play(&"sword_heavy_windup")
		return
	if current == CombatController.State.DODGE:
		_play(&"sword_dodge")


func _process(_delta: float) -> void:
	if show_debug_overlay:
		_draw_overlay()
	if not enabled or _wind_hitbox == null:
		return
	# Wind has no signal of its own; the hitbox going live IS the event.
	# Type-tested rather than converted, for the same reason as `_is_frozen`: `bool()` is
	# the bool CONSTRUCTOR and it rejects the `null` that `get()` returns for a property
	# that is not there, which would make a missing `active` an error instead of a false.
	var active := false
	var raw_active: Variant = _wind_hitbox.get("active")
	if raw_active is bool:
		active = raw_active
	if active and not _wind_was_active:
		_play(&"wind_burst")
	_wind_was_active = active


# -------------------------------------------------------------------- world

## What did the blade land on?
##
## Property first (an actor that knows what it is), then a GROUP (a prop that has
## no script at all), then "flesh" - because everything that exists in this game
## and can be hit is either a body or has said otherwise.
func _surface_of(target: Node) -> StringName:
	if target == null:
		return &"flesh"
	var declared: Variant = target.get("surface")
	if declared != null and String(declared) != "":
		return StringName(declared)
	for group in SURFACE_GROUPS:
		if target.is_in_group(group):
			return SURFACE_GROUPS[group]
	# A frozen body has no crate to declare itself with, but its surface has stopped
	# being flesh: a hit below the shatter threshold is a blade arriving on ICE.
	if _is_frozen(target):
		return &"ice"
	return &"flesh"


## Frozen is asked for by NAME rather than by reading a state enum, so a body that
## can be frozen without being a TechnicalDummy gets the shatter for free.
##
## Both branches TEST THE TYPE instead of converting, because `bool()` is not a cast in
## GDScript: it is the bool CONSTRUCTOR, and it only accepts a number. `bool(null)` - the
## value `get()` returns for a body with no `frozen` property - is an invalid call, so the
## original form raised "Nonexistent 'bool' constructor" on every contact whose target was
## not frozen, and got the right answer by accident: the error aborted the statement and
## the function fell out as false. A trigger that works because it throws is a trigger
## that stops working the moment somebody quiets the error - and it was already silencing
## the `&"ice"` fallback in `_surface_of`, which sits behind this call.
func _is_frozen(target: Node) -> bool:
	if target == null:
		return false
	if target.has_method("is_frozen"):
		var verdict: Variant = target.call("is_frozen")
		if verdict is bool:
			return verdict
		return false
	# `in` asks whether the property EXISTS, so the `get()` below cannot be the one that
	# reports a missing index.
	if "frozen" in target:
		var declared: Variant = target.get("frozen")
		if declared is bool:
			return declared
	return false


# -------------------------------------------------------------------- output

func _play(cue_id: StringName, intensity := 1.0, at := Vector3.ZERO, has_at := false) -> void:
	var cue := cues.get(cue_id) as SfxCue
	if cue == null:
		push_warning("CombatAudioDirector: unknown cue '%s'" % String(cue_id))
		return
	last_cue_id = cue_id
	var layers := sfx.play(cue, at, has_at)
	cue_seq += 1
	var entry := {
		"seq": cue_seq,
		"cue": cue_id,
		"at": at,
		"intensity": intensity,
		"layers": layers.size(),
	}
	history.append(entry)
	if history.size() > HISTORY_MAX:
		history = history.slice(history.size() - HISTORY_MAX)
	if log_cues:
		cue_log.append("%.2f %s" % [Time.get_ticks_msec() / 1000.0, String(cue_id)])


## Fire a cue by id from anywhere (debug panel, scripted moments, magic).
func play_cue(cue_id: StringName) -> void:
	_play(cue_id)


## Fire a cue by id AT A WORLD POSITION. `play_cue` is the player-layer case and
## deliberately drops the position; a spatial cue given no position has nothing to be
## spatial ABOUT, so it falls back to the centred pool. The cue sheet needs both, and
## needs them to be the same call, because the thing it is checking is whether the
## 3D path works at all - and a control reading of 0.0 dB on a dead-ahead source is
## the only way that check can fail loudly.
func play_cue_at(cue_id: StringName, at: Vector3) -> void:
	_play(cue_id, 1.0, at, true)


func cue_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for key in cues.keys():
		ids.append(key)
	ids.sort()
	return ids


## PART 18. The names only - a frame anyone watches must not carry numbers.
func recent_events(count := HISTORY_MAX) -> Array[String]:
	var out: Array[String] = []
	var from := maxi(0, history.size() - count)
	for i in range(from, history.size()):
		out.append(String(history[i]["cue"]))
	return out


func _draw_overlay() -> void:
	if _overlay == null:
		var layer := CanvasLayer.new()
		layer.name = "AudioDebugLayer"
		add_child(layer)
		_overlay = Label.new()
		_overlay.name = "AudioDebug"
		_overlay.position = Vector2(24.0, 120.0)
		_overlay.add_theme_font_size_override("font_size", 15)
		_overlay.add_theme_color_override("font_color", Color(0.85, 0.92, 1.0))
		layer.add_child(_overlay)
	_overlay.text = "\n".join(recent_events())
