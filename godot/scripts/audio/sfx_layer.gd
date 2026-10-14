extends Resource
class_name SfxLayer
## One layer of a cue: which atom group, how loud it sits RELATIVE to the cue's
## primary layer, when it enters, and how far it is allowed to drift.
##
## Layering rules that matter:
##   * The first thing the player perceives must be the cue's IDENTITY. A
##     perfect guard reads as a sharp metal transient first and a low boom
##     second - never three layers at the same loudness.
##   * If a mix is too thick, DELETE a layer. Do not turn everything down.
##   * If a mix is too thin, ADD a complementary layer. Do not go and render a
##     completely new "big" sound.

@export var group: StringName = &""
## dB relative to the cue's primary layer (the 0 dB layer), not absolute.
@export var gain_db := 0.0
## Seconds after the cue start. Audio scheduling ignores time_scale so hitstop
## does not smear a 40ms offset into a 200ms one.
@export var delay := 0.0
## Multiplier on top of the atom's own pitch range. Use it to pin a layer's
## colour across every cue that borrows it.
@export var pitch := 1.0
@export var pitch_jitter := 0.0
@export var gain_jitter := 0.0
## Optional layers are skipped when their atoms do not exist yet, so a cue
## stays playable while a P0 atom is still missing from the library.
@export var optional := false
@export var note := ""
