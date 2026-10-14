extends SceneTree
var failures: Array[String] = []
var world: Node3D
var phases: Array[StringName] = []
var events: Array[StringName] = []

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

func frames(count: int) -> void:
	for i in count:
		await physics_frame

func run() -> void:
	world = load("res://scenes/combat/CombatSandbox.tscn").instantiate()
	root.add_child(world)
	await frames(12)
	var player := world.get_node("Player") as CharacterBody3D
	var combat := player.get_node("CombatController") as CombatController
	var director := world.get_node("IaidoDirector") as IaidoDirector
	var hands := player.find_child("SwordHandPresentation",true,false)
	check(hands != null,"first-person grip presentation missing")
	for clip in [&"Idle",&"Draw Sword",&"Sheath Sword",&"Attack A1",&"Attack A2",&"Attack A3",&"Attack A4",&"Heavy",&"Parry",&"Iaido",&"Skill"]:
		check(hands.animator.has_animation(clip),"presentation clip missing: "+String(clip))
	if not ResourceLoader.exists("res://resources/animations/SwordPresentation.tres"):
		DirAccess.make_dir_recursive_absolute("res://resources/animations")
		ResourceSaver.save(hands.animator.get_animation_library(&""),"res://resources/animations/SwordPresentation.tres")
	var foreground := world.get_node("ForegroundWeaponLayer") as ForegroundWeaponLayer
	check(foreground.copies.has(hands.right.get_node("Palm")),"right palm was not copied into the foreground viewport")
	check(foreground.copies.has(hands.left.get_node("Palm")),"left palm was not copied into the foreground viewport")
	check(combat.moveset.get_skill(&"uni_sword_step") != null,"sword step interface missing")
	check(combat.moveset.get_skill(&"uni_qijian") != null,"sword pressure interface missing")
	check(combat.moveset.ultimate_id == &"","universal ultimate must remain reserved")
	var a3 := SwordBasic.a3()
	check(a3.reach_mode == &"body" and a3.traces.is_empty(),"A3 must be a physical uppercut")
	check(a3.follow.y > a3.wind.y+0.5,"A3 must load low and carry through upward")
	var dummy := world.get_node("TechnicalDummy")
	dummy.sword_reaction.react({"rising_cut":true,"slash_direction":Vector3.UP,"damage":18.4})
	check(dummy.sword_reaction.offset.y > 0.15,"rising cut did not lift the visual body")
	dummy.set_process(false)
	dummy.set_physics_process(false)
	director.phase_changed.connect(func(phase: StringName): phases.append(phase))
	combat.sword_vfx.weapon_event.connect(func(event: StringName,_payload:Dictionary): events.append(event))
	var demo := director.tuning
	check(demo.restore_end > 8.0,"long Demo profile was lost")
	check(combat.request(&"iaido"),"live combat Iaido request refused")
	check(director.tuning == director.combat_tuning,"combat request did not select the short profile")
	check(is_equal_approx(director.tuning.restore_end,2.75),"combat duration must be 2.75 seconds")
	var step_count := 0
	while director.active and step_count < 240:
		await physics_frame
		step_count += 1
	check(not director.active,"combat Iaido did not finish within three seconds of simulation")
	check(director.tuning == demo,"Demo tuning was not restored after combat")
	check(not paused and is_equal_approx(Engine.time_scale,1.0),"world/time pause leaked after Iaido")
	check(is_zero_approx(player.get_node("CameraFeedbackController").fov_hold),"FOV hold leaked")
	for phase in [&"Iaido_Prepare",&"Iaido_Draw",&"Iaido_Strike",&"Iaido_Sheath",&"Iaido_End"]:
		check(phases.has(phase),"missing phase " + String(phase))
	for event in [&"IAIDO_START",&"IAIDO_DRAW",&"IAIDO_SLASH",&"IAIDO_SHEATH"]:
		check(events.has(event),"missing event " + String(event))
	check(combat.request(&"light"),"cannot attack immediately after Iaido")
	await frames(50)
	# Lifecycle gates: abort and player death must restore the same globals.
	for death in [false,true]:
		combat.set_state(CombatController.State.IAIDO)
		director.start_iaido(true)
		await frames(10)
		if death:
			player.health = 0.0
			await frames(3)
		else:
			director.finish_iaido()
		check(not director.active and not paused,"short Iaido abort/death retained world ownership")
		check(director.tuning == demo,"abort/death lost long profile")
		player.health = 100.0
	# Spark lifecycle and event receipt use the real perfect-guard resolution.
	combat._perfect_guard({"source":dummy,"damage":10.0})
	check(events.has(&"SWORD_PARRY"),"parry event missing")
	check(not combat.sword_vfx._contacts.is_empty(),"blade-local parry sparks missing")
	print("UPGRADE_RECEIPT phases=",phases," events=",events," combat_frames=",step_count)
	combat.stow()
	world.queue_free()
	world = null
	await frames(10)
	print("PASS: sword full-upgrade integration" if failures.is_empty() else str(failures))
	quit(0 if failures.is_empty() else 1)
