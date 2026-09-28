extends Node3D
class_name ChainDirector
# 缚星链 / STAR-BIND CHAIN — the first COMPLEX WEAPON.
#
# A SWORD asks "where is the blade". A CHAIN asks three questions: how far out is
# the head, how fast is it already going, and is it taut. Those three numbers
# (RADIUS / MOMENTUM / TENSION) are the whole weapon, they are internal, and none
# of them gets a bar. If a player needs a gauge to know the chain is taut, this
# file has failed.
#
# WHAT IT DELIBERATELY IS NOT: a rigid-body chain. Twenty links with their own
# collision would be unstable, unsynchronisable, unanimateable and unreadable in
# first person — and none of that instability is something a player can feel.
# FAKE WHAT THE PLAYER CANNOT FEEL (brief §7 / §50). The head is driven by an
# explicit state machine; the links are a drawing (see ChainVisual).
#
# THE HEAD IS DESCRIBED IN POLAR FORM around the player — one azimuth, one
# radius, one height. Every action in the weapon is therefore the same three
# lerps with different data, which is why 横缚 (a 145° sweep), 缠锁 (a straight
# throw), 下砸 (a slam) and 绷切 (a snap back along a taut line) are one code
# path. Adding a chain technique means adding a ChainMove, not a branch here.
#
# CLOCKS: every window in this file rides `state_time` (delta-accumulated), never
# `Time.get_ticks_msec()`. So hitstop freezes the chain's animation AND its
# windows together, which is the behaviour the sword does not have yet — see
# COMBAT_DESIGN §18-7. A weapon whose windows ran on a different clock from its
# animation would feel like the input was lying.

enum State { HELD, SWINGING, EXTENDING, SLAMMING, ORBITING, TENSIONED, RETRACTING, HOOKED }

signal move_started(move: ChainMove)
signal hit_landed(move: ChainMove, hit: Dictionary)
signal hooked(target: Node3D, weight: StringName)
signal bound(target: Node3D, seconds: float)
signal taut_changed(taut: bool)
# §49: the SOUND of the chain is not this line's, but its TIMING is. The haul's
# rhythm and the wall's impact are events the audio line can only place correctly if
# the weapon hands them over as events rather than leaving them to be inferred from
# a state machine. Nothing in the game listens yet on purpose — see §50.
signal tug(step: int, total: int, amount: float)
signal wall_impact(strength: float)
signal message(text: String)
# §30: THE AUDIO LINE'S CONTRACT. The combat line owns no sound file and never
# will — it owns the MOMENTS, named, so the entire voice of this weapon can be
# replaced without a line changing here. The rhythm of a haul already needed
# `tug` for exactly this reason; this is the rest of the vocabulary, and the
# names are the brief's, not this file's.
#
#   CHAIN_THROW          the head leaves the hand
#   CHAIN_RATTLE         links moving — a sweep, the chain's own noise floor
#   CHAIN_CONTACT        the head meets something (a body, a wall, a target)
#   CHAIN_BITE           the hook has HOLD of something (§13's third beat)
#   CHAIN_TENSION_START  the rope begins to come up hard
#   CHAIN_TENSION_FULL   it is at its limit — the snap
#   CHAIN_YANK           one tug of a haul
#   CHAIN_RETRACT        the reel begins
#   CHAIN_SLAM           the head is driven down
#   CHAIN_WALL           metal on stone
signal chain_event(event: StringName, data: Dictionary)

const EV_THROW := &"CHAIN_THROW"
const EV_RATTLE := &"CHAIN_RATTLE"
const EV_CONTACT := &"CHAIN_CONTACT"
const EV_BITE := &"CHAIN_BITE"
const EV_TENSION_START := &"CHAIN_TENSION_START"
const EV_TENSION_FULL := &"CHAIN_TENSION_FULL"
const EV_YANK := &"CHAIN_YANK"
const EV_RETRACT := &"CHAIN_RETRACT"
const EV_SLAM := &"CHAIN_SLAM"
const EV_WALL := &"CHAIN_WALL"

# Layer 1 is the world (floor, walls, pillars) and layer 2 is every hurtbox —
# the same two layers the sword's Area3D hitboxes already use.
const WALL_MASK := 1
const HURTBOX_MASK := 2
# §30's two tension thresholds, as drawn-tension values. START is where the rope
# has visibly begun to come up; FULL is where it is at its limit.
const TENSION_START_AT := 0.25
const TENSION_FULL_AT := 0.95
# How much of its own average speed a move's startup is still carrying when it
# hands the head to the arc. See `_startup_arrive` — 0 is the old smoothstep, and
# 1 would be a straight line with no settle in it at all.
const STARTUP_TAIL := 0.42
# PlayerMovement's own decay constant. A tug is authored as a DISTANCE (see
# ChainMoveset) and only a body that owns its decay can turn one into motion; a
# body that only takes velocities gets the matching speed through this number.
const PULL_TO_SPEED := 9.0

@export var moveset: ChainMoveset

@onready var player: CharacterBody3D = get_parent()
@onready var weapon: WeaponSlot = get_parent().get_node_or_null("WeaponSlot")
@onready var camera_feedback: CameraFeedbackController = get_parent().get_node_or_null("CameraFeedbackController")
# Held rather than fetched per tug: a tug fires up to five times per pull and this
# is a global engine clock, not a per-hit value.
@onready var time_effects: TimeEffectManager = get_parent().get_parent().get_node_or_null(
	"TimeEffectManager"
)
@onready var hand: Node3D = get_parent().get_node_or_null(
	"CameraRig/LookPivot/MotionPivot/ShakePivot/WeaponRoot/ChainHandAnchor"
)
# WHERE THE PLAYER IS LOOKING, in pitch. Only the moves that ask for it read this
# (§13): a chain is thrown toward the aim, so a throw that can only ever leave the
# hand at chest height can hook a pillar but never the top of one, and a stage with
# a high anchor on it would be a stage nothing could reach. Negative rotation.x is
# looking DOWN, which is why the offset below negates it.
@onready var look_pivot: Node3D = get_parent().get_node_or_null("CameraRig/LookPivot")
# The chain's heights (home 0.62, sweep 1.05, slam peak 2.55) are measured FROM THE
# PLAYER'S FEET. Measured from the body's centre instead, "chest height" would land
# at world y 2.20 while an enemy's hurtbox tops out at 1.85 — the chain would swing
# cleanly over every enemy in the game and still look plausible in a screenshot.
# The capsule is centred on the body origin, so the feet are half its height below;
# reading it beats typing 0.9, because a taller player must not silently lift every
# authored chain height off the enemies it is supposed to reach.
@onready var _foot_offset := _measure_foot_offset()

# ------------------------------------------------------- the three variables
var state := State.HELD
var state_time := 0.0
# How far out the head is. Clamped to the chain's length: reach is the weapon's
# currency and it has a limit, which is what makes TENSION possible at all.
var radius := 0.0
# Normalised 0..1. What it buys is TIME (a sweep at full spin genuinely arrives
# sooner) and a little reach — never a flat damage number.
var momentum := 0.0
# Smooth 0..1 for the drawing; `is_taut()` is the boolean the rules use. The two
# are deliberately separate: the curve should straighten *before* the rules flip,
# so the player sees the state arrive instead of discovering it.
var tension := 0.0

var active_move: ChainMove
var move_hit := false
var hits_landed := 0
var wall_hits := 0
var last_wall_impact := 0.0
var bound_left := 0.0
var chain_visual: ChainVisual

# A test may take the clock away. The windows in this weapon ARE the design (a
# 0.30s bind deck is not a range), so a test that has to hit one exactly must not
# be at the mercy of how many frames a shared machine manages per second.
var manual_step := false

# ---------------------------------------------------------------- head model
var _azimuth := 0.0          # world yaw of the head: +Z at 0, matching the enemy's own convention
var _height := 0.0
var _head := Vector3.ZERO
var _head_prev := Vector3.ZERO
var _head_velocity := Vector3.ZERO
var _pose_from := Vector3.ZERO    # (azimuth, radius, height) at commit — the startup lerp starts here
var _pose_start := Vector3.ZERO   # where ACTIVE begins
var _pose_end := Vector3.ZERO     # where ACTIVE ends
var _radius_scale := 1.0
var _duration := 0.0
# Where the strike ends, frozen at commit. Recomputed from live momentum it could
# disagree with the duration the move is actually playing, and a cancel window
# that drifts while the animation does not is the input lying to the player.
var _strike_end := 0.0
var _move_end := 0.0
# Where the head was at the END OF THE ACTIVE PHASE. Tension is decided by whether
# the chain finished a technique stretched to its limit — not by the live radius,
# which recovery bleeds home at 1.6 m/s (so a 4.6m throw reads 4.12m by the time the
# move is over and would answer "no" for every throw ever made), and not by the
# maximum during the move either, which would be just as wrong in the other
# direction: 绷切 and 拉近斩 both START at the limit because they begin attached to
# whatever the chain already caught, so a maximum would have every one of them end
# back in TENSION — an infinite taut loop where the pressure never gets spent.
var _reach_end := 0.0
var _hit_targets: Array[Node] = []
var _head_shape: SphereShape3D

# ------------------------------------------------------------------- chain
var _chain_index := 0
var _idle_time := 0.0
var _pull_done := false
var _tension_left := 0.0
# The height the chain was stretched to when it went taut. §16's window is a fixed
# LENGTH, not a fixed pose, so this is what _step_tension holds while the player
# spends the pressure.
var _taut_height := 1.05

