extends Node3D
# First-person weapon driver.
#
# This node no longer guesses a pose from the combat state with a fixed lerp.
# It reads the pose the CombatController sampled from the active sword move's
# Weight Curve (anticipation → strike → follow-through → settle) and applies a
# short exponential lag so the weapon still belongs to a body instead of being
# welded to the camera.
#
# When the Iaido / signature director is running it owns the transform directly
# and this node stays out of the way.

@onready var combat: CombatController = get_node("../../../../../../CombatController")
@onready var player: CharacterBody3D = combat.get_parent()
@onready var camera_feedback: CameraFeedbackController = player.get_node("CameraFeedbackController")
@onready var iaido: IaidoDirector = player.get_parent().get_node("IaidoDirector")

# Kept for IaidoDirector, which restores the weapon here after the ceremony.
const IDLE_POSITION := Vector3(0.52, -0.50, -0.94)
const IDLE_ROTATION := Vector3(0.0, 0.0, -0.18)

const BLADE_TINT := Color(0.84, 0.92, 1.0)
const VOID_TINT := Color(0.72, 0.85, 1.0)
const GLINT_TINT := Color(1.0, 0.98, 0.90)
const BLADE_LENGTH := 0.95
const TRAIL_SAMPLES := 14
const TRAIL_MIN_TIP_TRAVEL := 0.012

var click_flash: MeshInstance3D
var blade_material: StandardMaterial3D
var blade_part: MeshInstance3D
var grip_part: MeshInstance3D
var guard_part: MeshInstance3D
var void_rim: MeshInstance3D
var void_rim_material: StandardMaterial3D
var sheath_prop: MeshInstance3D
var glint_band: MeshInstance3D
var glint_material: StandardMaterial3D
var trail: MeshInstance3D
var trail_mesh: ImmediateMesh
var trail_material: StandardMaterial3D
var trail_history: Array[Vector3] = []
var blade_length := BLADE_LENGTH

var pose_position := IDLE_POSITION
var pose_rotation := IDLE_ROTATION
var pose_time := 0.0
var glint := 0.0
var root_inverse := Transform3D.IDENTITY

# How strongly the cold void behind the cut is reflected on the blade.
var void_exposure := 0.0 : set = set_void_exposure

# Set for the duration of the Iaido ceremony. The director owns the transform
# and the scabbard then, and the moveset's own scabbard prop would otherwise be
# left frozen at whatever pose it held when the ceremony started, rotating with
# the blade like a second sword.
var ceremony_mode := false


func set_ceremony_mode(enabled: bool) -> void:
	ceremony_mode = enabled
	if not enabled:
		return
	trail.visible = false
	trail_history.clear()
	click_flash.visible = false
	if sheath_prop != null:
		sheath_prop.visible = false
	if glint_band != null:
		glint_band.visible = false


func _ready() -> void:
	position = IDLE_POSITION
	rotation = IDLE_ROTATION
	_build_sword()
	_build_sheath()
	_build_glint()
	_build_trail()
	_build_click_flash()


func _build_sword() -> void:
	grip_part = _add_part("TEMP Grip", Vector3(0.10, 0.28, 0.10), Vector3(0, -0.18, 0), Color(0.16, 0.12, 0.09))
	guard_part = _add_part("TEMP Guard", Vector3(0.36, 0.07, 0.11), Vector3(0, 0.01, 0), Color(0.72, 0.62, 0.35))
	blade_part = _add_part("TEMP Blade", Vector3(0.075, BLADE_LENGTH, 0.038), Vector3(0, 0.52, 0), BLADE_TINT)
	blade_material = blade_part.mesh.material as StandardMaterial3D
	blade_length = BLADE_LENGTH
	_add_void_rim()


func _add_void_rim() -> void:
	# Back faces only: a cold halo that keeps the blade readable against the
	# darkened world without ever lighting it like a torch.
	var rim_mesh := BoxMesh.new()
	rim_mesh.size = Vector3(0.075, 1.02, 0.035)
	void_rim_material = StandardMaterial3D.new()
	void_rim_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	void_rim_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	void_rim_material.cull_mode = BaseMaterial3D.CULL_FRONT
	void_rim_material.albedo_color = Color(0.55, 0.74, 0.95, 0.0)
	rim_mesh.material = void_rim_material
	void_rim = MeshInstance3D.new()
	void_rim.name = "VoidRim"
	void_rim.mesh = rim_mesh
	void_rim.position = Vector3(0, 0.52, 0)
	void_rim.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	void_rim.visible = false
	add_child(void_rim)


