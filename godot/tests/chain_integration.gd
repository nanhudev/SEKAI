extends SceneTree
# 缚星链 / STAR-BIND CHAIN — phase 0–1 acceptance.
#
# THE QUESTION THIS FILE ANSWERS (brief §53) is not "does it compile". It is
# "IS THE CHAIN FUN?" — and phase 1 answers that with exactly four things a sword
# cannot do: SWEEP, MOMENTUM, TENSION, HOOK. Every check below fails if the chain
# quietly degrades into "a sword with more reach", which §59 calls a design
# failure. §52's forbidden list is checked too, because the fastest way to lose
# the argument is to add a second chain or an ultimate and call it progress.
#
# WHY A TEST AND NOT A SCREENSHOT: three of the four are invisible in a still
# frame. Momentum only exists as a CHANGE in arrival time. Tension only exists as
# a CHANGE in which inputs do something. A hook's weight class only exists as the
# DIFFERENCE between two applications of the same input. And the three worst bugs
# found while writing this file all look completely normal in a picture: the head
# was swinging at the height of an enemy's HAT, the Chain Lab's deck was reachable
# only by teleport, and 地砸 was in the data with no input that could reach it.
#
# CLOCK: the chain's windows ride its own accumulated `state_time`, so this file
# takes the clock away (`manual_step`) and steps it itself. A bind window of 0.40s
# is a design decision, and a test that has to land inside one must not depend on
# how many frames a shared machine manages per second.

const DT := 1.0 / 60.0
# Somewhere no throw, sweep or orbit can reach. Targets are parked rather than
# deleted so the stage keeps the population it will have in play.
const PARK := Vector3(60.0, 0.0, 0.0)

var world: Node3D
var player: CharacterBody3D
var dummy: Node3D
var combat: CombatController
var chain: ChainDirector
var weapon: WeaponSlot
var lab: ChainLab
var moveset: ChainMoveset
# The chain's own aim reference. The test sets its pitch directly, because a headless
# run has no mouse to look up with — and the pitch IS the input this check is about.
var look_pivot: Node3D
var failures: Array[String] = []
var started: Array[StringName] = []
var landed: Array[Dictionary] = []
# Every yank the weapon announces, and every wall it announces hitting. These are the
# events §49 says the audio line needs as EVENTS — a rhythm inferred from a state
# machine is not a rhythm, and nothing would notice if the weapon stopped emitting
# them until the day someone tried to place a sound against one.
var tugs_seen: Array[int] = []
var walls_seen: Array[float] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene: PackedScene = load("res://scenes/combat/CombatSandbox.tscn")
	world = scene.instantiate()
	root.add_child(world)
	await _wait(12)

	player = world.get_node("Player")
	dummy = world.get_node("TechnicalDummy")
	combat = player.get_node("CombatController")
	weapon = player.get_node("WeaponSlot")
	chain = player.get_node("ChainDirector")
	look_pivot = player.get_node("CameraRig/LookPivot") as Node3D
	lab = world.get("chain_lab") as ChainLab
	if lab == null:
		_fail("The sandbox has no ChainLab, so the chain has no stage (§39)")
		_finish()
		return

	moveset = chain.moveset
	chain.manual_step = true
	chain.move_started.connect(_on_move_started)
	chain.hit_landed.connect(_on_hit_landed)
	chain.tug.connect(_on_tug)
	chain.wall_impact.connect(_on_wall_impact)
	_park_everything()

	# --- what the weapon is, before how it feels ----------------------------
	_check_slot_owns_the_weapon()
	_check_no_rigid_links()
	_check_phase_one_has_not_sneaked_in()
	_check_every_authored_knob_is_wired()
	await _check_momentum_buys_time_not_damage()

	# --- the four things ----------------------------------------------------
	await _check_sweep_hits_two_and_is_wide()
	await _check_the_second_cut_carries_the_first()
	await _check_a_whiff_costs_the_spin()
	# --- §43 THE FEEL PASS --------------------------------------------------
	await _check_landing_costs_the_head_its_spin()
	await _check_the_return_swings_before_it_comes_home()
	await _check_the_throw_ends_taut()
	await _check_tension_is_in_the_line_and_the_camera()
	await _check_tension_deletes_the_normal_inputs()
	await _check_the_weight_table()
	await _check_the_bind_is_a_window()
	await _check_an_anchor_pulls_the_player()
	await _check_the_wall_stops_the_head()
	await _check_wind_is_spin_and_frost_is_leverage()
	await _check_a_pull_moves_the_distance_it_states()
	await _check_the_pull_is_a_haul_not_a_magnet()
	await _check_deflect_is_not_a_sword_parry()

	# --- the stage ----------------------------------------------------------
	await _check_the_lab_is_reachable_on_foot()
	_check_the_lab_can_drive_every_action()
	_check_the_numbers_are_a_developer_readout()
	await _check_the_high_anchor_can_be_hooked()

	# --- what the player actually sees --------------------------------------
	await _check_the_chain_is_drawn_where_it_is()

	weapon.equip(WeaponSlot.SWORD)
	_finish()


# ============================================================================
#  WHAT THE WEAPON IS
# ============================================================================

# 玩家没有职业，只有经历 (§0). One slot, two weapons, and the chain must be inert
# while the sword is out — otherwise a chain technique could fire while the player
# is swinging a katana, and "which weapon am I holding" would stop having an answer.
func _check_slot_owns_the_weapon() -> void:
	_check(weapon.is_sword(), "the player does not start with the sword")
	_check(not chain.is_equipped(), "the chain is live while the sword is out")
	_check(not chain.request(&"light"), "a chain cut was accepted while the sword was out")
	_check(not chain.chain_visual.is_drawn(), "the chain is drawn while the sword is out")
	_check(weapon.equip(WeaponSlot.CHAIN), "the slot refused to take the chain")
	_check(chain.is_equipped(), "the chain is not equipped after equipping it")
	_check(chain.chain_visual.is_drawn(), "the chain is equipped but not drawn")
	# ...AND THE OTHER HAND HAS TO BE EMPTY. The sword's rig is a child of the same
	# hand root and nothing took it away when the slot changed, so the chain used to
	# be held alongside a drawn 95cm blade, permanently. No chain test could have
	# seen it: the sword appears in nobody's chain assertion, which is exactly why it
	# survived — the same way a missing hidden-object check survives a lighting test.
	var sword_rig := player.get_node_or_null(
		"CameraRig/LookPivot/MotionPivot/ShakePivot/WeaponRoot/TempSwordVisual"
	) as Node3D
	_check(sword_rig != null, "the player has no sword rig, so this check proves nothing")
	if sword_rig != null:
		_check(not sword_rig.visible, "the sword is still drawn while the chain is equipped")
	_check(not chain.request(&"chain_lock"), "缚 was accepted with nothing hooked")
	# A switch back must not leave a chain hanging in the air or bank momentum for
	# whoever picks it up later.
	chain.momentum = 0.8
	chain.request(&"light")
	weapon.equip(WeaponSlot.SWORD)
	_check(not chain.is_equipped(), "the chain is still equipped after switching away")
	_check(
		chain.state == ChainDirector.State.HELD and chain.momentum == 0.0,
		"switching weapons left the chain running (state %s, spin %.2f)"
			% [String(ChainDirector.State.keys()[chain.state]), chain.momentum]
	)
	_check(not chain.chain_visual.is_drawn(), "the chain is still drawn after switching away")
	if sword_rig != null:
		_check(sword_rig.visible, "the sword is not drawn after switching back to the sword")
	weapon.equip(WeaponSlot.CHAIN)


# §5 is a HARD RULE, not a preference: "do NOT make 20 RigidBody3D chain links the
# gameplay core". The check is structural on purpose — a chain that grows a physics
# link per segment still passes every feel test right up until it does not.
func _check_no_rigid_links() -> void:
	var bodies := 0
	for child in chain.get_children():
		if child is RigidBody3D:
			bodies += 1
		for grandchild in child.get_children():
			if grandchild is RigidBody3D:
				bodies += 1
	_check(bodies == 0, "the chain is driving %d rigid bodies — §5 forbids exactly this" % bodies)
	_check(moveset.links >= 8, "the chain draws only %d links, which is not a chain" % moveset.links)
	# The whole weapon is one head described in polar form, so the three variables
	# are the interface. The count matters: a fourth would mean the design sprawled.
	_check(chain.radius > 0.0, "the head has no radius, so it has no position")


