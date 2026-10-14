extends Node3D

const MAP_ROOT := "res://models/starter_village/v078/"
const WATER := preload("res://resources/shaders/starter_village_water.gdshader")
var water_materials: Array[ShaderMaterial] = []
var flow_time := 0.0
var route: Array = []
var spawn_position := Vector3.ZERO
var ready_for_exploration := false

func _ready() -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MAP_ROOT + "map_manifest.json"))
	route = manifest["route"]
	var art := (load(MAP_ROOT + "starter_village.glb") as PackedScene).instantiate()
	art.name = "Art";add_child(art)
	add_child((load(MAP_ROOT + "collision.scn") as PackedScene).instantiate())
	_install_water(art)
	$Player.set_physics_process(false)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var start := Vector3(route[0][0], route[0][1], route[0][2])
	var next := Vector3(route[1][0], route[1][1], route[1][2])
	start = start.move_toward(next, 4.0)
	var hit := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(start + Vector3.UP * 8.0, start - Vector3.UP * 8.0))
	assert(not hit.is_empty(), "No village entrance collision")
	spawn_position = hit["position"] + Vector3.UP * 1.05
	$Player.global_position = spawn_position
	$Player.rotation.y = atan2(-(next.x-start.x), -(next.z-start.z))
	$Player.set_physics_process(true)
	ready_for_exploration = true

func _install_water(art: Node) -> void:
	var pending: Array[Node] = [art]
	while not pending.is_empty():
		var n: Node = pending.pop_back()
		for child in n.get_children():pending.append(child)
		if not n is MeshInstance3D:continue
		var mesh_node := n as MeshInstance3D
		for index in mesh_node.mesh.get_surface_count():
			var original := mesh_node.get_active_material(index)
			if original == null:continue
			var label := original.resource_name
			if label in ["MV_Valley_Water_Prototype", "MV_Valley_FallingWater"]:
				var mat := ShaderMaterial.new();mat.shader = WATER
				mat.set_shader_parameter("falling_water", label == "MV_Valley_FallingWater")
				mesh_node.set_surface_override_material(index, mat);water_materials.append(mat)

func _process(delta: float) -> void:
	flow_time += delta
	for mat in water_materials:mat.set_shader_parameter("flow_time", flow_time)
	if ready_for_exploration and $Player.global_position.y < -15.0:
		$Player.global_position = spawn_position
		$Player.velocity = Vector3.ZERO
