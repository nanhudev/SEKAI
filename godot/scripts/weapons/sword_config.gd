extends Resource
# Shared sword data. Existing resources remain the owners of their own domains.
@export var attack_damage := PackedFloat32Array([21.0,24.0,46.0,34.0])
@export var combo_window := 0.90
@export var hit_stop := PackedFloat32Array([0.045,0.055,0.075,0.105])
@export var heavy_hit_stop := 0.095
@export var camera_strength := 1.0
@export var draw_time := 1.75
@export var sheath_time := 1.75
@export var presentation: Resource = preload("res://resources/tuning/SwordPresentationConfig.tres")
@export var combat_iaido: IaidoTuning = preload("res://resources/tuning/IaidoCombatTuning.tres")

var trail_length: PackedFloat32Array:
	get: return presentation.get("trail_lifetimes")

var iaido_duration: float:
	get: return combat_iaido.restore_end
