extends CanvasLayer
class_name IaidoGlassLayer
# Physical glass shards get their own transparent 3D viewport composited ABOVE
# the world-split shader, so the shards are never torn or displaced by the cut.
#
# Only 8-20 primary shards with real thickness. The fine debris and the crack
# network live in the screen shader; spawning hundreds of meshes here would
# just burn overdraw budget for nothing.

const SHARD_Z := -0.55

@onready var player: CharacterBody3D = get_parent().get_node("Player")
@onready var camera: Camera3D = player.get_node("CameraRig/LookPivot/MotionPivot/ShakePivot/Camera3D")

var viewport: SubViewport
var foreground_camera: Camera3D
var image_rect: TextureRect
var shards: Array[Node3D] = []
var shard_data: Array[Dictionary] = []
var active := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 7
	viewport = SubViewport.new()
	viewport.name = "GlassShardViewport"
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	viewport.handle_input_locally = false
	add_child(viewport)
	foreground_camera = Camera3D.new()
	foreground_camera.near = 0.02
	viewport.add_child(foreground_camera)
	foreground_camera.make_current()
	image_rect = TextureRect.new()
	image_rect.name = "GlassShardForeground"
	image_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	image_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	image_rect.texture = viewport.get_texture()
	image_rect.stretch_mode = TextureRect.STRETCH_SCALE
	add_child(image_rect)


func build(tuning: IaidoTuning) -> void:
	for shard in shards:
		if is_instance_valid(shard):
			shard.queue_free()
	shards.clear()
	shard_data.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260927
	var count := clampi(tuning.shard_count, 8, 20)
	var first_wave := int(ceilf(float(count) * 0.6))
	var angle := deg_to_rad(tuning.cut_angle_degrees)
	var tangent := Vector2(cos(angle), -sin(angle))
	var normal := Vector2(-sin(angle), -cos(angle))
	for i in count:
		var u := (float(i) + 0.5) / float(count) * 2.0 - 1.0
		var delay := lerpf(tuning.shard_min_delay, tuning.shard_max_delay, rng.randf())
		var side := 1.0 if i % 2 == 0 else -1.0
		var burst_time: float
		var hover_time: float
		if i < first_wave:
			burst_time = tuning.shard_burst + delay
			hover_time = tuning.slow_sheathe_start
		else:
			burst_time = tuning.collapse_start + 0.02 + delay
			hover_time = tuning.restore_start
		var data := {
			"u": u,
			"jitter": rng.randf_range(-0.16, 0.16),
			"side": side,
			"burst": burst_time,
			"hover": maxf(0.05, hover_time - burst_time),
			"speed": rng.randf_range(0.55, 1.35),
			"drift": rng.randf_range(-0.55, 0.55),
			"depth": rng.randf_range(-0.40, 0.40),
			"angular": Vector3(rng.randf_range(-7.0, 7.0), rng.randf_range(-7.0, 7.0), rng.randf_range(-6.0, 6.0)),
			"spin": rng.randf_range(0.0, TAU),
			"alpha": rng.randf_range(0.22, 0.42),
			"tangent": tangent,
			"normal": normal,
		}
		var holder := _make_shard(rng.randf_range(0.06, 0.16), rng.randf_range(0.04, 0.13))
		data["core_material"] = holder.get_child(0).get("mesh").material
		data["rim_material"] = holder.get_child(1).get("mesh").material
		shard_data.append(data)
		shards.append(holder)


func _make_shard(width: float, height: float) -> Node3D:
	var holder := Node3D.new()
	holder.name = "Shard"
	holder.visible = false
	viewport.add_child(holder)

	var core_mesh := BoxMesh.new()
	core_mesh.size = Vector3(width, height, 0.012)
	var core_material := StandardMaterial3D.new()
	core_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	core_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	core_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	core_material.albedo_color = Color(0.74, 0.85, 0.95, 0.20)
	core_mesh.material = core_material
	var core := MeshInstance3D.new()
	core.name = "Pane"
	core.mesh = core_mesh
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(core)

	# Back faces only: reads as a bright ground edge around each pane.
	var rim_mesh := BoxMesh.new()
	rim_mesh.size = Vector3(width * 1.10, height * 1.14, 0.010)
	var rim_material := StandardMaterial3D.new()
	rim_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rim_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rim_material.cull_mode = BaseMaterial3D.CULL_FRONT
	rim_material.albedo_color = Color(0.93, 0.96, 1.00, 0.70)
	rim_mesh.material = rim_material
	var rim := MeshInstance3D.new()
	rim.name = "Edge"
	rim.mesh = rim_mesh
	rim.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(rim)
	return holder


