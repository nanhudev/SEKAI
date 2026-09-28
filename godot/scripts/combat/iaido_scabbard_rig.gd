extends MeshInstance3D
class_name IaidoScabbardRig

# ---------------------------------------------------------------------------
# C2B_IAIDO_SCABBARD_STANDIN
#
# A STRUCTURALLY FAITHFUL stand-in for `C2B-05-IAIDO-SCABBARD`, which has been
# filed with the ART pipeline. It is not the final art. It exists so the
# ceremony's second half — the blade going home — can be built and verified
# against real geometry now:
#
#   * a closed, opaque tube, so the portion of the blade that is inside is
#     hidden by the scabbard's own walls rather than by a `visible = false`;
#   * a mouth with real wall thickness and a recessed lip, so the koiguchi reads
#     as a hole at the exact point every reverse-wave converges on;
#   * a taper and a kojiri, so it is not a pipe;
#   * the fittings the brief calls for, in the materials the brief calls for.
#
# It is built to the numbers in the brief, so replacing it with the GLB is a
# geometry-only swap with no runtime change.
#
# LOCAL FRAME (the contract the director relies on):
#   origin    the centre of the koiguchi mouth plane
#   +Y        down the bore, toward the kojiri — the direction the blade travels
#   -X        the side the cutting edge faces
#   +Z        the outward-facing side of the body (the kurikata side)
# ---------------------------------------------------------------------------

# --- the brief's numbers, in metres ---------------------------------------
@export var mouth_outer := Vector2(0.0575, 0.0390)   # 0.115 x 0.078 overall
@export var mouth_bore := Vector2(0.0460, 0.0275)    # 0.092 x 0.055 opening
@export var bore_depth := 1.00                       # the blade seats to y=0.95
@export var body_length := 1.02                      # origin -> kojiri
@export var taper := 0.88                            # size at the kojiri
@export var rings := 24
@export var body_segments := 12
@export var bore_segments := 6
@export var collar_length := 0.055
@export var collar_swell := 1.055

# --- palette: deep lacquer, dark iron, restrained ---------------------------
const LACQUER := Color(0.052, 0.043, 0.040)
const FITTING := Color(0.148, 0.132, 0.108)
const BORE_DARK := Color(0.014, 0.013, 0.016)
const CORD := Color(0.086, 0.070, 0.062)


func _ready() -> void:
	if mesh == null:
		build()


func build() -> void:
	mesh = _build_mesh()


func _build_mesh() -> ArrayMesh:
	var out := ArrayMesh.new()
	var st := SurfaceTool.new()

	var lacquer := _lacquer()
	st.clear()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_body(st)
	st.set_material(lacquer)
	st.commit(out)

	var bore := _bore()
	st.clear()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_bore_walls(st)
	st.set_material(bore)
	st.commit(out)

	var metal := _metal()
	st.clear()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_fittings(st)
	st.set_material(metal)
	st.commit(out)

	var cord := _cord()
	st.clear()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_sageo(st)
	st.set_material(cord)
	st.commit(out)

	return out


# --- materials --------------------------------------------------------------
# Every material is double sided on purpose. A scabbard is a tube: the near
# wall has to occlude the blade inside it, and the far wall's interior has to be
# visible through the mouth. With backface culling on, one of those two
# disappears and the mouth either reads as solid or as see-through.

func _base(colour: Color, rough: float, metal: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = colour
	mat.roughness = rough
	mat.metallic = metal
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
	return mat


func _lacquer() -> StandardMaterial3D:
	# Satin, not gloss: a mirror saya throws a long specular streak across the
	# lower frame and drags the eye off the mouth.
	return _base(LACQUER, 0.46, 0.04)


func _bore() -> StandardMaterial3D:
	# Non-reflective on purpose. Sharing the body material makes the inside of
	# the tube catch the same highlight and the hole looks filled in.
	return _base(BORE_DARK, 0.88, 0.0)


func _metal() -> StandardMaterial3D:
	return _base(FITTING, 0.34, 0.72)


func _cord() -> StandardMaterial3D:
	return _base(CORD, 0.92, 0.0)


# --- geometry helpers -------------------------------------------------------

func _profile(t: float) -> float:
	# t is 0 at the mouth and 1 at the kojiri.
	return 1.0 - (1.0 - taper) * pow(clampf(t, 0.0, 1.0), 0.85)


func _oval(y: float, angle: float, radius: Vector2) -> Vector3:
	return Vector3(radius.x * cos(angle), y, radius.y * sin(angle))


func _outer_radius(y: float) -> Vector2:
	return mouth_outer * _profile(y / maxf(body_length, 0.001))


func _bore_radius(y: float) -> Vector2:
	# The bore tapers with the body but stays clear of the blade everywhere.
	return mouth_bore * lerpf(1.0, 0.94, clampf(y / maxf(bore_depth, 0.001), 0.0, 1.0))


func _outward(angle: float, radius: Vector2) -> Vector3:
	# Exact ellipse normal for (rx cos a, rz sin a).
	return Vector3(cos(angle) / maxf(radius.x, 1e-5), 0.0, sin(angle) / maxf(radius.y, 1e-5)).normalized()


func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, na: Vector3, nb: Vector3, nc: Vector3, nd: Vector3) -> void:
	st.set_normal(na)
	st.add_vertex(a)
	st.set_normal(nb)
	st.add_vertex(b)
	st.set_normal(nc)
	st.add_vertex(c)

	st.set_normal(na)
	st.add_vertex(a)
	st.set_normal(nc)
	st.add_vertex(c)
	st.set_normal(nd)
	st.add_vertex(d)


