extends SceneTree
# Combat Lab check.
#
# The Lab is not a menu, it is an INSTRUMENT: every row must be crossable with
# every column in seconds, or the 3x3 combat tendencies can only be argued about
# rather than found. So this test refuses to accept a Lab whose buttons are
# decorative. It asserts that each preset goes through the same machinery the
# player's own actions use, and that the readout actually reports the systems
# this round added.

var world: Node3D
var player: CharacterBody3D
var dummy: Node3D
var combat: CombatController
var lab: CanvasLayer
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
	lab = world.get_node("DeveloperPanel")
	player.global_position = Vector3(0, 1.15, -0.6)
	dummy.set("attack_cooldown", 999.0)
	await _wait(3)

	await _verify_all_four_rows_exist()
	await _verify_all_three_columns_exist()
	await _verify_enemy_state_presets_are_real()
	await _verify_environment_can_interrupt_wind()
	await _verify_the_readout_covers_the_new_systems()

	if failures.is_empty():
		print("PASS: Combat Lab crosses style x magic x enemy state x environment, and every preset goes through the real machinery")
		quit(0)
	else:
		print("FAIL: %d problem(s)" % failures.size())
		for message in failures:
			print("  - " + message)
		quit(1)


# How far a Wind Pressure hit throws a medium enemy, in metres. The number the
# environment has to be built around.
func _push_reach() -> float:
	var wind := ElementLibrary.wind()
	return 5.0 * ElementLibrary.push_scale_for(ElementLibrary.WEIGHT_MEDIUM)


# --- rows ---------------------------------------------------------------

func _verify_all_four_rows_exist() -> void:
	var styles := SwordMovesetLibrary.all_styles()
	_check(styles.size() == 4, "The style row is not four entries (got %d)" % styles.size())
	for wanted in [
		SwordMovesetLibrary.STYLE_UNIVERSAL,
		SwordMovesetLibrary.STYLE_HIDDEN_EDGE,
		SwordMovesetLibrary.STYLE_FLOWING_WIND,
		SwordMovesetLibrary.STYLE_WHITE_ROSE,
	]:
		_check(styles.has(wanted), "The Lab cannot reach the %s style" % wanted)
		var ok := combat.set_style(wanted, true)
		_check(ok, "The Lab's %s button did not switch style" % wanted)
		_check(combat.style_id == wanted, "Style did not stick at %s" % wanted)
		# A row is only a row if it is playable from a standstill.
		_check(combat.moveset.has_light_chain(), "%s has no chain to test" % wanted)
		_check(combat.moveset.guard != null, "%s has no guard to test" % wanted)
	combat.finish_action()


func _verify_all_three_columns_exist() -> void:
	var schools := MagicLibrary.all()
	_check(schools.size() == 3, "The magic column is not three schools (got %d)" % schools.size())
	for id in schools:
		_check(schools.has(id), "The Lab cannot reach the %s school" % id)
		var school: MagicSchool = MagicLibrary.get_school(id)
		_check(school != null and not school.spells.is_empty(), "%s has no spells to select" % id)
		_check(school.element != null and school.element.id == id, "%s's element does not match" % id)

	# Every row must take every column, and the result must be the COLUMN's.
	for style_id in SwordMovesetLibrary.all_styles():
		for school_id in schools:
			combat.set_style(style_id, true)
			combat.finish_action()
			_check(combat.select_school(school_id), "%s x %s could not be selected" % [style_id, school_id])
			var spell := combat.current_spell()
			_check(
				spell != null and spell.element_id == school_id,
				"%s x %s produced the wrong magic" % [style_id, school_id]
			)
	combat.set_style(SwordMovesetLibrary.STYLE_UNIVERSAL, true)
	combat.finish_action()


# --- enemy state: the presets must be the real thing ---------------------

func _verify_enemy_state_presets_are_real() -> void:
	var frost := ElementLibrary.frost()

	# Normal
	dummy.call("apply_debug_state", &"normal")
	_check(float(dummy.get("frost")) == 0.0 and dummy.get("burn") == 0.0, "Normal left an element on the target")

	# Burning — and it must actually tick, which is the whole identity of Fire.
	_check(dummy.call("apply_debug_state", &"burning"), "The Burning preset was rejected")
	_check(float(dummy.get("burn")) > 0.0, "Burning did not leave a burn")
	var before: float = dummy.health
	await _wait(45)
	_check(dummy.health < before, "The Burning preset does not tick: it is only a tint")

	# Frosted — the rung COMBO 4 is built on, which is NOT Frozen.
	dummy.call("apply_debug_state", &"frosted")
	_check(
		dummy.call("element_stage", ElementLibrary.FROST) == &"frosted",
		"The Frosted preset landed on %s" % dummy.call("element_stage", ElementLibrary.FROST)
	)
	_check(not dummy.call("is_brittle"), "Frosted should not be brittle; Frozen is the brittle rung")
	_check(float(dummy.get("frost")) < frost.top_threshold(), "Frosted jumped straight to Frozen")

	# Frozen — short and brittle, not "switched off".
	_check(dummy.call("apply_debug_state", &"frozen"), "The Frozen preset was rejected")
	_check(dummy.state == dummy.State.FROZEN, "The Frozen preset did not freeze (state=%s)" % dummy.state)
	_check(dummy.call("is_brittle"), "Frozen is not brittle")
	_check(dummy.state_timer <= 5.0, "Frozen lasts %.1fs: it is a switch, not a beat" % dummy.state_timer)

	# And the two combos the Lab's own buttons claim to set up must really fire.
	dummy.call("reset_dummy")
	dummy.call("apply_debug_state", &"frozen")
	var shattered := [false]
	dummy.shattered.connect(func() -> void: shattered[0] = true)
	_hit_dummy(&"physical", 20.0, 45.0, {"frozen_bonus": 1.4})
	_check(shattered[0], "The Lab's Frozen preset does not lead to a Shatter")

	dummy.call("reset_dummy")
	dummy.call("apply_debug_state", &"frosted")
	_hit_dummy(&"physical", 20.0, 45.0)
	_check(
		dummy.state == dummy.State.STAGGER,
		"The Lab's Frosted preset does not lead to a Brittle Break (state=%s)" % dummy.state
	)
	dummy.call("reset_dummy")


