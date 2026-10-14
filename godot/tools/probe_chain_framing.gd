extends SceneTree
#
# PROBE · 缚星链 FRAMING — where the weapon's parts actually LAND IN THE FIRST-PERSON
# FRAME, in pixels, at 1280x720.
#
# WHY THIS EXISTS. Every part of this weapon is parented to CAMERA SPACE (the handle
# rides `CameraRig/.../WeaponRoot/ChainHandAnchor`, and the held bundle rides the
# handle). That has a consequence nobody can reason their way out of on paper: the
# LOOK PITCH DOES NOT MOVE THE WEAPON IN THE FRAME. Pitching down swings the world up
# behind a weapon that stays nailed to the same two-dimensional spot, so "it is cut
# off at the bottom, look down a bit" is not a fix — it is a no-op.
#
# Which means the only two questions that matter about the held weapon are:
#
#   1  WHERE is it in the frame, in pixels?
#   2  HOW BIG is it, in pixels?
#
# and both are arithmetic over the hand anchor, the camera's FOV and the viewport
# size. That arithmetic is easy to get wrong by hand — the first V4 review frame was
# read as "the bundle is a blob near the centre" when the bundle is in fact a cluster
# in the bottom-right corner and the blob near the centre is the TRIDENT seen end-on —
# so it is measured here instead of eyeballed.
#
# The projection is computed HERE rather than with `Camera3D.unproject_position`,
# because that one asks the viewport for its size and a headless run has none. The
# camera's `fov` is vertical (Godot's default `keep_aspect` is KEEP_HEIGHT), so the
# conversion is two divisions and a tangent — and it is the same number the renderer
# would produce at 1280x720.
#
# This is a developer probe, not a test: it asserts nothing and never fails.
#
# Usage:
#   godot --headless --path godot --script res://tools/probe_chain_framing.gd

const VIEW := Vector2(1280.0, 720.0)
const LAB_STAND := Vector3(0.0, 0.9, -33.0)

