extends SceneTree
# WEAPON SWITCH — the playtest gate's own regression.
#
# THE QUESTION THIS FILE ANSWERS. §5 says a weapon change must leave nothing behind:
# no orphan hitbox, no orphan chain. That sentence is easy to satisfy on the frame it is
# written and easy to lose on the frame after, because BOTH weapons are state machines
# that keep running whether or not anyone is holding them. The sword's move advances on
# its own clock and re-opens its hitbox when the timeline says to; the chain's head
# keeps travelling toward wherever it was thrown. Neither of them asks the slot before
# it does that. So the failure this file exists to catch is a body swinging a katana
# with a chain in its hand, and it is invisible in a screenshot and invisible to every
# single-weapon test ever written.
#
# WHY IT IS A TEST AND NOT A LOOK. Three of the four things below have no visual at all.
# A closed hitbox and a missing hitbox look identical. A buffered input that survived is
# a cut that happens a quarter of a second after you stopped expecting one. And the
# difference between "the chain was reset" and "the chain is still in the air" is a
# single frame of a head that is already leaving the screen.
#
# CLOCK. The chain's windows ride its own accumulated `state_time`, so this file takes
# its clock away (`manual_step`) and steps it itself, exactly as chain_integration does.
# The SWITCH's clock is the manager's `_process`, so anything waiting on the transition
# waits on idle frames rather than physics frames - a headless run does not guarantee
# one per physics tick, and a test that assumed it would pass on a fast machine and
# fail on a slow one.

const DT := 1.0 / 60.0
const MANAGER := preload("res://scripts/combat/weapon_manager.gd")

const WEAPON_ROOT := "CameraRig/LookPivot/MotionPivot/ShakePivot/WeaponRoot"
const SWORD_RIG := "CameraRig/LookPivot/MotionPivot/ShakePivot/WeaponRoot/TempSwordVisual"

var world: Node3D
var player: CharacterBody3D
var combat: CombatController
var chain: ChainDirector
var weapon: WeaponSlot
var manager: Node
var hitbox: Area3D
var weapon_root: Node3D
var sword_rig: Node3D
var failures: Array[String] = []
# Read off the registry rather than hard-coded, so the check below is about the
# REGISTRY being wired to real InputMap actions and not about two key codes.
var _registry: Array = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene: PackedScene = load("res://scenes/combat/CombatSandbox.tscn")
	world = scene.instantiate()
	root.add_child(world)
	await _wait(12)

	player = world.get_node("Player")
	combat = player.get_node("CombatController")
	chain = player.get_node("ChainDirector")
	weapon = player.get_node("WeaponSlot")
	hitbox = player.get_node(WEAPON_ROOT + "/SwordHitbox") as Area3D
	weapon_root = player.get_node(WEAPON_ROOT)
	sword_rig = player.get_node_or_null(SWORD_RIG)
	manager = player.get_node_or_null("WeaponManager")

	if manager == null:
		_fail("the Player has no WeaponManager, so no key can change the weapon (§1)")
		_finish()
		return

	# The chain is stepped by this file from here on. A window that is decided by the
	# machine's frame rate is not a window.
	chain.manual_step = true

	_check_the_registry_is_the_only_list()
	_check_the_keys_are_the_locked_map()
	await _check_the_same_weapon_is_a_no_op()
	await _check_leaving_the_sword_mid_swing()
	await _check_leaving_the_chain_mid_throw()
	await _check_a_queued_cut_dies_with_its_weapon()
	await _check_nothing_opens_the_hitbox_without_the_sword()
	await _check_a_cinematic_refuses_the_switch()
	await _check_the_switch_is_short()
	_check_both_weapons_are_never_drawn()

	_finish()


# ============================================================================
#  THE REGISTRY (§2)
# ============================================================================

