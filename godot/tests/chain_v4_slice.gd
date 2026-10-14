extends SceneTree
# 缚星链 · CHAIN V4 — THE A1 VERTICAL SLICE.
#
# THE QUESTION: is the weapon drawn as THREE IDENTITIES rather than as one spline
# from the hand to a point that something slides along?
#
# The user's verdict on V3 is the specification for this file: 摄像机前挂了一条
# spline，末端沿路径运动. That is exactly what one analytic span IS, and no value of
# coil count, sag, pitch or Bezier smoothing can change it — which is why V3 was
# rejected at the level of ABSTRACTION and not at the level of tuning. V4 draws the
# weapon three ways (HELD / SWING / TENSION) and this file asks whether the choice
# is really made, and whether each rig really does its own job.
#
# FIVE CLAIMS, AND EACH ONE IS A NUMBER RATHER THAN A COMPLIMENT:
#
#   §0   the rig FOLLOWS the situation — idle is HELD, a cut is SWING, a bite is
#        TENSION, and it goes back.
#   §11  the fistful GIVES WAY to the throw and comes back. Added after a review
#        frame was read BY EYE as "the bundle is still full during the sweep" when it
#        had in fact shed correctly — the shed was invisible to the frame, which is a
#        property of the shed, but it was also unasserted, which is a property of this
#        file. `drawn_bundle()` exists so this claim can go red.
#   §12  the head LAGS THE HANDLE while it swings, and catches up by the end. A lag
#        that never closed would be a head in the wrong place, which is worse than
#        no lag at all; the second half of that reading is the one that matters.
#   §9   the handle WINDS UP before A1 goes.
#   §18  a head that bit a wall DOES NOT MOVE. Measured as drift over forty frames
#        against the contact transform, because 链头乱漂 is the user's own words for
#        what V3 did here and "the anchor is set" is not the same claim.
#
# WHAT THIS FILE DOES NOT DO: it never reads `visual.drawn_slack()`. §松/§甩/§绷
# already belong to `chain_physicality`, and a second file measuring the same rope
# would only be a second chance to disagree about it.

const DT := 1.0 / 60.0
const PARK := Vector3(60.0, 0.0, 0.0)
# §STOW's band is a rule about the CROSSHAIR, and the crosshair is the centre of the
# projection — so the reading is in NDC and it has to be taken at the SHIPPING frame.
# A headless run has a 64×64 window, and NDC computed from that aspect is a different
# number entirely: the stow would be measured against the wrong rectangle and could pass
# here while failing on screen. 1280×720 is what the review captures, so it is what the
# assertion uses.
const VIEW := Vector2(1280.0, 720.0)
# §STOW's half-band, mirrored from `ChainVisual.SAFE_HALF` because the message has to be
# able to say what it enforced. The brief's 35–40% is a region of the picture and reads
# as ±0.18–0.20 NDC; `SAFE_HALF` is 0.38, i.e. the middle 76% of each axis. The stricter
# reading is the one asserted — a stow that clears 0.38 clears the brief with room to
# spare, and nothing here may loosen it without saying so out loud.
const SAFE_HALF := ChainVisual.SAFE_HALF
# 2.75m off the lab's own wall face. Derived from the wall rather than typed, so
# moving the wall moves the test.
const WALL_GAP := 2.75
# §12's band, as two readings. The brief asks for 50–120ms of lag, and at A1's own
# speed that is 1.5–4 m/s of travel — so the drawn head must get at least a quarter
# of a metre behind the authoritative one somewhere in the strike, and must be back
# within a third of that by the time the strike ends. A lag that never closed is a
# head pointing at nothing.
const LAG_MIN := 0.25
const LAG_CLOSE_SHARE := 0.40
# §11. How many of the bundle's turns a throw has to actually take away before the
# shed is worth calling visible. This is the MAGNITUDE claim only, and it is
# deliberately not the interesting one: the payout alone satisfies it, so on its own
# it goes green with the rig-driven shed switched off. The claim that can only be
# produced by `_bundle_fade` is `lowest < lowest_loops`, below.
const BUNDLE_SHED_MIN := 2
# §18. The head is a fixed point on a surface. This is the whole tolerance, in metres,
# across the entire hold — the anchor is stored as two vectors and nothing re-derives
# it, so anything above a centimetre means something is still moving it.
const ANCHOR_DRIFT_MAX := 0.01

var world: Node3D
var player: CharacterBody3D
var weapon: WeaponSlot
var chain: ChainDirector
var visual: ChainVisual
var head_node: Node3D
var camera: Camera3D
# §14's camera half. Resolved by node name and never assumed: a player without one has to
# read as "the reading cannot be taken", not as a crash inside a `_check`.
var feedback: CameraFeedbackController
# §13's clock. The chain's own events with the frame they landed on, because the beats the
# brief names are an ORDER and an INTERVAL, and neither survives being read off a still.
var _events: Array = []
var _contact_frame := 0
var lab: ChainLab
var moveset: ChainMoveset
var failures: Array[String] = []
var metrics: Dictionary = {}
var _pin := false
var _pin_at := Vector3.ZERO


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene: PackedScene = load("res://scenes/combat/CombatSandbox.tscn")
	world = scene.instantiate()
	root.add_child(world)
	await _wait(12)
	player = world.get_node("Player")
	weapon = player.get_node("WeaponSlot")
	chain = player.get_node("ChainDirector")
	lab = world.get_node_or_null("ChainLab") as ChainLab
	if chain == null or lab == null:
		_fail("the sandbox has no ChainDirector or no ChainLab, so the slice has no stage")
		_finish()
		return
	moveset = chain.moveset
	chain.manual_step = true
	visual = chain.chain_visual
	if visual == null:
		_fail("the chain has no ChainVisual, so there is no drawing to ask about")
		_finish()
		return
	head_node = visual.get_node_or_null("TerminalHead") as Node3D
	if head_node == null:
		_fail("the visual has no TerminalHead")
		_finish()
		return
	# §MOTION's safe-zone clamp projects every frame, and a HEADLESS viewport is a 64×64
	# placeholder whose aspect (1.0) is not the aspect the band rule is written in (1.78).
	# Left alone, the clamp would compress the whole motion to zero here while the reading
	# it was protecting still printed a comfortable 0.850 — a green test of a dead system.
	# EVERY OTHER safe-zone reading in this file already passes its own frame for exactly
	# this reason; the clamp is the one that has to keep running between the readings.
	visual.motion_frame = VIEW
	feedback = player.get_node_or_null("CameraFeedbackController") as CameraFeedbackController
	chain.chain_event.connect(_on_chain_event)
	weapon.equip(WeaponSlot.CHAIN)
	# The eye the stow's readings are taken FROM. Resolved through the viewport rather
	# than by a node path, because the path is the rig's business and this file has no
	# opinion about the rig.
	camera = player.get_viewport().get_camera_3d()
	if camera == null:
		_fail("no camera is current, so §STOW's safe-band reading has no eye to be taken from")
		_finish()
		return

	await _group_rig()
	await _group_bundle()
	await _group_stow()
	await _group_lag()
	await _group_preload()
	await _group_wall()
	await _group_contact()
	await _group_switch()
	await _group_motion()

	_report()
	_finish()


# ============================================================================
#  §0 · THE RIG FOLLOWS THE SITUATION
# ============================================================================

func _group_rig() -> void:
	await _park_everything()
	await _stand(OPEN_STAND, Vector3(0.0, 0.0, -1.0))
	chain.reset()
	await _tick(20)
	metrics["rig_idle"] = String(ChainVisual.Rig.keys()[visual.rig])
	_check(
		visual.rig == ChainVisual.Rig.HELD,
		"a chain at rest is drawn with rig %s — idle is the bundle and a short hang, and it is the rig the player looks at for most of the game"
			% String(ChainVisual.Rig.keys()[visual.rig])
	)
	chain.request(&"light")
	await _tick(6)
	metrics["rig_swing"] = String(ChainVisual.Rig.keys()[visual.rig])
	_check(
		visual.rig == ChainVisual.Rig.SWING,
		"a cut in the air is drawn with rig %s — a swing is where the head leads and the rope tightens"
			% String(ChainVisual.Rig.keys()[visual.rig])
	)
	# …and it goes back, or the weapon would spend the rest of the session being a
	# swung chain that had stopped being swung.
	await _tick(150)
	metrics["rig_after"] = String(ChainVisual.Rig.keys()[visual.rig])
	_check(
		visual.rig == ChainVisual.Rig.HELD,
		"a cut that has finished still leaves the chain in rig %s — the drawing never came home"
			% String(ChainVisual.Rig.keys()[visual.rig])
	)


# ============================================================================
#  §11 · THE FISTFUL GIVES WAY TO THE THROW
# ============================================================================

