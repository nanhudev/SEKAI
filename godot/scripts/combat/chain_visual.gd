extends Node3D
class_name ChainVisual
# 缚星链'S BODY: handle, the coils in the hand, the rope, the trident head.
#
# This is a DRAWING. Nothing in the gameplay reads it, and it has no physics of
# its own — which is deliberate, and is now the whole point of V3 (§3): fifty
# RigidBody3Ds and forty-nine joints would be unstable, unsynchronisable and
# unreadable in first person, and none of that instability is something a player
# can feel. What a player CAN feel is weight, sag, lag, tautness — and LENGTH,
# which is the thing V3 exists to add.
#
# The rope is a curve, not a simulation:
#
#   point(t) = lerp(hand, head, t)
#            + DOWN   * sag * sin(pi * t)      ← weight (slack when the head is close)
#            + BEHIND * bow * sin(pi * t)      ← lag (the chain trails a fast head)
#
# Sag and bow are both driven by SLACK and killed by TENSION, so the same code
# produces all three states the brief asks for (§33):
#   held / slow   → visibly hanging
#   fast swing    → straighter, knifing through the air
#   taut          → a straight metal line
#
# Why analytic and not Verlet: the rope has to look right in the one frame a
# player screenshots, every frame, at any framerate, and it must never explode.
# A hanging-cable formula cannot do any of those things wrong.
#
# ===========================================================================
# §1 / §2 / §25 / §26 — WHAT V3 ADDS: THE WEAPON IS LONG, AND YOU CAN SEE IT
#
# Two drawings, both driven by one number — HOW FAR THE HEAD IS PAID OUT.
#
#   THE COIL RIG      how much rope is still in the fist. A preset bundle of
#                     loops whose count falls as the head goes out and climbs
#                     back as it is reeled in. Nothing is simulated: the point
#                     is that a stationary player can see that they are holding
#                     eight metres of chain, not two.
#
#   THE LINK POOL     how much rope is DRAWN. A constant link SIZE, not a
#                     constant link count (§25): a chain drawn with 28 links at
#                     a 9m throw is a 32cm-per-link fence. The pool is 96 and
#                     the drawn subset is `reach / link_spacing`, so the links
#                     are the same size at rest and at full stretch.
#
# Both read `reach / chain_length`, so the quantity the player watches and the
# quantity the drawing reads are the same quantity.

const LINK_TINT := Color(0.66, 0.68, 0.73)
const HEAD_TINT := Color(0.78, 0.76, 0.71)
const HANDLE_TINT := Color(0.26, 0.24, 0.22)
const TRAIL_TINT := Color(0.95, 0.72, 0.35)
# §2/§26 — THE BUNDLE'S AXIS, AND THE ONE THING THAT DECIDES WHETHER IT READS.
#
# A torus is only a torus from the side. Look down its own axis and it is a flat
# hexagon, which is what the first V3 idle take photographed: eight loops stacked
# along a DOWN-AND-FORWARD axis (0, −0.55, −0.83) is 34° off the eye's own forward
# vector, so the player was looking almost straight down the barrel of the coil and
# all eight loops superimposed into one dark ring. The count was never visible, and
# §26's whole claim is the count.
#
# Nearly vertical instead, with only a little forward lean: the eye now meets the
# loop PLANES edge-on, so each loop is a separate band and the bundle reads as a
# spring of chain. The lean is what keeps it from becoming a flat 2D ladder — a
# few degrees of recession is enough for the near loops to sit in front of the far
# ones.
const COIL_AXIS := Vector3(0.08, 0.94, -0.33)

