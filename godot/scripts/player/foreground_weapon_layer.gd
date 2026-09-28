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
# A subtree that opts OUT of the foreground treatment. See `_copy_meshes`.
const WORLD_DRAWN := &"weapon_drawn_in_world"
# The real sun, and the copy that lights the weapon's private world. See
# `_mirror_world_lighting`.
var _sun: DirectionalLight3D
var _sun_copy: DirectionalLight3D


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
	_mirror_world_lighting()
	_copy_meshes(weapon_root)
	_process(0.0)


# ===========================================================================
# §LIGHT — THE PRIVATE WORLD IS GIVEN THE WORLD'S OWN ENVIRONMENT AND SUN.
#
# READ THE CORRECTION BELOW BEFORE RE-DECIDING THAT THIS "DOES NOT WORK".
#
# The paragraph in the §OPT-OUT block further down says mirroring was tried and
# abandoned because a sun alone leaves a curved link dark. That conclusion was
# drawn from a test that could never have run. The original code guarded on
# `viewport.world_3d`, and `own_world_3d = true` NEVER puts anything in that
# COMPUTED property -- Godot keeps the private world in a separate slot that only
# `find_world_3d()` reaches. So `viewport.world_3d` was null for this viewport at
# every moment of its life, the assignment below errored on a null instance, the
# function stopped there, and the DirectionalLight3D underneath it was never
# added.
#
# MEASURED, on this Training Ground, before the fix:
#     find_world_3d()          -> valid
#     find_world_3d().environment -> NULL
#     directional lights in it -> NONE      (with 32 meshes copied into it)
# i.e. the private world had no Environment and no light of any kind.
#
# AND MEASURED AFTER ADDING ONE LIGHT BY HAND, same pose, same camera, same
# material (albedo 0.46, metallic 0.48, roughness 0.20):
#     assets_source/review/fp_sword/01_idle_eye.png         blade = solid black bar
#     assets_source/review/steel_sweep/5_fill_light_only.png blade = grey steel with
#                                                     a lit edge, spine and tsuba
# Nothing about the material changed between those two frames.
#
# WHY IT WAS INVISIBLE FOR SO LONG: everything on this layer used to be UNLIT.
# `temp_sword_visual.gd` builds its placeholder sword out of
# `SHADING_MODE_UNSHADED` materials, which render at full albedo under no light
# at all. The only lit mesh here was the chain's held bundle -- which is why V4
# recorded the bundle as CHARCOAL against a PALE rope drawn with the same
# `LINK_TINT`. That was never a chain bug: its light had been deleted. It became
# unmissable the moment a real PBR material went into the player's hand.
#
# `WORLD_DRAWN` is left alone and still works. With the lighting restored, a
# subtree no longer HAS to opt out to be lit -- the two worlds now share one
# Environment and one sun, so the chain's rope and handle can agree again if
# COMBAT wants to stop splitting them. That is COMBAT's call, not this file's.
func _mirror_world_lighting() -> void:
	var world := get_viewport().world_3d as World3D
	if world == null:
		return
	var private_world := viewport.find_world_3d()
	if private_world == null:
		return
	private_world.environment = world.environment
	# Searched from the SCENE, not from the World3D: a `World3D` is a Resource and
	# the sun is a node in the tree. `get_parent()` is the sandbox, which owns both.
	_sun = _find_sun(get_parent())
	if _sun == null:
		return
	_sun_copy = DirectionalLight3D.new()
	_sun_copy.name = "ForegroundSun"
	_sun_copy.shadow_enabled = false
	_sun_copy.light_energy = _sun.light_energy
	_sun_copy.light_color = _sun.light_color
	_sun_copy.light_indirect_energy = _sun.light_indirect_energy
	viewport.add_child(_sun_copy)


func _find_sun(node: Node) -> DirectionalLight3D:
	for child in node.get_children():
		var light := child as DirectionalLight3D
		if light != null:
			return light
		var found := _find_sun(child)
		if found != null:
			return found
	return null


# ===========================================================================
# §OPT-OUT — A SUBTREE THAT MAY NOT BE SPLIT ACROSS TWO WORLDS.
#
#     node.add_to_group(ForegroundWeaponLayer.WORLD_DRAWN)
#
# `own_world_3d = true` gives this viewport a World3D of its own, which is the point of
# the layer: the weapon is composited after the world's post-processing. What it also
# means is that the world the weapon lives in has NO Environment and NO lights, so
# everything moved onto `WEAPON_LAYER` renders under a black sky with nothing to
# reflect — and for a `metallic` material that is fatal, because a metal has no diffuse
# term and a metal that reflects nothing is its own silhouette.
#
# THE V4 CHAIN REVIEW IS WHERE THIS WAS FOUND, and it is worth writing down because the
# symptom lied. In one first-person frame, the SAME `LINK_TINT` with the SAME material
# read PALE on the thrown rope and CHARCOAL on the held bundle. The rope is a child of
# `ChainVisual` and stays on the default layer; the bundle is a child of `WeaponRoot`
# and was moved here. So the weapon looked like it had two kinds of steel in it, and
# half an hour went into the bundle's geometry, its normals and its albedo before the
# layer was suspected.
#
# A `SubViewport` cannot be given a real sun for free: mirroring the world's
# Environment and its DirectionalLight3D was tried first, and `transparent_bg = true`
# means the sky that supplies the AMBIENT is not renderable in this world either, so a
# bundle of curved links lit by a sun alone is still dark. The honest answer is that
# some subtrees must not be split — and the chain's is the clearest case there is:
# its HANDLE is in the fist and its ROPE is out in the world, they are drawn with one
# material, and no amount of lighting work makes two cameras agree about one object.
#
# The price is real and is accepted: a world-drawn handle can clip into geometry the
# player stands very close to. For this weapon that means pressing your face into a
# wall — which, for a 10m chain, is a trade worth making. What it buys is that the
# near end and the far end of one rope are lit by the same light, which is not a
# preference.
func _copy_meshes(node: Node) -> void:
	if node.is_in_group(WORLD_DRAWN):
		return
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
	# The sun's DIRECTION is the whole of what it contributes to shading, and a
	# directional light has no position -- so following the real one is one rotation,
	# not a rig. Kept in sync every frame because the arena's sun can be moved (the
	# Training Ground's DAY/NEUTRAL toggle does exactly that).
	if _sun_copy != null and is_instance_valid(_sun):
		_sun_copy.global_rotation = _sun.global_rotation
		_sun_copy.light_energy = _sun.light_energy
		_sun_copy.light_color = _sun.light_color
		_sun_copy.light_indirect_energy = _sun.light_indirect_energy
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
