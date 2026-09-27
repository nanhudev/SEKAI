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

@export_group("Geometry")
@export var max_radius := 4.6
@export var min_radius := 0.55
@export var head_radius := 0.30
@export var chain_length := 4.7
@export var links := 28
# Reach grows a little with spin. Small on purpose: momentum's real payoff is
# speed, and this is the flavour on top.
@export var radius_momentum_scale := 0.10

@export_group("Held pose")
# 锁链不是永远垂直挂着: the head rests low and slightly to the side, with a slow
# weight sway. Low because a chain at rest hangs; alive because it is metal.
@export var home_radius := 1.05
@export var home_height := 0.62
@export var home_azimuth_degrees := 26.0
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

@export_group("Chain")
@export var light_window := 0.55
@export var light_chain: Array[StringName] = [&"ch_sweep", &"ch_return", &"ch_slam"]
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
