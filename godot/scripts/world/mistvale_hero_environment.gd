@tool
extends Node3D

# Four composed landmarks and a short, readable riverbank beside the main bridge.
# All placements use the authoritative height field; this layer changes no terrain
# or collision and can be removed without affecting the traversal baseline.
const KIT := "res://models/environment/mistvale/vegetation_v3/"
const FOUNDATION := "res://models/environment/mistvale/foundation_v2/"
const GROUND_MASTER := "res://resources/shaders/mistvale_ground_master_v2.gdshader"
var _foundation_rock_material: ShaderMaterial

func _ready() -> void:
	if Engine.is_editor_hint():
		return
	_build_landmarks()
	_build_bank()
	_build_bank_v2()


func _build_landmarks() -> void:
	# River bend, bridge frame, town approach, distant guild direction.
	_place("RiverTree_A", Vector2(62.0, 163.0), 1.18, -0.75, "A_RiverBend")
	_place("Broadleaf_C", Vector2(-17.0, 161.0), 1.25, 1.4, "B_BridgeHead")
	_place("Broadleaf_A", Vector2(-58.0, 102.0), 1.42, -0.3, "C_TownEntry")
	_place("Broadleaf_B", Vector2(-82.0, 38.0), 1.35, 0.95, "D_GuildVista")
	_place_foundation("MV_RiverCluster_B", Vector2(68.0, 164.0), 0.95, 0.4, "Rock_RiverBend")
	_place_foundation("MV_RiverCluster_A", Vector2(-18.0, 164.0), 1.0, 1.2, "Rock_BridgeApproach")
	_place("HeroRock_B", Vector2(-65.0, 87.0), 1.22, -0.6, "Rock_TownReveal")


func _place(asset: String, p: Vector2, scale_: float, yaw: float, label: String) -> void:
	var packed := load(KIT + asset + ".glb") as PackedScene
	if packed == null:
		push_warning("Hero environment missing: " + asset)
		return
	var node := packed.instantiate() as Node3D
	if node == null:
		return
	node.name = label
	node.position = Vector3(p.x, MistvaleHeights.height_at(p.x, p.y) - 0.12, p.y)
	node.rotation.y = yaw
	node.scale = Vector3.ONE * scale_
	add_child(node)
	if label == "Rock_TownReveal":
		# This steep-bank outcrop projected a near-black strip across the lower
		# town approach. It remains as a silhouette but does not shadow the road.
		var pending: Array[Node] = [node]
		while not pending.is_empty():
			var child: Node = pending.pop_back()
			if child is GeometryInstance3D:
				(child as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			for nested in child.get_children():
				pending.append(nested)


func _build_bank() -> void:
	# A 50 m bridge reach: sparse stones at the water edge and sedges set back
	# on dry ground. The varying band comes from actual terrain height.
	var stone := SphereMesh.new()
	stone.radial_segments = 7
	stone.rings = 3
	stone.radius = 0.34
	stone.height = 0.28
	var stone_mat := StandardMaterial3D.new()
	stone_mat.albedo_color = Color(0.42, 0.44, 0.43)
	stone_mat.roughness = 0.96
	stone.material = stone_mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = stone
	var stones: Array[Transform3D] = []
	for i in 52:
		var x := -27.0 + float(i) * 1.08
		var center := MistvaleHeights.river_center_z(x)
		for side in [-1.0, 1.0]:
			if i % 3 == 0:
				continue
			var offset := 13.8 + float((i * 7) % 13) * 0.45
			var z: float = center + float(side) * offset
			var y := MistvaleHeights.height_at(x, z)
			if y < MistvaleHeights.RIVER_Y - 0.05 or y > MistvaleHeights.RIVER_Y + 2.5:
				continue
			if MistvaleHeights.path_distance(x, z) < 4.8:
				continue
			var size := 0.60 + float((i * 11) % 9) * 0.085
			var t := Transform3D(Basis().scaled(Vector3(size * 1.6, size * 0.7, size)), Vector3(x, y + 0.04, z))
			stones.append(t)
	mm.instance_count = stones.size()
	for i in stones.size():
		mm.set_instance_transform(i, stones[i])
	var instance := MultiMeshInstance3D.new()
	instance.name = "ShoreStoneClusters_50m"
	instance.multimesh = mm
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)
	# A few deliberate plant groups mark the transition to the higher bank.
	for i in 12:
		var x := -23.0 + float(i) * 4.1
		var z := MistvaleHeights.river_center_z(x) + (1.0 if i % 2 == 0 else -1.0) * (20.0 + float(i % 3) * 2.0)
		var y := MistvaleHeights.height_at(x, z)
		if y > MistvaleHeights.RIVER_Y + 0.25 and MistvaleHeights.path_distance(x, z) > 5.5:
			_place("RiverGrass_A", Vector2(x, z), 1.6 + float(i % 3) * 0.15, float(i) * 1.8, "Sedge_%02d" % i)


func _place_foundation(asset: String, p: Vector2, scale_: float, yaw: float, label: String,
		sink: float = 0.10) -> void:
	var scene := load(FOUNDATION + asset + ".glb") as PackedScene
	if scene == null:
		push_warning("Foundation rock missing: " + asset)
		return
	var node := scene.instantiate() as Node3D
	node.name = label
	node.position = Vector3(p.x, MistvaleHeights.height_at(p.x, p.y) - sink, p.y)
	node.rotation.y = yaw
	node.scale = Vector3.ONE * scale_
	add_child(node)
	if _foundation_rock_material == null:
		_foundation_rock_material = _ground_variant(Color(0.42, 0.41, 0.37),
			Color(0.51, 0.49, 0.43), 0.90, 0.12, 1.30)
	# Shallow rocks generated a huge black bank shadow at this sun angle.
	var pending: Array[Node] = [node]
	while not pending.is_empty():
		var current: Node = pending.pop_back()
		if current is GeometryInstance3D:
			(current as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			(current as GeometryInstance3D).material_override = _foundation_rock_material
		for child in current.get_children():
			pending.append(child)


func _ground_variant(a: Color, b: Color, rough: float, patch: float, grain: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load(GROUND_MASTER) as Shader
	m.set_shader_parameter("base_color", a)
	m.set_shader_parameter("secondary_color", b)
	m.set_shader_parameter("roughness", rough)
	m.set_shader_parameter("patch_scale", patch)
	m.set_shader_parameter("grain_scale", grain)
	return m


func _build_bank_v2() -> void:
	# A sparse authored 90 m bridge reach. The existing terrain material owns
	# the wet/gravel transition; stone clusters establish the larger bank rhythm.
	for i in 17:
		var x := -43.0 + float(i) * 5.4
		for side in [-1.0, 1.0]:
			if i % 2 == 0 or i % 5 == 0:
				continue
			var offset := 16.4 + float((i * 7) % 7) * 0.88
			var z: float = MistvaleHeights.river_center_z(x) + side * offset
			if MistvaleHeights.path_distance(x, z) < 6.0:
				continue
			var asset: String = ["MV_RiverRock_M", "MV_RiverCluster_A", "MV_RiverRock_L", "MV_RiverCluster_B"][i % 4]
			_place_foundation(asset, Vector2(x, z), 0.72 + 0.10 * float(i % 3),
				float(i) * 1.83 + side, "BankRock_%02d_%d" % [i, int(side)])