func stage(time: float, tuning: IaidoTuning) -> void:
	if shards.is_empty():
		active = false
		if viewport != null:
			viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		return
	var any_visible := false
	var restore := IaidoTuning.ease_in_out(IaidoTuning.span(time, tuning.restore_start, tuning.restore_end))
	var rect_size := get_viewport().get_visible_rect().size
	var aspect := rect_size.x / maxf(rect_size.y, 1.0)
	var half_h := tan(deg_to_rad(maxf(camera.fov, 1.0) * 0.5)) * absf(SHARD_Z)
	var reach := maxf(half_h * aspect, half_h) * 0.92
	var k := maxf(tuning.shard_drag, 0.001)
	var terminal := Vector3(0.0, -tuning.shard_gravity, 0.0) / k
	var collapse := IaidoTuning.span(time, tuning.collapse_start, tuning.collapse_end)

	for i in shards.size():
		var holder := shards[i]
		var data: Dictionary = shard_data[i]
		var local := time - float(data["burst"])
		if local < 0.0 or restore >= 1.0:
			holder.visible = false
			continue
		var tangent: Vector2 = data["tangent"]
		var normal: Vector2 = data["normal"]
		var side: float = data["side"]
		var origin := Vector3(
			(tangent.x * float(data["u"]) + normal.x * float(data["jitter"])) * reach,
			(tangent.y * float(data["u"]) + normal.y * float(data["jitter"])) * reach,
			SHARD_Z
		)
		var velocity := Vector3(
			normal.x * side * float(data["speed"]) + tangent.x * float(data["drift"]),
			normal.y * side * float(data["speed"]) + tangent.y * float(data["drift"]) + 0.20,
			-float(data["depth"]) * 0.25
		)
		# Shards hang for 30-80ms before gravity and the burst take them.
		var local_clamped := minf(local, float(data["hover"]))
		var decay := (1.0 - exp(-k * local_clamped)) / k
		var position := origin + (velocity - terminal) * decay + terminal * local_clamped
		# Reality collapse peak kicks the debris outward once more.
		position += Vector3(normal.x * side, normal.y * side, 0.0) * collapse * 0.22
		if restore > 0.0:
			position = position.lerp(origin, restore)
		holder.position = position
		var angular: Vector3 = data["angular"]
		holder.rotation = Vector3(
			float(data["spin"]) + angular.x * decay,
			angular.y * decay * 0.7,
			angular.z * decay
		)
		var fade := clampf(local / 0.06, 0.0, 1.0) * (1.0 - restore)
		holder.scale = Vector3.ONE * lerpf(1.0, 0.25, restore)
		_apply_alpha(data, float(data["alpha"]) * fade)
		holder.visible = fade > 0.01
		any_visible = any_visible or holder.visible

	active = any_visible
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if any_visible else SubViewport.UPDATE_DISABLED


func _apply_alpha(data: Dictionary, alpha: float) -> void:
	var core_material := data.get("core_material") as StandardMaterial3D
	if core_material != null:
		core_material.albedo_color = Color(0.74, 0.85, 0.95, clampf(alpha, 0.0, 1.0))
	var rim_material := data.get("rim_material") as StandardMaterial3D
	if rim_material != null:
		rim_material.albedo_color = Color(0.93, 0.96, 1.00, clampf(alpha * 1.8, 0.0, 1.0))


func reset() -> void:
	for shard in shards:
		if is_instance_valid(shard):
			shard.visible = false
	active = false
	if viewport != null:
		viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED


func _process(_delta: float) -> void:
	if viewport == null:
		return
	var size := Vector2i(get_viewport().get_visible_rect().size)
	if viewport.size != size:
		viewport.size = size.max(Vector2i(1, 1))
	foreground_camera.fov = camera.fov
	foreground_camera.keep_aspect = camera.keep_aspect