# How much of the spare chain turns into visible hanging. Bigger = droopier.
const SAG_PER_SLACK := 0.34
const SAG_LIMIT := 0.95
# ONLY THE FIRST FEW METRES OF SPARE ROPE CAN SAG (§1). Past this, the spare rope
# is COILED IN THE PLAYER'S HAND and cannot droop, because it is not in the air.
# Without this cap a 10m rope would spend every frame of every technique pinned at
# `SAG_LIMIT`, and the loose → tight beat of §3 would have no room left to happen.
const SLACK_FOR_SAG := SAG_LIMIT / SAG_PER_SLACK
# Lateral bow per m/s of head speed. Small: a chain trails, it does not flap.
const BOW_PER_SPEED := 0.055
const BOW_LIMIT := 0.85
# Trail: a RIBBON of constant LENGTH in metres, not a fixed count of frames. A
# count would make the trail 8cm long at rest and 20m long at full spin.
const TRAIL_MAX_LENGTH := 2.6
const TRAIL_MIN_POINTS := 5
const TRAIL_MAX_POINTS := 90
const TRAIL_WIDTH := 0.055
# Below this the head is not travelling and has no direction of its own.
const HEAD_AIM_MIN_SPEED := 1.2
# How many links back the fallback tangent is taken from. One link is ~11cm, and
# the LAST one carries the whole of the rope's sag and bow, so aiming a head off
# it tilts the blade by tens of degrees exactly when the rope is most visible.
const HEAD_TANGENT_LINKS := 5
# Time constant of the head's own turn. Long enough that a reversal is a swing and
# not a flip, short enough that it still reads as following the throw.
#
# MEASURED, not chosen. `chain_physicality` group C reads the cosine between the
# head's blade and its own direction of travel while a 横缚 is in the air, and a
# first-order filter chasing a direction that is itself rotating lags by `ω·τ`. The
# strike turns the head's bearing at about 26° per frame — 27 rad/s — so at τ =
# 0.045 the blade sat ~70° behind its own motion for the whole of the fastest part
# of every strike: the head spent the strike looking somewhere other than where it
# was going (§5), which is what a ball on a string does. 0.030 puts the lag inside
# a right angle while keeping the turn a turn: a 90° reversal still takes ~3 frames.
const HEAD_TURN_TAU := 0.030

# A LOADED LINE HUMS. At full tension the chain shivers: it is the visual half of
# §43's "tension must be perceptible", and it is the one cue that says "at the
# limit" while a straight line alone only says "far away". Deliberately TINY — 13mm
# at full load — because §33 forbids the chain looking like a rubber band, and a
# taut rope that whips around is exactly that. It reads as metal under strain, not
# as slack, and 7.5Hz is above the sway of the idle pose so the two never argue.
const TREMOR_PER_TENSION := 0.013
const TREMOR_HZ := 7.5
# Below this much tension the line is merely out there rather than loaded.
const TREMOR_MIN_TENSION := 0.82

var links := 96
var link_spacing := 0.11
var head_size := 0.34
var chain_length := 10.0
var coil_max := 8
var coil_min := 1
var coil_radius := 0.105
var coil_pitch := 0.040

var _link_mesh: MultiMeshInstance3D
var _head: Node3D
var _head_blade: MeshInstance3D
var _trail: MeshInstance3D
var _trail_mesh: ImmediateMesh
var _trail_points: Array[Vector3] = []
var _handle: Node3D
var _tremor_time := 0.0
# The polyline as last drawn, hand → head. Kept and exposed because "the chain looks
# like a chain" is a claim about these numbers: how far the drawn line strays from a
# straight rope is exactly what separates sag, bow and vibration, and a test that
# cannot ask where the links ARE can only assert that something was drawn.
var _points: Array[Vector3] = []
# Where the head is POINTING, kept between frames so it can be eased (§5).
var _head_dir := Vector3.FORWARD
# ---- the V3 drawings, and the one number both of them read -------------------
# How far the head is out, as last handed in. Everything below is derived.
var _reach := 0.0
var _links_drawn := 0
var _coils := 0
var _coil_root: Node3D
var _coil_loops: Array[MeshInstance3D] = []


func _ready() -> void:
	# The chain lives in world space: the hand moves with the camera and the head
	# moves with nothing at all, so a parent transform would only ever be in the
	# way. `top_level` makes this node's children world-space, which is exactly
	# the coordinate system the director already thinks in.
	top_level = true
	# ...BUT `top_level` KEEPS THE TRANSFORM THE NODE ALREADY HAD. Flipping the flag
	# does not clear it, so this node kept the player's SPAWN position, and every
	# link — whose instance transform is a world coordinate — was drawn offset by
	# it. The head is placed with an explicit global transform and so was correct,
	# which is what made the bug invisible: a chain whose head is on the enemy and
	# whose links are five metres behind it still answers `is_drawn() == true`, and
	# still looks like a chain to a camera that happens to sit where the offset puts
	# it. This node is not a place, it is a coordinate system, so it takes the
	# identity transform and the instance transforms become the world coordinates
	# they were always written as.
	transform = Transform3D.IDENTITY
	_build_links()
	_build_head()
	_build_trail()
	_build_coils()


