extends SceneTree
# The Ability Wheel is the only way a player arms a spell, so this test answers
# one question for EVERY spell in the library: can it be armed, and can it be
# cast? Not "did somebody remember to try the interesting ones".
#
# It exists because three of six spells were unreachable for a whole round. The
# wheel had three hardcoded sectors (one per school) and select_school() always
# reset spell_id to that school's primary, so 焚环 / 凝霜 / 风步 — fire's entire
# area identity, frost's ladder-jump, and wind's movement — existed in data,
# passed every other test, and could not be cast by a player at all. Nothing
# failed, because nothing ever asked whether a spell could be armed.

var _failures: Array[String] = []
var _combat: CombatController
var _player: CharacterBody3D
var _hud: CombatHUD
var _wheel: RadialWheel


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene: PackedScene = load("res://scenes/combat/CombatSandbox.tscn")
	var world: Node3D = scene.instantiate()
	# The sandbox grants unlimited resources for free play; the mana economy can
	# only be checked with that grant switched off.
	world.set("sandbox_unlimited_resources", false)
	root.add_child(world)
	_player = world.get_node("Player")
	_combat = _player.get_node("CombatController")
	_hud = world.get_node("CombatHUD")
	# Park the enemy out of reach and stop it swinging. This test is about the
	# input path; a stray hit mid-cast would surface as "the cast was refused"
	# and send the next reader hunting in the wrong file.
	var dummy: Node3D = world.get_node("TechnicalDummy")
	dummy.global_position = Vector3(0.0, 0.0, 60.0)
	dummy.set("attack_cooldown", 9999.0)
	await process_frame
	if _hud.wheel == null or _hud.wheel.get_script() == null:
		_fail("The wheel did not load, so every check below would be vacuous")
		return
	_wheel = _hud.wheel

	var spells := _all_spells()
	_check_structure(spells)
	_check_geometry()
	await _check_reachability(spells)
	await _check_castability(spells)
	_check_wheel_restores_time()

	if _failures.is_empty():
		print("PASS: every one of the %d spells is armable through the wheel and castable" % spells.size())
		quit(0)
		return
	for reason in _failures:
		push_error(reason)
	print("FAIL: %d problem(s)" % _failures.size())
	quit(1)


func _all_spells() -> Array:
	var spells: Array = []
	for school_id in _combat.schools:
		var school: MagicSchool = _combat.schools[school_id]
		for spell in school.spells:
			spells.append(spell)
	return spells


# The wheel can only ever offer what it was built with, so the sector count is
# the structural half of the bug: a wheel with fewer sectors than spells cannot
# represent them, no matter how the selection code is written.
func _check_structure(spells: Array) -> void:
	_check(spells.size() >= 6, "The library should hold two spells per school, found %d" % spells.size())
	_check(
		_wheel.entries.size() == spells.size(),
		"Wheel offers %d sectors for %d spells" % [_wheel.entries.size(), spells.size()]
	)
	var seen := {}
	for entry in _wheel.entries:
		seen[entry["id"]] = true
	_check(seen.size() == spells.size(), "Two sectors share one spell id")
	for spell in spells:
		_check(
			_wheel.sector_of(spell.id) >= 0,
			"The wheel has no sector for %s (%s)" % [spell.id, spell.display_name]
		)


func _check_geometry() -> void:
	var count := _wheel.entries.size()
	if count == 0:
		return
	# Stepping around the circle, each bearing must resolve to its own sector.
	for index in range(count):
		var angle := _wheel.sector_angle(index)
		_wheel.set_direction(Vector2(cos(angle), sin(angle)) * 200.0)
		var expected: StringName = _wheel.entries[index]["id"]
		_check(
			_wheel.selected_spell == expected,
			"Bearing %d resolved to %s, expected %s" % [index, _wheel.selected_spell, expected]
		)
		# A bearing just inside each seam must stay inside the same sector, or the
		# highlight flickers while the player crosses between two spells.
		var step := TAU / float(count)
		var seam := angle + step * 0.5 - step * 0.05
		_wheel.set_direction(Vector2(cos(seam), sin(seam)) * 200.0)
		_check(
			_wheel.selected_spell == expected,
			"Just inside sector %d's edge it resolved to %s" % [index, _wheel.selected_spell]
		)
	_wheel.set_direction(Vector2.ZERO)
	_check(_wheel.selected_spell == &"", "A centred pointer must select nothing")