func _check_the_registry_is_the_only_list() -> void:
	_registry = MANAGER.WEAPONS
	_check(
		_registry.size() == 3,
		"the registry holds %d weapons; expected sword + phantom_chain + mirror"
			% _registry.size()
	)
	_check(_registry[0]["id"] == &"sword", "slot 1 must be sword")
	_check(_registry[1]["id"] == &"phantom_chain", "slot 2 must be phantom_chain")
	_check(_registry[2]["id"] == &"mirror", "slot 3 must be mirror")
	# The interface §2 asks for by name. It is checked as a contract and not as a
	# formality: a caller that reaches for `current_weapon` and finds a variable instead
	# of an answer is the difference between two callers and a rule.
	for method in ["equip_weapon", "current_weapon", "can_switch_weapon", "get_current_weapon"]:
		_check(manager.has_method(method), "the manager has no %s() (§2)" % method)
	_check(
		manager.call("get_current_weapon") == manager.call("current_weapon"),
		"get_current_weapon() and current_weapon() disagree about what is in the hand"
	)


func _check_the_keys_are_the_locked_map() -> void:
	# §1: 1 is the sword and 2 is the chain, and the two actions exist so a rebind is a
	# change to the registry rather than a change to this file.
	for i in _registry.size():
		var action := StringName("weapon_%d" % (i + 1))
		_check(InputMap.has_action(action), "%s is not a bound action (§1)" % action)
		var events := InputMap.action_get_events(action)
		_check(
			events.size() > 0 and (events[0] as InputEventKey).physical_keycode == _registry[i]["key"],
			"%s is not bound to %s" % [action, OS.get_keycode_string(_registry[i]["key"])]
		)
	# §1 also says what the switch must NOT take, so the two keys it is most likely to
	# steal are checked where they are actually declared.
	_check_shift_is_dodge()


func _check_shift_is_dodge() -> void:
	# INPUT CONTRACT V0.1: Shift is dodge_sprint. Dodge fires immediately on Down;
	# Sprint is action_press'd after dodge recovery — Shift must NOT be a physical
	# binding on `sprint`, and `dodge` itself has no physical key (router-owned).
	var route := InputMap.action_get_events(&"dodge_sprint")
	_check(
		not route.is_empty() and (route[0] as InputEventKey).physical_keycode == KEY_SHIFT,
		"Shift is not bound to dodge_sprint; it is bound to %s"
			% ("nothing" if route.is_empty() else OS.get_keycode_string(
				(route[0] as InputEventKey).physical_keycode
			))
	)
	var sprint_events := InputMap.action_get_events(&"sprint")
	for ev in sprint_events:
		if ev is InputEventKey:
			_check(
				(ev as InputEventKey).physical_keycode != KEY_SHIFT,
				"sprint still has a physical Shift binding — InputContract must own Hold→Sprint"
			)
			break


# ============================================================================
#  THE SWITCH ITSELF
# ============================================================================

func _check_the_same_weapon_is_a_no_op() -> void:
	await _settle()
	await _take(WeaponSlot.SWORD)
	_check(weapon.is_sword(), "the rig does not start with the sword in hand")
	# §1: pressing `1` while holding the sword does NOTHING. It must not re-equip, and
	# it must not restart the sword's state - a key that resets the weapon it names is
	# a key that eats a combo.
	combat.request(&"light")
	await _wait_idle(4)
	var state_before := combat.state
	var move_before := combat.state_time
	_check(
		not bool(manager.call("equip_weapon", WeaponSlot.SWORD)),
		"equipping the weapon already in hand reported a change"
	)
	# A restart is observable as `state_time` going BACKWARDS to zero (`set_state` is
	# skipped for the same state, so `_restart_state` is what a re-equip would trigger).
	# Asserting "the clock advanced" instead would pass on a stopped clock, which is the
	# opposite of what is being claimed.
	_check(
		combat.state == state_before and combat.state_time >= move_before,
		"pressing the current weapon's key restarted the move that was already running "
		+ "(state_time %.3f -> %.3f)" % [move_before, combat.state_time]
	)
	combat.finish_action()
	await _wait_idle(2)


