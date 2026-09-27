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
			rotation = move.anchor_rot.lerp(move.wind_rot, w)
			intensity = w * 0.45
		Phase.STRIKE:
			progress = clampf((t - move.startup) / maxf(move.strike, 0.0001), 0.0, 1.0)
			var w := ease_in(progress, move.strike_power)
			position = move.wind.lerp(move.contact, w)
			rotation = move.wind_rot.lerp(move.contact_rot, w)
			intensity = 0.55 + progress * 0.45
		Phase.FOLLOW:
			progress = clampf((t - move.startup - move.strike) / maxf(move.follow_time * recovery_scale, 0.0001), 0.0, 1.0)
			var w := ease_out(progress, move.follow_power)
			position = move.contact.lerp(move.follow, w)
			rotation = move.contact_rot.lerp(move.follow_rot, w)
			if move.follow_overshoot > 0.0:
				var push := sin(progress * PI) * move.follow_overshoot
				position += (move.follow - move.contact) * push
				rotation += (move.follow_rot - move.contact_rot) * push
			intensity = 0.7 - progress * 0.5
		Phase.RECOVERY:
			progress = clampf(
				(t - move.startup - move.strike - move.follow_time) / maxf(move.recovery * recovery_scale, 0.0001),
				0.0, 1.0
			)
			var w := ease_out(progress, move.recovery_power)
			position = move.follow.lerp(move.recover, w)
			rotation = move.follow_rot.lerp(move.recover_rot, w)
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


static func ease_out(u: float, power: float) -> float:
	if power <= 1.0:
		return u
	return 1.0 - pow(1.0 - u, power)


static func ease_in_out(u: float) -> float:
	var x := clampf(u, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)
