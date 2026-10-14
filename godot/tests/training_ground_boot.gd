extends SceneTree
# TRAINING GROUND — the playtest gate's room.
#
# THE QUESTION THIS FILE ANSWERS. §17 and §18 put the user in a visible window and ask
# them to play; everything about that plan fails silently if the room does not actually
# come up with a target in it. A range whose dummies failed to instantiate looks exactly
# like a range whose dummies are there and simply were not hit, and the person holding
# the mouse is the last one who should be diagnosing that.
#
# WHY THE DISTANCES ARE CHECKED AS DISTANCES. §10 asks for 3 / 6 / 9 m, and the whole
# point of the number is that a 10 m weapon can be told apart from a 4 m one. A dummy
# that ends up 1.5 m from the stand because a court pad moved would make the entire
# session's conclusion - "the chain feels long/short" - measure nothing.
#
# AND WHY THE SWITCH IS RE-CHECKED HERE. The sword-rig rule used to live in
# CombatSandbox, which means it was true in the arena and false in this room: the player
# would have carried a drawn katana into a chain playtest. It is a property of the
# Player now, and a property of the Player is worth asserting in a SECOND scene -
# otherwise the test proves the arena, not the rule.

const DT := 1.0 / 60.0
const PLAYTEST := preload("res://scripts/training/playtest_range.gd")
const POST := preload("res://scripts/training/iaido_post.gd")
const TRAINING := preload("res://scripts/training/training_ground.gd")
const SWORD_RIG := "CameraRig/LookPivot/MotionPivot/ShakePivot/WeaponRoot/TempSwordVisual"

var world: Node3D
var player: CharacterBody3D
var chain: ChainDirector
var weapon: WeaponSlot
var manager: Node
var range_node: Node3D
var failures: Array[String] = []
## Set by `_on_post_reformed`, read by the recovery check. A member rather than a lambda
## local because a GDScript lambda captures BY VALUE, so a delegate that tried to write a
## local would report success no matter what it saw — the failure mode this exists to
## catch, reproduced in the harness meant to catch it.
var _debris_at_reform := false
var _post: Node3D = null


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene: PackedScene = load("res://scenes/training/TrainingGround.tscn")
	if scene == null:
		_fail("TrainingGround.tscn will not load, so there is nothing to play (§19)")
		_finish()
		return
	world = scene.instantiate()
	root.add_child(world)
	await _wait(12)

	player = world.get_node_or_null("Player") as CharacterBody3D
	if player == null:
		_fail("the Training Ground has no Player, so there is nothing to play (§11)")
		_finish()
		return
	chain = player.get_node("ChainDirector")
	weapon = player.get_node("WeaponSlot")
	manager = player.get_node_or_null("WeaponManager")
	range_node = world.find_child("PlaytestRange", true, false) as Node3D

	_check_the_room_is_playable()
	await _check_the_switch_works_here()
	_check_the_bay_contains_the_rig()
	_check_the_zones_do_not_overlap()
	_check_the_gallery_is_a_gallery()
	_check_the_duel_ring_can_be_walked_onto()
	_check_the_terrain_has_walkable_levels()
	_check_the_long_range_is_empty()
	_check_the_range_has_three_ranges()
	await _check_the_targets_survive_a_session()
	await _check_the_drill_dummy_cannot_be_killed()
	await _check_the_iaido_post_can_be_cut()
	await _check_reset_puts_the_room_back()

	_finish()


func _check_the_room_is_playable() -> void:
	_check(
		player.get_node_or_null("CameraRig/LookPivot/MotionPivot/ShakePivot/Camera3D") != null,
		"the Training Ground has no first-person camera (§11: first person is the truth)"
	)
	_check(manager != null, "the Player in this scene has no WeaponManager (§1)")
	# §14: unlimited mana and stamina is the rule of this room, not a toggle.
	_check(
		bool(player.get("unlimited_resources")),
		"mana/stamina are not unlimited in the Training Ground (§14)"
	)


func _check_the_switch_works_here() -> void:
	# Not the switch's own logic (that is weapon_switch_integration's job) - the RULE
	# being a property of the Player rather than of one stage.
	if manager == null or range_node == null:
		return
	var rig := player.get_node_or_null(SWORD_RIG) as Node3D
	if rig == null:
		_fail("the sword rig is not where the visibility rule looks for it")
		return
	manager.call("equip_weapon", WeaponSlot.CHAIN)
	await _settle()
	_check(weapon.is_chain(), "the chain could not be equipped in the Training Ground")
	_check(not rig.visible, "a drawn katana is still in hand while the chain is out (§3/§5)")
	_check(chain.chain_visual.is_drawn(), "the chain is equipped but not drawn (§11)")
	# §20: Chain A1 must work in this room, since A1-A3 are the only three beats that
	# exist and the user is about to judge two of them from the idle bundle.
	_check(chain.request(&"light"), "the chain refused its first cut in the Training Ground")
	manager.call("equip_weapon", WeaponSlot.SWORD)
	await _settle()
	_check(weapon.is_sword(), "the sword could not be equipped again")
	_check(rig.visible, "the sword rig did not come back when the sword did")