# -------------------------------------------------------------------- orbit
var _orbit_hold := 0.0
var _orbit_hit_timer := 0.0

# --------------------------------------------------------------------- hook
var _hook_actor: Node3D
var _hook_offset := Vector3.ZERO
# §13's third beat, counted down in `step`. While it is running the rope is held
# off the snap on purpose — see ChainMoveset's bite note.
var _bite_left := 0.0
var _bite_actor: Node3D

# ----------------------------------------------------------------- the tugs
# A pull is a HAUL, not a magnet — see ChainMoveset's 顿挫 block. The total distance
# is armed here and paid out one yank at a time by _step_tugs(), so the body it is
# pulling visibly stops between yanks instead of sliding.
var _tug_dir := Vector3.ZERO
var _tug_total := 0.0
var _tug_target_share := 0.0
var _tug_player_share := 0.0
var _tug_left := 0
var _tug_step := 0
var _tug_timer := 0.0

# ----------------------------------------------------------------- feedback
var _was_taut := false
# §30's two tension moments, announced once per episode rather than every frame.
var _announced_start := false
var _announced_full := false
# The facing the current arc was authored around; steer is measured from it.
var _steer_base := 0.0
# How fast the head is going ROUND the player, in radians per second. Landing an
# impact needs to know which way the head was already travelling in order to knock
# it off that course in the right direction (§43), and a velocity vector cannot say
# that on its own once the head is coming straight at you.
var _azimuth_vel := 0.0
var _azimuth_prev := 0.0
# How far a landing has bent the current arc, and where it is heading. Eased rather
# than snapped: the head is deflected by a collision, and a collision that teleports
# the arc would read as a bug in the animation rather than as weight.
var _deflect := 0.0
var _deflect_target := 0.0

# ------------------------------------------------------------- debug readout
# §46. The three numbers the weapon runs on are a DEVELOPER readout, not a HUD: the
# moment the player needs a gauge to know the chain is taut, the weapon has failed
# (§51). So the numbers are opt-in. `debug_readout` is the explicit switch, and the
# developer panel (F8) is the project's idea of developer mode — this asks the panel
# rather than assuming it, and never reaches into the panel's own file to do it.
@export var debug_readout := false
var _dev_panel: Node
var _dev_probe_timer := 0.0
const DEV_PROBE_INTERVAL := 0.5


func _ready() -> void:
	if moveset == null:
		moveset = ChainLibrary.build()
	_head_shape = SphereShape3D.new()
	_head_shape.radius = moveset.head_radius
	chain_visual = ChainVisual.new()
	chain_visual.name = "ChainVisual"
	add_child(chain_visual)
	chain_visual.configure(moveset.links, moveset.chain_length, moveset.head_radius)
	if hand != null:
		chain_visual.build_handle(hand)
	if weapon != null:
		weapon.changed.connect(_on_weapon_changed)
	reset()


func _physics_process(delta: float) -> void:
	if manual_step:
		return
	step(delta)


func _unhandled_input(event: InputEvent) -> void:
	if not is_equipped():
		return
	if event.is_action_pressed(&"light_attack"):
		request(&"light")
	elif event.is_action_pressed(&"heavy_attack"):
		request(&"heavy")
	elif event.is_action_released(&"heavy_attack"):
		release_heavy()
	elif event.is_action_pressed(&"style_skill_1"):
		request(&"chain_hook")
	elif event.is_action_pressed(&"style_skill_2"):
		request(&"chain_lock")
	elif event.is_action_pressed(&"block"):
		request(&"block")


func _on_weapon_changed(_previous: StringName, _current: StringName) -> void:
	# Switching weapons must not leave a chain hanging in the air, and must not
	# leave momentum banked for whoever comes back to it later.
	reset()


# ============================================================================
#  PUBLIC API
# ============================================================================

func is_equipped() -> bool:
	# No slot at all means a stage that predates the weapon switch: the chain is
	# then simply always the active weapon, which keeps this node usable on its own.
	return weapon == null or weapon.is_chain()


func is_taut() -> bool:
	return state == State.HOOKED or radius >= moveset.max_radius * moveset.tension_ratio


func is_hooked() -> bool:
	return _hook_actor != null and is_instance_valid(_hook_actor)


func is_bound() -> bool:
	return bound_left > 0.0


func weight_of(actor: Node3D) -> StringName:
	# The chain asks a target how heavy it is without knowing what a target IS,
	# the same duck-typed contract Measure uses to find an opponent.
	if actor != null and actor.has_method("weight_class"):
		return actor.call("weight_class")
	return moveset.default_weight


func movement_scale() -> float:
	if not is_equipped():
		return 1.0
	# 锁链攻击时允许移动 — that is the whole difference between this and a heavy
	# weapon (§28). Only the FULL ORBIT costs speed, because holding a chain that
	# is circling you at 2.3m genuinely does.
	if state == State.ORBITING:
		return moveset.movement_scale_orbit
	return 1.0


func request(action: StringName) -> bool:
	if not is_equipped():
		return false
	match action:
		&"light":
			return _request_light()
		&"heavy":
			return _request_heavy()
		&"chain_hook":
			if not _can_start_now():
				return false
			return _start(moveset.hook_id)
		&"chain_lock":
			return _request_lock()
		&"block":
			if not _can_start_now():
				return false
			return _start(moveset.deflect_id)
		&"retract":
			if _can_act():
				_retract()
				return true
	return false


func release_heavy() -> bool:
	# The release of the orbit. Early is allowed and always was: acting sooner for
	# less force IS the timing choice (§14), not a punishable mis-input. But a TAP
	# is not an early release — below the minimum commitment the chain keeps
	# spinning, so 蓄势回旋 cannot be fired by brushing the button by accident.
	if state != State.ORBITING:
		return false
	if _orbit_hold < moveset.orbit_min_hold:
		message.emit("蓄势不足 · HOLD")
		return false
	return _launch()


# MAGIC x CHAIN, interaction 1 of 2 in phase 1. Wind does not add damage to the
# chain — it adds SPIN, which is the chain's own currency, so the most natural
# pairing in the whole system writes itself.
func apply_wind_boost() -> void:
	if not is_equipped():
		return
	momentum = minf(moveset.momentum_max, momentum + moveset.wind_momentum_bonus)
	_radius_scale = 1.0 + moveset.radius_momentum_scale * momentum
	if state == State.ORBITING:
		# A gust while the chain is already moving is the payoff: it speeds the
		# circle up, which speeds the eventual throw up.
		_orbit_hold = minf(_orbit_hold + 0.12, moveset.orbit_max_hold)
	message.emit("风助 · MOMENTUM %.0f%%" % (momentum * 100.0))


# Called from the player's damage reception. A chain does not block: it sweeps
# the attack aside, so this is asked before any damage is applied.
func try_deflect(hit: Dictionary) -> bool:
	if not is_equipped():
		return false
	if active_move == null or not active_move.deflects:
		return false
	if state != State.SWINGING:
		return false
	# HOT: the arc has been swept, and the head is now in front of the body. A
	# stale sweep is still worth something but is not free.
	if state_time < active_move.startup * 0.5:
		return false
	# Phase 1 deflects MELEE LIGHT attacks only. 35 poise is the project's
	# existing line between a light and a heavy, so a heavy goes straight through
	# this guard — which is the counterplay that keeps DEFLECT from being free.
	var poise := float(hit.get("poise_damage", 0.0))
	if poise >= 35.0:
		return false
	var elapsed := state_time - active_move.startup
	var perfect := elapsed >= 0.0 and elapsed <= moveset.deflect_perfect_window
	_nudge_camera(Vector2(0.02, -0.008), 0.05)
	var attacker: Node3D = hit.get("source")
	if perfect:
		# 截链 · PERFECT DEFLECT. Not a clash of metal: the enemy's attack
		# TRAJECTORY is disturbed, so the enemy is what gets interrupted.
		momentum = minf(moveset.momentum_max, momentum + moveset.deflect_momentum_bonus)
		if attacker != null and attacker.has_method("on_chain_deflect"):
			attacker.call("on_chain_deflect")
		if camera_feedback != null:
			camera_feedback.add_trauma(0.10)
			camera_feedback.roll_impulse(2.2)
		message.emit("截链 · PERFECT DEFLECT")
		return true
	# A stale sweep still spoils the blow, but it is not free: the chain is metal
	# on a rope, not a wall.
	var scale := moveset.deflect_damage_scale
	var damage := float(hit.get("damage", 0.0)) * scale
	var health: float = player.get("health")
	player.set("health", maxf(0.0, health - damage))
	if camera_feedback != null:
		camera_feedback.add_trauma(0.06)
	message.emit("拨链 · DEFLECT %.0f%%" % ((1.0 - scale) * 100.0))
	return true