func _group_bundle() -> void:
	await _park_everything()
	await _stand(OPEN_STAND, Vector3(0.0, 0.0, -1.0))
	chain.reset()
	await _tick(20)
	var held_shown := visual.drawn_bundle()
	var held_loops := visual.coils()
	metrics["bundle_held"] = held_shown
	metrics["bundle_held_loops"] = held_loops
	# §6/§PART H — at rest the drawing IS the rope's own count. A held bundle that
	# kept its own number of turns would be a second system wearing the same links.
	_check(
		held_shown == held_loops and held_shown >= 3,
		"a chain at rest shows %d turns against the rope's own %d — §6 asks for a fistful in the hand, and the count that is a property of the rope is the one the drawing has to use"
			% [held_shown, held_loops]
	)
	chain.request(&"light")
	var lowest := held_shown
	var lowest_loops := held_shown
	var seen := 0
	var guard := 0
	var was_swinging := false
	while guard < 400:
		guard += 1
		await _tick(1)
		var swinging := chain.state == ChainDirector.State.SWINGING
		if was_swinging and not swinging:
			break
		was_swinging = swinging
		if not swinging:
			continue
		seen += 1
		if visual.drawn_bundle() < lowest:
			lowest = visual.drawn_bundle()
			lowest_loops = visual.coils()
	metrics["bundle_low"] = lowest
	metrics["bundle_low_loops"] = lowest_loops
	metrics["bundle_swing_frames"] = seen
	_check(
		seen > 8,
		"the throw only lasted %d frames, so its fistful was never measured" % seen
	)
	_check(
		held_shown - lowest >= BUNDLE_SHED_MIN,
		"the fistful only came down from %d to %d turns during the throw — §11 asks the held bundle to make way for the attack chain, and a shed the frame cannot see is not one"
			% [held_shown, lowest]
	)
	# THE DISCRIMINATING CLAIM, and the first version of this file did NOT have it.
	#
	# `drawn_bundle()` alone cannot separate §11's shed from the rope's own payout:
	# `coils_for()` already walks 7 → 5 turns as the head reaches out, so an assertion
	# that only asked "did the drawn count fall by two" went GREEN AT
	# `BUNDLE_SHED_SHARE = 0.0` — i.e. with the rig-driven shed switched off entirely.
	# It was decoration, and it was caught by mutating the constant rather than by
	# reading the number.
	#
	# What §11 actually claims is that leaving the HELD rig takes turns away ON ITS
	# OWN, so the drawn count has to sit BELOW the count the payout alone would allow.
	# That is the number that can only be produced by `_bundle_fade`.
	_check(
		lowest < lowest_loops,
		"at its emptiest the fistful still showed all %d turns the rope's own count allows — §11's shed is RIG-driven and has to remove turns the reach did not; a fade that only follows `coils_for` is not §11 at all"
			% lowest_loops
	)
	# §11 asks for REDUCED, not EMPTY: a quarter of the coils stay so the rope still
	# has somewhere to come OUT OF, and a hand that empties completely makes the rope
	# start in mid-air — the joint §6 exists to prevent.
	_check(
		lowest >= 1,
		"the fistful emptied to %d turns — §11 keeps part of the bundle in the hand, or the chain has nothing left to leave from"
			% lowest
	)
	# …and it COMES BACK. This is the half that makes "retract → idle" read as the
	# weapon being gathered rather than as a teleport.
	var recovered := 0
	for _i in 240:
		await _tick(1)
		recovered = visual.drawn_bundle()
		if recovered >= held_shown:
			break
	metrics["bundle_recovered"] = recovered
	_check(
		recovered >= held_shown,
		"the fistful only came back to %d of %d turns after the throw — the bundle is gathered again, not left shed, or the hand stays empty for the rest of the session"
			% [recovered, held_shown]
	)


# ============================================================================
#  §STOW · THE SURPLUS IS STOWED, AND "STOWED" IS THREE NUMBERS
# ============================================================================
#
# The brief's rule is that the surplus chain must not sit around the crosshair, and its
# shape requirement is that it reads as a COIL — four open arcs of a continuous winding,
# 最外层最大最内层最小 — rather than as a pile. Both of those were, until now, only
# visible in a render, which means they were reviewed and then un-owned.
#
# THE THREE READINGS, and each one is a number that can go RED:
#
#   1 · breach.      `stow_breach()` is how far the deepest drawn link reaches inside the
#                    central band, so it is 0 or the rule is broken. It is taken in NDC at
#                    the shipping frame (see `VIEW`) because the rule is about the picture.
#   2 · knot.        `stow_interpenetration()` counts pairs of DRAWN links that overlap —
#                    the geometric statement of 不成为一坨. Consecutive links are excluded
#                    by construction (§5 alternation makes them interlock on purpose), so
#                    this number is not measuring the thing that is meant to be there.
#                    `stow_link_clearance()` is the same measurement as a distance, and it
#                    is reported: a stow that passes at 1mm of clearance is not a stow that
#                    is safe to move.
#   3 · order.       §STOW·V4·B sheds the OUTERMOST arcs first, because layer 0 is the arc
#                    the lead-in is welded to. Reversing that loop would empty the rope
#                    from the wrong end and make it start in mid-air — a bug no count can
#                    see, because the count is the same either way. So the visible layers
#                    are asserted to be a PREFIX.
#
# WHAT THIS GROUP DOES NOT DO: it does not check the geometry's constants. It asks the
# drawing, which is the only thing the player sees.
func _group_stow() -> void:
	await _park_everything()
	await _stand(OPEN_STAND, Vector3(0.0, 0.0, -1.0))
	chain.reset()
	await _tick(20)
	var breach: float = visual.call("stow_breach", camera, VIEW)
	# THE RING MODEL, NOT THE BOX MODEL, and the change is forced by the interlock. Boxes
	# were a faithful proxy while pitch (0.11) EXCEEDED the link's length (0.0946): no two
	# links shared a pixel, so a box round each one described it. Once `LINK_FILL` goes
	# above 1 the chain locks, two coplanar neighbours become solid slabs a curved path
	# rotates into each other, and the box count measures the alternation instead of a
	# defect — 16 "overlaps" of pairs whose real geometry is two RINGS with the odd link
	# threading between them. See `_stow_link_rings`.
	var rings: Dictionary = visual.call("stow_ring_readings")
	var straight: Dictionary = visual.call("chain_straight_clearance")
	var bend: float = visual.call("chain_min_bend_radius")
	var fan: float = visual.call("stow_tightest_radius")
	metrics["stow_breach"] = breach
	metrics["stow_neighbour"] = rings.neighbour
	metrics["stow_layered"] = rings.layered
	metrics["stow_link_flat"] = straight.adjacent
	metrics["stow_link_skip1"] = straight.skip1
	metrics["stow_bend"] = bend
	metrics["stow_fan"] = fan
	metrics["stow_margin"] = visual.call("stow_margin", camera, VIEW)
	metrics["stow_links"] = visual.links_drawn()
	_check(
		breach <= 0.0,
		"the stowed surplus reaches %.4f NDC inside the central band — 余链永远不能出现在准星周围, so nothing the stow draws may touch |x| or |y| below %.2f (the middle 76%% of each axis; the brief asks for 35–40%%, so this is the stricter of the two and it is the one enforced)"
			% [breach, SAFE_HALF]
	)
	# THE OTHER HALF OF THE SAME RULE, AND IT WAS MISSING UNTIL IT FAILED IN A FRAME.
	# `breach` only asks whether the surplus reached the MIDDLE of the picture. A stow that
	# is too BIG does not breach — it walks out of the left edge, and `breach` keeps reading
	# a clean 0.0000 the whole time. MEASURED on the circular-arc pass: breach 0.0000 with
	# layer 3 at NDC x −1.382, y −1.147, one to four tenths of the frame OUTSIDE the
	# picture. `stow_frame_reach()` is the farthest any drawn link reaches, and the frame is
	# 1.0, so this is the assertion that would have caught it.
	var reach: float = visual.call("stow_frame_reach", camera, VIEW)
	metrics["stow_reach"] = reach
	_check(
		reach < 1.0,
		"the stowed surplus reaches |max(nx,ny)| %.3f, outside the 1.0 frame — 余链 must be STOWED, and chain drawn off the edge of the picture is chain the player cannot see; `stow_breach` cannot catch this because a fan too big never enters the middle, it walks out of the left edge"
			% reach
	)
	# WHAT THE STOW OWNS: its own layering. Pairs two or more apart on the rope, in
	# different layers or the same one, must have positive material clearance.
	_check(
		float(rings.layered) >= 0.0,
		"the stow's own layering is %.4f m into interference — 多出来的链条 must not be 一坨金属毛线, and this is the reading of that, taken between the rings themselves rather than their bounding boxes"
			% float(rings.layered)
	)
	# WHAT THE LINK OWNS, and it is checked FIRST because nothing the stow does can fix it:
	# if the link cannot thread ITSELF on a dead straight run, no arrangement of arcs can
	# make a chain. `|pitch − ring radius| < ring inner radius` is the constraint, and
	# `chain_interlock_bounds()` is its closed form.
	_check(
		float(straight.adjacent) >= 0.0,
		"the link cannot thread itself: adjacent links on a STRAIGHT run interfere by %.4f m, which is the link's own geometry and not the stow's (pitch %.4f vs the %.4f…%.4f band the link admits, from `chain_interlock_bounds`)"
			% [
				-straight.adjacent, visual.link_spacing,
				(visual.call("chain_interlock_bounds") as Dictionary).min,
				(visual.call("chain_interlock_bounds") as Dictionary).max
			]
	)
	_check(
		float(straight.skip1) >= 0.0,
		"coplanar neighbours (i, i+2) interfere by %.4f m on a straight run — the pitch is %.4f and two of them must span a link, which is %.4f m long"
			% [-straight.skip1, visual.link_spacing, 2.0 * visual.link_spacing]
	)
	# AND WHETHER THE PATH CAN BE MADE OF LINKS AT ALL. A chain cannot be bent below its
	# own minimum radius; the fan's arcs are a squashed ellipse whose ends turn at `b²/a`.
	# Guarded on `bend > 0` because `chain_min_bend_radius()` returns −1 when NO radius
	# works — which is what the link's own interference produces, and is a different fault
	# (the one above) rather than a bend failure.
	_check(
		bend > 0.0 and fan >= bend,
		("the fan turns at %.4f m radius where this chain can only bend at %.4f m — the arcs are drawn tighter than the links can follow, so they interpenetrate at the curve and no pitch fixes it (shrinking the pitch scales the turn per step but not the LINK)"
			% [fan, bend])
		if bend > 0.0
		else "the fan cannot be judged for bend because the LINK has no workable bend radius at all (adjacent links already interfere when straight — see the previous reading); the drawn path does turn as tight as %.4f m"
			% fan
	)
	# ---- §JOINT · THE OTHER END OF THE SAME ROPE, WHICH IS THE USER'S OWN RULE ----------
	# 不要穿模刀手柄 is a rule about the HANDLE, and until now nothing measured it: every
	# reading above judges the stow at the hip. It regressed silently for two revisions —
	# the eye sat on the shaft's axis and the lead-in left it along `(0, -1, 0)` in the
	# STOW's own space, which is 18.1 deg off the handle's own axis, so the rope entered the
	# metal collar's top face and left through its side. Measured when the reading was
	# finally written: rope −0.0177 m, ring −0.0450 m, and every §STOW number green.
	#
	# THREE claims, because there are three separate ways to be inside the hilt and the fix
	# had to satisfy all of them: the rope's PATH clears the metal, the EYE clears the metal,
	# and the eye's HOLE faces the rope.
	# THE THRESHOLDS ARE DELIBERATELY WEAK, AND THE WEAKNESS IS THE CLAIM. Both readings are
	# the rope's CENTRELINE against the hilt's SILHOUETTE, so they do not say "no pixel of a
	# link overlaps the metal" — a link is 6.2cm across the rope, and that claim would need
	# 0.031 here. What they say is "the rope's path is OUTSIDE the hilt", by a centimetre
	# rather than by a hair, and a hair is exactly what the failure looked like: mutating
	# `HANDLE_EYE_OUT` back to 0 reads `rope +0.0000`, which `> 0.0` passes and `> 0.010`
	# does not. An assertion whose margin is zero is an assertion that comes back.
	var hilt: float = visual.call("stow_hilt_clearance")
	var eye_clear: float = visual.call("stow_eye_clearance")
	var threading: float = visual.call("stow_eye_threading")
	metrics["joint_hilt"] = hilt
	metrics["joint_eye"] = eye_clear
	metrics["joint_thread"] = threading
	_check(
		hilt > 0.010,
		"the lead-in runs %.4f m inside the sword's hilt — the rope's first links are the weapon's joint with the hand, so it has to leave the eye on a path that clears the grip, the collar and the hand stop by a centimetre (silhouette read off the drawn meshes, `handle_radius_at()`)"
			% hilt
	)
	_check(
		eye_clear > 0.005,
		"the chain eye's own ring is %.4f m from the hilt it hangs from — the eye is a part of its own sitting on the collar's shoulder, and the rope's clearance cannot cover for it"
			% eye_clear
	)
	_check(
		threading < 20.0,
		"the eye stands %.1f deg across the rope — a torus is an EYELET and the rope passes through its HOLE, so the ring's axis has to BE the direction the rope leaves in; anything near 90 is a ring jammed into the collar however clear its outline is"
			% threading
	)
	# THE ORDER, read off the nodes the renderer actually switches — AND IT IS READ FROM
	# INSIDE A THROW, WHICH IS THE WHOLE POINT.
	#
	# At rest all four layers are drawn, so `visible == (i < 4)` is true of EVERY ordering
	# and the first version of this assertion went GREEN WITH THE SHED LOOP REVERSED. It was
	# decoration, and mutating the loop is what showed it. The claim is about WHICH layers go
	# first, so it has to be taken at a moment when some of them have gone — hence the throw.
	var loops: Array = visual.get("_coil_loops")
	var shown: int = visual.drawn_bundle()
	metrics["stow_shown"] = shown
	metrics["stow_layers"] = loops.size()
	chain.request(&"light")
	var stray := -1
	var sampled := -1
	var guard := 0
	while guard < 400 and sampled < 0:
		guard += 1
		await _tick(1)
		var n: int = visual.drawn_bundle()
		if n >= 1 and n < loops.size():
			sampled = n
			for i in loops.size():
				if (loops[i] as MeshInstance3D).visible != (i < n):
					stray = i
					break
	metrics["stow_shed_shown"] = sampled
	_check(
		sampled >= 1,
		"the throw never left the stow short of a layer, so §STOW·V4·B's shed was never observed and the order claim below would be vacuous"
	)
	_check(
		stray < 0,
		"layer %d is drawn out of order while %d of %d layers are shown — §STOW·V4·B sheds the OUTERMOST first and keeps layer 0, the arc the lead-in is welded to, or the rope starts in mid-air"
			% [stray, sampled, loops.size()]
	)
	# …and it comes back, or the surplus would be permanently short after one attack.
	var back_guard := 0
	while back_guard < 400 and visual.drawn_bundle() < loops.size():
		back_guard += 1
		await _tick(1)
	_check(
		visual.drawn_bundle() == loops.size(),
		"the stow only came back to %d of %d layers — the surplus is gathered again after a throw, or the weapon loses rope every attack"
			% [visual.drawn_bundle(), loops.size()]
	)