## THE BAY MUST CONTAIN THE RIG, and the check is a sweep of the rig's own children
## rather than a comparison of two rectangles. A bay that is 4 m too small still
## contains the lab's CENTRE, and the failure it produces is a kerb inside the parapet —
## visible only at a distance, in one shot, on one side. So every object the rig built
## is asked where it is, and the answer is a number.
func _check_the_bay_contains_the_rig() -> void:
	var rig := world.find_child("ChainRig", true, false) as Node3D
	if rig == null:
		_fail("zone D has no ChainRig, so the compound's chain lab is not the game's chain lab")
		return
	var rect: Vector4 = TRAINING.ZONE_CHAIN
	var worst := 0.0
	var worst_name := "nothing"
	var far_z := 1.0e9
	var probes := 0
	for child in rig.get_children():
		if not (child is Node3D):
			continue
		var p := (child as Node3D).global_position
		probes += 1
		far_z = minf(far_z, p.z)
		# Flat: the rig is allowed to be tall, and a bay is a footprint.
		var out := maxf(maxf(rect.x - p.x, p.x - rect.z), maxf(rect.y - p.z, p.z - rect.w))
		if out > worst:
			worst = out
			worst_name = String(child.name)
	_check(
		probes >= 8,
		"the chain rig built only %d object(s), so this is not the lab" % probes
	)
	_check(
		worst < 2.0,
		"%s stands %.2f m outside zone D, so the bay is too small for the rig"
			% [worst_name, worst]
	)
	# The rig's long axis has to point down the bay, i.e. the wall a throw ends on has
	# to be at the far end. A rig placed rotated would pass the containment check and
	# fail this one, which is why it is a second assertion and not part of the first.
	_check(
		far_z < rect.y + 6.0,
		"the rig's far end is at z = %.1f; the bay's north end is z = %.1f" % [far_z, rect.y]
	)


## NO TWO ZONES SHARE THE SAME GROUND.
##
## The compound's whole organisation is "one zone, one rectangle, one reason". Two
## rectangles overlapping does not raise an error anywhere — it produces a review card
## that sends the reviewer to a place where two rooms are the same room, which is a bug
## that only ever shows up as a confusing photograph.
func _check_the_zones_do_not_overlap() -> void:
	var list: Array = TRAINING.zones()
	var bad := ""
	for i in range(list.size()):
		for j in range(i + 1, list.size()):
			var a: Vector4 = list[i]["rect"]
			var b: Vector4 = list[j]["rect"]
			var ox: float = minf(a.z, b.z) - maxf(a.x, b.x)
			var oz: float = minf(a.w, b.w) - maxf(a.y, b.y)
			if ox > 0.01 and oz > 0.01 and bad == "":
				bad = "%s and %s share %.1f x %.1f m" % [list[i]["id"], list[j]["id"], ox, oz]
	_check(bad == "", "two zones are the same ground: %s" % bad)


## THE GALLERY IS A GALLERY: every exhibit on its own base, and no two bases share a
## square metre.
##
## "It looks tidy" is not a property and cannot be asserted. Disjoint footprints can be,
## and this is the check that the layout which shipped before this one would have failed:
## an 8 m `ENV01_Terrace_8x8` on a 6.0 m column pitch overlaps its neighbour by 2 m, and
## at the scale a thumbnail is viewed at that is invisible. Asking the boxes is not.
func _check_the_gallery_is_a_gallery() -> void:
	var gallery := world.find_child("Gallery", true, false) as Node3D
	if gallery == null:
		_fail("zone F has no Gallery, so the ENV-01 kit is still lying about on a floor")
		return
	var plinths: Array = []
	for child in gallery.get_children():
		if child is StaticBody3D and String(child.name).begins_with("Plinth_"):
			plinths.append(child)
	_check(
		plinths.size() == TRAINING.GALLERY_SLOTS.size(),
		"the hall built %d plinths for %d exhibits"
			% [plinths.size(), TRAINING.GALLERY_SLOTS.size()]
	)
	var overlaps := 0
	var first := ""
	for i in range(plinths.size()):
		_check(
			absf(_box_top(plinths[i]) - TRAINING.PLINTH_H) < 0.01,
			"plinth %s tops out at %.2f m" % [plinths[i].name, _box_top(plinths[i])]
		)
		for j in range(i + 1, plinths.size()):
			if _box_footprint(plinths[i]).intersects(_box_footprint(plinths[j])):
				overlaps += 1
				if first == "":
					first = "%s / %s" % [plinths[i].name, plinths[j].name]
	_check(
		overlaps == 0,
		"%d exhibit plinth pair(s) overlap (first: %s)" % [overlaps, first]
	)

	# AND THE PIECES ON THEM, WHICH IS THE HALF THAT WAS MISSING.
	#
	# "One exhibit per pedestal" is not a claim about the pedestals, and the version of
	# this check that stopped at the two loops above is what let a staircase hang 2 m out
	# over the aisle: the plinths were all disjoint and all exactly 0.30 m high while the
	# thing standing on one of them was not on it at all. The kit's two climbing pieces
	# origin at the FOOT of the run rather than at the centre of their footprint, so
	# "place it at the plinth's centre" puts half of it somewhere else — a fact every
	# plinth measurement is blind to by construction. So the pieces are measured directly:
	# each one has to sit inside its own plinth's footprint.
	var exhibits := gallery.get_node_or_null("Exhibits") as Node3D
	if exhibits == null:
		_fail("the hall has no Exhibits node, so what is standing on a plinth cannot be named")
		return
	var occupied := 0
	for slot in TRAINING.GALLERY_SLOTS:
		if String(slot) != "":
			occupied += 1
	var standing := 0
	for child in exhibits.get_children():
		if child is StaticBody3D:
			standing += 1
	_check(
		standing == occupied,
		"the hall stands %d piece(s) on plinths built for %d" % [standing, occupied]
	)
	var strays := 0
	var stray_note := ""
	for i in range(TRAINING.GALLERY_SLOTS.size()):
		var asset: String = TRAINING.GALLERY_SLOTS[i]
		if asset == "":
			continue
		var plinth := gallery.get_node_or_null("Plinth_%d" % i) as Node3D
		var piece := exhibits.get_node_or_null(asset.get_basename() + "_Col") as Node3D
		if plinth == null or piece == null:
			_fail("Plinth_%d is labelled %s but %s is not standing on it"
				% [i, asset, asset.get_basename() + "_Col"])
			continue
		if not _inside(_box_footprint(plinth), _box_footprint(piece)):
			strays += 1
			if stray_note == "":
				stray_note = "%s overhangs Plinth_%d by %.2f m" % [
					asset, i, _overhang(_box_footprint(plinth), _box_footprint(piece))]
	_check(
		strays == 0,
		"%d piece(s) are not standing on their own plinth (first: %s)" % [strays, stray_note]
	)


