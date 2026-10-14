extends SceneTree
# Combat sound language: structure test.
#
# This does NOT judge taste - that is the 2-minute in-game audition. What it
# locks down is the shape of the language:
#   * every atom in the library actually loads
#   * variations alternate instead of repeating, and a group's variants are the SAME sound
#   * layer gains are relative values, which is only true if the trim equalises LOUDNESS
#   * a whiff carries no metal, heavy carries pressure, dodge carries no body
#   * perfect guard reads as a sharp transient first, and is not just a louder
#     version of a normal guard
#   * a frozen body answers ICE without the caller knowing what a TechnicalDummy is
#   * the cues the language still needs are reported, not silently forgotten
#
# The atom count is deliberately NOT asserted. It used to be pinned at 12, and when the
# library grew to 157 that assertion had been red for weeks - a test that fails because
# the project got bigger is a test nobody reads. What matters is that the CORE twelve are
# still present and that every atom that IS in the table loads.

## The sword's original twelve. Named, not counted: adding atoms is the normal way this
## library grows, and a test that has to be edited every time is a test that gets deleted.
const CORE_ATOMS: Array[StringName] = [
	&"air_fast_a", &"air_fast_b", &"pressure_low", &"body_low", &"cloth_fast",
	&"metal_sharp_a", &"metal_sharp_b", &"metal_body", &"glass_crack", &"glass_body",
	&"glass_low_tick", &"wind_pressure",
]

const DIRECTOR_PATH := "res://scripts/audio/combat_audio_director.gd"


func _initialize() -> void:
	call_deferred("_run")


func _fail(message: String) -> void:
	push_error(message)
	quit(1)


## A Node3D that answers `is_frozen()` - the shape a body with a script has.
func _frozen_stub() -> Node3D:
	return _stub("extends Node3D\n\n\nfunc is_frozen() -> bool:\n\treturn true\n")


## A Node3D that only carries the PROPERTY - the shape a body without a script has, and
## the one the duck typing in `_is_frozen` exists for.
func _property_stub() -> Node3D:
	return _stub("extends Node3D\n\n\nvar frozen := true\n")


