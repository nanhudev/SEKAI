extends RefCounted
class_name SwordPoseSampler
# Turns a SwordMove timeline into a first-person weapon pose.
#
# This exists because the old implementation lerped the weapon transform toward
# a target with a fixed response speed, which reads as "the sword is floating"
# rather than "someone is swinging a heavy object". Here the pose is the
# authored anticipation / contact / follow-through / settle, and any remaining
# softness is added by a spring in the pose driver, not by a tween.

enum Phase { STARTUP, STRIKE, FOLLOW, RECOVERY, DONE }


static func phase_of(move: SwordMove, t: float, recovery_scale: float = 1.0) -> Phase:
	if t < move.startup:
		return Phase.STARTUP
	if t < move.startup + move.strike:
		return Phase.STRIKE
	# The tail (follow-through + recovery) is what a style scales. Scaling only
	# the recovery would leave a long follow-through behind a fast style.
	var tail := recovery_scale
	var follow_end := move.startup + move.strike + move.follow_time * tail
	if t < follow_end:
		return Phase.FOLLOW
	if t < follow_end + move.recovery * tail:
		return Phase.RECOVERY
	return Phase.DONE


static func phase_name(phase: Phase) -> StringName:
	match phase:
		Phase.STARTUP: return &"startup"
		Phase.STRIKE: return &"strike"
		Phase.FOLLOW: return &"follow"
		Phase.RECOVERY: return &"recovery"
		_: return &"done"


static func sample(move: SwordMove, t: float, recovery_scale: float = 1.0) -> Dictionary:
	if move.has_beats():
		return sample_beats(move, t)
	var phase := phase_of(move, t, recovery_scale)
	var position := move.anchor
	var rotation := move.anchor_rot
	var intensity := 0.0
	var progress := 0.0
	match phase:
		Phase.STARTUP:
			progress = clampf(t / maxf(move.startup, 0.0001), 0.0, 1.0)
			# High anticipation_power = the blade stays put, then snaps.
			var w := ease_in(progress, move.anticipation_power)
			position = move.anchor.lerp(move.wind, w)
			rotation = arc(move.anchor_rot, move.wind_rot, w)
			intensity = w * 0.45
		Phase.STRIKE:
			progress = clampf((t - move.startup) / maxf(move.strike, 0.0001), 0.0, 1.0)
			var w := ease_in(progress, move.strike_power)
			position = move.wind.lerp(move.contact, w)
			rotation = arc(move.wind_rot, move.contact_rot, w)
			intensity = 0.55 + progress * 0.45
		Phase.FOLLOW:
			progress = clampf((t - move.startup - move.strike) / maxf(move.follow_time * recovery_scale, 0.0001), 0.0, 1.0)
			var w := ease_out(progress, move.follow_power)
			position = move.contact.lerp(move.follow, w)
			rotation = arc(move.contact_rot, move.follow_rot, w)
			if move.follow_overshoot > 0.0:
				var push := sin(progress * PI) * move.follow_overshoot
				position += (move.follow - move.contact) * push
				rotation += (move.follow_rot - move.contact_rot) * push
			intensity = 0.7 - progress * 0.5
		Phase.RECOVERY:
			progress = clampf(
				(t - move.startup - move.strike - move.follow_time * recovery_scale) / maxf(move.recovery * recovery_scale, 0.0001),
				0.0, 1.0
			)
			var w := ease_out(progress, move.recovery_power)
			position = move.follow.lerp(move.recover, w)
			rotation = arc(move.follow_rot, move.recover_rot, w)
			if move.recover_sag > 0.0:
				position.y -= sin(progress * PI) * move.recover_sag
			intensity = maxf(0.0, 0.25 * (1.0 - progress))
		Phase.DONE:
			position = move.recover
			rotation = move.recover_rot
	return {
		"position": position,
		"rotation": rotation,
		"phase": phase_name(phase),
		"phase_index": phase,
		"progress": progress,
		"intensity": clampf(intensity, 0.0, 1.0),
	}


static func ease_in(u: float, power: float) -> float:
	if power <= 1.0:
		return u
	return pow(u, power)


