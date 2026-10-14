extends SceneTree
##
## CHAIN AUDIO PASS 01 - first person, in the Chain Lab, with the sound design the
## player will actually hear.
##
## WHY A SEPARATE RENDERER instead of another tour in combat_movie_renderer.gd:
## that file belongs to the combat line and is being edited by another session.
## This take exists to answer ONE question - "does the chain have a voice now?" -
## so it is its own small tool and its own file, and it can be deleted without
## touching anybody else's work.
##
## BEATS, in the order the brief asks for them (§PART O):
##   IDLE -> A1 左甩 -> A2 快右左 -> A3 直抛 -> MISS/RETRACT -> WALL BITE ->
##   ENEMY HIT (light) -> ENEMY HIT (heavy) -> RECOIL
##
## Real time, because a chain beat is driven by input and its windows run on its
## own clock; the measured frame rate is written next to the frames so the encoder
## can play the clip back at true speed.
##
## Usage:
##   godot --path godot --resolution 1280x720 --audio-driver Dummy \
##         --script res://tools/chain_audio_movie.gd -- <out_dir>

const OUT_DEFAULT := "res://../.render/chain_audio"
const PLAYER_Y := 0.9
const LOOK_DOWN := -8.0
# The lab's own geometry (chain_lab.gd): the deck runs z -43..-19, the wall a throw
# is meant to end on is at z -42.6, and a fixed ANCHOR stands at (6.5, 0, -26) -
# which a sweep treats as a wall. The open stand is therefore clear of the anchor
# and short of the far wall, so the only beat that can find a surface is the one
# that is about finding a surface.
const OPEN_STAND := Vector3(0.0, PLAYER_Y, -30.0)
const WALL_STAND := Vector3(0.0, PLAYER_Y, -34.5)
const PARKED := Vector3(0.0, 0.0, 300.0)

var output_dir := ""
var frame_index := 0
var sandbox: Node3D
var player: CharacterBody3D
var combat: CombatController
var weapon: WeaponSlot
var chain: ChainDirector
var lab: ChainLab
var look_pivot: Node3D
var camera: Camera3D
var label: Label
var caption := ""


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	output_dir = String(args[0]) if args.size() > 0 else ProjectSettings.globalize_path(OUT_DEFAULT)
	DirAccess.make_dir_recursive_absolute(output_dir)
	_clear_frames()

	var window: Window = root
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	# A covered window stops firing frame_post_draw and the capture loop hangs.
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)
	DisplayServer.window_move_to_foreground()
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"), true)

	sandbox = load("res://scenes/combat/CombatSandbox.tscn").instantiate() as Node3D
	window.add_child(sandbox)
	for i in 3:
		await process_frame

	player = sandbox.get_node("Player") as CharacterBody3D
	combat = player.get_node("CombatController") as CombatController
	weapon = player.get_node("WeaponSlot") as WeaponSlot
	chain = player.get_node("ChainDirector") as ChainDirector
	look_pivot = player.get_node("CameraRig/LookPivot") as Node3D
	camera = player.get_node("CameraRig/LookPivot/MotionPivot/ShakePivot/Camera3D") as Camera3D
	lab = sandbox.get_node_or_null("ChainLab") as ChainLab

	# The stage belongs to the person playing, not to the recording.
	for name in [&"DeveloperPanel", &"ParryDebugOverlay", &"CombatHUD"]:
		var node := sandbox.get_node_or_null(NodePath(String(name)))
		if node is CanvasLayer or node is Control:
			(node as Node).set("visible", false)
	var fg := sandbox.get_node_or_null("ForegroundWeaponLayer")
	if fg != null:
		fg.set("visible", true)   # the chain's HANDLE lives on this layer
	if chain != null:
		chain.debug_readout = false
		# The weapon narrates itself, so the log says what the frames show.
		chain.message.connect(func(text: String) -> void: print("      · " + text))
	var dummy := sandbox.get_node_or_null("TechnicalDummy")
	if dummy != null:
		dummy.set("attack_cooldown", 9999.0)
	player.set("unlimited_resources", true)

	_equip_chain()
	_build_caption()
	print("rendering chain audio pass 01 to: ", output_dir)

	start_take()
	await _run()


# ------------------------------------------------------------------- the take

var beats: Array = []

func start_take() -> void:
	beats = [
		[0.60, "待机 · IDLE  链条在手里", func() -> void:
			_stand(OPEN_STAND, 0.0, LOOK_DOWN)
			_park_targets()],
		[2.40, "A1 · 左甩  HEAVY WIDE SWEEP", func() -> void:
			_park_targets()
			_light(&"ch_sweep")],
		[3.20, "A2 · 快右左  TWO BEATS, ONE INPUT", func() -> void: _light(&"ch_return")],
		[4.00, "A3 · 直抛  FORWARD RELEASE + PAY-OUT", func() -> void: _light(&"ch_throw")],
		[6.60, "落空 · MISS → 回收 RETRACT", func() -> void: pass],
		[7.60, "转身 · 对准石墙", func() -> void:
			_stand(WALL_STAND, 0.0, -4.0)
			_park_targets()],
		[8.30, "A3 · 撞墙 WALL BITE (CONTACT / BITE / TENSION)",
			func() -> void: _light(&"ch_throw")],
		[10.80, "回头 · 对准敌人", func() -> void:
			_stand(OPEN_STAND, 0.0, -6.0)
			_place_target(ElementLibrary.WEIGHT_LIGHT, 3.4)],
		[11.50, "命中轻敌 · ENEMY CONTACT", func() -> void: _light(&"ch_sweep")],
		[13.40, "命中重敌 · HEAVY TARGET", func() -> void:
			_place_target(ElementLibrary.WEIGHT_HEAVY, 3.6)],
		[13.90, "", func() -> void: _light(&"ch_sweep")],
		[15.90, "回收 · 链条回到手里", func() -> void:
			_stand(OPEN_STAND, 0.0, -12.0)],
	]