# ============================================================================
#  §12 · THE HEAD LAGS THE HANDLE, AND CATCHES UP
# ============================================================================

func _group_lag() -> void:
	await _park_everything()
	await _stand(OPEN_STAND, Vector3(0.0, 0.0, -1.0))
	chain.reset()
	chain.request(&"light")
	var worst := 0.0
	var worst_at := 0
	var last := 0.0
	var frames := 0
	var guard := 0
	var was_swinging := false
	while guard < 400:
		guard += 1
		await _tick(1)
		var swinging := chain.state == ChainDirector.State.SWINGING
		if was_swinging and not swinging:
			break
		was_swinging = swinging
		if not swinging:
			continue
		frames += 1
		var gap := visual.drawn_head().distance_to(chain.head_position())
		if gap > worst:
			worst = gap
			worst_at = frames
		last = gap
	metrics["lag_worst"] = worst
	metrics["lag_worst_frame"] = worst_at
	metrics["lag_last"] = last
	metrics["lag_frames"] = frames
	_check(
		frames > 8,
		"the strike only lasted %d frames, so nothing about its lag was measured" % frames
	)
	_check(
		worst > LAG_MIN,
		"the drawn head never got more than %.3fm behind the real one — §12 asks for 50–120ms of lag between the handle and the head, and at A1's own speed that is metres, not centimetres"
			% worst
	)
	_check(
		last < worst * LAG_CLOSE_SHARE,
		"the drawn head is still %.3fm behind after %.3fm at its worst — a lag that never closes is a head in the wrong place, which is worse than no lag"
			% [last, worst]
	)


# ============================================================================
#  §9 · THE HANDLE WINDS UP BEFORE THE CUT GOES
# ============================================================================

func _group_preload() -> void:
	await _park_everything()
	await _stand(OPEN_STAND, Vector3(0.0, 0.0, -1.0))
	chain.reset()
	chain.request(&"light")
	var peak := 0.0
	var peak_frame := 0
	var frames := 0
	var during_active := 0.0
	var guard := 0
	var was_swinging := false
	while guard < 400:
		guard += 1
		await _tick(1)
		frames += 1
		var swinging := chain.state == ChainDirector.State.SWINGING
		if was_swinging and not swinging:
			break
		was_swinging = swinging
		if not swinging:
			continue
		# STARTUP AND ACTIVE ARE BOTH `SWINGING`. Measuring "before the swing" as
		# "any frame not in SWINGING" finds nothing at all, because a cut is in
		# SWINGING from the frame it is requested — so the split has to be the move's
		# own startup boundary. (This reading first came back 0.00 / 1.00 because of
		# exactly that, which is why the number is reported with the phase in it.)
		var startup := chain.active_move.startup if chain.active_move != null else 0.25
		var amount := visual.preload_amount()
		if chain.state_time < startup:
			if amount > peak:
				peak = amount
				peak_frame = frames
		else:
			during_active = maxf(during_active, amount)
	metrics["preload_peak"] = peak
	metrics["preload_peak_frame"] = peak_frame
	metrics["preload_during_strike"] = during_active
	_check(
		peak > 0.5,
		"the handle only wound up to %.2f before A1 — §9 asks for a real anticipation, and a wind-up the player cannot see is not a cause"
			% peak
	)
	_check(
		during_active < 0.05,
		"the wind-up is still at %.2f while the strike is running — the anticipation has to be SPENT by the time the head goes, or the arc is fighting it"
			% during_active
	)
	# The head has no preload of its own. §9 and §12 compose: the handle moves first
	# and the head follows, which is a different claim from both of them together
	# moving, and it is the difference between a thrown mass and a rigid one.
	_check(
		metrics.get("lag_worst", 0.0) > LAG_MIN,
		"the head did not lag the handle, so the 'handle first' reading is not being produced by the lag either"
	)


# ============================================================================
#  §18/§19 · THE WALL BITE — THE HEAD DOES NOT MOVE
# ============================================================================

func _group_wall() -> void:
	await _park_everything()
	await _stand(WALL_STAND, Vector3(0.0, 0.0, -1.0))
	chain.reset()
	chain.momentum = 0.6
	var before := chain.wall_hits
	chain.request(&"chain_hook")
	var guard := 0
	while guard < 200 and not chain.is_anchored():
		guard += 1
		await _tick(1)
	if not chain.is_anchored():
		_fail("the throw never registered a wall bite, so the anchor was never measured")
		return
	metrics["anchor_frames_to_bite"] = guard
	_check(chain.wall_hits > before, "a throw into the wall never registered a wall hit")
	# §0 — and the drawing switched to the rig whose whole job this is.
	_check(
		visual.rig == ChainVisual.Rig.TENSION,
		"an anchored chain is drawn with rig %s — the contact rig is the only one that guarantees the head cannot drift"
			% String(ChainVisual.Rig.keys()[visual.rig])
	)
	var anchor := chain.anchor_point()
	var front := ChainLab.WALL_Z + 0.35
	metrics["anchor_z"] = anchor.z
	_check(
		absf(anchor.z - front) < 0.30,
		"the anchor was stored at z=%.2f, and the wall's own face is at %.2f — a bite has to be a place on the surface"
			% [anchor.z, front]
	)
	# THE DRIFT READING. Forty frames of hold, and the head's own position has to
	# stay put. This is the number that replaces 链头乱漂, and it is why the anchor is
	# two stored vectors rather than a pose that gets re-derived every frame.
	var first := chain.head_position()
	var drift := 0.0
	for _i in 40:
		await _tick(1)
		drift = maxf(drift, chain.head_position().distance_to(first))
	metrics["anchor_drift"] = drift
	_check(
		drift < ANCHOR_DRIFT_MAX,
		"the head moved %.4fm while it was bitten into a static wall — §18 asks for contact_position / surface_normal and NO drift, and this is the reading that says whether that is true"
			% drift
	)
	# §19 — the bite is a BEAT, not an instant: it has to complete, and the chain has
	# to come up on the same beat.
	metrics["bite_phase"] = visual.bite_phase()
	metrics["chain_load"] = visual.load()
	_check(
		visual.bite_phase() > 0.99,
		"the bite only reached %.2f of its length — the head never finished driving into the surface, so there was no 咬住 beat"
			% visual.bite_phase()
	)
	_check(
		visual.load() > 0.85,
		"the anchored chain is only %.2f loaded — §20 asks the rope to come up on the bite, and a slack chain hanging off a wall it bit does not read as loaded"
			% visual.load()
	)
	# §18 — ORIENTATION. The central blade runs INTO the surface. `_head_dir` is the
	# head's forward, and `_basis_along` puts local -Z along it.
	var blade := -head_node.global_basis.z
	var into_the_wall := -chain.anchor_normal()
	metrics["blade_into_wall"] = blade.dot(into_the_wall)
	_check(
		blade.dot(into_the_wall) > 0.90,
		"the trident's central blade points %.2f along the wall's own inward normal — §18 wants the blade bitten in, not lying across the surface at whatever angle the arc happened to end on"
			% blade.dot(into_the_wall)
	)
	# …and it LETS GO. An anchor that outlived the hold would leave a weapon stuck to
	# the architecture for the rest of the session.
	var released := false
	for _i in 240:
		await _tick(1)
		if not chain.is_anchored():
			released = true
			break
	_check(released, "the anchor never released — the chain is still attached to the wall long after the hold expired")