func reset() -> void:
	state = State.HELD
	state_time = 0.0
	active_move = null
	move_hit = false
	_release_hook()
	_hit_targets.clear()
	momentum = 0.0
	bound_left = 0.0
	_chain_index = 0
	_idle_time = 0.0
	_orbit_hold = 0.0
	_tension_left = 0.0
	_radius_scale = 1.0
	# A haul belongs to the weapon being in hand: switching away wipes it, for the
	# same reason switching away wipes the momentum.
	_clear_tugs()
	_tension_reset()
	radius = moveset.home_radius
	_height = moveset.home_height
	_azimuth = _facing_azimuth() + deg_to_rad(moveset.home_azimuth_degrees)
	# The angular trace is reset with the pose, or the first frame after a reset
	# reports one enormous turn and the very first landing would bend an arc that
	# had not started moving yet.
	_azimuth_prev = _azimuth
	_azimuth_vel = 0.0
	_deflect = 0.0
	_deflect_target = 0.0
	_head = _head_position()
	_head_prev = _head
	if camera_feedback != null:
		camera_feedback.sustain_fov = 0.0
	if chain_visual != null:
		chain_visual.set_chain_visible(is_equipped())
		chain_visual.update_chain(_hand_position(), _head, Vector3.ZERO, tension, 0.016)


func head_position() -> Vector3:
	return _head


func debug_state_line() -> String:
	# §46. RADIUS / MOMENTUM / TENSION are a developer readout, not a HUD: they exist
	# so a tester can tell a 0.40s bind from a 1.00s one without counting frames, and
	# they are exactly the numbers the player must never need (§51 — if a bar is
	# required to know the chain is taut, the weapon has failed). Outside developer
	# mode this answers with what a player IS allowed to know: the form, and — once
	# there is more than one form — nothing else. The line stays non-empty so the
	# HUD that calls it shows a weapon name rather than a blank row.
	if not dev_readout_on():
		return "%s" % moveset.form_name
	var move_name := active_move.display_name if active_move != null else "-"
	var hook := "—"
	if is_hooked():
		hook = "%s / %s" % [_hook_actor.name, String(weight_of(_hook_actor))]
	var bound := "  BOUND %.2fs" % bound_left if bound_left > 0.0 else ""
	# §46's list, in its order: FORM first, then the three variables, then what is
	# attached to what. ANCHORS and OPPORTUNITY TAG are not here because the forms
	# that own them do not exist yet — a field printed as "—" forever teaches a
	# reader to ignore the line it is on.
	return "%s  ·  %s  ·  R=%.2fm  M=%.0f%%  T=%.0f%%%s\n%s  钩=%s" % [
		moveset.form_name, String(State.keys()[state]),
		radius, momentum * 100.0, tension * 100.0, bound,
		move_name, hook,
	]


func debug_flags_line() -> String:
	if not dev_readout_on():
		return ""
	return "绷=%s  钩=%s  命中=%d  撞墙=%d  势=%s" % [
		str(is_taut()), str(is_hooked()), hits_landed, wall_hits,
		"是" if momentum >= 0.5 else "否",
	]


# ============================================================================
#  STEP
# ============================================================================

func step(delta: float) -> void:
	var equipped := is_equipped()
	if chain_visual != null:
		chain_visual.set_chain_visible(equipped)
	if not equipped:
		reset()
		return
	state_time += delta
	_decay_momentum(delta)
	_step_bite(delta)
	_step_tugs(delta)
	match state:
		State.HELD:
			_step_held(delta)
		State.SWINGING, State.EXTENDING, State.SLAMMING:
			_step_move(delta)
		State.ORBITING:
			_step_orbit(delta)
		State.TENSIONED:
			_step_tension(delta)
		State.RETRACTING:
			_step_retract(delta)
		State.HOOKED:
			_step_hooked(delta)
	# WHICH WAY THE HEAD IS GOING ROUND. Taken after the state has moved it, and
	# wrapped, because "past π" and "past -π" are the same place and a raw difference
	# would report a full turn the wrong way at exactly the moment the head crosses
	# the seam — which is also the moment 甩星 releases toward the aim.
	_azimuth_vel = wrapf(_azimuth - _azimuth_prev, -PI, PI) / maxf(delta, 0.0001)
	_azimuth_prev = _azimuth
	_update_tension(delta)
	_resolve_head(delta)
	_update_feedback(delta)


# §13's THIRD BEAT. The head has arrived; this is the moment the player is told it
# has HOLD. It is announced when the bite ENDS rather than when it begins, because
# the bite is the length of the pause in front of the snap — the thing the sound
# and the micro-jerk are placed against is the rope coming up, not the rope
# touching.
func _step_bite(delta: float) -> void:
	if _bite_left <= 0.0:
		return
	_bite_left = maxf(0.0, _bite_left - delta)
	if _bite_left > 0.0:
		return
	var actor := _bite_actor
	_bite_actor = null
	_announce(EV_BITE, {"target": actor, "weight": weight_of(actor)})
	# …and the rope starts to come up on the same beat. Not a separate state: the
	# drawing has been held at zero through the bite, so letting it read the radius
	# again IS the tension starting.
	_announce(EV_TENSION_START, {"from": "bite"})
	# §36: the element verb, offered to whatever is on the end of the chain. Frost
	# and Wind do not exist here and this file must not know that they might.
	_call_on_actor(actor, &"on_chain_bite", player)


func _step_held(delta: float) -> void:
	# 锁链不是永远垂直挂着 (§8): low, to one side, and alive. Small on purpose —
	# a head that swings around at idle would make the weapon look nervous.
	_idle_time += delta
	if _idle_time > moveset.light_window:
		_chain_index = 0
	var sway := deg_to_rad(moveset.idle_sway_degrees) * sin(_idle_time * moveset.idle_sway_speed)
	var want := _facing_azimuth() + deg_to_rad(moveset.home_azimuth_degrees) + sway
	_azimuth += wrapf(want - _azimuth, -PI, PI) * minf(1.0, delta * 4.5)
	radius = lerpf(radius, moveset.home_radius, minf(1.0, delta * 5.0))
	_height = lerpf(_height, moveset.home_height, minf(1.0, delta * 5.0))


func _step_move(delta: float) -> void:
	if active_move == null:
		_retract()
		return
	var move := active_move
	# STEER (§28/§29). Movement is never locked during a chain attack, so the head
	# has to partly follow the look — otherwise turning while you swing would be a
	# straight penalty. The ARC ROTATES rather than being re-authored, so 横缚 stays
	# exactly 145° wide however far you turn; `steer` only decides how much of your
	# turn the chain agrees to. 0 = the chain has its own opinion, which is what a
	# thrown hook wants; 1 = the player owns it completely, which no move wants.
	var steer := wrapf(_facing_azimuth() - _steer_base, -PI, PI) * move.steer
	# THE ARC BENDS WHERE IT LANDED (§43). A head that has just stopped against a
	# body does not carry on down a painted line: it is knocked off course by
	# whatever it hit, more so by something heavy. Eased, so the bend reads as the
	# arc giving way rather than as a correction.
	_deflect += (_deflect_target - _deflect) * minf(1.0, delta * 6.0)
	if state_time < move.startup:
		# STARTUP TRAVELS, AND ARRIVES MOVING. The head goes to where the move
		# begins instead of appearing there — no technique in this weapon can
		# teleport the chain, which is the difference between a chain and a very
		# long sword — and it gets there still travelling, so the arc it hands over
		# to does not have to start from a stopped chain (§8).
		var t := _startup_arrive(state_time / maxf(move.startup, 0.0001), _is_coasting(move))
		var travel := _lerp_pose(_pose_from, _pose_start, t)
		travel.x += steer + _deflect
		_apply_pose(travel)
		return
	if state_time < move.startup + _duration:
		var t := move.eased((state_time - move.startup) / maxf(_duration, 0.0001))
		_apply_pose(Vector3(
			lerpf(_pose_start.x, _pose_end.x, t) + steer + _deflect,
			lerpf(_pose_start.y, _pose_end.y, t),
			lerpf(_pose_start.z, _pose_end.z, t)
		))
		_reach_end = radius
		_on_active()
		return
	# RECOVERY: the head holds where the strike left it and bleeds energy. This is
	# the window the next cut comes out of.
	var late := state_time - _strike_end
	_apply_pose(Vector3(
		_pose_end.x + steer + _deflect,
		maxf(moveset.min_radius, _pose_end.y - late * 1.6),
		_pose_end.z
	))
	if state_time >= _move_end:
		_finish_move()


func _step_orbit(delta: float) -> void:
	_orbit_hold += delta
	momentum = minf(moveset.momentum_max, momentum + moveset.orbit_gain * delta)
	_radius_scale = 1.0 + moveset.radius_momentum_scale * momentum
	var speed := lerpf(moveset.orbit_speed_min, moveset.orbit_speed_max, momentum)
	_azimuth = wrapf(_azimuth + deg_to_rad(speed) * delta, -PI, PI)
	radius = moveset.orbit_radius * (1.0 + moveset.orbit_radius_swell * momentum)
	_height = moveset.orbit_height
	# A chain whirling around the player IS dangerous in every direction, so the
	# orbit really hits. The target list is cleared on an interval so one lap can
	# not register sixty times against the same enemy — but a second lap can land.
	_orbit_hit_timer -= delta
	if _orbit_hit_timer <= 0.0:
		_hit_targets.clear()
		_orbit_hit_timer = moveset.orbit_hit_interval
	if _orbit_hold >= moveset.orbit_max_hold:
		# Hoarding is not a strategy: at the cap the chain throws itself.
		_launch()