# Arm a spell the way a player does: open the wheel, move the pointer onto that
# sector's bearing, release. No writing spell_id from the test — that would test
# the test instead of the input path, which is exactly how the bug survived.
func _arm(spell_id: StringName) -> bool:
	var index := _wheel.sector_of(spell_id)
	if index < 0:
		return false
	_hud.open_wheel()
	var angle := _wheel.sector_angle(index)
	_hud.aim_wheel(Vector2(cos(angle), sin(angle)) * 200.0)
	_hud.close_wheel()
	return _combat.spell_id == spell_id


func _check_reachability(spells: Array) -> void:
	for spell in spells:
		var armed := _arm(spell.id)
		var resolved := _combat.current_spell()
		_check(
			armed and resolved != null and resolved.id == spell.id,
			"%s (%s) could not be armed through the wheel" % [spell.id, spell.display_name]
		)
		_check(
			_combat.selected_school == spell.school_id,
			"Arming %s left the school on %s instead of %s" % [spell.id, _combat.selected_school, spell.school_id]
		)
		_check(
			_combat.current_school() != null,
			"Arming %s left no current school" % spell.id
		)
	await process_frame


func _check_castability(spells: Array) -> void:
	for spell in spells:
		# Casting costs mana and the state machine refuses a new cast mid-action,
		# so each spell gets a clean idle frame and a full pool. Charging mana is
		# asserted exactly, one spell at a time, so the refill cannot hide a wrong
		# cost.
		_player.set("mana", 100.0)
		if not await _wait_until_idle():
			_fail("Never returned to IDLE before casting %s" % spell.id)
			return
		if not _arm(spell.id):
			continue
		var mana_before: float = _player.get("mana")
		if not _combat.request(&"cast"):
			_fail("%s was armed but the cast was refused" % spell.id)
			continue
		_check(
			_combat.active_spell != null and _combat.active_spell.id == spell.id,
			"Armed %s but the cast played %s" % [spell.id, _combat.active_spell.id if _combat.active_spell != null else "nothing"]
		)
		_check(
			_combat.casting_spell == spell.school_id,
			"Casting %s reported school %s" % [spell.id, _combat.casting_spell]
		)
		var spent := mana_before - float(_player.get("mana"))
		_check(
			is_equal_approx(spent, spell.mana_cost),
			"Casting %s charged %.1f mana, expected %.1f" % [spell.id, spent, spell.mana_cost]
		)


func _check_wheel_restores_time() -> void:
	_hud.open_wheel()
	_check(_hud.wheel_open, "The wheel did not report itself open")
	_check(Engine.time_scale < 1.0, "Opening the wheel did not slow time")
	# The wheel must confirm a SPELL and restore time. The school is derived from
	# the spell, so it is checked as a consequence, not as the input.
	var index := _wheel.sector_of(&"wind_step")
	_hud.aim_wheel(Vector2(cos(_wheel.sector_angle(index)), sin(_wheel.sector_angle(index))) * 200.0)
	_hud.close_wheel()
	_check(_combat.spell_id == &"wind_step", "Releasing on 风步 armed %s" % _combat.spell_id)
	_check(_combat.selected_school == &"wind", "风步 belongs to wind but armed school %s" % _combat.selected_school)
	_check(Engine.time_scale == 1.0, "Closing the wheel did not restore time")
	# And the readout has to name the spell, or the fix is invisible to a player.
	await process_frame
	_check(
		_hud.status_label.text.contains("风步"),
		"The HUD readout does not name the armed spell: '%s'" % _hud.status_label.text
	)


func _wait_until_idle(limit := 400) -> bool:
	for i in limit:
		if _combat.state == CombatController.State.IDLE:
			return true
		await process_frame
	return false


func _check(condition: bool, reason: String) -> void:
	if not condition:
		_failures.append(reason)


func _fail(reason: String) -> void:
	_failures.append(reason)
