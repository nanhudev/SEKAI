extends Node3D
class_name PhantomChainRenderer
# DETERMINISTIC VISUAL CHAIN. No physics rope, no per-link nodes.
# Gameplay never reads this node — it only draws the rule.

const SHADER_PATH := "res://vfx/phantom_chain/phantom_chain.gdshader"

var profile: PhantomChainProfile

var _mmi: MultiMeshInstance3D
var _mm: MultiMesh
var _mat: ShaderMaterial
var _anchor: MeshInstance3D
var _debug: MeshInstance3D

var start := Vector3.ZERO
var end := Vector3.ZERO
var control := Vector3.ZERO
var has_control := false

var alpha := 0.40
var tension := 0.0
var thickness := 0.028
var color := Color(0.72, 0.80, 0.90, 1.0)
var link_spacing := 0.16
var spawn_progress := 1.0
var dissolve_progress := 0.0
var fade := 1.0
var flow := 0.0
var hit_flash := 0.0
var visible_links := 0
var debug_draw := false

var _curve := Curve3D.new()
var _float_seed := 0.0


func _ready() -> void:
	_float_seed = float(get_instance_id() % 97) * 0.137
	_build_mesh()
	set_chain_visible(false)


func configure(p: PhantomChainProfile) -> void:
	profile = p
	if p == null:
		return
	color = p.base_color
	alpha = p.travel_alpha
	thickness = p.link_thickness
	link_spacing = p.link_spacing
	if _mat != null:
		_mat.set_shader_parameter("base_color", color)


func set_endpoints(from: Vector3, to: Vector3, ctrl: Variant = null) -> void:
	start = from
	end = to
	if ctrl is Vector3:
		control = ctrl
		has_control = true
	else:
		has_control = false
	_rebuild_curve()


func set_chain_visible(on: bool) -> void:
	if _mmi != null:
		_mmi.visible = on
	if _anchor != null:
		_anchor.visible = on and spawn_progress > 0.15 and dissolve_progress < 0.85


func clear() -> void:
	spawn_progress = 0.0
	dissolve_progress = 1.0
	fade = 0.0
	tension = 0.0
	hit_flash = 0.0
	visible_links = 0
	if _mm != null:
		_mm.visible_instance_count = 0
	set_chain_visible(false)


func _build_mesh() -> void:
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_custom_data = true
	_mm.mesh = _make_broken_link_mesh()
	_mm.instance_count = 64
	_mm.visible_instance_count = 0

	_mmi = MultiMeshInstance3D.new()
	_mmi.name = "Links"
	_mmi.multimesh = _mm
	_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mmi)

	var shader := load(SHADER_PATH) as Shader
	_mat = ShaderMaterial.new()
	_mat.shader = shader
	_mat.set_shader_parameter("base_color", color)
	_mat.set_shader_parameter("alpha", alpha)
	_mat.render_priority = 1
	_mmi.material_override = _mat

	_anchor = MeshInstance3D.new()
	_anchor.name = "PhantomAnchor"
	var torus := TorusMesh.new()
	torus.inner_radius = 0.04
	torus.outer_radius = 0.09
	torus.rings = 12
	torus.ring_segments = 16
	_anchor.mesh = torus
	var am := StandardMaterial3D.new()
	am.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	am.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	am.albedo_color = Color(0.78, 0.88, 0.98, 0.45)
	am.emission_enabled = true
	am.emission = Color(0.55, 0.72, 0.95)
	am.emission_energy_multiplier = 0.6
	am.cull_mode = BaseMaterial3D.CULL_DISABLED
	_anchor.material_override = am
	_anchor.visible = false
	add_child(_anchor)

	_debug = MeshInstance3D.new()
	_debug.name = "DebugCurve"
	_debug.visible = false
	add_child(_debug)


func _make_broken_link_mesh() -> ArrayMesh:
	# Two incomplete arcs + a thin energy filament. Not a closed oval.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_arc_ring(st, 0.072, 0.016, 0.0, -0.55, 0.55, Color(1, 0.2, 0.5))
	_arc_ring(st, 0.072, 0.016, PI * 0.5, 0.55, 2.0 * PI - 0.55, Color(0.15, 0.8, 0.5))
	# Filament through the gap.
	_box(st, Vector3(0.003, 0.003, 0.09), Color(0.5, 0.5, 0.9))
	st.generate_normals()
	return st.commit()


func _arc_ring(
	st: SurfaceTool, radius: float, tube: float, yaw: float, a0: float, a1: float, col: Color
) -> void:
	var segs := 10
	for i in segs:
		var t0 := lerpf(a0, a1, float(i) / float(segs))
		var t1 := lerpf(a0, a1, float(i + 1) / float(segs))
		var c0 := Vector3(cos(t0) * radius, sin(t0) * radius, 0.0)
		var c1 := Vector3(cos(t1) * radius, sin(t1) * radius, 0.0)
		var basis := Basis(Vector3.FORWARD, yaw)
		c0 = basis * c0
		c1 = basis * c1
		var n0 := c0.normalized()
		var n1 := c1.normalized()
		var b0 := n0.cross(Vector3.FORWARD).normalized() * tube
		if b0.length_squared() < 0.00001:
			b0 = Vector3.UP * tube
		var b1 := n1.cross(Vector3.FORWARD).normalized() * tube
		if b1.length_squared() < 0.00001:
			b1 = Vector3.UP * tube
		_quad(st, c0 - b0, c0 + b0, c1 + b1, c1 - b0, col)


