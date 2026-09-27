extends SceneTree
# Element + magic check.
#
# The design brief's test is behavioural, not numeric:
#   FIRE  — "is the player thinking about area and spread?"
#   FROST — "is the player setting up the next Shatter?"
#   WIND  — "is the player moving bodies around?"
# So this test refuses to accept "three colours of damage". It asserts that the
# three elements do structurally different things, that the rules are DATA (it
# mutates a definition at runtime and requires the behaviour to follow), and
# that the five cross-system combinations actually fire.

const FIRE := ElementLibrary.FIRE
const FROST := ElementLibrary.FROST
const WIND := ElementLibrary.WIND
const LIGHT := ElementLibrary.WEIGHT_LIGHT
const HEAVY := ElementLibrary.WEIGHT_HEAVY

var world: Node3D
var player: CharacterBody3D
var dummy: Node3D
var combat: CombatController
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
	player.global_position = Vector3(0, 1.15, -0.6)
	dummy.set("attack_cooldown", 999.0)
	await _wait(3)

	await _verify_identities_are_structural()
	await _verify_rules_are_data_not_branches()
	await _verify_fire_burns_and_spreads()
	await _verify_fire_thaws_frost()
	await _verify_frost_ladder_and_shatter()
	await _verify_brittle_break_on_frosted()
	await _verify_wind_weight_and_wall()
	await _verify_wind_spreads_a_field()
	await _verify_wind_feeds_flow()

	if failures.is_empty():
		print("PASS: fire/frost/wind act structurally differently, rules are data, and all five combinations fire")
		quit(0)
	else:
		print("FAIL: %d problem(s)" % failures.size())
		for message in failures:
			print("  - " + message)
		quit(1)


func _hit(element: StringName, damage: float, poise: float, impulse := 0.0, extra := {}) -> void:
	var payload := {
		"damage": damage, "poise_damage": poise, "element": element,
		"impulse": impulse, "source": player, "target": dummy,
	}
	for key in extra:
		payload[key] = extra[key]
	dummy.call("_on_hit", payload)


func _reset() -> void:
	dummy.call("reset_dummy")
	dummy.set("attack_cooldown", 999.0)
	dummy.global_position = Vector3(0, 0.6, -2.0)
	player.global_position = Vector3(0, 1.15, -0.6)


# --- identity is structural, not cosmetic --------------------------------

func _verify_identities_are_structural() -> void:
	var fire := ElementLibrary.fire()
	var frost := ElementLibrary.frost()
	var wind := ElementLibrary.wind()
	# Fire is area + spread + a damage-over-time, and it attacks frost.
	_check(fire.tick_damage > 0.0, "Fire has no damage over time")
	_check(fire.spread_by_wind, "Fire does not spread with wind")
	_check(FROST in fire.hastens_decay_of, "Burning does not thaw frost: fire has no counter-play")
	_check(not fire.has_ladder(), "Fire should be on/off, not a ladder")
	# Frost is a ladder that ends in a brittle state.
	_check(frost.has_ladder() and frost.stage_names.size() == 4, "Frost is not a four-rung ladder")
	_check(frost.enables_brittle, "Frost does not make anything brittle")
	_check(frost.final_stage_duration > 0.0 and frost.final_stage_duration <= 5.0, "Frozen is not a short beat")
	# Wind is force scaled by weight, and it has no ladder and no damage-over-time.
	_check(wind.pushes and wind.push_weight_scaled, "Wind does not push by weight")
	_check(wind.tick_damage == 0.0, "Wind has a damage-over-time: it became a colour of damage")
	# The three must actually differ, or this is one system with three skins.
	_check(
		ElementLibrary.push_scale_for(LIGHT) > ElementLibrary.push_scale_for(HEAVY) * 2.0,
		"Wind does not distinguish a light target from a heavy one"
	)


func _verify_rules_are_data_not_branches() -> void:
	# The strongest possible proof that the enemy no longer hardcodes frost:
	# change the definition and the behaviour must follow, with no code edit.
	var frost := ElementLibrary.frost()
	var original := frost.applies_per_hit
	frost.applies_per_hit = 3.0
	_reset()
	for i in 3:
		dummy.call("_on_hit", {
			"damage": 1.0, "poise_damage": 0.0, "element": FROST,
			"impulse": 0.0, "source": player, "target": dummy,
		})
	_check(
		dummy.state != dummy.State.FROZEN,
		"Frost froze the target from the definition alone being weakened: the enemy still hardcodes it"
	)
	frost.applies_per_hit = original
	_reset()
	for i in 3:
		dummy.call("_on_hit", {
			"damage": 1.0, "poise_damage": 0.0, "element": FROST,
			"impulse": 0.0, "source": player, "target": dummy,
		})
	_check(dummy.state == dummy.State.FROZEN, "Restoring the definition did not restore the freeze")
	_reset()


