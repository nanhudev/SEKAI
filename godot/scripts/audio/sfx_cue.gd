extends Resource
class_name SfxCue
## A named combination of atoms. Gameplay asks for a cue id and never builds
## its own stack of AudioStreamPlayers.
##
## A cue is authored as a vertical stack: one layer owns the identity (0 dB),
## the rest support it. Timing differences between layers are what turn a pile
## of samples into one event.

@export var id: StringName = &""
@export var bus: StringName = &"SFX"
## Master trim for the whole cue. Use for mix passes, not for per-hit dynamics.
@export var gain_db := 0.0
@export var layers: Array[SfxLayer] = []
## PART M. False = the PLAYER LAYER: the sound is in the player's hands (air,
## blade movement, cloth, handle) and is heard the same wherever the camera points.
## True = the CONTACT LAYER: it happened somewhere in the world (a stone facing, a
## body, a frozen shell) and has to arrive from that direction, or the player feels
## the hit land on themselves instead of on the target.
@export var spatial := false
## What the player should perceive first. Written down so the next person
## retuning this cue knows what they are allowed to break.
@export var intent := ""


## `pitch_jitter` / `gain_jitter` are the anti-machine-gun dial (§17). A round-robin
## cursor alone still plays each seed at exactly one level, and a player who spams a
## light cut hears the same four numbers in the same order. They are trailing
## arguments so every existing caller keeps working.
func layer(group: StringName, gain_db_value: float, delay_value := 0.0,
		pitch_value := 1.0, optional := false, note := "",
		pitch_jitter_value := 0.0, gain_jitter_value := 0.0) -> SfxCue:
	var entry := SfxLayer.new()
	entry.group = group
	entry.gain_db = gain_db_value
	entry.delay = delay_value
	entry.pitch = pitch_value
	entry.optional = optional
	entry.note = note
	entry.pitch_jitter = pitch_jitter_value
	entry.gain_jitter = gain_jitter_value
	layers.append(entry)
	return self


func primary_group() -> StringName:
	var best_group: StringName = &""
	var best_gain := -INF
	for entry in layers:
		if entry.gain_db > best_gain:
			best_gain = entry.gain_db
			best_group = entry.group
	return best_group