# §52: dual chain, body wrapping, rope knots, climbing, grappling traversal, ten
# skills, an ultimate, a cinematic signature, UE5 VFX. All of it later.
func _check_phase_one_has_not_sneaked_in() -> void:
	_check(ChainLibrary.ids().size() == 1, "there is more than one chain weapon")
	# ONE chain, not two: a single handle, a single drawing, a single head.
	var visuals := 0
	for child in chain.get_children():
		if child is ChainVisual:
			visuals += 1
	_check(visuals == 1, "there are %d chain visuals — dual chain is phase 2 (§1)" % visuals)
	var named := 0
	for id in moveset.moves.keys():
		var move := moveset.get_move(id)
		if move != null and move.display_name != "":
			named += 1
	_check(named <= 12, "the chain already has %d named techniques, which is a skill list, not a prototype" % named)


# A knob nobody reads is worse than no knob: it will be tuned and silently ignored.
# This caught three — steer, the per-move camera kick and orbit_min_hold.
func _check_every_authored_knob_is_wired() -> void:
	var profile := moveset.get_move(&"ch_sweep")
	_check(profile != null and profile.steer > 0.0, "横缚 cannot be steered (§28)")
	_check(
		profile != null and not is_zero_approx(profile.fov_kick) and not is_zero_approx(profile.roll_kick),
		"横缚 has no camera language"
	)
	_check(
		moveset.orbit_min_hold > 0.0 and moveset.orbit_min_hold < 0.4,
		"the orbit has no minimum commitment, so a tap fires 蓄势回旋"
	)
	# The pulled side of a hook is a DISTANCE. A speed here would only mean anything
	# to whoever owns the decay, which is why there is no such field any more.
	_check(
		not _has_property(moveset, "player_pull_speed"),
		"the moveset still expresses the player's pull as a speed, which reads as nothing"
	)


# MOMENTUM BUYS TIME AND A LITTLE REACH, NEVER A BIGGER NUMBER (§12/§59). This is
# the single check that decides whether the chain teaches SPACE or is just a long
# sword, so it is asserted twice: on the data, and by measuring the head.
func _check_momentum_buys_time_not_damage() -> void:
	var move := moveset.get_move(&"ch_return")
	if move == null:
		_fail("返扫 does not exist")
		return
	var slow := move.active_seconds(0.0)
	var fast := move.active_seconds(1.0)
	_check(fast < slow * 0.92, "spin barely shortens the arc (%.3fs vs %.3fs)" % [fast, slow])
	# And the reward is NOT a damage stat. If a chain move ever grows a
	# momentum-scaled multiplier this fails — by design, not by accident.
	for id in moveset.moves.keys():
		var profile := moveset.get_move(id)
		_check(
			not _has_property(profile, "momentum_damage") and not _has_property(profile, "damage_scale"),
			"%s scales its damage with momentum, which makes it a sword with reach" % String(id)
		)
	_check(
		moveset.radius_momentum_scale > 0.0 and moveset.radius_momentum_scale <= 0.25,
		"momentum changes reach by %.0f%%, which is the whole weapon"
			% (moveset.radius_momentum_scale * 100.0)
	)
	# The measured version: at the same elapsed time, the spun-up head is FURTHER
	# round its arc than the cold one. This is the entire reward for keeping the
	# chain moving, and it is a feel change rather than a number.
	await _park_everything()
	await _stand(Vector3(0.0, 1.0, -22.0), Vector3(0.0, 0.0, -1.0))
	var cold := await _measure_arc_progress(0.0)
	var hot := await _measure_arc_progress(1.0)
	_check(
		cold > 0.1 and hot > cold * 1.1,
		"after the same 10 frames the cold head travelled %.2frad and the spun-up one %.2frad — spin buys nothing"
			% [cold, hot]
	)


# ============================================================================
#  1 · SWEEP
# ============================================================================

# §9: 横缚 is fast and WIDE — 120–160° — and the point of a wide sweep is that it
# hits more than one thing. Two enemies in one arc is the weapon's whole promise.
func _check_sweep_hits_two_and_is_wide() -> void:
	await _park_everything()
	var left := _place_target(&"light", Vector3(-1.35, 0.0, -24.8))
	var right := _place_target(&"medium", Vector3(1.35, 0.0, -24.8))
	if left == null or right == null:
		return
	await _stand(Vector3(0.0, 1.0, -22.0), Vector3(0.0, 0.0, -1.0))
	var profile := moveset.get_move(&"ch_sweep")
	_check(
		profile.arc_degrees >= 120.0 and profile.arc_degrees <= 160.0,
		"横缚 sweeps %.0f°, outside the authored 120–160°" % profile.arc_degrees
	)
	var before_l: float = left.get("health")
	var before_r: float = right.get("health")
	landed.clear()
	chain.reset()
	_check(chain.request(&"light"), "the light attack was refused")
	await _tick(40)
	_check(chain.hits_landed >= 2, "one 横缚 landed %d time(s) — a wide sweep has to be wide" % chain.hits_landed)
	_check(left.get("health") < before_l, "the left target was never touched")
	_check(right.get("health") < before_r, "the right target was never touched")
	_check(landed.size() >= 2, "the sweep delivered %d hits through the real hurtbox path" % landed.size())


# §10/§12: 返扫 CARRIES the first cut's momentum. No reset, no teleport, no second
# wind-up. The only way to prove that is to watch the head the whole way through
# and fail on a single frame where it jumps.
func _check_the_second_cut_carries_the_first() -> void:
	await _park_everything()
	await _stand(Vector3(0.0, 1.0, -22.0), Vector3(0.0, 0.0, -1.0))
	chain.reset()
	started.clear()
	var heads: Array[Vector3] = []
	# The move that produced each step. Sampled after the request and before the
	# step, so `labels[s]` names the animation behind `heads[s] → heads[s + 1]`.
	var labels: Array[StringName] = []
	var slam_frame := -1
	chain.request(&"light")
	var guard := 0
	while guard < 600:
		guard += 1
		await physics_frame
		# Ask for the next cut every frame. Whether that is legal is the weapon's
		# answer, not the test's, so this exercises the real cancel window.
		if started.size() < 3:
			chain.request(&"light")
			if started.size() >= 3:
				slam_frame = guard
		labels.append(chain.active_move.id if chain.active_move != null else &"")
		heads.append(chain.head_position())
		chain.step(DT)
		if slam_frame > 0 and guard >= slam_frame + 20:
			break
	_check(started.size() >= 3, "the light chain produced %d cut(s)" % started.size())
	if started.size() >= 3:
		_check(
			started[0] == &"ch_sweep" and started[1] == &"ch_return" and started[2] == &"ch_slam",
			"the light chain went %s, so 横/横/纵 is not the order" % str(started)
		)
	var reverse := moveset.get_move(&"ch_return")
	if reverse == null:
		_fail("返扫 does not exist")
		return
	# THE CARRY (§7). 返扫 has to pick the head up where the first cut left it and
	# unwind from there — no reset, no second wind-up.
	#
	# WHAT THAT IS NOT is "the head barely moves". 返扫 opens with a deliberate 26° of
	# OVERRUN along cut 1's own direction (`carry_anticipation_degrees`), which at
	# 3.6m radius is 1.7m of travel — the head MUST travel, or the handover is exactly
	# the dead beat this check exists to catch. Distance alone therefore cannot be the
	# question, and the first version of this check asked it: it demanded < 1.0m and
	# passed only while the handover was dead. The two things that can actually go
	# wrong are the two measured here.
	#
	#   DIRECTION — a re-authored start pose turns the head away from where it was
	#               already going, and it does it inside a single frame.
	#   DEADNESS  — a handover with no overrun authored has nothing to travel, so the
	#               first frame after the cut is a frame with no motion in it.
	var carry_start := -1
	for s in labels.size():
		if labels[s] == &"ch_return":
			carry_start = s
			break
	if carry_start < 2 or carry_start + 2 >= heads.size():
		_fail("返扫 never started, or has no frames either side to read a carry from")
		return
	var before := heads[carry_start - 1] - heads[carry_start - 2]
	var after := heads[carry_start + 1] - heads[carry_start]
	_check(
		before.dot(after) > 0.0,
		"返扫 turned the head %.0f° inside one frame of the cut — the start pose was \
re-authored rather than carried (§7)"
			% rad_to_deg(before.angle_to(after))
	)
	_check(
		after.length() > 0.05,
		"the head travelled %.3fm in 返扫's first frame — the handover is a dead beat, \
which is the three-tweened-swings read of §8"
			% after.length()
	)
	var startup_frames := maxi(1, int(roundf(reverse.startup / DT)))
	var carry_end := mini(carry_start + startup_frames, heads.size() - 1)
	var windup := heads[carry_start].distance_to(heads[carry_end])
	# A ceiling is still needed, or "carry" could be answered by re-planting the pose
	# 1.7m away and calling the travel a carry. 返扫's own chord is 150° at ~3.9m ≈
	# 10m, so 2.5m is far past what an overrun can account for and nowhere near a
	# re-authored pose.
	_check(
		windup < 2.5,
		"返扫 repositioned the head %.2fm during its own startup — that is a re-planted \
pose, not the 26° of overrun §7 authors" % windup
	)
	# And the boundary itself must not be an instant jump: a cut whose startup is 0
	# would show up here even though the wind-up above is spread over frames.
	var inside := 0.0
	var at_cut := 0.0
	for s in range(0, heads.size() - 1):
		var step := heads[s].distance_to(heads[s + 1])
		if s > 0 and labels[s] != labels[s - 1]:
			at_cut = maxf(at_cut, step)
		else:
			inside = maxf(inside, step)
	_check(inside > 0.1, "the head barely moved, so nothing about its motion was measured")
	_check(
		at_cut <= inside * 1.15 + 0.05,
		"the head moved %.2fm at a cut boundary against %.2fm inside a cut — a cut snapped to a new pose (§10)"
			% [at_cut, inside]
	)
	_check(inside < 3.0, "a cut moves the head %.2fm in one frame, beyond a 4.6m chain's budget" % inside)
	# And 返扫 has to actually declare it carries on.
	_check(reverse.continue_from_head, "返扫 re-authors its own start instead of carrying on")


