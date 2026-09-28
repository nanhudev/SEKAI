extends Resource
class_name ChainMove
# ONE CHAIN ACTION, IN DATA.
#
# The head is always described the same way — an azimuth around the player, a
# radius, and a height. Every chain action is therefore the same three lerps with
# different numbers, which is why a wide sweep, a straight throw, a slam and a
# snap-back are one code path instead of four special cases. Adding a move means
# adding a resource, not a branch.
#
# WHY THERE IS NO `damage_multiplier_FOR_MOMENTUM` HERE: momentum buys SPEED and
# a little REACH, never a flat damage stat. 缚星链 teaches Space / Momentum. If
# its reward for spinning up were a bigger number it would just be a sword with a
# longer reach, which is the one outcome the design brief calls a failure.

enum Path {
	ARC,     # the head travels a swept angle (sweeps, deflect)
	RADIAL,  # the head travels in/out along its own azimuth (throw, launch, snap, yank)
	SLAM,    # the head rises during startup, then comes down (下砸, 地砸)
}

enum Ease { LINEAR, OUT, IN_OUT, IN, WHIP }
# How much of its own speed the head still has when an arc ENDS. See Ease.WHIP.
const WHIP_TAIL := 0.32

@export_group("Identity")
@export var id: StringName = &""
@export var display_name := ""
@export var path: Path = Path.ARC
@export var note := ""

@export_group("Timing")
@export var startup := 0.12
@export var active := 0.20
@export var recovery := 0.22

@export_group("Hit")
@export var damage := 14.0
@export var poise_damage := 14.0
@export var element_id: StringName = &"physical"
@export var impulse := 1.6

@export_group("Geometry")
# Where the arc begins, relative to where the player is facing, in degrees.
# A 145° sweep authored from -72.5 therefore straddles the centre line.
@export var start_azimuth_degrees := 0.0
# §13: HOW MUCH THE AIM TILTS THIS MOVE. 0 means the move owns its height entirely,
# which is what almost everything wants — a 横缚 that drifted upward whenever the
# player looked up would stop being a 145° sweep. 1.0 on a throw means the head goes
# exactly where the crosshair points: `sin(pitch) * reach` of elevation, so looking
# up 30° while throwing four metres puts the head two metres higher, and a raised
# anchor becomes something the weapon can actually reach.
@export var aim_pitch_scale := 0.0
# 返扫 must pick the head up where the previous cut left it. Setting this means
# start_azimuth_degrees is ignored — the head is already moving, and asking it to
# jump back to a start pose is exactly the "teleport" the brief forbids.
@export var continue_from_head := false
# §7/§8 — HOW FAR THE HEAD OVERRUNS BEFORE A CARRY CUT REVERSES IT.
#
# `continue_from_head` on its own starts the next arc where the head already is,
# which is a startup lerp between two identical poses: the cut begins from a chain
# that does not move. Measured, that was five frames at 0.5–1.2 m/s at every
# handover against an arc peak of 117 — three separate swings, not one sentence.
#
# The momentum the previous cut left has to go somewhere, and where it goes is the
# follow-through: the handle reverses, the head carries on, the rope opens, and
# only then is the head snapped back. Authored as degrees of overrun and applied
# AGAINST the new arc, so the data says "keep going 25° further, then reel it
# back" and stays correct whichever way the previous cut ended. See
# `ChainDirector._carry_anticipation`.
@export var carry_anticipation_degrees := 0.0
@export var arc_degrees := 145.0
# §A2 — THE SECOND ARC, INSIDE THE SAME INPUT.
#
# 快右左 is not two presses. It is one press that takes the head to the right-hand
# extreme and then, without stopping, brings it back through the left — and that
# is not expressible as a longer single arc, because a 300° arc passes through the
# FRONT, which is a different motion entirely. So a move may author a second arc
# and `arc_split` says at what fraction of the active window the reversal happens.
# Zero means "one arc", which is every other move in the weapon.
@export var arc_degrees_2 := 0.0
@export var arc_split := 0.45
@export var radius_from := 2.5
@export var radius_to := 3.4
@export var height_from := 1.15
@export var height_to := 1.05
# SLAM only: where the head is held during startup, before it falls.
@export var peak_height := 0.0
@export var ease: Ease = Ease.OUT
@export var ease_power := 2.2

@export_group("Momentum")
@export var momentum_gain := 0.30
# A whiff costs the spin. Missing has to cost something or the chain is just a
# wide sword, and the same is true of every style in this project.
@export var momentum_whiff_cost := 0.12
# How much of the momentum-driven duration bonus this move accepts. A sweep is
# visibly faster at full spin; a hook is not, because a throw is aimed.
@export var momentum_speed_scale := 0.45
# How much the head follows the player's look during the move. 0 = the chain has
# its own opinion, 1 = the player owns it completely. Neither extreme is good.
@export var steer := 0.35