func _step_tension(delta: float) -> void:
	# TAUT. The head sits at the chain's limit and follows the player, because a
	# chain at full stretch is a fixed length, not a fixed point — and this is the
	# state in which the available inputs change (§16).
	_tension_left -= delta
	radius = lerpf(radius, moveset.max_radius, minf(1.0, delta * 8.0))
	var want := _facing_azimuth()
	_azimuth += wrapf(want - _azimuth, -PI, PI) * 0.45 * delta
	# The HEIGHT IT WENT TAUT AT, not a hard-coded chest height. A taut line is a
	# fixed LENGTH, so it keeps whatever elevation it was stretched to — and with the
	# throw aimed by the look (§13) that can be a point well above the player. Pinning
	# it to 1.05 would drag a chain hooked to the top of a pillar down through it.
	_height = lerpf(_height, _taut_height, minf(1.0, delta * 5.0))
	if _tension_left <= 0.0:
		_retract()


func _step_retract(delta: float) -> void:
	var t := clampf(state_time / maxf(moveset.retract_time, 0.001), 0.0, 1.0)
	var pose := _lerp_pose(_pose_from, _retract_pose(), _settle(t))
	# 回收有重量 (§43 RETURN).
	#
	# Retracing the line the head came in on reads as a sprite being reset: the
	# chain is a rope with a mass on the end, so letting go of a strike does not
	# stop the mass, it only stops feeding it. The head therefore OVERSHOOTS —
	# further round, a little further out — and is hauled home from there. Both
	# bulges are zero at both ends of the retract, so the pose it starts from and
	# the pose it settles into are untouched and nothing that waits on HELD is
	# delayed by it.
	var arch := sin(PI * t)
	var home := _retract_pose()
	# `x` is the head's azimuth. The overshoot goes PAST the gap it has to close,
	# i.e. the way it was already travelling, which is why it is the negative of
	# that gap — no new state, and it stays correct if the player turns mid-reel.
	pose.x -= wrapf(home.x - _pose_from.x, -PI, PI) * moveset.retract_overshoot * arch
	# `y` is the radius: drift out before being reeled in, but never past the
	# chain's own length. A retract that stretched the rope would be the one bug
	# this weapon cannot have.
	pose.y = clampf(pose.y + moveset.retract_out * arch, moveset.min_radius, moveset.max_radius)
	_apply_pose(pose)
	if state_time >= moveset.retract_time:
		_enter_held()


func _step_hooked(delta: float) -> void:
	if not is_hooked():
		_release_hook()
		_retract()
		return
	if bound_left > 0.0:
		bound_left = maxf(0.0, bound_left - delta)
		if bound_left == 0.0:
			# 缚 is a WINDOW, not a state. When it closes the chain lets go, which
			# is what makes "拉近斩 or 地砸" a decision with a deadline instead of a
			# menu the player can browse.
			message.emit("缚 · 松脱")
			_release_hook()
			_retract()
			return
	# The head is pinned to the thing it caught. Its polar coordinates are simply
	# DERIVED from that point, so the same head model still positions it and the
	# chain cannot stretch past its own length.
	var want := _hook_actor.global_transform * _hook_offset
	var offset := want - _origin()
	offset.y = 0.0
	var flat := offset.length()
	if flat > 0.001:
		_azimuth = atan2(offset.x, offset.z)
	radius = clampf(_origin().distance_to(want), 0.0, moveset.max_radius)
	_height = want.y - _origin().y


# ============================================================================
#  REQUESTS
# ============================================================================

func _request_light() -> bool:
	if state == State.HOOKED and bound_left > 0.0:
		# The three ways out of a bind exist because 缚 happened. Light is the cut.
		return _start(moveset.bound_light_id)
	if is_taut():
		# TENSION CHANGES THE INPUT (§16). Light while taut is not 横缚, and the
		# player discovers that by pressing the same button and getting a
		# different answer — not by reading a tooltip.
		return _start(moveset.taut_light_id)
	if not _can_act():
		return false
	if moveset.light_chain.is_empty():
		return false
	var id := moveset.light_chain[_chain_index % moveset.light_chain.size()]
	_chain_index = (_chain_index + 1) % moveset.light_chain.size()
	_idle_time = 0.0
	return _start(id)


func _request_heavy() -> bool:
	if state == State.HOOKED and bound_left > 0.0:
		# §23's heavy exit, and it has to be checked BEFORE the taut line for the
		# same reason Light checks it first: a bound target is not a taut line, it
		# is something you are holding. Without this branch 地砸 exists in the data
		# and is unreachable in play, because `is_hooked()` is true throughout a
		# bind — a designed exit that no input can reach is not a designed exit.
		return _start(moveset.bound_heavy_id)
	if is_hooked() or is_taut():
		# 曳 is the CHEAP pull and stays available: hooked-but-not-bound (throw it,
		# do not commit) or taut with nothing caught. 缚 is the committed version.
		return _start(moveset.taut_heavy_id)
	if not _can_act():
		return false
	return _start_orbit()


func _request_lock() -> bool:
	# 缚 (brief §22): the chain snaps tight and the target is thrown off balance.
	# Which way that goes is the WEIGHT TABLE's business, not a special case here.
	if not is_hooked():
		return false
	var response := moveset.hook_response_for(weight_of(_hook_actor))
	_apply_pull(1.0, response)
	var seconds := float(response.get("bound_time", 0.7))
	bound_left = maxf(bound_left, seconds)
	if _hook_actor.has_method("apply_bound"):
		_hook_actor.call("apply_bound", seconds)
	if camera_feedback != null:
		# THE WEIGHT TABLE DRIVES THE CAMERA TOO (§43). The shares already say which
		# body travels; the camera reads those same two numbers instead of growing a
		# table of its own. A light target ARRIVES at you — that is an impact — while
		# a heavy one drags YOU, which is a sustained pull along the chain and a view
		# that leans in. So 缚 on a light enemy and 缚 on a pillar do not feel alike,
		# even though one line of code does both.
		var target_share := float(response.get("target_share", 0.5))
		var player_share := float(response.get("player_share", 0.45))
		camera_feedback.add_trauma(0.10 * (0.6 + target_share))
		camera_feedback.fov_kick(-moveset.taut_fov * (0.5 + player_share))
		var rel := wrapf(_azimuth - _facing_azimuth(), -PI, PI)
		camera_feedback.add_impulse(Vector2(-sin(rel) * 0.05, -0.018) * (0.4 + player_share))
	message.emit("缚 · BOUND %.2fs  (%s)" % [seconds, String(weight_of(_hook_actor))])
	bound.emit(_hook_actor, seconds)
	return true


func _start_orbit() -> bool:
	active_move = moveset.get_move(&"ch_orbit")
	if active_move == null:
		return false
	state = State.ORBITING
	state_time = 0.0
	_orbit_hold = 0.0
	_orbit_hit_timer = 0.0
	_hit_targets.clear()
	_pose_from = _pose_now()
	_pose_start = _pose_from
	_pose_end = _pose_from
	# The circle starts where the head already is and unwinds from there, so
	# holding Heavy never snaps the chain to a pose it was not already in.
	message.emit("蓄势 · ORBIT")
	return true


func _launch() -> bool:
	var move := moveset.get_move(moveset.heavy_id)
	if move == null:
		return false
	var ratio := clampf(_orbit_hold / maxf(moveset.orbit_max_hold, 0.001), 0.0, 1.0)
	if not _start(moveset.heavy_id):
		return false
	# Charge buys FORCE, not extra reach: a thrown chain always reaches its limit,
	# because the taut snap at the end is how the player meets TENSION at all.
	#
	# The throw is released TOWARD THE AIM (§13), so the azimuth moves to where
	# the player is facing. That is a 0.06s travel, not a jump — startup lerps the
	# head there, so the chain whips round instead of appearing on the other side.
	_azimuth = _facing_azimuth()
	_pose_start = Vector3(_azimuth, maxf(moveset.orbit_radius, radius), moveset.orbit_height)
	_pose_end = Vector3(_azimuth, moveset.max_radius, 1.05)
	message.emit("甩星 · LAUNCH %.0f%%" % (ratio * 100.0))
	return true


func _start(id: StringName) -> bool:
	var move := moveset.get_move(id)
	if move == null:
		return false
	if move.requires_taut and not is_taut():
		return false
	active_move = move
	state = _state_for(move)
	state_time = 0.0
	move_hit = false
	_hit_targets.clear()
	_pull_done = false
	_idle_time = 0.0
	# A new technique gets a clean arc: the bend a previous landing left in the last
	# one is the last one's business, and carrying it forward would let three hits
	# walk a 横缚 off the front of the player.
	_deflect = 0.0
	_deflect_target = 0.0
	momentum = minf(moveset.momentum_max, momentum + move.momentum_gain)
	_radius_scale = 1.0 + moveset.radius_momentum_scale * momentum
	_duration = move.active_seconds(momentum)
	_strike_end = move.startup + _duration
	_move_end = _strike_end + move.recovery
	_pose_from = _pose_now()
	_reach_end = radius
	var start_az := (
		_azimuth + _carry_anticipation(move) if move.continue_from_head
		else _facing_azimuth() + deg_to_rad(move.start_azimuth_degrees)
	)
	var start_h := move.height_from
	if move.path == ChainMove.Path.SLAM and move.peak_height > 0.0:
		start_h = move.peak_height
	_pose_start = Vector3(start_az, move.radius_from, start_h)
	_pose_end = Vector3(start_az + deg_to_rad(move.arc_degrees), move.radius_to, move.height_to)
	# Where the player was looking when the technique was committed to. Steer is
	# measured from here, so the arc can follow your turn without the end of a
	# 145° sweep sliding out from under it.
	_steer_base = _facing_azimuth()
	if camera_feedback != null:
		if not is_zero_approx(move.camera_trauma):
			camera_feedback.add_trauma(move.camera_trauma)
		if not is_zero_approx(move.fov_kick):
			camera_feedback.fov_kick(move.fov_kick)
		if not is_zero_approx(move.roll_kick):
			camera_feedback.roll_impulse(move.roll_kick)
	move_started.emit(move)
	_announce(_move_event(move), {"move": move.id, "radius": radius})
	return true


