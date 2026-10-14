extends Resource
class_name MirrorConfig
# MIRROR V0.1 — numbers only. Codex retunes handfeel here; controller stays a state machine.

@export_group("Nodes")
@export var mirror_max_count := 3
@export var mirror_place_min := 2.0
@export var mirror_place_max := 12.0
@export var mirror_height := 1.25
@export var mirror_width := 0.65
@export var mirror_wall_offset := 0.10
@export var clear_nodes_on_unequip := true
@export var place_lock_ms := 0.12
@export var spawn_anim_ms := 0.15

@export_group("Safe Exit")
@export var exit_offset_min := 0.6
@export var exit_offset_max := 1.2
@export var exit_probe_radius := 0.35
@export var exit_probe_height := 1.8

@export_group("Combo")
@export var combo_window := 0.70
@export var a1_startup := 0.06
@export var a1_active := 0.14
@export var a1_recover := 0.18
@export var a1_range := 2.8
@export var a1_half_width := 0.85
@export var a1_damage := 16.0
@export var a1_echo_delay := 0.13
@export var a1_echo_damage_scale := 0.60
@export var a1_echo_range := 2.8

@export var a2_startup := 0.08
@export var a2_active := 0.20
@export var a2_recover := 0.22
@export var a2_range := 10.0
@export var a2_damage := 18.0
@export var a2_max_reflections := 2
@export var a2_mirror_catch_radius := 1.15
@export var a2_assist_degrees := 15.0

@export var a3_startup := 0.10
@export var a3_active := 0.16
@export var a3_recover := 0.22
@export var a3_echo_damage := 10.0
@export var a3_echo_range := 2.2

@export var a4_startup := 0.08
@export var a4_transit_ms := 0.18
@export var a4_recover := 0.20
@export var a4_shift_range := 18.0

@export_group("Travel")
@export var travel_duration := 1.25
@export var exit_attack_window := 0.35
@export var exit_cut_range := 2.0
@export var exit_cut_dash := 1.4
@export var exit_cut_damage := 22.0
@export var travel_invuln := true
@export var preserve_view_direction := true
@export var travel_fov_kick := 8.0

@export_group("Visual Prototype")
@export var card_color := Color(0.55, 0.62, 0.68, 0.92)
@export var card_fresnel := Color(0.70, 0.92, 0.95, 1.0)
@export var node_color := Color(0.48, 0.58, 0.66, 0.78)
@export var node_selected_boost := 1.08
@export var tint_color := Color(0.55, 0.72, 0.82, 0.35)
