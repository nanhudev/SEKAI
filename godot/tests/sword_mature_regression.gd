extends SceneTree
var failures: Array[String] = []
func _initialize() -> void: call_deferred("run")
func frames(count:int) -> void:
	for i in count: await physics_frame
func check(ok:bool,message:String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)
func run() -> void:
	var world:Node3D = load("res://scenes/training/TrainingGround.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	await frames(12)
	var player:CharacterBody3D = world.get_node("Player")
	player.set_process_unhandled_input(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	player.position = Vector3(12,0.9,-25)
	for actor in get_nodes_in_group(&"hostiles"):
		actor.set_process(false)
		actor.set_physics_process(false)
		var hurt := actor.get_node_or_null("Hurtbox")
		if hurt is CombatHurtbox: hurt.monitorable = false
	var combat:CombatController = player.get_node("CombatController")
	var hands:Node3D = player.find_child("SwordHandPresentation",true,false)
	var sword:Node3D = hands.get_parent()
	await frames(20)
	var started := combat.combat_time
	check(combat.request(&"light"),"First cut must start promptly")
	check(combat.active_move.events.all(func(e:Dictionary):return e.id!=SwordBasic.EV_DRAW and e.id!=SwordBasic.EV_SHEATH_TOUCH),"Ordinary A1 must remain drawn")
	while combat.state_time<combat.effective_startup()+0.025: await frames(1)
	combat.request(&"light")
	check(combat.buffer.pending==&"light","Committed next-cut press must be remembered")
	var worst_grip := 0.0
	var guard := 0
	while combat.active_move_id!=SwordBasic.A2 and guard<60:
		await frames(1)
		guard += 1
		worst_grip = maxf(worst_grip,hands.left.position.distance_to(Vector3(0,-0.19,0)))
	check(combat.active_move_id==SwordBasic.A2,"Queued cut must execute at the existing link gate")
	var link_delay := combat.combat_time-started
	check(link_delay<0.5,"A queued combo must not wait for the full recovery")
	await frames(8)
	worst_grip = maxf(worst_grip,hands.left.position.distance_to(Vector3(0,-0.19,0)))
	check(worst_grip<0.0001,"Offhand must remain on the grip during fast cuts")
	var dummy:Node3D = load("res://scenes/enemies/TechnicalDummy.tscn").instantiate()
	world.add_child(dummy)
	dummy.set_process(false)
	dummy.set_physics_process(false)
	dummy.position = Vector3(12,0.1,-27)
	combat._begin_move(SwordBasic.a1(),CombatController.State.ATTACK)
	var holds:Array[float] = []
	for surface in ["body","metal","stone"]:
		for group in ["body","metal","stone"]: dummy.remove_from_group("surface_"+group)
		dummy.add_to_group("surface_"+surface)
		sword._have_tip = true
		sword._travel_step = Vector3(0.03,0.02,-0.01)
		sword._tip_speed = 6.0
		sword._on_sword_hit(combat.active_move,{"target":dummy})
		holds.append(sword._contact_hold_left)
	check(holds[0]<holds[1] and holds[1]<holds[2],"Metal and stone must resist more than flesh")
	combat._begin_move(SwordBasic.a2(),CombatController.State.ATTACK)
	dummy.position.z = -35
	sword._contact_hold_left = 0.0
	var velocity_before:float = sword._contact_vel
	sword._on_sword_hit(combat.active_move,{"target":dummy})
	check(is_zero_approx(sword._contact_hold_left) and is_equal_approx(velocity_before,sword._contact_vel),"Remote wave contact must not bend the held blade")
	combat.finish_action()
	combat.request(&"heavy")
	await frames(20)
	var loaded:Dictionary = combat.pose_snapshot()
	combat.release_heavy()
	var released:Dictionary = combat.pose_snapshot()
	check(combat.authored_move_time()>=combat.active_move.startup,"Held heavy release must start at the strike rather than replaying startup")
	check((loaded.position as Vector3).distance_to(released.position)<0.03,"Heavy release must preserve the loaded hand position")
	print("MATURE_METRICS link_delay=",link_delay," grip_error=",worst_grip," material_holds=",holds," heavy_release_jump=",(loaded.position as Vector3).distance_to(released.position))
	combat.stow()
	world.queue_free()
	await frames(10)
	print("PASS: mature sword combo buffering, exact grip, contact resistance and heavy clock" if failures.is_empty() else str(failures))
	quit(0 if failures.is_empty() else 1)