# §12: a whiff costs the spin. If missing were free the chain would just be a wide
# sword — the same reason 回风 loses 势 to air.
func _check_a_whiff_costs_the_spin() -> void:
	await _park_everything()
	await _stand(Vector3(0.0, 1.0, -22.0), Vector3(0.0, 0.0, -1.0))
	chain.reset()
	chain.request(&"light")
	await _tick_until_held(180)
	var after_whiff := chain.momentum

	_park_everything()
	_place_target(&"light", Vector3(0.0, 0.0, -24.9))
	await _stand(Vector3(0.0, 1.0, -22.0), Vector3(0.0, 0.0, -1.0))
	chain.reset()
	chain.request(&"light")
	await _tick_until_held(180)
	var after_hit := chain.momentum
	_check(chain.hits_landed > 0, "the control sweep missed, so this comparison means nothing")
	_check(
		after_whiff < after_hit - 0.04,
		"cutting air left %.3f spin against %.3f for a hit — whiffing is nearly free" % [after_whiff, after_hit]
	)


func _measure_arc_progress(spin: float) -> float:
	chain.reset()
	chain.momentum = spin
	var profile := moveset.get_move(&"ch_sweep")
	if not chain.request(&"light"):
		_fail("the light attack was refused while measuring spin %.1f" % spin)
		return 0.0
	var start_az := _facing_azimuth() + deg_to_rad(profile.start_azimuth_degrees)
	await _tick(10)
	var offset := chain.head_position() - chain._origin()
	var az := atan2(offset.x, offset.z)
	return absf(wrapf(az - start_az, -PI, PI))


# ============================================================================
#  §43 · THE FEEL PASS — WHAT MAKES THE CHAIN READ AS A MASS
# ============================================================================

# THE HEAD HAS WEIGHT, SO LANDING ON SOMETHING COSTS IT (§43 IMPACT).
#
# The same sweep, the same target slot, the same distance — only the weight differs.
# A whip behaves identically in all three cases; a mass does not. This is the whole
# distinction between 实链 and "a very long sword", so it is measured on the arc AND
# on the spin rather than asserted on the data:
#
#   spin   the head keeps less of it after stopping against something heavy
#   arc    the sweep is knocked further off course by something heavy
func _check_landing_costs_the_head_its_spin() -> void:
	var light := await _measure_landing(&"light")
	var heavy := await _measure_landing(&"heavy")
	if light.is_empty() or heavy.is_empty():
		return
	_check(
		int(light["hits"]) > 0 and int(heavy["hits"]) > 0,
		"a landing was never measured, so the cost of one means nothing"
	)
	_check(
		int(light["hits"]) == int(heavy["hits"]),
		"the two runs did not land the same number of times (%d vs %d)"
			% [int(light["hits"]), int(heavy["hits"])]
	)
	_check(
		float(heavy["momentum"]) < float(light["momentum"]) - 0.04,
		"stopping against a heavy body left %.3f spin against %.3f for a light one — \
the head does not care what it lands on"
			% [float(heavy["momentum"]), float(light["momentum"])]
	)
	# And the arc bends further, because a collision is a collision and the heavier
	# thing takes more of the head's course away from it.
	_check(
		float(heavy["azimuth"]) > float(light["azimuth"]) + deg_to_rad(1.5),
		"the heavy landing bent the arc to %.3f rad against %.3f for the light one — \
the head went through it, it did not hit it"
			% [float(heavy["azimuth"]), float(light["azimuth"])]
	)
	# Printed, not only asserted: "the head has weight" is a claim about MAGNITUDE, and
	# a threshold failure says nothing about whether the numbers are on the right side.
	print("    落点代价      轻 势=%.3f 偏=%.1f°   重 势=%.3f 偏=%.1f°" % [
		float(light["momentum"]), rad_to_deg(float(light["azimuth"])),
		float(heavy["momentum"]), rad_to_deg(float(heavy["azimuth"])),
	])


# Sampled at the END OF THE ACTIVE PHASE, not at rest: the return now bends by design
# (§43), so a reading taken after the head is home would be measuring the reel rather
# than the landing.
func _measure_landing(weight: StringName, with_target := true) -> Dictionary:
	await _park_everything()
	if with_target:
		_place_target(weight, Vector3(0.0, 0.0, -24.9))
	await _stand(Vector3(0.0, 1.0, -22.0), Vector3(0.0, 0.0, -1.0))
	chain.reset()
	chain.hits_landed = 0
	if not chain.request(&"light"):
		_fail("横缚 was refused while measuring a %s landing" % String(weight))
		return {}
	await _tick(19)
	var offset := chain.head_position() - chain._origin()
	return {
		"momentum": chain.momentum,
		"azimuth": atan2(offset.x, offset.z),
		"hits": chain.hits_landed,
	}


# 回收不许瞬回 (§43 RETURN). A mass released from a strike keeps going for a beat —
# the chain stops feeding it, it does not stop it — so the reel swings PAST where the
# head stopped and drifts further out before it is hauled home. Retracing the line the
# head came in on is the difference between a rope and a sprite being reset.
func _check_the_return_swings_before_it_comes_home() -> void:
	await _park_everything()
	await _stand(Vector3(0.0, 1.0, -22.0), Vector3(0.0, 0.0, -1.0))
	chain.reset()
	if not chain.request(&"light"):
		_fail("横缚 was refused while measuring the return")
		return
	var guard := 0
	while chain.state != ChainDirector.State.RETRACTING and guard < 240:
		guard += 1
		await _tick(1)
	if chain.state != ChainDirector.State.RETRACTING:
		_fail("the sweep never started reeling in, so there is no return to measure")
		return
	var start_radius := chain.radius
	var start_az := chain._azimuth
	# Which way "past it" is: the head has to close the gap to the home pose, so
	# overshooting means moving against the sign of that gap. Derived rather than
	# assumed, so this cannot quietly pass by measuring a turn in the wrong direction.
	var gap := wrapf(chain._retract_pose().x - start_az, -PI, PI)
	var outward := 0.0
	var past := 0.0
	var frames := 0
	while chain.state == ChainDirector.State.RETRACTING and frames < 120:
		frames += 1
		await _tick(1)
		outward = maxf(outward, chain.radius - start_radius)
		past = maxf(past, -signf(gap) * wrapf(chain._azimuth - start_az, -PI, PI))
	_check(
		outward > 0.05,
		"the head came straight home (%.3fm of drift out) — the reel has no weight" % outward
	)
	_check(
		past > deg_to_rad(2.0),
		"the head stopped turning the instant the strike ended (%.2f°) — that is a \
sprite being reset, not a mass on a rope"
			% rad_to_deg(past)
	)
	# And it must never overrun the chain's own length on the way out.
	_check(
		chain.radius <= moveset.max_radius + 0.001,
		"the reel took the head to %.2fm, past the %.2fm the chain is long"
			% [chain.radius, moveset.max_radius]
	)
	print("    回收跟随      外漂 +%.2fm   过冲 %.1f°  (%d 帧 / %.2fs)" % [
		outward, rad_to_deg(past), frames, float(frames) * DT,
	])


