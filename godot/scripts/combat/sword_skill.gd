extends Resource
class_name SwordSkill
# A style skill. Deliberately small: skills must change the RHYTHM of the
# style, not just add damage on a cooldown.

enum Kind {
	ATTACK,     # a move that happens to be on a cooldown
	ENHANCE,    # a state that changes startup / windows / posture for a while
	INTERRUPT,  # a precise cut that stops what the enemy was doing
	MOBILITY,   # displacement with a cut attached
}

@export var id: StringName = &""
@export var display_name := ""
@export var note := ""
@export var kind: Kind = Kind.ATTACK
@export var cooldown := 8.0
@export var move_id: StringName = &""

@export_group("Enhance state")
@export var enhance_duration := 8.0
@export var enhance_startup_scale := 0.85
@export var enhance_perfect_guard_bonus := 0.03
@export var enhance_first_hit_poise_scale := 1.6
@export var enhance_sheathe_scale := 0.7

@export_group("Interrupt")
@export var interrupt_damage_scale := 1.0
@export var interrupt_stagger := 0.85
