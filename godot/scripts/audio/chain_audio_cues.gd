extends RefCounted
class_name ChainAudioCues
## The chain cue table. Layer stacks, not files.
##
## WHAT THIS TABLE IS ALLOWED TO KNOW: the names ChainDirector already hands out
## (§30's contract) and the atom groups in the library. It does NOT know where a
## wav lives, and it does not know what "A1" is - the DIRECTOR maps a ChainMove id
## onto one of these cues, because that mapping is a fact about the moveset and
## this file is a fact about sound.
##
## THE THREE LOUDEST MISTAKES THIS TABLE EXISTS TO AVOID:
##   * Keys jingling. A chain is a dangerous heavy weapon; the rattle is TEXTURE
##     and sits 12-16 dB under the motion, never next to it.
##   * A whiff and a hit being one cue. A swing is air + moving links; landing
##     adds a CONTACT layer. If they were baked together the weapon would stop
##     reporting whether it touched anything.
##   * TENSION being an explosion. It is metal under load - a rise, a lock, and
##     only then a release. Three separate cues, because they are three separate
##     moments in the state machine.
##   * A CONTACT STANDING ON `metal_sharp`. That atom is 0.07s of 4.6 kHz, and it
##     used to be the top layer of DEFLECT and BITE - so the loudest layer of a
##     heavy thing meeting a wall was the brightest, shortest, most chopped sound
##     in the library. That is precisely what "brittle" sounds like. Mass belongs
##     on chain_impact_*/chain_ground/chain_link_heavy/body_low; a tick is the
##     detail ON TOP of the mass and never the top layer. Every contact below
##     gained a chain_link_heavy layer and gave up pitch for the same reason.
##
## Layer 0 dB is the identity. Everything else supports it and sits below.

static func build() -> Dictionary:
	var cues: Dictionary = {}
	for cue in [
		_idle(),
		_idle_shift(),
		_a1_sweep(),
		_a2_return(),
		_a2_reverse(),
		_a3_throw(),
		_launch(),
		_snap_cut(),
		_swing_short(),
		_slam_swing(),
		_slam_impact(),
		_deflect(),
		_orbit(),
		# --- tension, three beats ------------------------------------------------
		_tension_start(),
		_tension_full(),
		_snap(),
		# --- retract / haul ------------------------------------------------------
		_retract_light(),
		_retract_heavy(),
		_yank_light(),
		_yank_heavy(),
		# --- contact -------------------------------------------------------------
		_wall_light(),
		_wall_heavy(),
		_bite(),
		_hook_catch(),
		_wrap(),
		_hit_body(),
		_hit_body_heavy(),
	]:
		cues[cue.id] = cue
	return cues


# ------------------------------------------------------------------ idle

static func _idle() -> SfxCue:
	var cue := SfxCue.new()
	cue.id = &"chain_idle"
	cue.intent = "a chain at rest is nearly silent; this is a noise floor, not an event"
	cue.layer(&"chain_idle", 0.0)
	cue.layer(&"chain_rattle", -13.0, 0.02, 1.0, true, "one loose shift, well under the first layer")
	cue.layer(&"chain_link_tick", -16.0, 0.10, 1.0, true)
	return cue


static func _idle_shift() -> SfxCue:
	# Fired while the player is actually moving. Still light - §4 asks for a
	# settle, not for a marching chain.
	var cue := SfxCue.new()
	cue.id = &"chain_idle_shift"
	cue.intent = "the chain answering one step: barely there, but it proves the weapon is in hand"
	cue.layer(&"chain_idle", -1.0)
	cue.layer(&"chain_rattle", -11.0, 0.04, 1.02, true)
	cue.layer(&"chain_drag", -18.0, 0.06, 1.0, true)
	return cue


# ------------------------------------------------------------- A1 / A2 / A3

