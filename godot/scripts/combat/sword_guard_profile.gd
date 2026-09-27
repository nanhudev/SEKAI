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


func on_hit_recovery(hit: Dictionary, move: SwordMove) -> float:
	return move.recovery
