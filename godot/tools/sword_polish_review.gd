extends SceneTree
# Scripted runtime review through the real combat controller; no pose overrides.
var world: Node3D
var combat: CombatController
var output := "E:/SEKAI-SwordPolish-20261012/before"
var pending: Array[String] = []
var captures: Array[String] = []

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		output = args[0]
	DirAccess.make_dir_recursive_absolute(output)
	call_deferred("run")

func wait_seconds(seconds: float) -> void:
	await create_timer(seconds).timeout

func run() -> void:
	world = load("res://scenes/combat/CombatSandbox.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	await wait_seconds(0.3)
	var player := world.get_node("Player") as CharacterBody3D
	combat = player.get_node("CombatController")
	player.position = Vector3(0, 1.1, 4)
	var dummy := world.get_node_or_null("TechnicalDummy")
	if dummy != null:
		dummy.queue_free()
	for node_name in ["DeveloperPanel", "ParryDebugOverlay", "CombatHUD"]:
		var node := world.get_node_or_null(node_name)
		if node != null:
			node.set("visible", false)
	player.get_node("WeaponManager/WeaponIndicator").visible = false
	player.get_node("ChainDirector").debug_readout = false
	var lab := world.get_node_or_null("ChainLab")
	if lab != null and lab.has_method("set_legend_visible"):
		lab.set_legend_visible(false)
	combat.reach.trace_resolved.connect(func(i: int, _h: int, _mark: Dictionary): pending.append("a3_cut_%d" % i))
	combat.reach.arc_resolved.connect(func(i: int, _h: int, _a: float, _b: float):
		if i == 2 or i == 5:
			pending.append("a4_slice_%d" % i))
	RenderingServer.frame_post_draw.connect(capture)
	await wait_seconds(2.0)
	pending.append("idle")
	await wait_seconds(0.3)
	for i in 4:
		print("POLISH_REQUEST ", i + 1, " accepted=", combat.request(&"light"))
		await wait_seconds(0.16 if i == 1 else 0.20)
		pending.append("a%d_motion" % (i + 1))
		while combat.state != CombatController.State.IDLE:
			await physics_frame
		await wait_seconds(0.10)
	await wait_seconds(1.0)
	pending.append("settled")
	await wait_seconds(0.3)
	print("POLISH_CAPTURES ", captures)
	RenderingServer.frame_post_draw.disconnect(capture)
	combat.stow()
	world.queue_free()
	await wait_seconds(0.2)
	quit()

func capture() -> void:
	if pending.is_empty():
		return
	var frame := root.get_texture().get_image()
	for tag in pending:
		frame.save_png(output.path_join(tag + ".png"))
		captures.append(tag)
	pending.clear()
