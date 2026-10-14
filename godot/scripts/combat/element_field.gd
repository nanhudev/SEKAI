extends Area3D
class_name ElementField
# A live patch of an element: 焚环's burning ground, a drifting frost cloud.
#
# This is what makes FIRE an area question instead of a damage colour. The field
# applies its element on a cadence to whatever is standing inside it, and wind
# can carry it outward — so the player is choosing WHERE the fight happens, not
# just what number appears.
#
# It knows nothing about any specific element: everything comes from the
# ElementDefinition it is handed.

@export var element_id: StringName = &"fire"
@export var radius := 2.4
@export var duration := 6.0
@export var tick_interval := 0.5
@export var apply_amount := 0.0
@export var impulse := 0.0

var definition: ElementDefinition
var source: Node3D
var remaining := 6.0
var tick_left := 0.0
var _shape: CylinderShape3D
var _ring: MeshInstance3D
var _ring_material: StandardMaterial3D


func setup(def: ElementDefinition, from: Node3D) -> void:
	definition = def
	source = from
	element_id = def.id
	remaining = duration


func _ready() -> void:
	if definition == null:
		definition = ElementLibrary.get_element(element_id)
	if definition != null:
		element_id = definition.id
	remaining = duration
	monitoring = true
	_shape = CylinderShape3D.new()
	_shape.radius = radius
	_shape.height = 1.8
	var collision := CollisionShape3D.new()
	collision.shape = _shape
	collision.position.y = 0.9
	add_child(collision)
	_build_visual()
	area_entered.connect(_on_area_entered)


func _build_visual() -> void:
	_ring_material = StandardMaterial3D.new()
	_ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ring_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var tint := Color(1.0, 0.45, 0.12, 0.30)
	if definition != null:
		tint = Color(definition.tint.r, definition.tint.g, definition.tint.b, 0.30)
	_ring_material.albedo_color = tint
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius * 0.92
	mesh.height = 0.16
	_ring = MeshInstance3D.new()
	_ring.name = "FieldBody"
	_ring.mesh = mesh
	_ring.material_override = _ring_material
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ring)


func _process(delta: float) -> void:
	remaining -= delta
	tick_left -= delta
	if _ring != null:
		var life := clampf(remaining / maxf(duration, 0.01), 0.0, 1.0)
		var pulse := 1.0 + sin(remaining * 9.0) * 0.03
		_ring.scale = Vector3(pulse, 1.0, pulse)
		_ring_material.albedo_color.a = 0.34 * life
	if tick_left <= 0.0:
		tick_left = tick_interval
		_apply_to_overlaps()
	if remaining <= 0.0:
		queue_free()


func _on_area_entered(area: Area3D) -> void:
	if area is CombatHurtbox:
		_deliver(area)


func _apply_to_overlaps() -> void:
	for area in get_overlapping_areas():
		if area is CombatHurtbox:
			_deliver(area)


func _deliver(hurtbox: CombatHurtbox) -> void:
	var target = hurtbox.owner_actor
	if target == null or not target.has_method("is_brittle"):
		return
	# The field applies the ELEMENT; the element's own impact and tick damage do
	# the hurting. Dealing damage here too would double-dip the same burn.
	hurtbox.receive_hit({
		"damage": 0.0,
		"poise_damage": 0.0,
		"element": element_id,
		"impulse": impulse,
		"source": source,
		"target": target,
		"from_field": true,
	})


# Wind crossing a burning field carries it: the field widens and reaches further.
# This is the mechanical half of "wind spreads fire", and it is why the two
# elements are worth combining rather than stacking.
func spread(multiplier: float = 1.45) -> void:
	if definition != null and not definition.spread_by_wind:
		return
	radius *= multiplier
	if _shape != null:
		_shape.radius = radius
	if _ring != null:
		(_ring.mesh as CylinderMesh).top_radius = radius
		(_ring.mesh as CylinderMesh).bottom_radius = radius * 0.92
	remaining = maxf(remaining, duration * 0.6)
	_apply_to_overlaps()


func is_alive() -> bool:
	return remaining > 0.0