var world: Node3D
var player: CharacterBody3D
var chain: ChainDirector
var weapon: WeaponSlot
var visual: ChainVisual
var camera: Camera3D
var hand: Node3D


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	world = (load("res://scenes/combat/CombatSandbox.tscn") as PackedScene).instantiate()
	root.add_child(world)
	await _wait(12)
	player = world.get_node("Player")
	chain = player.get_node("ChainDirector")
	weapon = player.get_node("WeaponSlot")
	visual = chain.chain_visual
	camera = player.get_node("CameraRig/LookPivot/MotionPivot/ShakePivot/Camera3D") as Camera3D
	hand = player.get_node("CameraRig/LookPivot/MotionPivot/ShakePivot/WeaponRoot/ChainHandAnchor")

	weapon.equip(WeaponSlot.CHAIN)
	player.global_position = LAB_STAND
	player.rotation = Vector3.ZERO
	(player.get_node("CameraRig/LookPivot") as Node3D).rotation.x = 0.0
	chain.reset()
	await _wait(24)

	print("")
	print("缚星链 · FIRST-PERSON FRAMING PROBE   frame %d x %d   camera fov %.1f (vertical)"
		% [int(VIEW.x), int(VIEW.y), camera.fov])
	print("  the camera is pitched %+.1f°; note it cannot move ANY camera-space part in the frame"
		% rad_to_deg((player.get_node("CameraRig/LookPivot") as Node3D).rotation.x))
	print("  hand anchor (camera space) %s" % _v3(hand.position))
	print("  eye (world)                %s" % _v3(camera.global_position))
	print("")
	print("  %-26s %8s %8s %8s  %6s %6s  %-5s %7s"
		% ["part", "x", "y", "z", "px", "py", "in", "diam px"])
	print("  " + "-".repeat(88))

	_row("chain hand anchor", hand.global_position, 0.0)
	var handle := hand.get_node_or_null("ChainHandleVisual") as Node3D
	var coils: Node3D = null
	if handle != null:
		_row("handle root", handle.global_position, 0.062)
		_row("  grip top", handle.global_position + handle.global_basis.y * 0.108, 0.034)
		_row("  hand stop", handle.global_position + handle.global_basis.y * -0.098, 0.046)
		_row("  end cap", handle.global_position + handle.global_basis.y * -0.120, 0.041)
		_row("  pommel", handle.global_position + handle.global_basis.y * -0.142, 0.021)
		coils = handle.get_node_or_null("HeldStow") as Node3D
	if coils == null:
		coils = visual.get_node_or_null("HeldStow") as Node3D
	if coils != null:
		print("  bundle root parent  = %s" % coils.get_parent().name)
		_row("bundle root", coils.global_position, 0.0)

	var head := visual.get_node_or_null("TerminalHead") as Node3D
	if head != null:
		_row("TerminalHead", head.global_position, 0.19)
		_row("  blade tip", head.global_position - head.global_basis.z * 0.34, 0.0)

	if coils != null:
		print("")
		print("  %-26s %8s %8s %8s  %6s %6s  %-5s"
			% ["bundle turn", "x", "y", "z", "px", "py", "in"])
		print("  " + "-".repeat(88))
		# The turn NODES all sit on the bundle root — the links live in each turn's baked
		# MESH, not in its transform — so a turn's position has to be read off its own
		# `mesh.get_aabb()`. `VisualInstance3D.get_aabb()` would be the obvious call and
		# is the wrong one: the renderer fills it in, and a headless run fills in
		# nothing, so the same probe would read 0 x 0 x 0 here and a real box in a window.
		var union := AABB()
		var have := false
		for turn in visual.coil_loops():
			var box := turn.global_transform * (turn.mesh as ArrayMesh).get_aabb()
			_row("turn %-20s" % turn.name, box.get_center(), box.size.length() * 0.5)
			if turn.visible:
				if not have:
					union = box
					have = true
				else:
					var lo := union.position.min(box.position)
					var hi := (union.position + union.size).max(box.position + box.size)
					union = AABB(lo, hi - lo)
		if have:
			var centre := union.get_center()
			print("  visible bundle  %.3f x %.3f x %.3f m  centre %s  (≈%.0f x %.0f px)"
				% [
					union.size.x, union.size.y, union.size.z, _v3(centre),
					_pixels(union.size.x * 0.5, centre) * 2.0,
					_pixels(union.size.y * 0.5, centre) * 2.0,
				])

	print("")
	print("  layers drawn %d of %d · links drawn %d · rig %d"
		% [visual.coils(), visual.coil_loops().size(), visual.links_drawn(), visual.rig])
	# §STOW SAFE ZONE — the user's rule 余链永远不能出现在准星周围, as two numbers. This is
	# the reading `chain_v4_slice` turns into a pass/fail; here it is reported so a
	# framing change can be judged before anything is rendered.
	var ndc := visual.stow_links_ndc(camera, VIEW)
	print("")
	if ndc.is_empty():
		print("  SAFE ZONE  no stow link is drawn, so there is nothing to place")
	else:
		var lo := ndc[0]
		var hi := ndc[0]
		var nearest := 999.0
		for p in ndc:
			lo = lo.min(p)
			hi = hi.max(p)
			nearest = minf(nearest, maxf(absf(p.x), absf(p.y)))
		print("  SAFE ZONE  band ±%.2f NDC · nearest drawn link %.3f · clearance %+.3f · breach %.3f"
			% [
				ChainVisual.SAFE_HALF, nearest,
				visual.stow_margin(camera, VIEW), visual.stow_breach(camera, VIEW),
			])
		print("  stow NDC   x %.3f .. %.3f   y %.3f .. %.3f   (%d links drawn)"
			% [lo.x, hi.x, lo.y, hi.y, ndc.size()])
		_report_stow_layers(visual)
	_report_layers(hand)
	print("")
	# A SceneTree script that stops producing frames without quitting hangs the process
	# until it is killed — the probe has nothing left to wait for, so it ends itself.
	quit()


