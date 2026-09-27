extends Resource
class_name CombatTuning

@export_group("Movement")
@export var walk_speed := 5.0
@export var sprint_speed := 8.0
@export var acceleration := 14.0
@export var jump_velocity := 5.2

@export_group("Timing")
@export var input_buffer := 0.15
@export var light_hitstop := 0.028
@export var heavy_hitstop := 0.06
# Legacy mirror of SwordGuardProfile.perfect_guard_window, kept so the old
# guard tests and any external tooling still read a value. The live window is
# per-style and lives in the moveset.
@export var perfect_guard_window := 0.12
@export var combo_window := 0.48
# Hold Heavy: up to 0.8s of charge, translated into posture and hit reaction
# rather than a flat damage multiplier.
@export var heavy_charge_time := 0.8
@export var heavy_tap_grace := 0.18
# Incoming damage at or above this interrupts the player's own swing. Spamming
# through an enemy heavy must not be a valid answer.
@export var player_stagger_threshold := 20.0
# How long a follow-up window survives the end of the move it belongs to, so
# the player is never punished for watching their own animation.
@export var followup_grace := 0.12
# Cooldown for style signatures that are short player-driven sequences (长风)
# rather than full ceremonies (聚合斩, which times itself off the director).
@export var signature_cooldown := 12.0

@export_group("Camera")
@export var light_camera_impulse := 0.015
@export var heavy_camera_impulse := 0.04
@export var shake_decay := 1.8

@export_group("Resources")
@export var max_stamina := 100.0
@export var max_mana := 100.0
@export var dodge_stamina_cost := 20.0

@export_group("Iaido Targeting")
@export var iaido_range := 10.0
@export var iaido_cone_degrees := 45.0
@export var iaido_vertical_tolerance := 3.0
@export var iaido_vertical_cone_degrees := 25.0
