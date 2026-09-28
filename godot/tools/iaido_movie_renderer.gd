extends SceneTree
##
## Renders the full Iaido ceremony into a PNG frame sequence so the complete
## 7.2 s performance can actually be watched, instead of being judged from a
## handful of stills. The director is stepped in debug-hold mode, which pins
## the timeline to an exact time, so the exported frames are frame-rate
## independent and every take is identical.
##
## Usage:
##   godot --path . --resolution 1280x720 --audio-driver Dummy \
##         --script res://tools/iaido_movie_renderer.gd -- <output_dir> [MAX_TIME]
##         [start_time] [overlay 0/1] [shot_list "t:label,..."]
##         [overrides "k=v,k=v"] [ablations "glass,crack,void,sword"]
##
## The last argument is PART S's test matrix: it switches off the thing that is
## supposed to be carrying the read, so a frame can prove the effect is not
## resting on it.
##
## Then encode the sequence, for example:
##   ffmpeg -y -framerate 30 -i frame_%04d.png -pix_fmt yuv420p ../iaido.mp4

const FPS := 30.0
const STEP := 1.0 / FPS
const PRE_ROLL := 12        # frames held at t=0, so the "before" is visible
const TAIL_FRAMES := 20     # frames after everything is released again
var MAX_TIME := 9.90

var output_dir := ""
var frame_index := 0
var overlay: Label
var overlay_title: Label
var overlay_layer: CanvasLayer
var show_overlay := false
var tuning: Resource
# Explicit shot list: [time, label] pairs. The verification frames are specific
# moments, not windows, and hunting for a moment by stepping a window costs a
# whole render per shot.
var shots: Array = []
var overrides: Array = []


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	output_dir = args[0] if args.size() > 0 else ProjectSettings.globalize_path("res://../.render/frames")
	if args.size() > 1:
		MAX_TIME = float(args[1])
	# Optional window start, so a single stage can be checked in seconds
	# instead of re-rendering the whole ceremony.
	var start_time := float(args[2]) if args.size() > 2 else 0.0
	# The debug timeline is a developer tool. Anything the user watches must be
	# rendered without it.
	show_overlay = args.size() > 3 and int(args[3]) == 1
	# Optional shot list, "t:label,t:label,..." — renders one named frame per
	# entry and skips the pre-roll and tail entirely.
	if args.size() > 4 and args[4].strip_edges() != "":
		for piece in args[4].split(","):
			var parts := piece.split(":")
			shots.append([float(parts[0]), parts[1] if parts.size() > 1 else ""])
	# Optional tuning overrides, "key=value,key=value". Held in memory only —
	# the .tres is never written back. This is how a single variable gets A/B'd
	# against an otherwise identical frame, which is the only honest way to
	# claim a displacement is or is not visible.
	if args.size() > 5 and args[5].strip_edges() != "":
		for piece in args[5].split(","):
			var kv := piece.split("=")
			if kv.size() == 2:
				overrides.append([kv[0].strip_edges(), float(kv[1])])
	var err := DirAccess.make_dir_recursive_absolute(output_dir)
	print("output_dir=", output_dir, " mkdir_err=", err)
	_clear_existing_frames()

	var window: Window = root
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	# Keep this window on top and out of the OS background-throttling path:
	# when another Godot window (the editor) covers it, the render loop can
	# stall and frame_post_draw never fires, which hangs the whole render.
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)
	DisplayServer.window_move_to_foreground()
	var sandbox: Node = load("res://scenes/combat/CombatSandbox.tscn").instantiate()
	window.add_child(sandbox)

	await process_frame
	await process_frame
	await process_frame

	var director: Node = sandbox.get_node("IaidoDirector")
	var player := director.get("player") as Node3D
	director.get("combat").set("iaido_ready_at", 0.0)
	player.set("stamina", 100.0)
	tuning = director.get("tuning")
	for pair in overrides:
		tuning.set(String(pair[0]), pair[1])
		print("override %s = %s" % [pair[0], pair[1]])
	# ---- TEST MATRIX ABLATIONS (PART S) ------------------------------------
	#
	# PART S asks for frames in which the thing that is supposed to be carrying
	# the read is switched OFF — "no glass" and "no crack network" both still
	# have to be legible as a world cut in two. Driven through the director's
	# own flags rather than by editing the scene, so an ablation frame is
	# otherwise identical to the frame it is compared against.
	var ablations := String(args[6]) if args.size() > 6 else ""
	for flag in ablations.split(","):
		match flag.strip_edges():
			"glass":
				director.set("suppress_glass", true)
				print("ABLATION: glass OFF")
			"crack":
				director.set("suppress_crack", true)
				print("ABLATION: crack network OFF")
			"void":
				# TEST 2's twin: keep the displacement, delete the hole. If the
				# step alone reads as a break, the void is not carrying it. The
				# shader floors `open_px` at 0.45 authored px so a hairline
				# always exists — at 720p that is six tenths of a pixel, which
				# is to say not there.
				tuning.set("gap_ratio", 0.02)
				tuning.set("gap_min_px", 0.0)
				print("ABLATION: void slot OFF (displacement only)")
			"sword":
				var weapon_root: Node = player.get_node_or_null(
					"CameraRig/LookPivot/MotionPivot/ShakePivot/WeaponRoot")
				if weapon_root != null:
					(weapon_root as Node3D).visible = false
					print("ABLATION: weapon OFF")
	_build_overlay()

	var total := float(tuning.get("restore_end"))
	print("window size: ", root.size, " scale: ", root.content_scale_size)
	print("Rendering Iaido ceremony to: ", output_dir)
	print("Timeline length: %.2fs" % total)

	if not shots.is_empty():
		for shot in shots:
			_hold(director, float(shot[0]))
			await _frame()
			_save(float(shot[0]), String(shot[1]))
			print("  shot %s @ %.2fs" % [String(shot[1]), float(shot[0])])
		print("Wrote %d shot frames" % frame_index)
		quit()
		return

	# Pre-roll: what the fight looks like before the world stops.
	_hold(director, start_time)
	for _i in PRE_ROLL:
		await _frame()
		_save(start_time)

	# The ceremony itself, stepped at a fixed dt so the pace is exact.
	var t := start_time
	var guard := 0
	while t <= MAX_TIME and guard < 600:
		if not bool(director.get("active")):
			break
		_hold(director, t)
		await _frame()
		_save(t)
		t += STEP
		guard += 1

	# Release and let the restored world breathe for a moment.
	director.release_debug_hold()
	director.finish_iaido()
	for _i in TAIL_FRAMES:
		await _frame()
		overlay.visible = false
		_save(-1.0)

	print("Wrote %d frames" % frame_index)
	quit()


