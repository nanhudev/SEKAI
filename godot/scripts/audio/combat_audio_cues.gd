extends RefCounted
class_name CombatAudioCues
## The SWORD cue table: every answer the sword can give, written as a stack of
## atom groups instead of a pile of wav files.
##
## WHAT THIS FILE IS FOR. The sword used to have one vocabulary - `air_fast` plus a
## little cloth - so A1 and A3 were the same recording at two pitches and the blade
## itself was never audible. So eight new families were generated, and then measured,
## and MOST OF THEM WERE WORSE THAN THE TWELVE ATOMS THEY WERE MEANT TO REPLACE.
##
## That is the single result this table is now built on, so it is worth stating as
## numbers. Band split of the whole file, energy weighted, measured by
## `audio_source/tools/atom_bands.py`:
##
##   air_fast        (core, approved)   edge 49.9%  air  3.0%  centroid 2294 Hz
##   air_cut_light   (generated)        edge  8.5%  air  7.4%  centroid 1943 Hz
##   metal_sharp     (core, approved)   edge 35.2%  air 11.7%  centroid 2616 Hz  0.07 s
##   perfect_guard_sharp (generated)    edge 46.9%  air 38.5%  centroid 6049 Hz  0.41 s
##   metal_body      (core, approved)   edge  1.0%  air  1.1%  centroid  330 Hz  0.14 s
##   guard_metal     (generated)        edge 84.6%  air  5.0%  centroid 3339 Hz  0.58 s
##
## A "fast air cut" whose energy is 8% above 2 kHz is not a blade moving fast; it is
## a huff. A perfect guard whose energy is 38% above 6.5 kHz is a hiss, and the
## core registry already had an atom whose own note reads "perfect guard PRIMARY"
## and which is 70 ms long - so CLANG -> SILENCE is a property of the atom and cannot
## creep back in when a seed changes. And a BLOCK whose energy is 85% in 2-6.5 kHz is
## a clash, i.e. the one thing a block must not be if a perfect guard is to be told
## apart from it.
##
## So the identities are the CORE atoms again, and the generated families are kept
## only where they are the right substance and demoted to where they are the right
## SHAPE (a low-mid body under a heavy, not its voice).
##
##   `air_fast`       did that move happen, and how fast - pitch IS the combo step
##   `blade_move_*`   is this a steel object, or just moving air
##   `weapon_body_*`  does the thing in my hands have mass
##   `body_low` / `cloth_fast`        is a PERSON holding it
##   `metal_body`     did I stop it: dull, absorbed, 0.14 s
##   `metal_sharp`    did I stop it ON TIME: a 0.07 s hard tick
##   `riposte_release` the advantage being spent
##   `sword_contact_*` WHAT DID IT LAND ON
##
## RULES, all of them learned by getting them wrong:
##   * A swing and a hit are DIFFERENT cues. Whiffing is air; connecting adds the
##     material layer. That difference is what makes the sword report the world.
##   * The 0 dB layer is the identity - the first thing perceived. Support sits
##     below it and is never equally loud. A perfect guard that starts with a low
##     boom has stopped being a perfect guard.
##   * Light 1 / 2 / 3 are ONE language at three SPEEDS, not three recordings. Measured
##     isolated, pass 01's L1 and L2 were 0.5 dB and 1% of centroid apart - closer to
##     each other than one cue's own three seeds were to each other. Here they are
##     pitched 0.94 / 1.22 / 0.80 apart and L2 additionally carries the steel that L1
##     does not and L3 the mass neither has.
##   * Heavy is not "everything louder". It is TWO cues: a quiet wind-up (cloth +
##     grip) and a release that only then gets wide. Put a low body on the wind-up and
##     the whole swing turns into a drone.
##   * `_contact` cues are SPATIAL (PART M). A stone facing does not sound like it
##     is in the player's hands.
##
## Surface layers are declared and left optional on purpose: the optional flag
## keeps a cue playable while a P0 atom is still missing from the library.

