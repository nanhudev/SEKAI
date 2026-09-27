extends AbilityData
class_name SpellDefinition
# A single spell, described as data on top of the existing cast timing resource.
#
# The controller used to answer "what colour is the magic circle" and "which
# hitbox is this" with ternaries on a string. Now it reads the school's element
# definition instead, so adding a spell means adding data.

enum Cast {
	QUICK,  # one hand, the sword stays in the other: 火种 / 风压 / 寒流
	FULL,   # the whole body commits to a cast pose: 焚环 / 凝霜
}

@export var school_id: StringName = &""
@export var element_id: StringName = &"physical"
@export var cast_mode: Cast = Cast.QUICK
@export var note := ""

@export_group("Delivery")
@export var hitbox_damage := 0.0
@export var hitbox_poise := 0.0
@export var hitbox_impulse := 0.0
@export var hitbox_size := Vector3(2.0, 1.4, 2.0)
@export var hitbox_offset := Vector3(0.0, -0.2, -1.6)

@export_group("Field")
# A spell that leaves something behind on the ground is doing a different job
# from one that hits: it changes where the fight can happen.
@export var field_radius := 0.0
@export var field_duration := 0.0
@export var field_tick_interval := 0.5
@export var field_offset := 1.8

@export_group("Sword")
# Running the blade through a live source infuses it. No menu, no school lock.
@export var infuses_blade := false
