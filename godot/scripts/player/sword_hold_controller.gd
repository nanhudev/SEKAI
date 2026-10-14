extends Node
class_name SwordHoldController
# ============================================================================
# SHEATHED → DRAWING → DRAWN → SHEATHING
# ============================================================================
#
# §7 asks for four states BY NAME, and the reason that matters is that the naive
# version of this feature has two. A sword is either "out" or "not out", the key
# toggles a boolean, and the blade is in the hand on the frame the key went down.
# What that loses is the ONLY part of a draw anyone watches: the 0.6 s in which
# the blade is travelling out of the scabbard, when a cut is impossible and a real
# person can see that you are committed to something.
#
# SO THE TWO TRANSITIONS ARE STATES WITH DURATIONS, AND DURING THEM THE SWORD IS
# GENUINELY UNAVAILABLE. That is not a lockout for feel - it falls out of the rig:
# `CombatController._start` already refuses `light`/`heavy`/`iaido`/`ultimate`
# while `equip_blend < 1.0`, because a swing started mid-draw would be a swing
# with the blade half inside its own scabbard. This file does not have to enforce
# anything; it only has to tell the truth about WHICH of the four states the rig
# is in, and the rig does the rest.
#
# WHY IT IS NOT PART OF WeaponManager. `WeaponManager` decides when a weapon
# CHANGES - it drives the draw as the arrival half of a switch, and the sheathe as
# the departure half. This node owns a different question: given that the sword is
# the weapon in hand, is the blade out or home? Those are two questions, and the
# first playable needs the second one to be answerable on its own - `R` must work
# in a world where nothing is ever being switched.
#
# THE SOUND IS ATTACHED TO THE STATES, NOT TO THE KEY. The draw cue fires when
# DRAWING begins, so it cannot be heard by a player who pressed R and had nothing
# happen (no sword, or already mid-transition) - the same discipline the project
# already applies to `swing_started` on the combat side.

signal state_changed(previous: int, current: int)
signal draw_finished()
signal sheathe_finished()

enum Hold { SHEATHED, DRAWING, DRAWN, SHEATHING }

const HOLD_NAMES := {
	Hold.SHEATHED: "SHEATHED", Hold.DRAWING: "DRAWING",
	Hold.DRAWN: "DRAWN", Hold.SHEATHING: "SHEATHING",
}

## Mirrors `WeaponManager`'s draw, and deliberately the same number: a player who
## learned the length of a draw from the weapon switch must not find that R draws
## a different-length sword.
##
## THE NUMBER IS NO LONGER TYPED HERE. It was 0.62 s, which was the length of a
## four-key lerp; SWORD PRESENTATION V3's draw is a five-beat sentence with a
## 200 ms pause and a 120 ms glint inside it, and its length is a property of
## that sentence. Asking the move is the only way these two facts cannot drift —
## retune `SwordBasic.equip()` and both callers follow, with no second constant to
## update and therefore no second constant to forget.
func draw_seconds() -> float:
	return SwordBasic.equip().total_time()


## The sheathe is the same sentence read backwards, so it costs the same. §2's
## shared contract is why this is a call and not a second number: nothing about
## putting a sword away is longer or shorter than taking it out.
func sheathe_seconds() -> float:
	return SwordBasic.equip().total_time()

@export var draw_sfx_path := "res://audio/sfx/iaido/draw.wav"
@export var sheathe_sfx_path := "res://audio/sfx/iaido/sheath_move.wav"
@export var lock_sfx_path := "res://audio/sfx/iaido/sheath_lock.wav"

@export var draw_key: Key = KEY_R

var hold: int = Hold.SHEATHED
var state_name := "SHEATHED"

var _player: CharacterBody3D = null
var _combat: Node = null
var _slot: WeaponSlot = null
var _progress := 0.0
var _draw_sfx: AudioStreamPlayer = null
var _sheathe_sfx: AudioStreamPlayer = null
var _lock_sfx: AudioStreamPlayer = null


func _ready() -> void:
	_player = get_parent() as CharacterBody3D
	if _player == null:
		push_warning("SwordHoldController: parent is not a CharacterBody3D, so there "
			+ "is no rig to draw from.")
		return
	_combat = _player.get_node_or_null("CombatController")
	_slot = _player.get_node_or_null("WeaponSlot") as WeaponSlot
	_bind_key()
	_build_sound()
	set_process(true)
	# The blade starts home. A world that begins with the sword already out is a
	# world whose first story beat ("拔出来试试") cannot happen.
	_apply(0.0)


func _bind_key() -> void:
	var action := &"draw_sword"
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	# Physical code so the key follows the KEY, not the layout - the same reason
	# every other binding in this project uses `physical_keycode`.
	var already := false
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey and (ev as InputEventKey).physical_keycode == draw_key:
			already = true
	if not already:
		var e := InputEventKey.new()
		e.physical_keycode = draw_key
		InputMap.action_add_event(action, e)