## material -> the cue that answers it. Gameplay sends the material, NEVER a file.
## `flesh` is the default because every actor that exists is a body.
const MATERIAL_CUE := {
	&"flesh": &"sword_contact_body",
	&"body": &"sword_contact_body",
	&"stone": &"sword_contact_stone",
	&"metal": &"sword_contact_metal",
	&"wood": &"sword_contact_wood",
	&"ice": &"sword_contact_ice",
	&"frozen": &"sword_contact_ice",
}


static func build() -> Dictionary:
	var cues: Dictionary = {}
	_add(cues, _light(1))
	_add(cues, _light(2))
	_add(cues, _light(3))
	_add(cues, _heavy_windup())
	_add(cues, _heavy_release())
	_add(cues, _block())
	_add(cues, _perfect_guard())
	_add(cues, _riposte())
	_add(cues, _contact_body())
	_add(cues, _contact_stone())
	_add(cues, _contact_metal())
	_add(cues, _contact_wood())
	_add(cues, _contact_ice())
	_add(cues, _hit_weight())
	_add(cues, _shatter())
	_add(cues, _dodge())
	_add(cues, _wind_burst())
	# The basic sentence's own four beats. Kept in `SwordBasicCues` because they
	# are not steps on the generic light ladder — see that file's header for why
	# re-purposing `sword_light_1/2/3` was not an option. Merged rather than
	# accessed separately so the director keeps ONE table and ONE lookup.
	var basic := SwordBasicCues.build()
	for cue_id in basic:
		cues[cue_id] = basic[cue_id]
	return cues


static func _add(cues: Dictionary, cue: SfxCue) -> void:
	cues[cue.id] = cue


static func _new(id: StringName, intent: String, spatial := false) -> SfxCue:
	var cue := SfxCue.new()
	cue.id = id
	cue.intent = intent
	cue.spatial = spatial
	return cue


# ------------------------------------------------------------------- light

## A1 / A2 / A3 - ONE blade at three speeds.
##
## The combo step is expressed as the SPEED of the same air, because that is what it
## physically is: the same sword, cutting at three sizes of arc. Each step also gets
## exactly one thing the previous step did not have - L2 gets steel, L3 gets mass -
## so the difference is audible in three independent channels rather than in one.
##
##   L1  pitch 0.94   air + cloth            the opener, and NOT the loudest
##   L2  pitch 1.22   air + steel + cloth    shorter and faster: L1's momentum
##   L3  pitch 0.80   air + blade + mass     the largest arc, the only one with weight
static func _light(index: int) -> SfxCue:
	match index:
		2:
			return _light_two()
		3:
			return _light_three()
	var cue := _new(&"sword_light_1",
		"the opener: air only, at the blade's own speed, and no steel at all")
	# §17. A round-robin cursor alone still plays each seed at exactly ONE level, so a
	# player mashing a light attack hears four fixed numbers in a fixed order. ±2.5% of
	# pitch and ±1 dB is under the threshold where a hit stops sounding like itself and
	# over the threshold where two identical hits stop sounding identical.
	cue.layer(&"air_fast", 0.0, 0.0, 0.94, false, "air is the identity: how fast that arc was",
		0.025, 1.0)
	cue.layer(&"cloth_fast", -12.0, 0.004, 1.0, false, "", 0.02, 1.0)
	return cue


static func _light_two() -> SfxCue:
	var cue := _new(&"sword_light_2",
		"carried by L1: faster and shorter, and the steel has caught up")
	cue.layer(&"air_fast", -1.0, 0.0, 1.22, false, "", 0.025, 1.0)
	# NOT `blade_move_light`. Its three seeds measure 1374 / 2865 / 4183 Hz of centroid
	# - 1.6 octaves apart - so one play in three was a different sound, and a cue that
	# must sound like itself on every second light input cannot be built on it. §17 asks
	# for variety that does not change the identity; this atom changes the identity.
	# `metal_sharp` (two seeds, 2616 and 2564 Hz) and `cloth_fast` (one seed) are stable.
	cue.layer(&"metal_sharp", -13.0, 0.006, 1.02, false, "the steel has caught up, barely",
		0.02, 1.0)
	cue.layer(&"cloth_fast", -12.0, 0.003, 1.02, false, "", 0.02, 1.0)
	return cue