static func _a1_sweep() -> SfxCue:
	# A1 左甩 - HEAVY WIDE SWEEP. §5's three layers, in order: low air whoosh,
	# chain movement, and a very light body/handle layer.
	var cue := SfxCue.new()
	cue.id = &"chain_a1_sweep"
	cue.intent = "a wide heavy arc: air first, then the links, then the arm that threw it"
	cue.layer(&"air_heavy", 0.0, 0.0, 0.96, true, "wide low whoosh; the sweep's width")
	cue.layer(&"air_fast", -5.0, 0.01, 0.94, false, "keeps the low layer from being a drone")
	cue.layer(&"chain_move", -1.0, 0.02, 0.96, false, "many links under load at once - the mass of the arc, so it leads under the air")
	cue.layer(&"chain_link_heavy", -7.0, 0.02, 0.96, false, "the loud end of the rattle, carried on the swing")
	cue.layer(&"chain_whoosh", -7.0, 0.0, 0.95, true)
	# §5 layer 3 is deliberately tiny: the point is that a PERSON turned this.
	cue.layer(&"cloth_fast", -14.0, 0.03, 1.0, false)
	# WEIGHT. These two carry 31-36% of their energy below 160 Hz, which is more
	# than every chain atom in the library put together (the model rendered "heavy
	# steel chain" as 0.3% below 160 Hz and 57% above 8 kHz). They were sitting at
	# -14/-16 as tokens; the chain cannot feel heavy until they are real layers.
	cue.layer(&"pressure_low", -3.0, 0.06, 0.92, true, "the arm taking the load of the arc")
	cue.layer(&"body_low", -4.0, 0.05, 0.91, true, "the mass of the links, under the metal")
	return cue


static func _a2_return() -> SfxCue:
	# A2 快右左 - the same weapon, FASTER, higher, less low end. Sharing the atoms
	# and changing the tuning is the point: A2 is not A1 twice.
	var cue := SfxCue.new()
	cue.id = &"chain_a2_return"
	cue.intent = "shorter, brighter, meaner than A1 - the first of the two beats"
	cue.layer(&"air_heavy", -8.0, 0.0, 1.04, true, "present but pushed up and back")
	cue.layer(&"air_fast", 0.0, 0.0, 1.06, false, "the narrow cut leads instead")
	cue.layer(&"chain_move", -2.0, 0.01, 1.06, false)
	cue.layer(&"chain_link_heavy", -10.0, 0.01, 1.04, false, "A2 is not weightless, only quicker")
	cue.layer(&"chain_whoosh", -6.0, 0.0, 1.06, true)
	cue.layer(&"cloth_fast", -15.0, 0.02, 1.04, false)
	cue.layer(&"pressure_low", -7.0, 0.03, 0.94, true, "less low end than A1, not none")
	return cue


static func _a2_reverse() -> SfxCue:
	# The reversal at the extreme (§A2). Scheduled by the DIRECTOR off the move's
	# own `arc_split`, not baked here, because the split is moveset data.
	var cue := SfxCue.new()
	cue.id = &"chain_a2_reverse"
	cue.intent = "the whip crack back through the same side - the DA in da-DA"
	cue.layer(&"air_fast", 0.0, 0.0, 1.10, false)
	cue.layer(&"chain_move", -3.0, 0.0, 1.10, false)
	cue.layer(&"chain_link_heavy", -11.0, 0.0, 1.08, false)
	cue.layer(&"chain_link_tick", -12.0, 0.02, 1.06, true, "the links snapping over each other")
	cue.layer(&"pressure_low", -10.0, 0.02, 0.97, true)
	return cue


static func _a3_throw() -> SfxCue:
	# A3 直抛. First person cannot show a narrow forward release well, so the audio
	# carries the information: release, narrow cut, then the chain PAYING OUT.
	var cue := SfxCue.new()
	cue.id = &"chain_a3_throw"
	cue.intent = "a metallic release and a straight line leaving the hand - never a wide sweep"
	cue.layer(&"chain_snap", -7.0, 0.0, 1.02, true, "the release: short, metallic, in front")
	cue.layer(&"chain_whoosh", 0.0, 0.0, 1.02, false, "narrow forward air, not arc air")
	cue.layer(&"chain_payout", -1.0, 0.055, 0.98, true, "the head travelling away - this is what says THROW")
	cue.layer(&"chain_move", -6.0, 0.04, 1.02, false, "the mass leaving the hand")
	cue.layer(&"chain_link_heavy", -8.0, 0.045, 1.0, false)
	cue.layer(&"pressure_low", -5.0, 0.055, 0.93, true, "the arm paying out the weight")
	cue.layer(&"body_low", -6.0, 0.05, 0.92, true)
	return cue


static func _launch() -> SfxCue:
	# 甩星 - a charged release. Heavier than A3 because the orbit paid for it.
	var cue := SfxCue.new()
	cue.id = &"chain_launch"
	cue.intent = "the whole weapon being thrown with the spin behind it"
	cue.layer(&"chain_snap", -4.0, 0.0, 0.98, true)
	cue.layer(&"chain_whoosh", 0.0, 0.0, 0.97, false)
	cue.layer(&"chain_payout", -1.0, 0.05, 0.97, true)
	cue.layer(&"pressure_low", -4.0, 0.02, 0.95, true, "mass, not volume")
	cue.layer(&"chain_move", -4.0, 0.03, 1.0, false)
	cue.layer(&"body_low", -5.0, 0.02, 0.94, true)
	cue.layer(&"chain_link_heavy", -6.0, 0.03, 0.98, false, "a charged release is the heaviest thing this weapon does")
	return cue


