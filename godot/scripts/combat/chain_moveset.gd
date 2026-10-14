extends Resource
class_name ChainMoveset
# 缚星链 / STAR-BIND CHAIN — one weapon, in data.
#
# This is the chain's equivalent of SwordMoveset: the one place its design lives.
# The director reads it and owns no numbers of its own, so tuning the weapon is
# editing this resource and nothing else.
#
# THE THREE VARIABLES the whole weapon runs on, and the reason it is not "a sword
# with a wider hitbox":
#
#   RADIUS    how far the head is from the player — this is REACH and, at the
#             limit, it is what makes the chain go taut
#   MOMENTUM  how fast the head is already going — this buys TIME (sweeps arrive
#             sooner) and a little reach, never a damage stat
#   TENSION   whether the chain is stretched to its limit or holding something —
#             this is what CHANGES THE AVAILABLE INPUTS
#
# None of them get a bar. If a player needs a gauge to know the chain is taut,
# the weapon has failed (brief §51).

@export_group("Identity")
@export var id: StringName = &"star_bind"
@export var display_name := "缚星链 · STAR-BIND CHAIN"

@export_group("Form")
# WHICH CHAIN THIS IS (§1 / §6 / §12). A form is not a power level and not a skin:
# it is a different answer to "what is a chain FOR" — 实链 controls weight, 游链
# controls momentum, 律链 controls connection — so the three are meant to coexist
# and be chosen, never to replace one another.
#
# Only 实链 exists in the prototype, and these two fields are here anyway, for the
# same reason the phase-1 fields above are: the HUD, the debug readout and the
# renderer all have to be able to say WHICH chain is in hand, and a name added after
# the fact is how the second form ends up unnameable in every place that needed one.
@export var form_name := "实链"
@export var form_id: StringName = &"solid"

@export_group("Geometry")
# §1 — THE CHAIN IS LONG, AND THE LENGTH IS THE WEAPON.
#
# The prototype's 4.7m was a decision about what could be simulated. V3 is a
# decision about what the player should BELIEVE, and the number that has to be
# big is the ROPE, not the amount currently in the air. So `chain_length` and
# `max_radius` are two different numbers for the first time: the 6-7m between
# them is what the player is holding coiled in their fist while the head is a
# metre away, and it is the entire subject of PART F.
@export var chain_length := 10.0
# THE HARD REACH. `is_taut()` fires at 0.97 of this, so it owns the one beat the
# weapon is built around — and it must stay UNDER `chain_length`: a chain taut at
# a radius it cannot reach is a chain that is never taut. 9.7 of 10.0 leaves 3%
# of rope that never pays out, which is why a full throw reads as "almost all
# of it" rather than as an arbitrary cut-off.
@export var max_radius := 9.7
@export var min_radius := 0.55
# §4 — SIZED FOR TRACKING. The head is what the player has to find first, and V3
# makes it a TRIDENT, so it is longer than the old 刃锤 in every direction.
@export var head_radius := 0.34
# THE LINK POOL, NOT THE LINK COUNT (§25).
#
# V3 draws as many links as the paid-out rope needs — a constant link SIZE rather
# than a constant link COUNT — so this is the ceiling of that drawing:
# `chain_length / link_spacing`, rounded up = 10.0 / 0.052 ≈ 193, held at 200. A fixed
# 28 over a 10m rope would be 36cm per link, which is a fence, not a chain.
@export var links := 200
# 0.052, AND IT REPLACES 0.11 — WHICH WAS TRIED BOTH WAYS AND IS NOW SETTLED BY A RENDER.
#
# The OLD reason 0.11 stayed is still true and still worth keeping, because it is the one
# coupling that punishes a COARSER pitch: the droop is measured on the drawn POLYLINE, and
# the polyline has one point per link, so at 1m of reach a coarser spacing leaves fewer
# points to describe a 0.95m sag, the sampled arc falls short of its own apex, and the §1
# saturation reading stops saturating. V3 raised it to 0.145 (6.9/m) and
# `chain_physicality` went red with "the rope droops 0.926m at 1m of reach". That is a
# reason not to go coarser. It is NOT a reason not to go finer — a finer pitch samples the
# sag with MORE points, so the reading gets sharper, not softer.
#
# The NEW reason is that 0.11 could not be made into a chain. At 0.11 the link is 9.46cm
# long, so the centres of consecutive links are 1.54cm further apart than the links are
# long — a string of separate rings. The idle capture is the evidence
# (`.render/stow_idle_zoom_ab.png`): panel A is 0.11, panel B is 0.052 with `LINK_FILL`
# raised to hold the link size fixed, and only B reads as chain. 0.052 / 0.0946 = 0.55 is
# the pitch-to-length ratio real chain runs.
@export var link_spacing := 0.054
# Reach grows a little with spin. Small on purpose: momentum's real payoff is
# speed, and this is the flavour on top.
@export var radius_momentum_scale := 0.10

