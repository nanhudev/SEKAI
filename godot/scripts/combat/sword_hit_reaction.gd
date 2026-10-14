extends Node
# A visual body response; runs even when a static training target's AI is off.
var body: Node3D
var home := Vector3.ZERO
var base_xz := Vector2.ZERO
var offset := Vector3.ZERO
var tilt := Vector2.ZERO
var extra_parts: Dictionary = {}

func bind(mesh: Node3D) -> void:
	body = mesh
	home = body.position
	base_xz = Vector2(body.rotation.x, body.rotation.z)

func add_part(mesh: Node3D) -> void:
	extra_parts[mesh] = {"position":mesh.position,"rotation":mesh.rotation}

func react(hit: Dictionary) -> void:
	if not is_instance_valid(body):
		return
	var direction: Vector3 = hit.get("slash_direction", Vector3.ZERO)
	if direction.is_zero_approx():
		var source := hit.get("source") as Node3D
		if source != null:
			direction = body.global_position - source.global_position
	direction = body.get_parent_node_3d().global_basis.inverse() * direction.normalized()
	var heavy: bool = hit.get("finisher", false) or hit.get("iaido", false) or float(hit.get("poise_damage",0)) >= 35.0
	var strength := 0.26 if heavy else 0.12
	if hit.get("rising_cut",false):
		# Visual lift, not a new airborne enemy state or physics displacement.
		offset.y = maxf(offset.y,0.16)
		tilt.x += 0.12
	offset = (offset + direction * strength).limit_length(0.32)
	tilt = (tilt + Vector2(direction.z,-direction.x) * (0.24 if heavy else 0.12)).limit_length(0.32)

func _process(delta: float) -> void:
	if not is_instance_valid(body):
		return
	body.position = home + offset
	body.rotation.x = base_xz.x + tilt.x
	body.rotation.z = base_xz.y + tilt.y
	for mesh in extra_parts:
		if is_instance_valid(mesh):
			mesh.position = extra_parts[mesh].position + offset
			mesh.rotation.x = extra_parts[mesh].rotation.x + tilt.x
			mesh.rotation.z = extra_parts[mesh].rotation.z + tilt.y
	var settle := exp(-15.0 * delta)
	offset *= settle
	tilt *= settle

func reset() -> void:
	offset = Vector3.ZERO
	tilt = Vector2.ZERO
	if is_instance_valid(body):
		body.position = home
		body.rotation.x = base_xz.x
		body.rotation.z = base_xz.y
	for mesh in extra_parts:
		if is_instance_valid(mesh):
			mesh.position = extra_parts[mesh].position
			mesh.rotation = extra_parts[mesh].rotation
