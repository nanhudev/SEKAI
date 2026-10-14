extends StaticBody3D
# 居合桩 — THE IAIDO POST.
#
# The one thing in the training ground that 聚合斩 can CUT IN TWO for real, and the
# only target in the project that puts itself back together afterwards.
#
# WHY THE TRAINING GROUND NEEDED ONE
# Every other answer to "did the signature land" is indirect. An enemy is either
# killed (and then it is gone, and the next attempt starts from a walk back to the
# spawn) or a dummy that refuses to be cut, which proves the refusal and not the
# cut. Neither lets you do the thing a player actually wants to do with a finisher:
# do it again, twenty times, on the same object, and watch what changes. This post
# is that object. It splits, it falls over in real physics, and two and a half
# seconds later it is standing there again, whole.
#
# WHY THE HALVES ARE CONSTRUCTED RATHER THAN CUT
# 禁 runtime mesh boolean is a project rule, and it is a rule for a good reason:
# a boolean is a runtime dependency on a solver, it can fail on a degenerate input,
# and a training fixture is exactly the kind of object that gets handed a degenerate
# input. So nothing here is cut after the fact. The blade arrives on a PLANE, and a
# plane through a solid of revolution has an ANALYTIC intersection — at angle φ the
# surface sits at
#
#     y(φ) = ( w − n.x·r·cosφ − n.z·r·sinφ ) / n.y
#
# which is a sinusoid, i.e. an ellipse, which is exactly what a blade leaves on a
# round post. Both pieces are therefore built ALREADY cut, from the same two planes,
# and their cut faces are the same ellipse by construction rather than by luck. The
# two meshes mate flush at rest, which is also what makes the restore invisible.
#
# WHY THE CUT PLANE IS RECOVERED FROM THE CAMERA
# The director hands every target the same two vectors (`cut_normal`, `cut_line`)
# so that one fact can be drawn on the world and on a body without either
# re-deriving it — but a normal and a line direction describe a plane's ORIENTATION
# and not its PLACE, and a post cut at the ankles is a different picture from a post
# cut at the shoulder. It does not need a third vector: `IaidoCutPlane` is built
# from the camera and passes through the eye, so `w = n · eye` and the plane is
# fully determined. That is not a reconstruction, it is the definition, and it is
# why the cut lands at the height the player aimed at.

const TB := preload("res://scripts/training/training_build.gd")

## A post, not a pillar — and TALLER THAN THE PLAYER, which is a derived number and not
## a stylistic one.
##
## 聚合斩's cut plane is built from the camera and passes through the eye, and its screen
## line runs through the screen centre (`IaidoTuning.cut_center` = 0.5, 0.5). Work the
## intersection out and the two facts cancel: the plane contains the view axis, so it
## crosses the post's own axis at exactly the CAMERA'S HEIGHT. A 1.68 m post standing in
## front of a 1.5 m eye therefore loses a 18 cm cap — the blade passes over the top of it,
## and a fixture built to show a thing cut in half would show a thing decapitated.
## 2.30 m puts the wound at roughly the middle of the post for every stance the player
## can take, with the head and the feet both worth looking at.
const HEIGHT := 2.30
const BASE_RADIUS := 0.19
const TOP_RADIUS := 0.14
## Ring resolution. 40 is where the cut ellipse stops reading as a polygon: the chord
## error at r = 0.185 is 0.6 mm, an order of magnitude under the band a shader would
## draw on it anyway.
const SIDES := 40
## NEITHER PIECE MAY BE A SLIVER. A cut that removes a 4 cm cap is a cut that
## produces one object and some gravel, and the whole point is two things falling.
## It also keeps `create_convex_shape` away from a hull with no volume.
const MIN_PIECE := 0.30
## 自动复原. The user's ask was 静置约 2–3 秒, and the honest way to choose inside
## that window is to ask what the player is doing: shorter than the blade's own
## recovery and the post is whole again before the ceremony finishes, longer than
## about three seconds and the wait starts to be the thing you are waiting for.
const RECOVER_DELAY := 2.4
## The halves fly back rather than fading in. A fade would leave a ghost of two
## pieces overlapping the real one for a third of a second, and worse, it would hide
## the one fact this fixture is here to show: that the two faces are the SAME face.
const REFORM_TIME := 0.34
## The push the falling half gets. Sized so a 0.9 m piece of stone lands about a
## metre away inside the 0.43 s gravity gives it — far enough to read as "that came
## off", near enough that it is still in the same frame.
const TOPPLE_SPEED := 1.7
const TUMBLE := 4.5
## A struck post rings. ζ = 0.22 gives about three visible swings, which is one more
## than a stone should have and one fewer than a spring.
const WOBBLE_STIFF := 190.0
const WOBBLE_DAMP := 6.5
const WOBBLE_MAX := 0.12
## The severed half spawns this far above its seat. The two collision hulls are flush
## by construction — that is what makes the restore invisible — and flush is also the
## state a physics solver resolves by pushing. Four millimetres is under a pixel at
## any review distance and puts the falling half unambiguously above the base on its
## first step.
const SEAT_LIFT := 0.004