# §43 asks for tension in three channels and this checks the two that belong to the
# weapon: the LINE and the CAMERA. The third is AUDIO, and §49 is explicit that it
# stays a placeholder — the events are emitted (and counted here), the sounds are not
# this line's to make.
func _check_tension_is_in_the_line_and_the_camera() -> void:
	var visual := chain.chain_visual
	if visual == null:
		_fail("the chain has no ChainVisual, so tension has no visual channel")
		return
	var hand := player.global_position + Vector3.UP * 1.4
	var far := hand + Vector3(0.0, 0.0, -moveset.max_radius)
	# FULLY LOADED: straight, and ALIVE. Both halves matter — a perfectly straight
	# line is what a rigid bar looks like, and the tremor is what says "loaded"
	# rather than "far away".
	visual.update_chain(hand, far, Vector3(0.0, 0.0, -6.0), 1.0, DT)
	var taut_slack := visual.drawn_slack()
	var first := visual.drawn_points()
	visual.update_chain(hand, far, Vector3(0.0, 0.0, -6.0), 1.0, DT)
	var second := visual.drawn_points()
	var alive := 0.0
	for i in mini(first.size(), second.size()):
		alive = maxf(alive, first[i].distance_to(second[i]))
	_check(
		alive > 0.002,
		"a chain at full tension does not move at all (%.4fm per frame) — nothing on \
screen says it is loaded"
			% alive
	)
	# §33: and it must never read as a rubber band. 6cm of stray at full stretch.
	_check(
		taut_slack < 0.06,
		"a chain at full tension strays %.3fm from straight — that is a rubber band (§33)"
			% taut_slack
	)
	# The same rope, slack, hangs: the two states are different pictures, which is the
	# only reason the taut one is legible.
	var near := hand + Vector3(0.0, 0.0, -2.4)
	visual.update_chain(hand, near, Vector3.ZERO, 0.0, DT)
	var slack_slack := visual.drawn_slack()
	_check(
		slack_slack > taut_slack + 0.15,
		"a slack chain strays %.3fm against %.3fm taut — the two states look the same"
			% [slack_slack, taut_slack]
	)

	# ------------------------------- the camera channel -----------------------
	await _park_everything()
	await _stand(Vector3(0.0, 1.0, -22.0), Vector3(0.0, 0.0, -1.0))
	var feedback := player.get_node_or_null("CameraFeedbackController") as CameraFeedbackController
	if feedback == null:
		_fail("the player has no camera feedback, so tension has no camera channel")
		return
	chain.reset()
	if not chain.request(&"chain_hook"):
		_fail("缠锁 was refused while measuring tension's camera channel")
		return
	await _tick(70)
	_check(chain.is_taut(), "the throw did not go taut, so there is no tension to feel")
	feedback.sustain_fov = 0.0
	chain.step(DT)
	_check(
		feedback.sustain_fov < -0.5,
		"a loaded chain leaves the camera untouched (sustain_fov %.2f) — the squeeze is \
§43's camera half" % feedback.sustain_fov
	)
	# §30/§31: a PULL along the chain, never a turn toward the head. The impulse is a
	# nudge and the assertion is that it stays one.
	_check(
		absf(feedback.impulse.x) < 0.06,
		"the tension snap turned the camera by %.3f rad — the view must not follow the head"
			% feedback.impulse.x
	)
	print("    绷紧通道      线：抖 %.4fm/帧 离直 %.4fm（松时 %.4fm）   相机：%.2f° 挤压" % [
		alive, taut_slack, slack_slack, -feedback.sustain_fov,
	])



# ============================================================================
#  2 · TENSION
# ============================================================================

# §15: a throw that reaches the end of the chain leaves it TAUT — and this is the
# only introduction to tension the player ever gets, so it has to happen on its own.
func _check_the_throw_ends_taut() -> void:
	await _park_everything()
	await _stand(Vector3(0.0, 1.0, -22.0), Vector3(0.0, 0.0, -1.0))
	chain.reset()
	_check(chain.request(&"chain_hook"), "缠锁 was refused from a clean hold")
	await _tick(70)
	_check(chain.is_taut(), "the throw did not stretch the chain to its limit")
	_check(
		chain.state == ChainDirector.State.TENSIONED,
		"a full throw left the chain in %s, not TENSIONED" % String(ChainDirector.State.keys()[chain.state])
	)
	_check(
		chain.radius >= moveset.max_radius * moveset.tension_ratio - 0.01,
		"the throw stopped at %.2fm of a %.2fm chain" % [chain.radius, moveset.max_radius]
	)
	_check(chain.tension > 0.9, "the chain is taut but the drawing reads %.0f%%" % (chain.tension * 100.0))


# §16: TENSION CHANGES THE AVAILABLE INPUTS. Same buttons, different answers — this
# is the difference between pressure being a resource and pressure being a number.
func _check_tension_deletes_the_normal_inputs() -> void:
	# A control first: from rest, the normal light chain is what answers.
	await _park_everything()
	await _stand(Vector3(0.0, 1.0, -22.0), Vector3(0.0, 0.0, -1.0))
	chain.reset()
	var from_rest := chain.request(&"light") and chain.active_move != null
	_check(
		from_rest and chain.active_move.id == &"ch_sweep",
		"a light from rest produced %s" % _move_name(chain.active_move)
	)
	await _tick(80)
	# Now taut, and Light must mean something else.
	await _park_everything()
	await _stand(Vector3(0.0, 1.0, -22.0), Vector3(0.0, 0.0, -1.0))
	chain.reset()
	chain.request(&"chain_hook")
	await _tick(70)
	_check(chain.state == ChainDirector.State.TENSIONED, "could not reach tension, so the inputs cannot be tested")
	_check(chain.request(&"light"), "绷切 was refused while the chain was taut")
	_check(
		chain.active_move != null and chain.active_move.id == moveset.taut_light_id,
		"Light while taut played %s instead of 绷切" % _move_name(chain.active_move)
	)
	# A taut-only technique must be impossible to reach cold, or the resource is
	# decorative. The data says so, and the input map has to agree.
	var snap := moveset.get_move(moveset.taut_light_id)
	_check(snap != null and snap.requires_taut, "绷切 is not gated on being taut")
	_check(not moveset.light_chain.has(moveset.taut_light_id), "绷切 is in the normal light chain, so taut is not a gate")
	await _tick(60)
	# And 绷切 SPENDS the taut state: it cuts back along the tight line, so the chain
	# is no longer at its limit. Without this, pressure is not a resource at all —
	# 绷切 and 拉近斩 both begin at the limit (they start attached to whatever the
	# chain already caught), so a naive "did it reach the limit" test would put the
	# weapon straight back into TENSION and the taut inputs would never end.
	_check(
		not chain.is_taut(),
		"绷切 left the chain taut, so the pressure it is supposed to spend was never spent"
	)
	# And Heavy: an ORBIT from rest, a YANK once the chain is taut. §14's early
	# release is the timing choice; §13's minimum commitment stops a tap firing it.
	await _park_everything()
	await _stand(Vector3(0.0, 1.0, -22.0), Vector3(0.0, 0.0, -1.0))
	chain.reset()
	_check(chain.request(&"heavy"), "holding Heavy from rest was refused")
	_check(
		chain.state == ChainDirector.State.ORBITING,
		"holding Heavy from rest gave %s instead of 蓄势回旋" % String(ChainDirector.State.keys()[chain.state])
	)
	_check(not chain.release_heavy(), "释 fired 蓄势回旋 after a tap, so the minimum hold does nothing")
	await _tick(70)
	_check(chain.momentum > 0.4, "the orbit built only %.2f spin in 1.1s" % chain.momentum)
	_check(chain.release_heavy(), "释 was refused after a full hold")
	await _tick(70)
	_check(chain.is_taut(), "the launch did not leave the chain taut")
	_check(chain.request(&"heavy"), "曳 was refused while taut")
	_check(
		chain.active_move != null and chain.active_move.id == moveset.taut_heavy_id,
		"Heavy while taut played %s instead of 曳" % _move_name(chain.active_move)
	)


# ============================================================================
#  3 · HOOK
# ============================================================================