func configure(
	count: int,
	length: float,
	size: float,
	spacing: float = 0.0,
	coils_max: int = 8,
	coils_min: int = 1
) -> void:
	links = maxi(2, count)
	chain_length = maxf(0.5, length)
	# The link length is the SPACING, not `length / count`: the pool is a ceiling
	# and the drawn subset is what the rope actually needs (§25).
	link_spacing = maxf(0.02, spacing if spacing > 0.0 else length / float(links))
	head_size = size
	coil_max = maxi(1, coils_max)
	coil_min = clampi(coils_min, 0, coil_max)
	if is_inside_tree():
		_build_links()
		_build_head()
		_build_coils()


# The first-person handle. Parented to a camera-space anchor (not to this node)
# so it rides the hand: the chain then runs from screen space out into the world,
# which is the only way a first-person chain reads as attached to the player.
# The COILS ride the same anchor, because they are held, not thrown.
func build_handle(anchor: Node3D) -> void:
	for child in anchor.get_children():
		if child.name == &"ChainHandleVisual":
			child.queue_free()
	_handle = Node3D.new()
	_handle.name = "ChainHandleVisual"
	anchor.add_child(_handle)

	var material := StandardMaterial3D.new()
	material.albedo_color = HANDLE_TINT
	material.roughness = 0.55
	material.metallic = 0.5

	var grip := MeshInstance3D.new()
	var grip_mesh := CylinderMesh.new()
	grip_mesh.top_radius = 0.030
	grip_mesh.bottom_radius = 0.034
	grip_mesh.height = 0.20
	grip.mesh = grip_mesh
	grip.material_override = material
	grip.rotation.x = PI * 0.5
	_handle.add_child(grip)

	var ring := MeshInstance3D.new()
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 0.030
	ring_mesh.outer_radius = 0.052
	ring.mesh = ring_mesh
	ring.material_override = material
	ring.position = Vector3(0.0, 0.0, -0.125)
	_handle.add_child(ring)

	# Rebuilt here as well as in `_ready`, because before a hand anchor exists
	# there is nowhere for a HELD bundle to live and the rig falls back to a
	# world-space stand-in at the hand. Attaching the real anchor supersedes it.
	_build_coils()


func set_chain_visible(shown: bool) -> void:
	if _link_mesh != null:
		_link_mesh.visible = shown
	if _head != null:
		_head.visible = shown
	if _trail != null and not shown:
		_trail.visible = false
	if _handle != null:
		_handle.visible = shown
	if _coil_root != null and _handle == null:
		_coil_root.visible = shown
	if not shown:
		# The head's aim is eased from its own history, so a chain put away and
		# taken out again must not swing round from wherever it was last pointing.
		_head_dir = Vector3.FORWARD
		_trail_points.clear()


# Is the weapon actually being drawn right now. Asked by tests, and by anything
# that later needs to know whether the chain is in the world without reaching into
# this file's private nodes.
func is_drawn() -> bool:
	return _link_mesh != null and _link_mesh.visible


# ---- §25/§26, THE TWO ANSWERS THE DRAWING IS MADE OF ------------------------
# Both pure functions of the reach, so a test can ask what the drawing WILL do
# without running a frame — and so the rig and the assertion can never drift.

# How many links the rope is drawn with at this reach. A CONSTANT LINK SIZE:
# two links hanging at rest, eighty-seven at full stretch, same 11cm each.
func visible_links_for(reach: float) -> int:
	return clampi(int(roundf(maxf(0.0, reach) / maxf(0.001, link_spacing))), 2, links)


# How many loops are still coiled in the hand, `coil_min` .. `coil_max`.
func coils_for(reach: float) -> int:
	var paid := clampf(maxf(0.0, reach) / maxf(0.001, chain_length), 0.0, 1.0)
	return int(roundf(lerpf(float(coil_max), float(coil_min), paid)))