## Per-layer NDC, from each arc's baked mesh AABB. The AABB is CONSERVATIVE — its corners
## sit outside the curve — so "CLIPPED" here is a warning about margin and not proof that
## a link is off screen. Layers are listed innermost first, which is the order the rope is
## laid in and the order `_place_coils` sheds them in.
func _report_stow_layers(visual: ChainVisual) -> void:
	print("")
	print("  %-8s %8s %8s %8s %8s  %s" % ["layer", "nx min", "nx max", "ny min", "ny max", "frame"])
	for arc in visual.coil_loops():
		var mesh := arc.mesh as ArrayMesh
		if mesh == null:
			continue
		# THE CENTRE-LINE, not the mesh AABB. This table's first version used each arc's
		# baked `get_aabb()`, and for a 200° arc that LOCAL box is most of the disc — the
		# transform then inflates it again, so every layer came back CLIPPED and the whole
		# column meant nothing. The seams are where the links actually are.
		var seams: Array = visual.get("_stow_seams")
		var cuts: PackedInt32Array = visual.get("_arc_cuts")
		var xf := arc.global_transform
		var nlo := Vector2(999.0, 999.0)
		var nhi := Vector2(-999.0, -999.0)
		var seen := false
		var index := visual.coil_loops().find(arc)
		var a := cuts[index] if index < cuts.size() else 0
		var b := cuts[index + 1] if index + 1 < cuts.size() else seams.size()
		for i in range(a, mini(b, seams.size())):
			var sv: Vector3 = seams[i]
			var nd := _ndc(xf * sv)
			if is_nan(nd.x):
				continue
			seen = true
			nlo = nlo.min(nd)
			nhi = nhi.max(nd)
		if not seen:
			print("  %-8s %s" % [arc.name, "behind the lens"])
			continue
		var fits := nhi.x <= 1.0 and nlo.x >= -1.0 and nhi.y <= 1.0 and nlo.y >= -1.0
		print("  %-8s %8.3f %8.3f %8.3f %8.3f  %-8s visible=%s  seams %d..%d"
			% [
				arc.name, nlo.x, nhi.x, nlo.y, nhi.y,
				"yes" if fits else "CLIPPED", str(arc.visible), a, b - 1,
			])


## World point → NDC. `Vector2(NAN, NAN)` at or behind the lens.
func _ndc(world_point: Vector3) -> Vector2:
	var local := camera.global_transform.affine_inverse() * world_point
	if local.z >= -0.02:
		return Vector2(NAN, NAN)
	var half := tan(deg_to_rad(camera.fov * 0.5))
	var aspect := VIEW.x / VIEW.y
	return Vector2(local.x / (-local.z * half * aspect), local.y / (-local.z * half))


func _row(label: String, world_point: Vector3, radius: float) -> void:
	var p := _project(world_point)
	var diam := "—" if radius <= 0.0 else "%.0f" % (_pixels(radius, world_point) * 2.0)
	print("  %-26s %8.3f %8.3f %8.3f  %6.0f %6.0f  %-5s %7s"
		% [label, world_point.x, world_point.y, world_point.z, p.x, p.y, _inside(p, true), diam])


## World point → pixel, using the camera's own basis and its vertical FOV. `Vector2(-1, -1)`
## is returned for anything at or behind the lens, which is a real answer for a weapon
## held 62cm from the eye.
func _project(world_point: Vector3) -> Vector2:
	var local := camera.global_transform.affine_inverse() * world_point
	if local.z >= -0.02:
		return Vector2(-1.0, -1.0)
	var half := tan(deg_to_rad(camera.fov * 0.5))
	var aspect := VIEW.x / VIEW.y
	var nx := local.x / (-local.z * half * aspect)
	var ny := local.y / (-local.z * half)
	return Vector2((nx * 0.5 + 0.5) * VIEW.x, (0.5 - ny * 0.5) * VIEW.y)


func _inside(p: Vector2, visible: bool) -> String:
	if not visible:
		return "hid"
	if p.x < 0.0 or p.y < 0.0 or p.x > VIEW.x or p.y > VIEW.y:
		return "OFF"
	return "yes"


## How many pixels a sphere of `radius` metres at `world_point` spans.
func _pixels(radius: float, world_point: Vector3) -> float:
	var depth := camera.global_position.distance_to(world_point)
	if depth < 0.05:
		return 0.0
	return radius / (depth * tan(deg_to_rad(camera.fov * 0.5))) * VIEW.y


func _v3(v: Vector3) -> String:
	return "(%.3f, %.3f, %.3f)" % [v.x, v.y, v.z]


# WHICH CAMERA DRAWS WHAT, AND WITH WHICH LIGHT.
#
# The held weapon is composited through `ForegroundWeaponLayer`, which moves meshes
# onto its own render layer and draws them from a SubViewport with `own_world_3d`.
# That makes "why is this part dark" a question about a different world, and the
# first V4 review frame spent an hour answering it by eye. So it is read here: the
# layer each part is actually on, whether the private world has an environment and a
# sun, and whether the copy the layer made still points at a live node.
const WEAPON_LAYER_MASK := 1 << 19