# §18 — THE WEIGHT TABLE. The same input on three targets. If all three move the
# same way the chain is "pull everything to me" and §19 does not exist.
func _check_the_weight_table() -> void:
	var rows: Dictionary = {}
	for weight in [&"light", &"medium", &"heavy"]:
		var measured := await _measure_hook(weight)
		if measured.is_empty():
			return
		rows[weight] = measured
	var light: Dictionary = rows[&"light"]
	var medium: Dictionary = rows[&"medium"]
	var heavy: Dictionary = rows[&"heavy"]
	# Printed, not just asserted: the table is the feature, and a threshold failure
	# says nothing about WHICH way the numbers moved.
	#
	# The light row reads short of its shares ON PURPOSE and that is not slack in the
	# measurement: a light target is hauled the whole way in, so it closes the gap
	# until it collides with the player's own capsule and both bodies stop. The two
	# numbers add up to the 1.85m of daylight there was, not to 2.30m of shares. The
	# medium and heavy rows have no such wall, which is why they read within 1% of
	# their advertised distances — that is what the seam fix bought.
	print("    重量表  target/player:  light %.2f/%.2f  medium %.2f/%.2f  heavy %.2f/%.2f"
		% [
			float(light["target"]), float(light["player"]),
			float(medium["target"]), float(medium["player"]),
			float(heavy["target"]), float(heavy["player"]),
		])
	# LIGHT: the target comes to you and you barely move.
	_check(
		float(light["target"]) > 1.2,
		"hooking a light target moved it only %.2fm — it should fly" % float(light["target"])
	)
	_check(
		float(light["player"]) < 0.35,
		"hooking a light target dragged the player %.2fm — the TARGET is supposed to move" % float(light["player"])
	)
	# MEDIUM: both close, neither of them all the way.
	_check(
		float(medium["target"]) > 0.35 and float(medium["player"]) > 0.35,
		"a medium target produced %.2fm / %.2fm — both sides should give"
			% [float(medium["target"]), float(medium["player"])]
	)
	# HEAVY: the enemy does not move AT ALL and YOU do. This is the sentence the
	# whole feature exists for: a heavy enemy is an ANCHOR, not a victim.
	_check(
		float(heavy["target"]) < 0.12,
		"hooking a heavy target moved it %.2fm — a heavy enemy must not be pullable" % float(heavy["target"])
	)
	_check(
		float(heavy["player"]) > 0.45,
		"hooking a heavy target pulled the player only %.2fm — it should have dragged you in"
			% float(heavy["player"])
	)
	# The bound window is what makes 缚 a decision rather than a menu: heavies give
	# you the shortest one, which is the counterplay.
	_check(
		moveset.hook_response_for(&"light")["bound_time"] > moveset.hook_response_for(&"heavy")["bound_time"],
		"every weight binds for the same length of time, so the weight table is decoration"
	)


# One hook, measured. Returns {} and reports if anything went wrong.
func _measure_hook(weight: StringName) -> Dictionary:
	await _park_everything()
	var target := _place_target(weight, Vector3(0.0, 0.0, -25.0))
	if target == null:
		return {}
	await _stand(Vector3(0.0, 1.0, -22.0), Vector3(0.0, 0.0, -1.0))
	chain.reset()
	if not chain.request(&"chain_hook"):
		_fail("缠锁 was refused against a %s target" % String(weight))
		return {}
	if not await _hook_now(90):
		_fail("the throw never caught a %s target standing 3m away" % String(weight))
		return {}
	_check(
		chain.weight_of(target) == weight,
		"the %s target reports weight %s" % [String(weight), String(chain.weight_of(target))]
	)
	var target_before := target.global_position
	var player_before := player.global_position
	if not chain.request(&"chain_lock"):
		_fail("缚 was refused on a hooked %s target" % String(weight))
		return {}
	# A pull is a HAUL now, not one displacement: it is paid out in yanks with gaps
	# between them, so the measurement has to let the haul actually run. `_wait` would
	# not do it — this test drives the chain's clock itself (manual_step), so physics
	# frames go by without the chain advancing at all.
	#
	# 90 frames is deliberately more than the haul needs (the fifth yank lands at
	# 4 * 0.24s and each yank takes ~0.3s to be spent). The slack is not padding: the
	# test's clock is not slowed by 顿挫's hitstop while the BODY's physics frames
	# are, so ~0.18s of the haul is spent frozen and a window sized to the chain
	# alone would quietly under-measure every row by about a fifth.
	await _tick(90)
	return {
		"target": target_before.distance_to(target.global_position),
		"player": player_before.distance_to(player.global_position),
	}


# §22/§23: 缚 opens a WINDOW, and the window has THREE exits. When it closes the
# chain lets go — which is what makes 拉近斩 / 地砸 a decision with a deadline
# instead of a menu the player can browse.
func _check_the_bind_is_a_window() -> void:
	_check(moveset.bound_light_id != &"" and moveset.bound_heavy_id != &"", "缚 has no exits")
	# Exit 1 — Light = 拉近斩, and it is reachable.
	await _park_everything()
	_place_target(&"light", Vector3(0.0, 0.0, -25.0))
	await _stand(Vector3(0.0, 1.0, -22.0), Vector3(0.0, 0.0, -1.0))
	chain.reset()
	chain.request(&"chain_hook")
	if not await _hook_now(90):
		_fail("could not hook the light target for the bind test")
		return
	chain.request(&"chain_lock")
	_check(chain.is_bound(), "缚 did not open a bound window")
	_check(chain.request(&"light"), "拉近斩 was refused inside the bind window")
	_check(
		chain.active_move != null and chain.active_move.id == moveset.bound_light_id,
		"Light inside a bind played %s instead of 拉近斩" % _move_name(chain.active_move)
	)
	await _tick(80)
	_check(not chain.is_hooked(), "拉近斩 left the chain attached to the target")
	# Exit 2 — Heavy = 地砸. It must be REACHABLE (a designed exit no input can
	# reach is not a designed exit) and it must not be able to brittle-break on its
	# own, which is the whole reason 冰 has something to add (§24).
	var slam := moveset.get_move(moveset.bound_heavy_id)
	_check(slam != null and slam.pulls and slam.releases_hook, "地砸 is not a pull that lets go")
	_check(slam != null and slam.poise_damage < 35.0, "地砸 alone breaks brittle, so FROST has nothing to add")
	await _park_everything()
	_place_target(&"light", Vector3(0.0, 0.0, -25.0))
	await _stand(Vector3(0.0, 1.0, -22.0), Vector3(0.0, 0.0, -1.0))
	chain.reset()
	chain.request(&"chain_hook")
	if not await _hook_now(90):
		_fail("could not hook the light target for the heavy exit")
		return
	chain.request(&"chain_lock")
	_check(chain.request(&"heavy"), "地砸 was refused inside the bind window")
	_check(
		chain.active_move != null and chain.active_move.id == moveset.bound_heavy_id,
		"Heavy inside a bind played %s instead of 地砸" % _move_name(chain.active_move)
	)
	# Exit 3 is magic (§25) and is deliberately not here yet.
	# And when the window expires, the chain releases by itself.
	await _park_everything()
	_place_target(&"light", Vector3(0.0, 0.0, -25.0))
	await _stand(Vector3(0.0, 1.0, -22.0), Vector3(0.0, 0.0, -1.0))
	chain.reset()
	chain.request(&"chain_hook")
	if not await _hook_now(90):
		return
	chain.request(&"chain_lock")
	var bound := chain.bound_left
	_check(bound > 0.35, "缚 only lasted %.2fs, which is not a window" % bound)
	await _tick(int(ceil(bound * 60.0)) + 30)
	_check(not chain.is_hooked(), "the chain stayed attached after the bind window closed")


# §20: a fixed anchor is the same event as a heavy enemy. Because the weight table
# gives an anchor target_share 0, §20's "quick forward move" falls out of §18 for
# free — there is no anchor-specific code anywhere in the weapon.
func _check_an_anchor_pulls_the_player() -> void:
	if lab.anchor == null:
		_fail("the lab has no anchor, so §20 is unreachable")
		return
	await _park_everything()
	# Stand so the pillar is 3.4m away along -Z: the anchor is at (6.5, 0, -26).
	await _stand(Vector3(6.5, 1.0, -22.6), Vector3(0.0, 0.0, -1.0))
	chain.reset()
	_check(chain.request(&"chain_hook"), "缠锁 was refused toward the anchor")
	if not await _hook_now(90):
		_fail("the throw never caught the anchor")
		return
	_check(
		chain.weight_of(lab.anchor) == ElementLibrary.WEIGHT_HEAVY,
		"the anchor is not heavy, so it cannot be an anchor"
	)
	var anchor_before := lab.anchor.global_position
	var player_before := player.global_position
	chain.request(&"chain_lock")
	await _tick(60)
	_check(lab.anchor.global_position.distance_to(anchor_before) < 0.05, "hooking the pillar moved the pillar")
	_check(
		player_before.distance_to(player.global_position) > 0.45,
		"hooking a fixed point moved the player only %.2fm — §20 is a forward pull"
			% player_before.distance_to(player.global_position)
	)


# §21: 链 × 墙 = impact and lost spin. A chain must never pass through stone, and a
# throw into a wall has to cost something or space does not matter.
func _check_the_wall_stops_the_head() -> void:
	await _park_everything()
	await _stand(Vector3(0.0, 1.0, -38.0), Vector3(0.0, 0.0, -1.0))
	chain.reset()
	chain.momentum = 0.6
	var wall_before := chain.wall_hits
	chain.request(&"chain_hook")
	await _tick(70)
	_check(chain.wall_hits > wall_before, "a throw straight into the wall never registered a wall hit")
	var front := ChainLab.WALL_Z + 0.35
	_check(
		chain.head_position().z > front - 0.05,
		"the head ended at z=%.2f, past the wall face at %.2f (§21)" % [chain.head_position().z, front]
	)
	_check(chain.momentum < 0.6, "hitting a wall cost no spin at all")
	# §49: metal on stone is an event, not a state. The audio line reads this one to
	# place the impact, and the strength is carried rather than re-derived from the
	# head's speed by whoever listens — a listener that recomputes it will one day
	# recompute it differently.
	_check(walls_seen.size() > 0, "the wall impact was never announced")
	if not walls_seen.is_empty():
		_check(
			walls_seen[walls_seen.size() - 1] > 0.0,
			"the wall impact was announced with no strength (%.3f)" % walls_seen[walls_seen.size() - 1]
		)


