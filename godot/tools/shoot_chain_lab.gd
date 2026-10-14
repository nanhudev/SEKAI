extends SceneTree
##
## §17/§18 — LOOKS AT THE TRAINING GROUND, and asks it what its own key legend says.
##
## WHY THIS EXISTS SEPARATELY FROM THE SLICE TESTS. §17's finding was not that the
## training ground is missing — the deck, the three weights, the anchor and the wall
## were all built and tested — it was that **用户不知道怎么测试**: the scene worked and
## nobody could tell what to press. A legend answers that only if its keys are the keys
## the build actually binds, and that is a question NO OTHER TEST CAN ASK, because the
## bindings are created at runtime by four different nodes and the labels are read from
## `InputMap` at build time. So this script:
##
##   1. PRINTS every row of the legend, resolved, so the mapping is in the log rather
##      than only in a picture — a screenshot proves the panel drew, not that "Skill 1"
##      is F3. A blank or wrong key is a text-level fact.
##   2. SCREENSHOTS the ground with the legend SHOWING, because a still of the training
##      ground is the thing §18 asks to be able to look at, and `--headless` would hang
##      on `frame_post_draw` (see `combat_movie_renderer.gd`).
##
## Usage:
##   godot --path godot --resolution 1280x720 --script res://tools/shoot_chain_lab.gd \
##         -- <out.png>
## With no output path it prints the legend and exits without rendering.

const WAIT_FRAMES := 24


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out := String(args[0]) if args.size() > 0 else ""

	var sandbox := load("res://scenes/combat/CombatSandbox.tscn").instantiate() as Node3D
	root.add_child(sandbox)
	for _i in 4:
		await process_frame

	var lab := sandbox.get_node_or_null("ChainLab") as ChainLab
	if lab == null:
		print("!! no ChainLab in CombatSandbox — the training ground is not in this scene")
		quit(1)
		return

	# The legend is built with `call_deferred` because the InputMap is filled by the
	# player's own `_ready`, so the rows are only readable after the frame in which
	# every other `_ready` has run. Reading them before that is the bug the deferred
	# build exists to avoid, and it would look exactly like "the keys do not exist".
	for _i in WAIT_FRAMES:
		await process_frame

	print("--- §17 TRAINING GROUND LEGEND (resolved from InputMap) ---")
	var rows: Array = ChainLab.LEGEND_ROWS + ChainLab.LEGEND_MOVE_ROWS
	var blanks := 0
	for row in rows:
		var action: StringName = row[1]
		var key := ChainLab.key_of(action)
		var bound := InputMap.has_action(action)
		if key.is_empty():
			blanks += 1
		print("  %-22s %-8s %s" % [String(action), key if not key.is_empty() else "(none)",
			"ok" if bound else "!! ACTION NOT BOUND"])
	print("  %-22s %-8s" % ["weapon slot 1 / 2", "1 / 2"])
	if blanks > 0:
		print("  !! %d legend row(s) resolve to no key" % blanks)
	print("legend node: %s" % ("built" if lab.legend != null else "!! NOT BUILT"))

	if err_ok(out):
		lab.set_legend_visible(true)
		for _i in 4:
			await process_frame
		var image := root.get_texture().get_image()
		if image == null:
			print("!! viewport returned no image")
			quit(1)
			return
		image.save_png(out)
		print("wrote %s" % out)

	quit(0 if blanks == 0 else 1)


static func err_ok(path: String) -> bool:
	return not path.is_empty()