## The post has been cut in two. Read by tests and by anything that wants to know
## whether the fixture is currently an object or a picture of one.
signal cut_apart(height: float)
signal reformed

enum CutState { INTACT, CUT, REFORMING }

var health := 1.0
## How many times this post has come apart. A counter rather than a flag, because
## "it can be cut again" is the claim, and a flag cannot fail to be reset.
var cut_count := 0

var _state := CutState.INTACT
var _timer := 0.0
var _cut_height := 0.0
var _top: RigidBody3D = null
var _reform_from := Transform3D()
var _reform_to := Transform3D()
var _tilt := Vector2.ZERO
var _tilt_vel := Vector2.ZERO
var _shaft: MeshInstance3D
var _solid: CollisionShape3D


func _ready() -> void:
	# Two groups, two different readers. `hostiles` is how the signature's collector
	# finds a body it may cut at all (and how a chain sweep finds something to hit);
	# `training_fixture` is how a RESET finds the things that own their own recovery,
	# so adding a fourth fixture to this room is not an edit to the reset list.
	add_to_group("hostiles")
	add_to_group("training_fixture")
	_shaft = MeshInstance3D.new()
	_shaft.name = "Shaft"
	add_child(_shaft)
	_solid = CollisionShape3D.new()
	_solid.name = "Solid"
	add_child(_solid)
	# THE SUBSCRIPTION IS THE WHOLE CONTRACT. `build_for` builds a hurtbox and hands it
	# back; a hurtbox nothing is connected to still accepts hits, still reports them and
	# still does nothing — which is a post that a signature goes through without
	# leaving a mark, and the failure looks exactly like a post that was not reached.
	var hurtbox := CombatHurtbox.build_for(
		self, Vector3(BASE_RADIUS * 3.0, HEIGHT, BASE_RADIUS * 3.0), Vector3(0.0, HEIGHT * 0.5, 0.0)
	)
	hurtbox.hit_received.connect(_on_hit)
	_build_whole()


# ------------------------------------------------------------------------------
# The whole post
# ------------------------------------------------------------------------------

func _build_whole() -> void:
	# Both ends are the same "plane" — a horizontal one — so the full post and the
	# two halves come out of one generator. A second code path for the undamaged
	# shape is a second code path that can disagree with the first one.
	_shaft.mesh = _revolved(Vector3.UP, 0.0, Vector3.UP, HEIGHT,
		BASE_RADIUS, Vector3.DOWN, Vector3.UP, &"")
	var shape := _cylinder_shape(HEIGHT, _radius_at(HEIGHT * 0.5))
	_solid.shape = shape
	_solid.position = Vector3(0.0, HEIGHT * 0.5, 0.0)


func _cylinder_shape(height: float, radius: float) -> CylinderShape3D:
	var shape := CylinderShape3D.new()
	shape.height = height
	shape.radius = radius
	return shape


