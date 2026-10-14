extends Node

## Boot flow for the three worlds.
##
## THERE ARE THREE DOORS, AND ONLY ONE OF THEM IS THE GAME.
##
##   MistvalePlaza   — the FIRST PLAYABLE SEQUENCE. Town square, Mira, the first
##                     sword, the first fight. This is what "开始游戏" opens.
##   MistvalePlayable — the region, as a playable space. This is the imported
##                     UE5 town (226 actors, 281 k triangles, one baked
##                     ConcavePolygonShape3D), carrying the REAL Player.tscn and
##                     the same director stack as the training compound. Its
##                     golden route was measured continuous end to end -- see
##                     tools/walk_mistvale_route.gd.
##   MistvaleRegion  — the LD-01 blockout: 600 m of procedural valley, roads,
##                     town, landmarks. It deliberately does NOT contain
##                     Player.tscn (see the header of ld_review_walker.gd for
##                     why), so it is geography rather than a playable space.
##                     It is no longer what the door opens, and it is not dead:
##                     `region_blockout_scene` still holds it, so a single
##                     inspector change brings back the blockout walker for
##                     comparing the art against the grey box.
##   TrainingGround  — the third door, labelled 进入战斗沙盒. It used to open
##                     CombatSandbox: a 24 m greybox arena with one dummy, no
##                     sky texture and no ground. It now opens the LD-02
##                     compound — 112 x 78 m of real ground, the ENV-01 kit,
##                     zones A-J, weapon racks, the combat court, the duel
##                     ring, the terrain park and a gate into the region — and
##                     it carries the SAME director stack (Iaido, Moment of No
##                     Moon, screen FX, audio, the dev panel), because it was
##                     built as a superset of the arena rather than a second
##                     arena. See REQ-1 in docs/ART_INTEGRATION_REQUESTS.md.
##
## `CombatSandbox.tscn` IS NOT DEAD and was not deleted: it is still the stage
## `scenes/combat/ChainUltimateLab.tscn` instances, and it is still where the
## two sandbox-only stages live (WindProps, ExecutionLab) that no training-ground
## zone hosts yet. Swap the one `combat_scene` default back to reach it.
##
## Everything below that pokes at "the world" therefore has to ask WHICH world
## is running. The combat-only nodes are reached through has_node() guards, not
## assumed: a region session has no IaidoDirector and no AudioStateController,
## and get_node() on a missing path would throw on the very first pause.

@export var plaza_scene: PackedScene = preload("res://scenes/world/MistvalePlaza.tscn")
@export var combat_scene: PackedScene = preload("res://scenes/training/TrainingGround.tscn")
## The region door now opens the IMPORTED UE5 TOWN, which is the world the game
## is actually set in. See the header: MistvaleRegion.tscn is still held by
## `region_blockout_scene`.
@export var region_scene: PackedScene = preload("res://scenes/world/StarterVillagePlayable.tscn")
## Kept reachable on purpose. This is the LD-01 blockout walker -- geography with
## no Player -- which is worth keeping only as the thing the imported town can be
## compared against. Swap it into `region_scene` to walk the grey box again.
@export var region_blockout_scene: PackedScene = preload("res://scenes/world/MistvaleRegion.tscn")

@onready var main_menu: Control = $MainMenu
@onready var pause_menu: Control = $PauseMenu
@onready var settings_menu: Control = $SettingsMenu

var plaza_world: Node3D
## The third door's world. Named `_world` rather than `combat_sandbox` because the
## sandbox is no longer what is behind that door (see the header): the old name
## would keep describing a scene this variable has not held since the door moved.
var combat_world: Node3D
var region_world: Node3D
var settings_return_to_pause := false


## The one world currently mounted, or null. They are never alive at once: each
## carries a WorldEnvironment and a key light, and two of either fighting over
## the same viewport is not a state worth supporting.
func active_world() -> Node3D:
	if plaza_world != null:
		return plaza_world
	if region_world != null:
		return region_world
	return combat_world


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	main_menu.new_game_pressed.connect(start_new_game)
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