# What the last update actually drew. The claim "the weapon looks long while it is
# idle and short while it is thrown" is a claim about these two integers.
func links_drawn() -> int:
	return _links_drawn


func coils() -> int:
	return _coils


func coil_loops() -> Array[MeshInstance3D]:
	return _coil_loops


func update_chain(
	hand: Vector3,
	head: Vector3,
	head_velocity: Vector3,
	tension: float,
	delta: float
) -> void:
	if _link_mesh == null:
		return
	var taut := clampf(tension, 0.0, 1.0)
	var reach := hand.distance_to(head)
	# §1: only the rope that is IN THE AIR can hang. Every metre past this cap is
	# coiled in the fist, so it contributes nothing to the shape of the span.
	var slack := minf(maxf(0.0, chain_length - reach), SLACK_FOR_SAG)
	var sag := minf(SAG_LIMIT, slack * SAG_PER_SLACK) * (1.0 - taut)

	# The chain trails a fast head. Using the horizontal velocity keeps a
	# vertical slam from bowing the chain into the floor, the same mistake the
	# wind gust made when it carried its pitch.
	var flat := Vector3(head_velocity.x, 0.0, head_velocity.z)
	var bow := Vector3.ZERO
	if flat.length() > 0.05:
		bow = -flat.normalized() * minf(BOW_LIMIT, flat.length() * BOW_PER_SPEED) * (1.0 - taut)

	# THE HUM. Perpendicular to the line, horizontal, zero when the chain is not
	# loaded. It rides the same arch as sag and bow so the ends stay pinned: a chain
	# that vibrated at the hand would look like the PLAYER was shaking.
	_tremor_time += delta
	var tremor := Vector3.ZERO
	var load := clampf((taut - TREMOR_MIN_TENSION) / maxf(0.001, 1.0 - TREMOR_MIN_TENSION), 0.0, 1.0)
	if load > 0.0:
		var axis := head - hand
		axis.y = 0.0
		if axis.length() > 0.05:
			axis = axis.normalized()
			tremor = (
				Vector3(-axis.z, 0.0, axis.x)
				* TREMOR_PER_TENSION
				* load
				* sin(_tremor_time * TAU * TREMOR_HZ)
			)

	_reach = reach
	_links_drawn = visible_links_for(reach)
	_coils = coils_for(reach)

	# The span is drawn with exactly as many links as the paid-out rope needs, and
	# they are placed at even fractions of it — so the link size is a property of
	# the WEAPON and not of how far the throw went (§25).
	var drawn := _links_drawn
	var points: Array[Vector3] = []
	points.resize(drawn + 1)
	for i in range(drawn + 1):
		var t := float(i) / float(drawn)
		var arch := sin(PI * t)
		points[i] = hand.lerp(head, t) + Vector3.DOWN * sag * arch + (bow + tremor) * arch
	_points = points
	_place_links(points, drawn)
	_place_head(head, points, head_velocity, delta)
	_place_coils(hand)
	_update_trail(head, delta)


# Where the links were last drawn, as a copy: hand → head, one point per link seam.
func drawn_points() -> Array[Vector3]:
	return _points.duplicate()


# How far the drawn chain strays from the straight line between its own ends, in
# metres. This single number is the difference between a rope under load and a rope
# hanging — and it is bounded on purpose: §33 forbids the rubber band.
func drawn_slack() -> float:
	if _points.size() < 3:
		return 0.0
	var a := _points[0]
	var b := _points[_points.size() - 1]
	var span := b - a
	var length := span.length()
	if length < 0.0001:
		return 0.0
	var worst := 0.0
	for i in range(1, _points.size() - 1):
		var offset := _points[i] - a
		worst = maxf(worst, (offset - span * (offset.dot(span) / (length * length))).length())
	return worst