func _run() -> void:
	var begin := Time.get_ticks_msec()
	var next := 0
	var duration := 18.2
	while true:
		var t := float(Time.get_ticks_msec() - begin) / 1000.0
		while next < beats.size() and t >= float(beats[next][0]):
			caption = String(beats[next][1])
			var action: Callable = beats[next][2]
			action.call()
			next += 1
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		_save()
		if t >= duration:
			break
	var elapsed := float(Time.get_ticks_msec() - begin) / 1000.0
	var fps := float(frame_index) / maxf(elapsed, 0.001)
	print("frames=%d  wall=%.2fs  -> ENCODE_FPS=%.3f" % [frame_index, elapsed, fps])
	_write_fps(fps)
	quit()


# ------------------------------------------------------------------ driving

func _stand(at: Vector3, yaw_deg: float, pitch_deg: float) -> void:
	player.global_position = at
	player.velocity = Vector3.ZERO
	player.rotation = Vector3(0.0, deg_to_rad(yaw_deg), 0.0)
	if look_pivot != null:
		look_pivot.rotation.x = deg_to_rad(pitch_deg)


func _light(expect: StringName) -> void:
	if chain == null or not chain.request(&"light"):
		print("    !! light refused (wanted %s)" % String(expect))
		return
	var move := chain.active_move
	var played: StringName = move.id if move != null else &""
	if played != expect:
		print("    !! played %s but this take claims %s" % [String(played), String(expect)])
	else:
		print("    %s" % String(played))


func _place_target(weight: StringName, distance: float) -> void:
	if lab == null:
		print("    !! no ChainLab")
		return
	_park_targets(weight)
	var target := lab.target_for(weight)
	if target == null:
		print("    !! no %s target" % String(weight))
		return
	var forward := -player.global_transform.basis.z
	target.global_position = player.global_position + forward * distance
	target.global_position.y = 0.0
	target.rotation = Vector3.ZERO
	target.call("reset_dummy")
	target.set("attack_cooldown", 9999.0)


## The lab stands three weights in one place so the weight table can be compared.
## A take about ONE beat needs the other two out of reach, or a single contact
## lands as a drum roll and the clip claims something the sound is not doing.
func _park_targets(keep: StringName = &"") -> void:
	if lab == null:
		return
	for weight in [ElementLibrary.WEIGHT_LIGHT, ElementLibrary.WEIGHT_MEDIUM,
			ElementLibrary.WEIGHT_HEAVY]:
		if weight == keep:
			continue
		var node := lab.target_for(weight)
		if node != null:
			node.global_position = PARKED


func _equip_chain() -> void:
	var mgr := player.get_node_or_null("WeaponManager")
	if mgr != null and mgr.has_method("equip_weapon"):
		mgr.call("equip_weapon", &"chain")
	else:
		weapon.equip(&"chain")
	combat.finish_action()


# ------------------------------------------------------------------ capture

func _save() -> void:
	var image := root.get_texture().get_image()
	if image == null:
		push_error("viewport returned no image at frame %d" % frame_index)
		return
	_update_caption()
	var err := image.save_png("%s/frame_%04d.png" % [output_dir, frame_index])
	if err != OK:
		push_error("save_png failed (%d) at frame %d" % [err, frame_index])
	frame_index += 1
	if frame_index % 60 == 0:
		print("    frame %d" % frame_index)


func _write_fps(fps: float) -> void:
	var file := FileAccess.open("%s/fps.txt" % output_dir, FileAccess.WRITE)
	if file == null:
		return
	file.store_string("%.4f\n" % fps)
	file.close()


func _clear_frames() -> void:
	var dir := DirAccess.open(output_dir)
	if dir == null:
		return
	var removed := 0
	for file in dir.get_files():
		if file.get_extension().to_lower() == "png" or file == "fps.txt":
			dir.remove(file)
			removed += 1
	if removed > 0:
		print("cleared %d stale files" % removed)


# The caption is the film's voice, not a debug dump: labels stay, numbers do not
# (§46/§51). It is drawn INTO the frame on purpose - "A1 左甩" over a sweep is the
# difference between a clip that shows the chain moving and a clip that makes a
# claim, and a claim is the only thing worth reviewing.
func _build_caption() -> void:
	label = Label.new()
	label.position = Vector2(48.0, 44.0)
	label.add_theme_font_size_override("font_size", 26)
	label.add_theme_color_override("font_color", Color(0.96, 0.94, 0.90))
	label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.7))
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	root.add_child(label)


func _update_caption() -> void:
	if label != null:
		label.text = caption
