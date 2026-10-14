extends SceneTree
# Movement stage check.
#
# WHY THIS PLATFORM NEEDS A TEST: it exists because the arena physically cannot
# host a straight run — the dummy stands on the line the player walks, so forward
# movement ends in a collision about two metres in. That means every claim about
# this platform is a claim about *not being stopped*, and "not being stopped" is
# exactly the kind of thing that silently stops being true.
#
# Two of these checks are invisible until somebody tries them: whether the ramp
# actually reaches the deck, and whether a run that reaches the end stays on the
# world. A kerb across the ramp, or a missing one at the far end, looks perfectly
# fine in a screenshot.

var world: Node3D
var player: CharacterBody3D
var dummy: Node3D
var combat: CombatController
var lane: MovementLane
var baseline_distance := 0.0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene: PackedScene = load("res://scenes/combat/CombatSandbox.tscn")
	world = scene.instantiate()
	root.add_child(world)
	player = world.get_node("Player")
	dummy = world.get_node("TechnicalDummy")
	combat = player.get_node("CombatController")
	await _wait(6)
	lane = world.get_node_or_null("MovementLane") as MovementLane
	if lane == null:
		_fail("The sandbox has no MovementLane, so movement has no stage")
		return

	_check_the_stage_is_separate()
	_check_nothing_blocks_a_run()
	await _check_the_run_covers_ground()
	await _check_wind_step_covers_more()
	await _check_the_ramp_reaches_the_deck()
	await _check_a_run_cannot_leave_the_world()
	Input.action_release(&"move_forward")

	if failures.is_empty():
		print("PASS: the movement lane is a separate stage, nothing blocks a run, and 风步 covers more ground")
		quit(0)
		return
	for reason in failures:
		print("  - " + reason)
		push_error(reason)
	print("FAIL: %d problem(s)" % failures.size())
	quit(1)


# The whole reason the platform exists. If the deck were flush with the arena
# floor it would still be inside the arena's clutter, and the dummy would still
# be standing on the run.
func _check_the_stage_is_separate() -> void:
	_check(MovementLane.DECK_Y > 0.0, "The deck is not raised, so it is not a separate platform")
	_check(MovementLane.LENGTH >= 12.0, "The run is only %.1fm — too short to measure a speed change" % MovementLane.LENGTH)
	var start := lane.start_position()
	var dummy_pos := dummy.global_position
	var inside_lane := (
		absf(dummy_pos.z - MovementLane.CENTER.z) < MovementLane.WIDTH * 0.5 + 1.0
		and absf(dummy_pos.x - MovementLane.CENTER.x) < MovementLane.LENGTH * 0.5 + 1.0
	)
	_check(not inside_lane, "The enemy is standing on the movement lane at %s" % dummy_pos)
	# And the start line has to be ON the platform, not hovering past its edge.
	_check(
		absf(start.x - MovementLane.CENTER.x) < MovementLane.LENGTH * 0.5
			and absf(start.z - MovementLane.CENTER.z) < MovementLane.WIDTH * 0.5,
		"The start position %s is not on the deck" % start
	)


# A ray straight down the run, at a height a kerb cannot reach. Cheap, and it
# catches the case a visual check cannot: something added later that happens to
# sit in the lane.
func _check_nothing_blocks_a_run() -> void:
	var space := player.get_world_3d().direct_space_state
	var height := MovementLane.DECK_Y + 0.9
	var from := MovementLane.CENTER + Vector3(-MovementLane.LENGTH * 0.5 + 0.4, height, 0.0)
	var to := MovementLane.CENTER + Vector3(MovementLane.LENGTH * 0.5 - 0.4, height, 0.0)
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_areas = false
	var hit := space.intersect_ray(query)
	_check(hit.is_empty(), "Something blocks the lane at %s" % hit.get("position"))


