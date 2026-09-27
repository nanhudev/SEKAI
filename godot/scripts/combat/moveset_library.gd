extends RefCounted
class_name SwordMovesetLibrary
# Builds the sword styles in code instead of hand-authoring nested .tres files.
# The movesets are data; the CombatController never branches on style_id.
#
# Pose keys are authored in camera space (x right, y up, -z forward) and are
# placeholder-grade: they are the timing skeleton that the ART hand/arm
# animation will eventually drive. See docs/COMBAT_ANIMATION_REQUIREMENTS.md.

const STYLE_UNIVERSAL := &"universal"
const STYLE_HIDDEN_EDGE := &"hidden_edge"
const STYLE_FLOWING_WIND := &"flowing_wind"
const STYLE_WHITE_ROSE := &"white_rose"

# ---------------------------------------------------------------- pose anchors

const IDLE := Vector3(0.52, -0.50, -0.94)
const IDLE_R := Vector3(0.0, 0.0, -0.18)
# 藏锋: blade parked at the left hip, hilt forward.
const SHEATH := Vector3(-0.50, -0.60, -0.74)
const SHEATH_R := Vector3(0.12, -0.16, 2.12)
# The scabbard never moves: it is part of the body, not the weapon.
const SCABBARD := Vector3(-0.44, -0.58, -0.66)
const SCABBARD_R := Vector3(0.06, -0.30, 2.06)
const LOW_LEFT := Vector3(-0.16, -0.60, -0.84)
const LOW_LEFT_R := Vector3(0.14, 0.08, 1.58)


static func _move(id: StringName, display_name: String, params: Dictionary) -> SwordMove:
	var move := SwordMove.new()
	move.id = id
	move.display_name = display_name
	for key in params:
		move.set(key, params[key])
	return move


static func _skill(params: Dictionary) -> SwordSkill:
	var skill := SwordSkill.new()
	for key in params:
		skill.set(key, params[key])
	return skill


static func all_styles() -> Array[StringName]:
	return [STYLE_UNIVERSAL, STYLE_HIDDEN_EDGE, STYLE_FLOWING_WIND, STYLE_WHITE_ROSE]


static func build(style_id: StringName) -> SwordMoveset:
	match style_id:
		STYLE_HIDDEN_EDGE:
			return hidden_edge()
		STYLE_FLOWING_WIND:
			return flowing_wind()
		STYLE_WHITE_ROSE:
			return white_rose()
		_:
			return universal()


# A style that shares a Universal attack (回风 uses the same heavy, every style
# uses the same sprint cut) must resolve that move from the Universal layer
# instead of silently pointing at nothing.
static func _resolve_shared(moveset: SwordMoveset) -> void:
	var base := universal()
	for move_id in [moveset.heavy_id, moveset.sprint_light_id, moveset.retreat_light_id, moveset.riposte_id]:
		if move_id != &"" and not moveset.moves.has(move_id):
			var shared: SwordMove = base.moves.get(move_id)
			if shared != null:
				moveset.moves[move_id] = shared


static func build_all() -> Dictionary:
	var out := {}
	for style_id in all_styles():
		out[style_id] = build(style_id)
	return out


# =============================================================== UNIVERSAL
# The baseline language every style inherits. Also the honest first question:
# is plain sword fighting already fun before any style exists?