## THE RING IS A PLACE YOU CAN STAND ON, AND GET ONTO.
##
## Both halves are rays rather than comparisons of constants. The deck height could be
## read from `RING_DECK_H` all day and still be wrong in the room; the only question
## that matters is what a player's feet would find, and the physics server answers it.
func _check_the_duel_ring_can_be_walked_onto() -> void:
	var ring := world.find_child("DuelRing", true, false) as Node3D
	if ring == null:
		_fail("the compound has no 擂台, so zone H is a rectangle with nothing in it")
		return
	var c: Vector3 = TRAINING.RING_CENTRE
	var half: float = TRAINING.RING_SIZE * 0.5
	var deck := _surface_y(c.x, c.z)
	_check(
		absf(deck - TRAINING.RING_DECK_H) < 0.03,
		"the ring deck reads %.2f m, not the %.2f m the kit's own ramp can serve"
			% [deck, TRAINING.RING_DECK_H]
	)
	var top_y := _surface_y(c.x - half - 0.5, c.z)
	var bottom_y := _surface_y(c.x - half - 3.5, c.z)
	_check(
		absf(top_y - deck) < 0.12,
		"the ramp's top reads %.2f m against a deck at %.2f m, so there is a lip"
			% [top_y, deck]
	)
	_check(
		bottom_y < 0.35,
		"the ramp starts %.2f m above the floor, so it is not a way up" % bottom_y
	)
	# THE KERB IS CUT, AND THE CUT IS EXACTLY THE RAMP'S OWN WIDTH.
	#
	# This is asked of the MESH and not of a ray, and that is deliberate. A 0.28 m lip
	# is built without collision — a kerb you cannot walk over is a wall, and a ring you
	# can only enter through one door is a ring with a queue — so a ray crosses it
	# everywhere and would answer a question nobody asked. What has to be true is that
	# the gap in the kerb is the same size as, and in the same place as, the ramp; that
	# is three boxes and a subtraction, and it catches the version of this that ships:
	# a kerb laid as one piece, with the ramp running into the side of it.
	var north := ring.get_node_or_null("RingKerb_W_North") as Node3D
	var south := ring.get_node_or_null("RingKerb_W_South") as Node3D
	var ramp := ring.get_node_or_null("ENV01_Ramp_4x2_Col") as Node3D
	if north == null or south == null or ramp == null:
		_fail("the ring has no west gate: kerb or ramp is missing")
		return
	var gate_half := _box_size(ramp).z * 0.5
	var gap_n := north.global_position.z + _mesh_extent(north).z * 0.5
	var gap_s := south.global_position.z - _mesh_extent(south).z * 0.5
	_check(
		absf(gap_n - (c.z - gate_half)) < 0.02 and absf(gap_s - (c.z + gate_half)) < 0.02,
		"the kerb gap runs z %.2f..%.2f while the ramp is z %.2f..%.2f"
			% [gap_n, gap_s, c.z - gate_half, c.z + gate_half]
	)
	_check(
		gap_s - gap_n > 1.5,
		"the kerb gap is only %.2f m wide, which is narrower than the ramp" % (gap_s - gap_n)
	)


