extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene: PackedScene = load("res://scenes/combat/CombatSandbox.tscn")
	var world: Node3D = scene.instantiate()
	# The sandbox grants unlimited resources for free play; the mana economy can
	# only be checked with that grant switched off.
	world.set("sandbox_unlimited_resources", false)
	root.add_child(world)
	var player: CharacterBody3D = world.get_node("Player")
	var combat: CombatController = player.get_node("CombatController")
	var hud: CombatHUD = world.get_node("CombatHUD")
	await process_frame
	hud.open_wheel()
	if not hud.wheel_open or Engine.time_scale >= 1.0:
		_fail("Ability wheel did not open and slow time")
		return
	hud.pending_spell = &"wind"
	hud.close_wheel()
	if combat.selected_spell != &"wind" or Engine.time_scale != 1.0:
		_fail("Ability wheel did not confirm Wind and restore time")
		return
	var mana_before: float = player.get("mana")
	if not combat.request(&"cast") or combat.casting_spell != &"wind":
		_fail("Selected Wind was not used for cast")
		return
	if player.get("mana") != mana_before - combat.wind_ability.mana_cost:
		_fail("Wind cast did not charge the selected ability mana cost")
		return
	print("PASS: ability wheel selects Wind, restores time and changes cast")
	quit(0)


func _fail(reason: String) -> void:
	push_error(reason)
	quit(1)
