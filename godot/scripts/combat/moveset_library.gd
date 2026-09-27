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
	return [STYLE_UNIVERSAL, STYLE_HIDDEN_EDGE, STYLE_FLOWING_WIND]


static func build(style_id: StringName) -> SwordMoveset:
	match style_id:
		STYLE_HIDDEN_EDGE:
			return hidden_edge()
		STYLE_FLOWING_WIND:
			return flowing_wind()
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
	moves[&"uni_l1"] = _move(&"uni_l1", "Light 1", {
		"startup": 0.085, "strike": 0.085, "follow_time": 0.075, "recovery": 0.175,
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

	moveset.moves = moves
	moveset.light_chain = [&"fw_l1", &"fw_l2", &"fw_l3", &"fw_l4"]
	moveset.heavy_id = &"uni_heavy"
	moveset.sprint_light_id = &"uni_sprint_light"
	moveset.retreat_light_id = &"uni_retreat_light"
	moveset.riposte_id = &"uni_riposte"
	moveset.signature_id = &""
	# 长风万里 is design-only for now; the ultimate slot stays empty on purpose.
	moveset.ultimate_id = &""
	moveset.skills = [
		_skill({
			"id": &"fw_liuyun", "display_name": "流云", "kind": SwordSkill.Kind.MOBILITY,
			"cooldown": 6.0, "move_id": &"fw_liuyun",
			"note": "短位移同时切击，位移中保留方向控制。",
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
