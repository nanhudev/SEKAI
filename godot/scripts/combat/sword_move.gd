extends Resource
class_name SwordMove
# One attack in the Universal Sword Layer language.
#
# Timeline (every move has all four, no move is allowed to be "just a lerp"):
#
#   anchor ──startup──▶ wind ──strike──▶ contact ──follow──▶ follow ──recovery──▶ recover
#            anticipation      hitbox open        follow-through      settle
#
# The pose keys live in camera space (x right, y up, -z forward). They are
# authored here as placeholder-grade keys; the formal hand/arm animation from
# the ART line will replace the keys, not the timing language.

@export var id: StringName = &""
@export var display_name := ""
@export var note := ""

@export_group("Timing")
@export var startup := 0.09
@export var strike := 0.09
@export var follow_time := 0.075
@export var recovery := 0.18
# Fraction of (follow_time + recovery) after which cancels unlock.
@export var cancel_open := 0.45
@export var startup_scale := 1.0
@export var recovery_scale := 1.0
# Applied to `recovery` when the move connected / whiffed. A style can punish
# inaccuracy by making the miss longer, and reward contact by shortening it.
@export var hit_recovery_scale := 1.0
@export var miss_recovery_scale := 1.0
# The next move in the chain starts faster when this one connected.
@export var on_hit_next_startup_scale := 1.0

@export_group("Damage")
@export var damage := 18.0
@export var poise_damage := 15.0
@export var element: StringName = &"physical"
@export var hitstop := 0.028
@export var frozen_bonus := 1.0
# Posture multiplier when the swing was fully charged.
@export var charged_poise_bonus := 1.0
@export var charged_damage_bonus := 1.0

@export_group("Camera")
@export var camera_impulse := Vector2.ZERO
@export var camera_roll := 0.0
@export var fov_kick := 0.0
@export var trauma := 0.0

@export_group("Body")
# Metres of forward displacement delivered over the strike window.
@export var lunge := 0.0
@export var lunge_lead := 0.35
@export var steer := 0.30

@export_group("Pose · camera space")
@export var anchor := Vector3(0.55, -0.52, -0.95)
@export var anchor_rot := Vector3(0.0, 0.0, -0.2)
@export var wind := Vector3(0.72, -0.30, -0.88)
@export var wind_rot := Vector3(0.05, -0.30, -0.85)
@export var contact := Vector3(0.10, -0.62, -1.05)
@export var contact_rot := Vector3(0.14, 0.30, 1.15)
@export var follow := Vector3(0.02, -0.70, -1.00)
@export var follow_rot := Vector3(0.18, 0.44, 1.45)
@export var recover := Vector3(0.45, -0.55, -0.95)
@export var recover_rot := Vector3(0.02, 0.12, 0.05)
# Higher = the pose barely moves during startup, then snaps. 藏锋 sits high.
@export var anticipation_power := 2.0
# Higher = the blade accelerates harder out of the wind-up.
@export var strike_power := 3.0
@export var follow_power := 1.6
@export var recovery_power := 2.0
# The blade pushes past the follow pose before settling, then resolves back.
@export var follow_overshoot := 0.0
@export var recover_sag := 0.0

@export_group("Hitbox")
@export var hitbox_size := Vector3(1.4, 1.2, 1.6)
@export var hitbox_offset := Vector3(0.0, -0.2, -1.4)

