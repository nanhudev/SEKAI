extends SceneTree
## Dumps the per-mesh normal and vertex-colour statistics of the land layer.
##
## Written because a render bisect proved the black foreground was the ROAD
## ribbon, but not why — and "the road renders black" has four candidate causes
## (winding, vertex colour, material flag, UV) that all look the same in a
## screenshot. Numbers do not look the same.
##
## Run:
##   Godot --headless --path F:/SEKAI/godot --script res://tools/probe_land_meshes.gd

func _initialize() -> void:
	var script: GDScript = load("res://scripts/world/mistvale_land.gd")
	var land: Node3D = script.new()
	land.name = "Land"
	root.add_child(land)
	await process_frame
	await process_frame
	_dump(land)
	quit(0)


func _dump(node: Node) -> void:
	for c in node.get_children():
		if c is MeshInstance3D:
			var mi := c as MeshInstance3D
			var m: Mesh = mi.mesh
			if m == null or m.get_surface_count() == 0:
				print("%-22s [no mesh]" % mi.name)
				continue
			var ar := m.surface_get_arrays(0)
			var n: PackedVector3Array = ar[Mesh.ARRAY_NORMAL]
			var col_any = ar[Mesh.ARRAY_COLOR]
			var ny := 0.0
			var down := 0
			for v in n:
				ny += v.y
				if v.y < -0.2:
					down += 1
			ny /= maxf(float(n.size()), 1.0)
			var cs := "none"
			var cm := "-"
			if col_any != null and col_any.size() > 0:
				var cols: PackedColorArray = col_any
				var acc := Vector3.ZERO
				var cmin := 9.0
				var cmax := -9.0
				var black := 0
				for k in cols:
					var lum := (k.r + k.g + k.b) / 3.0
					acc += Vector3(k.r, k.g, k.b)
					cmin = minf(cmin, lum)
					cmax = maxf(cmax, lum)
					if lum < 0.05:
						black += 1
				acc /= float(cols.size())
				print("      colour lum min=%.3f max=%.3f  near-black verts=%d/%d"
					% [cmin, cmax, black, cols.size()])
				cm = "%.3f %.3f %.3f" % [acc.x, acc.y, acc.z]
				cs = "yes"
			var mat := mi.material_override
			var vc := false
			if mat is StandardMaterial3D:
				vc = (mat as StandardMaterial3D).vertex_color_use_as_albedo
			print("%-22s meanN.y=%+.3f  down%%=%.1f  colour[%s]=%s  vcol_albedo=%s"
				% [mi.name, ny, 100.0 * float(down) / maxf(float(n.size()), 1.0),
					cs, cm, vc])
		elif c is MultiMeshInstance3D:
			var mmi := c as MultiMeshInstance3D
			var mm := mmi.multimesh
			print("%-22s [multimesh %d]" % [mmi.name, mm.instance_count if mm else -1])
		else:
			_dump(c)
