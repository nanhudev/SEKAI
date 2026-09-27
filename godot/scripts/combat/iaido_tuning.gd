extends Resource
class_name IaidoTuning

@export_group("Timeline (real seconds)")
@export var world_lock := 0.0
@export var focus_start := 0.12
@export var focus_end := 0.42
@export var first_click := 0.42
@export var wave_end := 0.62
@export var first_tear_end := 0.78
@export var hold_end := 0.92
@export var draw_slow_end := 0.98
@export var draw_fast_end := 1.03
@export var draw_end := 1.08
@export var rupture_end := 1.30
@export var split_end := 1.50
@export var glass_end := 1.68
@export var recovery_end := 1.95
@export var final_click := 1.95
@export var damage_time := 1.48
@export var restore_end := 2.25

@export_group("Playback")
@export_range(0.25, 1.0, 0.05) var debug_speed := 1.0
