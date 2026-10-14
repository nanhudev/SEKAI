extends RefCounted
class_name SwordBasicCues
## THE BASIC SENTENCE'S OWN VOICE (§25).
##
## ===========================================================================
## WHY THIS IS NOT PART OF `combat_audio_cues.gd`
## ===========================================================================
##
## `sword_light_1 / _2 / _3` are the GENERIC light cues: every style in the game
## plays them, indexed by combo step. The basic sentence's four beats cannot be
## expressed that way — there are four of them, they are told apart by distance
## rather than by step, and A3 alone is three sounds rather than one.
##
## Re-purposing the three generic cues would have changed what 一文字 and 回风
## sound like in order to describe a combo they do not have. So the sentence gets
## its own family, declared on the moves themselves (`SwordMove.audio_cue`) and
## reached through the same single door everything else uses,
## `CombatAudioDirector.play_event`.
##
## ===========================================================================
## WHAT EACH BEAT IS ALLOWED TO SOUND LIKE
## ===========================================================================
##
##   A1  a SHORT DRAW. Air, a dry fitting, and a person. No weight: the blade is
##       leaving the sheath, not arriving anywhere.
##   A2  a MEDIUM SWING. The same air at a lower pitch — the arc is bigger, and
##       on this line pitch IS how big the arc was — plus the moving mid-low that
##       says the cut pushed something forward.
##   A3  THREE DIFFERENT CUTS, and the difference is SUBSTANCE, not level: a
##       high thin steel tick, a brittle glass crack, and a low steel tick with
##       mass under it. §25 is explicit that one sound copied three times is not
##       three cuts, so the three cues do not share a primary atom.
##   A4  a WIDE ARC. The lowest pitch in the family, with the wide air body and
##       the body's own weight underneath it.
##
## All of them are built from atoms that already exist and are already measured.
## `air_heavy` and `wood_sheath_tick` — the two groups this vocabulary would
## ideally use for A1 and A4 — are declared PENDING in `SoundAtomRegistry`, so
## they are not referenced here: a cue that depends on a group with no atoms is a
## cue that plays silence, and silence is worse than the nearest available atom.

# ------------------------------------------------------------------- A1
static func draw() -> SfxCue:
	var cue := _new(&"sword_iaido_draw",
		"the blade leaving the mouth: fast air, one dry fitting, and a hand")
	cue.layer(&"air_fast", 0.0, 0.0, 1.06, false,
		"short and slightly high: a DRAW is faster than a swing and travels"
		+ " a fifth as far", 0.025, 1.0)
	cue.layer(&"metal_sharp", -11.0, 0.014, 1.10, false,
		"the fitting releasing, and nothing more - a detail, never the identity")
	cue.layer(&"cloth_fast", -13.0, 0.006, 1.0, false, "a person is holding this")
	return cue


# ------------------------------------------------------------------- saya
static func saya_touch() -> SfxCue:
	var cue := _new(&"sword_saya_touch",
		"the blade touching the sheath mouth: short, dry, and over")
	# The throat of a lacquered scabbard with a metal koiguchi. Dry is carried by
	# the SHORTNESS here, because `wood_sheath_tick` does not exist yet: a 0.07 s
	# hard tick with no tail reads as wood far more than a longer soft one does.
	cue.layer(&"metal_sharp", 0.0, 0.0, 1.24, false,
		"the koiguchi, close-miked, and the pitch is what makes it small")
	cue.layer(&"cloth_fast", -16.0, 0.004, 1.04, false, "the hand steadying it")
	return cue


# ------------------------------------------------------------------- A2
static func wave_swing() -> SfxCue:
	var cue := _new(&"sword_wave_swing",
		"a bigger arc than A1's: the same air, lower, and the steel has caught up")
	# The established rule on this line: pitch IS the size of the arc. A1 is 1.06
	# and A2 is 0.90, so the two beats are audibly the same blade at two sizes.
	cue.layer(&"air_fast", 0.0, 0.0, 0.90, false, "", 0.025, 1.0)
	cue.layer(&"metal_sharp", -10.0, 0.008, 0.98, false, "carried by A1's momentum")
	cue.layer(&"cloth_fast", -12.0, 0.004, 1.0)
	cue.layer(&"wind_pressure", -13.0, 0.020, 1.0, false,
		"the only layer A1 does not have: this cut pushes air FORWARD")
	return cue


