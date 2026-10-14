extends SceneTree
var failures: Array[String] = []
var steel_surfaces := 0
func _initialize() -> void:
	call_deferred("run")
func check(ok:bool,message:String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)
func frames(count:int) -> void:
	for i in count: await physics_frame
func scan(node:Node) -> void:
	if node is MeshInstance3D and node.mesh != null:
		for i in node.mesh.get_surface_count():
			var material = node.mesh.surface_get_material(i)
			if material is ShaderMaterial and material.shader.resource_path.ends_with("sword_steel_life.gdshader"):
				steel_surfaces += 1
	for child in node.get_children(): scan(child)
func run() -> void:
	var world:Node3D = load("res://scenes/training/TrainingGround.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	await frames(12)
	var player:CharacterBody3D = world.get_node("Player")
	player.position = Vector3(12,0.9,-25)
	for actor in get_nodes_in_group(&"hostiles"):
		actor.set_process(false)
		actor.set_physics_process(false)
	var combat:CombatController = player.get_node("CombatController")
	var hands:Node3D = player.find_child("SwordHandPresentation",true,false)
	var sword:Node3D = hands.get_parent()
	await frames(20)
	var position_a:Vector3 = sword.position
	var fingers_a:Vector3 = hands.right.get_node("Fingers").scale
	await frames(65)
	var movement:float = sword.position.distance_to(position_a)
	check(movement>0.0001 and movement<0.025,"Idle must move subtly rather than freeze or sway widely")
	check(not fingers_a.is_equal_approx(hands.right.get_node("Fingers").scale),"Idle grip animation must advance")
	scan(sword)
	check(steel_surfaces>=3,"Existing blade faces must use directional steel finish")
	var dummy:Node3D = load("res://scenes/enemies/TechnicalDummy.tscn").instantiate()
	world.add_child(dummy)
	dummy.set_process(false)
	dummy.set_physics_process(false)
	dummy.position = Vector3(12,0.1,-35)
	var before:float = dummy.health
	combat._begin_move(SwordBasic.a3(),CombatController.State.ATTACK)
	await frames(65)
	check(is_equal_approx(dummy.health,before),"A3 uppercut must not retain remote spatial damage")
	var bank = JSON.parse_string(FileAccess.get_file_as_string("res://audio/sfx/weapons/sword/feel_v2/manifest.json"))
	check(bank is Array and bank.size()==14,"Fourteen generated SFX must be installed")
	if bank is Array:
		for row in bank:
			var stream:AudioStream = load(String(row.dir)+String(row.file))
			check(stream!=null and stream.get_length()>0.10,"Generated sound cannot be missing or empty: "+String(row.id))
			check(float(row.peak)<-5.9,"Generated sound must retain peak headroom")
	var director:IaidoDirector = world.get_node("IaidoDirector")
	director.audio_timeline.configure(director.combat_tuning,true)
	check(director.audio_timeline.cues.size()==8,"Combat Iaido must use the restrained generated timeline")
	check(director.audio_timeline.players[&"draw"].stream.resource_path.contains("feel_v2"),"Iaido draw must use the new real material identity")
	print("FEEL_V2_METRICS idle_motion_m=",movement," steel_surfaces=",steel_surfaces," far_A3_damage=",before-dummy.health)
	combat.stow()
	world.queue_free()
	await frames(10)
	print("PASS: Sword Feel V2 idle, grip, material, range and generated bank" if failures.is_empty() else str(failures))
	quit(0 if failures.is_empty() else 1)