@export_group("Reach · how this cut crosses space")
# DISTANCE IS THE COMBO'S GRAMMAR, NOT ITS SCALING.
#
# The four beats of the basic sentence are told apart by HOW FAR the blade
# reaches, not by how big the number was: A1 solves a body at arm's length, A2
# pushes the fight out to a projectile, A3 attacks far past that in one instant,
# and A4 refuses all of it and pulls the danger back around the player. Four
# moves that all used `hitbox_size` would be four sizes of the same sentence —
# which is exactly the thing this round exists to stop.
#
#   body  the sword's own hitbox. Nothing else. Arm's length.
#   wave  a travelling cut that leaves the blade and crosses the gap.
#   trace an INSTANT cut drawn in space, at range, with no travel at all.
#   arc   a sweep around the body — the attack comes back to the player.
@export var reach_mode: StringName = &"body"
# For `wave`: how far past the tip the cut travels before it dies, in metres.
# For `trace`: how far out the cut marks are laid, in metres.
@export var reach := 0.0
# For `arc`: how far around the player the sweep bites, in metres.
@export var reach_radius := 0.0
# For `arc`: the sweep, measured from the character's forward. More than 180 is
# what makes it an 优弧 — a cut that has already passed behind the player and is
# still going, rather than a shockwave with no beginning.
@export var reach_arc_from := -135.0
@export var reach_arc_to := 135.0
# The wave's own speed and lifetime. Kept here rather than in the VFX so the
# thing the player sees and the thing that can hit them cannot disagree.
@export var reach_speed := 26.0
# For `trace`: the cut marks themselves. Each entry is
#   {"t": seconds from the move's start when the cut happens,
#    "angle": degrees in the view plane, 0 = right, positive = counter-clockwise,
#    "reach": how far out the mark is laid, in metres,
#    "weight": this cut's share of the move's damage}
#
# THEY ARE NOT THREE COPIES OF ONE CUT, and that is the whole point of A3. The
# brief's three marks are `/`, `\` and a shallow arc — an irregular structure the
# eye can count, not a starburst and not a UI glyph. A cut is ALSO not a
# projectile: it happens at a place, at an instant, with no travel, which is the
# language A2 already speaks and A3 must not repeat.
@export var traces: Array[Dictionary] = []
# The mark's own size, in TANGENT units — the same units a lens works in, so the
# window the cut tests against and the mark the player can see are one number.
# 0.72 covers most of a 75-degree lens at any depth; the thickness is what makes
# the cut a line rather than a wall.
@export var trace_half_len_tan := 0.72
@export var trace_half_thick_tan := 0.085
# For `arc`: how many slices the sweep is resolved in. The sweep takes time, so
# resolving it once at the end would hit a body that was behind the player
# before the blade ever got there. Each slice only covers the arc the blade is
# actually passing through during that slice.
@export var arc_slices := 6
@export var reach_damage_scale := 1.0

@export_group("Animation events")
# THE CONTRACT THE OTHER LINES LISTEN TO (§23).
#
# Audio, VFX and any future third-person animation subscribe to these by NAME
# and by instant; none of them is allowed to guess a time from the move's total
# length, because a guess is a number that goes stale the first time the move is
# retuned. Each entry is `{"t": seconds from the move's start, "id": StringName}`.
#
# The gameplay half of a move is NOT driven from here. Hit resolution belongs to
# the reach fields above and to `startup`/`strike`; an event is a thing the move
# SAYS, never a thing the move DOES.
@export var events: Array[Dictionary] = []
# This beat's OWN voice, or &"" to fall back to the style's generic light cue.
#
# §25 gives the four beats four different sounds, and the index-based fallback
# cannot express that: `sword_light_%d` is shared by every style in the game, so
# re-purposing it for A1-A4 would change what 一文字 and 回风 sound like in order
# to describe a combo they do not have.
@export var audio_cue: StringName = &""
# The blade ribbon's width, as a multiple of the style's.
#
# A1 is 极薄 — the thinnest line in the sentence — and A4's sweep is the widest,
# and that is a property of the BEAT rather than of the style: 回风 and 一文字
# both run the Universal layer, so a style-wide number could never tell A1 from
# A4. §24 asks each beat to have its own visual identity, and the honest way to
# give A1 one is to make the trail that already exists thinner, not to draw a
# second trail on top of it.
@export var trail_width_scale := 1.0

@export_group("Domain · A3's micro hold")
# The one beat in the basic sentence that is allowed to change the world instead
# of the pose. Inside this window the camera stops moving, the lens squeezes and
# the room goes quiet — enough that the player feels the beat is different, not
# so much that the world stops. Zero means the move has no domain.
@export var domain_from := 0.0
@export var domain_to := 0.0