# ============================================================================
#  STAGE
# ============================================================================

# ============================================================================
#  §12/§13/§14 · THE CONTACT BEAT, THE TENSION TAKEOVER, AND THE HAND
# ============================================================================
#
# The brief gives this moment an ORDER — CONTACT → 50–100ms → BITE → CHAIN TIGHTEN → HAND
# RESISTANCE — and an order is the one thing a still cannot show. So the readings here come
# off the chain's OWN event stream (`chain_event`) on a clock this group drives, and the
# three claims are read from that: the interval, the fact that the rope does NOT come up
# before the bite, and what the hand and the camera do once it has.
#
# §12's half needs the player MOVING while the chain is out, because a trail that was never
# there cannot be seen to stop: measured at a standstill, every number below is zero for the
# wrong reason.

const CONTACT_BITE_MIN_MS := 50.0
const CONTACT_BITE_MAX_MS := 110.0  # §13 says 100; `wall_bite_time` is 0.10, so the frame
                                    # that consumes the last delta is the boundary case
const LOADED_TRAIL_MAX := 0.006     # m — a walking trail must be gone, not merely smaller
const HANDLE_RESIST_MIN := 0.02     # §14's 2–5 cm
const HANDLE_RESIST_MAX := 0.05
const KNOCK_MAX := 0.08             # a landing uses 0.035, so this is 不要：Shake Spam's ceiling
const WALL_TRAUMA_MAX := 0.15


func _group_contact() -> void:
	await _park_everything()
	await _stand(WALL_STAND, Vector3(0.0, 0.0, -1.0))
	chain.reset()
	await _tick(20)

	# ---- §12 · A LOADED CHAIN STOPS DRIFTING -----------------------------
	#
	# Backing away from the wall rather than toward it, so the walk cannot turn into the
	# thing this group is about to measure. The direction is the look's own backward, taken
	# from the rig instead of typed.
	var retreat := camera.global_transform.basis.z
	await _travel(retreat, WALK_SPEED, 40)
	var trail_walking := visual.motion_drag().length()
	_events.clear()
	_contact_frame = 0
	chain.momentum = 0.6
	chain.request(&"chain_hook")
	var idle_loaded := 0.0
	var trail_loaded := 999.0
	for _i in 12:
		await _contact_step(retreat)
		idle_loaded = maxf(idle_loaded, visual.motion_idle().length())
		trail_loaded = minf(trail_loaded, visual.motion_drag().length())
	var rig_left_hold := visual.rig != ChainVisual.Rig.HELD
	metrics["contact_trail_walking"] = trail_walking
	metrics["contact_trail_loaded"] = trail_loaded
	metrics["contact_idle_loaded"] = idle_loaded
	_check(
		trail_walking > 0.02,
		"walking with the chain held put only %.4f m of trail on the surplus, so there was nothing to lose — §12 is about a motion that exists and then stops, and a fan that never moved satisfies it by accident" % trail_walking
	)
	_check(
		rig_left_hold,
		"the throw never left the HELD rig, so §12's takeover was never exercised and the readings below are about the idle case"
	)
	_check(
		idle_loaded < 0.0001,
		"with the chain thrown the surplus still drifted %.5f m on §7's breathing — 不要：继续：Idle Lag, and a stow that keeps breathing while the rope is being paid out reads as the chain resisting the throw" % idle_loaded
	)
	_check(
		trail_loaded < LOADED_TRAIL_MAX,
		"a %.4f m walking trail was still on the surplus twelve frames after the throw began — §12 asks the four layers to give way to the force relationship 立即, and MOTION_LOAD_TAU is %.3f s, so this is a spring that ignored the load" % [trail_loaded, visual.MOTION_LOAD_TAU]
	)

	# ---- §13 · THE BEAT, IN ORDER AND ON THE CLOCK -----------------------
	#
	# Everything that decays has to be read ON the contact frame, and the camera is the
	# reason: `CameraFeedbackController` bleeds trauma at 1.8/s and the impulse at 9/s, so
	# a knock of 0.02 is gone in about three frames. Read after the bite instead of at the
	# contact and the answer is always 0.000 — which is what the first version reported
	# while the nudge was working perfectly.
	var tension_at_contact := -1.0
	var load_at_contact := -1.0
	var knock := -1.0
	var trauma_at_contact := -1.0
	var guard := 0
	var f_contact := -1
	var f_bite := -1
	var f_tension := -1
	while guard < 240 and f_bite < 0:
		guard += 1
		await _contact_step()
		f_contact = _event_frame(&"CHAIN_CONTACT")
		f_bite = _event_frame(&"CHAIN_BITE")
		f_tension = _event_frame(&"CHAIN_TENSION_START")
		if f_contact >= 0 and tension_at_contact < 0.0:
			tension_at_contact = chain.tension
			load_at_contact = visual.load()
			knock = feedback.impulse.length() if feedback != null else -1.0
			trauma_at_contact = feedback.trauma if feedback != null else -1.0
	# THE CHAIN TIGHTEN, read off the DRAWN ROPE. The director's own `tension` is the wrong
	# instrument here and its silence is correct: it is the rope being STRETCHED, and a
	# throw that catches a wall 2.6 m away has most of a 10 m rope still on the hip, so it
	# reads 0.000 no matter what the contact does. What §13's fourth beat is about is the
	# picture coming up — the sag leaving the line — and that is `load()`.
	var load_after_bite := 0.0
	for _i in 20:
		await _contact_step()
		load_after_bite = maxf(load_after_bite, visual.load())
	var bite_ms := float(f_bite - f_contact) * DT * 1000.0 if (f_contact >= 0 and f_bite >= 0) else -1.0
	metrics["contact_frames"] = {"contact": f_contact, "bite": f_bite, "tension": f_tension}
	metrics["contact_bite_ms"] = bite_ms
	metrics["contact_tension_at_contact"] = tension_at_contact
	metrics["contact_load_at_contact"] = load_at_contact
	metrics["contact_load_after_bite"] = load_after_bite
	_check(
		f_contact >= 0 and f_bite >= 0,
		"the throw into the wall never produced both a CONTACT and a BITE — §13's four beats are a sequence, and a chain that skips one has no 咬住 to read"
	)
	_check(
		bite_ms >= CONTACT_BITE_MIN_MS and bite_ms <= CONTACT_BITE_MAX_MS,
		"CONTACT → BITE took %.0f ms (frame %d → %d) against the %.1f s the move authors — §13 names 50–100 ms as the beat that separates 撞上了 from 咬住了, and outside it the two read as the same event" % [bite_ms, f_contact, f_bite, moveset.wall_bite_time]
	)
	_check(
		f_tension == f_bite,
		"the tension started on frame %d and the bite announced on frame %d — §13 puts CHAIN TIGHTEN AFTER the bite, and the two are one beat by construction (`_step_bite` announces both)" % [f_tension, f_bite]
	)
	_check(
		load_at_contact >= 0.0 and load_at_contact < 0.55,
		"the rope was already %.2f loaded on the CONTACT frame — §13's bite only means something if the line does NOT come up on the frame the head touches, because a rope that is already straight has no 咬住 to show" % load_at_contact
	)
	_check(
		load_after_bite > load_at_contact + 0.25,
		"twenty frames after the bite the drawn rope was only at %.2f load, against %.2f on the contact — §13's fourth beat is CHAIN TIGHTEN, and a bite the rope never answers is a head stuck to a wall" % [load_after_bite, load_at_contact]
	)

	# ---- §14 · THE WEIGHT IS IN THE HAND --------------------------------
	#
	# Read at the moment of the bite's end, which is when `_load` is up and the handle has
	# been hauled. The DIRECTION is half the claim: a handle pulled 4.5 cm the wrong way is
	# still 4.5 cm of weight and still wrong.
	var hand := chain._hand_position()
	var anchor := chain.anchor_point()
	var resist := visual.handle_resist()
	var toward_anchor := (anchor - hand).normalized()
	var resist_len := resist.length()
	metrics["handle_resist_m"] = resist_len
	metrics["handle_resist_align"] = resist.dot(toward_anchor)
	_check(
		resist_len >= HANDLE_RESIST_MIN and resist_len <= HANDLE_RESIST_MAX,
		"a fully loaded chain hauled the handle %.4f m — §14 asks for 2–5 cm, and this is the channel the weight is supposed to come from (不要：Shake Spam)" % resist_len
	)
	_check(
		resist.dot(toward_anchor) > resist_len * 0.80,
		"the handle was hauled %.4f m but only %.4f of it along the rope — §14 wants the weapon pulled TOWARD what the chain caught on, and a displacement across the line is a handle that slid rather than one that resisted. The remainder is the bite's own 7 cm drive, which puts the drawn head slightly inside the surface" % [resist_len, resist.dot(toward_anchor)]
	)
	# ...and the camera, which is where the BOUND is. Trauma is omnidirectional and the
	# knock is directional; §14 asks for the second and forbids the first from being a spam.
	metrics["wall_knock"] = knock
	metrics["wall_trauma"] = trauma_at_contact
	_check(
		feedback != null,
		"the player has no CameraFeedbackController, so §14's camera half cannot be read at all"
	)
	_check(
		knock > 0.0 and knock <= KNOCK_MAX,
		"the wall contact left the camera with %.4f of directional impulse (a landing uses 0.035) — §14 asks for a VERY LIGHT nudge, and zero is what a direction taken from the surface normal gives for a wall you are facing" % knock
	)
	_check(
		feedback != null and trauma_at_contact <= WALL_TRAUMA_MAX,
		"the wall contact left %.3f of trauma on the camera — 不要：Shake Spam; §14 says the weight comes from the HANDLE, so the shake has to stay the smaller channel" % trauma_at_contact
	)
	# The direction, as an independent physical claim rather than a re-run of the formula:
	# the anchor is below the eye, so a chain hauling on it pulls the muzzle DOWN.
	_check(
		feedback != null and feedback.impulse.y < 0.0,
		"the chain bit a wall below the eye line (anchor y %.2f, camera y %.2f) and the camera's pitch nudge was %+.4f — §14's knock has to point the way the rope pulls, and an upward kick off something under the player is the sign error that makes the whole channel read as a hit rather than a catch" % [anchor.y, camera.global_position.y, feedback.impulse.y if feedback != null else 0.0]
	)