@export_group("Held stow")
# §2 / §26 — THE ONE THING THAT SAYS "THIS WEAPON IS LONG" WHILE YOU STAND STILL.
#
# Not a simulation of ten metres of rope on the hip: a PRESET RIG whose count is driven
# by how much of the rope has been paid out. The head hangs a metre away and four arcs
# are at the hip; throw the head nine metres and there is one.
#
# Driven by REACH over `chain_length` rather than by an abstract "extension ratio", so
# the quantity the player is watching (how far the head is) is the same quantity the
# stow reads. One number, not two that can disagree.
#
# AND THE COUNT IS A PROPERTY OF THE ROPE, NOT A KNOB OF ITS OWN. A layer of a stow
# holds the same amount of chain however much rope there is — what changes is how MANY
# layers. So `coil_max` is `chain_length / coil_per_loop` rounded, which is what makes
# the idle stow actually read the weapon's length (§26) instead of reporting "long" at
# 8m and at 12m alike. `chain_physicality` group I asserts the two agree, and also that
# the layers can HOLD the rope that is not in the air — because raising the rope without
# raising the stow is how a long weapon silently becomes a short one that lies about it.
#
# §STOW·V4·B CHANGED THE UNIT, AND ONLY THE UNIT. The stow is drawn as OPEN ARCS now
# rather than as a nested spiral of turns (see `chain_visual.gd`), so a "coil" is one
# arc of several links and not one turn of one link. `coil_per_loop` therefore reads
# 2.5m rather than 1.25m and `coil_max` comes out at 4 — which is also exactly the
# 4-layer fan the user specified, arrived at from the rope instead of typed in. The
# old figure was eight turns of 1.25m in a fist whose drawing held about a metre; this
# one is four layers of 2.5m. Both are lies under §7, and this one is half the size.
@export var coil_per_loop := 2.5
@export var coil_max := 4
@export var coil_min := 1
@export var coil_radius := 0.100
# Unused by the V4 stow, and kept because it is still the field a future high-tier
# stow would read: the arcs are laid out in `chain_visual.gd` by `ARC_*`, not by a
# spool pitch, so nothing in the drawing reads this today.
@export var coil_pitch := 0.014