func _build_sheath() -> void:
	# The scabbard belongs to the body, not the weapon: it never moves, so the
	# blade sliding into it reads as a real sheathe.
	#
	# Both the scabbard and the trail must live in the WeaponRoot's space, not
	# in the blade's own rotating space. They are parented to this node (the
	# scene is still being built during _ready, so the parent cannot accept new
	# children) and compensated back into root space every frame.
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.10, 0.62, 0.075)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.13, 0.115, 0.13)
	mesh.material = material
	sheath_prop = MeshInstance3D.new()
	sheath_prop.name = "Scabbard"
	sheath_prop.mesh = mesh
	sheath_prop.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sheath_prop.visible = false
	add_child(sheath_prop)


func _build_glint() -> void:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.09, BLADE_LENGTH, 0.09)
	glint_material = StandardMaterial3D.new()
	glint_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glint_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glint_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	glint_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	glint_material.albedo_color = Color(1.0, 0.97, 0.88, 0.0)
	mesh.material = glint_material
	glint_band = MeshInstance3D.new()
	glint_band.name = "EdgeGlint"
	glint_band.mesh = mesh
	glint_band.position = Vector3(0, 0.52, 0)
	glint_band.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	glint_band.visible = false
	add_child(glint_band)


func _build_trail() -> void:
	# A swept ribbon through the blade's own recent path. This is what makes a
	# first-person swing readable without a hand or arm model.
	trail_mesh = ImmediateMesh.new()
	trail_material = StandardMaterial3D.new()
	trail_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	trail_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	trail_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	trail_material.vertex_color_use_as_albedo = true
	trail = MeshInstance3D.new()
	trail.name = "BladeTrail"
	trail.mesh = trail_mesh
	trail.material_override = trail_material
	trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	trail.visible = false
	add_child(trail)


func _build_click_flash() -> void:
	var flash_mesh := SphereMesh.new()
	flash_mesh.radius = 0.045
	flash_mesh.height = 0.09
	var flash_material := StandardMaterial3D.new()
	flash_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flash_material.albedo_color = Color(1.0, 0.98, 0.86)
	click_flash = MeshInstance3D.new()
	click_flash.name = "Iaido Hilt Click"
	click_flash.mesh = flash_mesh
	click_flash.material_override = flash_material
	click_flash.position = Vector3(0.0, 0.02, 0.05)
	click_flash.visible = false
	add_child(click_flash)


func set_void_exposure(value: float) -> void:
	void_exposure = clampf(value, 0.0, 1.0)
	if void_rim == null or blade_material == null:
		return
	void_rim.visible = void_exposure > 0.01
	void_rim_material.albedo_color = Color(0.55, 0.74, 0.95, void_exposure * 0.55)
	blade_material.albedo_color = BLADE_TINT.lerp(VOID_TINT, void_exposure * 0.55)


func _add_part(part_name: String, size: Vector3, offset: Vector3, tint: Color) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = tint
	mesh.material = material
	var part := MeshInstance3D.new()
	part.name = part_name
	part.mesh = mesh
	part.position = offset
	add_child(part)
	return part


func _process(delta: float) -> void:
	if combat.state == CombatController.State.IAIDO or combat.state == CombatController.State.ULTIMATE:
		# The signature / ultimate directors drive the transform directly,
		# including freeze frames.
		trail.visible = false
		trail_history.clear()
		if ceremony_mode and sheath_prop != null:
			sheath_prop.visible = false
		return
	pose_time += delta
	var snapshot := combat.pose_snapshot()
	var target: Vector3 = snapshot.position
	var target_rotation: Vector3 = snapshot.rotation
	var intensity: float = snapshot.intensity
	# Exponential lag, not a tween: the authored acceleration curve survives,
	# and the blade still belongs to a body. 藏锋 is tight, 回风 is loose.
	var tau := 2.2 / maxf(float(snapshot.stiffness), 1.0)
	var follow := 1.0 - exp(-delta / tau)
	pose_position = pose_position.lerp(target, follow)
	pose_rotation = pose_rotation.lerp(target_rotation, follow)
	if intensity > 0.02:
		var amp := float(snapshot.tremor) * intensity
		pose_position += Vector3(
			sin(pose_time * 47.0),
			sin(pose_time * 39.0 + 1.7),
			sin(pose_time * 53.0 + 3.1),
		) * amp
	position = pose_position
	rotation = pose_rotation
	# Transform from this node's space back into the WeaponRoot's space, so the
	# scabbard and the trail can be authored in root space while parented here.
	root_inverse = Transform3D(Basis.from_euler(pose_rotation), pose_position).affine_inverse()
	_update_sheath(snapshot)
	_update_glint(snapshot, delta)
	_update_trail(snapshot)
	click_flash.visible = false