## THE HILL HAS FOUR WALKABLE FLOORS, AND EACH RISE IS A KIT RISE.
##
## A grid of rays over the whole zone, counted per surface height: a "floor" that only
## exists in one sample is an edge, and an edge is not a place to stand. The counts are
## what separate the two, and the levels themselves are `TERRAIN_LEVELS`, which is
## derived from the kit's two lifts rather than typed.
func _check_the_terrain_has_walkable_levels() -> void:
	var rect: Vector4 = TRAINING.ZONE_TERRAIN
	var counts := {}
	var x := rect.x + 1.0
	while x < rect.z:
		var z := rect.y + 1.0
		while z < rect.w:
			var y := _surface_y(x, z)
			if y > -100.0:
				var key := snappedf(y, 0.05)
				counts[key] = int(counts.get(key, 0)) + 1
			z += 1.0
		x += 1.0
	for level_v in TRAINING.TERRAIN_LEVELS:
		var level := float(level_v)
		var best := 0
		for k in counts.keys():
			if absf(float(k) - level) < 0.06:
				best = maxi(best, int(counts[k]))
		_check(
			best >= 6,
			"the terrain has no floor at %.2f m (best match covered %d m2)" % [level, best]
		)
	# AND THE KIT'S STAIR ARRIVES ON THE TERRACE IT IS MEANT TO SERVE. Two rays a metre
	# apart up the stair's run: one at its top, one on the terrace beyond it. A stair
	# whose collider was never built reads the ground at both — which is what the
	# movement lane's own flight does today, because the export carries no collision.
	var mid := float(TRAINING.TERRAIN_LEVELS[1])
	var stair_top := _surface_y(33.8, 5.0)
	var terrace := _surface_y(34.5, 5.0)
	_check(
		absf(stair_top - mid) < 0.15,
		"the kit stair's top reads %.2f m, not the %.2f m terrace it serves" % [stair_top, mid]
	)
	_check(
		absf(terrace - mid) < 0.03,
		"the terrace beyond the stair reads %.2f m, not %.2f m" % [terrace, mid]
	)
	var midpoint := _surface_y(31.0, 5.0)
	_check(
		midpoint > 0.15 and midpoint < mid,
		"the kit stair's midpoint reads %.2f m, so it is a step and not a flight" % midpoint
	)


## 大平地 IS A CLAIM ABOUT WHAT IS NOT THERE, and only a ray can be asked about nothing.
##
## Two questions, both of them about absence: is the floor flat for 50 m, and does a line
## drawn 1 m above it reach the far end. The second one is the real one — a range with a
## crate in it still passes the first.
func _check_the_long_range_is_empty() -> void:
	var x := TRAINING.RANGE_LINE_X - 1.0
	var samples := 0
	var bumpy := ""
	while x > TRAINING.RANGE_LINE_X - 51.0:
		samples += 1
		var y := _surface_y(x, TRAINING.RANGE_Z)
		if absf(y) > 0.05 and bumpy == "":
			bumpy = "a surface %.2f m high at x = %.0f" % [y, x]
		x -= 2.0
	_check(
		samples >= 25,
		"the long range was sampled only %d times, so 50 m is not what was measured" % samples
	)
	_check(bumpy == "", "the long range is not flat: %s" % bumpy)
	var blocked := _blocked(
		Vector3(TRAINING.RANGE_LINE_X - 0.5, 0.9, TRAINING.RANGE_Z),
		Vector3(TRAINING.RANGE_LINE_X - 50.5, 0.9, TRAINING.RANGE_Z)
	)
	_check(blocked == false, "the long range has something standing in it")


## World height of the first solid surface under (x, z). A ray, not arithmetic over
## collision shapes: the question is what a player's feet find, and the physics server
## is the only thing that already knows.
func _surface_y(x: float, z: float, from_y: float = 60.0) -> float:
	var space := world.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, from_y, z), Vector3(x, -10.0, z))
	q.collide_with_areas = false
	if player != null and is_instance_valid(player):
		q.exclude = [player.get_rid()]
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return -999.0
	return (hit["position"] as Vector3).y


func _blocked(from: Vector3, to: Vector3) -> bool:
	var space := world.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collide_with_areas = false
	if player != null and is_instance_valid(player):
		q.exclude = [player.get_rid()]
	return not space.intersect_ray(q).is_empty()


## The collider itself: the measurement below is only as honest as this lookup, so it
## finds the CollisionShape3D rather than assuming it is the body's first child.
func _box_shape(body: Node3D) -> CollisionShape3D:
	for child in body.get_children():
		var cs := child as CollisionShape3D
		if cs != null and cs.shape is BoxShape3D:
			return cs
	return null