@export_group("Body beats")
# A POSE THAT IS NOT FOUR PHASES.
#
# The four-phase timeline (anticipation → contact → follow → settle) is the
# right shape for one cut. A3 is three cuts and two returns, so forcing it into
# four phases would either lie about the timeline or flatten the technique into
# a single swing.
#
# When these are present the sampler walks this list instead, eased between
# neighbours, and the sampled phase is still reported. It stays a PURE FUNCTION
# OF `t`: a beat list is data, and `apply(t)` must be able to produce frame 27
# without having produced frame 26.
@export var beat_times := PackedFloat32Array()
@export var beat_positions := PackedVector3Array()
@export var beat_rotations := PackedVector3Array()
# HOW MUCH THE BLADE BOWS BETWEEN TWO BEATS, in camera-space metres.
#
# ===========================================================================
# WHY A BEAT LIST IS NOT ALLOWED TO BE A POLYLINE ANY MORE
# ===========================================================================
#
# Until this field existed, a beat was joined to the next one by a straight line
# in pose space, and for a cut that is correct: a cut is a fast sweep and the eye
# reads the chord. For a DRAW it is wrong, and it is wrong by a measured amount.
#
# `tools/measure_saya_curve.gd` slices the shipping scabbard along its bore and
# reports the centreline. It is not straight: it departs from the mouth's own
# axis by **16.4 mm** over the 0.79 m bore, monotonically, toward +X (away from
# the edge). The blade's own centreline bows the same way by 13.1 mm over its
# 0.69 m of blade. The two curves were made for each other, which is exactly what
# a scabbard is — and it means a blade pulled along a straight line through the
# mouth's axis is 16 mm inside its own wall by the time it clears.
#
# So a segment may now carry a bow: `bow` is the offset of the path at its
# MIDPOINT, i.e. the sampled position is
#
#     lerp(P0, P1, u) + bow * 4u(1-u)
#
# which is a quadratic Bezier whose control point has been eliminated — `bow` is
# directly "how far off the chord the middle of the movement is", and 4u(1-u)
# peaks at exactly 1.0 when u = 0.5.
#
# ONE ENTRY PER SEGMENT: `beat_bows[i]` is the bow of the segment from beat `i`
# to beat `i+1`, so the array is one shorter than the beat list. An empty array,
# or a zero entry, means a straight segment — every cut in the game is unchanged
# by this field existing, and only the moves that must respect a curve opt in.
@export var beat_bows := PackedVector3Array()
# ROTATION BOW, the same idea for the euler triple. Kept separate because the
# draw's rotation path is not the position path's problem: the blade also has to
# rotate as it comes out of the mouth, and doing that along a straight euler
# lerp makes the tsuba plough the koiguchi on the way past.
@export var beat_turn_bows := PackedVector3Array()

# --- the SAYA's own beats -------------------------------------------------
#
# §2 asks for ONE WEAPON SYSTEM: the sheath is a second actor in the same
# sentence, not a prop whose pose is derived from the blade. A draw where the
# off hand does nothing except "be where the sword is" cannot express Beat 1
# ("the saya is brought to the front") or Beat 4 ("the left hand pushes the mouth
# back"), because in both of those the saya moves WHILE the blade is still home.
#
# So an equip-family move may carry the sheath's own poses, on the same clock and
# the same beat list. When they are present the controller drives the saya from
# them directly; when they are absent the rig falls back to deriving the seating
# from the sword, which is what every ATTACK still does (A1's mouth touch and
# A3's three returns are seating events, not choreography).
@export var saya_positions := PackedVector3Array()
@export var saya_rotations := PackedVector3Array()
@export var saya_bows := PackedVector3Array()

# --- the SAYA's CONTROL beats (§2 of the Controlled Stillness brief) -------
#
# THE OTHER HALF OF THE SAME IDEA, AND THE DIFFERENCE IS THE POINT.
#
# `saya_positions` above says where the scabbard IS. It is a pose list, it is
# only ever authored on the draw family, and it exists because a draw is the one
# act in which the scabbard is being CARRIED somewhere.
#
# These say how far the LEFT HAND pushes the scabbard away from where it already
# rests. They are a SMALL OFFSET on top of the hand's own pose, in metres and
# radians, in the camera frame — so "3 cm to the left" is a sentence somebody can
# read and check, instead of an absolute point that has to be re-derived every
# time the hand moves.
#
# The distinction is not cosmetic. An absolute pose list makes every cut in the
# game state where the saya is, and a cut has almost nothing to say about a
# scabbard — which is how the first version of this came to have the saya follow
# the blade (0.21 m per cut) and the second version came to have it nailed to the
# camera (0.00 m per cut). The offset form says the true thing: the hand holds
# the scabbard, the scabbard is wherever the hand is, and a cut may ask the hand
# to give it a few centimetres for one reason — present the mouth, clear the
# blade path, receive the blade, tuck out of the way.
#
# ENTRY PER BEAT, on the move's own clock, walked by the same sampler as
# everything else. An absent or empty array means the move asks for NOTHING, and
# the saya rides the hand untouched — which is the correct answer for most moves
# and the reason this field is opt-in.
#
# `saya_ctrl_times` is its OWN clock rather than a reuse of `beat_times`, and
# that is not tidiness. Three of the four cuts are authored as four PHASES
# (anticipation / strike / follow / settle) and have no beat list at all, so a
# control channel nailed to `beat_times` could not be authored on them without
# first giving them a beat list they do not want. The hand's clock is allowed to
# be coarser than the blade's: the blade turns 89 degrees while the scabbard does
# two things.
@export var saya_ctrl_times := PackedFloat32Array()
@export var saya_ctrl_positions := PackedVector3Array()
@export var saya_ctrl_rotations := PackedVector3Array()


