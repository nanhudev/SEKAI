extends CanvasLayer
class_name ForegroundWeaponLayer
# A separate transparent 3D viewport is composited AFTER world post-processing.
# Gameplay nodes and hitboxes stay in the main world. Only visual meshes are copied.

const WEAPON_LAYER := 1 << 19
@onready var player: CharacterBody3D = get_parent().get_node("Player")
@onready var camera: Camera3D = player.get_node("CameraRig/LookPivot/MotionPivot/ShakePivot/Camera3D")
@onready var weapon_root: Node3D = player.get_node("CameraRig/LookPivot/MotionPivot/ShakePivot/WeaponRoot")
var viewport: SubViewport
var foreground_camera: Camera3D
var image_rect: TextureRect
var copies: Dictionary = {}
var original_layers: Dictionary = {}
var previous_camera_mask := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = 100
	layer = 8
	viewport = SubViewport.new()
	viewport.name = "WeaponViewport"
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.handle_input_locally = false
	add_child(viewport)
	foreground_camera = Camera3D.new()
	foreground_camera.near = 0.02
	viewport.add_child(foreground_camera)
	foreground_camera.make_current()
	image_rect = TextureRect.new()
	image_rect.name = "UncutWeaponForeground"
	image_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	image_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	image_rect.texture = viewport.get_texture()
	image_rect.stretch_mode = TextureRect.STRETCH_SCALE
	add_child(image_rect)
	previous_camera_mask = camera.cull_mask
	camera.cull_mask &= ~WEAPON_LAYER
	_copy_meshes(weapon_root)
	_process(0.0)


func _copy_meshes(node: Node) -> void:
	if node is MeshInstance3D:
		var source := node as MeshInstance3D
		original_layers[source] = source.layers
		source.layers = WEAPON_LAYER
		var copy := MeshInstance3D.new()
		copy.mesh = source.mesh
		copy.material_override = source.material_override
		copy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		viewport.add_child(copy)
		copies[source] = copy
	for child in node.get_children():
		_copy_meshes(child)


func _process(_delta: float) -> void:
	if viewport == null:
		return
	var size := Vector2i(get_viewport().get_visible_rect().size)
	if viewport.size != size:
		viewport.size = size.max(Vector2i(1, 1))
	foreground_camera.fov = camera.fov
	foreground_camera.keep_aspect = camera.keep_aspect
	var inverse_camera := camera.global_transform.affine_inverse()
	for source in copies:
		var copy: MeshInstance3D = copies[source]
		if is_instance_valid(source):
			copy.transform = inverse_camera * source.global_transform
			copy.visible = source.is_visible_in_tree()
		else:
			copy.visible = false


func _exit_tree() -> void:
	if is_instance_valid(camera):
		camera.cull_mask = previous_camera_mask
	for source in original_layers:
		if is_instance_valid(source):
			source.layers = original_layers[source]