func _build_links() -> void:
	if _link_mesh == null:
		_link_mesh = MultiMeshInstance3D.new()
		_link_mesh.name = "Links"
		add_child(_link_mesh)
	_link_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mesh := BoxMesh.new()
	# A squat box rather than a torus: at first-person distance a real link torus
	# is three pixels wide and reads as nothing. The silhouette is what matters.
	#
	# V3 · 0.048 WAS A WIRE. The first V3 clean tour was watched, and the worst beat
	# in it was not a timing or a framing problem — it was that the chain itself did
	# not read as a chain: a 4.8cm box on an 11cm pitch is 4px of metal with 1px gaps
	# at four metres, which is a dotted line, and PART O fails a loop that looks like
	# "一根线飞来飞去". 7.2cm on the same pitch is 7px of metal with 3px of daylight,
	# which is a chain.
	#
	# The weight had to come from the link's SIZE and not from the PITCH: raising the
	# pitch to 0.145 also reddened `chain_physicality`, because the drawn polyline has
	# one point per link and a coarser polyline samples a 0.95m sag short of its apex.
	# See the note on `link_spacing` in ChainMoveset — the two knobs are not
	# interchangeable even though they look it.
	mesh.size = Vector3(link_spacing * 0.72, 0.072, 0.072)
	var material := StandardMaterial3D.new()
	material.albedo_color = LINK_TINT
	# §LINK METAL. `metallic` 0.75 with `roughness` 0.42 was measured to render the
	# whole weapon as a SILHOUETTE: a metal has no diffuse term, so in a scene lit by
	# one directional light plus a sky cubemap it is whatever the sky reflects and
	# nothing else. LINK_TINT is a light steel (0.66, 0.68, 0.73) and the chain was
	# still black in every frame, which is the giveaway — the albedo was never being
	# shown. At 0.45 the albedo carries again and the chain reads as steel that is
	# lit, not as a hole cut in the deck.
	material.roughness = 0.50
	material.metallic = 0.45
	mesh.material = material
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = mesh
	# The POOL. Only `visible_instance_count` moves per frame — allocating 96 and
	# drawing 2 costs one buffer, not two allocations.
	multi.instance_count = links
	multi.visible_instance_count = links
	_link_mesh.multimesh = multi


# §0 — THE TRIDENT. Central piercing blade, two splayed side blades, two rear
# barbs, one heavy collar where the rope enters.
#
# It has to support 刺 / 钩 / 贯穿 / 拉扯 / 扫击 with its SILHOUETTE ALONE, because
# that is all a player gets while it is doing 40 m/s across the middle of the
# screen. So the three readings are separate parts rather than one shape doing
# everything: the central spike IS 贯穿 (long, straight, on the chain axis), the
# splayed pair is 扫击 (a wide fork), and the rear barbs are 钩 / 拉扯 — they face
# BACKWARD, so the head still holds something when the chain is hauled.
#
# §4: geometry and material only. No glow, no trail-as-identity — those are
# decoration over a shape that has to work on its own. Local forward is -Z.
func _build_head() -> void:
	if _head == null:
		_head = Node3D.new()
		_head.name = "TerminalHead"
		add_child(_head)
	# Rebuilt in place rather than queued: `configure` may run after `_ready`, and
	# a frame of doubled trident is a frame the review will photograph.
	for child in _head.get_children():
		_head.remove_child(child)
		child.free()

	var material := StandardMaterial3D.new()
	material.albedo_color = HEAD_TINT
	# §HEAD METAL — THE SAME TRAP AS THE LINKS, AND IT WAS STILL OPEN HERE.
	#
	# 0.95 metallic / 0.22 roughness is a mirror, and a mirror with nothing to
	# mirror is black. The whole weapon is lit by one directional light plus a sky,
	# so the head — the single object the player has to track at 40m/s — rendered in
	# the first V3 tour as a pure black speck: HEAD_TINT is a pale bone-steel
	# (0.78, 0.76, 0.71) and NONE of it was reaching the frame. The links were
	# already moved to 0.45 for exactly this reason; the head is now the same
	# material family, just a little tighter (0.34 roughness) so it keeps a
	# highlight that reads as an edge.
	material.roughness = 0.34
	material.metallic = 0.45

	var h := head_size
	# THE COLLAR. The heavy end, and the thing that makes the head read as mass
	# rather than as a fork that happened to land on a rope.
	var hub := MeshInstance3D.new()
	var hub_mesh := CylinderMesh.new()
	hub_mesh.top_radius = h * 0.21
	hub_mesh.bottom_radius = h * 0.24
	hub_mesh.height = h * 0.46
	hub_mesh.radial_segments = 8
	hub.mesh = hub_mesh
	hub.material_override = material
	hub.rotation.x = PI * 0.5
	hub.position = Vector3(0.0, 0.0, h * 0.24)
	_head.add_child(hub)

	# 贯穿 · the central blade. The longest thing on the weapon's axis, and the
	# reason the head's direction is legible from any angle.
	_head.add_child(_spike(material, h * 0.115, h * 2.05, Vector3(0.0, 0.0, -1.0), Vector3(0.0, 0.0, h * 0.16)))
	# 扫击 · the fork. Splayed ~23° so the three points read as three at a glance
	# and the whole head is a trident rather than a spear.
	_head.add_child(_spike(material, h * 0.075, h * 1.20, Vector3(-0.42, 0.06, -1.0), Vector3(-h * 0.17, 0.0, h * 0.02)))
	_head.add_child(_spike(material, h * 0.075, h * 1.20, Vector3(0.42, 0.06, -1.0), Vector3(h * 0.17, 0.0, h * 0.02)))
	# 钩 / 拉扯 · the barbs. They point BACKWARD on purpose: a hook that faces
	# forward is a spike, and this is the half of the head that has to hold
	# something while the player walks away from it.
	_head.add_child(_spike(material, h * 0.055, h * 0.62, Vector3(-0.34, 0.0, 1.0), Vector3(-h * 0.30, 0.0, -h * 0.10)))
	_head.add_child(_spike(material, h * 0.055, h * 0.62, Vector3(0.34, 0.0, 1.0), Vector3(h * 0.30, 0.0, -h * 0.10)))

	_head_blade = _head.get_child(1) as MeshInstance3D