@export_group("Held pose")
# 锁链不是永远垂直挂着: the head rests low and slightly to the side, with a slow
# weight sway. Low because a chain at rest hangs; alive because it is metal.
#
# §A1 — WHY THE REST IS ON THE SIDE THE WIND-UP COMES FROM. A1 winds up to the right
# and then sweeps left, so a head resting on the LEFT has to cross the whole body one
# way and immediately come back the other — and measuring the blade's aim (`chain_
# physicality` group C) showed exactly what that costs: the direction of travel
# reversed inside a single frame at the moment the arc took over, and the head spent
# that frame pointed 77° away from where it was going. Resting on the side the wind-up
# comes from makes that reversal happen at low speed, under the head's own aim
# threshold, so the blade never loses the argument. It is also the hand the chain is in.
#
# ===========================================================================
# §V4 — THE NUMBERS MOVED, BECAUSE THE HEAD WAS NEVER ON SCREEN.
#
# V3's rest was (1.05, 0.62, −30°) and `tools/probe_chain_framing.gd` measured where
# that actually lands in a 1280x720 frame at the game's own 75° vertical FOV: the
# trident's centre projected to (909, 842) — 122px BELOW the bottom edge, with a 254px
# body. The weapon's hero element was not merely hard to read, it was absent, in the
# pose the player spends most of the game in. The fistful was on screen and the head
# was not, which is the exact inverse of §RIG A ("visible trident head").
#
# The geometry behind it is not a taste call, so the new numbers are derived from it.
# The eye sits 1.55m above the deck and the frame's half-height at `d` metres is
# `d · tan(37.5°) = 0.767 d`, so a head `Δy` BELOW the eye is in frame only while
# `Δy < 0.767 · depth`. At height 0.62 that needs 1.21m of FORWARD depth — and the
# forward depth is `radius · cos(azimuth)`, not the radius. 1.05m of radius aimed 30°
# off centre only bought 0.91m of depth, so it missed by 12cm and the frame said so.
#
# AND THE ANGLE IS THE WHOLE TRICK, because screen position depends only on the
# AZIMUTH and never on the radius. In camera space two objects at the same bearing
# project to the same screen column however far apart they are, and the hand anchor
# sits 26° to the player's right — so a head resting 30° right (the V3 value) lands in
# the same column as the handle, at 1.1m behind a 151px grip. Moving out to 42° is
# 16° of bearing away from the grip, which is 180px on screen, and that is the whole
# separation. The depth needed for a low head follows from `Δy < 0.767 · depth`, so the
# radius follows from the bearing: 42° off centre at 1.75m is 1.30m of forward depth,
# which carries a head 0.77m below the eye — and it is fully in frame at ≈(1063, 638).
#
# A SMALLER bearing than V3's is also the SAFE DIRECTION for §A1's aim: the startup
# traverse from the rest to the arc's first key is 36° here against V3's 48°, so the
# reversal at the handover happens slower, not faster.
@export var home_radius := 1.35
@export var home_height := 0.82
@export var home_azimuth_degrees := -34.0
@export var idle_sway_degrees := 4.5
@export var idle_sway_speed := 1.25
@export var retract_time := 0.30

@export_group("Momentum")
@export var momentum_max := 1.0
@export var momentum_decay := 0.42

@export_group("Orbit (Heavy)")
# Hold Heavy → the head circles. Longer hold, more spin; released at the cap so
# it is never worth hoarding. Early release is always available and is the
# intended timing choice: act sooner, hit lighter.
@export var orbit_radius := 2.25
@export var orbit_height := 1.05
@export var orbit_speed_min := 420.0
@export var orbit_speed_max := 940.0
@export var orbit_gain := 0.62
@export var orbit_max_hold := 1.30
@export var orbit_min_hold := 0.14
# A whirling chain is DANGEROUS in every direction, so the orbit really hits.
# The target list is cleared on an interval so one lap cannot register sixty
# times against the same enemy, but a second lap can land again.
@export var orbit_damage := 13.0
@export var orbit_poise := 12.0
@export var orbit_hit_interval := 0.34
@export var orbit_radius_swell := 0.18
@export var movement_scale_orbit := 0.72
# Small FOV pressure while spinning, and it is a SUSTAINED offset rather than a
# kick: the camera must not orbit the head (brief §30), but it should admit that
# something is circling.
@export var orbit_fov := 6.0

@export_group("Tension")
# How close to the limit counts as taut. Below 1.0 so a launch that stops one
# centimetre short still reads as "the chain caught it".
@export var tension_ratio := 0.97
# How long the taut window stays open for the player to use. Unused, the head
# comes home on its own.
@export var tension_window := 0.90

@export_group("Impact")
# Head speed at which a landing counts as a HARD one. Below it the head is
# arriving; above it, it is slamming. Everything about the reaction — the stop,
# the trauma, the spin it spends — reads off this ratio (§43).
@export var impact_speed_ref := 9.0
# WHAT A LANDING COSTS, BY WHAT IT LANDED ON. Same shape as the weight table above
# and for the same reason: an enemy's weight is a fact about the enemy, and every
# rule that cares about it should read one table instead of growing its own.
@export var impact_cost_by_weight := {
	&"light": 0.35,
	&"medium": 1.0,
	&"heavy": 1.7,
}
# How much the arc bends when the head lands on it, by weight. Kept small: this is
# a chain, and a head that ricochets off every target would make 横缚 unusable
# against a crowd — which is the one thing it is for.
@export var impact_deflect_by_weight := {
	&"light": 0.4,
	&"medium": 1.0,
	&"heavy": 1.8,
}
# The hitstop multiplier's floor and ceiling across that speed ratio.
@export var impact_hitstop_min := 0.55
@export var impact_hitstop_max := 1.35

