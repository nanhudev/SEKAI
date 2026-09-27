extends Resource
class_name SwordMove
# One attack in the Universal Sword Layer language.
#
# Timeline (every move has all four, no move is allowed to be "just a lerp"):
#
#   anchor ──startup──▶ wind ──strike──▶ contact ──follow──▶ follow ──recovery──▶ recover
#            anticipation      hitbox open        follow-through      settle
#
# The pose keys live in camera space (x right, y up, -z forward). They are
# authored here as placeholder-grade keys; the formal hand/arm animation from
# the ART line will replace the keys, not the timing language.

@export var id: StringName = &""
@export var display_name := ""
@export var note := ""

@export_group("Timing")
@export var startup := 0.09
@export var strike := 0.09
@export var follow_time := 0.075
@export var recovery := 0.18
# Fraction of (follow_time + recovery) after which cancels unlock.
@export var cancel_open := 0.45
@export var startup_scale := 1.0
@export var recovery_scale := 1.0
# Applied to `recovery` when the move connected / whiffed. A style can punish
# inaccuracy by making the miss longer, and reward contact by shortening it.
@export var hit_recovery_scale := 1.0
@export var miss_recovery_scale := 1.0
# The next move in the chain starts faster when this one connected.
@export var on_hit_next_startup_scale := 1.0

@export_group("Damage")
@export var damage := 18.0
@export var poise_damage := 15.0
@export var element: StringName = &"physical"
@export var hitstop := 0.028
@export var frozen_bonus := 1.0
# Posture multiplier when the swing was fully charged.
@export var charged_poise_bonus := 1.0
@export var charged_damage_bonus := 1.0

@export_group("Camera")
@export var camera_impulse := Vector2.ZERO
@export var camera_roll := 0.0
@export var fov_kick := 0.0
@export var trauma := 0.0

@export_group("Body")
# Metres of forward displacement delivered over the strike window.
@export var lunge := 0.0
@export var lunge_lead := 0.35
@export var steer := 0.30

@export_group("Pose · camera space")
@export var anchor := Vector3(0.55, -0.52, -0.95)
@export var anchor_rot := Vector3(0.0, 0.0, -0.2)
@export var wind := Vector3(0.72, -0.30, -0.88)
@export var wind_rot := Vector3(0.05, -0.30, -0.85)
@export var contact := Vector3(0.10, -0.62, -1.05)
@export var contact_rot := Vector3(0.14, 0.30, 1.15)
@export var follow := Vector3(0.02, -0.70, -1.00)
@export var follow_rot := Vector3(0.18, 0.44, 1.45)
@export var recover := Vector3(0.45, -0.55, -0.95)
@export var recover_rot := Vector3(0.02, 0.12, 0.05)
# Higher = the pose barely moves during startup, then snaps. 藏锋 sits high.
@export var anticipation_power := 2.0
# Higher = the blade accelerates harder out of the wind-up.
@export var strike_power := 3.0
@export var follow_power := 1.6
@export var recovery_power := 2.0
# The blade pushes past the follow pose before settling, then resolves back.
@export var follow_overshoot := 0.0
@export var recover_sag := 0.0

@export_group("Hitbox")
@export var hitbox_size := Vector3(1.4, 1.2, 1.6)
@export var hitbox_offset := Vector3(0.0, -0.2, -1.4)

@export_group("Rules")
@export var requires_hit := false
@export var followup_id: StringName = &""
@export var followup_window := 0.0
# Default: a follow-up opens on CONTACT (燕返 must be earned). A player-driven
# sequence like 长风 opts in to opening at the start instead, so a whiff cannot
# silently end the player's own combination.
@export var followup_from_start := false
@export var interrupt_bonus := 1.0
@export var in_air := false
# The player aims this cut: the side is taken from movement input when the move
# starts and the pose / hitbox are mirrored, so a signature sequence is steered
# rather than scripted.
@export var player_aimed := false


func total_time() -> float:
	return startup + strike + follow_time + recovery


func strike_end() -> float:
	return startup + strike


func pose_span() -> float:
	return follow_time + recovery


func duplicate_move(overrides: Dictionary = {}) -> SwordMove:
	var move: SwordMove = duplicate()
	for key in overrides:
		move.set(key, overrides[key])
	return move