# One tapered point: a CylinderMesh with no top radius is a cone, whose apex sits
# on its own +Y. Put +Y along `direction` and the point goes where the data says,
# which is cheaper and more reliable than hand-rolling an ArrayMesh and getting a
# winding order wrong on one of five blades.
func _spike(material: StandardMaterial3D, radius: float, length: float,
		direction: Vector3, at: Vector3, segments: int = 6) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = radius
	cone.height = length
	cone.radial_segments = segments
	cone.rings = 1
	node.mesh = cone
	node.material_override = material
	var dir := direction.normalized()
	node.transform = Transform3D(_basis_y_along(dir), at + dir * (length * 0.5))
	return node


# A basis whose +Y is `direction`. See `_spike`.
func _basis_y_along(direction: Vector3) -> Basis:
	var y := direction.normalized()
	var ref := Vector3.UP
	if absf(y.dot(Vector3.UP)) > 0.95:
		ref = Vector3.FORWARD
	var x := ref.cross(y).normalized()
	var z := x.cross(y).normalized()
	return Basis(x, y, z)


# §2 / §26 — THE COILS IN THE HAND.
#
# A preset bundle, not a simulation: `coil_max` loops around the grip, each one
# with its own small deterministic wobble so it reads as a loose fistful rather
# than a stack of washers, and only the first `_coils` of them drawn. Loops are
# dropped from the FAR END as the rope pays out, so the bundle visibly empties
# from the outside in and refills when the chain comes home.
#
# Parented to the handle anchor when there is one, because coils are HELD — they
# must ride the hand and the camera shake, not the world.
func _build_coils() -> void:
	var parent: Node = _handle if _handle != null else self
	if _coil_root != null:
		if _coil_root.get_parent() != null:
			_coil_root.get_parent().remove_child(_coil_root)
		_coil_root.free()
	_coil_loops.clear()
	_coil_root = Node3D.new()
	_coil_root.name = "HeldCoils"
	parent.add_child(_coil_root)

	var material := StandardMaterial3D.new()
	material.albedo_color = LINK_TINT
	# Same treatment as the links, and for the same reason: 0.80 metallic rendered
	# the fistful that §26 is ABOUT as an unreadable black lump, so the one shot
	# whose entire subject is "look how much chain is in this hand" showed a shadow.
	material.roughness = 0.50
	material.metallic = 0.45
	var loop_mesh := TorusMesh.new()
	loop_mesh.inner_radius = coil_radius * 0.58
	loop_mesh.outer_radius = coil_radius
	loop_mesh.rings = 6
	loop_mesh.ring_segments = 10
	for i in coil_max:
		var loop := MeshInstance3D.new()
		loop.mesh = loop_mesh
		loop.material_override = material
		loop.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# Deterministic per-index wobble: no RNG, so the bundle is the same bundle
		# in every frame of every render and a test can reason about it.
		loop.position = Vector3(
			sin(float(i) * 2.399) * 0.013,
			float(i) * coil_pitch,
			sin(float(i) * 1.117) * 0.011
		)
		loop.rotation = Vector3(
			sin(float(i) * 1.703) * 0.13,
			sin(float(i) * 0.911) * 0.45,
			sin(float(i) * 2.117) * 0.15
		)
		_coil_root.add_child(loop)
		_coil_loops.append(loop)
	_coils = -1
	_place_coils(Vector3.ZERO)