func _stub(source: String) -> Node3D:
	var script := GDScript.new()
	script.source_code = source
	script.reload()
	var node := Node3D.new()
	node.set_script(script)
	return node


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
	for atom_id in CORE_ATOMS:
		if registry.atom(atom_id) == null:
			_fail("core atom is gone from the table: " + String(atom_id))
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

	# ------------------------------------------------------------- loudness
	# Every layer gain in every cue is documented as RELATIVE, and that is only true
	# when each atom lands at the same loudness at 0 dB. Two assertions, because either
	# one alone is passable by a broken build:
	#   (a) the trim equals the loudness formula, so nobody hand-edited a base gain
	#   (b) the trims actually SPREAD, so a future regression to a constant - or back to
	#       the peak basis, which for these files is a different spread - turns this red
	var trim_min := INF
	var trim_max := -INF
	var measured := 0
	for atom_id in registry.atoms:
		var atom := registry.atom(atom_id)
		if not atom.has_loudness:
			continue
		measured += 1
		var want := SoundAtom.REFERENCE_LOUDNESS_DB - atom.loudness_db
		if absf(atom.base_gain_db - want) > 0.01:
			_fail("%s trim is %.2f dB but its measured loudness asks for %.2f dB - the trim is no longer the loudness basis" % [
				String(atom_id), atom.base_gain_db, want])
			return
		trim_min = minf(trim_min, atom.base_gain_db)
		trim_max = maxf(trim_max, atom.base_gain_db)
	if measured < 100:
		_fail("only %d atoms have a loudness row - the side table did not load, so every layer gain is a lie" % measured)
		return
	if trim_max - trim_min < 8.0:
		_fail("atom trims only span %.1f dB - that is a peak or a constant trim, not a loudness one" % (trim_max - trim_min))
		return

	# ----------------------------------------------------------------- cull
	# A variant that is a different sound from its siblings is a cue that changes
	# identity one play in three. The list is in the registry so a regeneration cannot
	# quietly bring the file back.
	if not registry.culled.has(&"sword_contact_stone_01_A"):
		_fail("sword_contact_stone_01_A is offered again - a group of three where two agree is a group with a bug")
		return
	if registry.group_ids(&"sword_contact_stone").size() != 2:
		_fail("sword_contact_stone should offer its two agreeing variants, got %d" % registry.group_ids(&"sword_contact_stone").size())
		return
	for atom_id in registry.culled:
		if registry.atoms.has(atom_id):
			_fail("culled atom is still in the playable table: " + String(atom_id))
			return

	# ------------------------------------------------------------ variation
	var light_1 := director.cues.get(&"sword_light_1") as SfxCue
	if light_1 == null:
		_fail("sword_light_1 cue missing")
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

	# A group with three members has to rotate through all three, not shuttle between two.
	var shatter := director.cues.get(&"sword_shatter") as SfxCue
	if shatter == null:
		_fail("sword_shatter cue missing")
		return
	var crystals: Array[StringName] = []
	for _i in 4:
		var layers := sfx.play(shatter)
		for entry in layers:
			if StringName(entry["group"]) == &"crystal_break":
				crystals.append(entry["atom"])
	if crystals.size() != 4:
		_fail("sword_shatter must lay down one crystal_break per play, got %d" % crystals.size())
		return
	if crystals[0] == crystals[1] or crystals[1] == crystals[2] or crystals[2] == crystals[3]:
		_fail("crystal_break repeated a file back to back: %s" % str(crystals))
		return
	if crystals[0] != crystals[3]:
		_fail("crystal_break does not rotate through its variants: %s" % str(crystals))
		return

	# ----------------------------------------------------------------- cues
	var expectations := {
		&"sword_light_1": {"primary": &"air_fast", "forbid": [&"metal_sharp", &"metal_body"]},
		&"sword_light_2": {"primary": &"air_fast", "forbid": [&"metal_body"]},
		&"sword_light_3": {"primary": &"air_fast", "forbid": []},
		&"sword_heavy_release": {"primary": &"feel_v2_swing_a4", "require": [&"feel_v2_iaido_pressure"]},
		&"sword_dodge": {"primary": &"air_fast", "forbid": [&"body_low"]},
		# A block is DULL on purpose - the blade does not bite - so it may carry the low
		# body the registry lists for "guard impact". What makes it a block and not a
		# perfect guard is that `metal_body` leads and `metal_sharp` sits under it, which
		# is exactly what `primary` asserts.
		&"sword_block": {"primary": &"metal_body", "forbid": []},
		&"sword_perfect_guard": {"primary": &"feel_v2_parry", "require": [&"feel_v2_hit_metal"]},
		&"wind_burst": {"primary": &"wind_pressure", "require": [&"air_fast"]},
		&"sword_contact_stone": {"primary": &"feel_v2_hit_stone", "forbid": [&"pressure_low"]},
		&"sword_contact_metal": {"primary": &"feel_v2_hit_metal", "forbid": [&"metal_sharp"]},
		&"sword_contact_wood": {"primary": &"feel_v2_hit_wood", "forbid": [&"pressure_low"]},
		&"sword_contact_ice": {"primary": &"crystal_break", "forbid": [&"pressure_low"]},
		&"sword_hit_weight": {"primary": &"feel_v2_iaido_pressure", "forbid": []},
		&"sword_riposte": {"primary": &"metal_sharp", "forbid": []},
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

	# PART §5: A1 opens the sentence with AIR ONLY - a whiff that carries metal is a whiff
	# that already landed. A2 and A3 may borrow the previous cut's steel, but only as a
	# DETAIL: if `metal_sharp` in the light chain is loud enough to be the identity, the
	# three-hit combo stops being three speeds of one blade and becomes three sounds.
	var first_light := director.cues.get(&"sword_light_1") as SfxCue
	if first_light == null:
		_fail("sword_light_1 cue missing")
		return
	for entry in first_light.layers:
		var layer := entry as SfxLayer
		if layer.group == &"metal_sharp":
			_fail("sword_light_1 is the opening cut and must carry no metal at all (found metal_sharp at %.1f dB)" % layer.gain_db)
			return
	for cue_id in [&"sword_light_2", &"sword_light_3"]:
		var cue := director.cues.get(cue_id) as SfxCue
		for entry in cue.layers:
			var layer := entry as SfxLayer
			if layer.group == &"metal_sharp" and layer.gain_db > -8.0:
				_fail("%s uses metal_sharp at %.1f dB - that is an identity, not a detail" % [
					String(cue_id), layer.gain_db])
				return
			# A3 is allowed a finisher's mass - the brief asks for one - but `metal_body` is
			# the guard / weapon-bind atom and it may never be the identity of a swing that
			# hit nothing. The level is what separates the two readings, so the level is what
			# gets asserted.
			if layer.group == &"metal_body" and layer.gain_db > -12.0:
				_fail("%s uses metal_body at %.1f dB - an air swing may hint at the weapon's mass, never lead with it" % [
					String(cue_id), layer.gain_db])
				return

	# PART M: a contact is a POINT IN THE WORLD, so it must not play in the player's hands.
	for cue_id in [&"sword_contact_body", &"sword_contact_stone", &"sword_contact_metal",
			&"sword_contact_wood", &"sword_contact_ice", &"sword_hit_weight", &"sword_shatter"]:
		var cue := director.cues.get(cue_id) as SfxCue
		if cue == null or not cue.spatial:
			_fail("%s must be spatial - a contact played at the origin is a lie in first person" % String(cue_id))
			return
	# ...and the swing itself must NOT be, because it belongs to the hands holding it.
	for cue_id in [&"sword_light_1", &"sword_heavy_windup", &"sword_heavy_release", &"sword_dodge"]:
		var cue := director.cues.get(cue_id) as SfxCue
		if cue == null or cue.spatial:
			_fail("%s is a player-layer cue and must not be spatialised" % String(cue_id))
			return

	# heavy pressure must enter late, not under the whole wind-up
	var heavy := director.cues.get(&"sword_heavy_release") as SfxCue
	for entry in heavy.layers:
		var layer := entry as SfxLayer
		if layer.group == &"feel_v2_iaido_pressure" and layer.delay <= 0.0:
			_fail("heavy pressure must be delayed into the acceleration tail")
			return

	# perfect guard hierarchy: sharp first, body under it
	var perfect := director.cues.get(&"sword_perfect_guard") as SfxCue
	var sharp_db := -100.0
	var body_db := -100.0
	for entry in perfect.layers:
		var layer := entry as SfxLayer
		if layer.group == &"feel_v2_parry" and layer.gain_db > sharp_db:
			sharp_db = layer.gain_db
		elif layer.group == &"feel_v2_hit_metal":
			body_db = layer.gain_db
	if sharp_db <= -100.0 or body_db <= -100.0:
		_fail("perfect guard lost its sharp/body pair (sharp %.1f / body %.1f)" % [sharp_db, body_db])
		return
	if body_db > sharp_db - 4.0:
		_fail("perfect guard body layer is too close to the sharp one (sharp %.1f / body %.1f)" % [sharp_db, body_db])
		return

	# PART D: a perfect guard has to be tellable from a block BY EAR, and not because it
	# is louder. Two different identity layers is the mechanism; the level gap is the
	# reinforcement. A build where PG is the same sound at +6 dB is the failure this
	# catches.
	var normal_guard := director.cues.get(&"sword_block") as SfxCue
	if normal_guard.primary_group() == perfect.primary_group():
		_fail("block and perfect guard share an identity layer - they must be tellable apart")
		return
	if perfect.gain_db <= normal_guard.gain_db:
		_fail("perfect guard is not even louder than a block (%.1f vs %.1f)" % [
			perfect.gain_db, normal_guard.gain_db])
		return

	# §15 HIERARCHY: movement < light sword < normal hit < heavy < perfect guard <
	# shatter/signature. Perfect guard earns its place with transient CLARITY, so the top
	# of the ladder is the shatter - and the shatter is the one cue that is spatially
	# placed on top of its gain, which is why it needs the level rather than a peak.
	if shatter.gain_db < perfect.gain_db:
		_fail("shatter sits at %.1f dB under a perfect guard at %.1f dB - the top of the loudness hierarchy is the shatter/signature" % [
			shatter.gain_db, perfect.gain_db])
		return
	for contact_id in [&"sword_contact_body", &"sword_contact_stone", &"sword_contact_metal",
			&"sword_contact_wood", &"sword_contact_ice"]:
		var contact := director.cues.get(contact_id) as SfxCue
		if contact.gain_db >= shatter.gain_db:
			_fail("%s is at %.1f dB, at or over the shatter at %.1f dB - a material contact is not the moment" % [
				String(contact_id), contact.gain_db, shatter.gain_db])
			return

	# ------------------------------------------- material routing / duck typing
	for material in [&"flesh", &"stone", &"metal", &"wood", &"ice", &"frozen"]:
		var routed: StringName = CombatAudioCues.MATERIAL_CUE.get(material, &"")
		if routed == &"" or not director.cues.has(routed):
			_fail("material '%s' routes to a cue that does not exist: %s" % [
				String(material), String(routed)])
			return
	if CombatAudioCues.MATERIAL_CUE.get(&"frozen") != &"sword_contact_ice":
		_fail("a frozen body must be answered by the ICE contact, not by a flesh one")
		return

	# A frozen body WITHOUT `is_frozen()` still has to answer ICE. This is the assertion
	# that covers the registry/caller contract rather than the one enemy that happens to
	# implement the method, and it is the one that was silently broken: `bool()` is the
	# bool CONSTRUCTOR, and handed the `null` that `get()` returns for a body with no
	# `frozen` property it raises "Nonexistent 'bool' constructor".
	var plain := Node3D.new()
	world.add_child(plain)
	if director._surface_of(plain) != &"flesh":
		_fail("a body with nothing to declare must read as flesh, got %s" % String(director._surface_of(plain)))
		return
	var by_property := _property_stub()
	world.add_child(by_property)
	if not director._is_frozen(by_property):
		_fail("a body that answers only the `frozen` PROPERTY was not recognised as frozen")
		return
	if director._surface_of(by_property) != &"ice":
		_fail("a frozen body without is_frozen() must surface as ice, got %s" % String(director._surface_of(by_property)))
		return
	var by_method := _frozen_stub()
	world.add_child(by_method)
	if not director._is_frozen(by_method):
		_fail("a body that answers only is_frozen() was not recognised as frozen")
		return

	# ------------------------------------------------------------- shatter gate
	if not is_equal_approx(CombatAudioDirector.SHATTER_POISE, 35.0):
		_fail("SHATTER_POISE is %.1f - it has to be the body's own number, 35.0" % CombatAudioDirector.SHATTER_POISE)
		return
	director._on_hit_landed(null, {"target": by_method, "poise_damage": 5.0})
	if director.last_cue_id == &"sword_shatter":
		_fail("a light hit on frozen matter announced a shatter the body decided not to do")
		return
	if director.last_cue_id != &"sword_contact_ice":
		_fail("a light hit on frozen matter must be an ICE contact, got %s" % String(director.last_cue_id))
		return
	director._on_hit_landed(null, {"target": by_method, "poise_damage": 40.0})
	if director.last_cue_id != &"sword_shatter":
		_fail("a hit at or above SHATTER_POISE must shatter, got %s" % String(director.last_cue_id))
		return

	# PART M / §18: contacts are placed at the hit, and the debug mirror has to show it.
	var before := director.cue_seq
	director.play_cue_at(&"sword_contact_stone", Vector3(3.0, 0.0, 0.0))
	if director.cue_seq != before + 1:
		_fail("play_cue_at did not fire exactly one cue (seq %d -> %d)" % [before, director.cue_seq])
		return
	var newest: Dictionary = director.history[director.history.size() - 1]
	var newest_at: Vector3 = newest.get("at", Vector3.ZERO)
	if newest_at.distance_to(Vector3(3.0, 0.0, 0.0)) > 0.001:
		_fail("play_cue_at lost the position - a contact with no place is a contact in the player's head")
		return

	# --------------------------------------------------- constructor trap guard
	# `bool(x)` is not a cast in GDScript: it is the bool constructor and it accepts a
	# bool or a number. `bool(some_node.get("..."))` therefore raises a runtime error
	# whenever the property is missing - and a runtime error cannot fail this test, so
	# the SOURCE is what gets asserted. This is the only reason this check reads a file.
	var source := FileAccess.get_file_as_string(DIRECTOR_PATH)
	if source.is_empty():
		_fail("cannot read %s to check for the bool() constructor trap" % DIRECTOR_PATH)
		return
	var trap := RegEx.new()
	trap.compile("bool\\s*\\(\\s*[A-Za-z_][A-Za-z0-9_.]*\\.(get|call)\\s*\\(")
	var hit := trap.search(source)
	if hit != null:
		_fail("bool() applied to a Variant at offset %d: %s - use `is bool` instead, bool(...) is a constructor and rejects null" % [
			hit.get_start(), hit.get_string()])
		return

	# ------------------------------------------------------------ wiring
	var controller := world.get_node("Player/CombatController") as CombatController
	# The DEPARTURE, not the input. `move_started` answers the keypress, and
	# startup is not dead air — it is the wind-up the player is watching. A
	# whoosh fired on the input describes 0.085s of light (0.185s of heavy) that
	# has not happened yet, and the ear believes the sound rather than the
	# blade, so the sword reads as late when nothing about it is late.
	if not controller.has_signal(&"swing_started"):
		_fail("this controller has no swing_started, so a swing cue can only be fired at the input - the sword will read as late")
		return
	if not controller.swing_started.is_connected(director._on_swing_started):
		_fail("swing_started is not wired to the audio director, so every swing cue is fired at the input instead of at the blade")
		return
	# The two beats are different jobs and must not share a handler: the input is the
	# body coiling (only the skill family has a wind-up worth hearing) and the departure
	# is the cut itself. One handler on both is a whoosh that plays twice.
	if controller.swing_started.is_connected(director._on_move_started):
		_fail("the departure is wired to the input handler as well, so the wind-up and the cut fire off the same beat")
		return
	if not controller.move_started.is_connected(director._on_move_started):
		_fail("move_started is not wired, so a skill's wind-up has no anticipation")
		return
	if not controller.hit_landed.is_connected(director._on_hit_landed):
		_fail("hit_landed is not wired to the audio director")
		return
	if not controller.perfect_guard_landed.is_connected(director._on_perfect_guard):
		_fail("perfect_guard_landed is not wired to the audio director")
		return
	if not controller.state_changed.is_connected(director._on_state_changed):
		_fail("state_changed is not wired, so the heavy wind-up (CHARGE) and dodge have no sound of their own")
		return
	var dodge_audio := world.get_node("Player/DodgeAudio") as AudioStreamPlayer
	if dodge_audio.volume_db > -60.0:
		_fail("legacy dodge_temp.wav is still audible and will double with the layered dodge")
		return

	# -------------------------------------------------- air absorption (contact)
	# The CONTACT layer is spatial, and a material is carried by its top end. Godot's
	# default air-absorption filter is a 5 kHz cutoff at -24 dB, applied with distance,
	# and on these voices it was deleting exactly that band: measured on a stone contact
	# in the sandbox, a faithful offline rebuild of the same layer list puts 27.8% of the
	# cue between 2-6.5 kHz and the recorded take had 5.6%. Nothing else in this project
	# reads these two properties, so the fix is a decoration until a test PLAY a contact
	# and then reads the node the fix lives on.
	var contact_at := Vector3(3.0, 1.0, 0.0)
	director.play_cue_at(&"sword_contact_metal", contact_at)
	await process_frame
	var voices: Array = sfx._spatial_players
	if voices.is_empty():
		_fail("a spatial contact produced no spatial voice - the CONTACT layer stopped being spatial")
		return
	var voice := voices[0] as AudioStreamPlayer3D
	if voice.attenuation_filter_cutoff_hz < 8000.0:
		_fail("contact air absorption cuts at %.0f Hz - the material's edge is filtered away before the player hears it" % voice.attenuation_filter_cutoff_hz)
		return
	if voice.attenuation_filter_db <= -12.0:
		_fail("contact air absorption is %.0f dB - a hit at 3 m loses the colour that distinguishes one material from another" % voice.attenuation_filter_db)
		return

	# ------------------------------------------------------------ pending
	var report := registry.pending_report()
	if report == "no pending atoms":
		_fail("pending atom list is empty - P0 glass ticks are still missing")
		return

	print("PASS: combat sound language")
	print("  atoms: %d (culled %d) | groups: %d | cues: %d" % [
		registry.atom_count(), registry.culled.size(), registry.groups.size(), director.cues.size()])
	print("  loudness rows merged: %d | trim span: %.1f dB" % [measured, trim_max - trim_min])
	print("  variation: air_fast " + str(seen) + " | crystal_break " + str(crystals))
	print("  air absorption on contact: cutoff %.0f Hz / %.0f dB" % [
		voice.attenuation_filter_cutoff_hz, voice.attenuation_filter_db])
	print("  pending atoms:")
	for line in report.split("\n"):
		print("    " + line)

	sfx.stop_all()
	world.queue_free()
	await process_frame
	await create_timer(0.25, true, false, true).timeout
	quit(0)