# §24: the only two magic interactions in phase 1, and they must be STRUCTURAL.
# 风 × 链 adds SPIN (the chain's own currency), not damage. 冰 × 链 makes a PULL
# worth more, because a chain is the best way to put force into something brittle.
func _check_wind_is_spin_and_frost_is_leverage() -> void:
	await _park_everything()
	await _stand(Vector3(0.0, 1.0, -22.0), Vector3(0.0, 0.0, -1.0))
	chain.reset()
	var before := chain.momentum
	_check(combat.select_spell(&"wind_step"), "风步 could not be armed")
	_check(combat.request(&"cast"), "风步 was refused")
	await _wait(40)
	_check(
		chain.momentum > before + moveset.wind_momentum_bonus * 0.9,
		"风 did not reach the chain's momentum (%.2f → %.2f)" % [before, chain.momentum]
	)
	_check(moveset.pull_poise_elements.has(ElementLibrary.FROST), "冰 is not named as the pull's payoff element")
	_check(moveset.pull_poise_scale > 1.0, "a frost pull pays nothing extra")
	# Measured: the same 地砸, on the same target, with and without the frost rung
	# that `pull_poise_min_stage` names. The poise comes out of the real hit dict.
	var plain := await _measure_pull_poise(false)
	var frosted := await _measure_pull_poise(true)
	_check(
		plain > 0.0 and frosted > plain * 1.3,
		"a pull on a frosted target delivered %.1f poise against %.1f — 冰 buys nothing" % [frosted, plain]
	)


# A PULL MOVES THE DISTANCE IT STATES. This is the seam EVERY number in the weight
# table is denominated in: "player_share 0.35" claims 0.8m of forward drag, and that
# claim is only worth anything if PlayerMovement.pull() actually delivers it.
#
# It did not. The push was added into `velocity` on every frame and only bled off by
# the walk solver's acceleration ramp, which removes a fixed `acceleration * delta`
# per frame — far slower than the decay it was supposed to have. Measured with a
# scratch probe: `pull(0.25)` moved the player 3.75m, a factor of 15. Every pull in
# the weapon was 15x too strong, and NOTHING IN THIS SUITE COULD SEE IT, because
# every assertion here is about which body moved and in which direction, never about
# how far. 15x is also exactly the kind of error a screenshot cannot show: being
# dragged 3.75m looks completely normal, it just is not the mechanic.
#
# Bare `pull()` rather than a hook, on purpose: a hook drags both bodies and the
# target's collision with the player can absorb yanks, so measuring through the
# weight table would test the stage as much as the seam.
func _check_a_pull_moves_the_distance_it_states() -> void:
	await _park_everything()
	await _stand(Vector3(0.0, 1.0, -22.0), Vector3(0.0, 0.0, -1.0))
	var asked := 0.40
	var before := player.global_position
	player.call("pull", Vector3(0.0, 0.0, -asked))
	await _wait(60)
	var moved := player.global_position - before
	var travelled := Vector2(moved.x, moved.z).length()
	_check(
		travelled > asked * 0.85 and travelled < asked * 1.15,
		"a pull of %.2fm moved the player %.2fm (factor %.2f) — the weight table's distances are scaled by that"
			% [asked, travelled, travelled / asked]
	)
	# And it has to be the RIGHT direction: a seam that delivered the distance
	# backwards would pass the factor check above.
	_check(
		moved.z < -asked * 0.5,
		"a pull toward -Z moved the player by %s, so the sign is inverted" % moved
	)
	# The body's own velocity must not have absorbed the push, or the walk solver
	# spends it a second time and the leak comes back through a different door.
	await _wait(40)
	_check(
		(player.get("external_velocity") as Vector3).length() < 0.05,
		"the push is still in the body after the pull finished (%s)" % player.get("external_velocity")
	)


# §15/§18: A PULL IS A HAUL, NOT A MAGNET.
#
# Delivered as a single displacement, a pull moves the body the right distance and
# tells the player nothing about what was on the end of it — there is no moment in
# the motion where anything resisted, so "heavy" is only ever a number in a table.
# The distance is therefore paid out in diminishing yanks with a stop between each.
#
# Measured on the BODY rather than on the settings, on purpose: a change to
# `pull_tugs` that never reached the motion — or a scheduler that stopped being
# called — would still look correct in the data, and this is the check that catches
# the difference between a tug of war and a snap-to.
func _check_the_pull_is_a_haul_not_a_magnet() -> void:
	await _park_everything()
	var target := _place_target(&"light", Vector3(0.0, 0.0, -25.0))
	if target == null:
		return
	await _stand(Vector3(0.0, 1.0, -22.0), Vector3(0.0, 0.0, -1.0))
	chain.reset()
	chain.request(&"chain_hook")
	if not await _hook_now(90):
		_fail("could not hook the light target to measure the haul")
		return
	chain.request(&"chain_lock")
	var before := target.global_position
	var previous := before
	var yanks := 0
	# Only THIS haul's announcements: the suite has run several by now, and a count
	# that includes them would pass on a weapon that had stopped announcing entirely.
	var announced_before := tugs_seen.size()
	for i in 60:
		await physics_frame
		chain.step(DT)
		# 3cm: above the settling of a body standing on a deck, well below the
		# smallest yank a 2.30m haul can produce.
		if previous.distance_to(target.global_position) > 0.03:
			yanks += 1
		previous = target.global_position
	_check(
		yanks >= 3,
		"a pull on a light target arrived in %d movement(s) — that is a magnet, not a haul" % yanks
	)
	_check(
		yanks <= moveset.pull_tugs,
		"the haul moved the target %d times but the data only asks for %d" % [yanks, moveset.pull_tugs]
	)
	# And the rhythm must not have changed the BUDGET: a haul that moves a body
	# further than the distance it advertises is a stealth balance change.
	var sum := 0.0
	for share in moveset.pull_tug_curve:
		sum += share
	_check(
		absf(sum - 1.0) < 0.001,
		"the tug curve sums to %.3f, so a pull no longer moves the distance it states" % sum
	)
	_check(moveset.pull_tugs >= 3, "a %d-yank haul is not a tug of war" % moveset.pull_tugs)
	# §49: the haul ANNOUNCES every yank. The audio line can only put a sound against
	# a rhythm that arrives as events — and an interface nobody reads rots silently, so
	# the count is asserted rather than left to the day someone tries to use it.
	_check(
		tugs_seen.size() - announced_before >= 3,
		"the haul announced %d yank(s) for %d movements — the audio line has nothing to \
place a sound against" % [tugs_seen.size() - announced_before, yanks]
	)
	_check(
		tugs_seen.size() - announced_before <= moveset.pull_tugs,
		"the haul announced %d yanks but the curve only has %d shares"
			% [tugs_seen.size() - announced_before, moveset.pull_tugs]
	)


# A heavy target is used deliberately: the weight table does not move it, so the
# geometry of the measurement cannot drift between the two runs.
func _measure_pull_poise(frosted: bool) -> float:
	await _park_everything()
	var target := _place_target(&"heavy", Vector3(0.0, 0.0, -25.0))
	if target == null:
		return 0.0
	target.call("apply_debug_state", &"frosted" if frosted else &"normal")
	await _stand(Vector3(0.0, 1.0, -22.0), Vector3(0.0, 0.0, -1.0))
	chain.reset()
	landed.clear()
	chain.request(&"chain_hook")
	if not await _hook_now(90):
		_fail("could not hook the heavy target to measure a pull")
		return 0.0
	chain.request(&"chain_lock")
	await _tick(6)
	chain.request(&"heavy")
	await _tick(60)
	var best := 0.0
	for hit in landed:
		best = maxf(best, float(hit.get("poise_damage", 0.0)))
	return best


