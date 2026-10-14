extends Resource
class_name PhantomChainProfile
# PHANTOM CHAIN V0.1 — numbers only. No logic.
# Tuning lives here so the controller stays a state machine, not a spreadsheet.

@export_group("Identity")
@export var base_color := Color(0.72, 0.80, 0.90, 1.0)
@export var idle_alpha := 0.38
@export var travel_alpha := 0.55
@export var tension_alpha := 0.92
@export var link_spacing := 0.14
@export var link_thickness := 0.038
@export var max_visible_links := 48

@export_group("Equip")
@export var equip_seconds := 0.55
@export var idle_link_interval_min := 0.8
@export var idle_link_interval_max := 2.0

@export_group("Combo")
@export var combo_window := 0.55
@export var a1_startup := 0.06
@export var a1_active := 0.22
@export var a1_recover := 0.18
@export var a1_range := 4.2
@export var a1_arc_degrees := 145.0
@export var a1_damage := 14.0
@export var a1_hitstop := 0.020

@export var a2_startup := 0.04
@export var a2_active := 0.14
@export var a2_recover := 0.16
@export var a2_range := 5.0
@export var a2_arc_degrees := 55.0
@export var a2_damage := 18.0
@export var a2_hitstop := 0.032

@export var a3_startup := 0.08
@export var a3_active := 0.10
@export var a3_recover := 0.20
@export var a3_range := 6.0
@export var a3_damage := 10.0
@export var a3_bind_seconds := 1.0
@export var a3_slack := 1.5
@export var a3_pull_distance := 1.5
@export var a3_hitstop := 0.040
@export var a3_pull_hitstop := 0.035

@export var a4_startup := 0.10
@export var a4_active := 0.45
@export var a4_recover := 0.22
@export var a4_radius := 4.0
@export var a4_arc_count := 4
@export var a4_spin_degrees := 240.0
@export var a4_damage := 22.0
@export var a4_hitstop := 0.040

@export_group("Visual")
@export var materialize_ms := 0.045
@export var dissolve_ms := 0.14
@export var tension_wave_ms := 0.18
