extends SceneTree
# Lists what the PLACEHOLDER GLBs actually expose, read through Godot's resource
# loader rather than from the demo_cast manifest.
#
# WHY BOTH. `demo_cast.json` records intent (`base_motions.Idle.clips = ["Idle"]`)
# and this records fact (what the imported .glb's AnimationPlayer holds). The two
# disagree exactly when an import failed, and per the manifest's own header that
# is the one failure Python-side validation cannot see.
#
# Run:  Godot --headless --script tools/probe_cast_clips.gd

const MODELS := [
	"res://assets/characters/placeholders/lpg_scifi_w.glb",
	"res://assets/characters/placeholders/lpg_adventurer_w.glb",
	"res://assets/characters/placeholders/lpg_farmer_m.glb",
	"res://assets/characters/placeholders/lpg_casual_m.glb",
]


func _init() -> void:
	for path in MODELS:
		_report(path)
	quit()


func _report(path: String) -> void:
	print("========================================================")
	print("MODEL ", path)
	if not ResourceLoader.exists(path):
		print("  MISSING AS A RESOURCE (import failed?)")
		return
	var packed := load(path) as PackedScene
	if packed == null:
		print("  NOT A PackedScene")
		return
	var root := packed.instantiate()
	var players := _collect(root, [])
	print("  root=", root.name, " type=", root.get_class(),
		" children=", root.get_child_count())
	if players.is_empty():
		print("  NO AnimationPlayer ANYWHERE IN THE TREE")
	else:
		for p in players:
			var ap := p as AnimationPlayer
			var names := ap.get_animation_list()
			print("  AnimationPlayer at ", root.get_path_to(ap),
				"  animations=", names.size(),
				"  autoplay=", ap.autoplay)
			var shown := 0
			for n in names:
				if shown < 60:
					var a := ap.get_animation(n)
					print("     - ", n, "   len=", "%.3f" % a.length,
						"  loop=", a.loop_mode)
					shown += 1
			if names.size() > shown:
				print("     ... and ", names.size() - shown, " more")
	# bone census: how many Skeleton3D bones, and does a leg hang off the root
	var skels := _collect_skel(root, [])
	for s in skels:
		var sk := s as Skeleton3D
		print("  Skeleton3D ", root.get_path_to(sk), " bones=", sk.get_bone_count())
		for i in sk.get_bone_count():
			var bn := sk.get_bone_name(i)
			if bn.to_lower().contains("leg") or bn.to_lower().contains("hip") \
					or bn.to_lower().contains("root") or bn.to_lower().contains("pelvis"):
				print("      ", i, " ", bn, "  parent=",
					sk.get_bone_parent(i), "  rest_y=%.3f" % sk.get_bone_rest(i).origin.y)
	root.free()


func _collect(n: Node, out: Array) -> Array:
	if n is AnimationPlayer:
		out.append(n)
	for c in n.get_children():
		_collect(c, out)
	return out


func _collect_skel(n: Node, out: Array) -> Array:
	if n is Skeleton3D:
		out.append(n)
	for c in n.get_children():
		_collect_skel(c, out)
	return out
