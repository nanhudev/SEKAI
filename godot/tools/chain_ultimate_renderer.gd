extends SceneTree
##
## CHAIN I ULTIMATE — the movie renderer.
##
## ---------------------------------------------------------------------------
## ONE CONTINUOUS TAKE, THEN THE SAME TAKE AGAIN AT HALF SPEED
## ---------------------------------------------------------------------------
##
## The clip is deliberately NOT a shot list and NOT a set of jump-cuts. This line
## already paid for the difference: a frame produced by being TOLD it is 5.70s is
## not the same frame as frame 183 of a take, because the second one arrived there
## through everything before it. So the renderer walks the ceremony clock forward
## from 0 and never moves it backwards.
##
## The delivered movie is:
##
##   1.0s lead-in   the room, untouched, nothing thrown
##   3.55s          THE SKILL, at normal speed, in one pass
##   1.0s tail      the restored room, whole again
##   7.1s           the SAME take re-sampled at 1/60s per frame — half speed
##
## The second half is the same pass of the same clock, just sampled twice as
## finely. Nothing is re-executed and nothing is re-triggered, so the slow section
## cannot disagree with the fast one about what happened.
##
## Usage:
##   godot --path godot --resolution 1280x720 --audio-driver Dummy \
##         --script res://tools/chain_ultimate_renderer.gd -- \
##         <output_dir> [overlay 0/1] [slowmo 0/1] [shot_list "t:label,..."] \
##         [ablations "nocapture,chain,anchor,hud"] [overrides "key=value,..."]
##
## The overrides are held IN MEMORY ONLY and the tuning resource is never written
## back. They are how one variable gets A/B'd against an otherwise identical
## frame, which is the only honest way to claim a value is or is not the reason
## something reads — and they are applied to the TUNING rather than to a shader
## material, because `apply()` rewrites every material uniform from the tuning on
## every frame and would silently undo anything set anywhere else.
##
## Then:
##   tools/encode_chain_ultimate_movie.sh <output_dir> <out.mp4> <ffmpeg> <godot>

const FPS := 30.0
const STEP := 1.0 / FPS
## Half speed for the second pass. Exactly 2, not 2.5, so every rendered frame of
## the slow section lands on an exact half-frame of the fast one.
const SLOW_FACTOR := 2.0
const SLOW_STEP := STEP / SLOW_FACTOR

const LEAD_SECONDS := 1.0
const TAIL_SECONDS := 1.0

var output_dir := ""
var frame_index := 0
var show_overlay := false
var slowmo := true
var shots: Array = []
var ablations := {}

