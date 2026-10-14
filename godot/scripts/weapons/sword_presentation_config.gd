extends Resource
# Presentation-only data. Damage/windows stay in SwordMove/SwordMoveset.
@export var trail_lifetimes := PackedFloat32Array([0.080, 0.100, 0.090, 0.140])
@export var contact_lifetime := 0.12
@export var parry_lifetime := 0.16
@export var impact_scale := 0.18
@export var glove_color := Color(0.055, 0.065, 0.085)
@export var cuff_color := Color(0.16, 0.19, 0.23)