@export_group("Behaviour")
@export var requires_taut := false
@export var hooks := false
@export var pulls := false
@export var deflects := false
# Reeling the head all the way back in lets go of whatever it was holding. This
# is how 拉近斩 and 地砸 end a 缚 instead of leaving the chain attached forever.
@export var releases_hook := false

@export_group("Weight")
# WHAT LANDING COSTS THE HEAD (§43 IMPACT).
#
# A weighted head behaves differently from a whip, and the difference is that it
# PAYS for its hits: it transfers momentum into whatever it lands on and keeps
# less of it itself. A chain that mows down a light enemy should still be spinning
# afterwards; one that slams into a heavy body should be nearly stopped by it —
# because that is the only way "I am swinging a mass" is something the player can
# feel rather than something the design document claims.
#
# It is also the second half of 实链's spatial rule: speed is the currency, and
# heavy targets are expensive to spend it on.
@export var impact_momentum_cost := 0.05
# The 顿 of a landing. Scaled by how fast the head was going when it arrived, and
# by how heavy the thing it hit was, because both of those ARE "impact".
@export var impact_hitstop := 0.032
# How far the arc is knocked off course by a landing at the reference weight. A
# head that hits something does not continue along a painted line — it is a
# collision, and it looks like one.
@export var impact_deflect_degrees := 5.0

@export_group("Feedback")
@export var camera_trauma := 0.05
@export var fov_kick := -1.2
@export var roll_kick := 0.0


# §A2 — THE EASE OF A TURNAROUND SEGMENT, AND IT IS NOT `eased()`.
#
# `Ease.WHIP` exists to keep velocity ACROSS A HANDOVER: two techniques, one
# chain, and the second must not start from a stopped mass. A turnaround is the
# opposite problem — one technique, and the head really does reach the end of its
# swing and come back. At an extreme the speed passes through zero, so the honest
# ease is one that arrives and leaves at rest, and smoothstep is that curve. It is
# also the only ease that lets the blade keep up: with WHIP the head is still doing
# 0.32 of its peak in the frame the azimuth flips, which flips its direction of
# travel inside one frame and leaves the blade pointing at nothing (§5).
func eased_turnaround(t: float) -> float:
	var x := clampf(t, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)


func eased(t: float) -> float:
	var x := clampf(t, 0.0, 1.0)
	match ease:
		Ease.OUT:
			return 1.0 - pow(1.0 - x, ease_power)
		Ease.IN:
			return pow(x, ease_power)
		Ease.IN_OUT:
			return x * x * (3.0 - 2.0 * x)
		Ease.WHIP:
			# §8 — A CUT THAT STOPS DEAD HANDS THE NEXT CUT A STOPPED CHAIN.
			#
			# Every polynomial ease-out has zero velocity at t = 1, so a three-cut
			# chain authored with `OUT` decelerates to nothing at the end of each
			# arc and the next cut accelerates from rest: measured on the last clean
			# tour, the head fell to 0.5 m/s between cuts against a peak of 142. The
			# player sees three authored swings, which is exactly what §8 forbids.
			#
			# WHIP is that ease-out blended with a linear tail, so the head keeps
			# `WHIP_TAIL` of its arc speed at the handover and the next beat starts
			# from a chain that is already travelling. The deceleration is still
			# there — it is the difference between a follow-through and a stop.
			#
			# AND IT IS SYMMETRIC, which matters more than it looks. The first
			# version kept `OUT`'s explosive start, and measuring the head's aim
			# (`chain_physicality` group C) showed what that costs: the wind-up
			# arrives at the arc's start travelling the OTHER way, so an arc that
			# leaves at 1.8× its own average speed flips the head's direction of
			# travel ~150° inside one frame. The head is a mass on a rope, and it
			# then needed six frames to swing its blade back round — a blade that
			# points 90° off its own motion for a tenth of a second, at the start of
			# every strike. Smoothstep leaves the arc slowly, so the direction of
			# travel ROTATES through the handover instead of snapping, and the mass
			# still cracks through the middle of the arc where a whip's speed
			# actually lives.
			return x * x * (3.0 - 2.0 * x) * (1.0 - WHIP_TAIL) + x * WHIP_TAIL
		_:
			return x


# The authored window, shortened by however much spin the head is carrying. A
# sweep at full momentum genuinely arrives sooner; this is the entire reward for
# keeping the chain moving, and it is a feel change rather than a number.
func active_seconds(momentum: float) -> float:
	return active / lerpf(1.0, 1.0 + momentum_speed_scale, clampf(momentum, 0.0, 1.0))


func strike_end(momentum: float) -> float:
	return startup + active_seconds(momentum)


func total_seconds(momentum: float) -> float:
	return startup + active_seconds(momentum) + recovery