func _report_layers(hand: Node3D) -> void:
	var layer := world.get_node_or_null("ForegroundWeaponLayer")
	print("")
	print("  foreground layer  %s" % ("missing" if layer == null else "present"))
	if layer == null:
		return
	var vp: SubViewport = layer.get("viewport")
	var copied: Dictionary = layer.get("copies")
	# A headless run has no rendering server, so the SubViewport has no World3D at all.
	# Reported as "n/a" rather than as a missing environment, because the two look the
	# same and only one of them is a bug.
	var env := "n/a"
	var size := "n/a"
	if vp != null:
		size = str(vp.size)
		var w: World3D = vp.world_3d
		env = "no world (headless)" if w == null else str(w.environment != null)
	print("  viewport          own_world=%s  environment=%s  size=%s"
		% [str(vp.own_world_3d) if vp != null else "?", env, size])
	print("  sun copied        %s" % str(layer.get("_sun_copy") != null))
	print("  copies held       %d" % copied.size())
	_report_bundle_mesh()
	print("")
	print("  %-26s %10s %10s %s" % ["part", "layers", "on weapon?", "copied"])
	print("  " + "-".repeat(72))
	var handle := hand.get_node_or_null("ChainHandleVisual") as Node3D
	if handle != null:
		var handle_mesh := _first_mesh(handle)
		if handle_mesh != null:
			_layer_row("handle, first mesh", handle_mesh, copied)
	# The bundle is a GRANDCHILD — `ChainHandleVisual/HeldStow/ArcNN` — so it is read
	# from `coil_loops()` rather than by walking the handle's children, which is the bug
	# the first version of this probe had and reported as "the turns are missing".
	for turn in visual.coil_loops():
		_layer_row("  " + String(turn.name), turn, copied)
	# The thrown rope's own links, which are NOT under WeaponRoot — the control case.
	var links: MeshInstance3D = visual.get_node_or_null("Links") as MeshInstance3D
	if links != null:
		_layer_row("drawn rope links", links, copied)


func _layer_row(label: String, node: MeshInstance3D, copied: Dictionary) -> void:
	var on_weapon := (node.layers & WEAPON_LAYER_MASK) != 0
	var has := copied.has(node) and is_instance_valid(copied[node])
	print("  %-26s %10d %10s %s" % [label, node.layers, str(on_weapon), str(has)])


func _first_mesh(node: Node) -> MeshInstance3D:
	for child in node.get_children():
		var mesh := child as MeshInstance3D
		if mesh != null:
			return mesh
	return null


# §BUNDLE NORMALS — the one reading that separates "the fistful is in shadow" from
# "the fistful has no surface normals at all". A mesh baked through `SurfaceTool` can
# come out with a valid vertex array and NO normal array, in which case it renders dark
# whatever the lights do, which is exactly the symptom the review frame showed next to
# a correctly-lit handle one node away.
const ARRAY_FORMAT_NORMAL := 2


func _report_bundle_mesh() -> void:
	var turns := visual.coil_loops()
	if turns.is_empty():
		return
	var mesh := turns[0].mesh as ArrayMesh
	if mesh == null:
		print("  stow mesh         NOT an ArrayMesh (%s)" % turns[0].mesh)
		return
	var surface := mesh.get_surface_count()
	var format := mesh.surface_get_format(0)
	var arrays := mesh.surface_get_arrays(0)
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	print("  stow mesh         Arc00: %d surface(s) · %d verts · format %d · NORMAL=%s (%d)"
		% [
			surface, vertices.size(), format,
			str((format & ARRAY_FORMAT_NORMAL) != 0), normals.size(),
		])
	if normals.size() > 0:
		print("  first normal      %s" % _v3(normals[0]))
	print("  material          albedo=%s rough=%.2f metallic=%.2f"
		% [
			str((turns[0].material_override as StandardMaterial3D).albedo_color),
			(turns[0].material_override as StandardMaterial3D).roughness,
			(turns[0].material_override as StandardMaterial3D).metallic,
		])


func _wait(frames: int) -> void:
	for i in frames:
		await process_frame