# Which of §30's moments a technique is. Not a second state machine: the answer is
# already in the data (does it hook, does it come down), which is why this is three
# lines and not a table.
func _move_event(move: ChainMove) -> StringName:
	if move.hooks:
		return EV_THROW
	if move.path == ChainMove.Path.SLAM:
		return EV_SLAM
	return EV_RATTLE


func _on_active() -> void:
	if _pull_done or active_move == null or not active_move.pulls:
		return
	_pull_done = true
	if not is_hooked():
		return
	# 曳: the same pull, taken early and at a discount. 缚 is the full snap.
	_apply_pull(moveset.yank_share, moveset.hook_response_for(weight_of(_hook_actor)))


func _finish_move() -> void:
	var move := active_move
	active_move = null
	if move != null and not move_hit and move.momentum_whiff_cost > 0.0:
		# A whiff costs the spin. If missing were free, the chain would just be a
		# wide sword — the same reason 回风 loses 势 when it cuts air.
		momentum = maxf(0.0, momentum - move.momentum_whiff_cost)
	if move != null and move.releases_hook:
		_release_hook()
	if move != null and move.deflects and Input.is_action_pressed(&"block"):
		# Holding the guard sweeps again. A chain deflect is a swung arc, not a
		# raised shield, so a held guard is a rhythm — and each swing gets its own
		# 截链 window rather than one window the player can camp in.
		_start(moveset.deflect_id)
		return
	if is_hooked():
		_enter_hooked()
		return
	if state == State.EXTENDING and _reach_end >= moveset.max_radius * moveset.tension_ratio:
		# A throw that reaches the end of the chain leaves it TAUT. This is the
		# weapon's signature and the only introduction to it the player ever gets.
		_enter_tension()
		return
	_retract()


func _enter_held() -> void:
	state = State.HELD
	state_time = 0.0
	active_move = null
	_hit_targets.clear()


func _enter_tension() -> void:
	state = State.TENSIONED
	state_time = 0.0
	_tension_left = moveset.tension_window
	_hit_targets.clear()
	# The chain is at its limit NOW, so it says so now. Waiting for _step_tension
	# to lerp the radius out would leave a window of a few frames in which the
	# weapon is in TENSIONED and `is_taut()` still answers no — and §16 hangs the
	# whole changed input map on that boolean, so a player who presses Light on the
	# frame the chain snaps tight would get 横缚 instead of 绷切.
	radius = moveset.max_radius
	_taut_height = _height
	# §15/§43: TENSION is a taut line AND a pull on the camera. The snap itself has
	# to be felt, so it gets the one moment of feedback a state change is allowed —
	# a jolt ALONG the chain's own bearing, never a turn toward the head (§30).
	var rel := wrapf(_azimuth - _facing_azimuth(), -PI, PI)
	if camera_feedback != null:
		camera_feedback.add_trauma(moveset.taut_snap_trauma)
		camera_feedback.fov_kick(-moveset.taut_fov)
		camera_feedback.add_impulse(Vector2(-sin(rel) * 0.02, -0.010))
	message.emit("链绷紧 · TENSION")


func _enter_hooked() -> void:
	state = State.HOOKED
	state_time = 0.0
	active_move = null
	_hit_targets.clear()


func _retract() -> void:
	_release_hook()
	state = State.RETRACTING
	state_time = 0.0
	active_move = null
	# AFTER `active_move` is cleared: `_pose_now` inverts `_apply_pose`, and from
	# here on every pose this state applies has no aim offset to undo.
	_pose_from = _pose_now()
	_hit_targets.clear()
	_announce(EV_RETRACT, {"radius": radius})


func _can_act() -> bool:
	match state:
		State.HELD, State.TENSIONED, State.HOOKED:
			return true
		State.SWINGING, State.EXTENDING, State.SLAMMING:
			return active_move != null and state_time >= _strike_end
		_:
			# ORBITING is a wind-up the player ends by releasing, not by cancelling.
			return false


# Throwing a hook or sweeping the guard OUT of a spin is allowed on purpose: the
# spin is momentum, and a chain player should be able to spend it.
func _can_start_now() -> bool:
	return state == State.ORBITING or _can_act()


func _state_for(move: ChainMove) -> State:
	match move.path:
		ChainMove.Path.RADIAL:
			return State.EXTENDING
		ChainMove.Path.SLAM:
			return State.SLAMMING
		_:
			return State.SWINGING


# ============================================================================
#  HEAD PLACEMENT
# ============================================================================

func _resolve_head(delta: float) -> void:
	var target := _head_position()
	if state in [State.SWINGING, State.EXTENDING, State.SLAMMING, State.ORBITING]:
		_head = _sweep_to(_head, target)
	else:
		_head = target
	_head_velocity = (_head - _head_prev) / maxf(delta, 0.0001)
	if chain_visual != null:
		chain_visual.update_chain(_hand_position(), _head, _head_velocity, tension, delta)
	_head_prev = _head


func _head_position() -> Vector3:
	var origin := _origin()
	return (
		origin
		+ Vector3(sin(_azimuth), 0.0, cos(_azimuth)) * radius
		+ Vector3.UP * _height
	)


func _apply_pose(p: Vector3) -> void:
	_azimuth = p.x
	# Reach is capped by the chain's own length. Momentum can extend a sweep; it
	# can never make the chain longer than it is, which is the rule that makes
	# TENSION a state rather than a number that keeps growing.
	radius = clampf(p.y * _radius_scale, moveset.min_radius * 0.35, moveset.max_radius)
	_height = p.z + _aim_pitch_offset(radius)


# THE POSE IN THE SPACE THE MOVES ARE AUTHORED IN — the exact inverse of
# `_apply_pose` under the move that is about to be applied.
#
# A handover is a lerp between "where the head is now" and "where the next
# technique is written to begin", so both ends have to be the same kind of number.
# They were not: `_pose_from` was read off the LIVE `radius` (already multiplied by
# `_radius_scale`) while every authored `radius_from` is not, so the moment momentum
# was carrying — three cuts in, `_radius_scale` ≈ 1.08 — the next cut's first frame
# re-applied the scale on top of an already-scaled number and the head hopped
# outward. Measured on the last clean tour: **13.1 m/s for one frame**, which is
# both a visible twitch and the reason the startup had no distance left to travel.
#
# This must be called AFTER `active_move` is set, because `_apply_pose` folds in
# the active move's own aim offset: with the same move on both sides the two
# cancel exactly, `_apply_pose(_pose_now())` is the identity, and a technique still
# cannot teleport the head. The aim offset is the one thing a
# `continue_from_head` handover must NOT inherit — it is the throw's business.
func _pose_now() -> Vector3:
	return Vector3(
		_azimuth,
		radius / maxf(_radius_scale, 0.0001),
		_height - _aim_pitch_offset(radius)
	)


# §13: THE THROW IS RELEASED TOWARD THE AIM.
#
# A chain that always leaves the hand at the same height can hook a pillar but never
# the top of one — which makes every raised thing in the world unhookable, including
# the high anchor §45 puts in the training ground. So a move may ask for the aim to
# tilt it, and the offset is `sin(pitch) * reach`: the head tracks the crosshair the
# way a thrown object would, and the amount is proportional to how far it has been
# thrown. Opt-in per move rather than always on, because a 横缚 that drifted upward
# whenever the player looked up would stop being a 145° sweep.
func _aim_pitch_offset(reach: float) -> float:
	var move := active_move
	if move == null or is_zero_approx(move.aim_pitch_scale):
		return 0.0
	if look_pivot == null:
		return 0.0
	return sin(look_pivot.rotation.x) * reach * move.aim_pitch_scale


func _lerp_pose(a: Vector3, b: Vector3, t: float) -> Vector3:
	# Startup takes the SHORT way round (wrapf), the active arc takes the long way
	# (a plain lerp). A 横缚 that went the short way would be a 215° sweep.
	return Vector3(
		a.x + wrapf(b.x - a.x, -PI, PI) * t,
		lerpf(a.y, b.y, t),
		lerpf(a.z, b.z, t)
	)


func _retract_pose() -> Vector3:
	return Vector3(
		_facing_azimuth() + deg_to_rad(moveset.home_azimuth_degrees),
		moveset.home_radius,
		moveset.home_height
	)


func _settle(t: float) -> float:
	var x := clampf(t, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)


# §7/§8 — WHERE A CARRY CUT'S ANTE COMES FROM.
#
# `continue_from_head` is not on its own enough, and measuring it is what proved
# that: starting the next arc "where the head already is" leaves the startup lerp
# travelling between two poses that are already the same pose, so the cut begins
# from a chain that does not move at all. Measured on the last clean tour, the head
# sat between 0.5 and 1.2 m/s for five frames at every handover against an arc peak
# of 117 — five frames of nothing is not a whip crack, it is three separate swings.
#
# A chain changing direction is not a chain that stops: the handle reverses, the
# head keeps going, the rope goes slack, and only then is the head snapped back the
# other way. That follow-through is the anticipation, and it is authored as degrees
# of OVERRUN measured against the new arc — so the data reads "26° more of the way
# it was already going before you reel it back", and it stays correct whichever
# direction the previous cut happened to end in.
func _carry_anticipation(move: ChainMove) -> float:
	if is_zero_approx(move.arc_degrees):
		return 0.0
	return -signf(move.arc_degrees) * deg_to_rad(move.carry_anticipation_degrees)