func _check_leaving_the_sword_mid_swing() -> void:
	await _settle()
	await _take(WeaponSlot.SWORD)
	combat.finish_action()
	combat.request(&"light")
	# Wait for the hitbox to actually be open. Without this the check below would pass
	# on a switch that happened before anything had started, which is the switch that
	# was never in question.
	var opened := false
	for i in 60:
		await _wait_idle(1)
		if combat.hitbox_open:
			opened = true
			break
	_check(
		opened,
		"the sword's light attack never opened its hitbox, so this check is not testing "
		+ "a switch out of a live swing"
	)

	_check(
		bool(manager.call("equip_weapon", WeaponSlot.PHANTOM_CHAIN)),
		"the switch to phantom chain was refused"
	)
	# §5's cleanup is on the FRAME OF THE PRESS — hitbox closed, move cleared,
	# state IDLE — and it has to be, because a cut must not survive a weapon change
	# for even one frame. The SLOT is not, and deliberately so: the sword is
	# SHEATHED first (§3, 0.4-0.8s) and the rig has to stay visible while the blade
	# goes home, or the put-away is a sword vanishing instead of being put away.
	await _wait_idle(1)
	_check(
		not combat.hitbox_open and combat.active_move == null \
			and combat.state == CombatController.State.IDLE,
		"the sword's swing survived the frame of the weapon change"
	)
	await _finish_switch()

	_check(weapon.is_phantom_chain(), "the slot did not take phantom chain")
	_check(not combat.hitbox_open, "the sword's hitbox stayed open after the weapon changed hands")
	_check(
		hitbox.monitoring == false,
		"the sword's hitbox is still listening for hurtboxes while phantom chain is in hand"
	)
	_check(
		combat.state == CombatController.State.IDLE,
		"the sword is in %s after being put away" % String(CombatController.State.keys()[combat.state])
	)
	_check(
		combat.active_move == null,
		"a sword move is still in flight with phantom chain in hand"
	)
	# ...AND IT STAYS THAT WAY. The frame the switch happens on is the easy one; the
	# failure mode is the move's own timeline re-opening the hitbox two frames later,
	# from a state machine that never asked whether anyone is holding it.
	var reopened := -1
	for i in 40:
		await _wait_idle(1)
		if combat.hitbox_open:
			reopened = i
			break
	_check(
		reopened < 0,
		"the sword's hitbox re-opened %d idle frames after phantom chain came out" % reopened
	)


func _check_leaving_the_chain_mid_throw() -> void:
	await _settle()
	await _take(WeaponSlot.CHAIN)
	chain.reset()
	await _wait(2)
	_check(chain.is_equipped(), "the chain is not equipped for the throw check")

	var started := chain.request(&"chain_hook")
	_check(started, "the chain refused a throw while it was the weapon in hand")
	for i in 12:
		chain.step(DT)
	_check(
		chain.radius > chain.moveset.home_radius * 1.5,
		"the chain never left the hand (radius %.2fm), so there is nothing to orphan"
			% chain.radius
	)

	_check(bool(manager.call("equip_weapon", WeaponSlot.SWORD)), "the switch back to the sword was refused")
	# Coming the other way there is no sheathe to run — the chain has no scabbard —
	# but there IS a draw: the slot takes the sword at once and the blade then comes
	# out over `DRAW_SECONDS`. So the slot check is immediate and the wait is on the
	# rig reaching a usable pose.
	await _wait_idle(2)
	_check(weapon.is_sword(), "the slot did not take the sword")
	_check(combat.equip_blend > 0.0, "the sword was taken but never began leaving the saya")
	await _finish_draw()
	# §5, the other half: a chain mid-throw is the state most likely to outlive its
	# owner, because the head is already somewhere else and nothing about the pixels
	# says who owns it.
	_check(
		chain.state == ChainDirector.State.HELD,
		"a throw was in flight when the weapon changed and the chain is in %s"
			% String(ChainDirector.State.keys()[chain.state])
	)
	_check(not chain.is_hooked(), "the chain is still attached to a target after being put away")
	_check(
		is_equal_approx(chain.radius, chain.moveset.home_radius),
		"the head came back at %.2fm instead of its resting %.2fm"
			% [chain.radius, chain.moveset.home_radius]
	)
	_check(
		not chain.chain_visual.is_drawn(),
		"the chain is still drawn while the sword is in hand"
	)
	# And it must not keep travelling on its own clock now that nobody owns it.
	var radius_after := chain.radius
	for i in 10:
		chain.step(DT)
	_check(
		is_equal_approx(chain.radius, radius_after),
		"the thrown head kept moving after the weapon changed (%.2fm -> %.2fm)"
			% [radius_after, chain.radius]
	)