# ============================================================================
#  §16 · PUTTING THE WEAPON AWAY AND PICKING IT UP AGAIN
# ============================================================================
#
# 1 → 2 is the one input that can leave a weapon half way through a sentence, and §16
# names six things that have to hold afterwards: A1, the full stow, no tension, no stale
# contact, no technique in flight and no old target. `chain_combo_memory` proves the first
# of those by PLAYING the next press; this asks the other five by reading the state,
# because a weapon that looks reset and still holds an anchor is the bug that outlives the
# scene the anchor was bitten into.
#
# The state is made as DIRTY as the switch has to survive — a bite in the wall, an arc
# already shed, a technique in flight, a target on the list — and the first assertion is
# that it really was dirty. A reset test that starts from a clean weapon measures nothing.

func _group_switch() -> void:
	await _park_everything()
	await _stand(WALL_STAND, Vector3(0.0, 0.0, -1.0))
	chain.reset()
	await _tick(10)
	chain.momentum = 0.6
	chain.request(&"chain_hook")
	var guard := 0
	while guard < 200 and not chain.is_anchored():
		guard += 1
		await _tick(1)
	await _tick(8)
	var arcs_before := visual.release_step()
	metrics["switch_dirty_anchored"] = chain.is_anchored()
	metrics["switch_dirty_arcs"] = arcs_before
	_check(
		chain.is_anchored() and arcs_before > 0,
		"the state going into the switch was already clean (anchored %s, shed arcs %d, in flight %s), so this group would prove nothing about the switch" % [chain.is_anchored(), arcs_before, chain.active_move != null]
	)

	# ---- the switch ---------------------------------------------------------
	weapon.equip(WeaponSlot.SWORD)
	await _tick(4)
	# Cleanliness is checked BEFORE the chain comes back, so that the repack §11 demands
	# cannot be mistaken for a stale arc: a weapon that is not in hand has no stow at all.
	var stowed_while_away := visual.release_step()
	weapon.equip(WeaponSlot.CHAIN)
	# THE REPACK IS A BEAT, NOT A TELEPORT (§11), so it is given its own length rather
	# than a frame count: `BUNDLE_GATHER_TIME` is what the ladder costs, and a stow that
	# snapped home would be the failure the ladder was introduced to fix.
	var repack_frames := int(ceil(visual.BUNDLE_GATHER_TIME / DT)) + 6
	await _tick(repack_frames)

	var index_after: int = chain.get("_chain_index")
	metrics["switch_stowed_away"] = stowed_while_away
	metrics["switch_index"] = index_after
	metrics["switch_arcs"] = visual.release_step()
	metrics["switch_rig"] = String(ChainVisual.Rig.keys()[visual.rig])
	metrics["switch_load"] = visual.load()
	_check(
		chain.state == ChainDirector.State.HELD,
		"coming back to the chain left it in %s — §16 asks a switched-away weapon to be put down, and the only state that means put down is HELD" % String(ChainDirector.State.keys()[chain.state])
	)
	_check(
		chain.active_move == null,
		"a technique was still in flight after the weapon was switched away and back — §16's 没有攻击链"
	)
	_check(
		index_after == 0,
		"the sentence came back at index %d — §16 asks the next press to be A1, and `chain_combo_memory` proves it by pressing; this is the same claim read one layer down" % index_after
	)
	_check(
		not chain.is_anchored(),
		"the chain came back still anchored to the wall it bit before the switch — §18 says a wiped weapon is not attached to anything, and an anchor that survives a switch points at geometry that may not exist any more"
	)
	_check(
		chain.bound_left <= 0.0 and chain.get("_hook_actor") == null,
		"the chain came back still holding a body (bound %.2f s, actor %s) — §16's 没有旧目标" % [chain.bound_left, str(chain.get("_hook_actor"))]
	)
	_check(
		(chain.get("_hit_targets") as Array).is_empty(),
		"the chain came back with %d target(s) already on its hit list — a list that survives a switch makes the first press after it unable to hit the same enemy twice" % (chain.get("_hit_targets") as Array).size()
	)
	_check(
		visual.release_step() == 0,
		"the stow came back with %d arc(s) still shed — §16's 余链 = 满, and §11's repack is the beat that is supposed to have finished by now" % visual.release_step()
	)
	_check(
		visual.rig == ChainVisual.Rig.HELD,
		"the drawing came back on the %s rig — a stow drawn on the contact rig is a bundle of chain arranged around a wall it is no longer touching" % String(ChainVisual.Rig.keys()[visual.rig])
	)
	_check(
		visual.load() < 0.05,
		"the stow came back %.2f loaded — §16's 没有张力, and a weapon that reads as loaded while it is hanging at the hip has its sag and its handle response displaced by a load that is not there" % visual.load()
	)


## ONE frame of this group's own clock. §13's reading is an INTERVAL, and `_tick` carries no
## frame index to measure one with, so the group drives its own loop and counts.
func _contact_step(walk: Vector3 = Vector3.ZERO) -> void:
	await physics_frame
	_pin = false
	if walk != Vector3.ZERO:
		player.global_position += walk.normalized() * WALK_SPEED * DT
		player.global_position.y = _pin_at.y
	player.velocity = Vector3.ZERO
	_contact_frame += 1
	chain.step(DT)


func _on_chain_event(event: StringName, _data: Dictionary) -> void:
	_events.append([event, _contact_frame])


## The frame the FIRST occurrence of an event landed on, or −1. First and not last because
## this is a throw: a second RATTLE later in the same episode says nothing about the order
## of the four beats.
func _event_frame(event: StringName) -> int:
	for e in _events:
		if e[0] == event:
			return e[1]
	return -1


# ============================================================================
#  §MOTION · CONTROLLED INERTIA — THE FROZEN POSE IS NOT TOUCHED, IT IS MOVED
# ============================================================================
#
# Every reading here is taken against `ChainVisual`'s own numbers and not against a
# picture, because the failure this group exists to catch is precisely the one a picture
# cannot show: a lag and a decal look identical in a still. `motion_lag()` is the offset
# ACTUALLY APPLIED (after the safe-zone clamp), so "did it lag", "was it bounded" and "was
# it compressed" are three separate readings rather than one impression.

const WALK_SPEED := 3.4          # m/s — what `MOTION_LAG_PER_SPEED` is sized against
const SPRINT_SPEED := 7.2        # m/s — §8 asks a sprint to drag visibly more
const TURN_RATE_DEG := 190.0     # deg/s — a fast look, which §4 caps at 8°
const NOD_RATE_DEG := 150.0      # deg/s — the same rate into pitch, to show it gives less
const OVERSHOOT_MIN := 0.0015    # m — §3's 继续前移几厘米 has to actually happen
const OVERSHOOT_MAX := 0.045     # m — ...and has to stay 克制
const RESIDUAL_TOL := 0.006      # m — when the surplus counts as settled


