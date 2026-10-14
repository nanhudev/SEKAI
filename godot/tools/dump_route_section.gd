# Print the real cross-section of the authored route surfaces at chosen z values.
#
# Written because the centreline kept landing on the bridge deck's edge (x=-3.35)
# instead of its middle (0.0), and the reason was not visible from the aggregate
# numbers. Guessing at a mesh's vertex layout wastes more time than measuring it.
#
# Run: godot --headless --path godot --script res://tools/dump_route_section.gd

extends SceneTree

const GLB := "res://models/mistvale_ue/mistvale_rebuild.glb"

const SOURCES := [
	"ART_Surface_SM_Route_GoldenRoute_South",
	"SM_Handoff_BridgeSouth",
	"MainStoneBridge_DECK",
	"SM_Handoff_BridgeNorth",
	"ART_Surface_SM_Route_GoldenRoute_Town",
]

## z positions to slice, and the half-thickness of each slice.
const SLICES := [-119.0, -114.0, -110.0, -107.0, -105.0, -104.5, -104.0, -103.0, -102.0, -95.0, -84.0, -68.0, -66.0, -60.0]
const HALF := 0.25


func _init() -> void:
	_run()


func _run() -> void:
	await process_frame
	var packed := load(GLB) as PackedScene
	if packed == null:
		printerr("NO VERDICT: cannot load ", GLB)
		quit(1)
		return
	var inst := packed.instantiate()
	get_root().add_child(inst)
	await process_frame

	for name in SOURCES:
		var node := inst.find_child(name, true, false) as MeshInstance3D
		if node == null:
			print("== %s : MISSING" % name)
			continue
		print("== %s" % name)
		var mesh: Mesh = node.mesh
		var xf: Transform3D = node.global_transform
		var all: Array = []
		for s in mesh.get_surface_count():
			var verts: PackedVector3Array = mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
			for v in verts:
				all.append(xf * v)
		print("   vertices=%d  surfaces=%d  aabb=%s" % [all.size(), mesh.get_surface_count(),
			str(node.global_transform * node.get_aabb())])
		for z0 in SLICES:
			var xs: Array = []
			for w in all:
				if absf(w.z - z0) <= HALF:
					xs.append(w)
			if xs.is_empty():
				continue
			xs.sort_custom(func(a, b): return a.x < b.x)
			var uniq: Array = []
			for w in xs:
				if uniq.is_empty() or absf(w.x - uniq[uniq.size() - 1].x) > 0.02:
					uniq.append(w)
			var s := ""
			for w in uniq:
				s += "(%.2f,%.2f) " % [w.x, w.y]
			print("   z=%8.2f  n=%3d  distinct (x,y): %s" % [z0, xs.size(), s])
	quit(0)
