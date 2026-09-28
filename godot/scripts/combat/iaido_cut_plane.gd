extends RefCounted
class_name IaidoCutPlane

# 一刀只有一个物理事实.
#
# The ceremony draws its cut in SCREEN space: a line through `cut_center` at
# `cut_angle_degrees`. Screen space is fine for a full-frame picture effect and
# completely useless for anything that has to happen in the world — an enemy cut
# in half, a shard released along the wound, a cut mark lying on a body.
#
# THIS CLASS IS THE TRANSLATION, AND THE TRANSLATION IS EXACT.
#
# Every point whose projection lands on that screen line lies on ONE plane
# through the camera. So the screen line is not an approximation of a 3D cut: it
# IS a 3D cut, seen from one place, and the plane is its preimage. Which means
# the world crack and the enemy's cross-section can be the same slash without
# anyone re-authoring the world effect in 3D — the world shader keeps drawing
# the line it always drew, and this hands the world the same fact as a plane.
#
# The cut is computed ONCE, at the instant the blade passes, and then it is
# frozen for the whole ceremony. It has to be: the camera takes three small
# impulses (the vacuum, the slash, the click) and a plane recomputed per frame
# would swing by degrees between them — so the enemy would be sliced along a
# plane that no longer matches the line on screen, which is exactly the
# "world cut diagonally, enemy cut at the waist" fault this exists to prevent.
#
# The impulses are 0.006-0.034 rad and the cut is taken after the first two have
# decayed (at 5.02s the draw's impulse is at e^-3.0 of its peak, ~0.07 degrees),
# so between the cut and the click the screen line is stationary to within a few
# millimetres at three metres. `iaido_execution_integration.gd` asserts that
# instead of trusting it.

## Plane normal, in world space. Unit length.
var normal := Vector3.UP
## `dot(p, normal) == offset` is the plane.
var offset := 0.0
## Where the blade was when the plane was taken (the camera). Kept so callers can
## express "which side is the near side" without re-deriving the view.
var eye := Vector3.ZERO
## The screen line this plane came from, so a caller can hand the same numbers
## back to the shader and prove they agree.
var center_uv := Vector2(0.5, 0.5)
var angle_degrees := 0.0


## A degenerate plane, for a ceremony that has not cut anything yet.
static func none() -> IaidoCutPlane:
	return IaidoCutPlane.new()


static func from_camera(camera: Camera3D, center: Vector2, angle_deg: float) -> IaidoCutPlane:
	var plane := IaidoCutPlane.new()
	if camera == null:
		return plane
	var viewport := camera.get_viewport()
	if viewport == null:
		return plane
	var size := viewport.get_visible_rect().size
	var dir := Vector2(cos(deg_to_rad(angle_deg)), sin(deg_to_rad(angle_deg)))
	var origin := camera.global_position
	# Two world points whose projections sit on the line. ANY two will do: the
	# plane through the eye and both of them is the same plane for every choice
	# of depth, which is the whole reason this works without a projection matrix.
	var a := camera.project_position((center - dir * 0.4) * size, 10.0)
	var b := camera.project_position((center + dir * 0.4) * size, 10.0)
	var n := (a - origin).cross(b - origin)
	if n.length_squared() < 0.000001:
		# Looking straight down the line: there is no plane to speak of. Fall back
		# to the camera's own forward-facing plane rather than emitting NaNs.
		n = camera.global_basis.z
	n = n.normalized()
	# ---- SIGN CONVENTION ---------------------------------------------------
	#
	# Which side is "positive" is not a mathematical fact, it is an interface,
	# and picking it wrong mirrors every cross-section in half of all camera
	# angles. So it is not derived, it is PROBED: step a little way toward the
	# uv-space normal of the line and check which side the plane thinks that is.
	#
	# uv space is y-down, so the normal of a line running along `dir` is
	# `(-dir.y, dir.x)`, and "positive" is defined to be the side that normal
	# points at. Everything downstream — the cross-section, the cut mark, the
	# debris — inherits the same orientation because this is the only place it is
	# decided.
	var normal_uv := Vector2(-dir.y, dir.x)
	var probe := camera.project_position((center + normal_uv * 0.1) * size, 10.0)
	if n.dot(probe - origin) < 0.0:
		n = -n
	plane.normal = n
	plane.offset = n.dot(origin)
	plane.eye = origin
	plane.center_uv = center
	plane.angle_degrees = angle_deg
	return plane


## Signed distance from the plane, in world metres. Positive is the side the
## line's uv normal points at.
func signed_distance(point: Vector3) -> float:
	return normal.dot(point) - offset


## The world direction the visible line runs in: the intersection of this plane
## with the plane of the screen, taken a little way in front of the camera.
func line_direction(camera: Camera3D) -> Vector3:
	if camera == null:
		return normal.cross(Vector3.UP).normalized()
	var view := -camera.global_basis.z
	var d := normal.cross(view)
	if d.length_squared() < 0.000001:
		d = normal.cross(camera.global_basis.y)
	return d.normalized()


## The in-plane direction perpendicular to the visible line. This is the axis a
## half topples about: rotating around it leans a piece ALONG the wound rather
## than along the screen, which is what a body losing half its support does.
func topple_axis(camera: Camera3D) -> Vector3:
	var along := line_direction(camera)
	var axis := normal.cross(along)
	if axis.length_squared() < 0.000001:
		return Vector3.RIGHT
	return axis.normalized()


## The plane, in the form the shader wants it: `xyz` normal, `w` offset.
func to_shader() -> Vector4:
	return Vector4(normal.x, normal.y, normal.z, offset)


## The same plane expressed in the object space of `xform`.
##
## The cleave shader measures its cut on `VERTEX`, i.e. in the piece's OWN space,
## and that is deliberate: a plane fixed in world space would keep eating a piece
## that has already fallen away from it, so a half would visually dissolve as it
## separated. Expressing the cut in the piece's own material space makes the cut
## surface travel with the piece, which is what a cut surface does.
func local_to(xform: Transform3D) -> Vector4:
	var n := xform.basis.transposed() * normal
	var w := offset - normal.dot(xform.origin)
	var scale := n.length()
	if scale < 0.000001:
		return Vector4(0.0, 1.0, 0.0, 0.0)
	return Vector4(n.x / scale, n.y / scale, n.z / scale, w / scale)


## The plane reduced to its screen line, for the alignment check.
##
## Returns `{ point: Vector2, angle: float }` in uv space, where `angle` is the
## line's angle with no direction (mod 180) because a cut has no arrowhead.
func screen_line(camera: Camera3D, depth := 6.0) -> Dictionary:
	if camera == null:
		return {"point": center_uv, "angle": angle_degrees}
	var size := camera.get_viewport().get_visible_rect().size
	var point := camera.project_position(center_uv * size, depth)
	var along := line_direction(camera)
	var a := camera.unproject_position(point)
	var b := camera.unproject_position(point + along)
	var delta := b - a
	return {
		"point": a / size,
		"angle": rad_to_deg(atan2(delta.y, delta.x)),
	}


## How far, in the plane, `point` sits from the line's own origin. Used to walk
## along the wound — placing a cut mark, spacing debris.
func along(point: Vector3, camera: Camera3D, from: Vector3) -> float:
	return (point - from).dot(line_direction(camera))


## True while a real cut exists.
func is_valid() -> bool:
	return normal.length_squared() > 0.5
