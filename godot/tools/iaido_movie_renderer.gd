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
##         --script res://tools/iaido_movie_renderer.gd -- <output_dir>
##
## Then encode the sequence, for example:
##   ffmpeg -y -framerate 30 -i frame_%04d.png -pix_fmt yuv420p ../iaido.mp4

const FPS := 30.0
const STEP := 1.0 / FPS
const PRE_ROLL := 12        # frames held at t=0, so the "before" is visible
const TAIL_FRAMES := 20     # frames after everything is released again
var MAX_TIME := 8.2

var output_dir := ""
var frame_index := 0
var overlay: Label
var overlay_title: Label


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	output_dir = args[0] if args.size() > 0 else ProjectSettings.globalize_path("res://../.render/frames")
	if args.size() > 1:
		MAX_TIME = float(args[1])
	# Optional window start, so a single stage can be checked in seconds
	# instead of re-rendering the whole ceremony.
	var start_time := float(args[2]) if args.size() > 2 else 0.0
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
	_build_overlay()

	var tuning: Resource = director.get("tuning")
	var total := float(tuning.get("restore_end"))
	print("window size: ", root.size, " scale: ", root.content_scale_size)
	print("Rendering Iaido ceremony to: ", output_dir)
	print("Timeline length: %.2fs" % total)

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
	# previous take, which then end up in the encoded video.
	var dir := DirAccess.open(output_dir)
	if dir == null:
		return
	var removed := 0
	for file in dir.get_files():
		if file.begins_with("frame_") and file.ends_with(".png"):
			dir.remove(file)
			removed += 1
	if removed > 0:
		print("cleared %d stale frames" % removed)


# Two frames: one to let physics/canvas settle, one to land the draw.
func _frame() -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw


func _save(t: float) -> void:
	var path := "%s/frame_%04d.png" % [output_dir, frame_index]
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
	var layer := CanvasLayer.new()
	layer.layer = 120
	root.add_child(layer)

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
	layer.add_child(holder)

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


func _phase(t: float) -> String:
	if t < 0.45:
		return "A · WORLD SILENCE"
	if t < 1.20:
		return "B · RETURN TO SHEATH"
	if t < 2.20:
		return "C · REVERSE WAVE"
	if t < 2.85:
		return "D · COMPRESSION HOLD"
	if t < 2.95:
		return "E · SHEATH LOCK"
	if t < 3.08:
		return "F · INSTANT DRAW"
	if t < 3.40:
		return "G · WORLD CUT"
	if t < 3.90:
		return "H · SEPARATION"
	if t < 4.25:
		return "I · TENSION FREEZE"
	if t < 4.75:
		return "J · GLASS FAILURE"
	if t < 5.35:
		return "K · SWORD CONTROL"
	if t < 6.20:
		return "L · SLOW SHEATHE"
	if t < 6.65:
		return "M · REALITY COLLAPSE"
	if t < 7.20:
		return "N · RESTORE"
	return "RECOVERY"