static func universal() -> SwordMoveset:
	var moveset := SwordMoveset.new()
	moveset.style_id = STYLE_UNIVERSAL
	moveset.display_name = "Universal"
	moveset.tagline = "Plain single-handed sword."
	moveset.idle_pose = IDLE
	moveset.idle_pose_rot = IDLE_R

	var moves := {}

	# L1 右上 → 左下. The opener: fast, wide, forgiving.
	#
	# HIT AND MISS ARE DIFFERENT MOVES NOW. They were the same animation wearing
	# two outcome labels, because the pose is a function of the timeline and the
	# timeline did not know; §31 says the weight of a weapon is what happens AFTER
	# it lands. Connecting shortens the settle — the blade found what it was
	# looking for and the body can come back. Missing leaves the arm out there
	# holding nothing, longer, because there was nothing to stop against.
	moves[&"uni_l1"] = _move(&"uni_l1", "Light 1", {
		"startup": 0.085, "strike": 0.085, "follow_time": 0.075, "recovery": 0.175,
		"hit_recovery_scale": 0.86, "miss_recovery_scale": 1.22,
		"damage": 18.0, "poise_damage": 15.0, "hitstop": 0.026,
		"anchor": IDLE, "anchor_rot": IDLE_R,
		"wind": Vector3(0.76, -0.20, -0.84), "wind_rot": Vector3(0.0, -0.34, -1.05),
		"contact": Vector3(0.06, -0.66, -1.06), "contact_rot": Vector3(0.16, 0.30, 1.15),
		"follow": Vector3(-0.04, -0.76, -1.00), "follow_rot": Vector3(0.20, 0.46, 1.48),
		"recover": Vector3(0.42, -0.56, -0.95), "recover_rot": Vector3(0.02, 0.10, -0.05),
		"anticipation_power": 1.8, "strike_power": 2.9, "follow_power": 1.7,
		"follow_overshoot": 0.06, "recover_sag": 0.010,
		"lunge": 0.35, "lunge_lead": 0.4, "steer": 0.30,
		"camera_impulse": Vector2(0.0035, 0.0015), "camera_roll": -1.1,
		"hitbox_size": Vector3(2.2, 1.3, 1.5), "hitbox_offset": Vector3(0.0, -0.2, -1.30),
	})

	# L2 左 → 右. Slightly horizontal, widens the melee footprint.
	moves[&"uni_l2"] = _move(&"uni_l2", "Light 2", {
		"startup": 0.095, "strike": 0.090, "follow_time": 0.075, "recovery": 0.180,
		"hit_recovery_scale": 0.86, "miss_recovery_scale": 1.24,
		"damage": 19.0, "poise_damage": 16.0, "hitstop": 0.028,
		"anchor": Vector3(0.24, -0.42, -0.92), "anchor_rot": Vector3(-0.05, 0.24, 0.85),
		"wind": Vector3(-0.12, -0.42, -0.94), "wind_rot": Vector3(-0.06, 0.34, 1.05),
		"contact": Vector3(0.62, -0.40, -1.02), "contact_rot": Vector3(0.05, -0.30, -0.95),
		"follow": Vector3(0.74, -0.46, -1.00), "follow_rot": Vector3(0.07, -0.42, -1.20),
		"recover": Vector3(0.46, -0.54, -0.94), "recover_rot": Vector3(0.0, 0.06, -0.10),
		"anticipation_power": 1.9, "strike_power": 3.0, "follow_power": 1.7,
		"follow_overshoot": 0.05, "recover_sag": 0.008,
		"lunge": 0.28, "lunge_lead": 0.4, "steer": 0.30,
		"camera_impulse": Vector2(-0.0035, 0.0015), "camera_roll": 1.1,
		"hitbox_size": Vector3(2.2, 1.3, 1.5), "hitbox_offset": Vector3(0.0, -0.2, -1.30),
	})

	# L3 短暂收剑 → 快速直刺. The third cut must change the rhythm, not just
	# be a bigger horizontal.
	moves[&"uni_l3"] = _move(&"uni_l3", "Light 3 · Thrust", {
		"startup": 0.125, "strike": 0.085, "follow_time": 0.090, "recovery": 0.200,
		"hit_recovery_scale": 0.88, "miss_recovery_scale": 1.30,
		"damage": 26.0, "poise_damage": 24.0, "hitstop": 0.036,
		"anchor": Vector3(0.30, -0.36, -0.94), "anchor_rot": Vector3(-0.10, 0.10, 0.30),
		"wind": Vector3(0.42, -0.30, -0.80), "wind_rot": Vector3(-0.35, 0.06, 0.22),
		"contact": Vector3(0.26, -0.34, -1.30), "contact_rot": Vector3(-1.40, 0.12, 0.18),
		"follow": Vector3(0.22, -0.40, -1.34), "follow_rot": Vector3(-1.52, 0.14, 0.14),
		"recover": Vector3(0.44, -0.50, -0.96), "recover_rot": Vector3(-0.15, 0.04, -0.10),
		"anticipation_power": 2.6, "strike_power": 3.4, "follow_power": 1.5,
		"follow_overshoot": 0.0, "recover_sag": 0.012,
		"lunge": 0.95, "lunge_lead": 0.25, "steer": 0.20,
		"camera_impulse": Vector2(0.0, 0.006), "fov_kick": 1.4,
		"hitbox_size": Vector3(0.9, 0.9, 2.5), "hitbox_offset": Vector3(0.0, -0.25, -1.85),
	})

	# Heavy: short charge, weight forward, strong diagonal cleave. Built for
	# posture damage, not for looking like a windmill.
	moves[&"uni_heavy"] = _move(&"uni_heavy", "Heavy · Cleave", {
		"startup": 0.185, "strike": 0.105, "follow_time": 0.100, "recovery": 0.300,
		"hit_recovery_scale": 0.90, "miss_recovery_scale": 1.34,
		"damage": 36.0, "poise_damage": 45.0, "hitstop": 0.058,
		"charged_poise_bonus": 1.85, "charged_damage_bonus": 1.30,
		"anchor": IDLE, "anchor_rot": IDLE_R,
		"wind": Vector3(0.60, -0.02, -0.72), "wind_rot": Vector3(-0.42, -0.10, -0.55),
		"contact": Vector3(0.30, -0.72, -1.18), "contact_rot": Vector3(0.35, 0.16, 0.55),
		"follow": Vector3(0.24, -0.84, -1.12), "follow_rot": Vector3(0.40, 0.22, 0.70),
		"recover": Vector3(0.48, -0.58, -0.96), "recover_rot": Vector3(0.06, 0.08, 0.0),
		"anticipation_power": 1.7, "strike_power": 3.4, "follow_power": 1.6,
		"follow_overshoot": 0.11, "recover_sag": 0.016,
		"lunge": 0.75, "lunge_lead": 0.30, "steer": 0.12,
		"camera_impulse": Vector2(0.008, 0.012), "camera_roll": -1.6, "fov_kick": 1.8,
		"hitbox_size": Vector3(1.5, 2.0, 1.7), "hitbox_offset": Vector3(0.0, -0.35, -1.45),
	})

	moves[&"uni_sprint_light"] = _move(&"uni_sprint_light", "Sprint Cut", {
		"startup": 0.075, "strike": 0.085, "follow_time": 0.075, "recovery": 0.190,
		"hit_recovery_scale": 0.86, "miss_recovery_scale": 1.24,
		"damage": 22.0, "poise_damage": 18.0, "hitstop": 0.030,
		"anchor": Vector3(0.50, -0.28, -0.86), "anchor_rot": Vector3(0.06, -0.10, -0.45),
		"wind": Vector3(0.70, -0.18, -0.78), "wind_rot": Vector3(0.04, -0.30, -0.85),
		"contact": Vector3(0.04, -0.62, -1.20), "contact_rot": Vector3(0.20, 0.34, 1.20),
		"follow": Vector3(-0.06, -0.72, -1.10), "follow_rot": Vector3(0.24, 0.50, 1.50),
		"recover": Vector3(0.44, -0.52, -0.94), "recover_rot": Vector3(0.02, 0.10, -0.05),
		"anticipation_power": 1.6, "strike_power": 3.0, "follow_power": 1.7,
		"follow_overshoot": 0.08, "recover_sag": 0.014,
		"lunge": 1.15, "lunge_lead": 0.15, "steer": 0.35,
		"camera_impulse": Vector2(0.004, 0.008), "camera_roll": -1.4, "fov_kick": 2.2,
		"hitbox_size": Vector3(2.4, 1.3, 1.7), "hitbox_offset": Vector3(0.0, -0.2, -1.35),
	})

	# Retreat + Light: a short back-step cut. Negative lunge = away from facing.
	moves[&"uni_retreat_light"] = _move(&"uni_retreat_light", "Retreat Cut", {
		"startup": 0.080, "strike": 0.080, "follow_time": 0.070, "recovery": 0.200,
		"hit_recovery_scale": 0.86, "miss_recovery_scale": 1.20,
		"damage": 17.0, "poise_damage": 14.0, "hitstop": 0.024,
		"anchor": IDLE, "anchor_rot": IDLE_R,
		"wind": Vector3(0.60, -0.36, -0.80), "wind_rot": Vector3(0.02, -0.24, -0.70),
		"contact": Vector3(0.20, -0.60, -1.00), "contact_rot": Vector3(0.10, 0.22, 0.95),
		"follow": Vector3(0.10, -0.68, -0.98), "follow_rot": Vector3(0.14, 0.32, 1.20),
		"recover": Vector3(0.44, -0.54, -0.94), "recover_rot": Vector3(0.0, 0.06, -0.10),
		"anticipation_power": 1.8, "strike_power": 2.8, "follow_power": 1.7,
		"lunge": -0.70, "lunge_lead": 0.0, "steer": 0.15,
		"camera_impulse": Vector2(0.0, -0.004), "camera_roll": -0.9,
		"hitbox_size": Vector3(1.8, 1.3, 1.5), "hitbox_offset": Vector3(0.0, -0.2, -1.25),
	})

	# Riposte: blade deflect then a short forward thrust. No long execution
	# animation: it has to feel like the fight restarts instantly.
	moves[&"uni_riposte"] = _move(&"uni_riposte", "Riposte", {
		"startup": 0.055, "strike": 0.070, "follow_time": 0.060, "recovery": 0.200,
		"hit_recovery_scale": 0.84, "miss_recovery_scale": 1.30,
		"damage": 26.0, "poise_damage": 34.0, "hitstop": 0.050,
		"anchor": Vector3(0.20, -0.42, -0.98), "anchor_rot": Vector3(-0.20, 0.16, 0.62),
		"wind": Vector3(0.34, -0.34, -0.86), "wind_rot": Vector3(-0.42, 0.10, 0.40),
		"contact": Vector3(0.28, -0.32, -1.34), "contact_rot": Vector3(-1.44, 0.10, 0.10),
		"follow": Vector3(0.26, -0.36, -1.40), "follow_rot": Vector3(-1.55, 0.10, 0.06),
		"recover": Vector3(0.46, -0.50, -0.96), "recover_rot": Vector3(-0.10, 0.04, -0.05),
		"anticipation_power": 1.4, "strike_power": 2.6, "follow_power": 1.5,
		"recover_sag": 0.010,
		"lunge": 0.85, "lunge_lead": 0.10, "steer": 0.10,
		"camera_impulse": Vector2(0.0, 0.010), "fov_kick": 2.4,
		"hitbox_size": Vector3(0.9, 0.9, 2.6), "hitbox_offset": Vector3(0.0, -0.25, -1.9),
	})

	moveset.moves = moves
	moveset.light_chain = [&"uni_l1", &"uni_l2", &"uni_l3"]
	moveset.heavy_id = &"uni_heavy"
	moveset.sprint_light_id = &"uni_sprint_light"
	moveset.retreat_light_id = &"uni_retreat_light"
	moveset.riposte_id = &"uni_riposte"
	moveset.signature_id = &"iaido"
	# The Universal layer has no ultimate of its own. Ultimates belong to a
	# style and are earned through it, not handed out with the base sword.
	moveset.ultimate_id = &""
	moveset.guard = _universal_guard()
	return moveset


static func _universal_guard() -> SwordGuardProfile:
	var guard := SwordGuardProfile.new()
	guard.pose = Vector3(0.26, -0.30, -0.80)
	guard.pose_rot = Vector3(-0.22, 0.05, 0.50)
	guard.damage_multiplier = 0.28
	guard.stamina_per_hit = 12.0
	guard.perfect_guard_window = 0.12
	guard.parry_pose = Vector3(0.18, -0.44, -1.00)
	guard.parry_pose_rot = Vector3(-0.26, 0.18, 0.78)
	guard.parry_duration = 0.18
	guard.riposte_window = 0.75
	guard.riposte_id = &"uni_riposte"
	guard.glint_move_id = &"uni_l3"
	guard.glint_startup_scale = 0.84
	guard.glint_poise_scale = 1.35
	return guard


# ============================================================== HIDDEN EDGE
# 藏锋流 — 「刀还在鞘里时，攻击已经开始。」
# Rhythm: observe → sheathe → wait for the window → burst → short chain → sheathe.
# It is deliberately a staccato style: spamming Light never lets the blade
# return to the sheath, so the player loses the sheathed bonus and the style
# stops working. Waiting is the mechanic.