## When a buffered input is allowed to be remembered, as a fraction of the move.
##
## Separating this from `cancel_open` is the whole of §18. A cancel is "stop what
## you are doing and do this instead" and it opens as soon as the blade has been
## committed. A BUFFER is "remember this and start it when I finish", and if it
## is accepted from the first frame then a mashed button is remembered for the
## entire swing — four hundred milliseconds of memory wearing a hundred-and-
## fifty-millisecond name. The buffer opens only in the last slice of the move,
## which is the only window in which "I saw the end coming" is true.
func buffer_open_at() -> float:
	return startup + strike + pose_span() * 0.62


## The move's OWN clock, recovered from the controller's.
##
## `state_time` is already scaled: the controller compares it against
## `startup * move_startup_scale`, because a style may buy itself a faster
## wind-up. Every instant authored on this move — the events, the trace marks,
## the domain window — is written in the move's own seconds, so all of them have
## to be read on one clock or a buffed draw would fire A3's second cut before the
## first one had happened.
##
## Only the startup is scaled; the strike and the settle are not. That is not an
## approximation, it is the same rule `_move_end_time()` already uses.
func raw_time_at(scaled_time: float, startup_scale: float = 1.0) -> float:
	var scale := maxf(startup_scale, 0.0001)
	var stretched := startup * scale
	if scaled_time <= stretched:
		return maxf(scaled_time, 0.0) / scale
	return startup + (scaled_time - stretched)


func has_beats() -> bool:
	return beat_times.size() >= 2 and beat_positions.size() == beat_times.size() \
		and beat_rotations.size() == beat_times.size()


## Whether this move also choreographs the sheath, rather than letting the rig
## derive the seating from the blade. See `saya_positions`.
func has_saya_beats() -> bool:
	return has_beats() and saya_positions.size() == beat_times.size() \
		and saya_rotations.size() == beat_times.size()


## Whether this move asks the LEFT HAND for anything. See `saya_ctrl_positions`
## — absent is the normal case and means "the hand does not move for this cut".
func has_saya_ctrl() -> bool:
	var n := saya_ctrl_times.size()
	return n >= 2 and saya_ctrl_positions.size() == n \
		and saya_ctrl_rotations.size() == n


## The bow on segment `i`, or zero when the move carries none. Returned rather
## than indexed so a short or absent array is a straight segment instead of an
## error — a move that predates this field must keep working unchanged.
func bow_of(i: int) -> Vector3:
	if i < 0 or i >= beat_bows.size():
		return Vector3.ZERO
	return beat_bows[i]


func turn_bow_of(i: int) -> Vector3:
	if i < 0 or i >= beat_turn_bows.size():
		return Vector3.ZERO
	return beat_turn_bows[i]


func saya_bow_of(i: int) -> Vector3:
	if i < 0 or i >= saya_bows.size():
		return Vector3.ZERO
	return saya_bows[i]


func has_domain() -> bool:
	return domain_to > domain_from

@export_group("Rules")
@export var requires_hit := false
@export var followup_id: StringName = &""
@export var followup_window := 0.0
# Default: a follow-up opens on CONTACT (燕返 must be earned). A player-driven
# sequence like 长风 opts in to opening at the start instead, so a whiff cannot
# silently end the player's own combination.
@export var followup_from_start := false
@export var interrupt_bonus := 1.0
@export var in_air := false
# The player aims this cut: the side is taken from movement input when the move
# starts and the pose / hitbox are mirrored, so a signature sequence is steered
# rather than scripted.
@export var player_aimed := false
# 假章's feint. Every other move locks its exits until the blade has at least
# been committed; a feint is the one exception, because cancelling the wind-up
# IS the technique. < 1.0 = cancels unlock this far into startup, and the
# dodge gate is pulled back with them. Default 1.0 keeps every other move honest.
@export var feint_cancel_from := 1.0


func total_time() -> float:
	return startup + strike + follow_time + recovery


func strike_end() -> float:
	return startup + strike


func pose_span() -> float:
	return follow_time + recovery


func duplicate_move(overrides: Dictionary = {}) -> SwordMove:
	var move: SwordMove = duplicate()
	for key in overrides:
		move.set(key, overrides[key])
	return move