@export_group("Return")
# 回收不许瞬回 (§43). The head is a mass on a rope: released from a strike it keeps
# going for a beat, and the chain then has to reel it back — so the return BENDS
# rather than retracing the line it came in on. Both numbers are shares of what is
# left, not absolutes, so a longer chain does not get a longer flourish.
# How much further round it swings past where it stopped.
#
# Sized against the base lerp rather than in isolation: the head is simultaneously
# being pulled home, so for the bulge to be visible at all it has to out-run that
# lerp early on. At 0.55 the peak lands a little before a quarter of the way through
# the reel — the head has gone about a fifth of the remaining gap the WRONG way and
# is only then hauled back. Lower than ~0.4 and the reel is a straight line again,
# which is the thing this exists to avoid.
@export var retract_overshoot := 0.55
# How much further out it drifts before coming home, in metres. Same argument: this
# is what stops the radius collapsing the instant the strike ends — a whirling head
# keeps its distance while it turns, and only then gets reeled in.
#
# MEASURED, because the number that matters is the one the player sees (`radius`),
# not the one authored here. At 0.45 the pose-space bulge peaked at 0.15m — a real
# bulge — but `radius` is `pose × _radius_scale`, and the whiff cost spends its
# momentum DURING the reel (1.030 → 1.003 over the 18 frames), so the chain was
# contracting under the bulge and the visible drift came out at 0.038m: three
# centimetres on a 3.2m radius is not a drift, it is rounding. At 0.80 the live
# drift peaks at ~0.15m, against a 2.1m haul — a 7% overshoot, which is what a mass
# on a rope does. It is still clamped by `max_radius` below, so a reel out of a TAUT
# chain cannot stretch the rope.
@export var retract_out := 0.80

@export_group("Tension feel")
# §43 asks for tension in three channels. Two of them are this file's: the LINE
# (ChainVisual trembles when loaded) and the CAMERA (a small squeeze and a nudge
# along the chain, never an orbit — §30). The third is AUDIO, and §49 says that
# stays a placeholder: the signals are emitted, the sounds are not this line's.
@export var taut_fov := 1.8
@export var taut_snap_trauma := 0.05
# Tension at which the line counts as LOADED. Below it the chain is just out there.
@export var taut_feel_threshold := 0.85

# ---------------------------------------------------------------------------
# §3 · THE SNAP IS THE WHOLE WEAPON, AND IT HAS TO BE A BEAT.
#
# Measured on the last clean tour before this pass existed: thrown across the lab
# the chain was 0.080m off straight while it was still loose, the drawing already
# read 67% taut well before the head reached the limit, and the whole
# loose→straight transition took 0.533s — a slow smear with no moment in it. A
# rope does not do that. It HANGS for as long as it has itself spare, and then at
# the end of its travel it comes up hard and all at once.
#
# `tension_knee` is where that begins, as a fraction of the chain's own length,
# and the curve is a cube from there to `tension_ratio`. So a chain with a third
# of itself still coiled is exactly as loose as one hanging at rest, and the
# entire transition lives in the last few percent of reach — which is the beat.
@export var tension_knee := 0.70
# How fast the rope comes up hard, and how fast it pays back out. ASYMMETRIC ON
# PURPOSE: tightening is an event, relaxing is a rope. A chain that let go as
# quickly as it tightened would be a spring, which §33 forbids.
#
# RE-MEASURED WHEN THE ROPE WENT TO 10m, and it had to be. The snap curve is a
# cube over the last 27% of REACH, so on the old 4.6m chain the target tension
# climbed gradually across a 1.2m band and the ramp spent part of its time chasing
# a moving number. On a 10m chain that band is 2.6m of a much faster throw, the
# target saturates almost at once, and the same 16/s produced a 0.033s snap —
# below the 0.035s floor, i.e. a model swap rather than a beat. 11.0/s restores
# the measured 0.050s. This is a rate on a curve whose SHAPE did not change; that
# is why the number and not the knee is what moved.
@export var tension_rise := 11.0
@export var tension_fall := 6.0

# ---------------------------------------------------------------------------
# §9 · HOW STRAIGHT THE WHIRLING CHAIN GETS AT FULL SPIN. Never anywhere near
# 1.0: a chain that reached a rod by spinning would have nothing left to snap
# from, and the orbit's whole job is to hand a straight line to the throw.
@export var orbit_straighten := 0.42