static func hidden_edge() -> SwordMoveset:
	var moveset := SwordMoveset.new()
	moveset.style_id = STYLE_HIDDEN_EDGE
	moveset.display_name = "藏锋流 · Hidden Edge"
	moveset.tagline = "The attack has already begun while the blade is still sheathed."
	moveset.idle_pose = IDLE
	moveset.idle_pose_rot = IDLE_R

	var moves := {}

	# L1 一文字 — a horizontal line, drawn from the left hip. Almost no
	# anticipation motion: the sword is already moving by the time you see it.
	moves[&"he_ichimonji"] = _move(&"he_ichimonji", "一文字 · Ichimonji", {
		"startup": 0.055, "strike": 0.085, "follow_time": 0.060, "recovery": 0.220,
		"damage": 26.0, "poise_damage": 26.0, "hitstop": 0.032,
		"anchor": SHEATH, "anchor_rot": SHEATH_R,
		"wind": Vector3(-0.44, -0.56, -0.76), "wind_rot": Vector3(0.10, -0.20, 2.05),
		"contact": Vector3(0.58, -0.44, -1.06), "contact_rot": Vector3(0.06, -0.34, -0.92),
		"follow": Vector3(0.70, -0.48, -1.00), "follow_rot": Vector3(0.08, -0.46, -1.15),
		"recover": Vector3(-0.16, -0.62, -0.82), "recover_rot": Vector3(0.14, 0.10, 1.55),
		"anticipation_power": 1.0, "strike_power": 2.2, "follow_power": 1.9,
		"follow_overshoot": 0.05, "recover_sag": 0.012,
		"lunge": 0.55, "lunge_lead": 0.15, "steer": 0.12,
		"camera_impulse": Vector2(0.004, 0.006), "camera_roll": -2.2, "fov_kick": 1.6,
		"hitbox_size": Vector3(2.6, 1.2, 1.5), "hitbox_offset": Vector3(0.0, -0.25, -1.30),
	})

	# L2 返刃 — the reverse diagonal. Accuracy pays: on a hit the L3 that
	# follows is fast, on a whiff the recovery is long enough to be punished.
	moves[&"he_kaeshi"] = _move(&"he_kaeshi", "返刃 · Kaeshi", {
		"startup": 0.100, "strike": 0.095, "follow_time": 0.070, "recovery": 0.280,
		"damage": 30.0, "poise_damage": 30.0, "hitstop": 0.038,
		"hit_recovery_scale": 0.66, "miss_recovery_scale": 1.50,
		"on_hit_next_startup_scale": 0.72,
		"anchor": Vector3(0.58, -0.46, -1.04), "anchor_rot": Vector3(0.06, -0.30, -0.85),
		"wind": Vector3(0.72, -0.32, -0.94), "wind_rot": Vector3(0.04, -0.40, -1.05),
		"contact": Vector3(0.10, -0.68, -1.10), "contact_rot": Vector3(0.20, 0.36, 1.25),
		"follow": Vector3(-0.02, -0.80, -1.04), "follow_rot": Vector3(0.24, 0.52, 1.55),
		"recover": Vector3(-0.22, -0.60, -0.84), "recover_rot": Vector3(0.14, 0.06, 1.62),
		"anticipation_power": 1.6, "strike_power": 3.0, "follow_power": 1.7,
		"follow_overshoot": 0.07, "recover_sag": 0.014,
		"lunge": 0.50, "lunge_lead": 0.3, "steer": 0.14,
		"camera_impulse": Vector2(-0.004, 0.008), "camera_roll": 2.2, "fov_kick": 1.6,
		"hitbox_size": Vector3(2.4, 1.3, 1.6), "hitbox_offset": Vector3(0.0, -0.25, -1.32),
	})

	# L3 落月 — a held beat, then a heavy top-right to bottom-left finish.
	moves[&"he_rakugatsu"] = _move(&"he_rakugatsu", "落月 · Rakugatsu", {
		"startup": 0.160, "strike": 0.095, "follow_time": 0.075, "recovery": 0.260,
		"damage": 40.0, "poise_damage": 48.0, "hitstop": 0.055,
		"anchor": Vector3(-0.16, -0.62, -0.86), "anchor_rot": Vector3(0.16, 0.08, 1.60),
		"wind": Vector3(0.74, -0.08, -0.80), "wind_rot": Vector3(-0.30, -0.24, -0.85),
		"contact": Vector3(0.02, -0.78, -1.16), "contact_rot": Vector3(0.34, 0.30, 1.05),
		"follow": Vector3(-0.06, -0.90, -1.06), "follow_rot": Vector3(0.40, 0.42, 1.30),
		"recover": Vector3(0.40, -0.56, -0.94), "recover_rot": Vector3(0.04, 0.08, -0.05),
		"anticipation_power": 2.7, "strike_power": 3.6, "follow_power": 1.6,
		"follow_overshoot": 0.13, "recover_sag": 0.018,
		"lunge": 1.00, "lunge_lead": 0.2, "steer": 0.10,
		"camera_impulse": Vector2(0.010, 0.013), "camera_roll": -2.0, "fov_kick": 1.5,
		"hitbox_size": Vector3(1.3, 2.1, 1.7), "hitbox_offset": Vector3(0.0, -0.35, -1.42),
	})

	# Heavy 断水 — a beat of absolute stillness, then an extremely fast
	# horizontal heavy cut. Against a frozen target it cracks harder.
	moves[&"he_dansui"] = _move(&"he_dansui", "断水 · Dansui", {
		"startup": 0.300, "strike": 0.085, "follow_time": 0.070, "recovery": 0.320,
		"damage": 44.0, "poise_damage": 52.0, "hitstop": 0.062, "frozen_bonus": 1.35,
		"charged_poise_bonus": 1.55, "charged_damage_bonus": 1.25,
		"anchor": Vector3(-0.20, -0.56, -0.86), "anchor_rot": Vector3(0.12, 0.12, 1.62),
		"wind": Vector3(-0.14, -0.52, -0.88), "wind_rot": Vector3(0.10, 0.16, 1.55),
		"contact": Vector3(0.66, -0.46, -1.12), "contact_rot": Vector3(0.04, -0.40, -1.02),
		"follow": Vector3(0.74, -0.50, -1.06), "follow_rot": Vector3(0.06, -0.52, -1.24),
		"recover": Vector3(-0.10, -0.60, -0.86), "recover_rot": Vector3(0.12, 0.10, 1.60),
		"anticipation_power": 6.0, "strike_power": 2.4, "follow_power": 1.8,
		"follow_overshoot": 0.08, "recover_sag": 0.014,
		"lunge": 0.80, "lunge_lead": 0.2, "steer": 0.08,
		"camera_impulse": Vector2(0.013, 0.0), "camera_roll": -3.0, "fov_kick": 2.0,
		"hitbox_size": Vector3(2.9, 1.1, 1.7), "hitbox_offset": Vector3(0.0, -0.25, -1.35),
	})

	# Skill 1 纳息 — a short settle, not an attack. It buys back rhythm.
	moves[&"he_sokyu"] = _move(&"he_sokyu", "纳息 · Sokyu", {
		"startup": 0.320, "strike": 0.260, "follow_time": 0.200, "recovery": 0.230,
		"damage": 0.0, "poise_damage": 0.0,
		"anchor": Vector3(0.30, -0.44, -0.92), "anchor_rot": Vector3(0.0, 0.06, 0.20),
		"wind": Vector3(-0.30, -0.60, -0.78), "wind_rot": Vector3(0.10, -0.10, 1.60),
		"contact": SHEATH, "contact_rot": SHEATH_R,
		"follow": Vector3(-0.52, -0.61, -0.74), "follow_rot": Vector3(0.12, -0.17, 2.14),
		"recover": Vector3(-0.34, -0.58, -0.80), "recover_rot": Vector3(0.11, -0.06, 1.75),
		"anticipation_power": 2.0, "strike_power": 1.4, "follow_power": 2.0,
		"steer": 0.0, "cancel_open": 0.7,
	})

	# Skill 2 燕返 — first cut up, and only on a hit, a second cut down. No
	# free second hit on a whiff.
	moves[&"he_tsubame_1"] = _move(&"he_tsubame_1", "燕返 · First", {
		"startup": 0.070, "strike": 0.085, "follow_time": 0.060, "recovery": 0.200,
		"damage": 28.0, "poise_damage": 24.0, "hitstop": 0.034,
		"followup_id": &"he_tsubame_2", "followup_window": 0.40,
		"anchor": LOW_LEFT, "anchor_rot": LOW_LEFT_R,
		"wind": Vector3(-0.28, -0.54, -0.84), "wind_rot": Vector3(0.12, 0.10, 1.50),
		"contact": Vector3(0.66, -0.16, -1.04), "contact_rot": Vector3(0.02, -0.34, -0.85),
		"follow": Vector3(0.76, -0.08, -0.98), "follow_rot": Vector3(0.0, -0.44, -1.05),
		"recover": Vector3(0.62, -0.30, -0.98), "recover_rot": Vector3(0.04, -0.30, -0.70),
		"anticipation_power": 1.2, "strike_power": 2.4, "follow_power": 1.7,
		"follow_overshoot": 0.06, "lunge": 0.45, "steer": 0.14,
		"camera_impulse": Vector2(0.004, -0.006), "camera_roll": -2.0, "fov_kick": 1.6,
		"hitbox_size": Vector3(2.2, 1.9, 1.5), "hitbox_offset": Vector3(0.0, -0.05, -1.30),
	})

	moves[&"he_tsubame_2"] = _move(&"he_tsubame_2", "燕返 · Return", {
		"startup": 0.075, "strike": 0.090, "follow_time": 0.070, "recovery": 0.240,
		"damage": 34.0, "poise_damage": 32.0, "hitstop": 0.046,
		"anchor": Vector3(0.68, -0.16, -0.98), "anchor_rot": Vector3(0.02, -0.36, -0.95),
		"wind": Vector3(0.72, -0.10, -0.94), "wind_rot": Vector3(0.0, -0.42, -1.08),
		"contact": Vector3(-0.10, -0.72, -1.08), "contact_rot": Vector3(0.24, 0.38, 1.30),
		"follow": Vector3(-0.22, -0.84, -1.02), "follow_rot": Vector3(0.28, 0.52, 1.55),
		"recover": Vector3(0.34, -0.56, -0.94), "recover_rot": Vector3(0.04, 0.06, 0.0),
		"anticipation_power": 1.5, "strike_power": 3.0, "follow_power": 1.6,
		"follow_overshoot": 0.09, "recover_sag": 0.014,
		"lunge": 0.70, "steer": 0.14,
		"camera_impulse": Vector2(-0.006, 0.010), "camera_roll": 2.6, "fov_kick": 1.4,
		"hitbox_size": Vector3(2.3, 1.9, 1.6), "hitbox_offset": Vector3(0.0, -0.30, -1.34),
	})

	# Skill 3 断章 — a precise cut that ends the enemy's sentence mid-word.
	moves[&"he_danzhang"] = _move(&"he_danzhang", "断章 · Danzhang", {
		"startup": 0.085, "strike": 0.075, "follow_time": 0.060, "recovery": 0.260,
		"damage": 24.0, "poise_damage": 20.0, "hitstop": 0.030, "interrupt_bonus": 2.6,
		"anchor": Vector3(-0.46, -0.58, -0.78), "anchor_rot": Vector3(0.12, -0.14, 2.02),
		"wind": Vector3(-0.42, -0.55, -0.80), "wind_rot": Vector3(0.11, -0.18, 1.98),
		"contact": Vector3(0.48, -0.38, -1.14), "contact_rot": Vector3(-0.10, -0.28, -0.30),
		"follow": Vector3(0.56, -0.44, -1.16), "follow_rot": Vector3(-0.14, -0.38, -0.48),
		"recover": Vector3(-0.24, -0.60, -0.84), "recover_rot": Vector3(0.13, 0.08, 1.62),
		"anticipation_power": 1.1, "strike_power": 2.1, "follow_power": 1.8,
		"follow_overshoot": 0.04, "recover_sag": 0.010,
		"lunge": 0.60, "lunge_lead": 0.1, "steer": 0.15,
		"camera_impulse": Vector2(0.003, 0.004), "camera_roll": -1.6, "fov_kick": 1.2,
		"hitbox_size": Vector3(1.0, 0.9, 2.4), "hitbox_offset": Vector3(0.0, -0.25, -1.80),
	})

	moveset.moves = moves
	moveset.light_chain = [&"he_ichimonji", &"he_kaeshi", &"he_rakugatsu"]
	moveset.heavy_id = &"he_dansui"
	moveset.sprint_light_id = &"uni_sprint_light"
	moveset.retreat_light_id = &"uni_retreat_light"
	moveset.riposte_id = &"he_ichimonji"
	moveset.signature_id = &"iaido"
	moveset.ultimate_id = &"moment_of_no_moon"

	moveset.skills = [
		_skill({
			"id": &"he_sokyu", "display_name": "纳息", "kind": SwordSkill.Kind.ENHANCE,
			"cooldown": 18.0, "move_id": &"he_sokyu", "enhance_duration": 8.0,
			"enhance_startup_scale": 0.85, "enhance_perfect_guard_bonus": 0.03,
			"enhance_first_hit_poise_scale": 1.6, "enhance_sheathe_scale": 0.7,
			"note": "归鞘呼吸，改变节奏而不是加伤害。",
		}),
		_skill({
			"id": &"he_tsubame", "display_name": "燕返", "kind": SwordSkill.Kind.ATTACK,
			"cooldown": 8.0, "move_id": &"he_tsubame_1",
			"note": "命中才有第二刀，X Cut。",
		}),
		_skill({
			"id": &"he_danzhang", "display_name": "断章", "kind": SwordSkill.Kind.INTERRUPT,
			"cooldown": 10.0, "move_id": &"he_danzhang", "interrupt_stagger": 0.85,
			"note": "对正在蓄力/施法的敌人才有意义。",
		}),
	]

	# 藏锋 punishes spam: no sheathing means no bonus, and cancels are worse
	# than the Universal baseline.
	moveset.combo_window = 0.30
	moveset.dodge_cancel_from = 0.55
	moveset.flow_on_hit_recovery = 1.0
	moveset.pose_stiffness = 132.0
	moveset.pose_damping = 0.965
	moveset.tremor = 0.0020
	moveset.trail_width = 0.034

	moveset.sheath_enabled = true
	moveset.sheath_delay = 0.50
	moveset.sheath_time = 0.38
	moveset.sheath_pose = SHEATH
	moveset.sheath_pose_rot = SHEATH_R
	moveset.sheath_scabbard_pose = SCABBARD
	moveset.sheath_scabbard_rot = SCABBARD_R
	moveset.sheathed_startup_scale = 0.72
	moveset.sheathed_poise_scale = 1.70

	var guard := SwordGuardProfile.new()
	# 刀低位准备: the blade sits low and ready, not raised across the screen.
	guard.pose = Vector3(0.30, -0.58, -0.86)
	guard.pose_rot = Vector3(-0.06, 0.14, 0.72)
	guard.damage_multiplier = 0.30
	guard.stamina_per_hit = 13.0
	guard.perfect_guard_window = 0.12
	guard.perfect_guard_hitstop = 0.062
	guard.perfect_guard_trauma = 0.28
	# 截锋: a very short draw that cuts the attack line, then straight back low.
	guard.parry_pose = Vector3(0.10, -0.44, -1.06)
	guard.parry_pose_rot = Vector3(-0.30, 0.24, 0.92)
	guard.parry_duration = 0.20
	guard.parry_steer = 0.10
	guard.riposte_window = 0.75
	guard.riposte_id = &"he_ichimonji"
	guard.glint_move_id = &"he_ichimonji"
	guard.glint_startup_scale = 0.74
	guard.glint_poise_scale = 1.50
	# The loop closer. The style's whole promise is "wait for that moment", so
	# blocking well has to COUNT as that moment.
	guard.parry_sheath_waiver = 1.2
	moveset.guard = guard
	_resolve_shared(moveset)
	return moveset


