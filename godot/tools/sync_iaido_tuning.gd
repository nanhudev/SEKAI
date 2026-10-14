extends SceneTree
##
## Regenerates `res://resources/tuning/IaidoTuning.tres` from the script's own
## defaults, then PROVES the file it wrote by loading it back and comparing every
## exported field.
##
## WHY THIS EXISTS
##
## The tuning resource is the runtime authority for the Iaido ceremony, and it is
## a plain .tres that a running Godot editor will happily re-save from its own
## stale in-memory copy. That silently reverted a whole pass once: 118 exported
## values are written into the file, every one of them overrides the script
## default, so a file that is one edit behind reverts the timeline without a
## single error being raised anywhere. It looks exactly like a code change that
## did nothing.
##
## This was previously done by regex over the .gd source, which cannot tell the
## difference between "wrote the right value" and "wrote the right value in the
## wrong place", and cannot notice a default it failed to match at all.
##
## HOW IT WORKS
##
## `IaidoTuning.new()` IS the set of defaults — the script is the source of
## truth, so the defaults are read from the engine rather than parsed. The
## resource is then saved over the .tres and RELOADED, and every field is
## compared against the fresh defaults. If any value disagrees, the tool reports
## it and exits non-zero, so a broken sync is a failed command and not a silent
## revert three renders later.
##
## Usage:
##   godot --headless --path godot --script res://tools/sync_iaido_tuning.gd
##
## Then re-run the integration test, which asserts the same invariant from the
## other side (`tests/iaido_integration.gd :: _verify_tuning_is_not_stale`).
##
## NOTE ON `--headless`: this touches no rendering, so it is safe to run while a
## visible editor is open. It does WRITE a shared file, so check that no other
## session is mid-edit on the .tres before running it.

const RESOURCE_PATH := "res://resources/tuning/IaidoTuning.tres"

var failures: Array[String] = []


func _initialize() -> void:
	# The values, not the file: whatever the script currently says is correct.
	var defaults := IaidoTuning.new()
	if defaults == null:
		_fail("Could not instantiate IaidoTuning — is the class_name still registered?")
		_finish()
		return

	# Read the current file straight off disk, bypassing the resource cache, so
	# the "what is about to change" list is a genuine before/after.
	var existing := ResourceLoader.load(
		RESOURCE_PATH, "", ResourceLoader.CACHE_MODE_REPLACE) as IaidoTuning
	if existing == null:
		_fail("Could not load %s — the path or its .uid changed." % RESOURCE_PATH)
		_finish()
		return

	var fields := _exported_fields(defaults)
	if fields.is_empty():
		_fail("IaidoTuning exposes no stored fields — refusing to write an empty resource.")
		_finish()
		return

	# Report what is about to change, so the diff of a sync is legible in CI and
	# in a terminal rather than only in `git diff`.
	var changed := 0
	for field in fields:
		var before = existing.get(field)
		var after = defaults.get(field)
		if not _same(before, after):
			changed += 1
			print("  %-28s %s  ->  %s" % [field, before, after])

	# Build the resource to save from the defaults, field by field, so the file
	# can never carry a value the script does not currently have.
	var fresh := IaidoTuning.new()
	for field in fields:
		fresh.set(field, defaults.get(field))

	var error := ResourceSaver.save(fresh, RESOURCE_PATH)
	if error != OK:
		_fail("ResourceSaver.save failed with error %d" % error)
		_finish()
		return

	# ---- PROVE IT ---------------------------------------------------------
	#
	# The whole point. A writer that cannot verify what it wrote is the reason
	# the .tres went stale in the first place, so re-read from disk and compare
	# against the defaults — not against the object that was just written, which
	# would only prove the object matches itself.
	#
	# CACHE_MODE_IGNORE is load-bearing, and not an optimisation. `load()` is
	# cached BY PATH, so a plain `load(RESOURCE_PATH)` here returns the very
	# object loaded at the top of this function — the STALE one — and the check
	# passes no matter what was written. That is how this tool first shipped: it
	# saved correctly and then reported 15 failures because it was comparing the
	# old resource against the new one. A verifier that can only ever see what it
	# expected to see is worse than no verifier, because it also removes the
	# suspicion.
	var written := ResourceLoader.load(
		RESOURCE_PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as IaidoTuning
	if written == null:
		_fail("Wrote %s but could not load it back from disk." % RESOURCE_PATH)
		_finish()
		return
	var missing := 0
	for field in fields:
		var got = written.get(field)
		var want = defaults.get(field)
		if got == null:
			missing += 1
			_fail("%s was not written to the .tres (reads back as null)." % field)
			continue
		if not _same(got, want):
			_fail("%s round-tripped as %s but the script default is %s." % [field, got, want])

	print("")
	print("IaidoTuning.tres synced: %d fields, %d changed, %d missing." % [fields.size(), changed, missing])
	_finish()


# Every property the engine will actually store, i.e. what belongs in the file.
# Group markers, category headers and the script itself are not values.
func _exported_fields(resource: IaidoTuning) -> Array[String]:
	var out: Array[String] = []
	for property in resource.get_property_list():
		var usage: int = int(property["usage"])
		if usage & PROPERTY_USAGE_SCRIPT_VARIABLE == 0:
			continue
		if usage & PROPERTY_USAGE_STORAGE == 0:
			continue
		var name := String(property["name"])
		# Constants and the built-in `script` handle are not timeline values.
		if name.begins_with("_"):
			continue
		out.append(name)
	out.sort()
	return out


# Floats are the overwhelming majority of these fields, and an exact `==` on
# floats compares the BINARY value — a value written as `2.1` and read back as
# `2.1` is identical, but one computed differently is not. The tolerance is
# deliberately far below anything the ceremony can express (a thousandth of a
# pixel, a thousandth of a second) and exists only to stop a formatting
# round-trip from being reported as a desync.
func _same(a, b) -> bool:
	if typeof(a) != typeof(b):
		# A float and an int holding the same number are the same value here.
		if (a is float or a is int) and (b is float or b is int):
			return absf(float(a) - float(b)) < 0.000001
		return false
	if a is float:
		return absf(float(a) - float(b)) < 0.0000001
	if a is Vector2:
		return (a as Vector2).is_equal_approx(b as Vector2)
	if a is Color:
		return (a as Color).is_equal_approx(b as Color)
	return a == b


func _fail(message: String) -> void:
	failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("OK: the .tres matches the script defaults on disk.")
		quit(0)
		return
	print("")
	print("SYNC FAILED: %d problem(s)" % failures.size())
	for message in failures:
		print("  - " + message)
	quit(1)
