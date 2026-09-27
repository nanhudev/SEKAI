extends Node3D
class_name WindProps
# Placeholder wind environment.
#
# Wind is only a real system if the world can interrupt what it throws. Without
# something to slam into, "Wind Push" is just a knockback number; with a wall it
# becomes a way to convert position into posture damage, which is the whole
# point of the element.
#
# Deliberately deterministic and collision-simple: no randomness, no navmesh,
# flat boxes. ART replaces the meshes; the physical ROLES (a wall to be thrown
# into, light bodies that actually move) must stay.

@export var build_wall := true
@export var build_light_objects := true

var wall: StaticBody3D
var light_objects: Array[RigidBody3D] = []

const WALL_POSITION := Vector3(0.0, 1.6, -6.0)
const WALL_SIZE := Vector3(9.0, 3.2, 0.6)
# Where the movable bodies start, so the scene can be restored.
const LIGHT_OBJECT_STARTS: Array[Vector3] = [
	Vector3(-1.5, 0.45, -3.2),
	Vector3(1.5, 0.45, -3.6),
]
# The player stands here to throw something into the wall: close enough that the
# push distance (impulse in metres) cannot overshoot, far enough to be readable.
const WALL_TEST_PLAYER := Vector3(0.0, 1.15, -0.9)
const WALL_TEST_TARGET := Vector3(0.0, 0.6, -2.4)


func _ready() -> void:
	if build_wall:
		_build_wall()
	if build_light_objects:
		for at in LIGHT_OBJECT_STARTS:
			_build_light_object(at)


# Puts the movable bodies back. The Combat Lab needs this: blowing the same two
# boxes into the wall twenty times must not slowly dismantle the test scene.
func reset() -> void:
	for i in light_objects.size():
		var body := light_objects[i]
		if not is_instance_valid(body):
			continue
		if i < LIGHT_OBJECT_STARTS.size():
			body.global_position = LIGHT_OBJECT_STARTS[i]
		body.linear_velocity = Vector3.ZERO
		body.angular_velocity = Vector3.ZERO


func _material(tint: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = tint
	material.roughness = 0.85
	return material


func _build_wall() -> void:
	wall = StaticBody3D.new()
	wall.name = "WindWall"
	wall.position = WALL_POSITION
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = WALL_SIZE
	shape.shape = box
	wall.add_child(shape)
	var mesh := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = WALL_SIZE
	mesh.mesh = box_mesh
	mesh.material_override = _material(Color(0.34, 0.33, 0.38))
	wall.add_child(mesh)
	add_child(wall)


func _build_light_object(at: Vector3) -> void:
	var body := RigidBody3D.new()
	body.name = "LightObject"
	body.position = at
	body.mass = 2.5
	# Light enough that wind is visibly a force, not a suggestion.
	body.linear_damp = 1.2
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.5, 0.5, 0.5)
	shape.shape = box
	body.add_child(shape)
	var mesh := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = Vector3(0.5, 0.5, 0.5)
	mesh.mesh = box_mesh
	mesh.material_override = _material(Color(0.62, 0.55, 0.44))
	body.add_child(mesh)
	add_child(body)
	light_objects.append(body)


# Applies a real impulse to every light body inside the cone. This is what makes
# "wind moves the world" a fact the player can see rather than a claim.
func blow(origin: Vector3, direction: Vector3, impulse: float, cone_degrees: float, radius: float) -> int:
	var moved := 0
	# Wind is horizontal. The enemy push path already flattens its direction, and
	# if this one did not, aiming slightly downward would drive the impulse into
	# the floor and quietly turn a gust into nothing — pitch must not be a hidden
	# multiplier on how much wind moves the world.
	direction.y = 0.0
	if direction.length_squared() < 0.0001:
		return 0
	direction = direction.normalized()
	var limit := cos(deg_to_rad(cone_degrees))
	for body in light_objects:
		if not is_instance_valid(body):
			continue
		var offset: Vector3 = body.global_position - origin
		offset.y = 0.0
		if offset.length() > radius or offset.length() < 0.01:
			continue
		if offset.normalized().dot(direction) < limit:
			continue
		body.apply_central_impulse(direction * impulse + Vector3.UP * impulse * 0.12)
		moved += 1
	return moved
