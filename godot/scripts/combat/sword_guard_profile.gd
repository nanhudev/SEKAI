extends Resource
class_name SwordGuardProfile
# How a style guards. 藏锋 cuts the attack line, 回风 slips it, 白蔷 binds it.
# The key bind (RMB) never changes between styles; only the profile changes.

@export_group("Hold")
@export var pose := Vector3(0.26, -0.30, -0.80)
@export var pose_rot := Vector3(-0.22, 0.05, 0.50)
@export var damage_multiplier := 0.28
@export var stamina_per_hit := 12.0
@export var heavy_stamina_multiplier := 2.2
@export var move_scale := 0.5

@export_group("Perfect Guard")
# 0.08–0.16s. Measured from the moment Guard was pressed, not from the hit.
@export var perfect_guard_window := 0.12
@export var perfect_guard_hitstop := 0.06
@export var perfect_guard_trauma := 0.26
@export var perfect_guard_impulse := Vector2(0.02, -0.03)
# The blade recoils off the incoming attack and settles back to guard.
@export var parry_pose := Vector3(0.16, -0.46, -1.02)
@export var parry_pose_rot := Vector3(-0.30, 0.22, 0.85)
@export var parry_duration := 0.20
@export var parry_steer := 0.0

@export_group("Riposte")
@export var riposte_window := 0.75
@export var riposte_id: StringName = &""
# Successful perfect guard lights the edge: the next named move gets this.
@export var glint_startup_scale := 0.80
@export var glint_poise_scale := 1.45
@export var glint_move_id: StringName = &""

@export_group("Sheath")
# 藏锋 only. A clean deflect IS the moment the style was waiting for, so the
# sword should already be on its way home: for this many seconds after a perfect
# guard the pre-sheath wait is waived. Without it the loop can only close while
# the enemy happens to be walking away, which is not a decision the player made.
# 0 = a perfect guard does not help you re-sheathe (true for every other style).
@export var parry_sheath_waiver := 0.0

@export_group("Bind")
# 白蔷庭 does not fling the attacker away on a perfect guard. It traps the blade
# for a beat and hands the player a CHOICE — three exits, one short window.
# This is why the style's perfect guard is a decision rather than a payoff:
#   Light  → the riposte move (stay inside the measure and answer)
#   Heavy  → the disengage move (cut on the way back out)
#   Dodge  → side step (leave the line entirely)
# The window is deliberately 0.2–0.4s: long enough to choose, short enough that
# not choosing is itself a choice.
# Bind does not invent a second window for Light: the deck window IS the riposte
# window, and the riposte move IS the Light exit. Only Heavy needs a new field,
# because "cut on the way back out" is a decision the standard guard has no slot
# for.
@export var bind_enabled := false
@export var bind_deck_window := 0.30
@export var bind_heavy_id: StringName = &""
@export var bind_message := "合围 · BIND"


func on_hit_recovery(hit: Dictionary, move: SwordMove) -> float:
	return move.recovery