# ---------------------------------------------------------------------------
# arc · blend two authored rotations AS ROTATIONS
# ---------------------------------------------------------------------------
#
# Every pose in this project is a euler triple, because that is what `aim_euler`
# solves and what a beat list stores. So every blend between two poses was
# written the way any two vectors are blended, and that is the wrong operation:
#
#     a.lerp(b, u)                                   # a straight line in ANGLE space
#     Basis.from_euler(a).slerp(Basis.from_euler(b), u)   # an arc in ROTATION space
#
# The two agree exactly at `u = 0` and `u = 1`, which is why this survived: every
# beat is reached exactly, every endpoint assertion passes, and the error lives
# in the interior of every segment where nothing was looking.
#
# `tools/probe_orientation_arc.gd` measured what the interior was doing, on the
# authored key pairs themselves, and the answer was not "slightly off":
#
#     sb_a1   wind → contact    strays 179.0 deg   (arc 138.2, walked 226.5)
#     sb_a3   beat 4 → 5        strays 179.4 deg   (arc 150.9, walked 211.1)
#     sb_a3   beat 12 → 13      strays 179.3 deg   (arc 131.5, walked 232.3)
#     sb_a4   wind → contact    strays  44.7 deg   (arc 175.9, walked 197.5)
#     sb_equip beat 0 → 1       strays   7.4 deg   (arc  88.9, walked  90.3)
#
# Three of those are not bulges, they are ROUTES: the blade turned 226 degrees
# where the two poses it was given are 138 apart, i.e. it swung the long way
# round. §18 of the Controlled Stillness brief is exactly this — "a large pose
# change must travel a real arc, the quaternion's shortest path or an explicitly
# authored intermediate pose".
#
# So this is the one operation, in one place, and every caller uses it. Anything
# that blends a rotation by blending its three angles is the same fault.
#
# THE ENDS ARE THE AUTHORED TRIPLES THEMSELVES, not `get_euler()` of the result.
# A slerp that lands on the antipodal representative of its target describes the
# same rotation, but `get_euler()` may write it as a different triple, and any
# downstream `a + offset` or `a.lerp(b, k)` on the triple would then step across
# that branch change. Returning the authored value at the ends keeps the beats
# byte-exact and is what every existing beat assertion already expects.
static func arc(from: Vector3, to: Vector3, weight: float) -> Vector3:
	if weight <= 0.0:
		return from
	if weight >= 1.0:
		return to
	return Basis.from_euler(from).slerp(Basis.from_euler(to), weight).get_euler()


# ---------------------------------------------------------------------------
# angle_between · how far apart two rotations are, IN A WAY THAT CAN BE ZERO
# ---------------------------------------------------------------------------
#
# This is the inverse of `arc`, and it exists because Godot's own
# `Quaternion.angle_to` cannot answer it. That function is
#
#     acos(clamp(dot * dot * 2 - 1, -1, 1))
#
# and `acos` is infinitely steep at 1, so it turns float32 rounding into a
# visible angle: measured on this project's own build,
#
#     Quaternion.angle_to(itself) == 0.055953 degrees
#
# for a quaternion whose length is 0.99999994 — which is every quaternion that
# has been through a `Basis`. The consequence is not a rounding report, it is a
# wrong one: any path length accumulated from `angle_to` gains 0.056 degrees per
# SAMPLE, so a segment that does not move at all measures 10.7 degrees at 600 Hz,
# and a REAL turn is over-reported by 5 to 15 degrees depending only on how long
# it takes. The first edition of `probe_orientation_arc.gd` was built on it and
# reported `sb_equip`'s hold beats as turning 191 times their own arc.
#
# The identity that fixes it is the same one, rearranged so the small case is the
# well-conditioned one. For two unit quaternions whose dot is `cos(t/2)`,
#
#     |a - b|^2 = 2 - 2cos(t/2) = 4 sin^2(t/4)   =>   t = 4 * asin(|a - b| / 2)
#
# and `asin` is FLATTEST at zero, which is where a path length spends its time.
# The sign fix is what makes it the shortest angle rather than the long way: `q`
# and `-q` are the same rotation, and without the flip the difference vector has
# length 2 at zero rotation.
static func angle_between(a: Quaternion, b: Quaternion) -> float:
	var to := b if a.dot(b) >= 0.0 else -b
	return rad_to_deg(4.0 * asin(clampf((a - to).length() * 0.5, 0.0, 1.0)))


# ---------------------------------------------------------------------------
# THE BEAT LIST
# ---------------------------------------------------------------------------
#
# A3 is three cuts and two returns inside one attack, so its pose is a list of
# beats rather than four phases. Sampling it is the same contract as everything
# else in this file: the answer for `t` depends on `t` and on the move, and on
# nothing that happened before `t`.
#
# The one authoring rule the curve enforces is that a beat's own instant is
# reached EXACTLY. Between beats the pose is smoothed, but AT a beat the blade
# is where the beat says it is — otherwise a cut that is supposed to happen at
# 0.54s happens somewhere near 0.54s, and the event the VFX listens to and the
# pose the player sees become two different cuts.
static func sample_beats(move: SwordMove, t: float) -> Dictionary:
	var times := move.beat_times
	var count := times.size()
	if t <= times[0]:
		return _beat_result(move, 0, 0.0)
	if t >= times[count - 1]:
		return _beat_result(move, count - 2, 1.0)
	for i in count - 1:
		if t >= times[i] and t < times[i + 1]:
			var span := maxf(times[i + 1] - times[i], 0.0001)
			return _beat_result(move, i, clampf((t - times[i]) / span, 0.0, 1.0))
	return _beat_result(move, count - 2, 1.0)