# ---------------------------------------------------------------------------
# §13 · THE THIRD BEAT. THROW → CONTACT → BITE → TENSION.
#
# Without a bite the sequence is THROW → it is already a straight line, which is
# indistinguishable from a raycast with a hit registered on the end of it. The
# bite holds the rope OFF the snap for a moment after the head catches something,
# so the player sees 挂住了 before they see 绷紧了 — and it is the only reason the
# two are different events.
@export var hook_bite_time := 0.09

# §9/§19 — THE SAME BEAT, ON STONE.
#
# A throw that ends on a WALL bites exactly like one that ends on a body, and for
# the same reason: without the pause, "it hit the wall" and "it stopped in front of
# the wall" are the same picture. §19 allows 50–120ms; 0.10 sits in it and is a
# touch longer than the body bite because a wall does not flinch, so the head is the
# only thing that can carry the beat.
@export var wall_bite_time := 0.10
# §20 — how long the anchored chain stays stretched before it reels back in. Long
# enough to read as a fixed length of metal under load, short enough that a player
# who threw into a wall once is not standing there holding it. The retract itself is
# still `retract_time`, so the whole exchange is this plus the haul home.
@export var wall_hold_time := 0.85

# ---------------------------------------------------------------------------
# §17 · A CONNECTION DOES NOT SIT AT FULL LOAD FOREVER.
#
# What is caught is ATTACHED, not necessarily at the end of the rope: hooking
# something three metres away on a 4.7m chain leaves a metre and a half of chain
# still hanging in the air, and pinning the drawing to "taut" there is what made
# every bind in the last tour a dead-straight rod. So the drawing reads the rope
# it can actually see, and the strain on it reads how hard the player is hauling.
@export var hook_strain_lift := 0.55
@export var strain_ref_speed := 3.0


@export_group("Chain")
# THE INPUT WINDOW — and §7 is explicit that it is NOT the combo's memory: "不要用
# 同一个计时器". How long after a cut's strike the next press is still accepted as a
# CONTINUATION of the sentence rather than ignored. `_can_act()` is what enforces
# it, by leaving the recovery phase open to the next light.
@export var light_window := 0.55
# §6 — HOW LONG THE SENTENCE IS REMEMBERED. The second and separate timer.
#
# MEASURED before this existed (`tools/probe_chain_combo.gd`), and the reading is
# the reason it does now: the only thing that reset the index was a `_idle_time`
# counter that advanced EXCLUSIVELY in `HELD` and was zeroed at attack START. Both
# halves of that were wrong, and they failed in opposite directions:
#
#   · the clock ran from the cut's start, and the retract on the end of every cut
#     (0.30s) was invisible to it — so a press 0.30s after a cut had settled read
#     as ~0.95s and restarted at A1. Chaining by rhythm was impossible; you had to
#     press DURING the cut or lose the sentence.
#   · every frame in RETRACTING / TENSIONED / HOOKED was also invisible, so how
#     long the memory lasted depended on which state the sentence happened to end
#     in rather than on a number.
#
# So this field is the ONE clock the memory reads: time since the last cut ENDED,
# counted in every state, independent of `light_window` above.
@export var combo_reset_timeout := 0.85
# §A / PART A. The loop, in order, and the whole of it: 左甩 → 快右左 → 直抛. A4 and
# A5 are the two beats after this one and are not authored yet (PART O gates them).
@export var light_chain: Array[StringName] = [&"ch_sweep", &"ch_return", &"ch_throw"]
@export var heavy_id: StringName = &"ch_launch"
@export var hook_id: StringName = &"ch_hook"
@export var taut_light_id: StringName = &"ch_snap"
@export var taut_heavy_id: StringName = &"ch_yank"
@export var bound_light_id: StringName = &"ch_pull_cut"
@export var bound_heavy_id: StringName = &"ch_ground_slam"
@export var deflect_id: StringName = &"ch_deflect"

@export_group("Deflect")
# DEFLECT SWING is deliberately not a sword parry: the chain sweeps the attack
# aside rather than meeting it. Phase 1 only disturbs MELEE LIGHT attacks — a
# heavy goes straight through, which is the counterplay.
@export var deflect_perfect_window := 0.10
# A stale deflect still saves most of the damage but does not interrupt, so
# 截链 has a reason to exist beyond a nicer word.
@export var deflect_damage_scale := 0.40
@export var deflect_momentum_bonus := 0.35