func _check_a_queued_cut_dies_with_its_weapon() -> void:
	await _settle()
	await _take(WeaponSlot.SWORD)
	combat.finish_action()
	# §18 FIRST, because it is what makes the rest of this check meaningful. A
	# press made two frames into a swing is DROPPED, not remembered. Note that in
	# V2 the light attack's own cancel window (0.34 of the pose span) opens well
	# BEFORE the buffer window (0.62), so the early input a player actually wants
	# still lands - as a cancel, on the spot, which is strictly better than a
	# queue. The buffer is what catches an input that CANNOT start yet, and the
	# thing that must not survive a weapon change is any of it.
	combat.request(&"light")
	await _wait_idle(2)
	var running := combat.active_move_id
	_check(running != &"", "the first press started nothing")
	combat.request(&"light")
	_check(
		combat.buffer.pending == &"",
		"an input two frames into a swing was remembered; §18 opens the buffer only "
		+ "near the end of a move"
	)
	_check(
		combat.active_move_id == running,
		"an early press started a second cut instead of being dropped"
	)

	# ...NOW THE HALF THAT IS §5's. Whatever the blade was doing, and whatever it
	# had remembered, must not survive the hand-off.
	manager.call("equip_weapon", WeaponSlot.PHANTOM_CHAIN)
	await _wait_idle(1)
	_check(combat.buffer.pending == &"", "a remembered input survived the weapon change")
	_check(combat.active_move == null, "a cut was still running on the frame the weapon changed")
	combat.request(&"light")
	await _wait_idle(1)
	_check(
		combat.active_move == null and combat.buffer.pending == &"",
		"the blade started a cut while it was being put away"
	)
	await _finish_switch()
	_check(combat.combo_index == 0, "the combo memory outlived the sword (§17)")

	# ...AND THE COMBO MEMORY IS THE OTHER HALF OF §17. Coming back to the sword,
	# the first cut is A1 - not the cut after the one the player was on when they
	# put it away. "Continue my chain" is not a promise a sword makes from inside
	# its scabbard, and the failure mode without this is the worst kind: the
	# player presses once after a weapon swap and gets A3, a three-cut iaido
	# domain, out of nowhere.
	await _take(WeaponSlot.SWORD)
	combat.request(&"light")
	await _wait_idle(1)
	_check(
		combat.active_move_id == combat.moveset.light_chain[0],
		"the first cut after a weapon round trip was %s instead of A1 (§17)"
			% String(combat.active_move_id)
	)
	_check(
		combat.combo_index == 1,
		"the combo counter restarted at %d instead of 1 (§17)" % combat.combo_index
	)
	combat.finish_action()
	await _wait_idle(2)


func _check_nothing_opens_the_hitbox_without_the_sword() -> void:
	# THE STRUCTURAL HALF OF §5, and the only check here that can fail on a body with a
	# perfectly clean switch. `stow()` puts the sword away, but `_process_move()` does
	# not ask who is holding it - so any path that starts a sword move without going
	# through the slot's gate (the combat lab's buttons, a buffered action, a future
	# caller) gets a hitbox that opens on a player holding a chain.
	await _settle()
	await _take(WeaponSlot.CHAIN)
	_check(weapon.is_chain(), "the chain is not in hand for the hitbox-ownership check")

	combat.request(&"light")
	var leaked := -1
	for i in 45:
		await _wait_idle(1)
		if combat.hitbox_open:
			leaked = i
			break
	_check(
		leaked < 0,
		"a sword move started while the chain was in hand, and its hitbox opened %d idle "
		% leaked
		+ "frames later - a blade nobody is holding is landing hits"
	)


func _check_a_cinematic_refuses_the_switch() -> void:
	await _settle()
	await _take(WeaponSlot.SWORD)
	# The ceremony owns the camera, the clock and the blade's transform, so a switch
	# inside it would leave the director driving a rig it no longer owns. Everything
	# else - throw, retract, orbit, recovery - must be interruptible, which is why this
	# is the only refusal.
	combat.set_state(CombatController.State.IAIDO)
	_check(not bool(manager.call("can_switch_weapon")), "a weapon switch was allowed during 居合")
	_check(
		not bool(manager.call("equip_weapon", WeaponSlot.PHANTOM_CHAIN)),
		"a weapon switch succeeded during 居合, mid-ceremony"
	)
	_check(weapon.is_sword(), "the weapon changed during 居合 anyway")
	combat.set_state(CombatController.State.IDLE)
	await _wait(2)
	_check(
		bool(manager.call("can_switch_weapon")),
		"the switch is still refused after the ceremony ended, so the refusal never clears"
	)


