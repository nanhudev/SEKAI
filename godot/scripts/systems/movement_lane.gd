extends Node3D
class_name MovementLane
# A separate stage for movement, and only for movement.
#
# WHY IT EXISTS: the arena physically cannot answer "does 风步 / 回风's loop feel
# good to move with?", because the dummy stands on the exact line the player
# walks down. Every forward attempt ends in a collision about two metres in, so a
# movement take turns into a shove and the only thing it measures is the enemy's
# pushbox. Combat needs an enemy in front of the player; movement needs nothing
# in front of the player. Those are two different stages, so this is the second.
#
# Unlike ArenaDressing, which is silhouette only and has no collision, this
# platform is REAL collision: being walked on is its entire job. ART may replace
# the meshes, but the deck plane, the kerbs that stop a run falling off the world
# (the arena floor is only 24 x 24 and there is no kill plane), and the distance
# markings must survive, because they are what makes "further in the same time"
# a thing a viewer can check.

# Offset in +x on purpose. The arena floor is 24 x 24 with nothing below it, and
# the ramp has to land ON that floor — keep the lane centred and its foot falls
# exactly on the floor's edge, so the way on is a hole you only find by falling
# through it.
const CENTER := Vector3(2.0, 0.0, 8.5)
const LENGTH := 18.0      # the run, along x
const WIDTH := 3.6        # lateral, along z
const DECK_Y := 0.9       # walking surface height
const KERB_HEIGHT := 0.5
const MARK_STEP := 3.0
const RAMP_RUN := 3.0

const DECK_TINT := Color(0.31, 0.31, 0.35)
const MARK_TINT := Color(0.58, 0.56, 0.48)
const INTERVAL_TINT := Color(0.74, 0.47, 0.32)
const KERB_TINT := Color(0.19, 0.20, 0.23)

# Every run goes the same way, so two takes are comparable by construction.
const RUN_DIRECTION := Vector3(1.0, 0.0, 0.0)


func _ready() -> void:
	_deck()
	_kerbs()
	_markings()
	_ramp()


# Slightly above the deck: the player has gravity, so dropping them in settles
# them onto it instead of guessing the exact standing height.
func start_position() -> Vector3:
	return Vector3(CENTER.x - LENGTH * 0.5 + 1.8, DECK_Y + 1.4, CENTER.z)


func end_x() -> float:
	return CENTER.x + LENGTH * 0.5


func _material(tint: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = tint
	material.roughness = 0.94
	return material


func _solid(size: Vector3, tint: Color, pos: Vector3, tilt := 0.0) -> void:
	# One body, one box, one mesh. Collision is the point here, not an extra.
	var body := StaticBody3D.new()
	body.position = pos
	body.rotation = Vector3(0.0, 0.0, tilt)
	add_child(body)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	var mesh := MeshInstance3D.new()
	var mesh_box := BoxMesh.new()
	mesh_box.size = size
	mesh.mesh = mesh_box
	mesh.material_override = _material(tint)
	body.add_child(mesh)


func _flat(size: Vector3, tint: Color, pos: Vector3) -> void:
	# Markings are paint: no collision, so they cannot catch a footstep.
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = _material(tint)
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh.position = pos
	add_child(mesh)


func _deck() -> void:
	# Thick rather than a sheet: it stands on the arena floor, so it should read
	# as a platform somebody built, not as a decal.
	_solid(Vector3(LENGTH, DECK_Y, WIDTH), DECK_TINT, CENTER + Vector3(0.0, DECK_Y * 0.5, 0.0))


func _kerbs() -> void:
	# All four edges. The arena floor ends at |x| 12 and |z| 12 with nothing
	# below it, so an unkerbed platform is a way to fall out of the world.
	var half_z := WIDTH * 0.5 - 0.15
	for side in [-1.0, 1.0]:
		_solid(
			Vector3(LENGTH, KERB_HEIGHT, 0.3),
			KERB_TINT,
			CENTER + Vector3(0.0, DECK_Y + KERB_HEIGHT * 0.5, side * half_z)
		)
	var half_x := LENGTH * 0.5 - 0.15
	# Far end only. Capping the near end too would wall off the ramp that is
	# supposed to be the way on — a barricade you only discover by trying to walk
	# up your own platform.
	_solid(
		Vector3(0.3, KERB_HEIGHT, WIDTH),
		KERB_TINT,
		CENTER + Vector3(half_x, DECK_Y + KERB_HEIGHT * 0.5, 0.0)
	)


func _markings() -> void:
	# The ground has to state the distance. A take that claims "the same 1.6
	# seconds covered more ground with 风步" is only checkable if the platform
	# says how much ground was covered.
	var count := int(LENGTH / MARK_STEP)
	for i in range(count + 1):
		var x := -LENGTH * 0.5 + float(i) * MARK_STEP
		var interval := i % 3 == 0
		_flat(
			Vector3(0.30 if interval else 0.14, 0.03, WIDTH - 0.7),
			INTERVAL_TINT if interval else MARK_TINT,
			CENTER + Vector3(x, DECK_Y + 0.015, 0.0)
		)


func _ramp() -> void:
	# A way on and off from the arena side, so this is part of the world rather
	# than a pocket only a teleport can reach.
	var angle := atan2(DECK_Y, RAMP_RUN)
	var slope := sqrt(RAMP_RUN * RAMP_RUN + DECK_Y * DECK_Y)
	var thickness := 0.28
	var near_x := CENTER.x - LENGTH * 0.5
	# Shift the slab along its own normal so its TOP face passes through the line
	# from the floor to the deck edge. Without this the ramp's upper surface sits
	# half a thickness above the deck and leaves a lip for the player to catch on.
	var normal := Vector3(-sin(angle), cos(angle), 0.0)
	_solid(
		Vector3(slope, thickness, WIDTH),
		DECK_TINT,
		Vector3(near_x - RAMP_RUN * 0.5, DECK_Y * 0.5, CENTER.z) - normal * (thickness * 0.5),
		angle
	)
	# A support so the slope is not a plank hanging in the air, kept well clear of
	# the walking surface. Its top MUST stay below the ramp at that x, or it is not
	# a support, it is a knee-high wall across the only way onto the platform:
	# the first version was 0.45m tall and the only symptom was the player stopping
	# dead 0.3m short of the ramp.
	var support_height := 0.34
	var support_x := near_x - RAMP_RUN * 0.35
	_solid(
		Vector3(0.45, support_height, WIDTH * 0.7),
		KERB_TINT,
		Vector3(support_x, support_height * 0.5, CENTER.z)
	)