static func _light_three() -> SfxCue:
	var cue := _new(&"sword_light_3",
		"the finisher: the largest arc, a real blade, and weight - but NOT an explosion")
	cue.layer(&"air_fast", 0.0, 0.0, 0.80, false, "", 0.02, 0.8)
	# Same air, 30% slower: the whole combo is one blade at three speeds, which is what
	# makes L1 / L2 / L3 a language instead of three recordings. The two extra layers are
	# the only ones the other two steps do not have.
	cue.layer(&"metal_sharp", -9.0, 0.006, 0.96, false, "the guard taking the blow", 0.02, 0.8)
	# `metal_body` is 0.14 s and 72% below 160 Hz: the guard's mass arriving, and over
	# before the next input. It has ONE variant, so it cannot drift between plays.
	cue.layer(&"metal_body", -16.0, 0.012, 0.98, false, "the mass of the guard arriving after the blade")
	cue.layer(&"cloth_fast", -10.0, 0.004, 0.98, false, "", 0.02, 0.8)
	return cue


# ------------------------------------------------------------------- heavy

## Heavy is TWO cues because it is two MOMENTS. The wind-up is quiet on purpose: it
## is the body coiling, and the air has not moved yet. Sound the wind-up as loudly as
## the release and there is no release left to hear.
##
## A NOTE ON EVERY `pressure_low` GAIN BELOW. `SoundAtom` trims by measured peak, so a
## gain a reviewer reads here is NOT the gain that plays: `pressure_low_01.wav` peaks
## at -10.2 dBFS, which hands it a +4.2 dB base trim. Written as -9 it played at
## -4.8 dB, i.e. the SECOND LOUDEST layer in every cue that used it - a layer whose own
## registry note says "NOT a low whoosh". Written as -16 it plays at -11.8.
static func _heavy_windup() -> SfxCue:
	var cue := _new(&"sword_heavy_windup",
		"the body coiling: cloth, a re-gripped hand, and air gathering - no cut yet")
	cue.layer(&"cloth_heavy", 0.0, 0.0, 0.94)
	# `cloth_heavy` alone is a 1.3 s body with a 330 Hz centroid - correct for length,
	# too dark to be cloth. `cloth_fast` is the approved 0.20 s cloth at 2367 Hz and
	# supplies the audible detail under it.
	cue.layer(&"cloth_fast", -5.0, 0.010, 0.90, false, "the fabric actually rustling")
	cue.layer(&"grip_shift", -8.0, 0.020, 1.0, false, "intent, not force")
	cue.layer(&"pressure_low", -16.0, 0.060, 0.97, false,
		"air displaced before the blade arrives: felt, not heard")
	return cue


static func _heavy_release() -> SfxCue:
	var cue := _new(&"sword_heavy_release",
		"the release: the blade's steel leads, displaced air under it, and mass behind")
	# THE IDENTITY IS THE BLADE, NOT THE AIR. `blade_move_heavy` is 79% of its energy
	# in 2-6.5 kHz at a 4400 Hz centroid over 0.80 s - a wide steel edge. Pass 01 led
	# with `air_cut_heavy` (edge 0.7%, centroid 337 Hz) and the release measured 48-58%
	# below 160 Hz: a whoomp. Heavy is allowed to be big; it is not allowed to be
	# mostly sub-bass, because that is a boom and the boom is PART B's forbidden fix.
	cue.layer(&"blade_move_heavy", 0.0, 0.0, 0.95)
	# Demoted, not deleted: this IS the displaced air, it is just the body of the sound
	# rather than its voice.
	cue.layer(&"air_cut_heavy", -4.0, 0.004, 0.90, false, "the air the blade shoved out of the way")
	cue.layer(&"air_fast", -7.0, 0.008, 0.70, false, "the same air again, an octave down and longer")
	cue.layer(&"weapon_body_heavy", -11.0, 0.010, 0.99, false, "the weapon's mass, arriving after the blade")
	cue.layer(&"pressure_low", -13.0, 0.020, 0.98)
	cue.layer(&"cloth_fast", -13.0, 0.0, 1.0, false, "a person is holding it")
	return cue


# ------------------------------------------------------------------ defense