# ============================================================ FLOWING WIND
# 回风式 — 流 / 转 / 接 / 移。Every connected hit shortens the next recovery,
# so the style literally flows only while you keep landing hits.

static func flowing_wind() -> SwordMoveset:
	var moveset := SwordMoveset.new()
	moveset.style_id = STYLE_FLOWING_WIND
	moveset.display_name = "回风式 · Flowing Wind"
	moveset.tagline = "Keep moving; never let the blade stop."
	moveset.idle_pose = Vector3(0.42, -0.44, -0.94)
	moveset.idle_pose_rot = Vector3(-0.02, 0.14, 0.30)

	var moves := {}

	moves[&"fw_l1"] = _move(&"fw_l1", "回风 · 横", {
		"startup": 0.090, "strike": 0.085, "follow_time": 0.070, "recovery": 0.200,
		"damage": 17.0, "poise_damage": 14.0, "hitstop": 0.024,
		"anchor": Vector3(0.30, -0.44, -0.92), "anchor_rot": Vector3(-0.06, 0.18, 0.70),
		"wind": Vector3(-0.12, -0.42, -0.94), "wind_rot": Vector3(-0.06, 0.32, 1.05),
		"contact": Vector3(0.60, -0.40, -1.06), "contact_rot": Vector3(0.05, -0.28, -0.90),
		"follow": Vector3(0.72, -0.46, -1.04), "follow_rot": Vector3(0.07, -0.40, -1.16),
		"recover": Vector3(0.34, -0.44, -0.94), "recover_rot": Vector3(-0.04, 0.16, 0.62),
		"anticipation_power": 1.7, "strike_power": 2.6, "follow_power": 1.5,
		"follow_overshoot": 0.05, "recover_sag": 0.006,
		"lunge": 0.45, "lunge_lead": 0.3, "steer": 0.62,
		"camera_impulse": Vector2(-0.004, 0.002), "camera_roll": 1.4, "fov_kick": 1.6,
		"hitbox_size": Vector3(2.3, 1.4, 1.6), "hitbox_offset": Vector3(0.0, -0.2, -1.30),
	})

	moves[&"fw_l2"] = _move(&"fw_l2", "回风 · 返", {
		"startup": 0.085, "strike": 0.080, "follow_time": 0.065, "recovery": 0.200,
		"damage": 17.0, "poise_damage": 14.0, "hitstop": 0.024,
		"anchor": Vector3(0.66, -0.42, -1.02), "anchor_rot": Vector3(0.05, -0.30, -0.92),
		"wind": Vector3(0.74, -0.34, -0.98), "wind_rot": Vector3(0.03, -0.40, -1.05),
		"contact": Vector3(0.10, -0.68, -1.10), "contact_rot": Vector3(0.20, 0.34, 1.22),
		"follow": Vector3(0.0, -0.78, -1.04), "follow_rot": Vector3(0.24, 0.48, 1.50),
		"recover": Vector3(0.28, -0.46, -0.92), "recover_rot": Vector3(-0.04, 0.18, 0.66),
		"anticipation_power": 1.7, "strike_power": 2.7, "follow_power": 1.5,
		"follow_overshoot": 0.05, "recover_sag": 0.006,
		"lunge": 0.35, "lunge_lead": 0.3, "steer": 0.62,
		"camera_impulse": Vector2(0.004, 0.002), "camera_roll": -1.4, "fov_kick": 1.6,
		"hitbox_size": Vector3(2.3, 1.4, 1.6), "hitbox_offset": Vector3(0.0, -0.25, -1.30),
	})

	moves[&"fw_l3"] = _move(&"fw_l3", "回风 · 进", {
		"startup": 0.100, "strike": 0.080, "follow_time": 0.060, "recovery": 0.220,
		"damage": 19.0, "poise_damage": 16.0, "hitstop": 0.026,
		"anchor": Vector3(0.10, -0.62, -0.98), "anchor_rot": Vector3(0.16, 0.10, 1.10),
		"wind": Vector3(0.30, -0.38, -0.86), "wind_rot": Vector3(-0.36, 0.06, 0.24),
		"contact": Vector3(0.26, -0.34, -1.34), "contact_rot": Vector3(-1.42, 0.10, 0.14),
		"follow": Vector3(0.24, -0.38, -1.40), "follow_rot": Vector3(-1.54, 0.10, 0.10),
		"recover": Vector3(0.34, -0.46, -0.94), "recover_rot": Vector3(-0.10, 0.10, 0.30),
		"anticipation_power": 2.2, "strike_power": 3.2, "follow_power": 1.4,
		"recover_sag": 0.008,
		"lunge": 0.90, "lunge_lead": 0.2, "steer": 0.50,
		"camera_impulse": Vector2(0.0, 0.006), "fov_kick": 1.8,
		"hitbox_size": Vector3(0.9, 0.9, 2.5), "hitbox_offset": Vector3(0.0, -0.25, -1.85),
	})

	moves[&"fw_l4"] = _move(&"fw_l4", "回风 · 环", {
		"startup": 0.115, "strike": 0.100, "follow_time": 0.085, "recovery": 0.280,
		"damage": 24.0, "poise_damage": 30.0, "hitstop": 0.040,
		"anchor": Vector3(0.28, -0.36, -0.92), "anchor_rot": Vector3(-0.30, 0.10, 0.20),
		"wind": Vector3(-0.16, -0.50, -0.92), "wind_rot": Vector3(-0.02, 0.34, 1.20),
		"contact": Vector3(0.44, -0.62, -1.20), "contact_rot": Vector3(0.24, -0.16, -0.30),
		"follow": Vector3(0.20, -0.80, -1.10), "follow_rot": Vector3(0.32, 0.16, 0.40),
		"recover": Vector3(0.34, -0.44, -0.92), "recover_rot": Vector3(-0.04, 0.16, 0.62),
		"anticipation_power": 1.8, "strike_power": 3.0, "follow_power": 1.6,
		"follow_overshoot": 0.10, "recover_sag": 0.010,
		"lunge": 0.50, "lunge_lead": 0.2, "steer": 0.55,
		"camera_impulse": Vector2(-0.010, 0.004), "camera_roll": -2.4, "fov_kick": 1.2,
		"hitbox_size": Vector3(2.6, 1.5, 1.7), "hitbox_offset": Vector3(0.0, -0.30, -1.35),
	})

	# Skill 流云 — displace and cut in the same motion; steering stays open.
	moves[&"fw_liuyun"] = _move(&"fw_liuyun", "流云", {
		"startup": 0.100, "strike": 0.100, "follow_time": 0.080, "recovery": 0.220,
		"damage": 26.0, "poise_damage": 22.0, "hitstop": 0.032,
		"anchor": Vector3(0.40, -0.42, -0.94), "anchor_rot": Vector3(-0.04, 0.16, 0.60),
		"wind": Vector3(-0.20, -0.46, -0.96), "wind_rot": Vector3(-0.06, 0.34, 1.15),
		"contact": Vector3(0.62, -0.30, -1.22), "contact_rot": Vector3(0.02, -0.30, -0.70),
		"follow": Vector3(0.58, -0.58, -1.10), "follow_rot": Vector3(0.22, -0.06, -0.10),
		"recover": Vector3(0.34, -0.44, -0.92), "recover_rot": Vector3(-0.04, 0.16, 0.62),
		"anticipation_power": 1.5, "strike_power": 2.6, "follow_power": 1.6,
		"follow_overshoot": 0.09, "recover_sag": 0.012,
		"lunge": 2.40, "lunge_lead": 0.05, "steer": 0.70,
		"camera_impulse": Vector2(0.008, 0.006), "camera_roll": -2.6, "fov_kick": 3.0,
		"hitbox_size": Vector3(2.2, 1.3, 2.0), "hitbox_offset": Vector3(0.0, -0.2, -1.45),
	})

	# Signature 长风 — three cuts the player keeps steering. Each cut is entered
	# from the previous one through an open follow-up window, so the sequence is
	# never a locked animation: you can always leave, and the side you cut on is
	# taken from your own movement input rather than scripted.
	moves[&"fw_changfeng_1"] = _move(&"fw_changfeng_1", "长风 · 一", {
		"startup": 0.080, "strike": 0.085, "follow_time": 0.065, "recovery": 0.190,
		"damage": 24.0, "poise_damage": 20.0, "hitstop": 0.032,
		"anchor": Vector3(0.34, -0.44, -0.92), "anchor_rot": Vector3(-0.05, 0.16, 0.60),
		"wind": Vector3(-0.16, -0.46, -0.94), "wind_rot": Vector3(-0.06, 0.34, 1.12),
		"contact": Vector3(0.62, -0.40, -1.08), "contact_rot": Vector3(0.05, -0.30, -0.88),
		"follow": Vector3(0.70, -0.50, -1.04), "follow_rot": Vector3(0.10, -0.42, -1.10),
		"recover": Vector3(0.34, -0.44, -0.92), "recover_rot": Vector3(-0.04, 0.16, 0.62),
		"anticipation_power": 1.5, "strike_power": 2.8, "follow_power": 1.6,
		"follow_overshoot": 0.06, "recover_sag": 0.008,
		"lunge": 0.55, "lunge_lead": 0.25, "steer": 0.72,
		"camera_impulse": Vector2(-0.006, 0.003), "camera_roll": 1.8, "fov_kick": 2.0,
		"hitbox_size": Vector3(2.4, 1.4, 1.7), "hitbox_offset": Vector3(0.0, -0.22, -1.32),
		"followup_id": &"fw_changfeng_2", "followup_window": 0.85,
		"followup_from_start": true, "player_aimed": true,
	})

	moves[&"fw_changfeng_2"] = _move(&"fw_changfeng_2", "长风 · 二", {
		"startup": 0.075, "strike": 0.085, "follow_time": 0.065, "recovery": 0.185,
		"damage": 24.0, "poise_damage": 20.0, "hitstop": 0.032,
		"anchor": Vector3(0.62, -0.42, -1.00), "anchor_rot": Vector3(0.05, -0.28, -0.88),
		"wind": Vector3(0.72, -0.34, -0.96), "wind_rot": Vector3(0.03, -0.40, -1.02),
		"contact": Vector3(0.08, -0.66, -1.10), "contact_rot": Vector3(0.20, 0.34, 1.20),
		"follow": Vector3(0.0, -0.76, -1.04), "follow_rot": Vector3(0.24, 0.48, 1.46),
		"recover": Vector3(0.30, -0.46, -0.92), "recover_rot": Vector3(-0.04, 0.18, 0.64),
		"anticipation_power": 1.6, "strike_power": 2.9, "follow_power": 1.6,
		"follow_overshoot": 0.06, "recover_sag": 0.008,
		"lunge": 0.45, "lunge_lead": 0.25, "steer": 0.72,
		"camera_impulse": Vector2(0.006, 0.003), "camera_roll": -1.8, "fov_kick": 2.0,
		"hitbox_size": Vector3(2.4, 1.4, 1.7), "hitbox_offset": Vector3(0.0, -0.26, -1.32),
		"followup_id": &"fw_changfeng_3", "followup_window": 0.85,
		"followup_from_start": true, "player_aimed": true,
	})

	moves[&"fw_changfeng_3"] = _move(&"fw_changfeng_3", "长风 · 三", {
		"startup": 0.095, "strike": 0.100, "follow_time": 0.090, "recovery": 0.300,
		"damage": 34.0, "poise_damage": 36.0, "hitstop": 0.048,
		"anchor": Vector3(0.30, -0.38, -0.92), "anchor_rot": Vector3(-0.28, 0.12, 0.24),
		"wind": Vector3(-0.18, -0.50, -0.92), "wind_rot": Vector3(-0.02, 0.36, 1.22),
		"contact": Vector3(0.46, -0.62, -1.22), "contact_rot": Vector3(0.24, -0.16, -0.30),
		"follow": Vector3(0.18, -0.82, -1.10), "follow_rot": Vector3(0.34, 0.18, 0.42),
		"recover": Vector3(0.34, -0.44, -0.92), "recover_rot": Vector3(-0.04, 0.16, 0.62),
		"anticipation_power": 1.8, "strike_power": 3.2, "follow_power": 1.7,
		"follow_overshoot": 0.11, "recover_sag": 0.012,
		"lunge": 0.70, "lunge_lead": 0.2, "steer": 0.60,
		"camera_impulse": Vector2(-0.012, 0.005), "camera_roll": -2.6, "fov_kick": 1.6,
		"hitbox_size": Vector3(2.7, 1.5, 1.8), "hitbox_offset": Vector3(0.0, -0.30, -1.36),
		"player_aimed": true,
	})

	# Skill 折柳 — decline the exchange instead of winning it. The slip itself
	# does almost nothing; the point is the space it leaves to cut into.
	moves[&"fw_zheliu"] = _move(&"fw_zheliu", "折柳", {
		"startup": 0.060, "strike": 0.070, "follow_time": 0.060, "recovery": 0.180,
		"damage": 8.0, "poise_damage": 6.0, "hitstop": 0.018,
		"anchor": Vector3(0.38, -0.46, -0.92), "anchor_rot": Vector3(-0.02, 0.20, 0.52),
		"wind": Vector3(0.62, -0.40, -0.86), "wind_rot": Vector3(0.06, 0.10, -0.20),
		"contact": Vector3(0.30, -0.58, -1.02), "contact_rot": Vector3(0.16, 0.26, 1.06),
		"follow": Vector3(0.22, -0.62, -0.96), "follow_rot": Vector3(0.18, 0.32, 1.24),
		"recover": Vector3(0.34, -0.44, -0.92), "recover_rot": Vector3(-0.04, 0.16, 0.62),
		"anticipation_power": 1.3, "strike_power": 2.2, "follow_power": 1.5,
		"lunge": 0.20, "lunge_lead": 0.2, "steer": 0.80,
		"camera_roll": 2.2, "fov_kick": 1.4,
		"hitbox_size": Vector3(1.6, 1.2, 1.4), "hitbox_offset": Vector3(0.0, -0.24, -1.10),
	})

	# Skill 惊鸿 — a flourish that makes the style's transitions effortless.
	moves[&"fw_jinghong"] = _move(&"fw_jinghong", "惊鸿", {
		"startup": 0.090, "strike": 0.085, "follow_time": 0.070, "recovery": 0.200,
		"damage": 16.0, "poise_damage": 12.0, "hitstop": 0.024,
		"anchor": Vector3(0.42, -0.44, -0.94), "anchor_rot": Vector3(-0.04, 0.16, 0.60),
		"wind": Vector3(-0.22, -0.48, -0.96), "wind_rot": Vector3(-0.06, 0.36, 1.18),
		"contact": Vector3(0.58, -0.32, -1.18), "contact_rot": Vector3(0.02, -0.28, -0.66),
		"follow": Vector3(0.54, -0.60, -1.08), "follow_rot": Vector3(0.20, -0.04, -0.06),
		"recover": Vector3(0.34, -0.44, -0.92), "recover_rot": Vector3(-0.04, 0.16, 0.62),
		"anticipation_power": 1.4, "strike_power": 2.5, "follow_power": 1.6,
		"follow_overshoot": 0.09, "recover_sag": 0.010,
		"lunge": 0.40, "lunge_lead": 0.2, "steer": 0.75,
		"camera_impulse": Vector2(0.006, 0.005), "camera_roll": -2.0, "fov_kick": 2.6,
		"hitbox_size": Vector3(2.2, 1.3, 1.7), "hitbox_offset": Vector3(0.0, -0.22, -1.30),
	})

	moveset.moves = moves
	moveset.light_chain = [&"fw_l1", &"fw_l2", &"fw_l3", &"fw_l4"]
	moveset.heavy_id = &"uni_heavy"
	moveset.sprint_light_id = &"uni_sprint_light"
	moveset.retreat_light_id = &"uni_retreat_light"
	moveset.riposte_id = &"uni_riposte"
	# 长风 is a SIGNATURE like 聚合斩, not an ultimate: three cuts the player
	# keeps steering rather than a cinematic that takes the wheel away.
	moveset.signature_id = &"fw_changfeng_1"
	# 长风万里 is design-only for now; the ultimate slot stays empty on purpose.
	moveset.ultimate_id = &""
	moveset.skills = [
		_skill({
			"id": &"fw_liuyun", "display_name": "流云", "kind": SwordSkill.Kind.MOBILITY,
			"cooldown": 6.0, "move_id": &"fw_liuyun",
			"note": "短位移同时切击，位移中保留方向控制。",
		}),
		_skill({
			"id": &"fw_zheliu", "display_name": "折柳", "kind": SwordSkill.Kind.SLIP,
			"cooldown": 7.0, "move_id": &"fw_zheliu",
			"slip_window": 0.34, "slip_distance": 1.8, "slip_counter_window": 0.9,
			"slip_flow_gain": 22.0,
			"note": "让攻击落空，再切进它留下的空档。与完美格挡相反：不是对抗，是不接。",
		}),
		_skill({
			"id": &"fw_jinghong", "display_name": "惊鸿", "kind": SwordSkill.Kind.ENHANCE,
			"cooldown": 10.0, "move_id": &"fw_jinghong",
			"enhance_duration": 7.0,
			"enhance_startup_scale": 0.88,
			"enhance_first_hit_poise_scale": 1.35,
			"enhance_transition_bonus": 0.85,
			"enhance_steer_bonus": 1.22,
			"note": "短期强化衔接：冲刺/闪避/轻击之间不再互相卡住。是势的放大器，不是伤害。",
		}),
	]

	# Connecting shortens the recovery: the style flows only while you land hits.
	moveset.flow_on_hit_recovery = 0.60
	moveset.flow_min_recovery = 0.085
	moveset.combo_window = 0.52
	moveset.dodge_cancel_from = 0.30
	moveset.pose_stiffness = 74.0
	moveset.pose_damping = 0.90
	moveset.tremor = 0.0042
	moveset.trail_width = 0.028

	# 势 (Flow). The style's whole promise is that the sword gets easier to
	# handle while you keep moving and connecting — so Flow pays in recovery,
	# steering and transition timing, never in damage.
	moveset.flow_enabled = true
	moveset.flow_max = 100.0
	moveset.flow_gain_hit = 12.0
	moveset.flow_gain_movement_hit = 19.0
	moveset.flow_gain_deflect = 24.0
	moveset.flow_loss_miss = 16.0
	moveset.flow_decay = 9.0
	moveset.flow_decay_delay = 1.6
	moveset.flow_recovery_at_max = 0.58
	moveset.flow_steer_bonus = 1.45
	moveset.flow_transition_bonus = 0.50

	var guard := SwordGuardProfile.new()
	# Deflect, not a wall: lower mitigation, but a perfect guard can leave the
	# line immediately.
	guard.pose = Vector3(0.18, -0.34, -0.88)
	guard.pose_rot = Vector3(-0.18, 0.10, 0.52)
	guard.damage_multiplier = 0.42
	guard.stamina_per_hit = 15.0
	guard.perfect_guard_window = 0.14
	guard.parry_pose = Vector3(0.44, -0.40, -1.00)
	guard.parry_pose_rot = Vector3(-0.20, -0.10, 0.20)
	guard.parry_duration = 0.16
	guard.parry_steer = 1.70
	guard.riposte_window = 0.70
	guard.riposte_id = &"uni_riposte"
	guard.glint_move_id = &"fw_l3"
	guard.glint_startup_scale = 0.82
	guard.glint_poise_scale = 1.30
	moveset.guard = guard
	_resolve_shared(moveset)
	return moveset