## TWO SPEEDS, AND BOTH ARE SPEC (§6 for a bare hand-off, §3 of SWORD
## PRESENTATION V3 for the sword).
##
## A weapon that arrives with nothing to do gets the short raise: 0.15-0.30s, one
## motion, no flourish. A SWORD does not arrive, it is TAKEN OUT OF SOMETHING, and
## §2 gives every sword-facing entry point — equip, inspect, A1, A3, iaido, the
## weapon switch — ONE draw-and-sheathe contract. §3 sizes that contract at
## **1.2-2.0 s**, with a 200 ms pause and a 120 ms glint inside it.
##
## THE ASSERTION IS STRONGER THAN IT WAS. It used to check a literal 0.40-0.80s
## band against a number typed in `weapon_manager.gd`, which could only ever catch
## a typo. It now checks two things that can actually drift apart: that the
## duration is inside the brief's band, AND that the manager's copy equals the
## length of the move the controller is really running. Those are two owners of one
## number, and if a future retune moves the beats without moving the constant, this
## fails instead of the switch quietly drawing a shorter sword than R does.
func _check_the_switch_is_short() -> void:
	await _settle()
	await _take(WeaponSlot.SWORD)
	var seconds: float = MANAGER.SWITCH_SECONDS
	_check(
		seconds >= 0.15 and seconds <= 0.30,
		"a bare hand-off takes %.2fs; §6 asks for 0.15-0.30s" % seconds
	)
	var sentence: float = SwordBasic.equip().total_time()
	for row in [
		{"name": "DRAW_SECONDS", "value": float(MANAGER.DRAW_SECONDS)},
		{"name": "SHEATHE_SECONDS", "value": float(MANAGER.SHEATHE_SECONDS)},
	]:
		_check(
			row["value"] >= 1.2 and row["value"] <= 2.0,
			"%s is %.2fs; §3 asks for 1.20-2.00s for the sword's own two directions"
				% [row["name"], row["value"]]
		)
		_check(
			is_equal_approx(row["value"], sentence),
			"%s is %.2fs but the five-beat sentence is %.2fs — the switch and the "
				% [row["name"], row["value"], sentence]
				+ "R-key draw are two owners of one number and they have drifted"
		)

	# ...and the sheathe really is what delays the slot, rather than a number that
	# happens to be in range. If the slot took phantom chain on the frame of the press
	# then the put-away is a `visible = false` wearing a duration.
	manager.call("equip_weapon", WeaponSlot.PHANTOM_CHAIN)
	_check(
		weapon.is_sword(),
		"the slot took phantom chain on the frame of the press, so there is no sheathe"
	)
	_check(
		float(combat.equip_blend) > 0.5,
		"the blade was already home on the frame of the press (equip_blend %.2f)"
			% float(combat.equip_blend)
	)
	await _finish_switch()
	_check(weapon.is_phantom_chain(), "the sheathe never delivered phantom chain")
	_check(
		float(combat.equip_blend) <= 0.001,
		"phantom chain is in hand with the blade still out (equip_blend %.2f)"
			% float(combat.equip_blend)
	)

	# NEITHER DIRECTION IS ALLOWED TO BE A POP, and the two directions fail in two
	# different ways. The sword's direction is the DRAW, and its observable is the
	# blend: a blend that jumps 0 -> 1 between two frames is a sword appearing in
	# the hand, however long the constant on the wall says the draw is.
	manager.call("equip_weapon", WeaponSlot.SWORD)
	var saw_middle := false
	var spent := 0.0
	while spent < _switch_budget():
		spent += await _wait_delta(1)
		var blend := float(combat.equip_blend)
		if blend > 0.08 and blend < 0.92:
			saw_middle = true
		if blend >= 0.999 and not _pending_or_switching():
			break
	_check(saw_middle, "the blade went from home to hand without passing through a draw")
	await _wait_idle(2)
	_check(
		is_zero_approx(weapon_root.position.y),
		"the weapon was left at y = %.3f instead of its home pose" % weapon_root.position.y
	)

	# ...AND THE OTHER DIRECTION ARRIVES ON A RAISE. Coming back from the sword
	# there is no draw - there is a sheathe, and THEN the incoming weapon has to
	# come up rather than appear where the blade used to be. §6's 0.18s is the
	# same number; what changes is that it starts only once the blade is home,
	# because a raise under the sheathe would drag the blade that is still
	# travelling to its mouth.
	manager.call("equip_weapon", WeaponSlot.PHANTOM_CHAIN)
	_check(weapon.is_sword(), "the sheathe did not delay the slot for the raise check")
	# Same trap, same fix: the raise cannot be observed inside a frame count that
	# was sized for a 0.55 s put-away, because it only STARTS once the 1.60 s one
	# is finished. The budget is the sentence plus the raise, spent in game time.
	var budget := _switch_budget()
	var dipped := 0.0
	var raise_spent := 0.0
	while raise_spent < budget:
		raise_spent += await _wait_delta(1)
		dipped = minf(dipped, weapon_root.position.y)
		if not _pending_or_switching():
			break
	_check(
		dipped < -0.01,
		"the incoming weapon never moved (deepest y = %.3f), so the switch is a pop"
			% dipped
	)
	await _wait_idle(2)
	_check(
		is_zero_approx(weapon_root.position.y),
		"the incoming weapon was left at y = %.3f instead of its home pose"
			% weapon_root.position.y
	)