func _verify_fire_burns_and_spreads() -> void:
	_reset()
	var before: float = dummy.health
	_hit(FIRE, 10.0, 0.0)
	_check(dummy.health < before, "Fire did not hurt on contact")
	_check(dummy.get("burn") > 0.0, "Fire did not leave the target burning")
	# The burn must tick on its own, with no further hits.
	var mid: float = dummy.health
	await _wait(45)
	_check(dummy.health < mid, "Burning never ticked")
	_check(float(dummy.health) < before, "Burning left the target healthier than before")

	# A live field is what makes Fire an area question rather than a hit.
	combat.finish_action()
	combat.select_school(FIRE)
	combat.spell_id = &"flame_ring"
	combat.request(&"cast")
	var frames := 0
	while combat.active_field == null and frames < 120:
		await physics_frame
		frames += 1
	_check(combat.active_field != null, "焚环 left no field behind")
	if combat.active_field != null:
		_check(combat.active_field.radius > 1.0, "The flame ring has no area")
		_check(combat.is_infused(), "Casting an infusing spell did not light the blade")
		dummy.global_position = combat.active_field.global_position + Vector3(0.4, 0, 0)
		var burning_before: float = dummy.health
		await _wait(70)
		_check(dummy.health < burning_before, "Standing in the flame ring did not keep the target burning")
		combat.active_field.queue_free()
		combat.active_field = null
	combat.finish_action()
	_reset()


func _verify_fire_thaws_frost() -> void:
	# Burning shortens Frost's life: fire is the answer to being frozen, which is
	# what stops the player from simply holding both states at once.
	_reset()
	_hit(FROST, 0.0, 0.0)
	var plain := float(dummy.frost)
	_check(plain > 0.0, "Frost was not applied at all")
	# Long enough to clear Frost's decay delay AND to give the 2.5x thaw time to
	# show up as a different number, not just as a rounding wobble.
	await _wait(100)
	var thawed_alone := float(dummy.frost)

	_reset()
	_hit(FROST, 0.0, 0.0)
	_hit(FIRE, 0.0, 0.0)
	await _wait(100)
	var thawed_by_fire := float(dummy.frost)
	_check(
		thawed_by_fire < thawed_alone,
		"Burning did not thaw frost any faster (%.1f vs %.1f)" % [thawed_by_fire, thawed_alone]
	)
	_reset()


func _verify_frost_ladder_and_shatter() -> void:
	_reset()
	_check(dummy.call("element_stage", FROST) == &"normal", "The target did not start unfrozen")
	_hit(FROST, 0.0, 0.0)
	_check(dummy.call("element_stage", FROST) == &"chilled", "First frost hit did not chill")
	_hit(FROST, 0.0, 0.0)
	_check(dummy.call("element_stage", FROST) == &"frosted", "Second frost hit did not reach Frosted")
	_hit(FROST, 0.0, 0.0)
	_check(dummy.state == dummy.State.FROZEN, "Third frost hit did not freeze")
	_check(dummy.call("is_brittle"), "Frozen is not brittle")

	# COMBO 1 — the reference combo: the heavy is what cashes in the setup.
	var shattered := [false]
	dummy.shattered.connect(func() -> void: shattered[0] = true)
	var before: float = dummy.health
	_hit(&"physical", 20.0, 45.0, 0.0, {"frozen_bonus": 1.4})
	_check(shattered[0], "Frozen + Heavy did not Shatter")
	_check(dummy.health < before, "Shatter dealt no damage")
	_check(float(dummy.frost) == 0.0, "Shatter did not consume the frozen state")
	_reset()


func _verify_brittle_break_on_frosted() -> void:
	# COMBO 4 — Frosted (not Frozen) + 藏锋's heavy 断水. Deliberately a rung
	# earlier than Shatter, so a heavy has a reason to exist against frost that
	# is not the same thing as Shatter.
	_reset()
	_hit(FROST, 0.0, 0.0)
	_hit(FROST, 0.0, 0.0)
	_check(dummy.call("element_stage", FROST) == &"frosted", "Setup did not reach Frosted")
	var before: float = dummy.health
	_hit(&"physical", 20.0, 45.0)
	_check(dummy.state == dummy.State.STAGGER, "A heavy on a Frosted target did not break it open")
	_check(dummy.health < before - 20.0, "Brittle Break dealt no bonus damage")
	_check(float(dummy.frost) == 0.0, "Brittle Break did not consume the frost layer")
	_reset()


