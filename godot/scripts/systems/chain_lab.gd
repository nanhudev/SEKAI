extends Node3D
class_name ChainLab
# CHAIN LAB — a stage with enough room for a chain to actually be thrown.
#
# WHY IT EXISTS: the arena cannot answer "is the chain fun?". The arena is 24 x 24
# with an enemy standing on the walking line, so a 4.6m sweep either clips a pillar
# or the dummy, and there is nowhere to throw a head far enough to feel the chain
# go taut. 缚星链 is a weapon about SPACE, so it needs a room that has some: a
# long deck, a wall at the end of it, a fixed anchor, and things of three different
# weights to catch (brief §39).
#
# Everything is built in code and is deterministic, like MovementLane and
# WindProps — ART may replace the meshes, but three things must survive, because
# they are the stage's whole function:
#
#   the WALL        a throw that hits nothing costs the spin, and that only exists
#                   if there is something solid to hit
#   the ANCHOR      hooking something fixed is how §20's tension is reachable
#   three WEIGHTS   light / medium / heavy standing in one place is the only way
#                   to see the weight table behave differently in one shot
#
# The deck's TOP FACE IS AT y = 0 while the arena's floor mesh tops out at 0.25 —
# a quarter of a metre, under a third of an enemy's hurtbox height, so a height in
# the chain's data still reaches the same thing in both rooms. Keeping the deck at
# 0 also keeps the bridge flush with it: a 0.25 lip at the join is taller than
# move_and_slide steps, and the deck would be reachable only by teleport.

const CENTER := Vector3(0.0, 0.0, -31.0)
const DECK_SIZE := Vector3(28.0, 0.9, 24.0)
const DECK_TINT := Color(0.29, 0.30, 0.33)
const KERB_TINT := Color(0.18, 0.19, 0.22)
const MARK_TINT := Color(0.55, 0.53, 0.46)
const INTERVAL_TINT := Color(0.72, 0.45, 0.30)
const MARK_STEP := 2.0
const KERB_HEIGHT := 0.55

# The wall a throw is meant to end on, and the bridge back to the arena.
const WALL_Z := -42.6
const WALL_HEIGHT := 3.4
const BRIDGE_WIDTH := 4.0
const BRIDGE_FROM_Z := -12.0

const ENTRY := Vector3(0.0, 0.9, -22.0)
const ANCHOR_POSITION := Vector3(6.5, 0.0, -26.0)
const CRATE_STARTS: Array[Vector3] = [
	Vector3(4.0, 0.5, -23.6),
	Vector3(4.9, 0.5, -24.7),
	Vector3(3.3, 1.4, -24.2),
]

const DUMMY_SCENE := preload("res://scenes/enemies/TechnicalDummy.tscn")

# Three weights, at three distances, all inside one throw of each other. This is
# the layout that makes the weight table's argument visible: the same hook, the
# same pull, three different outcomes.
const SLOTS: Array[Dictionary] = [
	{"weight": ElementLibrary.WEIGHT_LIGHT, "position": Vector3(-2.4, 0.0, -25.4)},
	{"weight": ElementLibrary.WEIGHT_MEDIUM, "position": Vector3(0.6, 0.0, -26.4)},
	{"weight": ElementLibrary.WEIGHT_HEAVY, "position": Vector3(-0.4, 0.0, -29.2)},
]

var targets: Array[Node3D] = []
var anchor: ChainAnchor
var crates: Array[ChainCrate] = []


func _ready() -> void:
	_deck()
	_kerbs()
	_markings()
	_bridge()
	_wall()
	_anchor()
	_crates()
	_spawn_targets()
	_clear_overlapping_dressing()


func entry_position() -> Vector3:
	return ENTRY


func slot_position(weight: StringName) -> Vector3:
	for slot in SLOTS:
		if slot["weight"] == weight:
			return slot["position"]
	return ENTRY


func target_for(weight: StringName) -> Node3D:
	for target in targets:
		if is_instance_valid(target) and target.call("weight_class") == weight:
			return target
	return null


