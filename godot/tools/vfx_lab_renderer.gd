extends SceneTree
#
# SEKAI VFX LAB — the movie and still renderer for all eleven prototypes.
#
# =============================================================================
# ONE RENDERER FOR ELEVEN CLIPS, AND WHY THAT IS THE POINT
# =============================================================================
#
# If each prototype had its own renderer then each clip would be rendered by a
# different piece of code, and the one thing this round has to compare — "which
# of these reads as a broken rule from a single still" — would be measured on
# eleven slightly different instruments. So there is one renderer and the only
# thing that changes between clips is a name on the command line.
#
# =============================================================================
# THE TAKE IS CONTINUOUS, AND THAT IS NOT COSMETIC
# =============================================================================
#
# A clip is rendered by walking `t` forward from 0 in steps of 1/30s and never
# moving it backwards. A frame produced by being TOLD it is 5.70s is not
# necessarily the same frame as frame 171 of a take — it is the same frame only
# if `apply(t)` is a pure function of `t`, which `vfx_prototype.gd` requires and
# this renderer is the thing that checks by construction.
#
# Still frames are a separate mode and use the same `apply(t)`, so a still and the
# corresponding frame of the clip agree by definition. That matters more in this
# round than in any other, because the deliverable includes five stills per clip
# and the hero still is the acceptance test.
#
# =============================================================================
# USAGE
# =============================================================================
#
#   godot --path godot --resolution 1920x1080 --audio-driver Dummy \
#         --script res://tools/vfx_lab_renderer.gd -- \
#         <effect_id> <output_dir> [shots "t:label,t:label"] [lead] [tail] [overlay]
#
#   shots empty  -> render the whole clip as frame_%04d.png plus manifest.txt
#   shots given  -> render only those stills, named <label>.png
#
# Then:
#   tools/encode_vfx_movie.sh <output_dir> <out.mp4> <ffmpeg>

const FPS := 30.0
const STEP := 1.0 / FPS

var effect_id := ""
var output_dir := ""
var shots: Array = []
var lead_seconds := 0.7
var tail_seconds := 0.7
var show_overlay := false
## A named review placement from the lab, for the clips that need one shot the
## first-person camera cannot give — "is the player still 3D", "how big is it",
## "how far has the world tilted". Empty means first person throughout.
var review_point := ""
## Debug: prop names to hide, and whether to dump every prop's bounds. Both are
## instruments for finding out which object is on the screen, never for delivery.
var hide_props: Array = []
var debug_report := false

var lab: Node3D
var overlay: Label
var overlay_layer: CanvasLayer

var frame_index := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		push_error("usage: <effect_id> <output_dir> [shots] [lead] [tail] [overlay]")
		quit(1)
		return
	effect_id = String(args[0])
	output_dir = String(args[1])
	if args.size() > 2 and String(args[2]).strip_edges() != "" and String(args[2]).strip_edges() != "-":
		for piece in String(args[2]).split(","):
			var parts := piece.split(":")
			if parts.size() >= 2:
				shots.append([float(parts[0]), String(parts[1])])
	if args.size() > 3:
		lead_seconds = float(args[3])
	if args.size() > 4:
		tail_seconds = float(args[4])
	if args.size() > 5:
		show_overlay = int(args[5]) == 1
	# EMPTY ARGUMENTS DO NOT SURVIVE THE SHELL. Passing `""` for a positional
	# argument through bash to this executable DROPS it, which silently shifts
	# every later argument one place to the left — so `-` is the placeholder and
	# it means "none". (The first version of this used `""` and the debug flag
	# landed in the review-camera slot, which is a hard bug to see because
	# everything still ran.)
	if args.size() > 6 and String(args[6]).strip_edges() != "-":
		review_point = String(args[6]).strip_edges()
	if args.size() > 7 and String(args[7]).strip_edges() != "-":
		for piece in String(args[7]).split(","):
			if piece.strip_edges() != "":
				hide_props.append(piece.strip_edges())
	if args.size() > 8 and int(args[8]) == 1:
		debug_report = true

	DirAccess.make_dir_recursive_absolute(output_dir)
	_clear_existing_frames()
	print("vfx lab: effect=%s  out=%s" % [effect_id, output_dir])

	var window: Window = root
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	# Keep this window on top and out of the OS background-throttling path: when
	# another window covers it the render loop can stall, `frame_post_draw` never
	# fires, and the whole render hangs. This project lost a take to that.
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)
	DisplayServer.window_move_to_foreground()

	lab = load("res://scenes/vfx/SekaiVfxLab.tscn").instantiate() as Node3D
	if lab == null:
		push_error("could not instantiate SekaiVfxLab.tscn")
		quit(1)
		return
	window.add_child(lab)
	for _i in 4:
		await process_frame

	if not lab.start(effect_id):
		quit(1)
		return

	if not hide_props.is_empty():
		lab.debug_hide(hide_props)
	if debug_report:
		lab.debug_report()

	_build_overlay()

	print("window size: %s" % str(root.size))

	if not shots.is_empty():
		for shot in shots:
			_hold(float(shot[0]))
			# THREE DRAWS, NOT ONE. Some prototypes arm things on the frame they
			# are first asked for a time (a capture rig, a material rebuild), and
			# a still rendered one draw after the hold photographs the state
			# before its own `apply`. Two draws settle, the third is the picture.
			await _frame()
			await _frame()
			await _frame()
			_hold(float(shot[0]))
			await _frame()
			_save(float(shot[0]), String(shot[1]))
			print("  still %s @ %.2fs" % [String(shot[1]), float(shot[0])])
		print("wrote %d stills" % frame_index)
		quit()
		return

	var end := float(lab.duration())
	var lead := int(round(lead_seconds * FPS))
	var tail := int(round(tail_seconds * FPS))

	for _i in lead:
		_hold(0.0)
		await _frame()
		_save(0.0)

	var t := 0.0
	var guard := 0
	var first := frame_index
	while t <= end + 0.0001 and guard < 6000:
		_hold(t)
		await _frame()
		_save(t)
		t += STEP
		guard += 1
	var take_frames := frame_index - first
	print("  take: 0.00 -> %.2fs  frames %d..%d  (%d)" % [
		end, first, frame_index - 1, take_frames])

	for _i in tail:
		_hold(end)
		await _frame()
		_save(end)

	_write_manifest(end, lead, take_frames, tail)
	print("wrote %d frames (%.2fs)" % [frame_index, float(frame_index) / FPS])
	quit()