# A STARTUP THAT ARRIVES MOVING. `_settle` is smoothstep, which is the right shape
# for lowering the head home and the wrong one for handing it to an arc: it ends at
# zero velocity, and the arc it is handing over to begins at its fastest. The seam
# is a stop followed by a yank — the exact "three tweened swings" read of §8.
#
# Blending `_settle` with a linear tail keeps the shape (the head still eases off
# the pose it started in) but leaves it carrying `STARTUP_TAIL` of its own average
# speed at the boundary, so the arc's first frame is an ACCELERATION rather than a
# cold start.
#
# A CARRY CUT IS THE OTHER CASE, and that blend is wrong for it. Nothing is being
# delivered anywhere: the handle has already reversed (the inputs have), the head is
# coasting, the rope is going slack, and the whole startup exists to reach the
# instant the chain bites and hauls it back. Measured on that shape, the head went
# 0.66 → 0.40 → **0.19 → 0.37** m/frame across the 横缚 → 返扫 handover: it lost most
# of its speed dead at the cut and then PICKED IT BACK UP inside its own coast,
# which is a power stroke the chain is not delivering.
#
# A coast is uniform deceleration and can be written down: f(x) = (2−T)·x − (1−T)·x²
# over a startup of length S covers S·V̄ and has speed (2−T)·V̄ at the seam decaying
# to T·V̄. T is not a taste knob — the seam speed has to be the speed cut 1 handed
# over, and cut 1 arrives at 0.40 m/frame against an average of 0.29, i.e. ≈1.4·V̄,
# so 2 − T ≈ 1.4 and T = 0.6. Two things fall out of that: the handover inherits
# the previous cut's speed instead of restarting from it, and the coast is still
# moving (0.6·V̄) when the arc takes over — the chain bites a mass that is still
# travelling, which is what a reversal is, rather than one that has stopped. How FAR
# it coasts is the authored overrun in degrees; this only decides its shape.
const CARRY_TURN_SPEED := 0.60

func _startup_arrive(t: float, carrying: bool) -> float:
	var x := clampf(t, 0.0, 1.0)
	if carrying:
		return (2.0 - CARRY_TURN_SPEED) * x - (1.0 - CARRY_TURN_SPEED) * x * x
	return _settle(x) * (1.0 - STARTUP_TAIL) + x * STARTUP_TAIL


# Is this startup a COAST, or a delivery to a pose? Only a move that deliberately
# overruns is coasting. 返扫 does; 绷切/曳/拉近斩 share `continue_from_head` but start
# from a TAUT chain, which is stopped at full stretch by definition and hauls
# INWARD — so for them "start fast and decay" would be a pop away from the pull.
# Read off the data rather than off the state, so it cannot drift.
func _is_coasting(move: ChainMove) -> bool:
	return move.continue_from_head and not is_zero_approx(move.carry_anticipation_degrees)


func _origin() -> Vector3:
	# The point every polar coordinate is measured from: the player's FEET, so a
	# height in a ChainMove means the same thing to this weapon as it does to a
	# hurtbox standing on the same floor.
	return player.global_position - Vector3.UP * _foot_offset


func _measure_foot_offset() -> float:
	for child in player.get_children():
		var shape_node := child as CollisionShape3D
		if shape_node == null:
			continue
		var capsule := shape_node.shape as CapsuleShape3D
		if capsule != null:
			return capsule.height * 0.5
	return 0.0


func _facing_azimuth() -> float:
	var forward := -player.global_basis.z
	return atan2(forward.x, forward.z)


func _hand_position() -> Vector3:
	if hand != null:
		return hand.global_position
	return _origin() + Vector3.UP * 1.5 - player.global_basis.z * 0.5


func _update_tension(delta: float) -> void:
	var want := _tension_want()
	# ASYMMETRIC ON PURPOSE (§3). Coming up hard is the EVENT and happens fast;
	# paying back out is the rope relaxing and happens slower, because a chain that
	# let go as quickly as it tightened would be a spring.
	var rate := moveset.tension_rise if want > tension else moveset.tension_fall
	tension = move_toward(tension, want, rate * delta)
	if tension >= TENSION_START_AT and not _announced_start:
		_announced_start = true
		_announce(EV_TENSION_START, {"radius": radius, "ratio": radius / moveset.max_radius})
	elif tension < TENSION_START_AT - 0.15:
		_announced_start = false
	if tension >= TENSION_FULL_AT and not _announced_full:
		_announced_full = true
		_announce(EV_TENSION_FULL, {"radius": radius})
		_call_on_actor(_hook_actor, &"on_chain_tension", player)
	elif tension < TENSION_FULL_AT - 0.20:
		_announced_full = false
	var taut := is_taut()
	if taut != _was_taut:
		_was_taut = taut
		taut_changed.emit(taut)


# HOW STRAIGHT THE ROPE IS DRAWN. Not "is the weapon taut" — that is `is_taut()`,
# and it is a RULE. This is the picture, and the picture is of a rope.
func _tension_want() -> float:
	if _bite_left > 0.0:
		# The bite: the head has hold and the rope has not come up yet. Zero is
		# the point — a rope that snapped on the contact frame has no bite.
		return 0.0
	if state == State.HOOKED:
		# §17. What is caught is ATTACHED, not necessarily at the end of the rope,
		# so the drawing reads the rope it can actually see — and a hard haul pulls
		# it further up than standing still does, which is what makes 拉 read as a
		# pull rather than as a state the weapon happens to be in.
		var base := _snap_curve(radius / maxf(0.001, moveset.max_radius))
		return clampf(base + (1.0 - base) * _strain() * moveset.hook_strain_lift, 0.0, 1.0)
	if state == State.ORBITING:
		# §9. The whirling chain straightens as it spins up — one of the channels
		# that has to say THIS IS GETTING DANGEROUS.
		return maxf(
			_snap_curve(radius / maxf(0.001, moveset.max_radius)),
			moveset.orbit_straighten * momentum
		)
	return _snap_curve(radius / maxf(0.001, moveset.max_radius))


# §3's curve. Zero for the whole of the rope's spare length, then a cube up to
# straight across the last few percent — so the transition is a BEAT and not a
# smear, and a chain with a third of itself still coiled hangs exactly as loosely
# as one at rest.
func _snap_curve(ratio: float) -> float:
	var span := maxf(0.001, moveset.tension_ratio - moveset.tension_knee)
	var x := clampf((ratio - moveset.tension_knee) / span, 0.0, 1.0)
	return x * x * x


# §17's strain: how hard the rope is being opposed right now, as a fraction of a
# brisk walk. Zero while standing still — which is why a parked player sees the
# rope hang, and why walking away from what you caught pulls it dead straight.
func _strain() -> float:
	if _hook_actor == null or not is_instance_valid(_hook_actor):
		return 0.0
	var bearing := _hook_actor.global_position - player.global_position
	bearing.y = 0.0
	if bearing.length_squared() < 0.0001:
		return 0.0
	var travel := Vector3(player.velocity.x, 0.0, player.velocity.z)
	var pushed: Variant = player.get("external_velocity")
	if pushed is Vector3:
		travel += pushed
	return clampf(
		absf(travel.dot(bearing.normalized())) / maxf(0.001, moveset.strain_ref_speed),
		0.0, 1.0
	)


func _tension_reset() -> void:
	_was_taut = false
	tension = 0.0
	_announced_start = false
	_announced_full = false
	_bite_left = 0.0
	_bite_actor = null


func _decay_momentum(delta: float) -> void:
	# Only while the chain is not doing anything that feeds it. A three-cut chain
	# must not lose momentum between its own cuts, or the second cut would arrive
	# at the same speed as the first and 返扫 would mean nothing.
	if state in [State.HELD, State.RETRACTING, State.TENSIONED]:
		momentum = maxf(0.0, momentum - moveset.momentum_decay * delta)
		_radius_scale = 1.0 + moveset.radius_momentum_scale * momentum


func _update_feedback(delta: float) -> void:
	_probe_dev_mode(delta)
	if camera_feedback == null:
		return
	# FOV PRESSURE, not a camera orbit (§30/§31). The view widens as the chain
	# spins up and snaps back the instant it is thrown; the camera itself never
	# turns to follow the head, because that is the one thing that would make this
	# weapon unplayable.
	if state == State.ORBITING:
		camera_feedback.sustain_fov = moveset.orbit_fov * momentum
	elif tension >= moveset.taut_feel_threshold:
		# A LOADED LINE LEANS IN. The squeeze is negative — the view tightens while
		# the chain is at its limit and lets go when the pressure is spent, which is
		# the sustained half of §43's camera channel (the snap in _enter_tension is
		# the transient half). Small on purpose: this must be felt, not read.
		camera_feedback.sustain_fov = -moveset.taut_fov
	else:
		camera_feedback.sustain_fov = 0.0


