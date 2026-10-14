extends Node3D
class_name SayaHandDriver
# SEKAI · THE LEFT HAND, AS A CONTROL POINT
#
# ===========================================================================
# WHY THIS EXISTS
# ===========================================================================
# The scabbard has now been wrong in both directions, and the two faults have the
# same root: nothing in the rig represented THE HAND.
#
#   Pass A  the saya was DERIVED from the sword's proximity to the seating
#           anchor. Measured at 0.20-0.22 m of scabbard travel per cut, and
#           76 mm of it in a single update. A scabbard that moves when the blade
#           does is a scabbard nobody is holding.
#
#   Pass B  the derivation was deleted and the saya was pinned to one authored
#           point. Measured at 0.0000 m of travel per cut — correct as an answer
#           to "stop following the blade", and wrong as an answer to "is this a
#           held object". A scabbard that never moves is a scabbard-shaped prop
#           welded to the camera.
#
# Both are the same missing thing: `Sword Transform -> Saya`, or
# `constant -> Saya`. Neither of those is `Hand -> Saya`. So this node is the
# hand, and it is the only thing the scabbard is ever placed relative to:
#
#     saya := hand(this)  +  authored control offset  +  (nothing else)
#
# ===========================================================================
# WHAT THE HAND IS MADE OF
# ===========================================================================
# The player rig has no arm. Confirmed, not assumed: `scenes/player/Player.tscn`
# is a camera rig with a `WeaponRoot`, the only forearm-shaped thing anywhere in
# the project is the chain's `ChainHandAnchor`, and the review renderer's idea of
# a body is a capsule with a wedge for a nose. So this node is the hand's CONTROL
# POINT rather than its palm — the point the scabbard's mouth is held at — and
# its transform is built from the three things a real left hand would contribute:
#
#   1  THE AUTHORED POSE. Where the hand holds the scabbard when nothing is
#      happening. Set from `SwordBasic.saya_home` / `SAYA_MOUTH_R` so the rest
#      pose and the seating anchor are one expression and cannot drift.
#
#   2  BREATHING (§5). 0.5-1.5 cm and 1-2 degrees, on two incommensurate
#      frequencies so it does not read as a loop. The point is not decoration:
#      it is the difference between "a person is holding this" and "this is
#      parented to the camera", and it cannot be told from a still frame.
#
#   3  INERTIA (§6). The hand hangs off a body, so it arrives after the body
#      does and overshoots when the body stops. Driven by the body's own
#      velocity, integrated through a damped spring rather than scaled, because
#      "lag" is a lead and "overshoot" is a second-order response and only the
#      spring has both.
#
# NOTHING HERE EVER PRODUCES A LARGE MOTION, and that is a design constraint and
# not an accident: the scabbard's big moves are AUTHORED per move (§7-§17) and
# live in `SwordMove.saya_ctrl_*`. What this file adds is the small continuous
# life that makes the authored parts read as the same held object.
#
# ===========================================================================
# AND IT GOES COMPLETELY STILL WHEN THE BLADE IS AT THE MOUTH
# ===========================================================================
# `seat_pin` is the whole of that, and it is a distance rather than a state.
# Breathing 6 mm while a blade with `SwordClasses.FIT_CLEAR` = 1.75 mm of
# clearance is entering the mouth is not a subtlety, it is a blade through the
# wall — and the window in which it would happen is precisely the window in which
# the act is about the blade arriving. So the hand stops being alive before the
# blade gets there and starts again after it leaves, with no frame in which it is
# half-alive at the seat.

## The two frequencies, in radians per second. 1.9 is a slow breath (3.3 s) and
## 5.4 rides on it; they are not in a small whole-number ratio with each other or
## with anything else in the rig, which is what keeps the cycle from reading as a
## loop. §5's "非常轻" is the amplitude below, not the speed.
const BREATH_SLOW := 1.90
const BREATH_FAST := 5.40
## Metres, per axis. Each axis's two components sum to 8.0 / 9.8 / 5.8 mm of
## travel end to end, so every axis is inside §5's 0.5-1.5 cm band -- AND SO IS
## THE THREE OF THEM TOGETHER, WHICH THEY WERE NOT BEFORE.
##
## The first values were 0.0042/0.0052/0.0030 and 0.0016/0.0018/0.0011, and the
## comment above them said "the two components sum to a little under a centimetre
## of excursion, which is §5's 0.5-1.5 cm band measured rather than asserted".
## The arithmetic was per axis: 11.6, 14.0 and 8.2 mm. The MOUTH does not move per
## axis, though -- it moves in three at once -- and the cloud's diameter is
## 2 x |(0.0058, 0.0070, 0.0041)| = 19.9 mm, a third over the ceiling the comment
## claimed it was measuring. This is not a hypothetical: the Pass 02 take read
## 14.9 mm over a two-second hold and 19.9 mm is where it converges, against a
## 15 mm ceiling.
##
## Everything is scaled by 0.70, which puts the envelope at 13.9 mm -- inside the
## band rather than straddling its top edge -- and leaves both ends of §5's band
## with millimetres of margin instead of tenths:
##
##   worst case, all axes aligned   19.9 -> 13.9 mm   (ceiling 15)
##   a two-second hold              14.9 -> ~10.4 mm  (floor 5)
##   the widest `idle` leg in probe_saya_motion   9.6 -> ~6.7 mm
##
## No axis leaves the band on the low side, and the two frequencies are unchanged:
## 1.90 and 5.40 rad/s are incommensurate with each other and with the rest of the
## rig, which is what keeps the cycle from reading as a loop.
const BREATH_SWAY := Vector3(0.0029, 0.0036, 0.0021)
const BREATH_JITTER := Vector3(0.0011, 0.0013, 0.0008)
## Radians, per axis: about 1.8 degrees of total tilt at the extremes, inside
## §5's 1-2 degree band.
const BREATH_TILT := Vector3(0.0200, 0.0210, 0.0130)