func _build_sound() -> void:
	_draw_sfx = _sfx("DrawSfx", draw_sfx_path, -7.0)
	_sheathe_sfx = _sfx("SheatheSfx", sheathe_sfx_path, -9.0)
	_lock_sfx = _sfx("SheathLockSfx", lock_sfx_path, -6.0)


func _sfx(node_name: String, path: String, volume: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.name = node_name
	if ResourceLoader.exists(path):
		var s := load(path)
		if s != null:
			p.stream = s
	p.volume_db = volume
	# In `world_audio` so §19's duck reaches it too.
	p.add_to_group("world_audio")
	_player.add_child(p)
	return p


# ================================================================ public API

func holds_a_sword() -> bool:
	return _slot != null and _slot.is_sword()


func is_drawn() -> bool:
	return hold == Hold.DRAWN


func is_busy() -> bool:
	return hold == Hold.DRAWING or hold == Hold.SHEATHING


## The one entry point. Returns whether anything actually started, so the caller
## (the story world's input handler) can leave the key unhandled when it did not.
func toggle() -> bool:
	match hold:
		Hold.SHEATHED:
			return _begin_draw()
		Hold.DRAWN:
			return _begin_sheathe()
	return false


func force_sheathed() -> void:
	hold = Hold.SHEATHED
	state_name = HOLD_NAMES[hold]
	_progress = 0.0
	_apply(0.0)


func force_drawn() -> void:
	hold = Hold.DRAWN
	state_name = HOLD_NAMES[hold]
	_progress = 1.0
	_apply(1.0)


func _begin_draw() -> bool:
	if not holds_a_sword():
		return false
	_enter_hold(Hold.DRAWING)
	_progress = 0.0
	_play(_draw_sfx)
	return true


func _begin_sheathe() -> bool:
	_enter_hold(Hold.SHEATHING)
	_progress = 1.0
	_play(_sheathe_sfx)
	return true


## Named `_enter_hold`, NOT `_set`. `Object._set(StringName, Variant) -> bool` is a
## real engine virtual, and a no-annotation `func _set(next: int)` is a hard parse
## error in 4.4.1 ("The function signature doesn't match the parent") - the
## controller fails to load, the plaza's typed reference to it fails with it, and
## the symptom reads as "the draw does not work" rather than "this method is
## reserved". If you are looking for this in a future diff, that is why.
func _enter_hold(next: int) -> void:
	if hold == next:
		return
	var previous := hold
	hold = next
	state_name = HOLD_NAMES[hold]
	state_changed.emit(previous, next)


func _play(p: AudioStreamPlayer) -> void:
	if p != null and p.stream != null:
		p.play()


# ================================================================== runtime

func _process(delta: float) -> void:
	if _combat == null:
		return
	match hold:
		Hold.DRAWING:
			_progress = minf(1.0, _progress + delta / draw_seconds())
			# LINEAR, AND ON PURPOSE. The draw used to be eased here (an
			# accelerate-out curve), because all it had was a start pose and an
			# end pose and the curve was the only thing that could give the motion
			# a shape. The five-beat sentence brought its own shape: a 200 ms
			# pause, a 120 ms glint, a slow first third and a faster last. An
			# ease applied ON TOP of that does not refine it, it re-times it —
			# the pause slides down the beat list and the glint lands early.
			#
			# So the blend is now the plain clock it reads as, and every question
			# of pacing lives in `SwordBasic.equip()`'s beat times where it can be
			# read next to the beat it describes.
			_apply(_progress)
			if _progress >= 1.0:
				_enter_hold(Hold.DRAWN)
				draw_finished.emit()
		Hold.SHEATHING:
			_progress = maxf(0.0, _progress - delta / sheathe_seconds())
			# ...and the same on the way back. The sheathe's urgency is authored
			# too: §7-§10's rework is a spine-glide, a mouth catch and a slow final
			# 10-15 cm, none of which survives being re-timed by a `pow`.
			_apply(_progress)
			if _progress <= 0.0:
				_enter_hold(Hold.SHEATHED)
				_play(_lock_sfx)
				sheathe_finished.emit()


func _apply(blend: float) -> void:
	if _combat != null:
		_combat.set("equip_blend", clampf(blend, 0.0, 1.0))


# ------------------------------------------------------------------- the key
#
# `_unhandled_input`, not `_input`: the story UI takes E and clicks while a
# dialogue is open, and R must keep working during a conversation (a player who
# draws their sword while someone is talking to them is doing something the game
# should allow). Nothing else in this world claims R, because the story-world
# input profile has already released it from `frost_cast`.
func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed(&"draw_sword"):
		return
	if toggle():
		get_viewport().set_input_as_handled()


func debug_line() -> String:
	return "HOLD  %s  blend %.2f" % [state_name, _progress]