## The XZ footprint of a collider, taken from the SHAPE's own transform and NOT from the
## body's position. The two are not the same thing, and the difference is the whole
## defect: `_env_collide` hangs a sloped piece's box off its body by half a run and tilts
## it, so a footprint read off `body.global_position` reports a staircase standing where
## its bottom step is — i.e. the measurement would have been wrong in exactly the same
## way and in the same direction as the thing it was supposed to catch.
func _box_footprint(body: Node3D) -> Rect2:
	var cs := _box_shape(body)
	if cs == null:
		return Rect2()
	var s := (cs.shape as BoxShape3D).size * cs.scale
	var b := cs.global_transform.basis
	# Projected extent of a box the shape's own basis may have tilted. Rotation here is
	# about Z, which mixes X with Y and leaves Z alone; written generally anyway so that a
	# collider tilted about another axis does not quietly report a too-small footprint.
	var ex := absf(b.x.x) * s.x + absf(b.y.x) * s.y + absf(b.z.x) * s.z
	var ez := absf(b.x.z) * s.x + absf(b.y.z) * s.y + absf(b.z.z) * s.z
	var p := cs.global_position
	return Rect2(p.x - ex * 0.5, p.z - ez * 0.5, ex, ez)


## Top surface of a collider, by the same projection. `maxf` rather than a sum, because a
## tilted box's highest corner is what matters and the sign of the tilt is not known here.
func _box_top(body: Node3D) -> float:
	var cs := _box_shape(body)
	if cs == null:
		return -999.0
	var s := (cs.shape as BoxShape3D).size * cs.scale
	var b := cs.global_transform.basis
	var ey := absf(b.x.y) * s.x + absf(b.y.y) * s.y + absf(b.z.y) * s.z
	return cs.global_position.y + ey * 0.5


func _box_size(body: Node3D) -> Vector3:
	var cs := _box_shape(body)
	if cs == null:
		return Vector3.ZERO
	return (cs.shape as BoxShape3D).size * cs.scale


## Whether `inner` lies within `outer`, with a tolerance because both are AABBs of boxes
## that were placed by arithmetic and can be off by a millimetre or two without meaning
## anything.
static func _inside(outer: Rect2, inner: Rect2, tol: float = 0.02) -> bool:
	return inner.position.x >= outer.position.x - tol \
		and inner.position.y >= outer.position.y - tol \
		and inner.end.x <= outer.end.x + tol \
		and inner.end.y <= outer.end.y + tol


## How far `inner` pokes out of `outer`, in metres, on its worst side. Reported rather
## than merely detected: "0.13 m" tells you which way to move the box and "it does not
## fit" does not.
static func _overhang(outer: Rect2, inner: Rect2) -> float:
	return maxf(
		maxf(outer.position.x - inner.position.x, inner.end.x - outer.end.x),
		maxf(outer.position.y - inner.position.y, inner.end.y - outer.end.y)
	)


## The size of a `training_build.slab` that was built WITHOUT collision, read off its
## own BoxMesh. Same reason as `_box_size`: the shape is the claim.
func _mesh_extent(node: Node3D) -> Vector3:
	for child in node.get_children():
		var mi := child as MeshInstance3D
		if mi != null and mi.mesh is BoxMesh:
			return (mi.mesh as BoxMesh).size
	return Vector3.ZERO


func _check_the_range_has_three_ranges() -> void:
	if range_node == null:
		_fail("the Training Ground has no PlaytestRange, so §9's targets are not in the room")
		return
	var count := int(range_node.call("target_count"))
	_check(count == 3, "the range built %d targets; §9 asks for light / medium / heavy" % count)
	# THE STAND IS ASKED FOR, NOT ASSUMED. It is host-supplied (the range stands at the
	# chain lab's door, and the door belongs to the lab), so a test that read a constant
	# here would pass while the range stood in the wrong bay.
	var stand := range_node.get("stand") as Vector3
	var weights: Array = PLAYTEST.WEIGHTS
	for i in range(mini(count, 3)):
		var dummy := range_node.get_node_or_null("RangeDummy_%d" % i) as Node3D
		if dummy == null:
			_fail("the range has no target %d" % i)
			continue
		# Flat distance: the range is a line on one floor, and a vertical offset from a
		# court pad must not be allowed to hide a wrong spacing.
		var metres := Vector2(dummy.global_position.x - stand.x, dummy.global_position.z - stand.z).length()
		var wanted: float = PLAYTEST.RANGES[i]
		_check(
			absf(metres - wanted) < 0.15,
			"target %d is %.2fm from the stand; §10 asks for %.0fm" % [i, metres, wanted]
		)
		_check(
			dummy.get("weight") == weights[i],
			"target %d is %s; §9 asks for %s" % [i, String(dummy.get("weight")), String(weights[i])]
		)
		# AND NOTHING ELSE IS STANDING ON THE DECK. The rig can build its own three
		# masses, and the whole reason this bay asks it not to is that two sets of
		# targets on one centreline is a sweep that cannot be attributed to either.
		var rig := world.find_child("ChainRig", true, false) as Node3D
		if rig != null:
			_check(
				rig.find_child("Target_%s" % String(weights[i]), true, false) == null,
				"the rig built its own %s target as well as the range's" % String(weights[i])
			)