func _write_manifest(end: float, lead: int, take: int, tail: int) -> void:
	# WRITTEN, NOT ASSUMED. The encoder has to know where the clip's own beats are
	# in the frame sequence, and a number typed into the encoder is a second home
	# for a fact about the picture.
	var file := FileAccess.open(output_dir.path_join("manifest.txt"), FileAccess.WRITE)
	if file == null:
		push_error("could not write manifest.txt into " + output_dir)
		return
	file.store_line("EFFECT=%s" % effect_id)
	file.store_line("FPS=%d" % int(FPS))
	file.store_line("LEAD_FRAMES=%d" % lead)
	file.store_line("TAKE_FRAMES=%d" % take)
	file.store_line("TAIL_FRAMES=%d" % tail)
	file.store_line("T_END=%.3f" % end)
	file.close()


func _hold(t: float) -> void:
	lab.set_time(t)
	# Re-asserted every hold, not applied once: a prototype is free to call
	# `review_off()` inside its own `apply` — 11 天地合页 does exactly that when it
	# comes back to the spine — and a one-time switch would be silently undone.
	if review_point != "":
		lab.review_on(review_point)
	if overlay != null:
		overlay.text = "t = %.2f s      %s" % [t, lab.phase_name(t)]


func _clear_existing_frames() -> void:
	# Re-rendering into the same folder leaves stale frames from a longer previous
	# take, which then end up in the encoded video. The chain ultimate line lost a
	# run to exactly this.
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


# Two frames: one to let the world settle, one to land the draw.
func _frame() -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw


func _save(t: float, label: String = "") -> void:
	var path := output_dir.path_join("%s.png" % label) if label != "" \
		else output_dir.path_join("frame_%04d.png" % frame_index)
	var image := root.get_texture().get_image()
	if image == null:
		push_error("viewport texture returned no image at t=%.2f" % t)
		return
	var err := image.save_png(path)
	if err != OK:
		push_error("save_png failed (%d) for %s" % [err, path])
	frame_index += 1
	if frame_index % 60 == 0:
		print("  frame %d  t=%.2f" % [frame_index, t])


func _build_overlay() -> void:
	overlay_layer = CanvasLayer.new()
	overlay_layer.layer = 120
	overlay_layer.visible = show_overlay
	root.add_child(overlay_layer)
	var holder := PanelContainer.new()
	holder.set_anchors_preset(Control.PRESET_BOTTOM_WIDE, true)
	holder.offset_top = -56.0
	holder.offset_bottom = -14.0
	holder.offset_left = 340.0
	holder.offset_right = -340.0
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.03, 0.05, 0.60)
	style.content_margin_left = 18.0
	style.content_margin_right = 18.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	holder.add_theme_stylebox_override("panel", style)
	overlay_layer.add_child(holder)
	overlay = Label.new()
	overlay.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	overlay.add_theme_font_size_override("font_size", 19)
	holder.add_child(overlay)
