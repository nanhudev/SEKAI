extends Area3D
class_name CombatHitbox

signal hit_landed(hit: Dictionary)

@export var damage := 20.0
@export var poise_damage := 20.0
@export var element: StringName = &"physical"
@export var impulse := 2.0
@export var hit_delay := 0.0

var source: Node3D
var active := false
var hit_targets: Dictionary = {}
var box: BoxShape3D
var shape_node: CollisionShape3D


func _ready() -> void:
	monitoring = false
	area_entered.connect(_on_area_entered)
	shape_node = get_node_or_null("CollisionShape3D") as CollisionShape3D
	_own_shape()


func _own_shape() -> void:
	if shape_node == null or not (shape_node.shape is BoxShape3D):
		return
	if box != null:
		return
	# Own the shape instead of mutating the shared scene sub-resource, so
	# resizing one player's sword cannot resize another instance's.
	box = shape_node.shape.duplicate() as BoxShape3D
	shape_node.shape = box


func configure(box_size: Vector3, offset: Vector3) -> void:
	_own_shape()
	if box != null:
		box.size = box_size
	position = offset


func set_active(enabled: bool) -> void:
	active = enabled
	set_deferred("monitoring", enabled)
	if enabled:
		hit_targets.clear()


func _on_area_entered(area: Area3D) -> void:
	if not active or not area is CombatHurtbox or hit_targets.has(area):
		return
	if source != null and area.owner_actor == source:
		return
	hit_targets[area] = true
	var hit := {
		"damage": damage,
		"poise_damage": poise_damage,
		"element": element,
		"impulse": impulse,
		"source": source,
		"target": area.owner_actor,
	}
	hit_landed.emit(hit)
	if hit_delay > 0.0:
		var target: CombatHurtbox = area
		get_tree().create_timer(hit_delay).timeout.connect(func() -> void:
			if is_instance_valid(target):
				target.receive_hit(hit)
		)
	else:
		area.receive_hit(hit)