## How long the body's velocity is worth, in seconds, when the hand is deciding
## where to hang. `velocity * LAG_GAIN` is the displacement, so 45 ms at a 5 m/s
## sprint is 22 cm of trail — a third of the scabbard's own length, which is the
## point at which a runner's sheath stops looking attached.
const LAG_GAIN := 0.045
## ...and the ceiling, because the same product at a dash would be absurd. A hand
## width.
const LAG_CLAMP := 0.085

## The spring the hand's own inertia is integrated through. `K`/`C` give
## zeta = C / (2 sqrt(K)) = 0.79 — visibly underdamped, which is what "overshoot
## when the body stops" means, and not so underdamped that it rings.
const SPRING_K := 90.0
const SPRING_C := 15.0

## How fast the hand fades between "being carried" and "holding a blade in place".
## 0.28 s is about a breath; shorter and the switch is visible, longer and the
## hand is still moving after the cut has started.
const LIVE_TAU := 0.28

## Where the hand holds the scabbard. Written by the controller from the same
## expression the seating anchor uses.
var base_position := Vector3.ZERO
var base_basis := Basis.IDENTITY

## 1 = only being carried (alive), 0 = the blade is home or a draw is running.
var live_target := 1.0
## 0 = the blade is nowhere near the mouth, 1 = the hand must be exact.
var seat_pin := 0.0

## The body's own velocity, in this node's parent frame. Fed by the controller
## from `player.velocity` rather than read here, so that a probe can hand this
## node a scripted motion and test the response on its own.
var body_velocity := Vector3.ZERO

var _live := 1.0
var _phase := 0.0
var _spring := Vector3.ZERO
var _spring_vel := Vector3.ZERO
var _seeded := false


func _ready() -> void:
	# BEFORE EVERYTHING THAT READS IT. `CombatController._drive_saya` reads this
	# node's transform to place the scabbard, and it runs in the same frame — so
	# the hand has to have been solved first or the scabbard is placed from last
	# frame's hand. Tree order would already give that (the camera rig precedes
	# the controller), but a priority states it instead of depending on it.
	process_priority = -10
	set_process(true)


func _process(delta: float) -> void:
	_phase += delta
	_live = _approach(_live, live_target, delta)
	# `freedom` is the one scalar that says how much of this node's own life is
	# allowed into the pose. Both ends are hard: 0 at the seat, 1 on a clean idle.
	var freedom := _live * (1.0 - clampf(seat_pin, 0.0, 1.0))

	var sway := Vector3(
		sin(_phase * BREATH_SLOW) * BREATH_SWAY.x
			+ sin(_phase * BREATH_FAST + 1.10) * BREATH_JITTER.x,
		sin(_phase * BREATH_SLOW * 0.77 + 2.30) * BREATH_SWAY.y
			+ sin(_phase * BREATH_FAST * 0.83 + 0.40) * BREATH_JITTER.y,
		sin(_phase * BREATH_SLOW * 0.59 + 0.70) * BREATH_SWAY.z
			+ sin(_phase * BREATH_FAST * 1.21 + 2.70) * BREATH_JITTER.z)
	var tilt := Vector3(
		sin(_phase * BREATH_SLOW * 1.13 + 0.50) * BREATH_TILT.x,
		sin(_phase * BREATH_SLOW * 0.86 + 2.00) * BREATH_TILT.y,
		sin(_phase * BREATH_FAST * 0.50 + 3.30) * BREATH_TILT.z)
	# The hand trails the body. `-velocity` because a body that moves forward
	# leaves its hand behind it.
	var trail := (-body_velocity * LAG_GAIN).limit_length(LAG_CLAMP)

	var desired := base_position + (sway + trail) * freedom

	if not _seeded:
		# First frame: start ON the answer. A spring that starts at the origin
		# spends its first half-second travelling from wherever the scene
		# happened to be to where the hand is, and every sample of that is a
		# scabbard in the wrong place.
		_spring = desired
		_spring_vel = Vector3.ZERO
		_seeded = true
	if freedom <= 0.0001:
		# Wound down. Park the integrator on the answer rather than letting it
		# keep a velocity it will release the moment the blade leaves: the
		# scabbard does not get to spring out of a hold.
		_spring = base_position
		_spring_vel = Vector3.ZERO
	else:
		_spring_vel += (-SPRING_K * (_spring - desired) - SPRING_C * _spring_vel) * delta
		_spring += _spring_vel * delta

	position = base_position.lerp(_spring, freedom)
	basis = Basis.from_euler(tilt * freedom) * base_basis


## Exponential approach with a time constant, the same shape the rig uses
## everywhere else. Written out rather than set as `lerp` so the constant is a
## SECONDS value, which is the only form in which it can be argued about.
func _approach(current: float, target: float, delta: float) -> float:
	if LIVE_TAU <= 0.0:
		return target
	return lerpf(current, target, 1.0 - exp(-delta / LIVE_TAU))


## Restarts the breath from zero and parks the spring. For a probe that wants to
## measure the response to one input rather than to the run's own history.
func reset_life() -> void:
	_live = live_target
	_phase = 0.0
	_spring = base_position
	_spring_vel = Vector3.ZERO
	_seeded = false
