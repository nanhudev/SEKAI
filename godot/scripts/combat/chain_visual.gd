extends Node3D
class_name ChainVisual
# 缚星链'S BODY: handle, chain, terminal head.
#
# This is a DRAWING. Nothing in the gameplay reads it, and it has no physics of
# its own — which is deliberate. See brief §5/§6/§50: twenty links with their own
# rigid bodies would be unstable, unsynchronisable and unreadable in first
# person, and none of that instability is something a player can feel. What a
# player CAN feel is weight, sag, lag and tautness, so those are what this file
# is made of.
#
# The chain is a curve, not a simulation:
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

const LINK_TINT := Color(0.66, 0.68, 0.73)
const HEAD_TINT := Color(0.78, 0.76, 0.71)
const HANDLE_TINT := Color(0.26, 0.24, 0.22)
const TRAIL_TINT := Color(0.95, 0.72, 0.35)

# How much of the spare chain turns into visible hanging. Bigger = droopier.
const SAG_PER_SLACK := 0.34
const SAG_LIMIT := 0.95
# Lateral bow per m/s of head speed. Small: a chain trails, it does not flap.
const BOW_PER_SPEED := 0.055
const BOW_LIMIT := 0.85
const TRAIL_POINTS := 26
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

var links := 28
var link_length := 0.17
var head_size := 0.30
var chain_length := 4.7

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


func configure(count: int, length: float, size: float) -> void:
	links = maxi(2, count)
	chain_length = length
	link_length = chain_length / float(links)
	head_size = size
	if is_inside_tree():
		_build_links()
		_build_head()


# The first-person handle. Parented to a camera-space anchor (not to this node)
# so it rides the hand: the chain then runs from screen space out into the world,
# which is the only way a first-person chain reads as attached to the player.
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


func set_chain_visible(shown: bool) -> void:
	if _link_mesh != null:
		_link_mesh.visible = shown
	if _head != null:
		_head.visible = shown
	if _trail != null and not shown:
		_trail.visible = false
	if _handle != null:
		_handle.visible = shown


# Is the weapon actually being drawn right now. Asked by tests, and by anything
# that later needs to know whether the chain is in the world without reaching into
# this file's private nodes.
func is_drawn() -> bool:
	return _link_mesh != null and _link_mesh.visible


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
	var slack := maxf(0.0, chain_length - reach)
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

	var points: Array[Vector3] = []
	points.resize(links + 1)
	for i in range(links + 1):
		var t := float(i) / float(links)
		var arch := sin(PI * t)
		points[i] = hand.lerp(head, t) + Vector3.DOWN * sag * arch + (bow + tremor) * arch
	_points = points
	_place_links(points)
	_place_head(head, points)
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
	mesh.size = Vector3(link_length * 0.62, 0.048, 0.048)
	var material := StandardMaterial3D.new()
	material.albedo_color = LINK_TINT
	material.roughness = 0.42
	material.metallic = 0.75
	mesh.material = material
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = mesh
	multi.instance_count = links
	multi.visible_instance_count = links
	_link_mesh.multimesh = multi


func _build_head() -> void:
	if _head == null:
		_head = Node3D.new()
		_head.name = "TerminalHead"
		add_child(_head)
	if _head_blade == null:
		_head_blade = MeshInstance3D.new()
		_head_blade.name = "AnchorBlade"
		_head.add_child(_head_blade)
	# 刃锤 / ANCHOR BLADE: a weighted head with a short edge. Long on the chain
	# axis so its direction is legible from any angle — the brief's requirement
	# that the head identify its own orientation (§36).
	var blade := BoxMesh.new()
	blade.size = Vector3(0.10, head_size * 0.55, head_size * 1.5)
	var material := StandardMaterial3D.new()
	material.albedo_color = HEAD_TINT
	material.roughness = 0.30
	material.metallic = 0.9
	blade.material = material
	_head_blade.mesh = blade
	_head_blade.position = Vector3.ZERO
	# A counterweight sphere so the head reads as heavy rather than as a stick.
	var weight := MeshInstance3D.new()
	var weight_mesh := SphereMesh.new()
	weight_mesh.radius = head_size * 0.38
	weight_mesh.height = head_size * 0.76
	weight.mesh = weight_mesh
	weight.material_override = material
	weight.position = Vector3(0.0, 0.0, head_size * 0.35)
	_head.add_child(weight)


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
	_trail.material_override = material
	add_child(_trail)


func _place_links(points: Array[Vector3]) -> void:
	var multi := _link_mesh.multimesh
	if multi == null or multi.instance_count < links:
		return
	for i in links:
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


func _place_head(head: Vector3, points: Array[Vector3]) -> void:
	var tangent := Vector3.FORWARD
	if points.size() >= 2:
		tangent = head - points[points.size() - 2]
	if tangent.length_squared() < 0.000001:
		tangent = Vector3.FORWARD
	_head.global_transform = Transform3D(_basis_along(tangent.normalized()), head)


func _update_trail(head: Vector3, delta: float) -> void:
	if _trail_mesh == null:
		return
	# A slow-following ghost of where the head has been. It is the one cue that
	# answers "where is it" when the head is off screen, without an arrow (§32).
	_trail_points.push_front(head)
	while _trail_points.size() > TRAIL_POINTS:
		_trail_points.pop_back()
	var moving := _trail_points.size() >= 3 and _trail_points[0].distance_to(_trail_points[_trail_points.size() - 1]) > 0.4
	_trail.visible = moving
	if not moving:
		return
	_trail_mesh.clear_surfaces()
	_trail_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	var count := _trail_points.size()
	for i in count:
		var age := float(i) / float(count - 1)
		var fade := pow(1.0 - age, 2.0)
		var color := Color(TRAIL_TINT.r, TRAIL_TINT.g, TRAIL_TINT.b, fade * 0.7)
		_trail_mesh.surface_set_color(color)
		_trail_mesh.surface_add_vertex(_trail_points[i])
	_trail_mesh.surface_end()