func _group_motion() -> void:
	await _park_everything()
	await _stand(OPEN_STAND, Vector3(0.0, 0.0, -1.0))
	chain.reset()
	await _tick(24)

	# ---- §7 · ALIVE, NOT ANIMATED -----------------------------------------
	#
	# Measured FIRST and at rest on purpose: everything below is about motion, and the
	# only way to tell a drift from a lag is to take the still reading before any of the
	# moving ones.
	#
	# AND IT READS `motion_idle()`, NOT THE TOTAL. The hand hangs under the camera rig, so
	# it is never perfectly still — tremor, look-lag and the sway spring all leave a
	# millimetre on it — and the first version of this block measured `motion_lag()`, which
	# therefore stayed above the floor even with §7's drift deleted from the sum. The
	# assertion passed for the wrong reason, which the mutation sweep showed by removing
	# the drift entirely and getting a green run. A window is taken rather than one frame
	# for the same reason a single sample of a two-frequency sine is not a reading.
	var idle_peak := 0.0
	var idle_first := visual.motion_idle().length()
	for _i in 90:
		await _still(1)
		idle_peak = maxf(idle_peak, visual.motion_idle().length())
	metrics["motion_idle_first"] = idle_first
	metrics["motion_idle_peak"] = idle_peak
	_check(
		idle_peak > 0.0015,
		"a chain standing still never got further than %.5f m from its rest pose over 1.5 s — §7 asks for a breathing drift of about a centimetre, and a stow that is bit-identical every frame is 完全静止 rather than alive" % idle_peak
	)
	_check(
		idle_peak < 0.032,
		"the at-rest drift reached %.4f m — §7 says 必须几乎感觉不到, so this is a motion and not a sway" % idle_peak
	)

	# ---- §2/§3 · A WALK DRAGS IT BACK, AND STOPPING OVERSHOOTS -----------
	#
	# The travel direction is the camera's own forward, taken from the rig rather than
	# typed, so the overshoot is measured along the axis the player actually moved on.
	var fwd := -camera.global_transform.basis.z
	await _travel(fwd, WALK_SPEED, 70)
	var walk_lag := visual.motion_drag()
	var walk_speed := visual.motion_hand_speed()
	# The trail has to point AWAY from the travel. Signed, so a lag in the direction of
	# travel — the sign error that would make the surplus lead the hand — cannot pass by
	# being the right size.
	var drag := walk_lag.dot(fwd)
	metrics["motion_walk_lag"] = walk_lag.length()
	metrics["motion_walk_signed"] = drag
	metrics["motion_walk_speed"] = walk_speed
	_check(
		drag < -0.004,
		"walking at %.2f m/s put the surplus %+.4f m along the travel axis — §3 asks it to trail BEHIND (negative), and the sign is half of that claim" % [walk_speed, drag]
	)

	# ...and the same frame must still be a legal frame. §5's clamp is the reason this is
	# asserted at the moment of MAXIMUM lag rather than at rest: at rest it is trivially
	# true, and the whole motion system could be broken while passing.
	var lag_breach: float = visual.call("stow_breach", camera, VIEW)
	var lag_reach: float = visual.call("stow_frame_reach", camera, VIEW)
	metrics["motion_lag_breach"] = lag_breach
	metrics["motion_lag_reach"] = lag_reach
	metrics["motion_lag_scale"] = visual.motion_lag_scale()
	_check(
		lag_breach <= 0.0,
		"at full walking lag the surplus is %.4f into the crosshair band — 余链永远不能出现在准星周围, and §5 makes the safe region bind on the LAG and not only on the pose" % lag_breach
	)
	_check(
		lag_reach < 1.0,
		"at full walking lag the surplus reaches NDC %.3f — the fan left the frame while the safe-band reading stayed silent" % lag_reach
	)
	# A LEGAL DEMAND MUST BE LET THROUGH UNTOUCHED, and this is the assertion that catches
	# the clamp lying rather than the clamp failing. The bisection started with its upper
	# bound at 1.0 and never evaluated it, so it returned 0.984375 for a demand that was
	# entirely legal — the whole motion got a permanent 1.6 % haircut and the scale read
	# "compressed" on every frame of an ordinary walk. `== 1.0` is therefore the claim:
	# a 3 cm trail is inside the budget and the clamp has no business touching it.
	_check(
		visual.motion_lag_scale() >= 0.9999,
		"a walking lag of %.4f m was compressed to %.4f of itself — the trail is inside the measured budget, so this is the clamp firing when it should not (or, as it was, a bisection that can never return its own upper bound)" % [walk_lag.length(), visual.motion_lag_scale()]
	)

	# Now stop dead and watch for the overshoot. The surplus should carry PAST the rest
	# pose once — along the travel direction, i.e. the SIGN flips — and then settle.
	var overshoot := 0.0
	var settled_at := -1
	for i in 90:
		await _still(1)
		var along := visual.motion_drag().dot(fwd)
		overshoot = maxf(overshoot, along)
		if settled_at < 0 and absf(along) < RESIDUAL_TOL and i > 5:
			settled_at = i
	metrics["motion_overshoot"] = overshoot
	metrics["motion_stop_settle_frames"] = settled_at
	_check(
		overshoot > OVERSHOOT_MIN,
		"stopping from a walk overshot by only %+.4f m — §3 asks the surplus to 继续前移几厘米 and settle, which is the one beat that makes this read as inertia rather than as a smoothing filter" % overshoot
	)
	_check(
		overshoot < OVERSHOOT_MAX,
		"stopping overshot by %+.4f m — the brief asks for a bounded give, 克制, not a whip" % overshoot
	)
	_check(
		settled_at >= 0,
		"the surplus had still not settled inside %.3f m after 1.5 s of standing still — §3 ends in settle, and a tail that never decays is a permanent offset" % RESIDUAL_TOL
	)

	# ---- §4 · A FAST TURN LEAVES 3–8°, AND PITCH GIVES LESS ---------------
	await _stand(OPEN_STAND, Vector3(0.0, 0.0, -1.0))
	await _tick(20)
	await _spin(TURN_RATE_DEG, 40)
	var yaw_lag: float = visual.motion_turn_lag()
	metrics["motion_turn_lag_deg"] = rad_to_deg(yaw_lag)
	metrics["motion_turn_limit_deg"] = rad_to_deg(visual.motion_turn_limit())
	_check(
		rad_to_deg(yaw_lag) > 2.0,
		"a %.0f deg/s turn left the fan only %.2f deg behind the hand — §4 asks for a visible 3–8 deg, and below that the fan is rotating rigidly with the camera" % [TURN_RATE_DEG, rad_to_deg(yaw_lag)]
	)
	_check(
		yaw_lag <= visual.motion_turn_limit() + 0.0001,
		"the turn lag reached %.2f deg against a %.2f deg cap — the cap exists so a fast flick cannot throw the fan off the hip" % [rad_to_deg(yaw_lag), rad_to_deg(visual.motion_turn_limit())]
	)

	await _stand(OPEN_STAND, Vector3(0.0, 0.0, -1.0))
	await _tick(20)
	# 24 FRAMES, NOT 40, AND THAT IS THE READING RATHER THAN A CONVENIENCE. `_nod` turns
	# the LookPivot, which SATURATES at ±1.2 rad — 150 deg/s reaches that at frame 28, so
	# the last twelve frames of a 40-frame nod rotate nothing at all and the lag has
	# already decayed by the time it is read: the first version reported 0.13 deg for a
	# term whose own share asks for 3.4, and the fault was the measurement, not the term.
	# §4's lag is a lag DURING a turn, so the reading is taken while the pivot is still
	# moving. 24 frames at 2.5 deg/frame is 60 deg, comfortably inside the throw.
	await _nod(NOD_RATE_DEG, 24)
	var pitch_lag: float = visual.motion_turn_lag()
	metrics["motion_pitch_lag_deg"] = rad_to_deg(pitch_lag)
	_check(
		pitch_lag < yaw_lag,
		"the same rate into PITCH lagged %.2f deg against %.2f deg for yaw — §4 says 镜头一抬整束链翻过去 is the failure, so pitch has to give less than yaw" % [rad_to_deg(pitch_lag), rad_to_deg(yaw_lag)]
	)
	# ...AND PITCH HAS TO GIVE WHAT THE SHARE SAYS, not merely something less than yaw.
	# `pitch < yaw` alone is satisfied by a pitch term that does nothing at all — and the
	# first version of this term did nothing much, because the angular velocity was a
	# LOCAL axis being dotted with the WORLD up and the camera's right. The expected value
	# is DERIVED from the visual's own two constants rather than typed: a spring tracking a
	# constant demand has no steady-state error, so a nod of `NOD_RATE_DEG` settles at
	# `rate x tau x share`. MEASURED 3.45 deg against a derived 3.37 (2 % off, which is the
	# frame quantisation), and the local-axis version of the same term MEASURED 5.33 deg —
	# 0.67 of yaw where the constant says 0.30, i.e. a knob reading more than double its
	# own value. That is the defect this line is here to keep out.
	var pitch_design := deg_to_rad(NOD_RATE_DEG) * visual.MOTION_TURN_TAU * visual.MOTION_TURN_PITCH_SHARE
	metrics["motion_pitch_design_deg"] = rad_to_deg(pitch_design)
	_check(
		absf(pitch_lag - pitch_design) <= pitch_design * 0.30,
		"a %.0f deg/s nod left the fan %.2f deg behind, against %.2f deg from the share the visual declares — §4 gives pitch LESS say than yaw (MOTION_TURN_PITCH_SHARE %.2f of %.3f s), so a term that reads more or less than that is not the term the constant describes" % [NOD_RATE_DEG, rad_to_deg(pitch_lag), rad_to_deg(pitch_design), visual.MOTION_TURN_PITCH_SHARE, visual.MOTION_TURN_TAU]
	)

	# ---- §9 · THE DODGE IS AN IMPULSE THAT SETTLES -----------------------
	await _stand(OPEN_STAND, Vector3(0.0, 0.0, -1.0))
	await _tick(20)
	var side := camera.global_transform.basis.x
	#
	# THE IMPULSE IS MEASURED IN TWO PARTS, and the split is the claim. §9 gives the whole
	# beat 150–300 ms and then adds 必须迅速 settle, which are two different requirements: the
	# KICK has to be big enough to be seen as 被留在左侧, and the RECOVERY after the input
	# stops has to be inside the window. One number cannot carry both, so the peak is taken
	# during the burst and the settle is timed from the frame the burst ends — exactly the
	# moment §9's 结束 refers to.
	var kick := 0.0
	for _i in 12:
		await _travel_frame(side, 11.0)
		kick = maxf(kick, visual.motion_drag().length())
	var frames_to_settle := 0
	var settle_ms := 9999.0
	for _i in 60:
		await _still(1)
		frames_to_settle += 1
		if visual.motion_drag().length() < RESIDUAL_TOL:
			settle_ms = float(frames_to_settle) * DT * 1000.0
			break
	metrics["motion_dodge_kick"] = kick
	metrics["motion_dodge_settle_ms"] = settle_ms
	_check(
		kick > 0.012,
		"a 12-frame dodge at 11 m/s kicked the surplus only %.4f m — §9 asks it to be 被留在左侧, visible as an impulse and not as a smooth follow" % kick
	)
	_check(
		settle_ms <= 300.0,
		"the surplus took %.0f ms to come back inside %.3f m after the dodge input stopped — §9 allows 150–300 ms for the whole beat and then requires 迅速 settle, because a surplus that keeps swinging is a tail and not a stow" % [settle_ms, RESIDUAL_TOL]
	)
	_check(
		settle_ms >= 60.0,
		"the dodge impulse was recovered in only %.0f ms — that is a snap back to the hip, not the 被惯性甩一下 §9 asks for; the kick has to be something the player can watch come back" % settle_ms
	)

	# ---- §6 · ONE ROOT, FOUR RESPONSE SPEEDS -----------------------------
	#
	# Taken at speed, because the per-layer trail is proportional to how loaded the major
	# motion is — at rest it is exactly zero, which is what keeps the frozen ring clearance
	# intact at rest.
	await _stand(OPEN_STAND, Vector3(0.0, 0.0, -1.0))
	await _tick(20)
	await _travel(fwd, SPRINT_SPEED, 60)
	var offsets: Array[float] = visual.motion_layer_offsets()
	metrics["motion_layer_offsets"] = offsets
	# NON-DECREASING, and the direction is the claim. `MOTION_LAYER_RESPONSE` gives layer 0
	# the FULL response (1.00) and the outermost 0.82, so the trail has to GROW outward —
	# the fan is pulled from the hand end and the free end is what gets left behind. The
	# first version of this line asserted the opposite direction and reddened a system that
	# was right, which is why the message names the order and not just the list.
	var ordered := offsets.size() >= 4
	for i in range(1, offsets.size()):
		if offsets[i] < offsets[i - 1] - 0.0005:
			ordered = false
	_check(
		ordered and offsets.size() >= 4,
		"the four layers trail by %s m — §6 asks for ONE shared root motion plus a small per-layer response difference (1.00 / 0.94 / 0.88 / 0.82), so the trail must GROW outward; a list that does not is four independent objects and therefore 四条蛇" % [offsets]
	)
	_check(
		offsets.size() >= 1 and offsets[0] < 0.0005,
		"the innermost layer trails %.4f m behind the root — its arc carries the lead-in, so a layer that moves independently of the root tears the rope off its own fist" % (offsets[0] if offsets.size() > 0 else -1.0)
	)
	_check(
		offsets.size() >= 4 and offsets[3] > offsets[0] + 0.001,
		"the outermost layer trails %s against the innermost %s — a difference that small is not a response difference at all" % [offsets[3] if offsets.size() >= 4 else "?", offsets[0] if offsets.size() > 0 else "?"]
	)

	# ---- §5 · THE CLAMP IS NOT DECORATION --------------------------------
	#
	# A DEMAND NO FRAME COULD HOLD, BUILT RATHER THAN WAITED FOR. The first version of this
	# block only recorded the live scale, and that reading is worthless in BOTH directions:
	# it is 1.0 whenever the demand happens to fit (so it says nothing), and the clamp's own
	# bisection used to return 0.984375 even for a perfectly legal demand (so it said the
	# wrong thing). Disabling the clamp entirely — `if true:` in place of the projection
	# test — left this suite GREEN, which is the definition of a decoration assertion.
	#
	# So the clamp is called the way it actually is: a pure function of (rest, offset,
	# basis). Three questions, and each one is a different failure.
	#
	# The oversize direction is the frame EDGE rather than the crosshair on purpose. A
	# lateral shunt a metre wide is nowhere near the ±0.38 NDC band, so only
	# `STOW_REACH_LIMIT` can reject it — which is what makes this the reading that can tell
	# the reach clause from the band clause. Without that separation, raising the reach
	# limit to 2.0 is invisible.
	# The oversize direction is derived from where the stow actually IS rather than typed,
	# and that is the whole of this reading. The first version pushed it sideways, which
	# moves the bundle TOWARD the screen centre: the demand then crossed the −0.38 band and
	# was compressed by the BAND clause, so the frame-edge clause could be deleted
	# (`STOW_REACH_LIMIT := 2.0`) or bypassed (`if true:` in the bisection) and the suite
	# stayed green. The band and the frame edge are opposite failures, so a shunt that only
	# ever tests one of them proves nothing about the other. OUT is away from the centre,
	# IN is toward it: out exercises the edge, in exercises the band.
	var rest_xf := visual.motion_rest()
	var rest_pts: PackedVector2Array = visual.call("_stow_ndc_for", rest_xf, camera, VIEW)
	var rest_centre := Vector2.ZERO
	for p in rest_pts:
		rest_centre += p
	rest_centre /= maxf(1.0, float(rest_pts.size()))
	var out_ndc := Vector2(
		signf(rest_centre.x) if absf(rest_centre.x) > 0.05 else 1.0,
		signf(rest_centre.y) if absf(rest_centre.y) > 0.05 else 1.0
	).normalized()
	var out_dir := (
		camera.global_transform.basis.x * out_ndc.x
		+ camera.global_transform.basis.y * out_ndc.y
	).normalized()
	var tiny_scale := float(visual.call("_lag_safe_scale", rest_xf, out_dir * 0.004, rest_xf.basis))
	var out_scale := float(visual.call("_lag_safe_scale", rest_xf, out_dir * 0.60, rest_xf.basis))
	var in_scale := float(visual.call("_lag_safe_scale", rest_xf, -out_dir * 0.60, rest_xf.basis))
	var out_xf := Transform3D(rest_xf.basis, rest_xf.origin + out_dir * 0.60 * out_scale)
	var in_xf := Transform3D(rest_xf.basis, rest_xf.origin - out_dir * 0.60 * in_scale)
	var out_reach := _ndc_extent(visual, out_xf, camera, VIEW)
	var in_extent := _ndc_extent(visual, in_xf, camera, VIEW)
	metrics["motion_clamp_tiny"] = tiny_scale
	metrics["motion_clamp_out"] = out_scale
	metrics["motion_clamp_in"] = in_scale
	metrics["motion_clamp_out_reach"] = out_reach
	metrics["motion_clamp_in_extent"] = in_extent
	metrics["motion_rest_centre"] = rest_centre
	_check(
		tiny_scale >= 0.9999,
		"a 4 mm shunt — a demand ten times smaller than the walking trail — was compressed to %.4f, so the clamp is not measuring the safe zone, it is measuring itself (the bisection's upper bound was never evaluated, so the answer could not be 1.0)" % tiny_scale
	)
	_check(
		out_scale < 0.9999,
		"a 0.60 m shunt AWAY from the centre of the frame was accepted whole (scale %.4f) — that demand leaves the picture, so a clamp that does not compress it is not running at all" % out_scale
	)
	_check(
		out_reach < 1.0,
		"after compression the outward shunt still reaches NDC %.3f — the clamp returned a scale that leaves the fan off the edge of the frame, which is the one thing §5's second reading exists to prevent" % out_reach
	)
	# THE BAND CLAUSE, AND THE COMPARISON IS THE OPPOSITE WAY ROUND FROM THE EDGE CLAUSE.
	# `stow_breach` is `half − max(|x|, |y|)`, so a LARGE distance from the middle is the
	# safe answer and a SMALL one is the failure: the fan may not come within 0.38 of the
	# centre. The first version of this line asserted `in_extent < SAFE_HALF` — i.e. that
	# the compressed transform HAD breached — and failed a clamp that was working
	# perfectly. Both readings being a `max(|x|, |y|)` does not make them the same reading.
	_check(
		in_scale < 0.9999 and in_extent >= visual.SAFE_HALF,
		"a 0.60 m shunt INTO the centre compressed to %.4f but left a seam %.3f from the middle, inside the %.2f band the surplus may never enter — 余链永远不能出现在准星周围" % [in_scale, in_extent, visual.SAFE_HALF]
	)
	_check(
		visual.call("_stow_ndc_legal", out_xf, camera, VIEW),
		"the transform the clamp actually returned is not legal by the clamp's own test — a scale that compresses the demand but still breaks the rule is a number that passed and a picture that did not"
	)
	metrics["motion_clamp_scale_min"] = visual.motion_lag_scale()

	# ---- §10/§11 · THE RELEASE IS A LADDER, NOT A CUT --------------------
	#
	# THE LADDER'S OWN STATE IS WHAT IS MEASURED, and that choice is the reading. The first
	# version sampled `drawn_bundle()` and reported the counts `[4, 2, 1, ...]` — a release
	# that appeared to skip 3 entirely — and the cause was not the ladder: `drawn_bundle()`
	# is `coils_for(payout) − release_step`, and `coils_for()` is ALREADY walking down as
	# the head reaches out. Two systems moving the same number, so a laddered release and a
	# payout-only drop are indistinguishable in it. §11's assertion above catches that
	# conflation from the payout side; this one asks §10's actual question — did each arc
	# leave as a STATE, or did two of them go at once?
	await _stand(OPEN_STAND, Vector3(0.0, 0.0, -1.0))
	chain.reset()
	await _tick(20)
	var steps := visual.release_steps()
	var rungs: Array[int] = []
	var held: Array[int] = []
	chain.request(&"light")
	var guard := 0
	while guard < 480:
		guard += 1
		await _tick(1)
		var rung: int = visual.release_step()
		if rungs.is_empty() or rungs[rungs.size() - 1] != rung:
			rungs.append(rung)
			held.append(0)
		held[held.size() - 1] += 1
		if guard > 40 and chain.state == ChainDirector.State.HELD and rung == 0:
			break
	metrics["motion_release_rungs"] = rungs
	# How long each INTERMEDIATE rung was held. The terminal rungs are excluded on purpose:
	# the 0 before the release starts and the 0 the loop breaks on are both one frame by
	# construction and say nothing about the dwell.
	var rung_holds: Array[int] = []
	for i in rungs.size():
		if rungs[i] >= 1:
			rung_holds.append(held[i])
	var min_hold := 999
	for h in rung_holds:
		min_hold = mini(min_hold, h)
	metrics["motion_release_min_hold"] = min_hold
	metrics["motion_release_rung_holds"] = rung_holds

	# Every rung the ladder has must appear IN ORDER on the way down — 1, then 2 — so a
	# single jump past a rung cannot pass however many steps it eventually reaches.
	#
	# AND THE COUNT IS NAMED, NOT TAKEN FROM THE LADDER. `climbed >= steps` looks like the
	# same claim and is not: `steps` IS `BUNDLE_SHED_STEPS`, so setting that constant to 1 —
	# a single arc released, i.e. §10's 4 → 3 → 2 collapsing back into 4 → 3 — satisfies it
	# by construction. The mutation sweep found that; the number below is §10's own.
	var climbed := 0
	for r in rungs:
		if r == climbed + 1:
			climbed += 1
	metrics["motion_release_climbed"] = climbed
	_check(
		climbed >= 2 and steps >= 2,
		"the release walked the rungs %s in order, reaching %d of the %d the ladder has — §10 names 4 → 3 and 3 → 2 as TWO separate, visible states (慢一点、看得见), so one rung means an arc left the fist without ever being a state, and the player sees a cut rather than 长链从身边被抽出去"
			% [rungs, climbed, steps]
	)
	_check(
		rungs.size() > 0 and rungs[rungs.size() - 1] == 0,
		"the release ladder finished at rung %d instead of 0 — §11 requires the surplus to be RE-ORGANISED after the technique, not left short, or the weapon loses rope with every attack"
			% (rungs[rungs.size() - 1] if rungs.size() > 0 else -1)
	)
	_check(
		min_hold >= 3,
		"an intermediate rung of the release lasted only %d frame(s) — the dwell is the entire point of `BUNDLE_SHED_STEPS`; below about three frames at 60fps the release is a smear with extra arithmetic, which is the reading it was introduced to replace"
			% min_hold
	)
	# ...and the pack came back FULL. The counts are read from the drawn bundle here
	# because "the weapon still has all its rope" is a claim about the drawing.
	await _tick(90)
	var recovered := visual.drawn_bundle()
	metrics["motion_repacked"] = recovered
	_check(
		recovered >= visual.coils(),
		"the pack came back to only %d of the rope's own %d layers — §11 requires the surplus to be re-organised rather than left short"
			% [recovered, visual.coils()]
	)