var director: ChainUltimateDirector
var sheet: ChainRealitySheet
var lab: Node3D
var overlay: Label
var overlay_layer: CanvasLayer
var _capture_overridden := false
## Set once the live capture texture has been written out, so the dump happens on
## the frame the picture actually freezes rather than on every held frame after.
var _capture_dumped := false


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	output_dir = args[0] if args.size() > 0 \
		else ProjectSettings.globalize_path("res://../.render/chain_ultimate")
	show_overlay = args.size() > 1 and int(args[1]) == 1
	slowmo = args.size() <= 2 or int(args[2]) == 1
	if args.size() > 3 and String(args[3]).strip_edges() != "":
		for piece in String(args[3]).split(","):
			var parts := piece.split(":")
			shots.append([float(parts[0]), parts[1] if parts.size() > 1 else ""])
	if args.size() > 4:
		for flag in String(args[4]).split(","):
			if flag.strip_edges() != "":
				ablations[flag.strip_edges()] = true
	var overrides: Array = []
	if args.size() > 5 and String(args[5]).strip_edges() != "":
		for piece in String(args[5]).split(","):
			var kv := piece.split("=")
			if kv.size() == 2:
				overrides.append([kv[0].strip_edges(), float(kv[1])])

	var err := DirAccess.make_dir_recursive_absolute(output_dir)
	print("output_dir=", output_dir, " mkdir_err=", err)
	_clear_existing_frames()

	var window: Window = root
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	# Keep this window on top and out of the OS background-throttling path: when
	# another Godot window (the editor) covers it, the render loop can stall and
	# frame_post_draw never fires, which hangs the whole render.
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)
	DisplayServer.window_move_to_foreground()

	lab = load("res://scenes/combat/ChainUltimateLab.tscn").instantiate() as Node3D
	window.add_child(lab)
	for _i in 4:
		await process_frame

	director = lab.find_child("ChainUltimateDirector", true, false) as ChainUltimateDirector
	if director == null:
		push_error("the lab produced no ChainUltimateDirector")
		quit(1)
		return
	sheet = director.sheet
	var tuning := director.tuning
	for pair in overrides:
		tuning.set(String(pair[0]), pair[1])
		print("override %s = %s" % [pair[0], pair[1]])

	# ---- THE REVIEW HARNESS IS NOT PART OF THE PICTURE ---------------------
	# The HUD and the lab's beat strip are developer instruments. A frame anyone
	# watches is rendered without them; the renderer has its own overlay for the
	# cases where a caption is wanted, and it is off by default.
	_hide(lab.find_child("CombatHUD", true, false))
	if not ablations.has("hud"):
		_hide(lab.find_child("LabStrip", true, false))
	for flag in ablations:
		match String(flag):
			"chain":
				var visual: Node3D = lab.find_child("ChainVisual", true, false) as Node3D
				_hide(visual)
				print("ABLATION: chain OFF — does the film carry it alone?")
			"anchor":
				_hide(director.get("anchor_visual") as Node)
				print("ABLATION: void anchor OFF")
			"sheet":
				# THE FILM AND ITS WOUND BOTH GO, so what is left is the world the
				# film is a photograph of. This is the only ablation that measures
				# the film's COLOUR: while the film is still welded to the world the
				# two must be the same picture, so a frame pair taken at the rip —
				# one with this flag and one without — reads the transfer directly,
				# pixel for pixel, with nothing else changed.
				_hide(sheet.sheet_root)
				_hide(sheet.hole)
				print("ABLATION: sheet OFF — this is the world the film is a photograph of")
			"nocapture":
				# The single most valuable frame this file can produce: the SAME
				# membrane with the world's photograph replaced by flat grey. If
				# the skill still reads as a piece of the world coming off, then
				# the read is resting on the outline and not on the sampling, and
				# the whole capture rig is decoration.
				print("ABLATION: capture OFF — the film will be a flat card")

	_build_overlay()

	print("window size: ", root.size, " scale: ", root.content_scale_size)
	print("Rendering chain ultimate to: ", output_dir)
	print("Timeline: 0.00 -> %.2fs" % tuning.t_end)

	if not shots.is_empty():
		if not lab.trigger():
			push_error("the room refused to start")
			quit(1)
			return
		for shot in shots:
			_hold(float(shot[0]))
			# THREE DRAWS, NOT ONE, AND THIS IS NOT PADDING. The film's capture rig
			# freezes over three frames of its own (settle / UPDATE_ONCE /
			# UPDATE_DISABLED), and the first draw after the hold is a frame in
			# which the film is armed but not yet visible. A shot rendered with a
			# single draw photographs the state one step behind its own time —
			# which is how a shot list quietly lies about what is on screen.
			await _frame()
			await _frame()
			await _frame()
			_hold(float(shot[0]))
			await _frame()
			_save(float(shot[0]), String(shot[1]))
			print("  shot %s @ %.2fs" % [String(shot[1]), float(shot[0])])
			# DOES THE FILM AGREE WITH THE FRAME IT IS DRAWN IN. `capture_fov` is
			# the fov the photograph was taken through; this is the fov the same
			# frame is finally drawn through. Any gap between them is the film
			# showing a view that was never on screen.
			var live := director.camera
			if live != null and sheet != null:
				print("    DRIFT fov %.2f -> %.2f (%+.2f)   eye %s -> %s  (d=%.3fm)" % [
					sheet.capture_fov, live.fov, live.fov - sheet.capture_fov,
					sheet.capture_eye, live.global_position,
					live.global_position.distance_to(sheet.capture_eye)])
		print("Wrote %d shot frames" % frame_index)
		quit()
		return

	# ---- THE TAKE ---------------------------------------------------------
	if not lab.trigger():
		push_error("the room refused to start")
		quit(1)
		return

	var lead := int(round(LEAD_SECONDS * FPS))
	for _i in lead:
		_hold(0.0)
		await _frame()
		_save(0.0)

	# `await`, AND IT IS NOT OPTIONAL. `render_pass` contains `await`, which makes
	# it a COROUTINE: called without `await` it starts, runs to its first
	# `frame_post_draw`, and RETURNS — so the next line executes before a single
	# frame has been drawn. The first version of this file did exactly that, and
	# the result was three passes running CONCURRENTLY against one frame counter:
	# the tail's `_hold(t_end)` and the first pass's `_hold(0.00)` overwriting each
	# other between draws, every pass writing into the same `frame_%04d.png`
	# sequence, and `frame_index` advancing three times per frame.
	#
	# It did not look like a bug. It produced 90 frames, a four-line manifest, and
	# 60 of those frames were byte-identical to each other — a take in which the
	# ceremony had been replaced by the same still picture repeated. The one number
	# that gave it away was `PASS1_FRAMES=0`: a pass that walked the timeline from
	# 0.00 to 3.55s reporting that it wrote no frames at all.
	await render_pass(STEP, tuning.t_end)
	var pass1_frames := frame_index - lead

	var tail := int(round(TAIL_SECONDS * FPS))
	for _i in tail:
		_hold(tuning.t_end)
		await _frame()
		_save(tuning.t_end)

	var slow_start_frame := -1
	if slowmo:
		# THE SAME TAKE, SAMPLED TWICE AS FINELY. The director is a pure function
		# of the clock, so this is not a re-enactment: it is the same path with
		# more points on it. It is also why this is not a second `trigger()` — the
		# film's capture in particular must not be taken twice, and the whole
		# ceremony must not be able to differ from itself.
		slow_start_frame = frame_index
		await render_pass(SLOW_STEP, tuning.t_end)

	# The manifest is WRITTEN, not assumed. The encoder has to place every cue and
	# every slow-motion copy of every cue, and it can only do that if it knows
	# where the slow section starts — which is a fact about the picture. A number
	# typed into the encoder would be a second home for it, which is the drift
	# class this project already has one scar from.
	_write_manifest(tuning, lead, pass1_frames, tail, slow_start_frame)

	print("Wrote %d frames (%.2fs)" % [frame_index, float(frame_index) / FPS])
	quit()