func _root_space(node: Node3D, target_position: Vector3, target_rotation: Vector3) -> void:
	node.transform = root_inverse * Transform3D(Basis.from_euler(target_rotation), target_position)


func _update_sheath(snapshot: Dictionary) -> void:
	var move: SwordMoveset = combat.moveset
	if move == null or not move.sheath_enabled:
		sheath_prop.visible = false
		if blade_part != null:
			blade_part.visible = true
			guard_part.visible = true
		return
	sheath_prop.visible = true
	_root_space(sheath_prop, move.sheath_scabbard_pose, move.sheath_scabbard_rot)
	var sheathed: float = snapshot.sheath
	# The blade is inside the scabbard, so only the hilt stays visible.
	var inside := sheathed > 0.55
	if blade_part != null:
		blade_part.visible = not inside
		guard_part.visible = true


func _update_glint(snapshot: Dictionary, delta: float) -> void:
	var wanted := 0.0
	if combat.edge_glint:
		wanted = 1.0
	elif combat.state == CombatController.State.CHARGE:
		wanted = 0.35 + combat.charge_ratio * 0.5
	elif float(snapshot.intensity) > 0.5:
		wanted = 0.16
	glint = lerpf(glint, wanted, minf(1.0, delta * 9.0))
	var active := glint > 0.02
	glint_band.visible = active and (blade_part == null or blade_part.visible)
	if active:
		glint_material.albedo_color = Color(GLINT_TINT.r, GLINT_TINT.g, GLINT_TINT.b, glint * 0.42)


func _update_trail(snapshot: Dictionary) -> void:
	var intensity: float = snapshot.intensity
	var origin: Vector3 = pose_position
	var tip: Vector3 = origin + (Basis.from_euler(pose_rotation) * Vector3.UP) * blade_length
	var base: Vector3 = origin + (Basis.from_euler(pose_rotation) * Vector3.UP) * -0.12
	if intensity > 0.4:
		trail_history.push_front(tip)
		if trail_history.size() > TRAIL_SAMPLES:
			trail_history.resize(TRAIL_SAMPLES)
	else:
		if trail_history.size() > 0:
			trail_history.pop_back()
			trail_history.pop_back()
	if trail_history.size() < 3:
		trail.visible = false
		return
	var travel := 0.0
	for i in range(1, trail_history.size()):
		travel = maxf(travel, trail_history[i - 1].distance_to(trail_history[i]))
	if travel < TRAIL_MIN_TIP_TRAVEL:
		trail.visible = false
		return
	_rebuild_trail(base, tip)
	_root_space(trail, Vector3.ZERO, Vector3.ZERO)
	trail.visible = true


func _rebuild_trail(base: Vector3, tip: Vector3) -> void:
	trail_mesh.clear_surfaces()
	var count := trail_history.size()
	var width: float = combat.moveset.trail_width
	trail_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in count:
		var fade := float(i) / float(count)
		var alpha := (1.0 - fade) * (1.0 - fade) * 0.42
		var sample_tip: Vector3 = trail_history[i]
		var sample_base := sample_tip + (tip - base).normalized() * -0.95
		# Widen very slightly toward the tip so the ribbon reads as a blade.
		trail_mesh.surface_set_color(Color(0.80, 0.90, 1.0, alpha * 0.35))
		trail_mesh.surface_add_vertex(sample_base)
		trail_mesh.surface_set_color(Color(0.94, 0.97, 1.0, alpha))
		trail_mesh.surface_add_vertex(sample_tip + (sample_tip - sample_base).normalized() * width)
	trail_mesh.surface_end()