## ORDINARY BLOCK. Solid metal contact, dull, edge did not bite, and a SHORT tail.
##
## BOTH defense cues now lead with a CORE atom, and the reason is the PAIR, not the two
## sounds individually. Measured isolated (cue sheet, three passes each):
##
##   block          edge 59 / 81 / 64 %   centroid 3108 / 3950 / 3035 Hz   tail up to 1.40 s
##   perfect guard  edge 20 / 49 / 36 %   centroid 2046 / 3821 / 4436 Hz   tail up to 1.49 s
##
## i.e. the BLOCK was the brighter, edgier metal sound, and by the third seed the
## perfect guard was the darker one. PART D wants a perfect guard that is brighter,
## sharper and cleaner than a block "by one ear, not by +6 dB", and the atom choice
## made that seed-dependent. The repair is not a level: `metal_body` is 0.14 s with 1%
## of its energy above 2 kHz, `metal_sharp` is 0.07 s with 35%. Point either role at
## the wrong one and no amount of mixing restores it.
static func _block() -> SfxCue:
	var cue := _new(&"sword_block",
		"absorbed: a dull metal body, almost no edge, over before the next beat")
	# +5 on the cue, not on a layer: measured isolated, `metal_body` is so dense
	# (crest 10.2) that the block came out 6 dB under every other contact, and a block
	# the player cannot hear is a block they cannot learn to time.
	cue.gain_db = 5.0
	cue.layer(&"metal_body", 0.0, 0.0, 1.0, false, "", 0.03, 1.2)
	# -2, not -11. At -11 the block measured 0.1% of its energy above 2 kHz, i.e. a
	# mallet: absorbed, yes, but no longer METAL. The dull body is the identity; this
	# is the edge of the blade that just got stopped, and it is the only thing that
	# separates a block from a body hit.
	cue.layer(&"metal_sharp", -2.0, 0.004, 0.96, false, "the edge that just got stopped",
		0.03, 1.2)
	cue.layer(&"body_low", -13.0, 0.004, 1.0, false, "the shock in the hands", 0.02, 1.0)
	return cue


## PERFECT GUARD. The most important auditory event in the sword's language, and it
## is NOT "block, louder".
##
## A block's identity is a dull metal BODY. A perfect guard's identity is a clean
## sharp TRANSIENT with nothing in front of it and nothing hanging off it: the
## player has to hear CLANG -> SILENCE, which is exactly what the hitstop is doing
## to the world.
##
## CLANG -> SILENCE IS NOW A PROPERTY OF THE ATOM. `metal_sharp` is 70 ms long. Pass 01
## used a 0.41 s atom whose energy was 38% above 6.5 kHz - a hiss with a tail - and the
## hitstop spent the next quarter of a second fighting it. A tail that cannot exist
## cannot come back when a seed changes.
static func _perfect_guard() -> SfxCue:
	var cue := _new(&"sword_perfect_guard",
		"deflected ON TIME: a hard 70 ms tick and its second edge, then nothing")
	# Above the block, and by ~1.5 dB rather than by 6: §15 asks for TRANSIENT CLARITY
	# here, not for the loudest sound in the game.
	cue.gain_db = 7.0
	cue.layer(&"metal_sharp", 0.0, 0.0, 1.0)
	# The same group twice, 10 ms apart: two edges of one clang is what makes it read
	# as a blade caught on a blade rather than as a click.
	cue.layer(&"metal_sharp", -2.5, 0.010, 1.06, false, "the other edge of the same clang")
	cue.layer(&"metal_body", -10.0, 0.012, 1.02, false, "something heavy stopped - a hint, not a thud")
	cue.layer(&"blade_ring_short", -8.0, 0.006, 1.06, false, "one short ring, then nothing")
	return cue


