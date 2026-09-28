extends Node

## Boot flow for both worlds.
##
## THERE ARE TWO DOORS, AND THEY ARE NOT THE SAME WORLD.
##
## CombatSandbox is the combat instrument: a 24 m arena, a training dummy, the
## Iaido directors, the audio state controller. MistvaleRegion is the region
## itself — 600 m of valley, roads, town, landmarks — and it deliberately does
## NOT contain Player.tscn (see the header of ld_review_walker.gd for why).
##
## Everything below that pokes at "the world" therefore has to ask WHICH world
## is running. The combat-only nodes are reached through has_node() guards, not
## assumed: a region session has no IaidoDirector and no AudioStateController,
## and get_node() on a missing path would throw on the very first pause.

@export var combat_scene: PackedScene = preload("res://scenes/combat/CombatSandbox.tscn")
@export var region_scene: PackedScene = preload("res://scenes/world/MistvaleRegion.tscn")

@onready var main_menu: Control = $MainMenu
@onready var pause_menu: Control = $PauseMenu
@onready var settings_menu: Control = $SettingsMenu

var combat_sandbox: Node3D
var region_world: Node3D
var settings_return_to_pause := false


## The one world currently mounted, or null. Both are never alive at once: they
## each carry a WorldEnvironment and a key light, and two of either fighting
## over the same viewport is not a state worth supporting.
func active_world() -> Node3D:
	if region_world != null:
		return region_world
	return combat_sandbox


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	main_menu.start_pressed.connect(start_game)
	main_menu.region_pressed.connect(start_region)
	main_menu.settings_pressed.connect(func() -> void: _open_settings(false))
	main_menu.exit_pressed.connect(exit_game)
	pause_menu.resume_pressed.connect(resume_game)
	pause_menu.settings_pressed.connect(func() -> void: _open_settings(true))
	pause_menu.title_pressed.connect(return_to_title)
	pause_menu.exit_pressed.connect(exit_game)
	settings_menu.back_pressed.connect(_close_settings)
	settings_menu.fov_slider.value_changed.connect(_apply_settings)
	settings_menu.sensitivity_slider.value_changed.connect(_apply_settings)
	settings_menu.motion_slider.value_changed.connect(_apply_settings)
	settings_menu.shake_slider.value_changed.connect(_apply_settings)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and active_world() != null and not settings_menu.visible:
		if pause_menu.visible:
			resume_game()
		else:
			pause_game()
		get_viewport().set_input_as_handled()


func start_game() -> void:
	if active_world() != null:
		return
	combat_sandbox = combat_scene.instantiate() as Node3D
	add_child(combat_sandbox)
	move_child(combat_sandbox, 0)
	_enter_world()
	_apply_settings(0.0)


## Second door: the region, not the arena. Spawn is the East Forest end of
## ROAD_SPINE (200, 320) — the masterplan's MISTVALE REVEAL vista, so the first
## thing the player sees is the valley opening up rather than a wall of trees.
##
## THE BUILD IS SYNCHRONOUS AND SLOW. Measured with tools/build_smoke.gd: the
## region takes ~11 s to build (terrain heightfield + 1028 ms of flora meshes +
## town + landmarks). Every one of those builders runs inside _ready(), so
## clicking this button freezes the process for eleven seconds with the menu
## already gone — which reads as a hang, not a load. The notice below is drawn
## and flushed BEFORE the build starts, so the freeze at least has a caption.
func start_region() -> void:
	if active_world() != null:
		return
	main_menu.visible = false
	settings_menu.visible = false
	pause_menu.visible = false
	var notice := _build_loading_notice("正在生成雾谷 · 地形 / 植被 / 城镇 / 地标 …")
	add_child(notice)
	await get_tree().process_frame
	await get_tree().process_frame
	region_world = region_scene.instantiate() as Node3D
	add_child(region_world)
	move_child(region_world, 0)
	notice.queue_free()
	_enter_world()


func _build_loading_notice(text: String) -> CanvasLayer:
	var layer := CanvasLayer.new()
	layer.layer = 9
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.05, 0.06, 1.0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(bg)
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", Color(0.78, 0.86, 0.87))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(label)
	return layer


func _enter_world() -> void:
	main_menu.visible = false
	pause_menu.visible = false
	settings_menu.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func pause_game() -> void:
	var world := active_world()
	if world == null:
		return
	# Combat-only. The region has neither of these nodes.
	if world.has_node("IaidoDirector"):
		var iaido: IaidoDirector = world.get_node("IaidoDirector")
		if iaido.active:
			iaido.finish_iaido()
	if world.has_node("AudioStateController"):
		world.get_node("AudioStateController").pause_world_audio()
	world.process_mode = Node.PROCESS_MODE_DISABLED
	pause_menu.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func resume_game() -> void:
	var world := active_world()
	if world == null:
		return
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	if world.has_node("AudioStateController"):
		world.get_node("AudioStateController").resume_world_audio()
	pause_menu.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func return_to_title() -> void:
	var world := active_world()
	if world != null:
		if world.has_node("IaidoDirector"):
			var iaido: IaidoDirector = world.get_node("IaidoDirector")
			if iaido.active:
				iaido.finish_iaido()
		if world.has_node("AudioStateController"):
			world.get_node("AudioStateController").resume_world_audio()
		world.queue_free()
		combat_sandbox = null
		region_world = null
	Engine.time_scale = 1.0
	pause_menu.visible = false
	settings_menu.visible = false
	main_menu.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func exit_game() -> void:
	get_tree().quit()


func _open_settings(from_pause: bool) -> void:
	settings_return_to_pause = from_pause
	main_menu.visible = false
	pause_menu.visible = false
	settings_menu.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _close_settings() -> void:
	settings_menu.visible = false
	pause_menu.visible = settings_return_to_pause
	main_menu.visible = not settings_return_to_pause


func _apply_settings(_value: float) -> void:
	# Camera feel is a Player.tscn contract. The region mounts LDReviewWalker
	# instead, which has no CameraFeedbackController, so the sliders are inert
	# there rather than fatal.
	if combat_sandbox == null or not combat_sandbox.has_node("Player"):
		return
	var player: CharacterBody3D = combat_sandbox.get_node("Player")
	var camera_feedback: CameraFeedbackController = player.get_node("CameraFeedbackController")
	camera_feedback.base_fov = settings_menu.fov_slider.value
	camera_feedback.camera_motion_strength = settings_menu.motion_slider.value
	camera_feedback.camera_shake_strength = settings_menu.shake_slider.value
	player.set("mouse_sensitivity", settings_menu.sensitivity_slider.value)
