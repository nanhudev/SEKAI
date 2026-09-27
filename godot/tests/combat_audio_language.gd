extends SceneTree
# Combat sound language: structure test.
#
# This does NOT judge taste - that is the 2-minute in-game audition. What it
# locks down is the shape of the language:
#   * every atom in the library actually loads
#   * variations alternate instead of repeating
#   * a whiff carries no metal, heavy carries pressure, dodge carries no body
#   * perfect guard reads as a sharp transient first, and is not just a louder
#     version of a normal guard
#   * the cues the language still needs are reported, not silently forgotten

func _initialize() -> void:
	call_deferred("_run")


func _fail(message: String) -> void:
	push_error(message)
	quit(1)


func _run() -> void:
	var scene: PackedScene = load("res://scenes/combat/CombatSandbox.tscn")
	var world: Node3D = scene.instantiate()
	root.add_child(world)
	await process_frame
	await process_frame

	var director := world.get_node_or_null("CombatAudioDirector") as CombatAudioDirector
	if director == null:
		_fail("CombatAudioDirector is not in the combat scene")
		return
	var registry := director.registry
	var sfx := director.sfx
	if registry == null or sfx == null:
		_fail("director did not build a registry / layered sfx")
		return

	# ---------------------------------------------------------------- atoms
	if registry.atom_count() != 12:
		_fail("expected 12 core atoms, got %d" % registry.atom_count())
		return
	for group in [&"air_fast", &"pressure_low", &"body_low", &"cloth_fast",
			&"metal_sharp", &"metal_body", &"glass_crack", &"glass_body",
			&"glass_low_tick", &"wind_pressure"]:
		if not registry.has_group(group):
			_fail("atom group missing: " + String(group))
			return
	for atom_id in registry.atoms:
		var atom := registry.atom(atom_id)
		if atom.stream == null:
			_fail("atom has no stream: " + String(atom_id))
			return
	if registry.group_ids(&"air_fast").size() != 2:
		_fail("air_fast must offer two alternating variations")
		return
	if registry.group_ids(&"metal_sharp").size() != 2:
		_fail("metal_sharp must offer two alternating variations")
		return

	# ------------------------------------------------------------ variation
	var light_1 := director.cues.get(&"light_1") as SfxCue
	if light_1 == null:
		_fail("light_1 cue missing")
		return
	var seen: Array[StringName] = []
	for _i in 4:
		var layers := sfx.play(light_1)
		var atom_id: StringName = &""
		for entry in layers:
			if StringName(entry["group"]) == &"air_fast":
				atom_id = entry["atom"]
		seen.append(atom_id)
	if seen[0] == seen[1] or seen[1] == seen[2]:
		_fail("air_fast repeated the same file back to back: %s" % str(seen))
		return
	if seen[0] != seen[2]:
		_fail("air_fast does not alternate: %s" % str(seen))
		return

	# ----------------------------------------------------------------- cues
	var expectations := {
		&"light_1": {"primary": &"air_fast", "forbid": [&"metal_sharp", &"metal_body"]},
		&"light_2": {"primary": &"air_fast", "forbid": [&"metal_sharp", &"metal_body"]},
		&"light_3": {"primary": &"air_fast", "forbid": [&"metal_sharp", &"metal_body"]},
		&"heavy_swing": {"primary": &"air_fast", "require": [&"pressure_low"]},
		&"dodge": {"primary": &"air_fast", "forbid": [&"body_low"]},
		&"guard": {"primary": &"metal_body", "forbid": [&"body_low"]},
		&"perfect_guard": {"primary": &"metal_sharp", "require": [&"metal_body", &"body_low"]},
		&"wind_burst": {"primary": &"wind_pressure", "require": [&"air_fast"]},
	}
	for cue_id in expectations:
		var cue := director.cues.get(cue_id) as SfxCue
		if cue == null:
			_fail("cue missing: " + String(cue_id))
			return
		var want: Dictionary = expectations[cue_id]
		if cue.primary_group() != want["primary"]:
			_fail("%s identity layer is %s, expected %s" % [
				String(cue_id), String(cue.primary_group()), String(want["primary"])])
			return
		var groups_present: Array[StringName] = []
		for entry in cue.layers:
			var layer := entry as SfxLayer
			groups_present.append(layer.group)
			if not registry.has_group(layer.group) and not layer.optional:
				_fail("%s depends on a group with no atoms: %s" % [String(cue_id), String(layer.group)])
				return
		for needed in want.get("require", []):
			if not groups_present.has(needed):
				_fail("%s is missing required layer %s" % [String(cue_id), String(needed)])
				return
		for banned in want.get("forbid", []):
			if groups_present.has(banned):
				_fail("%s must not contain %s" % [String(cue_id), String(banned)])
				return

	# heavy pressure must enter late, not under the whole wind-up
	var heavy := director.cues.get(&"heavy_swing") as SfxCue
	for entry in heavy.layers:
		var layer := entry as SfxLayer
		if layer.group == &"pressure_low" and layer.delay <= 0.0:
			_fail("heavy pressure must be delayed into the acceleration tail")
			return

	# perfect guard hierarchy: sharp first, body under, weight last
	var perfect := director.cues.get(&"perfect_guard") as SfxCue
	var sharp_db := -100.0
	var body_db := -100.0
	var low_db := -100.0
	for entry in perfect.layers:
		var layer := entry as SfxLayer
		if layer.group == &"metal_sharp":
			sharp_db = layer.gain_db
		elif layer.group == &"metal_body":
			body_db = layer.gain_db
		elif layer.group == &"body_low":
			low_db = layer.gain_db
	if body_db > sharp_db - 4.0 or low_db > sharp_db - 8.0:
		_fail("perfect guard layers are too close in level (sharp %.1f / body %.1f / low %.1f)" % [
			sharp_db, body_db, low_db])
		return
	var normal_guard := director.cues.get(&"guard") as SfxCue
	if normal_guard.primary_group() == perfect.primary_group():
		_fail("guard and perfect guard share an identity layer - they must be tellable apart")
		return

	# ------------------------------------------------------------ wiring
	var controller := world.get_node("Player/CombatController") as CombatController
	# The DEPARTURE, not the input. `move_started` answers the keypress, and
	# startup is not dead air — it is the wind-up the player is watching. A
	# whoosh fired on the input describes 0.085s of light (0.185s of heavy) that
	# has not happened yet, and the ear believes the sound rather than the
	# blade, so the sword reads as late when nothing about it is late. What has
	# to be wired is `swing_started`, with `move_started` only as the fallback
	# for a controller that predates it.
	if controller.has_signal(&"swing_started"):
		if not controller.swing_started.is_connected(director._on_move_started):
			_fail("swing_started is not wired to the audio director, so every swing cue is fired at the input instead of at the blade")
			return
		# And not BOTH: one handler, two triggers, is a whoosh that plays twice
		# — once for the keypress and once for the blade — which reads as an
		# echo rather than as a sword.
		if controller.move_started.is_connected(director._on_move_started):
			_fail("the audio director is listening to both the input and the departure, so every swing cue plays twice")
			return
	elif not controller.move_started.is_connected(director._on_move_started):
		_fail("this controller has no swing_started and move_started is not wired either, so swings are silent")
		return
	if not controller.hit_landed.is_connected(director._on_hit_landed):
		_fail("hit_landed is not wired to the audio director")
		return
	if not controller.perfect_guard_landed.is_connected(director._on_perfect_guard):
		_fail("perfect_guard_landed is not wired to the audio director")
		return
	var dodge_audio := world.get_node("Player/DodgeAudio") as AudioStreamPlayer
	if dodge_audio.volume_db > -60.0:
		_fail("legacy dodge_temp.wav is still audible and will double with the layered dodge")
		return

	# ------------------------------------------------------------ pending
	var report := registry.pending_report()
	if report == "no pending atoms":
		_fail("pending atom list is empty - P0 glass ticks are still missing")
		return

	print("PASS: combat sound language")
	print("  atoms: %d | groups: %d | cues: %d" % [
		registry.atom_count(), registry.groups.size(), director.cues.size()])
	print("  variation: " + str(seen))
	print("  pending atoms:")
	for line in report.split("\n"):
		print("    " + line)

	sfx.stop_all()
	world.queue_free()
	await process_frame
	await create_timer(0.25, true, false, true).timeout
	quit(0)
