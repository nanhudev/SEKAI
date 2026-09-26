extends Area3D
class_name CombatHitbox

@export var damage := 20.0
@export var poise_damage := 20.0
@export var element: StringName = &"physical"
@export var impulse := 2.0
@export var hit_delay := 0.0

var source: Node3D
var active := false
var hit_targets: Dictionary = {}


func _ready() -> void:
	monitoring = false
	area_entered.connect(_on_area_entered)


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
	}
	if hit_delay > 0.0:
		var target: CombatHurtbox = area
		get_tree().create_timer(hit_delay).timeout.connect(func() -> void:
			if is_instance_valid(target):
				target.receive_hit(hit)
		)
	else:
		area.receive_hit(hit)