static func _beat_result(move: SwordMove, index: int, u: float) -> Dictionary:
	var eased := ease_in_out(u)
	var position: Vector3 = move.beat_positions[index].lerp(
		move.beat_positions[index + 1], eased
	)
	var rotation: Vector3 = arc(move.beat_rotations[index],
		move.beat_rotations[index + 1], eased)
	# THE BOW. A segment is a chord by default, which is right for a cut and
	# wrong for a draw — see `SwordMove.beat_bows` for the 16.4 mm of measured
	# scabbard curvature that makes it wrong. `4u(1-u)` is 0 at both ends and 1
	# at the middle, so a beat's own instant is still reached EXACTLY: the bow
	# can bend the path between two beats and can never move a beat itself.
	#
	# The same curve is applied to the eased `u` rather than to a raw one, so the
	# bow peaks where the movement is actually fastest rather than at the
	# arithmetic midpoint of the window.
	var bend := 4.0 * eased * (1.0 - eased)
	position += move.bow_of(index) * bend
	rotation += move.turn_bow_of(index) * bend
	return {
		"position": position,
		"rotation": rotation,
		"phase": &"beat",
		"phase_index": index,
		"progress": u,
		# Intensity is what the trail width and the tremor read. A beat list has
		# no anticipation/strike labels to take it from, so it is taken from the
		# work: how far the blade is asked to travel between these two beats, per
		# second. A return to the saya is slow and reads as quiet; a cut is fast.
		#
		# Computed from the beats themselves rather than stored, so retuning a
		# beat cannot leave a stale intensity behind on the trail.
		"intensity": beat_intensity(move, index),
	}


## The same walk, over a bare set of arrays instead of a SwordMove's own beats.
##
## §2's ONE WEAPON SYSTEM is the reason this exists. The sheath's beats live on
## the same clock as the blade's but are not the blade's, so the sampler has to
## be able to answer "where is the saya" without pretending the saya is a sword.
## Sharing the walk rather than copying it is what keeps the two from drifting:
## a bezier fix, an easing change or a beat-exactness rule lands in both at once,
## because there is only one of each.
##
## Returns an empty dictionary when the arrays are too short to walk, which the
## caller reads as "this move does not choreograph the sheath".
static func sample_arrays(times: PackedFloat32Array, positions: PackedVector3Array,
		rotations: PackedVector3Array, bows: PackedVector3Array, t: float) -> Dictionary:
	var count := times.size()
	if count < 2 or positions.size() != count or rotations.size() != count:
		return {}
	if t <= times[0]:
		return _arrays_result(positions, rotations, bows, 0, 0.0)
	if t >= times[count - 1]:
		return _arrays_result(positions, rotations, bows, count - 2, 1.0)
	for i in count - 1:
		if t >= times[i] and t < times[i + 1]:
			var span := maxf(times[i + 1] - times[i], 0.0001)
			return _arrays_result(positions, rotations, bows, i,
				clampf((t - times[i]) / span, 0.0, 1.0))
	return _arrays_result(positions, rotations, bows, count - 2, 1.0)


static func _arrays_result(positions: PackedVector3Array, rotations: PackedVector3Array,
		bows: PackedVector3Array, index: int, u: float) -> Dictionary:
	var eased := ease_in_out(u)
	var position: Vector3 = positions[index].lerp(positions[index + 1], eased)
	var rotation: Vector3 = arc(rotations[index], rotations[index + 1], eased)
	var bend := 4.0 * eased * (1.0 - eased)
	if index < bows.size():
		position += bows[index] * bend
	return {"position": position, "rotation": rotation, "progress": u}


## How hard the blade is working between beat `index` and the one after it.
## 1.0 is a full-speed cut; a beat that barely moves returns near zero.
static func beat_intensity(move: SwordMove, index: int) -> float:
	if index < 0 or index + 1 >= move.beat_times.size():
		return 0.0
	var span := maxf(move.beat_times[index + 1] - move.beat_times[index], 0.0001)
	var travel: float = move.beat_positions[index].distance_to(move.beat_positions[index + 1])
	# 3.0 m/s is a full-blooded cut at this scale: the pose keys live in a metre
	# box in front of the chest, so a blade crossing most of it in a third of a
	# second is the fast case.
	return clampf(travel / span / 3.0, 0.0, 1.0)


static func ease_out(u: float, power: float) -> float:
	if power <= 1.0:
		return u
	return 1.0 - pow(1.0 - u, power)


static func ease_in_out(u: float) -> float:
	var x := clampf(u, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)