func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, na: Vector3, nb: Vector3, nc: Vector3) -> void:
	st.set_normal(na)
	st.add_vertex(a)
	st.set_normal(nb)
	st.add_vertex(b)
	st.set_normal(nc)
	st.add_vertex(c)


# --- surfaces ---------------------------------------------------------------

func _body(st: SurfaceTool) -> void:
	var last := body_segments
	for s in last:
		var y0 := body_length * float(s) / float(last)
		var y1 := body_length * float(s + 1) / float(last)
		var r0 := _outer_radius(y0)
		var r1 := _outer_radius(y1)
		for i in rings:
			var a0 := TAU * float(i) / float(rings)
			var a1 := TAU * float(i + 1) / float(rings)
			_quad(
				st,
				_oval(y0, a0, r0), _oval(y1, a0, r1), _oval(y1, a1, r1), _oval(y0, a1, r0),
				_outward(a0, r0), _outward(a0, r1), _outward(a1, r1), _outward(a1, r0)
			)
	# Kojiri: dome the end rather than cutting the tube off flat.
	var r_end := _outer_radius(body_length)
	var steps := 4
	for s in steps:
		var u0 := float(s) / float(steps)
		var u1 := float(s + 1) / float(steps)
		var k0 := sqrt(maxf(1.0 - u0 * u0, 0.0))
		var k1 := sqrt(maxf(1.0 - u1 * u1, 0.0))
		var y0 := body_length + 0.030 * u0
		var y1 := body_length + 0.030 * u1
		for i in rings:
			var a0 := TAU * float(i) / float(rings)
			var a1 := TAU * float(i + 1) / float(rings)
			_quad(
				st,
				_oval(y0, a0, r_end * k0), _oval(y1, a0, r_end * k1),
				_oval(y1, a1, r_end * k1), _oval(y0, a1, r_end * k0),
				_outward(a0, r_end) * k0 + Vector3.UP * u0,
				_outward(a0, r_end) * k1 + Vector3.UP * u1,
				_outward(a1, r_end) * k1 + Vector3.UP * u1,
				_outward(a1, r_end) * k0 + Vector3.UP * u0
			)


func _bore_walls(st: SurfaceTool) -> void:
	# The whole bore, at low resolution. Only the first few centimetres are ever
	# on screen, but the blade is inside the rest of it and the walls are what
	# hide the blade, so they have to exist.
	for s in bore_segments:
		var y0 := bore_depth * float(s) / float(bore_segments)
		var y1 := bore_depth * float(s + 1) / float(bore_segments)
		var r0 := _bore_radius(y0)
		var r1 := _bore_radius(y1)
		for i in rings:
			var a0 := TAU * float(i) / float(rings)
			var a1 := TAU * float(i + 1) / float(rings)
			var n0 := -_outward(a0, r0)
			var n1 := -_outward(a0, r1)
			var n2 := -_outward(a1, r1)
			var n3 := -_outward(a1, r0)
			_quad(
				st,
				_oval(y0, a0, r0), _oval(y0, a1, r0), _oval(y1, a1, r1), _oval(y1, a0, r1),
				n0, n3, n2, n1
			)