static func _snap_cut() -> SfxCue:
	# 绷切 - a cut along a taut line, so there is no arc to whoosh through.
	var cue := SfxCue.new()
	cue.id = &"chain_snap_cut"
	cue.intent = "a straight cut on a loaded rope: the release IS the swing"
	cue.layer(&"chain_snap", 0.0, 0.0, 1.0, false)
	cue.layer(&"air_fast", -6.0, 0.0, 1.04, false)
	cue.layer(&"chain_move", -5.0, 0.0, 1.02, false)
	cue.layer(&"chain_link_heavy", -9.0, 0.01, 1.0, false, "a taut line is a heavy line")
	cue.layer(&"pressure_low", -9.0, 0.01, 0.96, true)
	cue.layer(&"chain_link_tick", -14.0, 0.03, 1.05, true)
	return cue


static func _swing_short() -> SfxCue:
	# 曳 / 拉近斩 - a pull is not a sweep. Short, tight, no wide air.
	var cue := SfxCue.new()
	cue.id = &"chain_swing_short"
	cue.intent = "a short loaded movement of the chain; the pull itself is a separate event"
	cue.layer(&"chain_move", 0.0, 0.0, 1.0, false)
	cue.layer(&"chain_link_heavy", -8.0, 0.01, 1.0, false, "a pull drags the whole chain, not one link")
	cue.layer(&"air_fast", -9.0, 0.0, 1.0, false)
	cue.layer(&"pressure_low", -8.0, 0.01, 0.94, true)
	cue.layer(&"chain_rattle", -13.0, 0.02, 1.05, true)
	return cue


# -------------------------------------------------------------------- slam

static func _slam_swing() -> SfxCue:
	var cue := SfxCue.new()
	cue.id = &"chain_slam_swing"
	cue.intent = "the head driven downward from above - the air is falling, not sweeping"
	cue.layer(&"air_heavy", 0.0, 0.0, 0.90, true)
	cue.layer(&"chain_move", -2.0, 0.01, 0.92, false)
	cue.layer(&"chain_whoosh", -8.0, 0.0, 0.92, true)
	cue.layer(&"chain_link_heavy", -9.0, 0.01, 0.92, false)
	cue.layer(&"pressure_low", -8.0, 0.02, 0.92, true, "a falling swing carries its weight upward")
	return cue


static func _slam_impact() -> SfxCue:
	var cue := SfxCue.new()
	cue.id = &"chain_slam_impact"
	cue.intent = "mass arriving at the floor: the ground layer leads, the camera does not have to"
	cue.layer(&"chain_ground", 0.0, 0.0, 0.95, true)
	cue.layer(&"chain_impact_heavy", -1.0, 0.0, 0.94, false)
	cue.layer(&"chain_link_heavy", -7.0, 0.005, 0.94, false)
	cue.layer(&"body_low", -1.0, 0.01, 0.94, false, "the weight, under the metal - at -6 it was decoration")
	cue.layer(&"pressure_low", -3.0, 0.0, 0.94, true)
	cue.layer(&"hook_stone", -12.0, 0.0, 0.96, true, "the surface answering; -9 of a 6.9 kHz tick was too much of the total")
	return cue


static func _deflect() -> SfxCue:
	# 拨链 - the chain sweeps an attack aside. It does not clash like a shield.
	var cue := SfxCue.new()
	cue.id = &"chain_deflect"
	cue.intent = "metal sweeping a blow off course; sharp, dry, no boom"
	cue.layer(&"metal_body", -3.0, 0.0, 0.98, false, "the body of the metal sweeping the blow aside")
	cue.layer(&"metal_sharp", -6.0, 0.0, 1.0, false, "the edge - detail ON the metal, no longer the top layer")
	cue.layer(&"chain_link_heavy", -8.0, 0.01, 0.98, false)
	cue.layer(&"chain_link_tick", -11.0, 0.02, 1.04, true)
	return cue


static func _orbit() -> SfxCue:
	var cue := SfxCue.new()
	cue.id = &"chain_orbit"
	cue.intent = "a chain whirling: continuous, and RE-FIRED rather than looped so the mix stays in one pool"
	cue.layer(&"chain_orbit", 0.0, 0.0, 1.0, true)
	cue.layer(&"chain_move", -4.0, 0.03, 1.0, false)
	cue.layer(&"chain_rattle", -15.0, 0.05, 1.0, true)
	cue.layer(&"chain_link_heavy", -10.0, 0.04, 1.0, false, "one heavy link passing per revolution")
	cue.layer(&"pressure_low", -10.0, 0.05, 0.95, true)
	return cue