## How far the FARTHEST drawn seam of a CANDIDATE transform sits from the middle of the
## frame, in NDC. The clamp's own two readings are both `max(|x|, |y|)` over this set, so
## a test that wants to ask "did the scale it returned actually keep the rule" has to run
## the same projection on the transform it returned rather than on the one in the scene.
func _ndc_extent(vis: ChainVisual, xf: Transform3D, cam: Camera3D, frame: Vector2) -> float:
	var worst := 0.0
	var pts: PackedVector2Array = vis.call("_stow_ndc_for", xf, cam, frame)
	for p in pts:
		worst = maxf(worst, maxf(absf(p.x), absf(p.y)))
	return worst


## ONE frame of travel, for readings that have to be taken DURING a burst rather than
## after it. `_travel` runs its whole distance before returning, which is fine for a steady
## state and useless for an impulse — the peak is over before the first reading.
func _travel_frame(dir: Vector3, speed: float) -> void:
	_pin = false
	await physics_frame
	player.global_position += dir.normalized() * speed * DT
	player.global_position.y = _pin_at.y
	player.velocity = Vector3.ZERO
	chain.step(DT)


## Walk the player for real. `_stand` PINS the body on purpose so every other group reads
## from a still rig — and a pinned body has zero velocity, so §MOTION cannot be measured
## through it at all. This frees the ground plane while holding the stand height: the body
## is not allowed to fall, because a drop is vertical motion and the trail is computed from
## the hand's velocity, so an unheld body would put a player's own gravity into every
## reading of a walk.
func _travel(dir: Vector3, speed: float, frames: int) -> void:
	_pin = false
	var step := dir.normalized() * speed * DT
	for _i in frames:
		await physics_frame
		player.global_position += step
		player.global_position.y = _pin_at.y
		player.velocity = Vector3.ZERO
		chain.step(DT)