# §46: is a developer looking? Cached, and re-probed on a slow timer rather than
# every frame — this runs sixty times a second and a full tree search does not
# belong in a frame budget for a debug label.
func _probe_dev_mode(delta: float) -> void:
	if debug_readout:
		return
	_dev_probe_timer -= delta
	if _dev_panel != null and is_instance_valid(_dev_panel):
		return
	if _dev_probe_timer > 0.0:
		return
	_dev_probe_timer = DEV_PROBE_INTERVAL
	var tree := get_tree()
	if tree == null:
		return
	_dev_panel = tree.root.find_child("DeveloperPanel", true, false)


# The panel's own container is what F8 shows and hides, so this asks THAT rather
# than the panel node — which is present and invisible whenever the panel is closed.
func dev_readout_on() -> bool:
	if debug_readout:
		return true
	if _dev_panel == null or not is_instance_valid(_dev_panel):
		return false
	var container: Variant = _dev_panel.get("panel")
	if container is Control:
		return (container as Control).visible
	return false


func _nudge_camera(direction: Vector2, trauma: float) -> void:
	if camera_feedback == null:
		return
	camera_feedback.add_impulse(direction)
	camera_feedback.add_trauma(trauma)


# One named moment, on its way to whoever makes the sound (§30). Nothing in this
# file knows what a sound is; it only knows WHEN.
func _announce(event: StringName, data: Dictionary = {}) -> void:
	chain_event.emit(event, data)


# ============================================================================
#  HIT DELIVERY
# ============================================================================

func _sweep_to(from: Vector3, to: Vector3) -> Vector3:
	var profile := active_move
	if profile == null:
		return to
	var space := get_world_3d().direct_space_state
	if space == null:
		return to
	var seg := to - from
	var dist := seg.length()
	var resolved := to
	# 1) SOLID WORLD. The head must not pass through anything solid (§21). Bodies
	#    that can be hit are excluded: an enemy is a TARGET, not a wall, and if it
	#    stopped the head then one sweep could never pass through two of them.
	if dist > 0.0001:
		var query := PhysicsRayQueryParameters3D.create(from, to, WALL_MASK, _sweep_exclude(profile.hooks))
		query.collide_with_areas = false
		query.collide_with_bodies = true
		var hit := space.intersect_ray(query)
		if not hit.is_empty():
			var normal: Vector3 = hit.get("normal", Vector3.UP)
			resolved = hit.get("position") + normal * moveset.head_radius
			_on_wall_hit()
	# 2) TARGETS. A sphere sampled along the segment, because a head doing 20 m/s
	#    moves 0.33m per frame and would otherwise tunnel straight through a 0.8m
	#    enemy without ever overlapping it.
	var steps := maxi(1, int(ceil(dist / maxf(0.05, moveset.head_radius * 0.9))))
	for s in range(1, steps + 1):
		var point := from.lerp(resolved, float(s) / float(steps))
		if _hit_sphere(point, profile):
			break
	return resolved


func _hit_sphere(point: Vector3, profile: ChainMove) -> bool:
	# Returns true only when the sampling must STOP — which only a hook does,
	# because the chain has attached and there is nothing left to sweep. A wide
	# sweep must keep sampling: hitting two enemies with one 横缚 is the weapon's
	# whole promise, and `_hit_targets` already stops the same actor twice.
	var space := get_world_3d().direct_space_state
	if space == null:
		return false
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = _head_shape
	params.transform = Transform3D(Basis.IDENTITY, point)
	params.collision_mask = HURTBOX_MASK
	params.collide_with_areas = true
	params.collide_with_bodies = false
	for result in space.intersect_shape(params, 8):
		var collider: Object = result.get("collider")
		if not (collider is CombatHurtbox):
			continue
		var area: CombatHurtbox = collider
		var actor: Node3D = area.owner_actor
		if actor == null or actor == player or _hit_targets.has(actor):
			continue
		_hit_targets.append(actor)
		if profile.hooks:
			# Hook delivery: the chain does not strike the target, it ATTACHES to
			# it. Damage comes later, and only if the player asks for it.
			_attach(actor, point)
			return true
		_deliver(actor, area, profile)
	return false


func _deliver(actor: Node3D, area: CombatHurtbox, profile: ChainMove) -> void:
	var hit := {
		"damage": profile.damage,
		"poise_damage": _poise_for(profile, actor),
		"element": profile.element_id,
		"element_scale": 1.0,
		"impulse": profile.impulse,
		"source": player,
		"target": actor,
	}
	move_hit = true
	hits_landed += 1
	area.receive_hit(hit)
	hit_landed.emit(profile, hit)
	_announce(EV_CONTACT, {"move": profile.id, "target": actor, "weight": weight_of(actor)})
	_pay_for_the_impact(profile, weight_of(actor))


# HOW HARD THE HEAD ARRIVED, as a ratio: 0 at a crawl, 1 at impact_speed_ref, more
# beyond it. Everything about a landing reads off this, which is what keeps "the
# chain has weight" a property of the physics rather than a table of juice values.
func _impact_strength(profile: ChainMove) -> float:
	return clampf(_head_velocity.length() / maxf(0.001, moveset.impact_speed_ref), 0.0, 1.6)


# THE HEAD HAS MASS, SO LANDING ON SOMETHING COSTS IT (§43 IMPACT).
#
# A whip does not care what it hits. This does: it hands momentum to whatever it
# lands on, so it keeps less of its own, it is knocked off its arc, and the world
# stops for a beat that is longer the faster it arrived. All three are scaled by the
# WEIGHT of the thing it hit — the same table the pull uses, because how heavy
# something is is a fact about that thing and there is only one place that says so.
#
# The consequence in play is the point: mowing down light enemies is cheap and keeps
# the chain spinning, while spending a throw on a heavy body takes the spin and
# gives back a thud. 实链's currency is momentum (§12), so this is where the weapon
# charges for its power.
func _pay_for_the_impact(profile: ChainMove, weight: StringName) -> void:
	var strength := _impact_strength(profile)
	var speed_share := minf(1.0, strength)
	var cost_scale := float(moveset.impact_cost_by_weight.get(weight, 1.0))
	if profile.impact_momentum_cost > 0.0 and cost_scale > 0.0:
		momentum = maxf(
			0.0,
			momentum - profile.impact_momentum_cost * cost_scale * lerpf(0.6, 1.0, speed_share)
		)
		_radius_scale = 1.0 + moveset.radius_momentum_scale * momentum
	var deflect_scale := float(moveset.impact_deflect_by_weight.get(weight, 1.0))
	if profile.impact_deflect_degrees > 0.0 and deflect_scale > 0.0:
		# Off the arc, the way it was already going. A head with no angular travel
		# to speak of (a straight thrust) has no line to be knocked off, so it gets
		# nothing rather than an invented direction.
		var side := signf(_azimuth_vel)
		if not is_zero_approx(side):
			_deflect_target += side * deg_to_rad(profile.impact_deflect_degrees * deflect_scale)
	var hitstop_scale := _hitstop_scale()
	if profile.impact_hitstop > 0.0 and hitstop_scale > 0.0 and time_effects != null:
		time_effects.request_hitstop(
			profile.impact_hitstop
				* lerpf(moveset.impact_hitstop_min, moveset.impact_hitstop_max, speed_share)
				* hitstop_scale
		)
	if camera_feedback != null:
		# The camera admits the impact rather than the technique: the same 横缚 that
		# rolls off a light enemy lands differently when it stops against a heavy one.
		camera_feedback.add_trauma(profile.camera_trauma * lerpf(0.7, 1.7, speed_share))
		if profile.impulse >= 2.0 and strength > 0.5:
			camera_feedback.add_impulse(Vector2(0.008, -0.012) * lerpf(0.6, 1.3, speed_share))


# The developer panel's hitstop preset belongs to the PLAYER, not to a weapon, so the
# chain honours it too — asked for rather than copied, exactly like the weight
# contract. 0 means "no hitstop at all", which is how that control already reads.
func _hitstop_scale() -> float:
	var combat := get_parent().get_node_or_null("CombatController")
	if combat == null:
		return 1.0
	var value: Variant = combat.get("hitstop_scale")
	if value == null:
		return 1.0
	return float(value)


# MAGIC x CHAIN, interaction 2 of 2. A pull is the best way to apply force to
# something whose material is already compromised — and WHICH element pays off is
# named in the moveset, so no weapon is hard-bound to an element (brief §44) and
# this file never has to know what "frost" means.
func _poise_for(profile: ChainMove, actor: Node3D) -> float:
	var poise := profile.poise_damage
	if not profile.pulls or moveset.pull_poise_elements.is_empty():
		return poise
	if not actor.has_method("element_stage"):
		return poise
	for element in moveset.pull_poise_elements:
		var stage: StringName = actor.call("element_stage", element)
		var index := _stage_index(element, stage)
		if index >= moveset.pull_poise_min_stage:
			return poise * moveset.pull_poise_scale
	return poise


func _stage_index(element: StringName, stage: StringName) -> int:
	if stage == &"":
		return -1
	var def := ElementLibrary.get_element(element)
	if def == null:
		return -1
	return def.stage_names.find(stage)