## FIRST DOOR — the game. Opens the FIRST PLAYABLE SEQUENCE: the town square in
## MistvalePlaza, with the player at its centre, no weapon in hand, and the story
## director waiting on the player's own first move.
##
## THE BUILD IS SYNCHRONOUS AND SLOW, exactly as start_region()'s notice says:
## MistvalePlaza mounts MistvaleTerrain (heightfield + trimesh collision),
## MistvaleTown and MistvaleLandmarks, so the same eleven or so seconds apply.
## The caption is drawn and flushed BEFORE the build for the same reason.
##
## The fade-in is issued here rather than from the director because §2 wants the
## black to lift on the world, not on a line of dialogue: StoryUI starts opaque,
## so by the time the first subtitle is allowed to appear the player has already
## had his establishing seconds and can already look around.
func start_new_game() -> void:
	if active_world() != null:
		return
	main_menu.visible = false
	settings_menu.visible = false
	pause_menu.visible = false
	var notice := _build_loading_notice("正在生成雾栖镇 · 广场 …")
	add_child(notice)
	await get_tree().process_frame
	await get_tree().process_frame
	plaza_world = plaza_scene.instantiate() as Node3D
	add_child(plaza_world)
	move_child(plaza_world, 0)
	notice.queue_free()
	_enter_world()
	_apply_settings(0.0)
	if plaza_world.has_node("StoryUI"):
		plaza_world.get_node("StoryUI").call("fade_in", 2.4)


## THIRD DOOR — 进入战斗沙盒. The scene is the LD-02 training compound, which is
## where "can I hit something" is answered now: the arena's one dummy stood on the
## exact line the player walks down, so movement and combat could not be reviewed
## in the same run, and its floor, sky and dressing were a greybox (measured on
## PASS 4: 42% of the blade's line had no geometry at all and 36% of it was a flat
## face square-on to the eye, which is why a 15px displacement was invisible).
##
## No loading notice: unlike the plaza and the region, this scene builds from
## literals and a 12-piece kit rather than a heightfield, and the measured build
## is short enough that a caption would flash rather than inform.
func start_game() -> void:
	if active_world() != null:
		return
	combat_world = combat_scene.instantiate() as Node3D
	add_child(combat_world)
	move_child(combat_world, 0)
	_enter_world()
	_apply_settings(0.0)


## Second door: the region, not the arena. This now opens MistvalePlayable --
## the imported UE5 town -- and the player spawns at the golden route's southern
## end, on the road, facing the bridge, per the integration brief's §7-§10.
##
## THE BUILD IS SYNCHRONOUS AND SLOW, but for a different reason than it used to
## be. It no longer generates a heightfield; it loads a 2.7 MB glTF town and a
## 10 MB baked collision, then derives 22 anchors by raycasting. The notice is
## still drawn and flushed BEFORE the load starts, so the freeze has a caption.
func start_region() -> void:
	if active_world() != null:
		return
	main_menu.visible = false
	settings_menu.visible = false
	pause_menu.visible = false
	var notice := _build_loading_notice("正在载入新手村 …")
	add_child(notice)
	await get_tree().process_frame
	await get_tree().process_frame
	region_world = region_scene.instantiate() as Node3D
	add_child(region_world)
	move_child(region_world, 0)
	notice.queue_free()
	_enter_world()
	# The imported town mounts the real Player, so the settings sliders now mean
	# something here. They used to be inert in this door, because the door used
	# to open the blockout walker, which has no camera controller to configure.
	_apply_settings(0.0)


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
		plaza_world = null
		combat_world = null
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
	# Camera feel is a Player.tscn contract. MistvalePlaza and the training
	# compound both mount Player.tscn and therefore have it; MistvaleRegion
	# mounts LDReviewWalker instead and has neither, so the sliders are inert
	# there rather than fatal. Asked of the ACTIVE world, not of combat_world,
	# or the settings menu would silently do nothing in the game proper.
	var world := active_world()
	if world == null or not world.has_node("Player"):
		return
	var player: CharacterBody3D = world.get_node("Player")
	if not player.has_node("CameraFeedbackController"):
		return
	var camera_feedback: CameraFeedbackController = player.get_node("CameraFeedbackController")
	camera_feedback.base_fov = settings_menu.fov_slider.value
	camera_feedback.camera_motion_strength = settings_menu.motion_slider.value
	camera_feedback.camera_shake_strength = settings_menu.shake_slider.value
	player.set("mouse_sensitivity", settings_menu.sensitivity_slider.value)