## RIPOSTE. Not a new skill - the advantage the perfect guard just bought being
## spent. The release IS the identity; the air and the blade are what make it a cut
## rather than a click.
##
## The tick that opens it is the SAME tick the perfect guard closed on, deliberately:
## the player hears their own parry come back as the thing that pays for it. Pass 01
## led with `riposte_release`, which is 44% of its energy above 6.5 kHz, so the
## "focused release" was a hiss - and it measured a 4.0 dB swing between its own seeds
## (-7.3 / -4.0 / -8.0), which is a cue that sometimes does not sound like itself.
static func _riposte() -> SfxCue:
	var cue := _new(&"sword_riposte",
		"the advantage spent: the perfect guard's own tick, then the cut it pays for")
	cue.layer(&"metal_sharp", 0.0, 0.0, 1.02)
	cue.layer(&"blade_slide_short", -6.0, 0.004, 1.0, false, "the advantage, spent")
	cue.layer(&"air_fast", -7.0, 0.008, 1.12, false, "the cut that the release pays for")
	return cue


# ---------------------------------------------------------------- contact

## THE MATERIAL SYSTEM (§PART F). One family per substance, chosen by what was hit
## rather than by which attack hit it, so a new weapon inherits all five for free.
##
## All five are SPATIAL: the contact has to arrive from where it happened.
##
## The stack is always the same three jobs - the surface answering, the blade's
## edge, and the mass that carried it - and only the surface changes.
##
## EVERY CONTACT CARRIES `cue.gain_db = +3.0` BELOW, and it is a measured number, not
## taste. Played isolated at the same nominal gain and the same 1.75 m, the five
## contacts measured -5.8 to -7.6 dBFS while the light cuts measured -5.6 to -6.3: a
## sword landing on a stone facing was QUIETER than the swing that got there. §15 puts
## a normal hit above a light sword, and a contact is also the one family played from
## a 3D source, so it needs the trim the player layer does not.
static func _contact_body() -> SfxCue:
	var cue := _new(&"sword_contact_body",
		"SWORD_CONTACT_BODY: stylized. A dull body, a small blade slice, no gore", true)
	cue.gain_db = 3.0
	cue.layer(&"sword_contact_body", 0.0, 0.0, 1.0)
	cue.layer(&"blade_slide_short", -9.0, 0.020, 1.0, false, "the edge passing through")
	# `body_impact` is a 0.37 s sub with a 61-77 Hz centroid, i.e. inaudible on most
	# devices; `body_low` is the same job at 192 Hz and is actually heard.
	cue.layer(&"body_low", -8.0, 0.0, 1.0, false, "the shared body layer under it")
	cue.layer(&"metal_sharp", -16.0, 0.004, 0.94, false, "the edge, barely")
	return cue


static func _contact_stone() -> SfxCue:
	var cue := _new(&"sword_contact_stone",
		"SWORD_CONTACT_STONE: a chip of stone, and the edge that chipped it - NOT a hammer", true)
	cue.gain_db = 3.0
	# The identity is the layer that has to be stable, and the registry now culls
	# `sword_contact_stone_01_A` for being the odd seed of three - the measurement is in
	# CULLED_ATOMS. Two consistent variants alternate instead of three uneven ones.
	cue.layer(&"sword_contact_stone", 0.0, 0.0, 1.0)
	cue.layer(&"stone_chip", -6.0, 0.015, 1.0, false, "debris answering")
	cue.layer(&"metal_sharp", -9.0, 0.004, 0.98, false, "the edge, not the stone")
	cue.layer(&"body_low", -22.0, 0.006, 0.94, false, "a hint of mass behind it")
	return cue


static func _contact_metal() -> SfxCue:
	var cue := _new(&"sword_contact_metal",
		"SWORD_CONTACT_METAL: a hard metal transient, then a short ring", true)
	cue.gain_db = 3.0
	# `metal_contact_heavy` is the best atom in the set - 65-77% of its energy in
	# 2-6.5 kHz, under 1% below 160 Hz - so it leads and the rest is trim. Pass 01 put
	# a third layer at -9 underneath and the cue swung 3.8 dB between seeds; the extra
	# layer bought no timbre and cost consistency.
	cue.layer(&"metal_contact_heavy", 0.0, 0.0, 1.0)
	cue.layer(&"blade_ring_short", -8.0, 0.007, 1.02)
	# `metal_body` was at -7 here and is GONE: it is dense (crest 10.2) against a spiky
	# identity, so whether its 0.14 s peak coincided with the attack decided the cue's
	# colour - measured, the same cue came out at 3889 Hz and at 2244 Hz on alternate
	# plays. A layer that changes the identity when its phase is unlucky is not a
	# support layer.
	return cue
	return cue