func _on_wall_hit() -> void:
	wall_hits += 1
	last_wall_impact = clampf(_head_velocity.length() / 6.0, 0.2, 1.5)
	# Metal on stone costs the spin. If a throw into a wall were free, the chain
	# would have no reason to respect the space it is thrown through.
	momentum = maxf(0.0, momentum * 0.30)
	if camera_feedback != null:
		camera_feedback.add_trauma(0.07 * last_wall_impact)
	wall_impact.emit(last_wall_impact)
	if active_move != null and active_move.deflects:
		# A guard arc stays a guard arc. Clamping is enough; retracting would turn
		# standing near a wall into losing your defence.
		return
	# Everything else STOPS at the wall. The head has already been clamped to the
	# contact point this frame, so nothing is ever placed inside geometry — and
	# retracting now, rather than re-deriving a pose that pushes further out, is
	# what stops a thrown chain from tunnelling through the second frame.
	message.emit("撞墙 · WALL")
	_announce(EV_WALL, {"strength": last_wall_impact})
	_retract()


func _attach(actor: Node3D, contact: Vector3) -> void:
	_hook_actor = actor
	_hook_offset = actor.global_transform.affine_inverse() * contact
	# §14 LOCAL ATTACH POINT. The offset above is kept in the ACTOR'S OWN space,
	# which is why the head stays on the shoulder it caught when the body turns
	# instead of sliding round to whatever this file thinks the centre is. For a
	# parked dummy that is nearly invisible; for an enemy mid-swing it is the
	# difference between a chain and a magnet.
	if actor.has_method("on_chain_hooked"):
		# Being caught mid-swing and dragged off balance is the reward for landing
		# the throw, so the target is told about it rather than merely damaged.
		actor.call("on_chain_hooked", player)
	var weight := weight_of(actor)
	message.emit("缠锁 · HOOKED  (%s)" % String(weight))
	# §13's SECOND beat, and it is not the same moment as the first: the head has
	# ARRIVED. Whether it has HOLD of anything is the bite, which is announced a
	# few frames later — see _step_bite.
	_announce(EV_CONTACT, {"target": actor, "weight": weight, "hooking": true})
	_call_on_actor(actor, &"on_chain_contact", player)
	_bite_left = moveset.hook_bite_time
	_bite_actor = actor
	_enter_hooked()
	hooked.emit(actor, weight)


# §36: THE ELEMENT HOOKS, and nothing else. This pass keeps the NEUTRAL chain and
# only leaves the verbs where a Frost or Wind modifier will one day find them —
# called duck-typed, on the actor, so a chain that is hooked to something with no
# element system is not a special case and this file never learns what frost means.
func _call_on_actor(actor: Node3D, verb: StringName, source: Node3D) -> void:
	if actor == null or not is_instance_valid(actor):
		return
	if actor.has_method(verb):
		actor.call(verb, source)


func _release_hook() -> void:
	if _hook_actor != null and is_instance_valid(_hook_actor) and _hook_actor.has_method("on_chain_released"):
		_hook_actor.call("on_chain_released")
	_hook_actor = null
	bound_left = 0.0
	# NOTE: the haul is deliberately NOT cancelled here. A yank already in flight is a
	# physical event on the body — once the rope has been pulled, the body's momentum
	# does not care that the chain let go a moment later — and 地砸/拉近斩 pull AND
	# release, so cancelling on release would have those two techniques retract their
	# own haul and deliver nothing. Only a reset (weapon away, state wiped) stops one.


# The weight table, applied. THIS is brief §18 and it is the reason a chain is
# not "pull everything to me": the same input on a light enemy drags it to the
# player, on a medium enemy closes both, and on a heavy enemy does not move the
# enemy AT ALL — it moves the player, because a heavy enemy is an ANCHOR.
#
# This function ARMS the haul and does not perform it. The distance is paid out by
# _step_tugs() in diminishing yanks, because a pull delivered in one displacement is
# a snap-to: it moves the body the right distance and tells the player nothing about
# what was on the end of it. See ChainMoveset's 顿挫 block.
func _apply_pull(share: float, response: Dictionary) -> void:
	if not is_hooked():
		return
	var toward_player := player.global_position - _hook_actor.global_position
	toward_player.y = 0.0
	if toward_player.length_squared() <= 0.0001:
		return
	_tug_dir = toward_player.normalized()
	_tug_total = moveset.pull_distance * share
	_tug_target_share = float(response.get("target_share", 0.5)) * share
	_tug_player_share = float(response.get("player_share", 0.45)) * share
	_tug_step = 0
	_tug_left = maxi(1, moveset.pull_tugs)
	# First yank lands on the frame the pull was asked for: the catch and the haul
	# are one motion, and a gap in front of it would read as the chain hesitating.
	_tug_timer = 0.0


# Paying out the haul. Runs for every state on purpose — a pull that only advanced
# while the move that started it was playing would strand its own last yank when the
# technique ended first.
func _step_tugs(delta: float) -> void:
	if _tug_left <= 0:
		return
	_tug_timer -= delta
	if _tug_timer > 0.0:
		return
	var curve := moveset.pull_tug_curve
	var amount := float(curve[mini(_tug_step, curve.size() - 1)]) if not curve.is_empty() else 1.0
	_deliver_tug(amount)
	_tug_step += 1
	_tug_left -= 1
	_tug_timer = moveset.pull_tug_gap


func _deliver_tug(amount: float) -> void:
	if amount <= 0.0:
		return
	var actor := _hook_actor
	var target_move := _tug_dir * _tug_total * _tug_target_share * amount
	var player_move := -_tug_dir * _tug_total * _tug_player_share * amount
	var moved_something := false
	tug.emit(_tug_step + 1, moveset.pull_tugs, amount)
	_announce(EV_YANK, {"step": _tug_step + 1, "total": moveset.pull_tugs, "amount": amount})
	if target_move.length_squared() > 0.0 and actor != null and is_instance_valid(actor) \
			and actor.has_method("chain_pull"):
		# A body that takes a displacement takes it whole: no compensation, no
		# residual, one move per yank.
		actor.call("chain_pull", target_move)
		moved_something = true
		_call_on_actor(actor, &"on_chain_yank", player)
	if player_move.length_squared() > 0.0:
		# A DISPLACEMENT, not a speed: this file knows how far a 缨拉 should move
		# the player, and the movement code owns how that becomes motion. Asking
		# for a velocity instead made the number meaningless — 9 m/s of impulse
		# through the walk solver's decay is 0.35m, which is not "pulled forward".
		#
		# Each yank asks for ITS OWN SHARE and nothing else, and the sum of the
		# shares is 1.0, so a haul of five yanks moves the body exactly as far as a
		# haul of one would. That is now literally true rather than nearly true:
		# `PlayerMovement.pull()` used to leak a factor of 15 through its own walk
		# solver (see the note there), which is why this function once carried a
		# `(1 - residual)` correction. Fixing the leak made the correction wrong in
		# the other direction, so it was deleted, not retuned — and the RHYTHM of a
		# pull is now a free choice instead of something the budget paid for.
		if player.has_method("pull"):
			player.call("pull", player_move)
			moved_something = true
		elif player.has_method("push"):
			# A body without pull() gets the same travel by asking for the matching
			# speed, which only works if its decay is the same PUSH_DECAY.
			player.call("push", player_move * PULL_TO_SPEED)
			moved_something = true
	if not moved_something:
		return
	# 顿挫, sold. Each yank is a stop, a shove and a camera jolt; the chain's windows
	# ride `state_time`, which is delta-accumulated, so freezing delta freezes the
	# tug and the technique together and the sequence resumes exactly where it was.
	if time_effects != null and not is_zero_approx(moveset.pull_tug_hitstop):
		time_effects.request_hitstop(moveset.pull_tug_hitstop)
	if camera_feedback != null:
		if not is_zero_approx(moveset.pull_tug_trauma):
			camera_feedback.add_trauma(moveset.pull_tug_trauma)
		if not is_zero_approx(moveset.pull_tug_impulse):
			# Sign follows who moved: hauling something in shoves the view forward,
			# being hauled in drags it back, and the player reads which one it was
			# from the jolt before they read it from the debug line.
			var along := player_move.normalized().dot(-player.global_transform.basis.z)
			camera_feedback.add_impulse(
				Vector2(0.0, -moveset.pull_tug_impulse * along)
			)


func _clear_tugs() -> void:
	_tug_left = 0
	_tug_step = 0
	_tug_timer = 0.0
	_tug_total = 0.0


# Everything the head must NOT treat as a wall.
#
# The player's own body is first: a chain thrown from the hand starts inside it.
# Enemies and crates follow, because an enemy or a crate is a TARGET, not terrain
# — if either stopped the head, one 横缚 could never pass through two of them.
#
# FIXED ANCHORS ARE THE EXCEPTION, and only for a hook: a pillar must stop an
# ordinary sweep (a chain cannot pass through stone), but a HOOK has to be able to
# reach the pillar's surface or §20 is unreachable. So they leave the wall set
# exactly when the technique is a throw.
func _sweep_exclude(hooking: bool) -> Array[RID]:
	var out: Array[RID] = []
	if player is CollisionObject3D:
		out.append((player as CollisionObject3D).get_rid())
	for group in [CombatTuning.TARGET_GROUP, CombatTuning.PROP_GROUP]:
		for node in get_tree().get_nodes_in_group(group):
			if node is CollisionObject3D:
				out.append((node as CollisionObject3D).get_rid())
	if hooking:
		for node in get_tree().get_nodes_in_group(CombatTuning.ANCHOR_GROUP):
			if node is CollisionObject3D:
				out.append((node as CollisionObject3D).get_rid())
	return out