func _write_manifest(
	tuning: ChainUltimateTuning, lead: int, pass1: int, tail: int, slow_start: int
) -> void:
	var file := FileAccess.open(output_dir + "/manifest.txt", FileAccess.WRITE)
	if file == null:
		push_error("could not write manifest.txt into " + output_dir)
		return
	file.store_line("FPS=%d" % int(FPS))
	file.store_line("LEAD_FRAMES=%d" % lead)
	file.store_line("PASS1_FRAMES=%d" % pass1)
	file.store_line("TAIL_FRAMES=%d" % tail)
	file.store_line("SLOW_START_FRAME=%d" % slow_start)
	file.store_line("SLOW_FACTOR=%.3f" % SLOW_FACTOR)
	file.store_line("T_END=%.3f" % tuning.t_end)
	file.close()


func render_pass(step: float, until: float) -> void:
	var t := 0.0
	var guard := 0
	var first := frame_index
	while t <= until + 0.0001 and guard < 4000:
		_hold(t)
		await _frame()
		_save(t)
		t += step
		guard += 1
	# THE PASS REPORTS ITS OWN SPAN. A take that silently wrote nothing is the one
	# failure this file cannot see from the outside: the frames on disk look like a
	# ceremony, the manifest has four numbers in it, and only the COUNT against the
	# timeline says whether the picture ever moved. So it is printed.
	print("  pass: step=%.4f until=%.2f  frames %d..%d  (%d)" % [
		step, until, first, frame_index - 1, frame_index - first])


func _hold(t: float) -> void:
	director.set_debug_hold(t)
	# The capture ablation is applied AFTER the hold, because the freeze happens
	# inside it — overriding before would be overwritten by `step_capture`.
	if ablations.has("nocapture") and not _capture_overridden \
			and sheet != null and sheet.built and sheet.frozen():
		var flat := Image.create(4, 4, false, Image.FORMAT_RGBA8)
		flat.fill(Color(0.42, 0.43, 0.46, 1.0))
		var uniform := sheet.get("sheet_material") as ShaderMaterial
		if uniform != null:
			uniform.set_shader_parameter("capture_tex", ImageTexture.create_from_image(flat))
			_capture_overridden = true
			print("  capture ablation applied at t=%.2f" % t)
	# THE SHEET ABLATION HAS TO BE RE-ASSERTED HERE FOR THE SAME REASON as the one
	# above, and for one more: `arm` hides the film and `step_capture` shows it
	# again the moment the picture freezes, so hiding it once when the flags are
	# parsed lasts exactly until the capture lands.
	if ablations.has("sheet") and sheet != null and sheet.built:
		var root := sheet.get("sheet_root") as Node3D
		var wound := sheet.get("hole") as Node3D
		if root != null:
			root.visible = false
		if wound != null:
			wound.visible = false
	# THE ONE DIAGNOSTIC THAT SEPARATES "THE PICTURE IS WRONG" FROM "THE SHADING ON
	# TOP OF IT IS WRONG". `capture_tex` is a live viewport texture, so it can be
	# read back and written out — and the film's own appearance can then be compared
	# against the thing it claims to be showing, instead of being argued about.
	if ablations.has("dumpcapture") and sheet != null and sheet.frozen() and not _capture_dumped:
		var vp := sheet.get("capture_viewport") as SubViewport
		if vp != null:
			var img := vp.get_texture().get_image()
			img.save_png(output_dir.path_join("_capture.png"))
			_capture_dumped = true
			print("  capture dumped: %dx%d -> _capture.png" % [img.get_width(), img.get_height()])


func _hide(node: Node) -> void:
	if node is CanvasLayer:
		(node as CanvasLayer).visible = false
	elif node is Node3D:
		(node as Node3D).visible = false


func _clear_existing_frames() -> void:
	# Re-rendering into the same folder leaves stale frames from a longer previous
	# take, which then end up in the encoded video.
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
		print("  frame %d  t=%.2f" % [frame_index, t])


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

	var title := Label.new()
	title.text = "CHAIN I · VOID ANCHOR"
	title.add_theme_font_size_override("font_size", 14)
	title.modulate = Color(0.55, 0.68, 0.82, 0.80)
	row.add_child(title)

	overlay = Label.new()
	overlay.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	overlay.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	overlay.add_theme_font_size_override("font_size", 17)
	row.add_child(overlay)


func _label(t: float) -> String:
	if t < 0.0:
		return "RESTORED"
	var phase := director.phase_name(t) if director != null else ""
	return "t = %.2f s      %s" % [t, phase]