func _hold(director: Node, t: float) -> void:
	director.set_debug_hold(t)


func _clear_existing_frames() -> void:
	# Re-rendering into the same folder leaves stale frames from a longer
	# previous take, which then end up in the encoded video. Every PNG in the
	# folder goes, not just the ones matching the current naming scheme — an
	# older take used different names and its leftovers would otherwise sit
	# alongside the new shot list.
	var dir := DirAccess.open(output_dir)
	if dir == null:
		return
	var removed := 0
	for file in dir.get_files():
		if file.get_extension().to_lower() == "png":
			dir.remove(file)
			removed += 1
	if removed > 0:
		print("cleared %d stale images" % removed)


# Two frames: one to let physics/canvas settle, one to land the draw.
func _frame() -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw


func _save(t: float, label: String = "") -> void:
	var path := ""
	if label != "":
		path = "%s/%s.png" % [output_dir, label]
	else:
		path = "%s/frame_%04d.png" % [output_dir, frame_index]
	var image := root.get_texture().get_image()
	if image == null:
		push_error("Viewport texture returned no image at t=%.2f" % t)
		return
	var save_err := image.save_png(path)
	if save_err != OK:
		push_error("save_png failed (%d) for %s" % [save_err, path])
	if overlay != null:
		overlay.text = _label(t)
	frame_index += 1
	if frame_index % 30 == 0:
		print("  frame %d" % frame_index)


func _build_overlay() -> void:
	overlay_layer = CanvasLayer.new()
	overlay_layer.layer = 120
	overlay_layer.visible = show_overlay
	root.add_child(overlay_layer)

	var holder := PanelContainer.new()
	holder.set_anchors_preset(Control.PRESET_BOTTOM_WIDE, true)
	holder.offset_top = -58.0
	holder.offset_bottom = -12.0
	holder.offset_left = 180.0
	holder.offset_right = -180.0
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.03, 0.05, 0.62)
	style.content_margin_left = 18.0
	style.content_margin_right = 18.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	holder.add_theme_stylebox_override("panel", style)
	overlay_layer.add_child(holder)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 28)
	holder.add_child(row)

	overlay_title = Label.new()
	overlay_title.text = "IAIDO"
	overlay_title.add_theme_font_size_override("font_size", 14)
	overlay_title.modulate = Color(0.55, 0.68, 0.82, 0.80)
	row.add_child(overlay_title)

	overlay = Label.new()
	overlay.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	overlay.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	overlay.add_theme_font_size_override("font_size", 17)
	row.add_child(overlay)


func _label(t: float) -> String:
	if t < 0.0:
		return "RESTORED"
	return "t = %.2f s      %s" % [t, _phase(t)]


# Phase names are read off the tuning resource, so the debug strip can never
# disagree with the timeline it is describing.
#
# THIS TABLE IS PART OF THE TIMELINE, NOT A CAPTION. It went stale against V7
# and started throwing `float(null)` on every frame — it still named
# `freeze_end`, which V7 deleted, and it had no name at all for the hero hold
# or the consequence delay, so the two beats this pass exists for were the two
# beats the strip could not label.
func _phase(t: float) -> String:
	if tuning == null:
		return ""
	var marks := [
		["A · WORLD SILENCE", float(tuning.get("silence_end"))],
		["B · RETURN TO HIP", float(tuning.get("sheath_end"))],
		["C · CHARGING (2.0s)", float(tuning.get("wave_end"))],
		["D · GREY DRAIN", float(tuning.get("time_stop_start"))],
		["D · TIME STOP", float(tuning.get("time_stop_end"))],
		["E · SEAT", float(tuning.get("first_click"))],
		["E · ONE SECOND", float(tuning.get("wait_end"))],
		["F · INSTANT DRAW", float(tuning.get("draw_end"))],
		["G · CONSEQUENCE DELAY", float(tuning.get("cut_start"))],
		["G · THE SPLIT", float(tuning.get("cut_end"))],
		["G · HERO HOLD", float(tuning.get("hero_hold_end"))],
		["H · FRACTURE STREAM", float(tuning.get("glass_stream_end"))],
		["K · WRIST ARCS", float(tuning.get("spin_end"))],
		["L · FIRST TO LET GO", float(tuning.get("loosen_start"))],
		["L · RETURN TO SHEATH", float(tuning.get("final_click"))],
		["M · DEVOUR + COLLAPSE", float(tuning.get("collapse_end"))],
		["N · RESTORE", float(tuning.get("restore_end"))],
	]
	for mark in marks:
		if t < float(mark[1]):
			return String(mark[0])
	return "RECOVERY"
