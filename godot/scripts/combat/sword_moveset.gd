extends Resource
class_name SwordMoveset
# A sword style is a set of overrides on the Universal Sword Layer, not a
# second game. Nothing here is allowed to need its own CombatController.

@export var style_id: StringName = &"universal"
@export var display_name := "Universal"
@export var tagline := ""
@export var implemented := true

@export_group("Universal Sword Layer")
@export var light_chain: Array[StringName] = []
@export var heavy_id: StringName = &""
@export var sprint_light_id: StringName = &""
@export var retreat_light_id: StringName = &""
@export var riposte_id: StringName = &""
# 聚合斩: a SIGNATURE technique. It has its own cooldown and does NOT occupy
# the ultimate slot.
@export var signature_id: StringName = &""
@export var ultimate_id: StringName = &""
@export var skills: Array[SwordSkill] = []
@export var moves: Dictionary = {}
@export var guard: SwordGuardProfile

@export_group("Anchors")
@export var idle_pose := Vector3(0.52, -0.50, -0.94)
@export var idle_pose_rot := Vector3(0.0, 0.0, -0.18)

@export_group("Rhythm")
# Grace after a move ends during which the next Light continues the chain.
@export var combo_window := 0.46
# Dodge / guard cancels unlock this deep into the move.
@export var dodge_cancel_from := 0.38
# < 1 shortens recovery on a connected hit (回风 flows, 藏锋 does not).
@export var flow_on_hit_recovery := 1.0
@export var flow_min_recovery := 0.10

@export_group("Flow")
# 回风式's 势. An INTERNAL value — deliberately not a big UI bar. It rises while
# you keep connecting and moving, falls when you whiff, and decays when you
# stand still. It must never be a damage multiplier: it buys *smoothness*
# (recovery, steering, earlier transitions), so the player feels the sword get
# easier to handle rather than simply hitting harder.
@export var flow_enabled := false
@export var flow_max := 100.0
@export var flow_gain_hit := 12.0
# Movement attacks feed the style specifically: 回风 wants you to attack on the move.
@export var flow_gain_movement_hit := 19.0
@export var flow_gain_deflect := 24.0
@export var flow_loss_miss := 16.0
@export var flow_decay := 9.0
@export var flow_decay_delay := 1.6
# Recovery multiplier at full Flow, applied only to connected cuts.
@export var flow_recovery_at_max := 0.58
# Steering multiplier at full Flow: this is how "顺势" is felt in the hands.
@export var flow_steer_bonus := 1.45
# Fraction earlier that cancels open at full Flow: transitions stop snagging.
@export var flow_transition_bonus := 0.50

@export_group("Measure")
# 白蔷庭's core mechanic. Distance IS the resource, and it deliberately has no
# bar: the style reads the space between you and the opponent and changes the
# QUALITY of the attack from it. Ideal measure buys startup, reach and posture —
# never plain damage, or the style collapses into "stand at the magic distance
# and collect numbers".
@export var measure_enabled := false
# Closer than this the point has no room to extend: crowding.
@export var measure_close := 1.50
# Past this the thrust arrives late and the point is spent.
@export var measure_far := 3.20
# Which way counts as "in front of me", and how far the style bothers to read.
@export var measure_cone_degrees := 55.0
@export var measure_max_range := 6.0
@export var measure_ideal_startup_scale := 0.80
@export var measure_ideal_poise_scale := 1.55
# Ideal measure also extends the reach: a properly extended point is longer.
@export var measure_ideal_reach := 0.30
@export var measure_close_startup_scale := 1.25
@export var measure_close_poise_scale := 0.70
@export var measure_far_startup_scale := 1.20
@export var measure_far_poise_scale := 0.85

@export_group("Pose solver")
@export var pose_stiffness := 96.0
@export var pose_damping := 0.94
@export var tremor := 0.0035
@export var trail_width := 0.030

@export_group("Sheath")
@export var sheath_enabled := false
@export var sheath_delay := 0.55
@export var sheath_time := 0.40
@export var sheath_pose := Vector3(-0.50, -0.60, -0.74)
@export var sheath_pose_rot := Vector3(0.12, -0.16, 2.12)
@export var sheath_scabbard_pose := Vector3(-0.42, -0.58, -0.62)
@export var sheath_scabbard_rot := Vector3(0.05, -0.30, 2.05)
# Sheathing is a real mechanic: starting 一文字 from a full sheath is stronger.
@export var sheathed_startup_scale := 0.78
@export var sheathed_poise_scale := 1.55
@export var sheathed_recovery_scale := 1.0


func get_move(move_id: StringName) -> SwordMove:
	if move_id == &"":
		return null
	return moves.get(move_id)


func get_skill(skill_id: StringName) -> SwordSkill:
	for skill in skills:
		if skill.id == skill_id:
			return skill
	return null


func light_move(index: int) -> SwordMove:
	if light_chain.is_empty():
		return null
	return get_move(light_chain[index % light_chain.size()])


func has_light_chain() -> bool:
	return not light_chain.is_empty()