# ----------------------------------------------------------------- tension

static func _tension_start() -> SfxCue:
	# §11/§30. The rope beginning to come up. It must be stackable: the director
	# may fire it more than once as the load builds.
	var cue := SfxCue.new()
	cue.id = &"chain_tension_start"
	cue.intent = "links aligning under load - the player hears the rope become a rope"
	cue.layer(&"chain_tension", 0.0, 0.0, 1.0, true)
	cue.layer(&"chain_tension_rise", -2.0, 0.0, 1.0, false)
	cue.layer(&"pressure_low", -8.0, 0.03, 0.95, true, "a hint of mass, never a rumble")
	return cue


static func _tension_full() -> SfxCue:
	var cue := SfxCue.new()
	cue.id = &"chain_tension_full"
	cue.intent = "at the limit: metal held, load transferred, nothing released yet"
	cue.layer(&"chain_tension_lock", 0.0, 0.0, 1.0, false)
	cue.layer(&"chain_tighten", -3.0, 0.0, 1.0, false)
	cue.layer(&"pressure_low", -4.0, 0.01, 0.95, true)
	cue.layer(&"body_low", -7.0, 0.02, 0.94, true)
	return cue


static func _snap() -> SfxCue:
	var cue := SfxCue.new()
	cue.id = &"chain_snap_release"
	cue.intent = "the pressure being spent: sudden slack, and the links answering"
	cue.layer(&"chain_snap", 0.0, 0.0, 1.0, false)
	cue.layer(&"chain_link_tick", -9.0, 0.01, 1.04, true)
	cue.layer(&"metal_sharp", -14.0, 0.0, 1.02, true, "the pressure spending itself is not a click")
	return cue


# --------------------------------------------------------- retract / haul

static func _retract_light() -> SfxCue:
	var cue := SfxCue.new()
	cue.id = &"chain_retract_light"
	cue.intent = "the reel after a whiff - reeling has to be as good as throwing"
	cue.layer(&"chain_retract_light", 0.0, 0.0, 0.98, false)
	cue.layer(&"chain_slide", -14.0, 0.02, 1.02, true)
	cue.layer(&"chain_link_heavy", -12.0, 0.03, 1.0, false)
	cue.layer(&"chain_link_tick", -13.0, 0.07, 1.03, true, "the hand catching it")
	return cue


static func _retract_heavy() -> SfxCue:
	var cue := SfxCue.new()
	cue.id = &"chain_retract_heavy"
	cue.intent = "hauling something with weight home; the drag is part of the reel"
	cue.layer(&"chain_retract_heavy", 0.0, 0.0, 0.96, true)
	cue.layer(&"chain_drag", -5.0, 0.02, 0.98, false)
	cue.layer(&"chain_link_heavy", -7.0, 0.03, 0.96, false)
	cue.layer(&"pressure_low", -5.0, 0.03, 0.95, true)
	cue.layer(&"body_low", -8.0, 0.04, 0.94, true)
	return cue


static func _yank_light() -> SfxCue:
	# §6: ONE tug. It must NOT contain the impact of whatever it pulled - that is
	# a separate event, and merging them is how a pull stops reading as a pull.
	var cue := SfxCue.new()
	cue.id = &"chain_yank_light"
	cue.intent = "one sudden release of tension - a tug, not a hit"
	cue.layer(&"chain_yank_light", 0.0, 0.0, 1.0, false)
	cue.layer(&"chain_link_tick", -11.0, 0.0, 1.05, true)
	return cue


static func _yank_heavy() -> SfxCue:
	var cue := SfxCue.new()
	cue.id = &"chain_yank_heavy"
	cue.intent = "a heavy body on the other end; this is the one haul that is allowed low end"
	cue.layer(&"chain_yank_heavy", 0.0, 0.0, 0.95, false)
	cue.layer(&"chain_link_heavy", -7.0, 0.0, 0.95, false)
	cue.layer(&"pressure_low", -4.0, 0.0, 0.94, true)
	cue.layer(&"body_low", -5.0, 0.01, 0.93, true)
	return cue


# ----------------------------------------------------------------- contact

static func _wall_light() -> SfxCue:
	var cue := SfxCue.new()
	cue.id = &"chain_wall_light"
	cue.intent = "the head arriving at stone: a contact, not an explosion"
	cue.layer(&"hook_stone", -3.0, 0.0, 1.0, true)
	cue.layer(&"chain_impact_light", 0.0, 0.0, 1.0, false)
	cue.layer(&"chain_link_heavy", -10.0, 0.005, 1.0, false)
	cue.layer(&"body_low", -8.0, 0.01, 0.95, true)
	cue.layer(&"metal_sharp", -13.0, 0.0, 1.0, true, "the edge, well under the contact")
	return cue


