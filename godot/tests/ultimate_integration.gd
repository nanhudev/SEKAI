extends SceneTree
# 无明一刻 / MOMENT OF NO-MOON — the 藏锋流 ultimate, as a playable prototype.
#
# What is being verified is not the damage. It is that the thing the ultimate
# claims to do actually happens, in order, and that it gives the world back
# afterwards: everything stops, several enemies are marked, one invisible draw
# occurs, and only then do the marks open together.

const HIDDEN_EDGE := SwordMovesetLibrary.STYLE_HIDDEN_EDGE

var world: Node3D
var player: CharacterBody3D
var dummy: Node3D
var combat: CombatController
var director: MomentOfNoMoonDirector
var screen_fx: CombatScreenFX
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)


func _wait(frames: int) -> void:
	for i in frames:
		await physics_frame


func _run() -> void:
	var scene: PackedScene = load("res://scenes/combat/CombatSandbox.tscn")
	world = scene.instantiate()
	root.add_child(world)
	player = world.get_node("Player")
	dummy = world.get_node("TechnicalDummy")
	combat = player.get_node("CombatController")
	director = world.get_node("MomentOfNoMoonDirector")
	screen_fx = world.get_node("CombatScreenFX")
	player.global_position = Vector3(0, 1.15, 1.2)
	dummy.set("attack_cooldown", 999.0)
	await _wait(20)

	_verify_ownership()
	await _verify_full_run()

	if failures.is_empty():
		print("PASS: 无明一刻 · one cut, many results, and the world is handed back intact")
		quit(0)
	else:
		print("FAIL: %d problem(s)" % failures.size())
		for message in failures:
			print("  - " + message)
		quit(1)


func _verify_ownership() -> void:
	# The Universal layer is a language, not a style: it owns no ultimate.
	combat.set_style(SwordMovesetLibrary.STYLE_UNIVERSAL, true)
	await physics_frame
	_check(combat.moveset.ultimate_id == &"", "The universal sword handed out an ultimate for free")
	_check(not combat.request(&"ultimate"), "Universal style accepted an ultimate request")
	_check(combat.state == CombatController.State.IDLE, "A rejected ultimate still moved the player")
	# 藏锋 owns it.
	combat.set_style(HIDDEN_EDGE, true)
	await physics_frame
	_check(combat.moveset.ultimate_id == &"moment_of_no_moon", "藏锋 does not own 无明一刻")
	# 聚合斩 must stay a SIGNATURE technique: its own cooldown, and the ultimate
	# slot must not be the thing that gates it.
	_check(combat.moveset.signature_id == &"iaido", "聚合斩 is no longer registered as the signature technique")


func _verify_full_run() -> void:
	combat.reset_skill_cooldowns()
	await physics_frame
	var health_before: float = dummy.health
	_check(combat.request(&"ultimate"), "藏锋 ultimate request was rejected")
	_check(combat.state == CombatController.State.ULTIMATE, "Ultimate did not take over the controller")
	_check(director.active, "Ultimate director did not activate")

	# Everything the enemy was doing must stop mid-motion.
	var frames := 0
	while director.elapsed < MomentOfNoMoonDirector.T_MARK and frames < 200:
		await physics_frame
		frames += 1
	_check(dummy.process_mode == Node.PROCESS_MODE_DISABLED, "Enemy attacks were not stopped mid-motion")
	_check(director.targets.size() >= 1, "The ultimate marked no targets")
	_check(director.marks.size() == director.targets.size(), "Mark count does not match the target count")
	_check(director.targets.size() <= MomentOfNoMoonDirector.MAX_TARGETS, "Target collector exceeded its cap")
	_check(screen_fx.desaturation > 0.0, "The world never drained toward monochrome")
	# The draw itself must be almost invisible: this is the whole point.
	_check(
		MomentOfNoMoonDirector.T_DRAW_END - MomentOfNoMoonDirector.T_DRAW <= 0.15,
		"The moment's draw is not instantaneous"
	)
	_check(
		MomentOfNoMoonDirector.T_ACTIVATE > MomentOfNoMoonDirector.T_CLICK,
		"The marks activate before the click that releases them"
	)

	# Run the rest of the ceremony.
	frames = 0
	while director.active and frames < 900:
		await physics_frame
		frames += 1
	_check(frames < 900, "The ultimate never finished")
	_check(not director.active, "Director still active after the end of the timeline")
	_check(combat.state == CombatController.State.IDLE, "Combat state was not handed back")
	_check(dummy.health < health_before, "Every mark opened and the enemy took no damage")
	_check(dummy.state == dummy.State.STAGGER, "The marked enemy was not interrupted")
	_check(director.marks.is_empty(), "Cut marks were left in the scene")
	_check(dummy.process_mode != Node.PROCESS_MODE_DISABLED, "Enemies were left frozen after the ultimate")
	_check(screen_fx.desaturation < 0.01, "The monochrome grade was not lifted")
	_check(Engine.time_scale == 1.0, "Time was left scaled at %.2f" % Engine.time_scale)
	_check(combat.ultimate_ready_at > Time.get_ticks_msec() / 1000.0, "The ultimate has no cooldown")
	# 聚合斩 was untouched by all of this.
	_check(combat.moveset.signature_id == &"iaido", "The signature slot was consumed by the ultimate")