func _hit_dummy(element: StringName, damage: float, poise: float, extra := {}) -> void:
	var payload := {
		"damage": damage, "poise_damage": poise, "element": element,
		"impulse": 0.0, "source": player, "target": dummy,
	}
	for key in extra:
		payload[key] = extra[key]
	dummy.call("_on_hit", payload)


# --- environment --------------------------------------------------------

func _verify_environment_can_interrupt_wind() -> void:
	# The Lab's own buttons must exist and be callable. A panel whose script
	# failed to load still "exists" as a node, so this has to be its own check —
	# otherwise a broken Lab reads as a working one.
	_check(lab.get_script() != null, "The Combat Lab panel has no script loaded")
	for method in ["_place_for_wall_impact", "_refresh_magic_label", "_refresh_enemy_label", "_refresh_world_label"]:
		_check(lab.has_method(method), "The Combat Lab is missing %s()" % method)

	var props: WindProps = world.get_node_or_null("WindProps")
	_check(props != null, "The Lab has no wind environment: Wind is only a number")
	if props == null:
		return
	_check(props.wall != null, "The wind environment has no wall to be thrown into")
	_check(props.light_objects.size() >= 2, "The wind environment has nothing light to move")

	# The placement button has to actually set up the shot, or the wall is
	# scenery the player will never hit.
	lab.call("_place_for_wall_impact")
	await _wait(2)
	_check(
		player.global_position.distance_to(WindProps.WALL_TEST_PLAYER) < 0.2,
		"The placement button did not move the player into the shot"
	)
	_check(
		dummy.global_position.distance_to(WindProps.WALL_TEST_TARGET) < 0.2,
		"The placement button did not move the target into the shot"
	)
	var wall_face := WindProps.WALL_POSITION.z + WindProps.WALL_SIZE.z * 0.5
	var gap := absf(dummy.global_position.z - wall_face)
	_check(
		gap <= _push_reach(),
		"The wall is %.2fm away but a push only reaches %.2fm: the impact can never happen" % [gap, _push_reach()]
	)

	# Wind must really move the light bodies, and blowing must be reversible.
	props.reset()
	await _wait(2)
	var start: Vector3 = props.light_objects[0].global_position
	var moved: int = props.blow(
		player.global_position, -player.global_transform.basis.z, 7.0, 55.0, 6.0
	)
	await _wait(20)
	_check(moved > 0, "Wind blew nothing: the light objects are not in the shape's way")
	if moved > 0:
		_check(
			props.light_objects[0].global_position.distance_to(start) > 0.15,
			"A blown light object barely moved: wind is not a force"
		)
	props.reset()
	await _wait(2)
	_check(
		props.light_objects[0].global_position.distance_to(start) < 0.6,
		"The Lab cannot put the wind objects back"
	)

	# And the player-side call the Lab button uses must agree with the props call.
	props.reset()
	var spread := combat.wind_spread()
	_check(spread, "Wind Spread found nothing in front, even standing in the shot")


# --- readout: the Lab must SHOW the new systems --------------------------

func _verify_the_readout_covers_the_new_systems() -> void:
	combat.set_style(SwordMovesetLibrary.STYLE_FLOWING_WIND, true)
	combat.finish_action()
	await _wait(2)
	_check("势" in combat.debug_state_line(), "The readout hides 回风's Flow")
	_check("距离" not in combat.debug_state_line(), "The readout shows a measure for 回风")

	combat.set_style(SwordMovesetLibrary.STYLE_WHITE_ROSE, true)
	combat.finish_action()
	dummy.global_position = player.global_position + Vector3(0, -0.55, -2.2)
	# Let idle processing refresh the measure.
	await process_frame
	await process_frame
	_check("距离" in combat.debug_state_line(), "The readout hides 白蔷庭's Measure")
	_check("ideal" in combat.debug_state_line(), "The readout does not name the measure band")
	_check("势" not in combat.debug_state_line(), "The readout shows Flow for a style without it")

	# The panel's own labels must fill in rather than sit blank.
	var panel: PanelContainer = lab.get("panel")
	_check(panel != null, "The Combat Lab has no panel container")
	if panel == null:
		return
	panel.visible = true
	lab.call("_refresh_magic_label")
	lab.call("_refresh_enemy_label")
	lab.call("_refresh_world_label")
	await process_frame
	var magic_text: String = (lab.get("magic_label") as Label).text
	var enemy_text: String = (lab.get("enemy_label") as Label).text
	var world_text: String = (lab.get("world_label") as Label).text
	var school_name: String = combat.current_school().display_name
	_check(school_name in magic_text, "The magic readout does not name the current school '%s': '%s'" % [school_name, magic_text])
	_check(magic_text.contains("blade"), "The magic readout does not report blade infusion: '%s'" % magic_text)
	_check(("brittle" in enemy_text) or ("IDLE" in enemy_text), "The enemy readout is blank: '%s'" % enemy_text)
	_check("wall" in world_text.to_lower(), "The environment readout is blank: '%s'" % world_text)
	panel.visible = false