# The bundle's rest pose: standing up out of the fist along `COIL_AXIS`, so the eye
# meets the loop planes edge-on and the player reads a column of rings rather than a
# single donut. Stacked along that axis, so the count is legible.
#
# It is parked BELOW and INBOARD of the hand anchor rather than on it (−0.10, −0.14):
# the anchor is 34cm under the eye and 30cm to the right, so a stack growing straight
# off it runs into the bottom-right corner of the first-person frame and the last two
# loops are cropped off the edge. §26 asks for the count to be VISIBLE, so the offset
# exists to bring all eight bands inside the shot — pulled left toward the centre line
# and only far enough down that the bottom loop still clears the frame edge.
func _place_coils(hand: Vector3) -> void:
	if _coil_root == null:
		return
	if _handle == null:
		# No hand anchor (a headless rig, or a stage with no first-person arms):
		# the bundle stands in at the hand's world position so the drawing still
		# exists and a test can still count it.
		_coil_root.global_transform = Transform3D(
			_basis_y_along(COIL_AXIS), hand
		)
	elif _coil_root.get_parent() == _handle:
		_coil_root.transform = Transform3D(
			_basis_y_along(COIL_AXIS), Vector3(-0.10, -0.14, -0.10)
		)
	var shown := _coils if _coils >= 0 else coil_max
	for i in _coil_loops.size():
		var loop := _coil_loops[i]
		loop.visible = i < shown and (_handle == null or _handle.visible)


func _build_trail() -> void:
	_trail = MeshInstance3D.new()
	_trail.name = "HeadTrail"
	_trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_trail_mesh = ImmediateMesh.new()
	_trail.mesh = _trail_mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = TRAIL_TINT
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.vertex_color_use_as_albedo = true
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_trail.material_override = material
	add_child(_trail)


func _place_links(points: Array[Vector3], drawn: int) -> void:
	var multi := _link_mesh.multimesh
	if multi == null or multi.instance_count < links:
		return
	multi.visible_instance_count = drawn
	for i in drawn:
		var a := points[i]
		var b := points[i + 1]
		var tangent := b - a
		if tangent.length_squared() < 0.000001:
			tangent = Vector3.FORWARD
		tangent = tangent.normalized()
		var basis := _basis_along(tangent)
		# Alternating roll, the way real links sit at right angles to each other.
		if i % 2 == 1:
			basis = basis.rotated(tangent, PI * 0.5)
		multi.set_instance_transform(i, Transform3D(basis, (a + b) * 0.5))


# A slam points the head straight down. `looking_at` needs an up vector that is
# not parallel to the direction, or the basis collapses — and a chain that
# disappears during the one move with the biggest height change is a bug that
# only shows up in the last ninety degrees.
func _basis_along(direction: Vector3) -> Basis:
	var up := Vector3.UP
	if absf(direction.dot(Vector3.UP)) > 0.98:
		up = Vector3.FORWARD
	return Basis.looking_at(direction, up)


