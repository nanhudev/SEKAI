extends RefCounted
class_name MagicLibrary
# The three schools, in code — same pattern as SwordMovesetLibrary.
#
# The brief's test for magic is behavioural: "can you tell the three apart just
# by watching?" So each school is built around a different question:
#   FIRE  "where should this fight happen?"   → 焚环 leaves burning ground
#   FROST "what am I setting up next?"        → 寒流 climbs, 凝霜 jumps the ladder
#   WIND  "where do I want everyone to be?"   → 风压 moves bodies, 风步 moves me
# Renaming three projectiles would not have produced three identities.

const FIRE := ElementLibrary.FIRE
const FROST := ElementLibrary.FROST
const WIND := ElementLibrary.WIND


static func all() -> Dictionary:
	return {FIRE: fire(), FROST: frost(), WIND: wind()}


static func get_school(id: StringName) -> MagicSchool:
	return all().get(id)


static func _spell(params: Dictionary) -> SpellDefinition:
	var spell := SpellDefinition.new()
	for key in params:
		spell.set(key, params[key])
	return spell


# ----------------------------------------------------------------------- FIRE
static func fire() -> MagicSchool:
	var school := MagicSchool.new()
	school.id = FIRE
	school.display_name = "Fire"
	school.tagline = "Choose the ground."
	school.element = ElementLibrary.fire()
	school.spells = [
		_spell({
			"id": &"fire_bolt", "display_name": "火矢", "school_id": FIRE,
			"element_id": FIRE, "cast_mode": SpellDefinition.Cast.QUICK,
			"startup": 0.20, "active": 0.18, "recovery": 0.28,
			"mana_cost": 15.0, "cooldown": 0.8,
			"hitbox_damage": 14.0, "hitbox_poise": 8.0, "hitbox_impulse": 2.0,
			"hitbox_size": Vector3(1.6, 1.4, 2.4), "hitbox_offset": Vector3(0.0, -0.2, -1.9),
			"note": "快、直接。它的作用是点火，不是主伤害。",
		}),
		_spell({
			"id": &"flame_ring", "display_name": "焚环", "school_id": FIRE,
			"element_id": FIRE, "cast_mode": SpellDefinition.Cast.FULL,
			"startup": 0.34, "active": 0.20, "recovery": 0.36,
			"mana_cost": 26.0, "cooldown": 6.0,
			"hitbox_damage": 0.0, "hitbox_poise": 0.0,
			# Radius and duration come from the element, so wind can widen it.
			"field_radius": 2.6, "field_duration": 7.0, "field_tick_interval": 0.5,
			"field_offset": 2.0, "infuses_blade": true,
			"note": "留下燃烧地面：区域封锁。剑穿过它会被点燃。",
		}),
	]
	return school


# ---------------------------------------------------------------------- FROST
static func frost() -> MagicSchool:
	var school := MagicSchool.new()
	school.id = FROST
	school.display_name = "Frost"
	school.tagline = "Build the opening."
	school.element = ElementLibrary.frost()
	school.spells = [
		_spell({
			"id": &"frost_stream", "display_name": "寒流", "school_id": FROST,
			"element_id": FROST, "cast_mode": SpellDefinition.Cast.QUICK,
			"startup": 0.18, "active": 0.30, "recovery": 0.22,
			"mana_cost": 12.0, "cooldown": 0.8,
			"hitbox_damage": 6.0, "hitbox_poise": 6.0,
			"hitbox_size": Vector3(2.2, 1.6, 2.8), "hitbox_offset": Vector3(0.0, -0.15, -1.9),
			"infuses_blade": true,
			"note": "低消耗持续堆积，靠次数爬到 Frozen。",
		}),
		_spell({
			"id": &"frost_burst", "display_name": "凝霜", "school_id": FROST,
			"element_id": FROST, "cast_mode": SpellDefinition.Cast.FULL,
			"startup": 0.32, "active": 0.18, "recovery": 0.34,
			"mana_cost": 24.0, "cooldown": 5.0,
			"hitbox_damage": 12.0, "hitbox_poise": 14.0,
			"hitbox_size": Vector3(3.0, 2.0, 3.0), "hitbox_offset": Vector3(0.0, -0.1, -2.0),
			"note": "一次性大幅推进冷度阶梯，冷却明显。",
		}),
	]
	return school


# ----------------------------------------------------------------------- WIND
static func wind() -> MagicSchool:
	var school := MagicSchool.new()
	school.id = WIND
	school.display_name = "Wind"
	school.tagline = "Change where everyone stands."
	school.element = ElementLibrary.wind()
	school.spells = [
		_spell({
			"id": &"wind_pressure", "display_name": "风压", "school_id": WIND,
			"element_id": WIND, "cast_mode": SpellDefinition.Cast.QUICK,
			"startup": 0.14, "active": 0.15, "recovery": 0.25,
			"mana_cost": 10.0, "cooldown": 0.7,
			"hitbox_damage": 6.0, "hitbox_poise": 10.0, "hitbox_impulse": 5.0,
			"hitbox_size": Vector3(3.2, 1.8, 3.2), "hitbox_offset": Vector3(0.0, -0.2, -2.1),
			"note": "近距锥形推力：按重量分档，轻的被推出去，重的只被扰乱。",
		}),
		_spell({
			"id": &"wind_step", "display_name": "风步", "school_id": WIND,
			"element_id": WIND, "cast_mode": SpellDefinition.Cast.QUICK,
			"startup": 0.10, "active": 0.12, "recovery": 0.16,
			"mana_cost": 8.0, "cooldown": 3.0,
			"hitbox_damage": 0.0, "hitbox_poise": 0.0,
			"note": "短时间增强移动：不是传送。它改变的是动量。",
		}),
	]
	return school
