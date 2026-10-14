extends SceneTree
## Phantom Chain V0.1 proof movie → PNG sequence, then encode to phantom_chain_v01.mp4
##
## Usage:
##   Godot_v4.4.1-stable_win64_console.exe --path godot --resolution 1280x720 \
##     --audio-driver Dummy --script res://tools/phantom_chain_v01_movie.gd

const OUT_DIR := "res://../.render/phantom_chain_v01"
const FPS := 30.0
const WIDTH := 1280
const HEIGHT := 720

var sandbox: Node3D
var player: CharacterBody3D
var phantom: Node
var combat: CombatController
var weapon: WeaponSlot
var manager: Node
var look: Node3D
var camera: Camera3D
var dummies: Array[Node3D] = []

var frame_i := 0
var overlay: CanvasLayer
var title: Label
var note: Label


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var abs_out := ProjectSettings.globalize_path(OUT_DIR)
	DirAccess.make_dir_recursive_absolute(abs_out)
	for f in DirAccess.get_files_at(abs_out):
		if f.ends_with(".png"):
			DirAccess.remove_absolute(abs_out.path_join(f))

	var scene: PackedScene = load("res://scenes/combat/CombatSandbox.tscn")
	sandbox = scene.instantiate()
	root.add_child(sandbox)
	await _frames(20)

	player = sandbox.get_node("Player")
	phantom = player.get_node("PhantomChainController")
	combat = player.get_node("CombatController")
	weapon = player.get_node("WeaponSlot")
	manager = player.get_node("WeaponManager")
	look = player.get_node("CameraRig/LookPivot")
	camera = player.get_node("CameraRig/LookPivot/MotionPivot/ShakePivot/Camera3D")
	camera.current = true
	_build_overlay()
	_place_dummies()
	_hide_dev_noise()

	# Start sword so sheathe→chain is visible.
	manager.call("equip_weapon", WeaponSlot.SWORD)
	await _settle_weapon()

	await _segment("1 · EQUIP", "Press 2 — Chain Rule Mode", func():
		await _hold(0.6)
		manager.call("equip_weapon", WeaponSlot.PHANTOM_CHAIN)
		await _settle_weapon()
		await _hold(1.4)
	)

	await _segment("2 · IDLE", "Faint phantom links waiting", func():
		await _hold(2.8)
	)

	await _segment("3 · A1 SWEEP", "Path rule — materialize arc", func():
		_face_dummy(0)
		_move_dummy(0, player.global_position + _forward() * 3.5)
		phantom.call("request", &"light")
		await _hold(1.1)
	)

	await _segment("4 · A2 SNAP", "Curve → straight tension", func():
		phantom.call("request", &"light")
		await _hold(0.9)
	)

	await _segment("5 · A3 BIND", "Define connection", func():
		_face_dummy(1)
		_move_dummy(1, player.global_position + _forward() * 3.2)
		phantom.set("combo_index", 2)
		phantom.call("request", &"light")
		await _hold(1.2)
	)

	await _segment("6 · TENSION", "Target walks — rule tightens", func():
		var target := dummies[1]
		var start_p := target.global_position
		var away := start_p + _forward() * 4.0
		var t := 0.0
		while t < 2.0:
			target.global_position = start_p.lerp(away, clampf(t / 1.6, 0.0, 1.0))
			await _hold(0.05)
			t += 0.05
		await _hold(0.7)
	)

	await _segment("7 · PULL", "Attack during bind", func():
		phantom.call("request", &"light")
		await _hold(1.0)
	)

	await _segment("8 · A4 ORBIT", "Space itself draws the chains", func():
		phantom.call("reset")
		weapon.equip(WeaponSlot.PHANTOM_CHAIN)
		await _frames(6)
		phantom.set("combo_index", 3)
		_face_dummy(0)
		phantom.call("request", &"light")
		await _hold(1.4)
	)

	await _segment("9 · FULL COMBO", "A1 → A2 → A3 → A4", func():
		phantom.call("reset")
		weapon.equip(WeaponSlot.PHANTOM_CHAIN)
		await _frames(6)
		_face_dummy(0)
		_move_dummy(0, player.global_position + _forward() * 3.0)
		phantom.call("request", &"light")
		await _hold(0.7)
		phantom.call("request", &"light")
		await _hold(0.55)
		phantom.call("request", &"light")
		await _hold(0.9)
		if int(phantom.get("combo_index")) != 0:
			phantom.set("combo_index", 3)
			phantom.call("request", &"light")
		await _hold(1.2)
	)

	await _segment("10 · SWORD", "1 — independent system", func():
		manager.call("equip_weapon", WeaponSlot.SWORD)
		await _settle_weapon()
		await _hold(0.5)
		combat.request(&"light")
		await _hold(1.0)
		combat.finish_action()
	)

	await _segment("11 · BACK TO CHAIN", "2 — no leftover sword state", func():
		manager.call("equip_weapon", WeaponSlot.PHANTOM_CHAIN)
		await _settle_weapon()
		phantom.call("request", &"light")
		await _hold(1.0)
	)

	await _segment("END", "Phantom Chain V0.1", func():
		await _hold(1.2)
	)

	print("frames=", frame_i, " dir=", ProjectSettings.globalize_path(OUT_DIR))
	quit(0)