static func wave_cut() -> SfxCue:
	var cue := _new(&"sword_wave_cut",
		"the compressed cut leaving the blade: thin, fast, and gone")
	# Spatial, and played at the wave's own position: the cut happens six metres
	# away from the person who made it, and a sound that happens in your hands
	# when the thing happened out there is the lie PART M exists to prevent.
	cue.spatial = true
	cue.layer(&"air_fast", 0.0, 0.0, 1.10, false, "thin air, higher than the swing")
	cue.layer(&"wind_pressure", -9.0, 0.006, 1.04, false,
		"the displacement arriving behind the edge")
	return cue


# ------------------------------------------------------------------- A3
static func domain_sheathe() -> SfxCue:
	var cue := _new(&"sword_domain_sheathe",
		"the blade going home and the room leaning in to listen")
	# One slow breath of air at a low pitch: the sword's own motion, heard as the
	# last thing before the world goes quiet. Nothing here is a cut, because at
	# this instant no cut has happened yet.
	cue.layer(&"air_fast", 0.0, 0.020, 0.82, false, "one slow breath", 0.02, 1.0)
	cue.layer(&"metal_sharp", -9.0, 0.050, 0.94, false, "the fitting taking it back")
	cue.layer(&"pressure_low", -12.0, 0.0, 0.99, false,
		"the room leaning in: felt, not heard")
	cue.layer(&"cloth_fast", -14.0, 0.010, 0.96, false, "")
	return cue


## The first cut: `/`, thin and high. The primary atom is steel.
static func space_cut_1() -> SfxCue:
	var cue := _new(&"sword_space_cut_1",
		"the first of the three: a thin, high, close steel line")
	cue.spatial = true
	cue.layer(&"metal_sharp", 0.0, 0.0, 1.20, false, "the highest tick in the family")
	cue.layer(&"air_fast", -4.0, 0.0, 1.18, false, "the air the line took with it")
	cue.layer(&"glass_low_tick", -14.0, 0.004, 1.06, false,
		"a body transient only - the registry's own note says this atom is not"
		+ " crystalline enough to carry anything")
	return cue


## The second cut: `\`, wider and more brittle. A different SUBSTANCE, which is
## what makes it a different cut rather than a louder copy of the first.
static func space_cut_2() -> SfxCue:
	var cue := _new(&"sword_space_cut_2",
		"the second of the three: brittle and wide, a crack rather than a tick")
	cue.spatial = true
	cue.layer(&"glass_crack", 0.0, 0.0, 1.02, false,
		"the only cue in the sword family whose identity is not steel, and that"
		+ " is deliberate: this is the cut that goes through the space itself")
	cue.layer(&"metal_sharp", -7.0, 0.0, 0.98, false, "still a blade at the root of it")
	cue.layer(&"air_fast", -8.0, 0.002, 0.95, false, "")
	return cue


## The third cut: shallow, long, and the only one with mass (weight 0.40 of the
## beat's damage, §29).
static func space_cut_3() -> SfxCue:
	var cue := _new(&"sword_space_cut_3",
		"the third of the three: low, long, and the only one with weight")
	cue.spatial = true
	cue.layer(&"metal_sharp", 0.0, 0.0, 0.86, false, "the lowest steel in the family")
	cue.layer(&"metal_body", -13.0, 0.006, 0.98, false,
		"the mass arriving behind the blade - allowed at this level because this"
		+ " cut is the beat's finisher and is meant to have weight")
	cue.layer(&"pressure_low", -14.0, 0.0, 1.0, false, "the space being told about it")
	cue.layer(&"body_low", -18.0, 0.010, 0.97, false, "")
	return cue


