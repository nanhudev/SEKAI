extends Resource
class_name ElementDefinition
# What an element IS, as data.
#
# The enemy used to answer "what does frost do?" with a chain of
# `if element == frost` branches and a fistful of magic numbers. That is the
# same mistake the sword layer already had: the moment a second thing needs to
# react to an element, the rules have to be copied. So the rules live here, and
# actors only decide what to DO about a stage change.
#
# FROST uses the build-up ladder. FIRE and WIND do not climb — they act on
# apply and on contact — so their stage arrays stay empty on purpose.

@export var id: StringName = &""
@export var display_name := ""
@export var tint := Color(1.0, 1.0, 1.0, 1.0)

@export_group("Build-up ladder")
# Index 0 is always the base state. Thresholds are ascending and the same
# length as the names, so a definition cannot describe a stage it never reaches.
@export var stage_names: Array[StringName] = []
@export var stage_thresholds: Array[float] = []
@export var applies_per_hit := 40.0
@export var decay_rate := 4.0
@export var decay_delay := 0.6

@export_group("Damage")
# Fire has to hurt on contact, not only over time, or a spell that "applies a
# state" feels like it did nothing at the moment it landed.
@export var impact_damage := 0.0
@export var tick_damage := 0.0
@export var tick_interval := 0.5
@export var tick_poise := 0.0

@export_group("Behaviour")
# Reaching the top stage interrupts whatever the target was doing.
@export var final_stage_staggers := false
@export var final_stage_duration := 0.0
# At the top stage the target takes more from the right follow-up (Frozen → Heavy).
@export var enables_brittle := false
@export var brittle_bonus := 1.0
# Wind: move the target, scaled by how heavy it is.
@export var pushes := false
@export var push_weight_scaled := false
@export var push_staggers := false
# Wind crossing this state spreads it to neighbours (Fire spreads, Frost chills).
@export var spread_by_wind := false
@export var spread_radius := 0.0
@export var spread_amount := 0.0
# This state makes another element's build-up fall away faster.
@export var hastens_decay_of: Array[StringName] = []
@export var hasten_multiplier := 2.5
# Enemies flinch on their own while this is running (Burning panic).
@export var panic_health_fraction := 0.0

@export_group("Sword infusion")
# Running the blade through a live source of this element infuses it for a
# while. This is how the sword joins the magic system without a menu.
@export var infusion_duration := 0.0
@export var infusion_applies := 0.0
@export var infusion_damage_bonus := 0.0


func has_ladder() -> bool:
	return not stage_names.is_empty() and stage_names.size() == stage_thresholds.size()


func stage_index_for(amount: float) -> int:
	if not has_ladder():
		return 0
	var index := 0
	for i in stage_thresholds.size():
		if amount >= stage_thresholds[i]:
			index = i
	return index


func is_final_stage(index: int) -> bool:
	return has_ladder() and index == stage_names.size() - 1


func top_threshold() -> float:
	if not has_ladder():
		return 0.0
	return stage_thresholds[stage_thresholds.size() - 1]