## Waits out a sheathe AND the raise that follows it, and fails loudly rather
## than hanging if it never ends.
##
## ===========================================================================
## THE GUARD IS A TIME BUDGET, NOT A FRAME COUNT
## ===========================================================================
## It used to be `frames < 240`, and 240 was chosen when a put-away cost 0.55 s.
## That is the trap this helper existed to avoid and then walked into: a frame
## count is only a duration if the frame rate is known, and `_wait_idle` awaits
## `process_frame`, which headless runs as fast as it can. So the guard silently
## meant "about 1.5 s" on the machine it was written on and something else
## everywhere afterwards.
##
## SWORD PRESENTATION V3 made a put-away 1.60 s, and the guard did not fail
## because the switch broke — it failed because the number was never a duration.
## It is one now: the test spends GAME SECONDS, accumulated from the same delta
## the game itself runs on, and the budget is derived from the move rather than
## from a memory of how long things used to take.
func _finish_switch() -> void:
	var budget := SwordBasic.equip().total_time() + MANAGER.SWITCH_SECONDS
	var spent := 0.0
	while _pending_or_switching() and spent < budget * 2.0 + 1.0:
		spent += await _wait_delta(1)
	_check(
		spent < budget * 2.0 + 1.0,
		"a weapon put-away never finished (%.2fs of a %.2fs budget)" % [spent, budget]
	)
	await _wait_idle(2)


func _pending_or_switching() -> bool:
	return String(manager.get("_pending_slot")) != "" or bool(manager.get("switching"))


## Waits out a draw. Fails loudly on a draw that never arrives.
##
## It only waits while the SWORD is the weapon in hand: "the blade has been
## drawn" is a question about a sword, and asking it of a chain would wait out
## the whole guard on a blend that is correctly and permanently zero.
func _finish_draw() -> void:
	var spent := 0.0
	while manager.call("current_weapon") == &"sword" \
		and (bool(manager.get("drawing_in")) or float(combat.equip_blend) < 0.999) \
		and spent < _switch_budget():
		spent += await _wait_delta(1)
	_check(spent < _switch_budget(), "a weapon draw never finished (%.2fs)" % spent)


## The game-time budget every move-shaped wait in this file is allowed, derived
## from the sword's own sentence rather than from a frame count.
##
## See `_finish_switch` for why. This is the one place the number is written, and
## it is written as an expression over the two durations it is a budget for — so
## retuning the draw moves the guards with it instead of leaving four tests
## asserting a duration nobody can find.
func _switch_budget() -> float:
	return (SwordBasic.equip().total_time() + MANAGER.SWITCH_SECONDS) * 2.0 + 1.0


