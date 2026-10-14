extends SceneTree
## DEMO_CAST AUDIT -- is the cast manifest usable *by the engine*?
##
## tools/character/validate_cast.py checks the manifest against the bakes on disk.
## This checks the other half, which Python cannot see: that each declared model
## actually became a loadable Godot resource.  A GLB that is present but failed to
## import exists on disk and does not exist as a resource -- and that is precisely
## the failure a manifest is supposed to catch before narrative code binds to it.
##
##   godot --headless --path F:/SEKAI/godot --script res://tools/cast_check.gd \
##     > F:/SEKAI/assets_source/characters/placeholders/_review/cast_audit.txt 2>&1
##
## Redirect stdout to a file: print() is block-buffered and is otherwise lost when
## piped, which makes a working run look like a hang.

const DemoCast := preload("res://scripts/characters/demo_cast.gd")


func _init() -> void:
	print("== DEMO_CAST AUDIT ==")
	print("manifest: %s" % DemoCast.MANIFEST_PATH)
	print("")

	var chars := DemoCast.characters()
	if chars.is_empty():
		print("FAIL: manifest has no characters")
		quit(1)
		return

	print("%-18s %-20s %-17s %-14s %-6s %5s %s"
			% ["character_id", "scene_role", "placeholder_model", "skeleton",
			   "loads", "acts", "priority"])
	var n_load_fail := 0
	for c in chars:
		var d := c as Dictionary
		var cid := String(d.get("character_id", ""))
		var model := String(d.get("placeholder_model", ""))
		var p := DemoCast.skeleton_profile_name(cid)
		var loadable := ResourceLoader.exists(model)
		if not loadable:
			n_load_fail += 1
		print("%-18s %-20s %-17s %-14s %-6s %5d %s"
				% [cid, String(d.get("scene_role", "")), model.get_file().get_basename(),
				   p, "yes" if loadable else "NO", DemoCast.required_actions(cid).size(),
				   String(d.get("priority", ""))])

	print("")
	print("-- base motion coverage --")
	var base: Dictionary = DemoCast.manifest().get("base_motions", {})
	# NOT a Dictionary-of-PackedStringArray: packed arrays are VALUE types, so
	# `dict[k].append(x)` appends to a temporary copy and the count silently stays
	# zero.  That is exactly the class of bug this audit exists to find.
	var covered := PackedStringArray()
	var partial := PackedStringArray()
	var missing := PackedStringArray()
	var unknown := PackedStringArray()
	for key in base:
		if String(key).begins_with("_"):
			continue
		match String((base[key] as Dictionary).get("status", "?")):
			"covered":
				covered.append(String(key))
			"partial":
				partial.append(String(key))
			"missing":
				missing.append(String(key))
			_:
				unknown.append(String(key))
	print("   %-8s %2d  %s" % ["covered", covered.size(), ", ".join(covered)])
	print("   %-8s %2d  %s" % ["partial", partial.size(), ", ".join(partial)])
	print("   %-8s %2d  %s" % ["missing", missing.size(), ", ".join(missing)])
	for u in unknown:
		print("   ?? base motion '%s' has an unknown status" % u)

	print("")
	print("-- pools --")
	var pools: Dictionary = DemoCast.manifest().get("pools", {})
	for pname in pools:
		var pool := pools[pname] as Dictionary
		var bad := 0
		for m in (pool.get("models", []) as Array):
			if not ResourceLoader.exists(String(m)):
				bad += 1
				print("   %s: UNLOADABLE %s" % [pname, m])
		print("   %-24s %d model(s)%s"
				% [pname, (pool.get("models", []) as Array).size(),
				   "" if bad == 0 else "  <-- %d unloadable" % bad])

	print("")
	var probs := DemoCast.problems()
	for p in probs:
		print("PROBLEM  %s" % p)

	print("")
	if probs.is_empty() and n_load_fail == 0:
		print("RESULT: OK  (%d characters, manifest agrees with the engine)" % chars.size())
		quit(0)
	else:
		print("RESULT: FAIL  (%d problem(s), %d unloadable model(s))"
				% [probs.size(), n_load_fail])
		quit(1)