# §26/§27: DEFLECT SWING is deliberately NOT a sword parry. It sweeps a light melee
# attack aside, a heavy goes straight through, and 截链 disturbs the trajectory
# instead of meeting it. The counterplay has to be real or the guard is free.
func _check_deflect_is_not_a_sword_parry() -> void:
	var window := moveset.deflect_perfect_window
	_check(window >= 0.08 and window <= 0.16, "the 截链 window is %.2fs, outside the project's 0.08–0.16" % window)
	var guard := moveset.get_move(moveset.deflect_id)
	_check(guard != null and guard.deflects, "拨链 is not a deflect")
	_check(guard != null and guard.damage == 0.0, "拨链 deals damage, so it is an attack, not a guard")
	var light_hit := {"poise_damage": 8.0, "damage": 20.0, "source": dummy, "target": player}
	# Too early: the arc has not been swept, so nothing is in front of the body.
	await _park_everything()
	await _stand(Vector3(0.0, 1.0, -22.0), Vector3(0.0, 0.0, -1.0))
	chain.reset()
	_check(chain.request(&"block"), "拨链 was refused")
	_check(not chain.try_deflect(light_hit), "a deflect worked before the arc had been swept")
	await _tick_until_time(guard.startup + 0.01)
	player.set("health", 100.0)
	_check(chain.try_deflect(light_hit), "a light melee attack went straight through 拨链")
	_check(player.get("health") == 100.0, "a perfect 截链 still cost the player health")
	_check(chain.momentum > 0.0, "截链 did not pay in momentum")
	# A stale sweep still spoils the blow but is not free: a chain is metal on a
	# rope, not a wall. Otherwise holding the guard would be a wall.
	await _tick_until_time(guard.startup + window + 0.05)
	player.set("health", 100.0)
	_check(chain.try_deflect(light_hit), "a stale 拨链 stopped working entirely, so holding it is free")
	var after_stale: float = player.get("health")
	_check(
		after_stale < 100.0 and after_stale > 100.0 - 20.0,
		"a stale deflect either blocked everything (%.1f) or nothing" % after_stale
	)
	# A HEAVY goes through. 35 poise is the project's existing light/heavy line.
	await _park_everything()
	await _stand(Vector3(0.0, 1.0, -22.0), Vector3(0.0, 0.0, -1.0))
	chain.reset()
	chain.request(&"block")
	await _tick_until_time(guard.startup + 0.01)
	var heavy_hit := {"poise_damage": 40.0, "damage": 30.0, "source": dummy, "target": player}
	_check(not chain.try_deflect(heavy_hit), "a heavy attack was deflected, so the guard has no counterplay")
	# And a sword in hand must not deflect at all.
	weapon.equip(WeaponSlot.SWORD)
	_check(not chain.try_deflect(light_hit), "a chain deflect worked while the sword was out")
	weapon.equip(WeaponSlot.CHAIN)


# ============================================================================
#  THE STAGE (§39) AND WHAT IT CAN DRIVE (§37/§38)
# ============================================================================

# The deck needs a way on. Without one, "the Chain Lab" is a pocket only the debug
# panel can reach — the same failure the movement lane's ramp had, and one that a
# screenshot of the deck cannot possibly show.
func _check_the_lab_is_reachable_on_foot() -> void:
	await _park_everything()
	var start := Vector3(0.0, 1.2, -13.0)
	player.global_position = start
	player.velocity = Vector3.ZERO
	player.look_at_from_position(start, start + Vector3(0.0, 0.0, -1.0), Vector3.UP)
	await _wait(20)
	Input.action_press(&"move_forward")
	await _wait(300)
	Input.action_release(&"move_forward")
	var deck_near := ChainLab.CENTER.z + ChainLab.DECK_SIZE.z * 0.5
	var deck_far := ChainLab.CENTER.z - ChainLab.DECK_SIZE.z * 0.5
	_check(
		player.global_position.z < deck_near and player.global_position.y > 0.4,
		"walking from the arena onto the Chain Lab deck ended at %s — the bridge is blocked"
			% player.global_position
	)
	_check(
		lab.entry_position().z > deck_far and lab.entry_position().z < deck_near,
		"the lab's own entry point is not on the deck"
	)
	# Three weights, in one room, inside one throw of each other: that layout is
	# what makes the weight table's argument visible in a single glance.
	var weights: Array[StringName] = []
	for target in lab.targets:
		if is_instance_valid(target):
			weights.append(target.call("weight_class"))
	for weight in [ElementLibrary.WEIGHT_LIGHT, ElementLibrary.WEIGHT_MEDIUM, ElementLibrary.WEIGHT_HEAVY]:
		_check(weights.has(weight), "the lab has no %s target" % String(weight))
	_check(lab.anchor != null, "the lab has no fixed anchor (§20)")
	_check(lab.crates.size() > 0, "the lab has nothing light to drag (§39)")
	# A STAGE HAS TO BE FREE OF THE OTHER ROOM. ArenaDressing scatters 39
	# placeholders without knowing the deck exists, and eight of them landed inside
	# it — two of them four-metre pillars, one square in the bridge doorway. They
	# carry no collision, so this is a framing failure and not a movement one, which
	# is precisely the kind that survives a green walk test and then shows up as
	# rubble standing in the middle of the video.
	var dressing := world.get_node_or_null("ArenaDressing")
	if dressing == null:
		_fail("the sandbox has no ArenaDressing, so the overlap this guards against cannot be seen")
	else:
		var half_x := ChainLab.DECK_SIZE.x * 0.5
		var intruders: Array[String] = []
		for child in dressing.get_children():
			var mesh_node := child as MeshInstance3D
			if mesh_node == null or mesh_node.mesh == null or not mesh_node.visible:
				continue
			# The mesh's own box, transformed — see the note in ChainLab. Reading
			# VisualInstance3D.get_aabb() here silently returns an empty box in a
			# headless run and this check would pass no matter what.
			var box := mesh_node.global_transform * mesh_node.mesh.get_aabb()
			var overlaps_z := box.position.z < deck_near and box.position.z + box.size.z > deck_far
			var overlaps_x := (
				box.position.x < ChainLab.CENTER.x + half_x
				and box.position.x + box.size.x > ChainLab.CENTER.x - half_x
			)
			if overlaps_z and overlaps_x:
				intruders.append(String(mesh_node.name))
		_check(
			intruders.is_empty(),
			"visible ArenaDressing geometry stands inside the lab deck: %s" % ", ".join(intruders)
		)


# §37/§39: the lab has to be able to drive every action the PLAYER can, or the
# weapon can only be judged on the subset the panel happens to expose.
func _check_the_lab_can_drive_every_action() -> void:
	var reachable: Array[StringName] = []
	reachable.append_array(moveset.light_chain)
	for id in [moveset.heavy_id, moveset.hook_id, moveset.taut_light_id, moveset.taut_heavy_id,
			moveset.bound_light_id, moveset.bound_heavy_id, moveset.deflect_id]:
		if not reachable.has(id):
			reachable.append(id)
	for id in reachable:
		var move := moveset.get_move(id)
		_check(move != null, "the weapon names %s but has no such technique" % String(id))
		if move != null:
			_check(move.display_name != "", "%s has no name, so no readout can say what is happening" % String(id))
	# §38: the readout has to answer the questions the design turns on — IN DEVELOPER
	# MODE, which §46 makes the only place it exists.
	chain.debug_readout = true
	var line := chain.debug_state_line()
	for token in ["R=", "M=", "T="]:
		_check(token in line, "the debug readout does not report %s" % token)
	_check(chain.debug_flags_line().length() > 0, "the debug readout has no flags line")
	chain.debug_readout = false


# §46: FORM / RADIUS / MOMENTUM / TENSION / ANCHORS / BOUND TARGETS / OPPORTUNITY TAG
# are a DEVELOPER readout. Clean hides them completely.
#
# This is not tidiness. §51 says the weapon fails if the player needs a gauge to know
# the chain is taut, and a HUD that prints T=87% is that gauge — it just lives in the
# top-left instead of in the middle. What the player IS allowed to know is which form
# is in hand, because the forms are a real choice and a choice needs a name.
func _check_the_numbers_are_a_developer_readout() -> void:
	chain.debug_readout = false
	var clean := chain.debug_state_line()
	_check(
		clean.strip_edges() != "",
		"the status line is empty outside developer mode, so the HUD cannot say what is in hand"
	)
	for token in ["R=", "M=", "T="]:
		_check(
			token not in clean,
			"the status line still reports %s outside developer mode — that is the gauge §51 forbids"
				% token
		)
	_check(
		moveset.form_name in clean,
		"the status line does not name the form (%s), which is the one thing a player \
may be told" % moveset.form_name
	)
	_check(
		chain.debug_flags_line() == "",
		"the flags line is printed outside developer mode"
	)
	# And the switch is the switch: turning it on is what reveals them. Without this
	# half the check above would pass on a weapon that had simply lost its readout.
	chain.debug_readout = true
	_check("R=" in chain.debug_state_line(), "the readout is missing even in developer mode")
	chain.debug_readout = false