func _fittings(st: SurfaceTool) -> void:
	# 1. The mouth ring: the annular face the blade passes through. This is the
	#    wall thickness, and without it the mouth reads as a painted ellipse.
	for i in rings:
		var a0 := TAU * float(i) / float(rings)
		var a1 := TAU * float(i + 1) / float(rings)
		var o0 := _oval(0.0, a0, mouth_outer)
		var o1 := _oval(0.0, a1, mouth_outer)
		var b0 := _oval(-0.006, a0, mouth_bore)
		var b1 := _oval(-0.006, a1, mouth_bore)
		_quad(st, o0, b0, b1, o1, Vector3.DOWN, Vector3.DOWN, Vector3.DOWN, Vector3.DOWN)

	# 2. The collar: a raised band wrapping the mouth, the one place on the
	#    object that is allowed to catch a highlight.
	var r_lo := mouth_outer * collar_swell
	for s in 3:
		var t0 := collar_length * float(s) / 3.0
		var t1 := collar_length * float(s + 1) / 3.0
		var k0 := 1.0 - 0.16 * pow(float(s) / 3.0, 1.4)
		var k1 := 1.0 - 0.16 * pow(float(s + 1) / 3.0, 1.4)
		for i in rings:
			var a0 := TAU * float(i) / float(rings)
			var a1 := TAU * float(i + 1) / float(rings)
			var p0 := r_lo * k0
			var p1 := r_lo * k1
			_quad(
				st,
				_oval(t0, a0, p0), _oval(t1, a0, p1), _oval(t1, a1, p1), _oval(t0, a1, p0),
				_outward(a0, p0), _outward(a0, p1), _outward(a1, p1), _outward(a1, p0)
			)
	# The collar's forward lip, so it is a band with an edge and not a decal.
	for i in rings:
		var a0 := TAU * float(i) / float(rings)
		var a1 := TAU * float(i + 1) / float(rings)
		var outer := mouth_outer
		var inner := mouth_outer * collar_swell
		_quad(
			st,
			_oval(0.0, a0, inner), _oval(0.0, a1, inner), _oval(0.0, a1, outer), _oval(0.0, a0, outer),
			Vector3.FORWARD, Vector3.FORWARD, Vector3.FORWARD, Vector3.FORWARD
		)

	# 3. The kurikata: the cord knob, on +Z where the brief puts it.
	_box(st, Vector3(0.030, 0.052, 0.020), Vector3(0.0, 0.185, _outer_radius(0.185).y + 0.010))


func _box(st: SurfaceTool, size: Vector3, centre: Vector3) -> void:
	var h := size * 0.5
	var p := [
		centre + Vector3(-h.x, -h.y, -h.z), centre + Vector3(h.x, -h.y, -h.z),
		centre + Vector3(h.x, h.y, -h.z), centre + Vector3(-h.x, h.y, -h.z),
		centre + Vector3(-h.x, -h.y, h.z), centre + Vector3(h.x, -h.y, h.z),
		centre + Vector3(h.x, h.y, h.z), centre + Vector3(-h.x, h.y, h.z),
	]
	var n := [
		Vector3(0, 0, -1), Vector3(0, 0, 1), Vector3(-1, 0, 0),
		Vector3(1, 0, 0), Vector3(0, -1, 0), Vector3(0, 1, 0),
	]
	var faces := [
		[0, 1, 2, 3, 0], [5, 4, 7, 6, 1], [4, 0, 3, 7, 2],
		[1, 5, 6, 2, 3], [4, 5, 1, 0, 4], [3, 2, 6, 7, 5],
	]
	for f in faces:
		var nrm: Vector3 = n[f[4]]
		_quad(st, p[f[0]], p[f[1]], p[f[2]], p[f[3]], nrm, nrm, nrm, nrm)


func _sageo(st: SurfaceTool) -> void:
	# One short hanging loop through the kurikata. Flat braid, no knot
	# sculpture and no tassel: the brief rejects ornament here.
	var knob := Vector3(0.0, 0.185, _outer_radius(0.185).y + 0.020)
	var major := 0.032
	var minor := 0.0046
	var centre := knob + Vector3(0.0, -major * 0.92, 0.0)
	var seg := 18
	var tube := 6
	for i in seg:
		var a0 := TAU * float(i) / float(seg)
		var a1 := TAU * float(i + 1) / float(seg)
		for j in tube:
			var b0 := TAU * float(j) / float(tube)
			var b1 := TAU * float(j + 1) / float(tube)
			_quad(
				st,
				_torus(centre, major, minor, a0, b0), _torus(centre, major, minor, a0, b1),
				_torus(centre, major, minor, a1, b1), _torus(centre, major, minor, a1, b0),
				_torus_normal(a0, b0), _torus_normal(a0, b1),
				_torus_normal(a1, b1), _torus_normal(a1, b0)
			)


# The loop hangs in the local YZ plane, so it falls away from the body instead
# of sticking out sideways past the silhouette.
func _torus(centre: Vector3, major: float, minor: float, a: float, b: float) -> Vector3:
	var ring := major + minor * cos(b)
	return centre + Vector3(0.0, ring * cos(a), ring * sin(a))


func _torus_normal(a: float, b: float) -> Vector3:
	return Vector3(0.0, cos(b) * cos(a), cos(b) * sin(a)).normalized()
