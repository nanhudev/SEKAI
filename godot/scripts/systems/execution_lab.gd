extends Node3D
class_name ExecutionLab

# 聚合斩 · EXECUTION LAB — a stage for one question the arena cannot answer.
#
# WHY IT EXISTS: the arena has exactly one target, and the execution system's
# whole point is that DIFFERENT BODIES FAIL DIFFERENTLY. One construct cannot
# tell you whether "a biological reads as restrained and a construct reads as a
# machine" is true, whether a heavy body falls at a different speed, or whether
# three enemies killed by one slash come apart like three enemies or like a
# copy-and-paste. §T of the brief asks for at least three targets for exactly
# that reason, and this is the smallest stage that can hold them.
#
# THREE MATERIAL FAMILIES, THREE WEIGHTS, ONE SLASH:
#
#   BIOLOGICAL   the restrained cross-section. No light inside, no gore. This is
#                the one that decides whether the default reads as tasteful.
#   CONSTRUCT    stone, aged metal, and a core that was still running — the
#                Lessar Ruin Sentinel's answer, and the game's most likely enemy.
#   HEAVY        the same material with three times the body. Gravity is scaled
#                down and the fall runs longer: mass is supposed to be legible
#                from how something loses its argument with the ground.
#
# Built in code and deterministic, like MovementLane / WindProps / ChainLab. ART
# may replace every mesh here; what must survive is the SHAPE OF THE LINE — three
# bodies of different material, inside one 45° cone, close enough to be killed by
# a single slash.

const CENTER := Vector3(0.0, 0.0, -66.0)
const ENTRY_OFFSET := Vector3(0.0, 0.9, 6.0)
const FLOOR_SIZE := Vector3(24.0, 0.5, 22.0)
# 7.0m from the entry, and the whole line is 4.8m wide: measured against the real
# targeting numbers (`iaido_range` 10, `iaido_cone_degrees` 45) so that ONE slash
# can legitimately catch all three — which is the only way §P can be reviewed.
const SPAWN_Z := -1.0
const SPACING := 2.4

var targets: Array[Node3D] = []
var labels: Array[Label3D] = []
var _defs: Array[Dictionary] = []


func _ready() -> void:
	_build_stage()
	_build_targets()


func entry_position() -> Vector3:
	return CENTER + ENTRY_OFFSET


func _build_stage() -> void:
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color(0.30, 0.30, 0.32)
	floor_material.roughness = 1.0

	var mesh := BoxMesh.new()
	mesh.size = FLOOR_SIZE
	mesh.material = floor_material

	var shape := BoxShape3D.new()
	shape.size = FLOOR_SIZE

	var body := StaticBody3D.new()
	body.name = "LabFloor"
	var surface := MeshInstance3D.new()
	surface.mesh = mesh
	# NEVER cast a shadow from a ground plate: see the height-field acne note in
	# the rendering rules — a lit ground plane that shadows itself goes black.
	surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(surface)
	var collider := CollisionShape3D.new()
	collider.shape = shape
	body.add_child(collider)
	body.position = CENTER + Vector3(0.0, -FLOOR_SIZE.y * 0.5, 0.0)
	add_child(body)

	# The line the three bodies stand on, so "was the cut plane the same slash for
	# all of them" can be read off the floor and not only off the bodies.
	var mark := BoxMesh.new()
	mark.size = Vector3(SPACING * 2.0 + 2.6, 0.02, 0.06)
	var mark_material := StandardMaterial3D.new()
	mark_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mark_material.albedo_color = Color(0.62, 0.58, 0.50)
	mark.material = mark_material
	var ruler := MeshInstance3D.new()
	ruler.mesh = mark
	ruler.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ruler.position = CENTER + Vector3(0.0, 0.012, SPAWN_Z)
	add_child(ruler)


func _build_targets() -> void:
	# HEALTH IS CHOSEN SO ONE SLASH CAN KILL ALL THREE. `execution_damage_splash`
	# is 120, and if a body survives the splash then a multi-kill test can only
	# ever find two executions — the third would be a deep slash, and §P would go
	# unexercised. Weight is expressed by SCALE and by the weight class, not by a
	# health bar: 重量不是血量 is the same rule the element layer already follows.
	_defs = [
		{
			"name": "BIOLOGICAL",
			"profile": IaidoExecutionLibrary.biological(),
			"slot": -1,
			"scale": 1.0,
			"health": 90.0,
			"weight": ElementLibrary.WEIGHT_LIGHT,
		},
		{
			"name": "CONSTRUCT",
			"profile": IaidoExecutionLibrary.construct(),
			"slot": 0,
			"scale": 1.05,
			"health": 100.0,
			"weight": ElementLibrary.WEIGHT_MEDIUM,
		},
		{
			"name": "HEAVY",
			"profile": IaidoExecutionLibrary.heavy(),
			"slot": 1,
			"scale": 1.55,
			"health": 110.0,
			"weight": ElementLibrary.WEIGHT_HEAVY,
		},
	]
	var scene: PackedScene = load("res://scenes/enemies/TechnicalDummy.tscn")
	for def in _defs:
		var body := scene.instantiate() as Node3D
		body.name = String(def["name"])
		# BEFORE `_ready()`: a dummy enters play with `health = max_health`, so a
		# heavier body has to be told its health while it is still an instance.
		body.set("max_health", float(def["health"]))
		body.set("weight", def["weight"])
		body.set("execution_profile", def["profile"])
		add_child(body)
		body.scale = Vector3.ONE * float(def["scale"])
		body.global_position = CENTER + Vector3(float(def["slot"]) * SPACING, 0.0, SPAWN_Z)
		body.rotation.y = 0.0
		targets.append(body)
		_add_label(body, def)


func _add_label(body: Node3D, def: Dictionary) -> void:
	var label := Label3D.new()
	label.text = "%s\n%s" % [String(def["name"]), String(def["profile"].cut_material)]
	label.font_size = 64
	label.pixel_size = 0.006
	label.modulate = Color(0.86, 0.86, 0.84)
	label.outline_size = 12
	label.outline_modulate = Color(0.05, 0.06, 0.08, 0.9)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = false
	label.position = Vector3(0.0, 2.35, 0.0)
	body.add_child(label)
	labels.append(label)


## Put the three bodies back on their feet, whatever the last experiment did to
## them. The profiles are re-stamped so a test that retuned one in memory cannot
## leak into the next run.
func reset() -> void:
	for i in targets.size():
		var body := targets[i]
		if not is_instance_valid(body):
			continue
		body.call("reset_dummy")
		body.set("execution_profile", _defs[i]["profile"])
		body.global_position = CENTER + Vector3(float(_defs[i]["slot"]) * SPACING, 0.0, SPAWN_Z)


func set_labels_visible(shown: bool) -> void:
	for label in labels:
		if is_instance_valid(label):
			label.visible = shown