func _verify_wind_weight_and_wall() -> void:
	# COMBO 2 — Wind Push → wall → impact. The wall is what turns position into
	# posture damage, so this only passes if the world can interrupt the push.
	_reset()
	var props: WindProps = world.get_node_or_null("WindProps")
	_check(props != null, "The sandbox has no wind environment")
	if props == null:
		return
	_check(props.wall != null, "There is no wall to be thrown into")

	# Same gust, two weights, different results.
	var light_start := dummy.global_position
	dummy.set("weight", LIGHT)
	dummy.global_position = Vector3(0, 0.6, -2.0)
	_hit(WIND, 0.0, 0.0, 5.0)
	var light_moved := dummy.global_position.distance_to(light_start)

	_reset()
	var heavy_start := dummy.global_position
	dummy.set("weight", HEAVY)
	_hit(WIND, 0.0, 0.0, 5.0)
	var heavy_moved := dummy.global_position.distance_to(heavy_start)
	_check(
		light_moved > heavy_moved * 1.5,
		"Wind moved a heavy target as far as a light one (%.2f vs %.2f)" % [light_moved, heavy_moved]
	)

	# Now aim it at the wall.
	_reset()
	dummy.set("weight", LIGHT)
	dummy.global_position = Vector3(0, 0.6, -4.4)
	var impacts := [0.0]
	dummy.wall_impact.connect(func(strength: float) -> void: impacts[0] = strength)
	var poise_before := float(dummy.poise)
	_hit(WIND, 0.0, 0.0, 7.0)
	_check(impacts[0] > 0.0, "Driving the target into the wall registered no impact")
	_check(float(dummy.poise) > poise_before, "A wall impact added no posture damage")
	_check(dummy.state == dummy.State.STAGGER, "A wall impact did not stagger")
	dummy.set("weight", ElementLibrary.WEIGHT_MEDIUM)
	_reset()


func _verify_wind_spreads_a_field() -> void:
	# COMBO 3 — Fire → Burning → Wind → spread. Wind must widen the burning
	# ground rather than multiply a number.
	combat.finish_action()
	combat.select_school(FIRE)
	combat.spell_id = &"flame_ring"
	combat.request(&"cast")
	var frames := 0
	while combat.active_field == null and frames < 120:
		await physics_frame
		frames += 1
	_check(combat.active_field != null, "焚环 produced no field to spread")
	if combat.active_field == null:
		return
	var radius_before: float = combat.active_field.radius
	combat.finish_action()
	await _wait(4)
	combat.select_school(WIND)
	combat.request(&"cast")
	frames = 0
	while combat.state == CombatController.State.CAST and frames < 120:
		await physics_frame
		frames += 1
	_check(
		combat.active_field.radius > radius_before,
		"Wind did not spread the burning ground (%.2f -> %.2f)" % [radius_before, combat.active_field.radius]
	)
	combat.active_field.queue_free()
	combat.active_field = null
	combat.finish_action()
	await _wait(2)


func _verify_wind_feeds_flow() -> void:
	# COMBO 5 — Wind movement → 回风 chain. The combination is not a damage bonus;
	# it is that 风步 lets 回风 keep feeding 势, which is the style's whole loop.
	combat.finish_action()
	await _wait(2)
	combat.set_style(SwordMovesetLibrary.STYLE_FLOWING_WIND, true)
	combat.finish_action()
	combat.reset_flow()
	await _wait(2)
	var base_speed := combat.speed_multiplier()
	combat.select_school(WIND)
	combat.spell_id = &"wind_step"
	combat.request(&"cast")
	var frames := 0
	while combat.state == CombatController.State.CAST and frames < 120:
		await physics_frame
		frames += 1
	_check(
		combat.speed_multiplier() > base_speed,
		"风步 did not change movement at all, so it cannot feed 回风's loop"
	)
	await _wait(200)
	_check(
		is_equal_approx(combat.speed_multiplier(), base_speed),
		"风步 never expired"
	)
	combat.finish_action()
	await _wait(2)