static func _contact_wood() -> SfxCue:
	var cue := _new(&"sword_contact_wood",
		"SWORD_CONTACT_WOOD: a dry cut, then the timber giving way", true)
	cue.gain_db = 3.0
	cue.layer(&"sword_contact_wood", 0.0, 0.0, 1.0)
	# Measured isolated, this cue was 73-79% in 2-6.5 kHz with 1-4% below 160 Hz: a
	# metallic crack with no timber behind it. `wood_crack` is the layer that carries
	# the wood and it was sitting at -5 under a bright identity.
	cue.layer(&"wood_crack", -2.0, 0.018, 1.0, false, "the timber taking the blow")
	cue.layer(&"body_low", -14.0, 0.006, 0.95, false, "a hint of mass behind it")
	cue.layer(&"blade_slide_short", -13.0, 0.010, 1.0)
	return cue


static func _contact_ice() -> SfxCue:
	var cue := _new(&"sword_contact_ice",
		"SWORD_CONTACT_ICE: the blade arriving on frozen matter - stress, not shatter", true)
	cue.gain_db = 3.0
	# THE IDENTITY IS `crystal_break`, NOT `ice_impact`. Measured: ice_impact is 56-71%
	# of its energy above 6.5 kHz and ice_crack 42-57% - a blade landing on a frozen
	# shell was a white-noise hiss. crystal_break is 3-13% below 160 Hz and 22-44% in
	# the 160-2k body band, so it is the one atom in the family that is a SUBSTANCE.
	# Contact and shatter now share it on purpose: the contact is the shell taking the
	# news, the shatter is the shell failing.
	cue.layer(&"crystal_break", 0.0, 0.0, 1.0)
	cue.layer(&"metal_sharp", -5.0, 0.0, 0.96, false, "the blade that delivered it")
	cue.layer(&"ice_crack", -9.0, 0.004, 1.0, false, "the frozen shell taking the news")
	# -22, not -16: with `body_low` at -16 this cue measured 48-61% below 160 Hz, i.e. a
	# thud. A blade on a frozen shell is brittle - the mass is a rumour under it.
	cue.layer(&"body_low", -22.0, 0.008, 0.96)
	return cue


## The accent that a HEAVY connect adds on top of whatever material it met. Kept
## separate from the material cues so that "what it hit" and "how hard it hit" stay
## two independent decisions - the alternative is five more cues nobody asked for.
##
## THIS CUE USED TO BE THE LOUDEST THING IN THE GAME AND IT WAS PURE SUB-BASS.
## Measured isolated: peak -0.7 / -6.8 / -2.9 dBFS, 87-89% of its energy below 160 Hz,
## and ZERO percent above 2 kHz. Its registry layers were `low_impact_short` (a 26 Hz
## centroid) and `pressure_low` (101 Hz) - so a heavy connect added a boom, which is the
## one thing PART B says must not be how a heavy gets its weight. It now adds a dull
## HARD thing and real body: `metal_body` (330 Hz) and `body_low` (192 Hz).
static func _hit_weight() -> SfxCue:
	var cue := _new(&"sword_hit_weight",
		"a heavy connect's weight - a dull hard body under the material, never a boom", true)
	cue.gain_db = 2.0
	# HOW TO JUDGE THIS CUE: it never plays alone. The director adds it ONLY on top of a
	# material contact, at intensity >= 0.75, so the material supplies the colour and
	# this supplies the weight. Measuring it isolated therefore says nothing about
	# whether it has "enough edge" - the edge is in the layer underneath it.
	#
	# What it must not be is a boom. It was one: `low_impact_short` (26 Hz) and
	# `pressure_low` (101 Hz) at 87-89% below 160 Hz, and the loudest cue in the game.
	# Old shares, as measured offline per layer's share of the mix ENERGY:
	#   metal_body 55.5 / body_low 25.6 / metal_sharp 11.1 / pressure_low 7.9
	# `pressure_low` is the 101 Hz swell and it was a thirteenth of the accent; it is
	# now well under, and `metal_sharp` is the second largest layer, pitched DOWN to
	# 0.90 so that it lands as a chunk rather than a tick - a tick would read "that was
	# sharp", and the accent has to read "that connected hard".
	cue.layer(&"metal_body", -1.0, 0.0, 0.98, false, "the dull hard body of the connect")
	cue.layer(&"metal_sharp", -2.0, 0.002, 0.90, false,
		"the hard thing that connected, pitched down into a chunk", 0.03, 0.8)
	cue.layer(&"body_low", -14.0, 0.006, 0.94, false, "mass, under it rather than in front")
	cue.layer(&"pressure_low", -26.0, 0.020, 0.96, false, "the air that got pushed, well under")
	return cue