## Radius of the post at a height, in metres. Linear taper, and the linearity is not
## a convenience: it is what makes the plane's intersection a sinusoid and therefore
## the cut face an exact ellipse. A curved profile would put a transcendental
## equation between the blade and the cross-section.
func _radius_at(y: float) -> float:
	return BASE_RADIUS + (TOP_RADIUS - BASE_RADIUS) * clampf(y / HEIGHT, 0.0, 1.0)


# ------------------------------------------------------------------------------
# Being hit
# ------------------------------------------------------------------------------

func _on_hit(hit: Dictionary) -> void:
	# Both ends of this guard matter. INTACT-only means a second signature during the
	# two and a half seconds of debris does not re-cut a post that is already in two
	# pieces — and `health` is parked at zero for the same window, which is the
	# collector's own word for "not a target", so the director will not pick it in
	# the first place. The guard is the second line, not the first.
	if _state != CutState.INTACT:
		return
	if hit.get("iaido", false):
		_cut(hit)
		return
	_knock(hit)


## A struck post rings about its own base. The collision does not move with it, and
## that is deliberate: the post is socketed, so what a hit moves is the part above
## the ground, and a 7° tilt is under a third of the post's own radius in collision
## terms. Driving the real body would also make a training post a siege engine.
func _knock(hit: Dictionary) -> void:
	var source: Variant = hit.get("source")
	var dir := Vector3.ZERO
	if source is Node3D:
		dir = global_position - (source as Node3D).global_position
	dir.y = 0.0
	if dir.length_squared() < 0.0001:
		return
	dir = dir.normalized()
	var amount := clampf(float(hit.get("poise_damage", 12.0)) * 0.0035, 0.02, WOBBLE_MAX)
	# Leaning the top AWAY along `dir` is a rotation about `UP × dir`: +X pushes the
	# top toward −X under a positive z-rotation, and +Z toward +Z under a positive
	# x-rotation, so the two components carry opposite signs.
	_tilt += Vector2(-dir.x, dir.z) * amount
	_tilt = _tilt.limit_length(WOBBLE_MAX * 2.0)


# ------------------------------------------------------------------------------
# Being cut
# ------------------------------------------------------------------------------

func _cut(hit: Dictionary) -> void:
	var plane := _local_cut_plane(hit)
	if plane.is_empty():
		return
	var n: Vector3 = plane["normal"]
	var y_cut: float = plane["height"]

	_shaft.mesh = _revolved(Vector3.UP, 0.0, n, y_cut,
		_radius_at(y_cut), Vector3.DOWN, n, &"hi")
	# THE BASE'S COLLISION IS ITS OWN MESH, not a cylinder sized to it. A cylinder
	# stops at the axis height, so on a 30° cut it would either float a hand's width
	# above the visible stone on one side or be born inside the falling half on the
	# other. The hull cannot disagree with the picture it was built from.
	var lower_shape := _shaft.mesh.create_convex_shape()
	if lower_shape != null:
		_solid.shape = lower_shape
	else:
		_solid.shape = _cylinder_shape(HEIGHT * 0.5, _radius_at(y_cut))
	_solid.position = Vector3.ZERO

	_build_top_piece(n, y_cut, hit)
	_shaft.visible = true
	_cut_height = y_cut
	cut_count += 1
	_state = CutState.CUT
	_timer = RECOVER_DELAY
	_tilt = Vector2.ZERO
	_tilt_vel = Vector2.ZERO
	# NOT a death, a holiday. Health is the collector's target filter, so zero here
	# means "this body is not a valid target", and restoring it on reform is what
	# makes the post re-cuttable without any other system being told.
	health = 0.0
	cut_apart.emit(y_cut)


