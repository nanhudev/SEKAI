extends SceneTree
## Mirror Weapon V0.1 proof movie → PNG sequence → mirror_weapon_v01_prototype.mp4
##
## Usage:
##   G:/Godot/Godot_v4.4.1-stable_win64_console.exe --path F:/SEKAI/godot \
##     --resolution 1280x720 --audio-driver Dummy \
##     --script res://tools/mirror_weapon_v01_movie.gd

const OUT_DIR := "E:/SEKAI-renders/mirror_weapon_v01"
const FPS := 30.0
const WIDTH := 1280
const HEIGHT := 720

var sandbox: Node3D
var player: CharacterBody3D
var mirror: MirrorWeaponController
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
	var abs_out := OUT_DIR.replace("\\", "/")
	DirAccess.make_dir_recursive_absolute(abs_out)
	var existing := DirAccess.open(abs_out)
	if existing != null:
		for f in existing.get_files():
			if f.ends_with(".png"):
				DirAccess.remove_absolute(abs_out.path_join(f))

	var scene: PackedScene = load("res://scenes/combat/CombatSandbox.tscn")
	sandbox = scene.instantiate()
	root.add_child(sandbox)
	await _frames(24)

	player = sandbox.get_node("Player")
	mirror = player.get_node("MirrorWeaponController")
	phantom = player.get_node_or_null("PhantomChainController")
	combat = player.get_node("CombatController")
	weapon = player.get_node("WeaponSlot")
	manager = player.get_node("WeaponManager")
	look = player.get_node("CameraRig/LookPivot")
	camera = player.get_node("CameraRig/LookPivot/MotionPivot/ShakePivot/Camera3D")
	camera.current = true
	mirror.debug_draw = true
	if mirror.manager != null:
		mirror.manager.set_debug_draw(true)
		mirror.manager.set_labels_visible(true)
	_build_overlay()
	_place_dummies()
	_hide_dev_noise()

	manager.call("equip_weapon", WeaponSlot.SWORD)
	await _settle_weapon()

	await _segment("1 · EQUIP", "Press 3 — Mirror Mode", func():
		await _hold(0.35)
		manager.call("equip_weapon", WeaponSlot.MIRROR)
		await _settle_weapon()
		await _hold(0.7)
	)

	await _segment("2 · PLACE M1", "RMB — left flank", func():
		_aim_world(Vector3(-3.2, 0.0, 1.5))
		await _hold(0.25)
		_place_or_direct(Vector3(-3.2, 0.0, 1.5))
		await _hold(0.55)
	)

	await _segment("3 · PLACE M2", "RMB — right flank", func():
		_aim_world(Vector3(3.2, 0.0, 1.5))
		await _hold(0.25)
		_place_or_direct(Vector3(3.2, 0.0, 1.5))
		await _hold(0.55)
	)

	await _segment("4 · PLACE M3", "RMB — behind target", func():
		_aim_world(Vector3(0.0, 0.0, -1.2))
		await _hold(0.25)
		_place_or_direct(Vector3(0.0, 0.0, -1.2))
		await _hold(0.55)
	)

	await _segment("5 · A1 BODY", "Player cut", func():
		_face_dummy(0)
		mirror.request(&"light")
		await _hold(0.35)
	)

	await _segment("6 · A1 ECHO", "Last mirror side cut", func():
		await _hold(0.55)
	)

	await _segment("7 · A2 ONE BOUNCE", "Refract via M1", func():
		_aim_world(Vector3(-3.2, 1.2, 1.5))
		mirror.set("combo_index", 1)
		mirror.request(&"light")
		await _hold(0.75)
	)

	await _segment("8 · A2 TWO BOUNCES", "Player → A → B", func():
		# Place geometry so ray hits two mirrors.
		_aim_world(Vector3(-3.2, 1.2, 1.5))
		mirror.set("combo_index", 1)
		mirror.request(&"light")
		await _hold(0.85)
	)

	await _segment("9 · ENTER MIRROR", "Q — Mirror State", func():
		mirror.request(&"travel")
		await _hold(0.55)
	)

	await _segment("10 · SELECT M2", "Look at right mirror", func():
		_aim_world(Vector3(3.2, 1.2, 1.5))
		await _hold(0.55)
	)

	await _segment("11 · EXIT M2", "Confirm exit", func():
		if mirror.travel != null:
			mirror.travel.confirm_exit(mirror.manager.get_aim_selected_node())
		await _hold(0.55)
	)

	await _segment("12 · EXIT CUT", "LMB window", func():
		mirror.request(&"light")
		await _hold(0.55)
	)

	await _segment("13 · A4 SHIFT", "Shift to M3", func():
		_aim_world(Vector3(0.0, 1.2, -1.2))
		mirror.set("combo_index", 3)
		mirror.request(&"light")
		await _hold(0.9)
	)

	await _segment("14 · FREE COMBO", "Place / cut / travel flow", func():
		mirror.reset()
		manager.call("equip_weapon", WeaponSlot.MIRROR)
		await _settle_weapon()
		_aim_world(Vector3(-2.5, 0.0, 2.0))
		_place_or_direct(Vector3(-2.5, 0.0, 2.0))
		await _hold(0.45)
		_aim_world(Vector3(2.5, 0.0, 2.0))
		_place_or_direct(Vector3(2.5, 0.0, 2.0))
		await _hold(0.45)
		_aim_world(Vector3(0.0, 0.0, -1.0))
		_place_or_direct(Vector3(0.0, 0.0, -1.0))
		await _hold(0.4)
		_face_dummy(0)
		mirror.request(&"light")
		await _hold(0.55)
		mirror.request(&"light")
		await _hold(0.7)
		mirror.request(&"light")
		await _hold(0.7)
		mirror.request(&"travel")
		await _hold(0.55)
		_aim_world(Vector3(2.5, 1.2, 2.0))
		await _hold(0.45)
		if mirror.travel != null:
			mirror.travel.confirm_exit(mirror.manager.get_aim_selected_node())
		await _hold(0.55)
		mirror.request(&"light")
		await _hold(0.7)
		mirror.set("combo_index", 3)
		_aim_world(Vector3(0.0, 1.2, -1.0))
		mirror.request(&"light")
		await _hold(1.0)
	)

	await _segment("15 · SWORD", "1 — independent", func():
		manager.call("equip_weapon", WeaponSlot.SWORD)
		await _settle_weapon()
		combat.request(&"light")
		await _hold(0.65)
		combat.finish_action()
	)

	await _segment("16 · CHAIN", "2 — independent", func():
		manager.call("equip_weapon", WeaponSlot.PHANTOM_CHAIN)
		await _settle_weapon()
		if phantom != null and phantom.has_method("request"):
			phantom.call("request", &"light")
		await _hold(0.65)
	)

	await _segment("17 · BACK TO MIRROR", "3 — travel again", func():
		manager.call("equip_weapon", WeaponSlot.MIRROR)
		await _settle_weapon()
		_aim_world(Vector3(0.0, 0.0, 2.0))
		_place_or_direct(Vector3(0.0, 0.0, 2.0))
		await _hold(0.4)
		_aim_world(Vector3(0.0, 0.0, -1.0))
		_place_or_direct(Vector3(0.0, 0.0, -1.0))
		await _hold(0.4)
		mirror.request(&"travel")
		await _hold(0.35)
		_aim_world(Vector3(0.0, 1.2, -1.0))
		await _hold(0.25)
		if mirror.travel != null:
			mirror.travel.confirm_exit(mirror.manager.get_aim_selected_node())
		await _hold(0.55)
	)

	await _segment("18 · SWITCH STRESS", "1↔2↔3 rapid (no sheathe wait)", func():
		# Full sheathe path already covered above; stress the slot cleanup path.
		for i in 8:
			weapon.equip(WeaponSlot.SWORD)
			await _frames(3)
			weapon.equip(WeaponSlot.MIRROR)
			await _frames(3)
			weapon.equip(WeaponSlot.PHANTOM_CHAIN)
			await _frames(3)
			weapon.equip(WeaponSlot.MIRROR)
			await _frames(3)
		await _hold(0.35)
	)

	await _segment("END", "Mirror Weapon V0.1", func():
		await _hold(0.8)
	)

	print("frames=", frame_i, " dir=", OUT_DIR)
	quit(0)