func _box(st: SurfaceTool, half: Vector3, col: Color) -> void:
	var p := [
		Vector3(-half.x, -half.y, -half.z), Vector3(half.x, -half.y, -half.z),
		Vector3(half.x, half.y, -half.z), Vector3(-half.x, half.y, -half.z),
		Vector3(-half.x, -half.y, half.z), Vector3(half.x, -half.y, half.z),
		Vector3(half.x, half.y, half.z), Vector3(-half.x, half.y, half.z),
	]
	var faces := [
		[0, 1, 2, 3], [5, 4, 7, 6], [4, 0, 3, 7],
		[1, 5, 6, 2], [3, 2, 6, 7], [4, 5, 1, 0],
	]
	for f in faces:
		_quad(st, p[f[0]], p[f[1]], p[f[2]], p[f[3]], col)


func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color) -> void:
	st.set_color(col)
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)
	st.set_color(col)
	st.add_vertex(a)
	st.add_vertex(c)
	st.add_vertex(d)


func _rebuild_curve() -> void:
	_curve.clear_points()
	if has_control:
		_curve.add_point(start)
		_curve.add_point(control)
		_curve.add_point(end)
	else:
		# Soft sag so a "straight" bind still reads as a rule-link, not a rod.
		var mid := start.lerp(end, 0.5)
		var sag := Vector3.DOWN * clampf(start.distance_to(end) * 0.06 * (1.0 - tension), 0.0, 0.55)
		_curve.add_point(start)
		_curve.add_point(mid + sag)
		_curve.add_point(end)


func refresh() -> void:
	_rebuild_curve()
	var length := _curve.get_baked_length()
	if length < 0.05:
		visible_links = 0
		_mm.visible_instance_count = 0
		set_chain_visible(false)
		return

	var spacing := maxf(0.08, link_spacing)
	var count := clampi(int(floor(length / spacing)) + 1, 2, profile.max_visible_links if profile else 42)
	visible_links = count
	_mm.visible_instance_count = count

	if _mat != null:
		_mat.set_shader_parameter("base_color", color)
		_mat.set_shader_parameter("alpha", alpha)
		_mat.set_shader_parameter("tension", tension)
		_mat.set_shader_parameter("fade", fade)
		_mat.set_shader_parameter("flow", flow)
		_mat.set_shader_parameter("hit_flash", hit_flash)
		_mat.set_shader_parameter("spawn_progress", spawn_progress)
		_mat.set_shader_parameter("dissolve_progress", dissolve_progress)
		_mat.set_shader_parameter("link_count", float(count))
		_mat.set_shader_parameter("edge_emission", 0.25 + tension * 0.55)

	var scale := thickness / 0.028
	for i in count:
		var d := float(i) / float(maxi(count - 1, 1)) * length
		var pos := _curve.sample_baked(d)
		var tangent := end - start
		var baked := _curve.sample_baked_with_rotation(d)
		if baked.basis.z.length_squared() > 0.0001:
			tangent = baked.basis.z
		if tangent.length_squared() < 0.0001:
			tangent = Vector3.FORWARD
		else:
			tangent = tangent.normalized()
		# Alternate 90° so it still reads as a chain without being forged iron.
		var twist := Basis(tangent, deg_to_rad(90.0 if (i % 2) == 0 else 0.0))
		var drift := Vector3(
			sin(_float_seed + float(i) * 1.7 + flow) * 0.012,
			cos(_float_seed * 0.7 + float(i) * 1.1) * 0.010,
			sin(_float_seed * 1.3 + float(i) * 0.9) * 0.008
		) * (1.0 - tension * 0.85)
		var up := Vector3.UP
		if absf(tangent.dot(up)) > 0.92:
			up = Vector3.RIGHT
		var basis := Basis.looking_at(tangent, up) * twist
		var xf := Transform3D(basis.scaled(Vector3.ONE * scale), pos + drift)
		_mm.set_instance_transform(i, xf)
		# r=variant, g=along, b=tension — read as INSTANCE_CUSTOM in the shader.
		_mm.set_instance_custom_data(
			i, Color(float(i % 2), float(i) / float(maxi(count - 1, 1)), tension, 1.0)
		)

	if _anchor != null:
		_anchor.global_position = end
		var am := _anchor.material_override as StandardMaterial3D
		if am != null:
			am.albedo_color.a = lerpf(0.25, 0.75, tension) * fade * spawn_progress * (1.0 - dissolve_progress)
		_anchor.visible = _mmi.visible and spawn_progress > 0.2 and dissolve_progress < 0.8

	set_chain_visible(fade > 0.02 and spawn_progress > 0.0 and dissolve_progress < 1.0)
	_update_debug()


func _update_debug() -> void:
	if _debug == null:
		return
	_debug.visible = debug_draw and fade > 0.01
	if not _debug.visible:
		return
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	var steps := 24
	var len := _curve.get_baked_length()
	for i in steps + 1:
		im.surface_set_color(Color(0.2, 1.0, 0.7, 0.9))
		im.surface_add_vertex(_curve.sample_baked(len * float(i) / float(steps)))
	im.surface_end()
	_debug.mesh = im
