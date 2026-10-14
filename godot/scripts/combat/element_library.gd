extends RefCounted
class_name ElementLibrary
# The three elements, as data. Same pattern as SwordMovesetLibrary: this is the
# only place an element's rules are written down.
#
# The test the design brief demands is behavioural, so each element has to
# answer a different question for the player:
#   FIRE  — "where do I want the fight to happen?"     (area, spread)
#   FROST — "how do I set up my next big hit?"         (build-up, brittle)
#   WIND  — "where do I want everyone to be?"          (force, position)
# If two of them only differ in tint and number, the identity has failed.

const FIRE := &"fire"
const FROST := &"frost"
const WIND := &"wind"

const WEIGHT_LIGHT := &"light"
const WEIGHT_MEDIUM := &"medium"
const WEIGHT_HEAVY := &"heavy"

# One instance per element, shared by every actor and every field. This matters:
# if each call returned a fresh resource, two enemies could hold different rules
# for the same element, and tuning one would silently not affect the other. The
# library has to be the single source of truth, or "the rules are data" is a lie.
static var _cache: Dictionary = {}


static func all() -> Dictionary:
	return {FIRE: fire(), FROST: frost(), WIND: wind()}


static func get_element(id: StringName) -> ElementDefinition:
	var table := all()
	return table.get(id)


# Used by tests and tuning tools that want to start from a clean definition.
static func forget_cache() -> void:
	_cache.clear()


# ----------------------------------------------------------------------- FIRE
# Burning is not "lose a bit of health every second". It ticks, it makes weaker
# enemies lose their nerve, it thaws frost, and wind carries it to whatever is
# standing nearby. It is area denial with a damage rider, not the other way round.

static func fire() -> ElementDefinition:
	if _cache.has(FIRE):
		return _cache[FIRE]
	var element := ElementDefinition.new()
	element.id = FIRE
	element.display_name = "Fire"
	element.tint = Color(1.0, 0.42, 0.12, 1.0)
	# Fire has no ladder: it is on or it is off.
	element.applies_per_hit = 0.0
	element.decay_rate = 0.0
	# It has to hurt on contact too, or the spell reads as "nothing happened".
	element.impact_damage = 8.0
	element.tick_damage = 6.0
	element.tick_interval = 0.5
	element.tick_poise = 1.0
	element.spread_by_wind = true
	element.spread_radius = 4.0
	element.spread_amount = 40.0
	# Burning thaws: fire is the natural answer to being frozen, and it also
	# means the player cannot hold both states at once. A real trade-off.
	element.hastens_decay_of = [FROST]
	element.hasten_multiplier = 2.5
	element.panic_health_fraction = 0.35
	element.infusion_duration = 6.0
	element.infusion_applies = 100.0
	element.infusion_damage_bonus = 2.0
	_cache[FIRE] = element
	return element


# ---------------------------------------------------------------------- FROST
# A ladder rather than a switch: Chilled → Frosted → Frozen. Each rung changes
# how the target behaves, so the player can see the setup coming. The top rung
# is short and makes the target brittle rather than removing it from the game.

static func frost() -> ElementDefinition:
	if _cache.has(FROST):
		return _cache[FROST]
	var element := ElementDefinition.new()
	element.id = FROST
	element.display_name = "Frost"
	element.tint = Color(0.72, 0.92, 1.0, 1.0)
	element.stage_names = [&"normal", &"chilled", &"frosted", &"frozen"]
	element.stage_thresholds = [0.0, 35.0, 70.0, 100.0]
	element.applies_per_hit = 45.0
	element.decay_rate = 4.0
	element.decay_delay = 0.6
	element.tick_damage = 1.5
	element.tick_interval = 1.0
	# Reaching Frozen stops whatever it was doing, but only briefly: the point is
	# the opening it creates, not a target that is simply switched off.
	element.final_stage_staggers = true
	element.final_stage_duration = 4.0
	element.enables_brittle = true
	element.brittle_bonus = 2.2
	# Wind pushes the chill into whatever is standing near it.
	element.spread_by_wind = true
	element.spread_radius = 3.5
	element.spread_amount = 30.0
	element.infusion_duration = 6.0
	element.infusion_applies = 35.0
	_cache[FROST] = element
	return element


# ----------------------------------------------------------------------- WIND
# Force and position. Wind does not care how much health anything has; it cares
# how heavy it is. The same gust that throws a light enemy into a wall only
# turns a heavy one a few degrees.

static func wind() -> ElementDefinition:
	if _cache.has(WIND):
		return _cache[WIND]
	var element := ElementDefinition.new()
	element.id = WIND
	element.display_name = "Wind"
	element.tint = Color(0.76, 0.94, 0.90, 1.0)
	element.applies_per_hit = 0.0
	element.decay_rate = 0.0
	element.impact_damage = 4.0
	element.pushes = true
	element.push_weight_scaled = true
	element.push_staggers = true
	# Driving something into a wall is the payoff, so the wall has to matter.
	element.spread_by_wind = false
	_cache[WIND] = element
	return element


# How much of a push actually lands, given how heavy the target is.
static func push_scale_for(weight: StringName) -> float:
	match weight:
		WEIGHT_LIGHT:
			return 1.6
		WEIGHT_HEAVY:
			return 0.25
		_:
			return 1.0