## The plane the blade arrived on, expressed in this node's own space, with the
## positive side forced UP so that "the top piece" is always the same piece.
##
## Returns `{normal, height}` in local metres, or an empty dictionary when there is
## nothing to cut on.
func _local_cut_plane(hit: Dictionary) -> Dictionary:
	var normal_v: Variant = hit.get("cut_normal")
	var n_world := Vector3.UP
	if normal_v is Vector3:
		n_world = normal_v as Vector3
	if n_world.length_squared() < 0.5:
		return {}
	n_world = n_world.normalized()

	# `w = n · eye`, because the plane was taken from the camera and passes through
	# it. See the header. When there is no camera (a headless test that only wants
	# the geometry) the plane is dropped through the post's own middle instead, which
	# is the honest degradation: a cut in a room with nobody in it has no height.
	var eye := Vector3.ZERO
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		eye = cam.global_position
	else:
		eye = global_position + Vector3.UP * (HEIGHT * 0.5)
	var w_world := n_world.dot(eye)

	var xform := global_transform
	var n_local := xform.basis.transposed() * n_world
	var scale := n_local.length()
	if scale < 0.000001:
		return {}
	n_local /= scale
	var w_local := (w_world - n_world.dot(xform.origin)) / scale
	if n_local.y < 0.0:
		n_local = -n_local
		w_local = -w_local

	if absf(n_local.y) < 0.25:
		# THE BLADE IS LYING ALONG THE POST'S AXIS, i.e. the cut is a lengthways
		# split rather than a chop. A plane with no y component does not cross the
		# axis at all, and there is no "upper piece" to hand to gravity — so rather
		# than invent a vertical split (two slivers, bad physics, and a mesh no
		# ellipse describes) the post is cut across at its own two thirds, which is
		# the most common thing a player does to a post and always a real cut.
		n_local = Vector3.UP
		w_local = HEIGHT * 0.66

	var y_cut := clampf(w_local / n_local.y, MIN_PIECE, HEIGHT - MIN_PIECE)
	return {"normal": n_local, "height": y_cut}


## How far, in metres, the plane's height varies around the post's own circumference
## at the radius the plane is evaluated at. Public because it is the one number that
## says whether a cut is a clean cross-section or a near-vertical slice.
func plane_spread(n: Vector3) -> float:
	if absf(n.y) < 0.0001:
		return 0.0
	return maxf(absf(n.x), absf(n.z)) * _radius_at(HEIGHT * 0.5) / absf(n.y)


func _build_top_piece(n: Vector3, y_cut: float, hit: Dictionary) -> void:
	if _top != null and is_instance_valid(_top):
		_top.queue_free()
	_top = RigidBody3D.new()
	_top.name = "TopPiece"
	var mesh: ArrayMesh = _revolved(n, y_cut, Vector3.UP, HEIGHT,
		_radius_at(y_cut), -n, Vector3.UP, &"lo")
	var view := MeshInstance3D.new()
	view.name = "Shell"
	# No `material_override` anywhere: the wound lives on surface 1 with its own
	# material, and an override would repaint it as weathered stone — which is the
	# one thing the cut face must not be.
	view.mesh = mesh
	add_child(_top)
	_top.add_child(view)
	# EXACT, NOT APPROXIMATE. The piece's mesh is convex — it is a cylinder with two
	# plane cuts and every one of its extreme vertices is on the side surface — so the
	# hull of those vertices IS the piece. A capsule or a box would let a half land on
	# a corner that is not there.
	var shape := CollisionShape3D.new()
	var hull := mesh.create_convex_shape()
	shape.shape = hull if hull != null else _cylinder_shape(HEIGHT - y_cut, _radius_at(y_cut))
	_top.add_child(shape)
	# SEAT LIFT. The two hulls are flush by construction — that is what makes the
	# restore invisible — and flush is also the state a solver resolves by pushing.
	# Four millimetres is under a pixel at any review distance and puts the falling
	# half unambiguously above the base on its first step.
	_top.global_transform = Transform3D(global_transform.basis, global_transform.origin + Vector3.UP * SEAT_LIFT)
	_top.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	_top.center_of_mass = Vector3(0.0, (y_cut + HEIGHT) * 0.5, 0.0)
	# A stone drum this size is about 55 kg if it is limestone; the number matters
	# because the piece has to be heavy enough to sit still after it lands and light
	# enough that the 1.7 m/s push moves it.
	_top.mass = 55.0
	var physics := PhysicsMaterial.new()
	physics.friction = 0.75
	physics.bounce = 0.06
	_top.physics_material_override = physics

	var push := _topple_direction(hit)
	_top.linear_velocity = push * TOPPLE_SPEED + Vector3.UP * 0.35
	# `UP × push` is the axis whose positive rotation carries the piece's top along
	# `push` — the same derivation the wobble uses, in the other direction, because
	# there the body moves and here it turns.
	_top.angular_velocity = Vector3.UP.cross(push).normalized() * TUMBLE


