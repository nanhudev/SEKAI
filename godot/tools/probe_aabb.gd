extends SceneTree
##
## probe_aabb.gd — "what is actually standing here?"
##
## WHY THIS EXISTS: the review loop repeatedly hit frames that were 90% black
## and every layer-hiding bisect could only name the subtree, not the object.
## Reading the builder source did not answer it either, because the question is
## about WORLD positions after the builder's own transforms, which is exactly
## what the source does not tell you. This prints them.
##
## The R06 case, for the record: the Guild Terrace review point came back at
## luminance 24. Hiding Terrain / Town / Greybox / Land / Flora changed nothing;
## hiding Ascent took it to 73; hiding Ascent/Guild alone did the same. This
## tool is what turned "the Guild group is wrong" into a list of boxes.
##
## Usage:
##   Godot --path F:/SEKAI/godot --headless \
##         --script res://tools/probe_aabb.gd -- --path=Ascent/Guild \
##         --at=x,z --eye=y --radius=40 [--top=30] [--contain]
##
##   --path     subtree to walk (default: whole scene)
##   --at       XZ to measure distance from
##   --eye      if given with --contain, the world point to test for enclosure
##   --radius   only report meshes whose AABB comes within this many metres
##   --top      print at most this many (default 30)
##   --contain  only print meshes whose world AABB contains the test point

var _path := ""
var _x := 0.0
var _z := 0.0
var _eye := 1.7
var _radius := 40.0
var _top := 30
var _contain := false


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--path="):
			_path = a.substr(7)
		elif a.begins_with("--at="):
			var v := a.substr(5).split(",")
			_x = float(v[0])
			_z = float(v[1])
		elif a.begins_with("--eye="):
			_eye = float(a.substr(6))
		elif a.begins_with("--radius="):
			_radius = float(a.substr(9))
		elif a.begins_with("--top="):
			_top = int(a.substr(6))
		elif a.begins_with("--contain"):
			_contain = true

	var packed: PackedScene = load("res://scenes/world/MistvaleRegion.tscn")
	var scene: Node3D = packed.instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	await process_frame

	var root_n: Node = scene
	if _path != "":
		root_n = scene.get_node_or_null(NodePath(_path))
		if root_n == null:
			push_error("probe_aabb: no such path %s" % _path)
			quit(1)
			return

	var rows: Array = []
	var st: Array = [root_n]
	while not st.is_empty():
		var n: Node = st.pop_back()
		for c in n.get_children():
			st.append(c)
		if not (n is MeshInstance3D):
			continue
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		var ab: AABB = mi.mesh.get_aabb()
		var gx := mi.global_transform
		# An AABB's corners transform to an AABB of the transformed corners.
		# Using only the two native corners under rotation UNDERSTATES the box
		# and would have missed the very mesh this tool was written to find.
		var corners := PackedVector3Array()
		for cx in [ab.position.x, ab.position.x + ab.size.x]:
			for cy in [ab.position.y, ab.position.y + ab.size.y]:
				for cz in [ab.position.z, ab.position.z + ab.size.z]:
					corners.append(gx * Vector3(cx, cy, cz))
		var wab := AABB(corners[0], Vector3.ZERO)
		for cv in corners:
			wab = wab.expand(cv)

		var d := Vector2(wab.get_center().x - _x, wab.get_center().z - _z).length()
		d = maxf(0.0, d - 0.5 * Vector2(wab.size.x, wab.size.z).length())
		var pt := Vector3(_x, _eye, _z)
		var inside := wab.has_point(pt)
		if _contain and not inside:
			continue
		if d > _radius:
			continue
		rows.append({
			"d": d, "inside": inside, "name": _full(n, scene),
			"lo": wab.position, "hi": wab.position + wab.size,
			"sz": wab.size,
		})

	rows.sort_custom(func(a, b): return a["d"] < b["d"])
	print("probe_aabb  path=%s  at(%.1f, %.1f) eye %.2f  radius %.1f  hits %d"
		% [_path if _path != "" else "/", _x, _z, _eye, _radius, rows.size()])
	var i := 0
	for r in rows:
		if i >= _top:
			break
		i += 1
		print("  %6.1f m %s %-46s lo(%.1f %.1f %.1f) hi(%.1f %.1f %.1f) size(%.1f %.1f %.1f)"
			% [r["d"], "IN>" if r["inside"] else "   ", r["name"],
			   r["lo"].x, r["lo"].y, r["lo"].z,
			   r["hi"].x, r["hi"].y, r["hi"].z,
			   r["sz"].x, r["sz"].y, r["sz"].z])
	quit(0)


func _full(n: Node, scene: Node) -> String:
	var s := String(n.name)
	var p := n.get_parent()
	while p != null and p != scene:
		s = String(p.name) + "/" + s
		p = p.get_parent()
	return s