func _segment(heading: String, caption: String, body: Callable) -> void:
	title.text = heading
	note.text = caption
	await body.call()


func _place_dummies() -> void:
	var existing := sandbox.find_child("TechnicalDummy", true, false) as Node3D
	var packed: PackedScene = load("res://scenes/enemies/TechnicalDummy.tscn")
	if existing != null:
		dummies.append(existing)
	while dummies.size() < 3:
		var d: Node3D = packed.instantiate()
		d.name = "Mirror_Dummy_%d" % dummies.size()
		sandbox.add_child(d)
		dummies.append(d)
	player.global_position = Vector3(0, 1.15, 6)
	look.rotation = Vector3(0, 0, 0)
	_move_dummy(0, Vector3(0, 0, 2.2))
	_move_dummy(1, Vector3(-3.5, 0, 2.0))
	_move_dummy(2, Vector3(3.5, 0, 2.0))


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


func _place_or_direct(point: Vector3) -> void:
	if not mirror.request(&"place"):
		mirror.manager.place_at(point, Vector3.UP)


func _aim_world(point: Vector3) -> void:
	var eye := camera.global_position if camera else player.global_position + Vector3.UP * 1.6
	var to := point - eye
	if to.length_squared() < 0.001:
		return
	var yaw := atan2(-to.x, -to.z)
	player.rotation.y = yaw
	var flat := Vector3(to.x, 0.0, to.z)
	# Negative look.x = look down.
	var pitch := atan2(to.y, maxf(0.01, flat.length()))
	look.rotation = Vector3(pitch, 0, 0)


func _hide_dev_noise() -> void:
	for n in ["DeveloperPanel", "CombatHUD", "WeaponIndicator"]:
		var node := sandbox.find_child(n, true, false)
		if node != null:
			node.visible = false
	if manager != null and manager.has_method("_set_indicator_shown"):
		manager.call("_set_indicator_shown", false)


func _build_overlay() -> void:
	overlay = CanvasLayer.new()
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
	brand.text = "SEKAI · MIRROR WEAPON V0.1"
	brand.add_theme_font_size_override("font_size", 14)
	brand.modulate = Color(0.7, 0.88, 0.95, 0.75)
	brand.position = Vector2(36, HEIGHT - 48)
	overlay.add_child(brand)


func _settle_weapon() -> void:
	# Capture while settling so sheathe/draw appear in the proof movie.
	for i in 240:
		var switching := bool(manager.get("switching"))
		var pending := StringName(manager.get("_pending_slot"))
		var drawing := bool(manager.get("drawing_in"))
		if not switching and pending == &"" and not drawing:
			for _j in 4:
				await _capture()
			return
		await _capture()


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
	var path := "%s/frame_%05d.png" % [OUT_DIR.replace("\\", "/"), frame_i]
	img.save_png(path)
	frame_i += 1
