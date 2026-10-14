extends Resource
class_name SwordSkill
# A style skill. Deliberately small: skills must change the RHYTHM of the
# style, not just add damage on a cooldown.

enum Kind {
	ATTACK,     # a move that happens to be on a cooldown
	ENHANCE,    # a state that changes startup / windows / posture for a while
	INTERRUPT,  # a precise cut that stops what the enemy was doing
	MOBILITY,   # displacement with a cut attached
	SLIP,       # let the attack miss entirely, then answer into the gap
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
# 惊鸿: while active, the exits out of an attack open far earlier, so Light /
# Dodge / Sprint stop snagging on each other. A transition enhancer, not damage.
@export var enhance_transition_bonus := 0.0
@export var enhance_steer_bonus := 1.0

@export_group("Interrupt")
@export var interrupt_damage_scale := 1.0
@export var interrupt_stagger := 0.85

@export_group("Slip")
# 折柳. A short window in which an incoming attack is allowed to pass by instead
# of being met. This is the opposite answer to Perfect Guard: you do not win the
# exchange, you decline it — and then cut into the space it left behind.
@export var slip_window := 0.35
@export var slip_distance := 1.7
@export var slip_counter_window := 0.9
@export var slip_flow_gain := 22.0