# ============================================================== WHITE ROSE
# 白蔷庭剑术 · White Rose School — "win with distance".
#
# The third style asks a question neither of the others asks. 藏锋 is TIMING
# (stop, then burst), 回风 is MOVEMENT (never let the sword stop), 白蔷 is
# DISTANCE (make the opponent fight at your measure or not at all).
#
# Consequences that follow from that, and are the reason this is a style rather
# than a reskin:
#   · no big swings — the whole chain is short cut → point thrust → backhand cut
#   · the third cut is NOT a finisher; it keeps the threat alive and feeds back
#     into the chain, because a finisher would end the conversation the style is
#     trying to keep at its own range
#   · the heavy 穿庭 rewards a fully extended point and punishes crowding
#   · the guard BINDS: a perfect guard does not throw the attacker away, it traps
#     the blade and hands the player three exits
static func white_rose() -> SwordMoveset:
	var moveset := SwordMoveset.new()
	moveset.style_id = STYLE_WHITE_ROSE
	moveset.display_name = "白蔷庭剑术 · White Rose"
	moveset.tagline = "Win with distance — measure, point, bind."
	# Point already on the line, blade compact: the style never shows a big shape.
	moveset.idle_pose = Vector3(0.30, -0.34, -1.00)
	moveset.idle_pose_rot = Vector3(-0.08, 0.06, 0.30)

	var moves := {}

	# 第一式 横 — a SHORT crossing cut. Deliberately the smallest hitbox in the
	# game: it exists to keep the point alive at close measure, not to sweep.
	moves[&"wr_l1"] = _move(&"wr_l1", "白蔷 · 横", {
		"startup": 0.078, "strike": 0.070, "follow_time": 0.055, "recovery": 0.168,
		"damage": 13.0, "poise_damage": 13.0, "hitstop": 0.020,
		"anchor": Vector3(0.26, -0.34, -0.96), "anchor_rot": Vector3(-0.04, 0.10, 0.42),
		"wind": Vector3(0.40, -0.32, -0.94), "wind_rot": Vector3(0.02, -0.10, -0.10),
		"contact": Vector3(-0.24, -0.34, -1.06), "contact_rot": Vector3(0.02, 0.24, 0.80),
		"follow": Vector3(-0.34, -0.38, -1.02), "follow_rot": Vector3(0.04, 0.30, 0.94),
		"recover": Vector3(0.30, -0.34, -1.00), "recover_rot": Vector3(-0.08, 0.06, 0.32),
		"anticipation_power": 2.4, "strike_power": 3.4, "follow_power": 1.8,
		"recovery_power": 2.2, "follow_overshoot": 0.03, "recover_sag": 0.004,
		"lunge": 0.22, "lunge_lead": 0.35, "steer": 0.52,
		"camera_impulse": Vector2(-0.003, 0.002), "camera_roll": 1.0, "fov_kick": 1.0,
		"hitbox_size": Vector3(2.0, 0.9, 1.0), "hitbox_offset": Vector3(0.0, -0.20, -1.05),
	})

	# 第二式 刺 — the point. Long, narrow, and it commits straight: steering drops
	# because a thrust that can be walked sideways is not a thrust.
	moves[&"wr_l2"] = _move(&"wr_l2", "白蔷 · 刺", {
		"startup": 0.072, "strike": 0.076, "follow_time": 0.050, "recovery": 0.172,
		"damage": 15.0, "poise_damage": 18.0, "hitstop": 0.024,
		"anchor": Vector3(0.22, -0.30, -1.02), "anchor_rot": Vector3(-0.10, 0.06, 0.30),
		"wind": Vector3(0.34, -0.26, -0.88), "wind_rot": Vector3(-0.22, 0.08, 0.20),
		"contact": Vector3(0.14, -0.24, -1.44), "contact_rot": Vector3(-0.58, 0.04, 0.10),
		"follow": Vector3(0.12, -0.26, -1.56), "follow_rot": Vector3(-0.66, 0.04, 0.08),
		"recover": Vector3(0.30, -0.34, -1.00), "recover_rot": Vector3(-0.10, 0.06, 0.28),
		"anticipation_power": 2.8, "strike_power": 4.2, "follow_power": 1.2,
		"recovery_power": 2.4, "recover_sag": 0.005,
		"lunge": 0.46, "lunge_lead": 0.20, "steer": 0.30,
		"camera_impulse": Vector2(0.0, 0.008), "fov_kick": 2.4,
		"hitbox_size": Vector3(0.7, 0.8, 2.3), "hitbox_offset": Vector3(0.0, -0.18, -1.72),
	})

	# 第三式 反 — the backhand cut that does NOT finish. Recovery is the shortest
	# in the school and connecting feeds back into 第一式, so the chain stays open
	# instead of resolving. "Keeps the threat alive" is a mechanic here, not a
	# description: the follow-up only opens on contact, so a whiff does end it.
	moves[&"wr_l3"] = _move(&"wr_l3", "白蔷 · 反", {
		"startup": 0.070, "strike": 0.068, "follow_time": 0.048, "recovery": 0.150,
		"damage": 16.0, "poise_damage": 15.0, "hitstop": 0.024,
		"anchor": Vector3(-0.26, -0.36, -1.00), "anchor_rot": Vector3(0.04, 0.26, 0.84),
		"wind": Vector3(-0.40, -0.34, -0.94), "wind_rot": Vector3(0.06, 0.34, 1.02),
		"contact": Vector3(0.30, -0.30, -1.08), "contact_rot": Vector3(-0.06, -0.26, -0.62),
		"follow": Vector3(0.40, -0.34, -1.04), "follow_rot": Vector3(-0.08, -0.34, -0.76),
		"recover": Vector3(0.30, -0.34, -1.00), "recover_rot": Vector3(-0.08, 0.06, 0.32),
		"anticipation_power": 2.6, "strike_power": 3.4, "follow_power": 1.8,
		"recovery_power": 3.0, "follow_overshoot": 0.03, "recover_sag": 0.004,
		"lunge": 0.24, "lunge_lead": 0.30, "steer": 0.50,
		"camera_impulse": Vector2(0.003, 0.002), "camera_roll": -1.0, "fov_kick": 1.0,
		"hitbox_size": Vector3(1.9, 0.9, 1.0), "hitbox_offset": Vector3(0.0, -0.20, -1.06),
		# Contact feeds the chain back to the top instead of ending on a finisher.
		"on_hit_next_startup_scale": 0.84,
		"followup_id": &"wr_l1", "followup_window": 0.42,
	})

	# Heavy · 穿庭 — a very SHORT wind-up for a heavy, and almost no lunge lead,
	# because the point is the reach rather than the step. At ideal measure the
	# posture multiplier turns it into a posture break; face-hugging it is merely
	# an ordinary heavy. That asymmetry is the whole style in one move.
	moves[&"wr_chuanting"] = _move(&"wr_chuanting", "穿庭", {
		"startup": 0.135, "strike": 0.090, "follow_time": 0.095, "recovery": 0.250,
		"damage": 26.0, "poise_damage": 34.0, "hitstop": 0.040,
		"charged_damage_bonus": 1.25, "charged_poise_bonus": 1.50,
		"anchor": Vector3(0.24, -0.28, -1.02), "anchor_rot": Vector3(-0.12, 0.06, 0.28),
		"wind": Vector3(0.42, -0.22, -0.78), "wind_rot": Vector3(-0.34, 0.10, 0.16),
		"contact": Vector3(0.10, -0.22, -1.78), "contact_rot": Vector3(-0.74, 0.02, 0.06),
		"follow": Vector3(0.08, -0.24, -1.94), "follow_rot": Vector3(-0.82, 0.02, 0.04),
		"recover": Vector3(0.30, -0.34, -1.00), "recover_rot": Vector3(-0.10, 0.06, 0.28),
		"anticipation_power": 3.2, "strike_power": 4.6, "follow_power": 1.1,
		"recovery_power": 2.6, "recover_sag": 0.006,
		"lunge": 1.10, "lunge_lead": 0.10, "steer": 0.25,
		"camera_impulse": Vector2(0.0, 0.012), "fov_kick": 3.6,
		"hitbox_size": Vector3(0.8, 1.0, 3.2), "hitbox_offset": Vector3(0.0, -0.14, -2.20),
	})

	# Bind exit · Light → Riposte Thrust. Stay inside the measure and answer.
	moves[&"wr_bind_thrust"] = _move(&"wr_bind_thrust", "白蔷 · 合围刺", {
		"startup": 0.052, "strike": 0.062, "follow_time": 0.045, "recovery": 0.215,
		"damage": 22.0, "poise_damage": 26.0, "hitstop": 0.034,
		"anchor": Vector3(0.20, -0.30, -1.08), "anchor_rot": Vector3(-0.14, 0.04, 0.26),
		"wind": Vector3(0.32, -0.26, -0.90), "wind_rot": Vector3(-0.26, 0.06, 0.18),
		"contact": Vector3(0.10, -0.24, -1.52), "contact_rot": Vector3(-0.62, 0.02, 0.08),
		"follow": Vector3(0.08, -0.26, -1.64), "follow_rot": Vector3(-0.70, 0.02, 0.06),
		"recover": Vector3(0.30, -0.34, -1.00), "recover_rot": Vector3(-0.10, 0.06, 0.28),
		"anticipation_power": 3.0, "strike_power": 4.4, "follow_power": 1.2,
		"recovery_power": 2.4, "recover_sag": 0.005,
		"lunge": 0.55, "lunge_lead": 0.15, "steer": 0.30,
		"camera_impulse": Vector2(0.0, 0.009), "fov_kick": 2.8,
		"hitbox_size": Vector3(0.7, 0.8, 2.4), "hitbox_offset": Vector3(0.0, -0.16, -1.78),
	})

	# Bind exit · Heavy → Disengage Cut. The opposite answer: cut WHILE leaving,
	# so the negative lunge is the move. This is why the bind is a decision —
	# the two Light/Heavy exits resolve in opposite directions.
	moves[&"wr_bind_disengage"] = _move(&"wr_bind_disengage", "白蔷 · 脱手斩", {
		"startup": 0.080, "strike": 0.082, "follow_time": 0.080, "recovery": 0.250,
		"damage": 22.0, "poise_damage": 20.0, "hitstop": 0.032,
		"anchor": Vector3(0.16, -0.32, -1.02), "anchor_rot": Vector3(-0.10, 0.04, 0.28),
		"wind": Vector3(0.30, -0.28, -0.90), "wind_rot": Vector3(-0.14, 0.06, 0.22),
		"contact": Vector3(-0.30, -0.36, -1.16), "contact_rot": Vector3(0.06, 0.28, 0.90),
		"follow": Vector3(-0.40, -0.42, -1.10), "follow_rot": Vector3(0.08, 0.36, 1.06),
		"recover": Vector3(0.30, -0.34, -1.00), "recover_rot": Vector3(-0.08, 0.06, 0.32),
		"anticipation_power": 2.6, "strike_power": 3.6, "follow_power": 1.9,
		"recovery_power": 2.2, "follow_overshoot": 0.05, "recover_sag": 0.005,
		# Negative lunge: the cut happens on the way OUT.
		"lunge": -0.95, "lunge_lead": 0.10, "steer": 0.45,
		"camera_impulse": Vector2(0.004, 0.004), "camera_roll": -1.6, "fov_kick": 1.4,
		"hitbox_size": Vector3(2.2, 1.2, 1.6), "hitbox_offset": Vector3(0.0, -0.22, -1.28),
	})

	# Skill 假章 — the feint. A wind-up that is indistinguishable from 穿庭 until
	# the moment it is not. `feint_cancel_from` is the only field in the whole
	# move vocabulary that opens an exit DURING the wind-up; that is precisely
	# what a feint is, and why it needs its own flag rather than a tuning value.
	moves[&"wr_jiazhang"] = _move(&"wr_jiazhang", "假章", {
		"startup": 0.200, "strike": 0.070, "follow_time": 0.050, "recovery": 0.160,
		"damage": 12.0, "poise_damage": 12.0, "hitstop": 0.020,
		"anchor": Vector3(0.24, -0.28, -1.02), "anchor_rot": Vector3(-0.12, 0.06, 0.28),
		"wind": Vector3(0.42, -0.22, -0.78), "wind_rot": Vector3(-0.34, 0.10, 0.16),
		"contact": Vector3(0.12, -0.24, -1.42), "contact_rot": Vector3(-0.54, 0.04, 0.10),
		"follow": Vector3(0.10, -0.26, -1.50), "follow_rot": Vector3(-0.60, 0.04, 0.08),
		"recover": Vector3(0.30, -0.34, -1.00), "recover_rot": Vector3(-0.10, 0.06, 0.28),
		# High anticipation: the pose barely moves, so the bluff reads as a real
		# commitment right up to the moment the player takes it back.
		"anticipation_power": 4.0, "strike_power": 3.8, "follow_power": 1.4,
		"lunge": 0.30, "lunge_lead": 0.20, "steer": 0.35,
		"fov_kick": 1.2,
		"hitbox_size": Vector3(0.8, 0.8, 2.0), "hitbox_offset": Vector3(0.0, -0.18, -1.50),
		"feint_cancel_from": 0.55,
	})

	# Skill 白蔷刺 — precision, expressed spatially: the narrowest long hitbox in
	# the game. It is easy to miss and hard to aim, and at ideal measure the
	# posture multiplier carries it past a break threshold.
	moves[&"wr_baqiangci"] = _move(&"wr_baqiangci", "白蔷刺", {
		"startup": 0.045, "strike": 0.060, "follow_time": 0.045, "recovery": 0.205,
		"damage": 22.0, "poise_damage": 30.0, "hitstop": 0.038,
		"anchor": Vector3(0.20, -0.30, -1.04), "anchor_rot": Vector3(-0.14, 0.04, 0.26),
		"wind": Vector3(0.30, -0.28, -0.92), "wind_rot": Vector3(-0.20, 0.06, 0.20),
		"contact": Vector3(0.08, -0.22, -1.66), "contact_rot": Vector3(-0.68, 0.02, 0.06),
		"follow": Vector3(0.06, -0.24, -1.78), "follow_rot": Vector3(-0.76, 0.02, 0.04),
		"recover": Vector3(0.30, -0.34, -1.00), "recover_rot": Vector3(-0.10, 0.06, 0.28),
		"anticipation_power": 3.4, "strike_power": 5.0, "follow_power": 1.0,
		"recovery_power": 2.6, "recover_sag": 0.005,
		"lunge": 0.60, "lunge_lead": 0.12, "steer": 0.26,
		"camera_impulse": Vector2(0.0, 0.010), "fov_kick": 3.2,
		"hitbox_size": Vector3(0.55, 0.7, 2.6), "hitbox_offset": Vector3(0.0, -0.15, -1.92),
	})

	moveset.moves = moves
	# Three cuts, none of them a finisher. The chain is short on purpose: the
	# style is not trying to end the fight, it is trying to hold the range.
	moveset.light_chain = [&"wr_l1", &"wr_l2", &"wr_l3"]
	moveset.heavy_id = &"wr_chuanting"
	moveset.sprint_light_id = &"uni_sprint_light"
	moveset.retreat_light_id = &"uni_retreat_light"
	moveset.riposte_id = &"wr_bind_thrust"
	# No signature and no ultimate yet. The brief asked for a prototype, and
	# inventing a ceremony before the Measure loop is proven would be exactly the
	# content-first mistake this round is meant to avoid.
	moveset.signature_id = &""
	moveset.ultimate_id = &""
	moveset.skills = [
		_skill({
			"id": &"wr_jiazhang", "display_name": "假章", "kind": SwordSkill.Kind.ATTACK,
			"cooldown": 6.0, "move_id": &"wr_jiazhang",
			"note": "像穿庭一样的起手，但在剑真正出去之前就能收回。骗格挡、骗反击用。",
		}),
		_skill({
			"id": &"wr_baqiangci", "display_name": "白蔷刺", "kind": SwordSkill.Kind.ATTACK,
			"cooldown": 7.0, "move_id": &"wr_baqiangci",
			"note": "极窄极长的精准刺击。理想距离下姿态伤害会过线，贴脸则形同虚设。",
		}),
	]

	# Rhythm: 白蔷 commits hardest and turns slowest. It is the style that loses
	# the most by being in the wrong place, so it must not also be nimble.
	moveset.combo_window = 0.50
	moveset.dodge_cancel_from = 0.46
	moveset.flow_on_hit_recovery = 1.0
	moveset.pose_stiffness = 112.0
	moveset.pose_damping = 0.95
	# Steady hands and a thin trail: precision reads as less noise, not more.
	moveset.tremor = 0.0022
	moveset.trail_width = 0.018
	moveset.sheath_enabled = false

	# Measure. 1.50m is where the point stops having room; 3.20m is where it
	# stops arriving. Between them the attack starts faster, reaches further and
	# breaks posture harder — and nowhere does it simply hit for more.
	moveset.measure_enabled = true
	moveset.measure_close = 1.50
	moveset.measure_far = 3.20
	moveset.measure_cone_degrees = 55.0
	moveset.measure_max_range = 6.0
	moveset.measure_ideal_startup_scale = 0.80
	moveset.measure_ideal_poise_scale = 1.55
	moveset.measure_ideal_reach = 0.30
	moveset.measure_close_startup_scale = 1.25
	moveset.measure_close_poise_scale = 0.70
	moveset.measure_far_startup_scale = 1.20
	moveset.measure_far_poise_scale = 0.85

	var guard := SwordGuardProfile.new()
	# Guard · Bind. The point stays on the line and the profile stays small: this
	# style does not cover up, it contests the measure.
	guard.pose = Vector3(0.22, -0.30, -1.06)
	guard.pose_rot = Vector3(-0.10, 0.04, 0.30)
	guard.damage_multiplier = 0.34
	guard.stamina_per_hit = 11.0
	guard.heavy_stamina_multiplier = 2.0
	guard.move_scale = 0.46
	guard.perfect_guard_window = 0.12
	guard.perfect_guard_hitstop = 0.065
	guard.perfect_guard_trauma = 0.22
	guard.perfect_guard_impulse = Vector2(0.014, -0.018)
	# The bind pose is barely a pose: the point does not leave the line, because
	# the blade is trapped, not swept aside.
	guard.parry_pose = Vector3(0.22, -0.36, -1.14)
	guard.parry_pose_rot = Vector3(-0.12, 0.02, 0.24)
	guard.parry_duration = 0.24
	# Zero: a bind holds the line. Leaving is one of the three CHOICES, not
	# something the guard does to you.
	guard.parry_steer = 0.0
	# The deck window and the riposte window are the same window.
	guard.riposte_window = 0.30
	guard.riposte_id = &"wr_bind_thrust"
	guard.glint_move_id = &"wr_bind_thrust"
	guard.glint_startup_scale = 0.86
	guard.glint_poise_scale = 1.35
	guard.bind_enabled = true
	guard.bind_deck_window = 0.30
	guard.bind_heavy_id = &"wr_bind_disengage"
	guard.bind_message = "合围 · BIND"
	moveset.guard = guard
	_resolve_shared(moveset)
	return moveset