## Which way the severed half falls. The blade's own travel is the honest source: a
## post does not fall away from the player, it falls the way it was hit. Flattened,
## because the upward component of a slash has already been spent cutting.
func _topple_direction(hit: Dictionary) -> Vector3:
	var line_v: Variant = hit.get("cut_line")
	var dir := Vector3.ZERO
	if line_v is Vector3:
		dir = line_v as Vector3
	dir.y = 0.0
	if dir.length_squared() < 0.0001:
		var normal_v: Variant = hit.get("cut_normal")
		if normal_v is Vector3:
			dir = normal_v as Vector3
			dir.y = 0.0
	if dir.length_squared() < 0.0001:
		dir = Vector3.RIGHT
	return dir.normalized()


# ------------------------------------------------------------------------------
# Recovering
# ------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	_update_wobble(delta)
	match _state:
		CutState.CUT:
			_timer -= delta
			if _timer <= 0.0:
				_begin_reform()
		CutState.REFORMING:
			_timer -= delta
			var t := 1.0 - clampf(_timer / REFORM_TIME, 0.0, 1.0)
			if _top != null and is_instance_valid(_top):
				# Ease-in: the pieces sit where they landed for a beat and then snap
				# home, which is how a reset reads. A linear pull would start moving
				# them the instant the timer expired and the wait would feel longer
				# than it is.
				var e := t * t
				_top.global_transform = _reform_from.interpolate_with(_reform_to, e)
			if _timer <= 0.0:
				_finish_reform()
		_:
			pass


func _begin_reform() -> void:
	if _top == null or not is_instance_valid(_top):
		_finish_reform()
		return
	# FROZEN, NOT KINEMATIC. The piece is being posed, not simulated, and a kinematic
	# body would still shove anything it touched on the way home — which for the
	# last fraction of a metre is the base it belongs to.
	_top.freeze = true
	_top.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	_top.linear_velocity = Vector3.ZERO
	_top.angular_velocity = Vector3.ZERO
	_reform_from = _top.global_transform
	_reform_to = global_transform
	_state = CutState.REFORMING
	_timer = REFORM_TIME


func _finish_reform() -> void:
	if _top != null and is_instance_valid(_top):
		# HIDDEN NOW, FREED LATER, AND THE ORDER IS THE FIX. `queue_free` is deferred to
		# the end of the frame, so without the line above it the frame that first reports
		# INTACT still RENDERS the severed half lying against the post that replaced it.
		# The state and the picture disagreed by exactly one frame — and that is the frame
		# a still lands on when it is gated on the state, so the review sheet went out
		# with a post that was very nearly whole under a filename that said `reformed`.
		# Setting `visible` is immediate, which is what makes the two agree.
		_top.visible = false
		_top.queue_free()
	_top = null
	_build_whole()
	_cut_height = 0.0
	health = 1.0
	_state = CutState.INTACT
	reformed.emit()


## The RESET the training ground already has, pointed at this fixture.
##
## INSTANT, AND DELIBERATELY NOT THE TIMER'S PATH. The two routes are two different
## things and the difference is who asked. The timer is the fixture PERFORMING its own
## reassembly on a training ground where nothing is urgent, so it spends 0.34 s doing
## it and the pause is the point. A RESET is somebody asking the room to be back to a
## known state NOW — a room that is still animating a third of a second later is a room
## that is not back yet, and for a host that resets between takes it is a half-finished
## picture. It also means a caller can rely on the post being whole when this returns,
## which is the only reason a synchronous hook is worth having.
func reset_fixture() -> void:
	match _state:
		CutState.CUT, CutState.REFORMING:
			_timer = 0.0
			_finish_reform()
		_:
			_tilt = Vector2.ZERO
			_tilt_vel = Vector2.ZERO


