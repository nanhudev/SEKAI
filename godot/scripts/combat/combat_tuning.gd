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
@export var perfect_guard_window := 0.18
@export var combo_window := 0.48

@export_group("Camera")
@export var light_camera_impulse := 0.015
@export var heavy_camera_impulse := 0.04
@export var shake_decay := 1.8

@export_group("Resources")
@export var max_stamina := 100.0
@export var max_mana := 100.0
@export var dodge_stamina_cost := 20.0