func _segment(heading: String, caption: String, body: Callable) -> void:
	title.text = heading
	note.text = caption
	await body.call()


func _place_dummies() -> void:
	# Reuse sandbox dummy if present; spawn extras for surround / mid.
	var existing := sandbox.find_child("TechnicalDummy", true, false) as Node3D
	var packed: PackedScene = load("res://scenes/enemies/TechnicalDummy.tscn")
	if existing != null:
		dummies.append(existing)
	while dummies.size() < 4:
		var d: Node3D = packed.instantiate()
		d.name = "PC_Dummy_%d" % dummies.size()
		sandbox.add_child(d)
		dummies.append(d)
	# Close / mid / surround layout in front of player.
	player.global_position = Vector3(0, 1.15, 6)
	look.rotation = Vector3(0, 0, 0)
	_move_dummy(0, Vector3(0, 0, 2.5))
	_move_dummy(1, Vector3(0, 0, 1.0))
	_move_dummy(2, Vector3(-2.8, 0, 3.5))
	_move_dummy(3, Vector3(2.8, 0, 3.5))


func _move_dummy(i: int, pos: Vector3) -> void:
	if i < 0 or i >= dummies.size():
		return
	dummies[i].global_position = pos


func _face_dummy(i: int) -> void:
	if i < 0 or i >= dummies.size():
		return
	var to := dummies[i].global_position - player.global_position
	to.y = 0.0
	if to.length_squared() < 0.001:
		return
	player.rotation.y = atan2(-to.x, -to.z)
	look.rotation = Vector3(deg_to_rad(-6.0), 0, 0)


func _forward() -> Vector3:
	var f := -player.global_transform.basis.z
	f.y = 0.0
	return f.normalized()


func _hide_dev_noise() -> void:
	for n in ["DeveloperPanel", "CombatHUD", "WeaponIndicator", "DevOverlay", "HelpPanel"]:
		var node := sandbox.find_child(n, true, false)
		if node != null:
			node.visible = false
	# CombatSandbox draws a left help column as a CanvasLayer child — hide all UI layers.
	for child in sandbox.get_children():
		if child is CanvasLayer and child.name != "PhantomMovieOverlay":
			child.visible = false
	if manager != null:
		var ind: CanvasLayer = manager.get_node_or_null("WeaponIndicator") as CanvasLayer
		if ind != null:
			ind.visible = false


func _build_overlay() -> void:
	overlay = CanvasLayer.new()
	overlay.name = "PhantomMovieOverlay"
	overlay.layer = 20
	root.add_child(overlay)
	title = Label.new()
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	title.add_theme_constant_override("shadow_offset_x", 2)
	title.add_theme_constant_override("shadow_offset_y", 2)
	title.position = Vector2(36, 28)
	overlay.add_child(title)
	note = Label.new()
	note.add_theme_font_size_override("font_size", 18)
	note.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	note.position = Vector2(36, 68)
	overlay.add_child(note)
	var brand := Label.new()
	brand.text = "SEKAI · PHANTOM CHAIN V0.1"
	brand.add_theme_font_size_override("font_size", 14)
	brand.modulate = Color(0.75, 0.85, 0.95, 0.7)
	brand.position = Vector2(36, HEIGHT - 48)
	overlay.add_child(brand)


func _settle_weapon() -> void:
	var wanted: StringName = manager.call("current_weapon")
	for i in 360:
		wanted = manager.call("current_weapon")
		var sheathe_done := float(manager.call("sheathe_progress")) >= 0.999
		var switching := bool(manager.get("switching"))
		var drawing := bool(manager.get("drawing_in"))
		if sheathe_done and not switching and not drawing:
			if wanted == WeaponSlot.SWORD and float(combat.equip_blend) < 0.999:
				await _frames(1)
				continue
			await _frames(4)
			return
		await _frames(1)


func _hold(seconds: float) -> void:
	var frames := int(ceil(seconds * FPS))
	for i in frames:
		await _capture()


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _capture() -> void:
	await physics_frame
	var img := camera.get_viewport().get_texture().get_image()
	if img == null:
		return
	if img.get_width() != WIDTH or img.get_height() != HEIGHT:
		img.resize(WIDTH, HEIGHT, Image.INTERPOLATE_BILINEAR)
	var path := "%s/frame_%05d.png" % [OUT_DIR, frame_i]
	img.save_png(path)
	frame_i += 1