func _update_wobble(delta: float) -> void:
	if _shaft == null:
		return
	if _state != CutState.INTACT:
		_shaft.rotation = Vector3.ZERO
		return
	_tilt_vel += (-WOBBLE_STIFF * _tilt - WOBBLE_DAMP * _tilt_vel) * delta
	_tilt += _tilt_vel * delta
	_shaft.rotation = Vector3(_tilt.y, 0.0, _tilt.x)


# ------------------------------------------------------------------------------
# Readings — for tests and for a review that wants numbers rather than a picture
# ------------------------------------------------------------------------------

func is_cut() -> bool:
	return _state != CutState.INTACT


func cut_height() -> float:
	return _cut_height


func top_piece() -> RigidBody3D:
	return _top


## The height of the post's main shaft RIGHT NOW, in metres — a READBACK, not the constant
## in the header.
##
## "The post is whole again" is a claim about what is on screen, and the two readings can
## disagree: the state flips to INTACT on the frame `_build_whole()` runs, and a harness
## that only asks `is_cut()` cannot tell a rebuilt 2.30 m shaft from a rebuilt one that
## never happened. Measuring the mesh it actually drew is the difference.
func shaft_height() -> float:
	if _shaft == null or _shaft.mesh == null:
		return 0.0
	return _shaft.get_aabb().size.y


## True while a severed half is STILL VISIBLE IN THE SCENE — asked of the children, and
## deliberately not of `_top`.
##
## `_top` is nulled the moment the reform finishes, but the node it named lives until the
## end of the frame because `queue_free` is deferred. A check written against `_top`
## therefore reports "no debris" for a frame in which debris is plainly on screen, which
## is precisely the bug it would have been written to catch. This one walks the tree.
func has_debris() -> bool:
	for child in get_children():
		if not String(child.name).begins_with("TopPiece"):
			continue
		var node := child as Node3D
		if node != null and node.visible:
			return true
	return false


## True while the severed half is a real body obeying gravity, i.e. the claim
## 真实物理切碎 as a state rather than an adjective.
func is_falling() -> bool:
	if _top == null or not is_instance_valid(_top):
		return false
	return not _top.freeze


func tilt() -> Vector2:
	return _tilt


# ------------------------------------------------------------------------------
# Geometry
# ------------------------------------------------------------------------------