static func _wall_heavy() -> SfxCue:
	var cue := SfxCue.new()
	cue.id = &"chain_wall_heavy"
	cue.intent = "the same wall, hit hard enough to cost the spin"
	cue.layer(&"hook_stone", -3.0, 0.0, 0.96, true)
	cue.layer(&"chain_impact_heavy", 0.0, 0.0, 0.96, false)
	cue.layer(&"chain_link_heavy", -6.0, 0.005, 0.96, false)
	cue.layer(&"metal_body", -8.0, 0.0, 0.98, true)
	cue.layer(&"body_low", -2.0, 0.01, 0.94, true, "the thud under it, never on top of it")
	cue.layer(&"pressure_low", -4.0, 0.0, 0.94, true)
	return cue


static func _bite() -> SfxCue:
	# §13's third beat. Dryer and sharper than the contact: the hook has HOLD.
	var cue := SfxCue.new()
	cue.id = &"chain_bite"
	cue.intent = "the trident is in: drier and sharper than the contact that preceded it"
	cue.layer(&"hook_stone", -4.0, 0.0, 1.0, true, "still the surface, just less of it")
	cue.layer(&"chain_link_heavy", -8.0, 0.005, 1.0, false, "the hook has HOLD: mass, not a click")
	cue.layer(&"metal_sharp", -6.0, 0.0, 1.04, false, "the trident's edge - detail, under the bite")
	cue.layer(&"chain_tension_rise", -7.0, 0.035, 1.0, false, "the rope starts to come up ON this beat")
	cue.layer(&"body_low", -7.0, 0.005, 0.95, true, "the hook has HOLD - weight, not a click")
	cue.layer(&"pressure_low", -8.0, 0.01, 0.95, true)
	cue.layer(&"chain_link_tick", -11.0, 0.05, 1.03, true)
	return cue


static func _hook_catch() -> SfxCue:
	var cue := SfxCue.new()
	cue.id = &"chain_hook_catch"
	cue.intent = "the head has ARRIVED - hold is not yet claimed, the bite says that"
	cue.layer(&"chain_wrap", 0.0, 0.0, 1.0, true)
	cue.layer(&"chain_impact_light", -5.0, 0.0, 0.98, false)
	cue.layer(&"chain_move", -6.0, 0.03, 1.0, false)
	cue.layer(&"chain_link_heavy", -9.0, 0.02, 1.0, false)
	cue.layer(&"pressure_low", -10.0, 0.02, 0.95, true)
	return cue


static func _wrap() -> SfxCue:
	var cue := SfxCue.new()
	cue.id = &"chain_wrap"
	cue.intent = "coil closing - reserved for 缚, where the chain is doing the holding"
	cue.layer(&"chain_wrap", 0.0, 0.0, 1.0, false)
	cue.layer(&"chain_tension_rise", -6.0, 0.02, 1.0, false)
	return cue


static func _hit_body() -> SfxCue:
	# §10. Stylized body/armour contact. No gore, no voice.
	var cue := SfxCue.new()
	cue.id = &"chain_hit_body"
	cue.intent = "the trident landing on a body, then the chain being stopped by it"
	cue.layer(&"chain_impact_heavy", -2.0, 0.0, 0.98, false)
	cue.layer(&"body_impact", 0.0, 0.0, 0.98, false)
	cue.layer(&"chain_link_heavy", -8.0, 0.005, 0.98, false)
	cue.layer(&"body_low", -7.0, 0.01, 0.95, true)
	cue.layer(&"metal_sharp", -11.0, 0.0, 1.0, true)
	cue.layer(&"chain_yank_light", -9.0, 0.02, 1.0, false, "the jerk that follows a landing")
	return cue


static func _hit_body_heavy() -> SfxCue:
	var cue := SfxCue.new()
	cue.id = &"chain_hit_body_heavy"
	cue.intent = "a heavy target: the chain keeps less of its own momentum, and it is audible"
	cue.layer(&"chain_impact_heavy", 0.0, 0.0, 0.95, false)
	cue.layer(&"body_impact", -1.0, 0.0, 0.94, false)
	cue.layer(&"chain_link_heavy", -6.0, 0.005, 0.95, false)
	cue.layer(&"body_low", -1.0, 0.01, 0.93, false)
	cue.layer(&"chain_yank_heavy", -8.0, 0.03, 0.96, true)
	return cue