## Puts `weapon_id` in the hand THROUGH THE MANAGER, and waits for it to arrive.
##
## Several checks below are ABOUT the draw, so their setup cannot be allowed to
## skip it: a scene armed by calling `WeaponSlot.equip()` directly is a scene
## where the slot and the rig may disagree, and the first thing the check then
## measures is the disagreement rather than the switch.
func _take(weapon_id: StringName) -> void:
	if manager.call("current_weapon") == weapon_id:
		if weapon_id != &"sword" or float(combat.equip_blend) >= 0.999:
			return
		# The slot already says sword but the rig never finished arriving - a
		# foreign writer or a previous check left it that way. There is no
		# transition in flight to wait on, so snapping is the only honest end.
		manager.call("reset_weapons")
		return
	manager.call("equip_weapon", weapon_id)
	await _finish_switch()
	await _finish_draw()


func _check_both_weapons_are_never_drawn() -> void:
	# The seam between two weapons is where "held" stops meaning anything. Both rigs are
	# children of the same hand root, so nothing but this rule stops a chain from being
	# carried alongside a drawn blade - the same defect that used to be permanent when
	# the sandbox hid the sword and no other scene did.
	if sword_rig == null:
		_fail("the sword rig is not where this test expects it, so visibility is unchecked")
		return
	weapon.equip(WeaponSlot.SWORD)
	_check(sword_rig.visible, "the sword is in hand but its rig is hidden")
	_check(not chain.chain_visual.is_drawn(), "the chain is drawn while the sword is in hand")
	weapon.equip(WeaponSlot.CHAIN)
	_check(not sword_rig.visible, "the sword rig is still drawn while the chain is in hand")
	_check(chain.chain_visual.is_drawn(), "the chain is in hand but nothing is drawn")
	var phantom: Node = player.get_node_or_null("PhantomChainController")
	weapon.equip(WeaponSlot.PHANTOM_CHAIN)
	_check(not sword_rig.visible, "the sword rig is still drawn while phantom chain is in hand")
	_check(not chain.chain_visual.is_drawn(), "star-bind chain is still drawn under phantom chain")
	_check(phantom != null and bool(phantom.call("is_equipped")), "phantom chain did not equip")
	weapon.equip(WeaponSlot.SWORD)
	_check(
		phantom == null or phantom.call("debug_state").get("state") == "STOWED",
		"phantom chain did not stow when the sword returned"
	)


# ============================================================================
#  HARNESS
# ============================================================================

## Waits out a switch in progress. Every check that starts by equipping has to funnel
## through this, or a refusal from the previous check looks like a failure of the next.
## A sheathe counts as in-progress even though `switching` is still false while it runs,
## which is why this asks the pair and not the flag.
func _settle() -> void:
	var spent := 0.0
	while _pending_or_switching() and spent < _switch_budget():
		spent += await _wait_delta(1)


func _wait(frames: int) -> void:
	for i in frames:
		await physics_frame


## The manager runs on `_process`, so its clock is idle frames. A headless run does not
## guarantee an idle frame per physics tick.
func _wait_idle(frames: int) -> void:
	for i in frames:
		await process_frame


## Waits `frames` render frames and reports how much GAME TIME that cost.
##
## The companion `_wait_idle` never had. Any guard written as a frame count is
## really a duration with the frame rate baked in, and headless has no frame rate
## worth baking in — it runs `process_frame` as fast as it can, so 240 frames is
## 0.3 s on one machine and 2 s on another. A test that needs to say "wait a
## second" has to be able to ask what a second cost, which is this.
func _wait_delta(frames: int) -> float:
	var spent := 0.0
	for i in frames:
		spent += root.get_process_delta_time()
		await process_frame
	return spent


func _check(condition: bool, reason: String) -> void:
	if not condition:
		failures.append(reason)


func _fail(reason: String) -> void:
	failures.append(reason)


func _finish() -> void:
	if failures.is_empty():
		print(
			"PASS: the weapon changes hands cleanly - nothing is left swinging, flying, "
			+ "queued or drawn that the player is no longer holding"
		)
		quit(0)
		return
	for reason in failures:
		print("  - " + reason)
		push_error(reason)
	print("FAIL: %d problem(s)" % failures.size())
	quit(1)