func _check_the_run_covers_ground() -> void:
	await _place_at_start()
	var origin := player.global_position
	Input.action_press(&"move_forward")
	await _wait(100)
	Input.action_release(&"move_forward")
	baseline_distance = player.global_position.distance_to(origin)
	_check(
		baseline_distance > 3.0,
		"A 1.6s run only covered %.2fm — the player is being stopped" % baseline_distance
	)
	# And they must still be standing on the deck, not fallen off it.
	_check(
		player.global_position.y > MovementLane.DECK_Y - 0.2,
		"A run dropped the player below the deck (y=%.2f)" % player.global_position.y
	)


# The point of the platform: the same elapsed time covers more ground with 风步.
# Same start line, same frame count, so the only difference is the buff.
func _check_wind_step_covers_more() -> void:
	await _place_at_start()
	_check(combat.select_spell(&"wind_step"), "风步 could not be armed at all")
	if not combat.request(&"cast"):
		_fail("风步 was armed but the cast was refused")
		return
	await _wait(40)
	_check(combat.speed_multiplier() > 1.0, "风步 did not raise the speed multiplier")
	var origin := player.global_position
	Input.action_press(&"move_forward")
	await _wait(100)
	Input.action_release(&"move_forward")
	var travelled := player.global_position.distance_to(origin)
	_check(
		travelled > baseline_distance * 1.1,
		"风步 covered %.2fm against a %.2fm baseline in the same 100 frames — the buff is not reaching movement"
			% [travelled, baseline_distance]
	)


# The ramp is the way on. A kerb across it, or a slab seated half a thickness
# high, looks fine and makes the platform reachable only by teleport.
func _check_the_ramp_reaches_the_deck() -> void:
	var foot := MovementLane.CENTER + Vector3(
		-MovementLane.LENGTH * 0.5 - MovementLane.RAMP_RUN - 0.6, 1.2, 0.0
	)
	player.global_position = foot
	player.velocity = Vector3.ZERO
	player.look_at_from_position(foot, foot + MovementLane.RUN_DIRECTION * 4.0, Vector3.UP)
	await _wait(6)
	Input.action_press(&"move_forward")
	await _wait(160)
	Input.action_release(&"move_forward")
	var standing_on_deck := player.global_position.y > MovementLane.DECK_Y + 0.8
	var past_the_ramp := player.global_position.x > MovementLane.CENTER.x - MovementLane.LENGTH * 0.5
	_check(
		standing_on_deck and past_the_ramp,
		"Walking up the ramp did not reach the deck: ended at %s" % player.global_position
	)


# The arena floor is 24 x 24 and there is nothing below it, so a platform without
# a far kerb is a way to fall out of the world.
func _check_a_run_cannot_leave_the_world() -> void:
	await _place_at_start()
	Input.action_press(&"move_forward")
	await _wait(400)
	Input.action_release(&"move_forward")
	_check(
		player.global_position.y > MovementLane.DECK_Y - 0.3,
		"Running to the end of the lane left the world (y=%.2f, x=%.2f)"
			% [player.global_position.y, player.global_position.x]
	)
	_check(
		player.global_position.x < lane.end_x() + 0.6,
		"A run went past the far kerb (x=%.2f)" % player.global_position.x
	)


func _place_at_start() -> void:
	var start := lane.start_position()
	player.global_position = start
	player.velocity = Vector3.ZERO
	player.look_at_from_position(start, start + MovementLane.RUN_DIRECTION * 4.0, Vector3.UP)
	# The enemy stays parked off the lane for the whole file, because "the player
	# got stopped" must never be explained away by the enemy wandering back in.
	dummy.global_position = Vector3(0.0, 0.6, -9.0)
	await _wait(4)


func _wait(frames: int) -> void:
	for i in frames:
		await physics_frame


func _check(condition: bool, reason: String) -> void:
	if not condition:
		failures.append(reason)


func _fail(reason: String) -> void:
	failures.append(reason)