## One solid of revolution, cut by a plane at each end.
##
## `lo_n/lo_w` and `hi_n/hi_w` are `dot(p, n) == w` planes in this node's own space,
## evaluated at the ring radius. `cap_lo`/`cap_hi` are the outward normals of the two
## end faces, or the zero vector to leave that end open (the post's base is in the
## ground, so its bottom cap is never visible).
##
## `cut_end` names which end is the blade's face — `&"cut"` gives that face its own
## surface and its own material, so the wound reads as fresh stone instead of as the
## outside of the post. NOTE that the cut surface carries no vertex the convex hull
## needs: every extreme point is on the side surface, which is why `create_convex_shape`
## can be called on a mesh whose cut face lives in surface 1.
func _revolved(
	lo_n: Vector3, lo_w: float, hi_n: Vector3, hi_w: float, r_ref: float,
	cap_lo: Vector3, cap_hi: Vector3, cut_end: StringName
) -> ArrayMesh:
	var lo := PackedVector3Array()
	var hi := PackedVector3Array()
	var slope := (TOP_RADIUS - BASE_RADIUS) / HEIGHT
	for i in SIDES + 1:
		var phi := TAU * float(i) / float(SIDES)
		var c := cos(phi)
		var s := sin(phi)
		var yl := _plane_height(lo_n, lo_w, r_ref, c, s)
		var yh := _plane_height(hi_n, hi_w, r_ref, c, s)
		yl = clampf(yl, 0.0, HEIGHT)
		yh = clampf(yh, 0.0, HEIGHT)
		lo.append(Vector3(c * _radius_at(yl), yl, s * _radius_at(yl)))
		hi.append(Vector3(c * _radius_at(yh), yh, s * _radius_at(yh)))

	var mesh := ArrayMesh.new()
	# ---- surface 0: the shell, which is what the collision is built from --------
	var shell := SurfaceTool.new()
	shell.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in SIDES:
		var j := i + 1
		var nl := Vector3(cos(TAU * float(i) / float(SIDES)), -slope,
			sin(TAU * float(i) / float(SIDES))).normalized()
		var nl2 := Vector3(cos(TAU * float(j) / float(SIDES)), -slope,
			sin(TAU * float(j) / float(SIDES))).normalized()
		var face := (nl + nl2).normalized()
		_tri(shell, lo[i], lo[j], hi[j], face, nl, nl2, nl2)
		_tri(shell, lo[i], hi[j], hi[i], face, nl, nl2, nl)
	var lo_centre := _centroid(lo)
	var hi_centre := _centroid(hi)
	if cap_lo.length_squared() > 0.5 and cut_end != &"lo":
		for i in SIDES:
			_tri(shell, lo_centre, lo[i + 1], lo[i], cap_lo, cap_lo, cap_lo, cap_lo)
	if cap_hi.length_squared() > 0.5 and cut_end != &"hi":
		for i in SIDES:
			_tri(shell, hi_centre, hi[i], hi[i + 1], cap_hi, cap_hi, cap_hi, cap_hi)
	mesh = shell.commit(mesh)
	mesh.surface_set_material(0, TB.material(TB.STONE_DARK))

	# ---- surface 1: the wound, when the blade made one -------------------------
	if cut_end == &"lo" and cap_lo.length_squared() > 0.5:
		mesh = _add_face(mesh, lo_centre, lo, cap_lo)
	elif cut_end == &"hi" and cap_hi.length_squared() > 0.5:
		mesh = _add_face(mesh, hi_centre, hi, cap_hi)
	return mesh


func _add_face(mesh: ArrayMesh, centre: Vector3, ring: PackedVector3Array, normal: Vector3) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in SIDES:
		_tri(st, centre, ring[i], ring[i + 1], normal, normal, normal, normal)
	var index := mesh.get_surface_count()
	mesh = st.commit(mesh)
	# Fresh stone is LIGHTER than weathered stone. Same reasoning as the training
	# construct's collar: the cut has to be visible against the thing it was made in,
	# and a wound the same colour as the outside is a wound nobody can find.
	mesh.surface_set_material(index, TB.material(TB.STONE_STRUCT, 0.55))
	return mesh


func _plane_height(n: Vector3, w: float, r: float, c: float, s: float) -> float:
	if absf(n.y) < 0.000001:
		return 0.0
	return (w - n.x * r * c - n.z * r * s) / n.y


func _centroid(ring: PackedVector3Array) -> Vector3:
	# The rings repeat their first vertex at the end, so the mean of the first SIDES
	# entries is the centre the fan needs — averaged over the RING and not over the
	# vertices of the ring, which for a cut ring sits at the ellipse's centre
	# automatically because a sinusoid's mean over a full turn is its constant term.
	var sum := Vector3.ZERO
	for i in SIDES:
		sum += ring[i]
	return sum / float(SIDES)


## FRONT FACES ARE CLOCKWISE IN GODOT, which makes a front-facing triangle's
## geometric normal the NEGATIVE of the right-hand cross product. Rather than reason
## that out once per surface — side, up-facing cap, down-facing cap, wound facing
## ±n — every triangle is emitted and then CHECKED against the normal it is supposed
## to have, and swapped if it disagrees. A wrong winding is the one mistake in a
## hand-written mesh that reads as correct in review and is obvious on screen, so it
## is made unable to happen instead of being got right.
func _tri(
	st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, face: Vector3,
	na: Vector3, nb: Vector3, nc: Vector3
) -> void:
	if (b - a).cross(c - a).dot(face) > 0.0:
		var swap := b
		b = c
		c = swap
		var swap_n := nb
		nb = nc
		nc = swap_n
	st.set_normal(na)
	st.add_vertex(a)
	st.set_normal(nb)
	st.add_vertex(b)
	st.set_normal(nc)
	st.add_vertex(c)