## Yaw the body, which is what a look does to the whole rig — the same axis `_turn()`
## drives in the renderer, so the two cannot disagree about which rotation is 转身.
func _spin(rate_deg: float, frames: int) -> void:
	_pin = false
	var step := deg_to_rad(rate_deg) * DT
	for _i in frames:
		await physics_frame
		player.rotation.y += step
		chain.step(DT)


## Pitch the look pivot — the rig's own pitch node, so the reading is about the camera
## going up rather than about the body leaning.
func _nod(rate_deg: float, frames: int) -> void:
	_pin = false
	var pivot := player.get_node_or_null("CameraRig/LookPivot") as Node3D
	var step := deg_to_rad(rate_deg) * DT
	for _i in frames:
		await physics_frame
		if pivot != null:
			pivot.rotation.x = clampf(pivot.rotation.x + step, -1.2, 1.2)
		chain.step(DT)


## Frames with no input at all. Not `_wait`, which also holds the body on its pin: after a
## dodge the whole point is that the body was NOT pinned.
func _still(frames: int) -> void:
	for _i in frames:
		await physics_frame
		chain.step(DT)


const OPEN_STAND := Vector3(0.0, 1.0, -22.0)
const WALL_STAND := Vector3(0.0, 1.0, ChainLab.WALL_Z + 0.35 + WALL_GAP)


func _park_everything() -> void:
	var all: Array[Node3D] = [world.get_node("TechnicalDummy")]
	for t in lab.targets:
		all.append(t)
	for target in all:
		if not is_instance_valid(target):
			continue
		target.set_process(false)
		target.global_position = PARK
	for crate in lab.crates:
		if not is_instance_valid(crate):
			continue
		crate.freeze = true
		crate.linear_velocity = Vector3.ZERO
		crate.global_position = PARK + Vector3(0.0, 0.5, 2.0)
	chain.reset()


func _stand(position: Vector3, direction: Vector3) -> void:
	player.global_position = position
	player.velocity = Vector3.ZERO
	player.set("external_velocity", Vector3.ZERO)
	player.look_at_from_position(position, position + direction, Vector3.UP)
	_pin = true
	_pin_at = position
	await _wait(14)


# The player is part of the instrument: a CharacterBody3D left where `_stand` put it
# falls until it finds the deck, and that fall is added to every reading taken from
# the head. Same discipline as `chain_physicality`, one pin instead of a stance.
func _hold_ground() -> void:
	if _pin:
		player.global_position = _pin_at
		player.velocity = Vector3.ZERO
		player.set("external_velocity", Vector3.ZERO)


func _tick(frames: int) -> void:
	for _i in frames:
		await physics_frame
		_hold_ground()
		chain.step(DT)


func _wait(frames: int) -> void:
	for _i in frames:
		await physics_frame
		_hold_ground()


func _report() -> void:
	print("")
	print("缚星链 · CHAIN V4 — A1 VERTICAL SLICE")
	print("  §0   rig: idle %s → cut %s → after %s"
		% [metrics.get("rig_idle", "?"), metrics.get("rig_swing", "?"), metrics.get("rig_after", "?")])
	print("  §11  fistful: rest %d of %d turns → lowest %d (rope's own count there: %d) during a %d-frame throw → back to %d"
		% [
			int(metrics.get("bundle_held", 0)), int(metrics.get("bundle_held_loops", 0)),
			int(metrics.get("bundle_low", 0)), int(metrics.get("bundle_low_loops", 0)),
			int(metrics.get("bundle_swing_frames", 0)),
			int(metrics.get("bundle_recovered", 0)),
		])
	print("  §12  head lag: worst %.2fm at frame %d of %d · last frame %.2fm"
		% [
			metrics.get("lag_worst", 0.0), int(metrics.get("lag_worst_frame", 0)),
			int(metrics.get("lag_frames", 0)), metrics.get("lag_last", 0.0),
		])
	print("  §9   preload: peak %.2f at frame %d · still %.2f during the strike"
		% [
			metrics.get("preload_peak", 0.0), int(metrics.get("preload_peak_frame", 0)),
			metrics.get("preload_during_strike", 0.0),
		])
	print("  §STOW stow: %d links · %d/%d layers · breach %.4f · reach %.3f · margin %+.4f · ring layering %+.4f · link(flat) %+.4f · link(skip1) %+.4f · bend %.3f vs %.3f · band ±0.38 NDC at 1280×720"
		% [
			int(metrics.get("stow_links", 0)), int(metrics.get("stow_shown", 0)),
			int(metrics.get("stow_layers", 0)), metrics.get("stow_breach", 0.0),
			metrics.get("stow_reach", 0.0), metrics.get("stow_margin", 0.0),
			metrics.get("stow_layered", 0.0),
			metrics.get("stow_link_flat", 0.0), metrics.get("stow_link_skip1", 0.0),
			metrics.get("stow_fan", 0.0), metrics.get("stow_bend", 0.0),
		])
	print("  §JOINT hilt: rope %+.4f m · eye ring %+.4f m · ring-vs-rope %.1f deg  (want > 0, > 0, < 20)"
		% [
			metrics.get("joint_hilt", 0.0), metrics.get("joint_eye", 0.0),
			metrics.get("joint_thread", 0.0),
		])
	print("  §MOTION idle %.4f m (peak over 1.5 s) · walk lag %.4f m (%+.4f along travel at %.2f m/s) · overshoot %+.4f m"
		% [
			metrics.get("motion_idle_peak", 0.0), metrics.get("motion_walk_lag", 0.0),
			metrics.get("motion_walk_signed", 0.0), metrics.get("motion_walk_speed", 0.0),
			metrics.get("motion_overshoot", 0.0),
		])
	print("  §MOTION turn %.2f deg (cap %.2f) · pitch %.2f deg · dodge kick %.4f m settling in %.0f ms"
		% [
			metrics.get("motion_turn_lag_deg", 0.0), metrics.get("motion_turn_limit_deg", 0.0),
			metrics.get("motion_pitch_lag_deg", 0.0), metrics.get("motion_dodge_kick", 0.0),
			metrics.get("motion_dodge_settle_ms", 0.0),
		])
	print("  §MOTION clamp: walk kept %.4f · 4 mm kept %.4f · stow centre NDC %s" % [
			metrics.get("motion_lag_scale", 1.0), metrics.get("motion_clamp_tiny", 1.0),
			metrics.get("motion_rest_centre", Vector2.ZERO),
		])
	print("  §MOTION clamp: 0.60 m OUT → %.4f (reach %.3f) · 0.60 m IN → %.4f (extent %.3f, band %.2f)"
		% [
			metrics.get("motion_clamp_out", 1.0), metrics.get("motion_clamp_out_reach", 0.0),
			metrics.get("motion_clamp_in", 1.0), metrics.get("motion_clamp_in_extent", 0.0),
			visual.SAFE_HALF,
		])
	print("  §MOTION clamp: live breach %.4f · live reach %.3f at full lag"
		% [
			metrics.get("motion_lag_breach", 0.0), metrics.get("motion_lag_reach", 0.0),
		])
	print("  §MOTION release ladder rungs %s (each held %s frames, climbed %d) · layer offsets %s"
		% [
			metrics.get("motion_release_rungs", []),
			metrics.get("motion_release_rung_holds", []),
			metrics.get("motion_release_climbed", 0),
			metrics.get("motion_layer_offsets", []),
		])
	print("  §18  wall bite: anchored after %d frames at z=%.2f · drift %.4fm over 40 · bite %.2f · load %.2f · blade·normal %.2f"
		% [
			int(metrics.get("anchor_frames_to_bite", 0)), metrics.get("anchor_z", 0.0),
			metrics.get("anchor_drift", 0.0), metrics.get("bite_phase", 0.0),
			metrics.get("chain_load", 0.0), metrics.get("blade_into_wall", 0.0),
		])
	print("  §12  loaded: walk trail %.4f m → %.4f m with the chain out · idle drift while out %.5f m"
		% [
			metrics.get("contact_trail_walking", 0.0),
			metrics.get("contact_trail_loaded", 0.0),
			metrics.get("contact_idle_loaded", 0.0),
		])
	print("  §13  beat: CONTACT→BITE %.0f ms (authored %.0f ms, frames %s) · drawn rope %.2f at contact → %.2f after the bite"
		% [
			metrics.get("contact_bite_ms", -1.0), moveset.wall_bite_time * 1000.0,
			metrics.get("contact_frames", {}),
			metrics.get("contact_load_at_contact", -1.0),
			metrics.get("contact_load_after_bite", 0.0),
		])
	print("  §14  hand: resist %.4f m (%.4f along the rope) · camera knock %.4f · trauma %.3f"
		% [
			metrics.get("handle_resist_m", 0.0), metrics.get("handle_resist_align", 0.0),
			metrics.get("wall_knock", -1.0), metrics.get("wall_trauma", -1.0),
		])
	print("  §16  switch: away (stow %d) → back: %s · A%d · arcs %d · rig %s · load %.2f"
		% [
			metrics.get("switch_stowed_away", -1), String(ChainDirector.State.keys()[chain.state]),
			metrics.get("switch_index", -1) + 1, metrics.get("switch_arcs", -1),
			metrics.get("switch_rig", "?"), metrics.get("switch_load", -1.0),
		])
	print("")


func _check(condition: bool, reason: String) -> void:
	if not condition:
		failures.append(reason)


func _fail(reason: String) -> void:
	failures.append(reason)


func _finish() -> void:
	if failures.is_empty():
		print("PASS: the chain is drawn three ways — it hangs as a held weapon, swings with a head that arrives late, and bites a wall without moving")
		quit(0)
		return
	for reason in failures:
		print("  - " + reason)
	print("FAIL: %d problem(s)" % failures.size())
	quit(1)