# §32/§33: the chain has to be DRAWN WHERE IT IS. The links are MultiMesh instance
# transforms written in world coordinates, which only means anything if ChainVisual
# is a coordinate system rather than a place — and `top_level` does not clear the
# transform, it FREEZES it. The flag flips while the player is still standing on its
# spawn point, so the node kept the spawn position and drew every link offset by it,
# while the head (placed with an explicit global transform) stayed correct. The
# weapon therefore rendered as a head on the enemy and a chain five metres behind
# it — and `is_drawn()` answered true the entire time, which is why the structural
# assertion below is the one that matters and "is anything visible" is not.
func _check_the_chain_is_drawn_where_it_is() -> void:
	weapon.equip(WeaponSlot.CHAIN)
	var visual := chain.chain_visual
	if visual == null:
		_fail("the chain has no ChainVisual, so nothing is drawn at all")
		return
	# Away from the spawn point first: at spawn the lost offset is zero and the bug
	# is invisible, which is exactly why it survived this long.
	await _stand(Vector3(0.0, 0.9, -25.5), Vector3(0.0, 0.0, -1.0))
	chain.reset()
	await _wait(4)
	_check(
		visual.top_level,
		"ChainVisual is not top_level — the hand's own transform would bend the chain"
	)
	var offset := visual.global_transform.origin
	_check(
		offset.length() < 0.001,
		"ChainVisual carries the transform %s — every link is drawn offset by it" % offset
	)
	var head := chain.head_position()
	var reach := head.distance_to(player.global_position)
	_check(
		reach <= moveset.max_radius + 0.6,
		"the head is %.2fm from the player, beyond the chain's reach of %.2fm"
			% [reach, moveset.max_radius]
	)


# §45: the training ground owes the three forms a stage each of them can use, and
# 游链's subject (§6–§9) is a point ABOVE the player — swing, redirect, orbit. That
# fixture is only worth having if the weapon can reach it, so this throws at it rather
# than checking that a node exists: a bar nothing can hook is scenery.
#
# It also pins §13, because reaching it is the proof: a chain released at chest height
# can hook a pillar but never the top of one, which is why the throw follows the aim.
func _check_the_high_anchor_can_be_hooked() -> void:
	var bar := lab.high_anchor
	if bar == null:
		_fail("the lab has no high anchor, so §45's stage is missing its overhead point")
		return
	_check(
		bar.weight_class() == ElementLibrary.WEIGHT_HEAVY,
		"the high anchor answers %s instead of heavy, so it would be dragged" % String(bar.weight_class())
	)
	# Stand at a natural throwing distance and look up at it, as a player would.
	var offset := ChainLab.HIGH_ANCHOR_POSITION - ChainLab.GANTRY_POST
	var stand := Vector3(
		ChainLab.HIGH_ANCHOR_POSITION.x, 0.0, ChainLab.HIGH_ANCHOR_POSITION.z + 3.4
	)
	await _park_everything()
	await _stand(stand, Vector3(0.0, 0.0, -1.0))
	# Measured from the DECK, which is the same origin the chain's heights use — the
	# deck's top face is y = 0, and the player's body origin is not.
	var bar_height := bar.hurtbox.global_position.y
	var horizontal := Vector2(
		bar.hurtbox.global_position.x - stand.x, bar.hurtbox.global_position.z - stand.z
	).length()
	_check(
		bar_height > 1.9,
		"the high anchor's hookable point is only %.2fm up — that is not overhead" % bar_height
	)
	# THE PITCH THAT HITS IT, derived from the pose model rather than guessed: the head
	# lands at `radius = horizontal` and `height = 1.15 + sin(pitch) * radius`.
	if look_pivot != null:
		look_pivot.rotation.x = asin(clampf((bar_height - 1.15) / maxf(0.1, horizontal), -0.9, 0.9))
	chain.reset()
	_check(chain.request(&"chain_hook"), "缠锁 was refused at the high anchor")
	var hooked_bar := await _hook_now(90)
	_check(
		hooked_bar and chain._hook_actor == bar,
		"the throw could not catch the high anchor — the hook still leaves the hand at \
one height and every raised thing in the world is unhookable"
	)
	if not hooked_bar:
		return
	# And once caught, it behaves like the pillar: it does not move, the player does.
	# That is §20 for free, and it is what makes it usable as a swing point later.
	var player_before := player.global_position
	var bar_before := bar.global_position
	chain.request(&"chain_lock")
	await _tick(60)
	_check(
		bar.global_position.distance_to(bar_before) < 0.05,
		"the high anchor moved %.2fm — an anchor that moves is not an anchor (§20)"
			% bar.global_position.distance_to(bar_before)
	)
	_check(
		player_before.distance_to(player.global_position) > 0.25,
		"曳 on the high anchor moved the player %.2fm — pulling on an overhead point is \
the whole reason it is in the stage" % player_before.distance_to(player.global_position)
	)
	_check(
		absf(offset.x) > 1.0,
		"the high anchor stands directly over its own post, so a throw at it is blocked by it"
	)
	print("    高阶锚点      横杆高 %.2fm  水平 %.2fm  需抬头 %.0f°  已钩住=%s" % [
		bar_height, horizontal,
		rad_to_deg(asin(clampf((bar_height - 1.15) / maxf(0.1, horizontal), -0.9, 0.9))),
		str(hooked_bar),
	])


# ============================================================================
#  HELPERS
# ============================================================================

func _on_move_started(move: ChainMove) -> void:
	started.append(move.id)


func _on_hit_landed(_move: ChainMove, hit: Dictionary) -> void:
	landed.append(hit)


func _on_tug(step: int, _total: int, _amount: float) -> void:
	tugs_seen.append(step)


func _on_wall_impact(strength: float) -> void:
	walls_seen.append(strength)


func _all_targets() -> Array[Node3D]:
	var out: Array[Node3D] = [dummy]
	for target in lab.targets:
		out.append(target)
	return out


# Targets move out of every possible reach and their AI is switched off: a test
# that measures a sweep must not be measuring where an enemy wandered to.
func _park_everything() -> void:
	for target in _all_targets():
		if not is_instance_valid(target):
			continue
		target.set_process(false)
		target.global_position = PARK
	for i in lab.crates.size():
		var crate := lab.crates[i]
		if not is_instance_valid(crate):
			continue
		crate.freeze = true
		crate.linear_velocity = Vector3.ZERO
		crate.global_position = PARK + Vector3(0.0, 0.5, 2.0 + float(i) * 1.2)
	chain.reset()


func _place_target(weight: StringName, position: Vector3) -> Node3D:
	var target := lab.target_for(weight)
	if target == null:
		_fail("the lab has no %s target to place" % String(weight))
		return null
	target.set_process(false)
	target.global_position = position
	target.rotation = Vector3.ZERO
	target.call("reset_dummy")
	return target


func _stand(position: Vector3, direction: Vector3) -> void:
	player.global_position = position
	player.velocity = Vector3.ZERO
	player.set("external_velocity", Vector3.ZERO)
	player.look_at_from_position(position, position + direction, Vector3.UP)
	# Long enough for the body to settle onto the deck and for the physics server
	# to agree about where everything is, because the head is delivered by queries.
	await _wait(14)


# Throw the hook that is already committed to and wait for it to catch something.
func _hook_now(cap: int) -> bool:
	for i in cap:
		if chain.is_hooked():
			return true
		await _tick(1)
	return chain.is_hooked()


# One simulated frame of the chain plus one real physics frame, in that order: the
# queries the head is delivered with have to see the world as it is.
func _tick(frames: int) -> void:
	for i in frames:
		await physics_frame
		chain.step(DT)


func _tick_until_time(target_time: float) -> void:
	var guard := 0
	while chain.state_time < target_time and guard < 240:
		guard += 1
		await _tick(1)


# Runs until the chain has come back to a hold — the point at which the move is
# over and its whiff cost has been charged but barely any decay has happened.
func _tick_until_held(cap: int) -> void:
	for i in cap:
		await _tick(1)
		if chain.state == ChainDirector.State.HELD:
			return


func _facing_azimuth() -> float:
	var forward := -player.global_basis.z
	return atan2(forward.x, forward.z)


func _move_name(move: ChainMove) -> String:
	return String(move.id) if move != null else "nothing"


func _has_property(object: Object, name: String) -> bool:
	for entry in object.get_property_list():
		if String(entry["name"]) == name:
			return true
	return false


func _wait(frames: int) -> void:
	for i in frames:
		await physics_frame


func _check(condition: bool, reason: String) -> void:
	if not condition:
		failures.append(reason)


func _fail(reason: String) -> void:
	failures.append(reason)


func _finish() -> void:
	if failures.is_empty():
		print(
			"PASS: the chain sweeps wide, carries momentum, changes its inputs when taut, "
			+ "and a hook's outcome is decided by the weight of what it caught"
		)
		quit(0)
		return
	for reason in failures:
		print("  - " + reason)
		push_error(reason)
	print("FAIL: %d problem(s)" % failures.size())
	quit(1)