func reset() -> void:
	# Back to the starting picture. Rigid bodies do not restore themselves, and a
	# take that begins with the crates already thrown across the room is measuring
	# the previous take.
	for i in crates.size():
		if is_instance_valid(crates[i]):
			crates[i].freeze = true
			crates[i].global_position = CRATE_STARTS[i] if i < CRATE_STARTS.size() else CENTER
			crates[i].linear_velocity = Vector3.ZERO
			crates[i].angular_velocity = Vector3.ZERO
			crates[i].freeze = false
	for target in targets:
		if is_instance_valid(target):
			target.call("reset_dummy")


func _material(tint: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = tint
	material.roughness = 0.94
	return material


func _solid(size: Vector3, tint: Color, pos: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = pos
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
	return body


func _flat(size: Vector3, tint: Color, pos: Vector3) -> void:
	# Paint, not geometry: a marking that caught a footstep would be a bug.
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = _material(tint)
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh.position = pos
	add_child(mesh)


func _deck() -> void:
	# Top face at y = 0: the chain's heights are authored relative to the floor the
	# player stands on, so the lab and the arena have to agree about where that is.
	_solid(DECK_SIZE, DECK_TINT, CENTER + Vector3(0.0, -DECK_SIZE.y * 0.5, 0.0))


func _kerbs() -> void:
	var half_x := DECK_SIZE.x * 0.5 - 0.15
	var half_z := DECK_SIZE.z * 0.5 - 0.15
	for side in [-1.0, 1.0]:
		_solid(
			Vector3(0.3, KERB_HEIGHT, DECK_SIZE.z),
			KERB_TINT,
			CENTER + Vector3(side * half_x, KERB_HEIGHT * 0.5, 0.0)
		)
	# THE NEAR END HAS A DOORWAY, NOT A KERB. The bridge lands on this edge, and a
	# 0.55m kerb across the join is taller than a step — so a full-width kerb here
	# makes the whole deck reachable only by teleport, which is exactly the failure
	# the movement lane's ramp had. Two segments flank a BRIDGE_WIDTH gap instead,
	# so the ground still states "the deck ends here" everywhere the deck does end.
	var opening := BRIDGE_WIDTH + 0.8
	var segment := (DECK_SIZE.x - opening) * 0.5
	for side in [-1.0, 1.0]:
		_solid(
			Vector3(segment, KERB_HEIGHT, 0.3),
			KERB_TINT,
			CENTER + Vector3(
				side * (opening * 0.5 + segment * 0.5), KERB_HEIGHT * 0.5, half_z
			)
		)
	# The far end needs no kerb: the wall stands there, full width and 3.4 tall.


func _markings() -> void:
	# The ground states the distance, so "it reached the end of the chain" is a
	# thing a viewer can check instead of take on faith.
	var count := int(DECK_SIZE.z / MARK_STEP)
	var start_z := CENTER.z - DECK_SIZE.z * 0.5 + MARK_STEP
	for i in range(count):
		var z := start_z + float(i) * MARK_STEP
		var interval := i % 4 == 0
		_flat(
			Vector3(DECK_SIZE.x - 1.2, 0.03, 0.16 if interval else 0.09),
			INTERVAL_TINT if interval else MARK_TINT,
			Vector3(CENTER.x, 0.02, z)
		)


func _bridge() -> void:
	# A way over on foot, so this is part of the world rather than a pocket only a
	# teleport reaches. The arena floor ends at z = -12 and the lab starts at z = -19.
	var length := absf(BRIDGE_FROM_Z - (CENTER.z + DECK_SIZE.z * 0.5))
	var middle := (BRIDGE_FROM_Z + (CENTER.z + DECK_SIZE.z * 0.5)) * 0.5
	_solid(
		Vector3(BRIDGE_WIDTH, 0.6, length),
		DECK_TINT,
		Vector3(0.0, -0.3, middle)
	)


func _wall() -> void:
	# THE THING A THROW ENDS ON. Without it, momentum loss on impact does not exist
	# and the chain has no reason to respect space (§21).
	_solid(
		Vector3(DECK_SIZE.x, WALL_HEIGHT, 0.7),
		Color(0.24, 0.25, 0.28),
		Vector3(CENTER.x, WALL_HEIGHT * 0.5, WALL_Z)
	)


func _anchor() -> void:
	# A FIXED POINT (§20). Made of the same contract an enemy is: it says it is
	# heavy, so the chain moves the player instead of the pillar — no anchor-
	# specific code anywhere in the weapon.
	anchor = ChainAnchor.new()
	anchor.name = "ChainAnchor"
	anchor.radius = 0.6
	anchor.height = 4.4
	anchor.position = ANCHOR_POSITION
	add_child(anchor)


func _crates() -> void:
	for i in CRATE_STARTS.size():
		var crate := ChainCrate.new()
		crate.name = "Crate%d" % i
		crate.position = CRATE_STARTS[i]
		add_child(crate)
		crates.append(crate)


func _spawn_targets() -> void:
	# Three weights standing in one room. They live HERE rather than in the sandbox
	# because a stage owning its own enemies is what makes the weight table's
	# argument visible in a single glance — and the dummy finds the player through
	# the player's group, so it does not care whose child it is.
	for slot in SLOTS:
		var dummy := DUMMY_SCENE.instantiate() as Node3D
		dummy.name = "Target_%s" % String(slot["weight"])
		dummy.set("weight", slot["weight"])
		add_child(dummy)
		dummy.global_position = slot["position"]
		dummy.rotation.y = 0.0
		targets.append(dummy)


# THE ROOM CANNOT CONTAIN THE OTHER ROOM'S RUBBLE.
#
# ArenaDressing predates this stage and scatters 39 placeholder pieces across
# z = -3..-22 without knowing the deck is here, so eight of them land inside it —
# including two four-metre pillars, one of which stands square in the bridge
# doorway. They have no collision, so this is a framing problem rather than a
# movement one, but a stage with someone else's rubble standing in the middle of it
# is not a stage, and every one of these shows up in a 4.6m sweep.
#
# Hiding rather than deleting: both rooms are deterministic placeholders ART is
# going to replace wholesale, so nothing is lost by suppressing the overlap now —
# and if the lab ever moves, the dressing is still complete underneath.
func _clear_overlapping_dressing() -> void:
	var parent := get_parent()
	if parent == null:
		return
	var dressing := parent.get_node_or_null("ArenaDressing")
	if dressing == null:
		return
	# A tall column over the deck plus the bridge corridor, both grown sideways so
	# a piece that merely leans over the edge is caught too.
	const pad := 0.5
	const COLUMN_HEIGHT := 12.0
	var deck_min := CENTER - DECK_SIZE * 0.5
	var deck := AABB(
		Vector3(deck_min.x - pad, 0.0, deck_min.z - pad),
		Vector3(DECK_SIZE.x + pad * 2.0, COLUMN_HEIGHT, DECK_SIZE.z + pad * 2.0)
	)
	var deck_near_z := CENTER.z + DECK_SIZE.z * 0.5
	var bridge := AABB(
		Vector3(-(BRIDGE_WIDTH * 0.5 + pad), 0.0, BRIDGE_FROM_Z),
		Vector3(BRIDGE_WIDTH + pad * 2.0, COLUMN_HEIGHT, absf(BRIDGE_FROM_Z - deck_near_z))
	)
	var hidden := 0
	for child in dressing.get_children():
		var mesh_node := child as MeshInstance3D
		if mesh_node == null or mesh_node.mesh == null:
			continue
		# Ask the MESH for its box and transform it, rather than reading
		# VisualInstance3D.get_aabb(): that one is filled in by the renderer and
		# stays empty in a headless run, so the same code would hide the pillars in
		# the video and miss them in the test that is supposed to prove it does.
		var box := mesh_node.global_transform * mesh_node.mesh.get_aabb()
		if deck.intersects(box) or bridge.intersects(box):
			mesh_node.visible = false
			hidden += 1
	if hidden > 0:
		print("ChainLab: hid %d ArenaDressing placeholder(s) inside the deck/bridge footprint" % hidden)
