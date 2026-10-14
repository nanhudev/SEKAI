extends SceneTree
# Continuous TrainingGround replay. User actions enter actual input handlers.
# Marked fixture resets reposition the test target/player; not human play footage.
var world: Node3D
var player: CharacterBody3D
var combat: CombatController
var manager: Node
var dummy: Node3D
var label: Label
var clock := 0.0
var running := false
var index := 0
var receipts: Array = []
var sequence: Array = []
var pending: Array[String] = []
var output := "E:/SEKAI-SwordUpgrade-20261012"

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	call_deferred("boot")

func boot() -> void:
	world = load("res://scenes/training/TrainingGround.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	for i in 16:
		await physics_frame
	player = world.get_node("Player")
	combat = player.get_node("CombatController")
	manager = player.get_node("WeaponManager")
	for actor in get_nodes_in_group(&"hostiles"):
		actor.set_process(false)
		actor.set_physics_process(false)
		var hurt := actor.get_node_or_null("Hurtbox")
		if hurt != null:
			hurt.monitorable = false
	dummy = load("res://scenes/enemies/TechnicalDummy.tscn").instantiate()
	dummy.name = "SwordAcceptanceTarget"
	world.add_child(dummy)
	dummy.max_health = 10000.0
	dummy.health = 10000.0
	dummy.collision_layer = 1
	dummy.attack_cooldown = 99.0
	dummy.set_process(false)
	dummy.set_physics_process(false)
	station(2.4)
	for node_name in ["DeveloperPanel","ParryDebugOverlay","CombatHUD","TrainingUI"]:
		var node := world.get_node_or_null(node_name)
		if node != null:
			node.set("visible",false)
	manager.get_node("WeaponIndicator").visible = false
	player.get_node("ChainDirector").debug_readout = false
	hide_legends(world)
	var overlay := CanvasLayer.new()
	root.add_child(overlay)
	label = Label.new()
	label.position = Vector2(22,20)
	label.add_theme_font_size_override("font_size",22)
	label.add_theme_color_override("font_shadow_color",Color.BLACK)
	label.add_theme_constant_override("shadow_offset_x",2)
	label.add_theme_constant_override("shadow_offset_y",2)
	overlay.add_child(label)
	combat.move_started.connect(func(move:SwordMove): receipts.append({"time":clock,"move":String(move.id)}))
	combat.state_changed.connect(func(_previous: int,state: int): receipts.append({"time":clock,"state_name":CombatController.State.keys()[state]}))
	combat.sword_vfx.weapon_event.connect(func(event:StringName,payload:Dictionary): receipts.append({"time":clock,"event":String(event),"payload":payload}))
	world.get_node("IaidoDirector").phase_changed.connect(func(phase:StringName): receipts.append({"time":clock,"phase":String(phase)}))
	combat.perfect_guard_landed.connect(func(): pending.append("parry"))
	sequence = [
		[0.0,"title","SWORD / scripted input review in TrainingGround"],[0.15,"putaway",0],
		[2.2,"title","01 / DRAW SWORD"],[2.3,"equip",0],[3.4,"still","draw"],
		[4.5,"title","02 / A1 - A2 - A3 RISING FINISH - A4 MAJOR ARC"],
		[4.7,"light_attack",true],[4.8,"light_attack",false],[5.3,"light_attack",true],[5.4,"light_attack",false],
		[5.9,"light_attack",true],[6.0,"light_attack",false],[7.5,"light_attack",true],[7.6,"light_attack",false],
		[7.65,"still","a4"],
		[9.0,"title","03 / SECOND COMBO / fixture reset"],[9.1,"station",2.4],
		[9.5,"light_attack",true],[9.6,"light_attack",false],[10.1,"light_attack",true],[10.2,"light_attack",false],
		[10.7,"light_attack",true],[10.8,"light_attack",false],[12.3,"light_attack",true],[12.4,"light_attack",false],
		[13.6,"title","04 / DODGE INTO ATTACK"],[13.7,"dodge_sprint",true],[13.8,"dodge_sprint",false],[14.15,"light_attack",true],[14.25,"light_attack",false],
		[15.7,"title","05 / PERFECT GUARD + COUNTER / fixture reset"],[15.8,"station",2.1],[16.1,"enemy",0],
		[16.43,"block",true],[16.62,"block",false],[16.68,"light_attack",true],[16.78,"light_attack",false],
		[18.3,"title","SWORD PRESSURE / MID RANGE / fixture reset"],[18.4,"station",6.0],[18.7,"style_skill_1",true],[18.8,"style_skill_1",false],
		[20.0,"title","SWORD STEP / fixture reset"],[20.1,"station",2.4],[20.4,"style_skill_2",true],[20.5,"style_skill_2",false],
		[22.0,"title","06 / COMBAT IAIDO / 2.75 SECONDS / fixture reset"],[22.1,"station",3.2],[22.4,"skill_1",true],[22.5,"skill_1",false],
		[23.38,"still","iaido_split"],[24.55,"still","iaido_sheath"],
		[25.5,"title","07 / CONTINUE FIGHTING AFTER IAIDO"],[25.6,"light_attack",true],[25.7,"light_attack",false],
		[26.2,"light_attack",true],[26.3,"light_attack",false],[26.8,"light_attack",true],[26.9,"light_attack",false],[28.4,"light_attack",true],[28.5,"light_attack",false],
		[30.0,"title","MATERIAL / BODY / fixture reset"],[30.1,"station",2.1],[30.2,"surface","body"],[30.5,"light_attack",true],[30.6,"light_attack",false],
		[32.0,"title","MATERIAL / STONE / fixture reset"],[32.1,"station",2.1],[32.2,"surface","stone"],[32.5,"light_attack",true],[32.6,"light_attack",false],
		[34.0,"title","MATERIAL / METAL / fixture reset"],[34.1,"station",2.1],[34.2,"surface","metal"],[34.5,"light_attack",true],[34.6,"light_attack",false],
		[36.0,"title","MATERIAL / WOOD / fixture reset"],[36.1,"station",2.1],[36.2,"surface","wood"],[36.5,"light_attack",true],[36.6,"light_attack",false],
		[38.0,"title","08 / SHEATH / FINAL FITTING"],[38.2,"putaway",0],[39.4,"still","final_sheath"],
	]
	RenderingServer.frame_post_draw.connect(capture)
	running = true

func hide_legends(node: Node) -> void:
	if node.has_method("set_legend_visible"):
		node.set_legend_visible(false)
	for child in node.get_children():
		hide_legends(child)

func station(distance: float) -> void:
	player.position = Vector3(12,0.9,-25)
	player.velocity = Vector3.ZERO
	player.health = 100.0
	player.rotation = Vector3.ZERO
	dummy.reset_dummy()
	dummy.health = 10000.0
	dummy.position = Vector3(12,0.1,-25-distance)
	dummy.player = player
	dummy.attack_cooldown = 99.0
	dummy.set_process(false)
	dummy.set_physics_process(false)

func _process(delta: float) -> bool:
	if not running:
		return false
	# Launch with --fixed-fps 60: schedule by movie frames, unaffected by hitstop.
	clock += 1.0 / 60.0
	while index < sequence.size() and clock >= float(sequence[index][0]):
		var action: Array = sequence[index]
		index += 1
		match action[1]:
			"title": label.text = String(action[2])
			"still": pending.append(String(action[2]))
			"station": station(float(action[2]))
			"equip": manager.equip_weapon(&"sword")
			"putaway": manager._begin_sheathe(&"none")
			"surface":
				for surface in ["body","wood","stone","metal"]:
					dummy.remove_from_group("surface_"+surface)
				dummy.add_to_group("surface_"+String(action[2]))
			"enemy":
				dummy.set_process(true)
				dummy.force_attack(int(action[2]))
			_:
				var input := InputEventAction.new()
				input.action = StringName(action[1])
				input.pressed = bool(action[2])
				Input.parse_input_event(input)
		receipts.append({"time":clock,"input":String(action[1]),"state":combat.state})
	if clock >= 41.0:
		running = false
		FileAccess.open(output.path_join("Sword_Final_Test_receipt.json"),FileAccess.WRITE).store_string(JSON.stringify(receipts,"\t"))
		print("SWORD_FINAL_RECEIPT events=",receipts.size()," perfect_guard=",combat.perfect_guard_count)
		return true
	return false

func capture() -> void:
	if pending.is_empty():
		return
	var frame := root.get_texture().get_image()
	for tag in pending:
		frame.save_png(output.path_join(tag+".png"))
	pending.clear()