@export_group("Hook")
@export var pull_distance := 2.30
# A yank is the same pull, taken early and at a discount. 缚 is the full snap.
@export var yank_share := 0.55

# THE PULL IS A TUG OF WAR, NOT A MAGNET (§15–§19).
#
# Delivered as one displacement, a pull reads as a snap-to: the body is there, and
# then it is here. Nobody can feel how heavy it was, because nothing in the motion
# ever resisted. The weight becomes feelable when the rope is HAULED — yank, stop,
# yank, stop — and the body visibly re-settles between each one, so the total is
# split across `pull_tugs` diminishing yanks.
#
# The shares are a CURVE rather than an average on purpose: a rope that loses power
# as it comes in is a rope with something on the end of it. They sum to 1.0, so the
# distance a pull moves is unchanged by how many tugs it takes to get there — this
# changed the RHYTHM of a pull, not its budget. (That sentence is now literally
# true, not nearly true: see the note on PlayerMovement.pull().)
@export var pull_tugs := 5
# The gap is what makes it 顿挫 instead of smooth. `PlayerMovement` spends 88% of a
# yank in 0.20s and 95% in 0.30s, so 0.24 means the body is visibly at rest for a
# beat before the next one arrives — 顿, then 挫. It is a pure FEEL number and it
# can be moved without touching how far anything ends up, because the shares above
# own the distance and this owns only the rhythm.
@export var pull_tug_gap := 0.24
@export var pull_tug_curve: Array[float] = [0.28, 0.24, 0.20, 0.16, 0.12]
# The 顿 of 顿挫: a tug stops the world for a hair. Small enough that no single one
# is a hit — and a sequence of them is not, which is the same trick a drum roll uses.
@export var pull_tug_hitstop := 0.035
@export var pull_tug_trauma := 0.09
@export var pull_tug_impulse := 0.012
# NOTE: there is deliberately no `player_pull_speed` here. Both sides of a pull are
# expressed as a DISTANCE: the target is displaced by pull_distance * target_share
# and the player by pull_distance * player_share. Speeds were removed because a
# speed is only meaningful to whoever owns the decay — see PlayerMovement.pull().
# The weight reaction table. This is brief §18 as data, and it is the thing that
# stops the chain being "pull everything to me": a heavy enemy is not a victim,
# it is an ANCHOR — the chain does not move it, it moves YOU. The shares are
# multiples of pull_distance, so "player_share 0.35" means 0.8m of forward drag.
@export var hook_response := {
	&"light": {"target_share": 0.85, "player_share": 0.10, "bound_time": 1.00},
	&"medium": {"target_share": 0.50, "player_share": 0.45, "bound_time": 0.70},
	&"heavy": {"target_share": 0.00, "player_share": 0.35, "bound_time": 0.40},
}
@export var default_weight: StringName = &"medium"

@export_group("Interactions")
# MAGIC x CHAIN, phase 1 and only two of them (brief §24).
# WIND: the most natural pairing there is — wind does not add damage, it adds
# spin, which is the chain's own currency.
@export var wind_momentum_bonus := 0.45
# FROST: a chain is the best way to apply force to something you have already
# made brittle. WHICH element pays off is named here rather than hard-coded in
# the director, so a future chain can be brittle-payoff-free without a code
# change — and no weapon is hard-bound to an element (brief §44).
@export var pull_poise_elements: Array[StringName] = [&"frost"]
@export var pull_poise_scale := 1.60
# Which rung of that element's ladder has to be reached before a pull pays off.
# 2 = the element's own "the material is compromised" stage. Expressed as a
# number so this file never has to spell out what any element's stages mean.
@export var pull_poise_min_stage := 2

@export_group("Moves")
# Keyed by id, exactly like SwordMoveset — one shape for both weapons means a
# reader who knows the sword already knows where to look.
@export var moves: Dictionary = {}


func get_move(wanted: StringName) -> ChainMove:
	return moves.get(wanted)


func move_ids() -> Array:
	return moves.keys()


# A target that has no opinion about its own weight still has to be hookable, so
# an unknown class resolves to the middle of the table instead of failing.
func hook_response_for(weight: StringName) -> Dictionary:
	if hook_response.has(weight):
		return hook_response[weight]
	return hook_response.get(default_weight, {"target_share": 0.5, "player_share": 0.45, "bound_time": 0.7})