# §5 · THE HEAD MUST POINT WHERE IT IS GOING.
#
# It used to take its direction from the LAST LINK — `head - points[n-1]`, a 17cm
# segment that carries the whole of the rope's sag and bow on its far end. Measured
# before this pass: a head doing 76 m/s along a wide sweep was drawn up to 0.33
# cosine away from its own travel, i.e. pointing most of 70° off, and the reading
# got WORSE the more slack the rope had. The blade was aimed into the floor while
# the head flew forward — the "ball on a string" failure, arrived at by arithmetic.
#
# While the head is actually travelling, its own velocity IS its direction, and
# that is the only reading that stays true through a sag, a bow and a whip alike.
# At rest there is no velocity to point along, so a LONGER slice of the rope takes
# over — the same idea, with the last link's tilt divided by five.
func _place_head(head: Vector3, points: Array[Vector3], velocity: Vector3, delta: float) -> void:
	var solved := Vector3.ZERO
	if velocity.length() > HEAD_AIM_MIN_SPEED:
		solved = velocity.normalized()
	elif points.size() >= 2:
		var back := maxi(0, points.size() - 1 - HEAD_TANGENT_LINKS)
		solved = head - points[back]
		if solved.length_squared() > 0.000001:
			solved = solved.normalized()
		else:
			solved = Vector3.ZERO
	if solved != Vector3.ZERO:
		# Eased, so a head that reverses swings round instead of flipping, and a
		# slow head cannot chatter between the two sources above.
		var blend := 1.0 - exp(-maxf(delta, 0.0001) / HEAD_TURN_TAU)
		_head_dir = _head_dir.lerp(solved, blend)
		if _head_dir.length_squared() > 0.000001:
			_head_dir = _head_dir.normalized()
	_head.global_transform = Transform3D(_basis_along(_head_dir), head)


# §M · A TRAIL IS A RIBBON, NOT A LINE STRIP.
#
# A line strip is one pixel wide whatever the resolution, so on a 4K capture the
# "where is the head" cue is invisible — which is the one job it has (§32). It is
# also a fixed COUNT of frames, which makes it 8cm long at rest and twenty metres
# long at full spin. So: constant length in METRES, and a camera-facing ribbon
# that is the same width on any screen. Headless has no camera, so the fallback
# faces +Y instead of the eye and the two never disagree about width.
func _update_trail(head: Vector3, delta: float) -> void:
	if _trail_mesh == null:
		return
	_trail_points.push_front(head)
	while _trail_points.size() > TRAIL_MAX_POINTS:
		_trail_points.pop_back()
	while _trail_points.size() > TRAIL_MIN_POINTS and _trail_span() > TRAIL_MAX_LENGTH:
		_trail_points.pop_back()
	var span := _trail_span()
	var moving := _trail_points.size() >= 3 and span > 0.4
	_trail.visible = moving
	if not moving:
		return
	var cam: Camera3D = null
	if is_inside_tree():
		cam = get_viewport().get_camera_3d()
	_trail_mesh.clear_surfaces()
	_trail_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	var count := _trail_points.size()
	for i in count:
		var age := float(i) / float(count - 1)
		var fade := pow(1.0 - age, 2.0)
		var color := Color(TRAIL_TINT.r, TRAIL_TINT.g, TRAIL_TINT.b, fade * 0.55)
		var p := _trail_points[i]
		var tangent := Vector3.ZERO
		if i + 1 < count:
			tangent = _trail_points[i + 1] - p
		elif i > 0:
			tangent = p - _trail_points[i - 1]
		var face := Vector3.UP
		if cam != null:
			face = cam.global_position - p
		if face.length_squared() < 0.000001:
			face = Vector3.UP
		var side := tangent.cross(face)
		if side.length_squared() < 0.000001:
			side = Vector3.RIGHT
		side = side.normalized() * TRAIL_WIDTH * (0.30 + 0.70 * fade)
		_trail_mesh.surface_set_color(color)
		_trail_mesh.surface_add_vertex(p + side)
		_trail_mesh.surface_set_color(color)
		_trail_mesh.surface_add_vertex(p - side)
	_trail_mesh.surface_end()


func _trail_span() -> float:
	var total := 0.0
	for i in range(1, _trail_points.size()):
		total += _trail_points[i - 1].distance_to(_trail_points[i])
	return total