func _check_the_drill_dummy_cannot_be_killed() -> void:
	var dummy := world.find_child("DrillDummy", true, false) as Node3D
	if dummy == null:
		_fail("the Combat Court has no 小假人, so a combo test still ends in a walk back")
		return
	var hurtbox := dummy.get_node_or_null("Hurtbox")
	if hurtbox == null:
		_fail("the drill dummy has no Hurtbox, so it cannot be hit at all")
		return
	# SMALLER THAN THE THING IT IS A SMALLER VERSION OF. The user's ask was 小一点,
	# and a size difference nobody measured is a size difference that ships as a
	# duplicate.
	var big := world.find_child("Dummy_W_Dummy", true, false) as Node3D
	if big != null:
		var small_top := _height_of(dummy)
		var big_top := _height_of(big)
		_check(
			small_top < big_top - 0.4,
			"the small dummy is %.2f m tall against the construct's %.2f m"
				% [small_top, big_top]
		)
	# LETHAL DAMAGE AND THE SIGNATURE, through the hurtbox, the way play delivers them.
	hurtbox.call("receive_hit", {"damage": 999999.0, "poise_damage": 0.0, "element": &"physical"})
	await _wait(2)
	_check(
		float(dummy.get("health")) > 0.0,
		"a lethal hit left the drill dummy at %.0f health" % float(dummy.get("health"))
	)
	_check(dummy.visible, "the drill dummy hid itself after a lethal hit")
	hurtbox.call("receive_hit", {
		"damage": 999999.0, "poise_damage": 70.0, "element": &"physical",
		"iaido": true, "cut_normal": Vector3(0.35, 0.94, 0.0).normalized(),
		"cut_line": Vector3(1.0, 0.0, 0.0),
	})
	await _wait(2)
	# `expects_iaido_execution()` is the contract's own answer to "has the ceremony taken
	# this body", and a body it has taken is a body that is about to be cut in half — so
	# asserting on it is asserting the difference between 打不死 and 死得慢一点.
	_check(
		not bool(dummy.call("expects_iaido_execution")),
		"the drill dummy was handed to the execution ceremony, so it is not unkillable"
	)
	_check(dummy.visible, "the drill dummy was hidden by the signature")
	_check(bool(dummy.call("is_alive")), "the drill dummy is not alive after a signature")


## Top of a body's own geometry in world metres, read from its meshes rather than from
## the engine's AABB cache — the same reason `chain_lab._clear_overlapping_dressing`
## asks the mesh: `VisualInstance3D.get_aabb()` is filled in by the renderer and stays
## empty in a headless run, so a test that trusted it would compare 0 to 0.
func _height_of(body: Node3D) -> float:
	var top := -1.0e9
	var feet := 1.0e9
	for child in body.get_children():
		var mesh_node := child as MeshInstance3D
		if mesh_node == null or mesh_node.mesh == null:
			continue
		var box := mesh_node.transform * mesh_node.mesh.get_aabb()
		top = maxf(top, box.end.y)
		feet = minf(feet, box.position.y)
	return top - feet