# ------------------------------------------------------------------ shatter

## SHATTER is its own cue because it is its own EVENT: a frozen thing being broken
## by a blade. It must not be four glass sounds - the blade is the first thing you
## hear, and the crystal is what answers it.
##
## It shares `crystal_break` with `sword_contact_ice` on purpose, so the two cues are
## the same substance at two severities: the contact is the shell taking the news, the
## shatter is the shell failing. Measured isolated in pass 01 this cue was 29-48% above
## 6.5 kHz - the "ice" was mostly hiss - because the two layers that carry substance
## (`crystal_break`, `ice_crack`) were both in the hissing half of the family.
static func _shatter() -> SfxCue:
	var cue := _new(&"sword_shatter",
		"a frozen object destroyed BY A BLADE: impact, crack, break, then shards settling", true)
	# 7.0, and not the 3.0 the other contacts use - nor a level under perfect guard. Two
	# reasons, both measured. It is a SPATIAL cue, so it loses level to distance on top of
	# its gain; and in the shot take it came out at peak -5.2 while BOTH the light hit
	# that set it up (-3.0) and its own lead-in frozen contact (-3.4) were louder than it.
	# The brief's hierarchy puts shatter/signature at the TOP, with perfect guard getting
	# its prominence from TRANSIENT CLARITY rather than from being the loudest thing -
	# so parity on gain is the settlement, and the denser material does the rest.
	cue.gain_db = 7.0
	cue.layer(&"crystal_break", 0.0, 0.0, 0.99)
	cue.layer(&"metal_body", -4.0, 0.0, 0.96, false, "the blade that did it")
	cue.layer(&"ice_crack", -11.0, 0.020, 1.0, false, "the shell failing outward")
	cue.layer(&"body_low", -10.0, 0.010, 0.94, false, "short low body, not a collapse boom")
	cue.layer(&"ice_shard_settle", -18.0, 0.100, 1.0, false, "aftermath, dry and short")
	return cue


# ----------------------------------------------------------------- movement

## Dodge never gets a body layer - a dodge that thumps reads as a Heavy attack. But
## the sword is in the player's hand while they do it, so there IS a weapon layer; it
## is event based and deliberately almost inaudible (§PART H).
##
## `weapon_sway` was the layer for this and it has been dropped: measured, it is 29-44%
## of its energy above 6.5 kHz at a 6.7-7.5 kHz centroid, i.e. a hiss, not a handle
## moving. `metal_body` at -22 is the same idea and is actually a piece of metal - and
## at -22 it is a texture, not an event, which is what PART H asks for.
static func _dodge() -> SfxCue:
	var cue := _new(&"sword_dodge",
		"light and quick: the body slips, it does not land, and the sword just follows")
	cue.layer(&"air_fast", -3.0, 0.0, 1.14)
	cue.layer(&"cloth_fast", -8.0, 0.0, 1.0)
	cue.layer(&"metal_body", -22.0, 0.020, 1.0, false, "the handle moving, nothing more")
	return cue


# -------------------------------------------------------------------- magic

static func _wind_burst() -> SfxCue:
	var cue := _new(&"wind_burst",
		"moving air with force behind it, not a sword whoosh")
	cue.layer(&"wind_pressure", 0.0, 0.0, 1.0)
	cue.layer(&"air_fast", -5.0, 0.020, 0.72)
	cue.layer(&"pressure_low", -14.0, 0.060, 1.0, false, "the deep push behind it")
	return cue