# ------------------------------------------------------------------- A4
static func arc_wide() -> SfxCue:
	var cue := _new(&"sword_arc_wide",
		"one cut around the body: the widest air in the game, and then the weight")
	# 0.72 is the lowest air pitch of the four beats, one step below A2's 0.90 and
	# nearly an octave below A1. The whole sentence is one blade at four sizes,
	# and this is the biggest one.
	cue.layer(&"air_fast", 0.0, 0.0, 0.72, false, "wide and slow", 0.02, 1.0)
	cue.layer(&"wind_pressure", -7.0, 0.0, 0.92, false,
		"the moving mid-low: the air actually being carried around the player")
	cue.layer(&"metal_body", -12.0, 0.030, 0.94, false, "the mass, arriving late")
	cue.layer(&"body_low", -16.0, 0.055, 0.95, false,
		"the body's own weight under the cut, at the END - which is the only"
		+ " reason this beat is allowed to feel heavier than A3")
	return cue


# ===========================================================================
# Assembly
# ===========================================================================

## Every cue the basic sentence can ask for. `CombatAudioCues.build()` merges
## this dictionary, so the director still has one `cues` table and one lookup.
static func sheathe_slide() -> SfxCue:
	var cue := _new(&"sword_saya_slide", "quiet controlled blade slide into the mouth")
	cue.layer(&"cloth_fast", -12.0, 0.0, 0.85, false)
	cue.layer(&"metal_body", -18.0, 0.0, 1.15, false)
	return cue


static func sheathe_click() -> SfxCue:
	var cue := _new(&"sword_saya_click", "one dry fitting only when the blade is fully seated")
	cue.layer(&"metal_sharp", -8.0, 0.0, 1.18, false, "dry fitting", 0.0, 0.045)
	return cue


static func build() -> Dictionary:
	var cues: Dictionary = {}
	for cue in [
		draw(), saya_touch(),
		wave_swing(), wave_cut(),
		domain_sheathe(), space_cut_1(), space_cut_2(), space_cut_3(),
		arc_wide(), sheathe_slide(), sheathe_click(),
	]:
		cues[cue.id] = cue
	# Local Feel V2 renders replace the physical sword voices, not a second player.
	for row in [
		[&"sword_iaido_draw",&"feel_v2_draw",-1.0],
		[&"sword_feel_a1",&"feel_v2_swing_a1",0.0],
		[&"sword_wave_swing",&"feel_v2_swing_a2",0.0],
		[&"sword_wave_cut",&"feel_v2_iaido_pressure",-17.0],
		[&"sword_uppercut",&"feel_v2_swing_a3",0.0],
		[&"sword_arc_wide",&"feel_v2_swing_a4",0.0],
		[&"sword_saya_touch",&"feel_v2_sheath_click",-11.0],
		[&"sword_saya_slide",&"feel_v2_sheath_slide",-5.0],
		[&"sword_saya_click",&"feel_v2_sheath_click",-1.0],
		[&"sword_contact_body",&"feel_v2_hit_body",0.0],
		[&"sword_contact_metal",&"feel_v2_hit_metal",0.0],
		[&"sword_contact_stone",&"feel_v2_hit_stone",0.0],
		[&"sword_contact_wood",&"feel_v2_hit_wood",0.0],
		[&"sword_perfect_guard",&"feel_v2_parry",0.0],
		[&"sword_heavy_release",&"feel_v2_swing_a4",0.0],
		[&"sword_hit_weight",&"feel_v2_iaido_pressure",-16.0],
	]:
		var cue := _new(row[0],"Sword Feel V2 local regenerated voice")
		cue.spatial = String(row[0]).begins_with("sword_contact_") or row[0] == &"sword_hit_weight"
		cue.layer(row[1],row[2],0.0,1.0,false)
		if cue.id == &"sword_perfect_guard":
			cue.gain_db = 7.0
			cue.layer(&"feel_v2_hit_metal",-11.0,0.02,0.95,false)
		if cue.id == &"sword_heavy_release":
			cue.layer(&"feel_v2_iaido_pressure",-14.0,0.04,1.0,false)
		cues[cue.id] = cue
	return cues


static func _new(id: StringName, intent: String) -> SfxCue:
	var cue := SfxCue.new()
	cue.id = id
	cue.intent = intent
	return cue