func _check_the_iaido_post_can_be_cut() -> void:
	var post := world.find_child("IaidoPost", true, false) as Node3D
	if post == null:
		_fail("the Combat Court has no 居合桩, so nothing in this room can be cut in two")
		return
	_post = post
	post.connect("reformed", _on_post_reformed)
	# NOT AN OPPONENT. It is a thing you cut, not a thing that measures distance to you:
	# joining the target group would make the post a valid opponent for every style's
	# Measure, which is what `CombatTuning.ANCHOR_GROUP`'s comment exists to prevent.
	_check(
		not post.is_in_group(CombatTuning.TARGET_GROUP),
		"the iaido post joined the opponent group, so every Measure now sees a post"
	)
	_check(
		post.is_in_group("hostiles"),
		"the iaido post is not in `hostiles`, so the signature's collector cannot find it"
	)
	var hurtbox := post.get_node_or_null("Hurtbox")
	if hurtbox == null:
		_fail("the iaido post has no Hurtbox, so the signature cannot reach it")
		return

	# THE FIRST CUT: it comes apart, and the top half FALLS.
	_iaido_hit(hurtbox, Vector3(0.35, 0.94, 0.0).normalized())
	_check(bool(post.call("is_cut")), "the signature did not cut the iaido post")
	# `get`, not `call`: a counter is a field, and `Object.call` resolves methods only —
	# a test that asked for it by name would report "nonexistent function" instead of
	# reading the number, which is a failure that names the wrong thing.
	_check(int(post.get("cut_count")) == 1, "the post did not count its own first cut")
	var height := float(post.call("cut_height"))
	_check(
		height > POST.MIN_PIECE - 0.01 and height < POST.HEIGHT - POST.MIN_PIECE + 0.01,
		"the post was cut at %.2f m, which is outside the band that leaves two pieces" % height
	)
	_check(
		float(post.get("health")) <= 0.0,
		"the severed post still offers itself as a target to the signature's collector"
	)
	var piece := post.call("top_piece") as RigidBody3D
	if piece == null:
		_fail("the cut produced no falling half, so 真实物理切碎 is not what happened")
		return
	_check(bool(post.call("is_falling")), "the severed half is frozen, so it is posed and not physics")
	# REAL GRAVITY, MEASURED ON THE CENTRE OF MASS. The body's ORIGIN sits at the post's
	# base and the piece is given angular velocity, so the origin swings around the mass
	# it is attached to — reading it would be reading the tumbling, not the falling. The
	# world-space centre of mass is the one point whose y is only gravity's business.
	var com0 := piece.global_transform * piece.center_of_mass
	await _wait(30)
	var com1 := piece.global_transform * piece.center_of_mass
	_check(
		com1.y < com0.y - 0.15,
		"the severed half's mass fell only %.3f m in half a second" % (com0.y - com1.y)
	)

	# RECOVERY, AND IT IS AUTOMATIC. 静置约 2–3 秒 was the ask, so the wait is derived
	# from the fixture's own constants rather than typed as a frame count.
	#
	# COUNTED IN PHYSICS FRAMES, WHICH IS THE UNIT THE FIXTURE COUNTS IN. A render frame
	# is not that unit: with vsync off the render loop can run many times per physics
	# tick, which is how the review sheet once photographed a post that a log line said
	# had already stood back up. Nothing in this file may wait on `process_frame` and then
	# read a fixture timer.
	var frames := int(ceil((POST.RECOVER_DELAY + POST.REFORM_TIME) * 60.0)) + 20
	var recovered := false
	for i in frames:
		await physics_frame
		if not bool(post.call("is_cut")):
			recovered = true
			break
	_check(
		recovered,
		"the post is still in two pieces %.1f s after the cut" % (float(frames) / 60.0)
	)
	# ASKED ON THE FRAME IT SAYS SO, WHICH IS THE ONLY FRAME THAT CAN FAIL.
	#
	# `queue_free` is deferred to the end of the frame, so a severed half that is merely
	# SCHEDULED for deletion still RENDERS for the rest of that frame — and a check made a
	# single `await physics_frame` later sees nothing either way, because by then the node
	# is genuinely gone. This was written that way first, and a deliberate mutation to
	# `_finish_reform` proved it was decoration: the check went on passing while the
	# fixture rendered its debris over its own repaired post. `reformed` is emitted
	# SYNCHRONOUSLY from the last line of `_finish_reform`, so the handler below runs in
	# the one instant where the question has two different answers.
	_check(
		not _debris_at_reform,
		"the post reported itself whole on a frame that still rendered a severed half"
	)
	# THE MESH, NOT THE FLAG. `_build_whole()` runs on the same frame the state flips, so
	# asking `is_cut()` cannot tell a shaft that was rebuilt from one that never stopped
	# being a stump. The height it actually drew is the claim.
	var rebuilt := float(post.call("shaft_height"))
	_check(
		absf(rebuilt - POST.HEIGHT) < 0.02,
		"the recovered shaft is %.2f m tall, not the %.2f m of an uncut post"
			% [rebuilt, POST.HEIGHT]
	)
	_check(post.call("top_piece") == null, "the severed half is still in the room after recovery")
	_check(
		float(post.get("health")) > 0.0,
		"the recovered post is not a valid target again, so it can only be cut once"
	)

	# THE SECOND CUT, cleaned up by the RESET rather than by waiting: a fixture a person
	# can put back without waiting out a timer that exists to make waiting feel
	# deliberate. This also proves the fixture is RE-usable, which a flag cannot.
	_iaido_hit(hurtbox, Vector3(-0.30, 0.95, 0.0).normalized())
	_check(int(post.get("cut_count")) == 2, "the post could not be cut a second time")
	post.call("reset_fixture")
	# SYNCHRONOUS, SO THIS IS ASKED SYNCHRONOUSLY. RESET's promise is that the room is a
	# known state BY THE TIME IT RETURNS, which is a promise a fixture still animating a
	# third of a second later cannot keep — and one that a half scheduled for deletion
	# but not yet freed breaks without any error at all.
	_check(not bool(post.call("is_cut")), "RESET left the iaido post in two pieces")
	_check(not bool(post.call("has_debris")), "RESET left a severed half standing in the room")
	await _wait(2)
	_check(not bool(post.call("is_cut")), "RESET left the iaido post in two pieces after settling")


## READ INSIDE THE SIGNAL, WHICH IS THE ONE MOMENT THE QUESTION HAS AN ANSWER.
##
## `reformed` is emitted synchronously from the last line of `_finish_reform()`, i.e. on
## the frame the state flips and BEFORE the deferred `queue_free` has run. A frame later
## the two cases — hidden, or merely scheduled for deletion — are indistinguishable,
## because both are gone. This is not a stylistic preference: the check was first written
## the obvious way (wait a frame, then ask) and a deliberate mutation showed it passing
## against a fixture that drew its debris over its own repaired post.
func _on_post_reformed() -> void:
	if _post != null and bool(_post.call("has_debris")):
		_debris_at_reform = true


func _iaido_hit(hurtbox: Node, normal: Vector3) -> void:
	hurtbox.call("receive_hit", {
		"damage": 240.0, "poise_damage": 70.0, "element": &"physical",
		"iaido": true, "cut_normal": normal, "cut_line": Vector3(1.0, 0.0, 0.0),
	})


func _check_the_targets_survive_a_session() -> void:
	# §14: hit reaction normal, health effectively infinite. A target that dies turns a
	# combo test into a sequence of dummies, which is the one thing this room must not do.
	if range_node == null:
		return
	var dummy := range_node.get_node_or_null("RangeDummy_0") as Node3D
	if dummy == null:
		return
	var max_health := float(dummy.get("max_health"))
	_check(
		max_health >= 10000.0,
		"a target has %.0f health, which a combo can exhaust (§14)" % max_health
	)
	_hit(dummy, 250.0)
	_check(
		float(dummy.get("health")) > 10000.0,
		"a 250 damage hit took a training target below a session's worth of health"
	)


## Damage arrives the way it does in play - through the hurtbox - so a target that
## cannot be hurt would fail here rather than pass on a direct write to `health`.
func _hit(dummy: Node3D, damage: float) -> void:
	var hurtbox := dummy.get_node_or_null("Hurtbox")
	if hurtbox == null:
		_fail("a range target has no Hurtbox, so it cannot be hit at all")
		return
	hurtbox.call("receive_hit", {"damage": damage, "poise_damage": 0.0, "element": &"physical"})


func _check_reset_puts_the_room_back() -> void:
	if range_node == null:
		return
	var stand := range_node.get("stand") as Vector3
	var dummy := range_node.get_node_or_null("RangeDummy_1") as Node3D
	var home := dummy.global_position if dummy != null else Vector3.ZERO
	if dummy != null:
		dummy.global_position = home + Vector3(2.0, 0.0, 0.0)
		_hit(dummy, 5000.0)
	player.global_position = Vector3(12.0, 0.5, -20.0)

	range_node.call("reset_training")
	await _wait(2)

	# Flat, because the stand's own height is a hand's width of clearance and the claim
	# is "back where they were standing", not "back at one y".
	_check(
		Vector2(player.global_position.x - stand.x, player.global_position.z - stand.z).length() < 1.5,
		"RESET did not put the player back at the stand (they are %.1fm away)"
			% Vector2(player.global_position.x - stand.x, player.global_position.z - stand.z).length()
	)
	if dummy == null:
		return
	_check(
		dummy.global_position.distance_to(home) < 0.05,
		"RESET did not put the moved target back"
	)
	_check(
		is_equal_approx(float(dummy.get("health")), float(dummy.get("max_health"))),
		"RESET left a target at %.0f of %.0f health"
			% [float(dummy.get("health")), float(dummy.get("max_health"))]
	)


# ============================================================================

func _wait(frames: int) -> void:
	for i in frames:
		await physics_frame


## The manager's transition runs on `_process`, and a headless run does not guarantee
## an idle frame per physics tick - waiting two physics frames and reading the result
## is exactly the mistake that made this file fail the first time it ran.
##
## AND A SWITCH IS TWO ACTS, NOT ONE. Putting the sword away is its own beat — the
## sheathe — and the slot does not change until it finishes, so `switching` is FALSE
## for the whole first half of a switch that is very much in flight. A wait that
## watched only that flag returned on the first frame and then read the weapon the
## player was still holding. Both flags are the arming condition; the arena's own test
## spells it the same way (`weapon_switch_integration._pending_or_switching`).
func _settle() -> void:
	var guard := 0
	while _in_flight() and guard < 360:
		await process_frame
		guard += 1


func _in_flight() -> bool:
	if manager == null:
		return false
	return bool(manager.get("switching")) or String(manager.get("_pending_slot")) != ""


func _check(condition: bool, reason: String) -> void:
	if not condition:
		failures.append(reason)


func _fail(reason: String) -> void:
	failures.append(reason)


func _finish() -> void:
	# LET GO OF THE POST BEFORE THE TREE COMES DOWN. The handler above is a `Callable`
	# into this object and `_post` holds a node from inside the scene; leaving either in
	# place turns a clean `quit(0)` into a segfault during teardown — a crash that says
	# nothing about the room and everything about the harness, and one that buries the
	# verdict line under a backtrace.
	if _post != null and is_instance_valid(_post) \
			and _post.is_connected("reformed", _on_post_reformed):
		_post.disconnect("reformed", _on_post_reformed)
	_post = null
	if failures.is_empty():
		print(
			"PASS: the Training Ground comes up playable - a first-person player, a weapon "
			+ "switch, three targets at 3 / 6 / 9 m that a session cannot kill, the chain "
			+ "rig contained by its own bay, a small dummy nobody can kill, a post the "
			+ "signature cuts in two and that stands back up, eight zones that do not share "
			+ "the same ground, a gallery of non-overlapping plinths with every exhibit standing on its own, a 擂台 with a ramp and "
			+ "a gate in its kerb, a hill with four walkable floors, and 50 m of provably "
			+ "empty floor in the long range"
		)
		quit(0)
		return
	for reason in failures:
		print("  - " + reason)
		push_error(reason)
	print("FAIL: %d problem(s)" % failures.size())
	quit(1)
