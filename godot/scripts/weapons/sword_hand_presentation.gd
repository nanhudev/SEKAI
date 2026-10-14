extends Node3D
# Stylized glove geometry; real sword and saya remain the transform owners.
const CONFIG = preload("res://resources/tuning/SwordPresentationConfig.tres")
var sword: Node3D
var combat: CombatController
var director: IaidoDirector
var right: Node3D
var left: Node3D
var upper_right: MeshInstance3D
var fore_right: MeshInstance3D
var fore_left: MeshInstance3D
var upper_left: MeshInstance3D
var idle_clock := 0.0
var channels: Node3D
var animator: AnimationPlayer
var _clip: StringName = &""
var glove: StandardMaterial3D
var cuff: StandardMaterial3D

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = 90
	sword = get_parent()
	combat = sword.combat
	director = sword.iaido
	glove = StandardMaterial3D.new()
	glove.albedo_color = CONFIG.glove_color
	glove.roughness = 0.92
	cuff = StandardMaterial3D.new()
	cuff.albedo_color = CONFIG.cuff_color
	cuff.roughness = 0.86
	right = build_glove("RightGlove", 1.0)
	left = build_glove("LeftGlove", -1.0)
	upper_right = capsule("RightUpperArm", cuff, 0.045, 0.20)
	upper_left = capsule("LeftUpperArm", cuff, 0.045, 0.20)
	fore_right = capsule("RightForearm", cuff, 0.038, 0.20)
	fore_left = capsule("LeftForearm", cuff, 0.038, 0.20)
	for forearm in [fore_right,fore_left]:
		var sleeve := CylinderMesh.new()
		sleeve.top_radius = 0.029
		sleeve.bottom_radius = 0.040
		sleeve.height = 0.20
		sleeve.radial_segments = 16
		forearm.mesh = sleeve
	channels = Node3D.new()
	channels.name = "PoseChannels"
	add_child(channels)
	animator = AnimationPlayer.new()
	animator.name = "SwordAnimationPlayer"
	add_child(animator)
	build_clips()

func capsule(label: String, material: Material, radius: float, height: float, parent: Node3D = null) -> MeshInstance3D:
	if parent == null:
		parent = self
	var node := MeshInstance3D.new()
	node.name = label
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = maxf(height, radius * 2.0)
	mesh.radial_segments = 12
	mesh.rings = 4
	node.mesh = mesh
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)
	return node

func build_glove(label: String, side: float) -> Node3D:
	var hand := Node3D.new()
	hand.name = label
	add_child(hand)
	var palm := capsule("Palm", glove, 0.022, 0.09, hand)
	palm.position = Vector3(side * 0.038, 0, 0.0)
	var fingers := Node3D.new()
	fingers.name = "Fingers"
	hand.add_child(fingers)
	# Four curled fingers around a 30 x 22 mm handle; no finger enters the grip.
	for i in 4:
		var y := -0.030 + i * 0.019
		var points := [Vector3(side*0.036,y,0.020),Vector3(side*0.010,y,0.027),Vector3(-side*0.024,y,0.016),Vector3(-side*0.026,y,-0.006)]
		for j in 3:
			var segment := capsule("Finger_%d_%d" % [i,j],glove,0.007,0.02,fingers)
			place_segment(segment,points[j],points[j+1])
	var thumb := capsule("Thumb",glove,0.010,0.054,hand)
	place_segment(thumb,Vector3(side*0.044,0.024,-0.010),Vector3(side*0.012,0.046,-0.018))
	var wrist := capsule("Cuff",cuff,0.034,0.067,hand)
	var leather := CylinderMesh.new()
	leather.top_radius = 0.027
	leather.bottom_radius = 0.032
	leather.height = 0.055
	leather.radial_segments = 16
	wrist.mesh = leather
	wrist.position = Vector3(side*0.039,-0.072,0.012)
	return hand

func place_segment(mesh: MeshInstance3D, a: Vector3, b: Vector3) -> void:
	var axis := b-a
	mesh.position = (a+b)*0.5
	mesh.basis = Basis(Quaternion(Vector3.UP,axis.normalized()))
	mesh.scale = Vector3(1,axis.length()/float(mesh.mesh.get("height")),1)

func build_clips() -> void:
	# Editable native clips take precedence; the authored fallback creates them.
	if ResourceLoader.exists("res://resources/animations/SwordPresentation.tres"):
		animator.add_animation_library(&"",load("res://resources/animations/SwordPresentation.tres"))
		animator.root_node = NodePath("..")
		return
	animator.add_animation_library(&"",build_library())
	animator.root_node = NodePath("..")

static func build_library() -> AnimationLibrary:
	var library := AnimationLibrary.new()
	# Time/shoulder roll/elbow load: anticipation -> acceleration -> carry -> settle.
	var profiles := {
		&"Idle":[[0,1.15,2.3,3.45,4.6],[0,0.003,0,-0.003,0],[Vector3.ZERO,Vector3(0,0.001,0),Vector3.ZERO,Vector3(0,-0.001,0),Vector3.ZERO]],
		&"Draw Sword":[[0,0.35,0.75,0.95,1.38,1.75],[0,-0.045,-0.02,-0.02,0.035,0],[Vector3.ZERO,Vector3(-0.035,0.025,-0.025),Vector3(0,0.01,-0.04),Vector3(0,0.01,-0.04),Vector3(0.03,0.015,-0.025),Vector3.ZERO]],
		&"Sheath Sword":[[0,0.35,0.95,1.38,1.75],[0,0.04,0.015,-0.025,0],[Vector3.ZERO,Vector3(0.02,0.01,-0.025),Vector3(-0.02,0.015,-0.025),Vector3(-0.035,0.02,0),Vector3.ZERO]],
		&"Attack A1":[[0,0.07,0.13,0.245,0.34,0.57],[0,-0.09,-0.13,0.14,0.10,0],[Vector3.ZERO,Vector3(-0.035,-0.025,0.035),Vector3(-0.065,-0.02,0.045),Vector3(0.075,0.025,-0.045),Vector3(0.04,-0.015,-0.025),Vector3.ZERO]],
		&"Attack A2":[[0,0.15,0.29,0.42,0.68],[0,0.15,-0.18,-0.12,0],[Vector3.ZERO,Vector3(0.09,-0.03,0.05),Vector3(-0.09,0.03,-0.065),Vector3(-0.06,-0.025,-0.02),Vector3.ZERO]],
		&"Attack A3":[[0,0.10,0.20,0.38,0.53,0.81],[0,-0.06,-0.10,0.10,0.08,0],[Vector3.ZERO,Vector3(-0.03,-0.055,0.025),Vector3(-0.055,-0.10,0.04),Vector3(0.015,0.10,-0.05),Vector3(0.04,0.075,-0.02),Vector3.ZERO]],
		&"Attack A4":[[0,0.25,0.53,0.69,1.03],[0,-0.22,0.24,0.17,0],[Vector3.ZERO,Vector3(-0.11,-0.025,0.07),Vector3(0.12,0.015,-0.07),Vector3(0.10,-0.03,0.04),Vector3.ZERO]],
		&"Heavy":[[0,0.24,0.42,0.57,0.92],[0,-0.06,0.15,0.10,0],[Vector3.ZERO,Vector3(0,0.15,0.08),Vector3(0,-0.13,-0.09),Vector3(0,-0.07,0.04),Vector3.ZERO]],
		&"Parry":[[0,0.06,0.14,0.20],[0,-0.04,0.025,0],[Vector3.ZERO,Vector3(0,-0.015,0.045),Vector3(0,0,-0.01),Vector3.ZERO]],
		&"Iaido":[[0,0.55,0.75,0.85,1.18,1.65,2.35,2.75],[0,-0.07,-0.07,0.14,0.12,0.04,-0.035,0],[Vector3.ZERO,Vector3(-0.045,-0.035,0.02),Vector3(-0.045,-0.035,0.02),Vector3(0.07,0,-0.06),Vector3(0.055,-0.025,-0.04),Vector3(-0.01,-0.035,0),Vector3(-0.035,-0.025,0),Vector3.ZERO]],
		&"Skill":[[0,0.10,0.24,0.38,0.55],[0,-0.065,0.10,0.06,0],[Vector3.ZERO,Vector3(-0.03,-0.025,0.035),Vector3(0.05,0.025,-0.06),Vector3(0.03,0.015,0.02),Vector3.ZERO]],
	}
	for name in profiles:
		var profile: Array = profiles[name]
		var animation := Animation.new()
		animation.length = float(profile[0][-1])
		if name == &"Idle": animation.loop_mode = Animation.LOOP_LINEAR
		for path in ["RightGlove/Fingers:scale","LeftGlove/Fingers:scale","PoseChannels:rotation","PoseChannels:position"]:
			var track := animation.add_track(Animation.TYPE_VALUE)
			animation.track_set_path(track,NodePath(path))
			animation.track_set_interpolation_type(track,Animation.INTERPOLATION_CUBIC)
			for i in profile[0].size():
				var value := Vector3.ZERO
				if path.ends_with("scale"):
					var grip := 0.994 if name == &"Idle" and i%2==1 else (0.980 if i>0 and i<profile[0].size()-1 else 1.0)
					value = Vector3(1,1,grip)
				elif path.ends_with("rotation"):
					value = Vector3(0,float(profile[1][i])*0.3,float(profile[1][i]))
				else: value = profile[2][i]
				animation.track_insert_key(track,float(profile[0][i]),value)
		library.add_animation(name,animation)
	return library

func _process(delta: float) -> void:
	if not is_instance_valid(sword) or not is_instance_valid(combat):
		return
	visible = combat._holds_sword()
	if not visible:
		return
	var clock := combat.presentation_clock()
	var move: SwordMove = clock.get("move")
	var clip: StringName = &"Idle"
	var progress := 0.0
	var in_iaido := is_instance_valid(director) and director.active
	if in_iaido:
		clip = &"Iaido"
		progress = director.elapsed / maxf(director.tuning.restore_end,0.001)
	elif combat.state == CombatController.State.CHARGE and combat.active_move != null and combat.active_move.id == &"uni_heavy":
		clip = &"Heavy"
		progress = minf(combat.state_time/0.18,1.0)*combat.active_move.startup/combat.active_move.total_time()*0.985
	elif combat.state == CombatController.State.PARRY or combat.state == CombatController.State.BLOCK:
		clip = &"Parry"
		progress = clampf(combat.state_time/0.2,0,1)
	elif move != null:
		var pose_clock := float(clock.get("time",0.0))
		var tail_start := move.startup+move.strike
		if move.id in SwordBasic.light_chain() and pose_clock>tail_start:
			pose_clock = tail_start+(pose_clock-tail_start)/maxf(combat.recovery_scale(),0.001)
		progress = clampf(pose_clock/maxf(move.total_time(),0.001),0,1)
		if move.id == SwordBasic.EQUIP:
			clip = &"Sheath Sword" if clock.get("reverse",false) else &"Draw Sword"
		elif move.id == &"uni_heavy":
			clip = &"Heavy"
		else:
			var index := SwordBasic.light_chain().find(move.id)
			clip = StringName("Attack A%d" % (index+1)) if index >= 0 else &"Skill"
	if clip == &"Idle":
		idle_clock += delta
		progress = fposmod(idle_clock,4.6)/4.6
	if _clip != clip:
		animator.play(clip)
		_clip = clip
	animator.seek(progress*animator.current_animation_length,true)
	right.transform = Transform3D(Basis.IDENTITY,Vector3(0,-0.075,0))
	var weapon_root := sword.get_parent() as Node3D
	var inverse := global_transform.affine_inverse()
	var wrist := sword.transform * Vector3(0.038,-0.147,0.012)
	var elbow := Vector3(0.48 + channels.rotation.z*0.4,-0.64,-0.18) + channels.position
	root_segment(fore_right,weapon_root,wrist,elbow,inverse)
	root_segment(upper_right,weapon_root,elbow,Vector3(0.26 + channels.rotation.z*0.20,-0.72,0.18),inverse)
	var saya: Node3D = director.ceremony_scabbard if in_iaido else combat.saya_rig
	var both_hands := not in_iaido and clip not in [&"Draw Sword",&"Sheath Sword"]
	left.visible = both_hands or (is_instance_valid(saya) and saya.is_visible_in_tree())
	fore_left.visible = left.visible
	upper_left.visible = left.visible
	if left.visible:
		var held := sword.global_transform * Transform3D(Basis.IDENTITY,Vector3(0,-0.19,0)) if both_hands else saya.global_transform * Transform3D(Basis.IDENTITY,Vector3(0,0.10,0))
		if not in_iaido and clip in [&"Draw Sword",&"Sheath Sword"]:
			var support := smoothstep(0.80,1.0,combat.equip_blend)
			var grip := sword.global_transform * Transform3D(Basis.IDENTITY,Vector3(0,-0.19,0))
			held = held.interpolate_with(grip,support)
		# Grip constraints stay exact at speed; inertia belongs in the elbows.
		left.global_transform = held
		var left_wrist := weapon_root.global_transform.affine_inverse() * (left.global_transform * Vector3(-0.039,-0.072,0.012))
		var left_elbow := Vector3(-0.40,-0.68,-0.10) + Vector3(-channels.position.x*0.65,channels.position.y*0.35,channels.position.z*0.5)
		root_segment(fore_left,weapon_root,left_wrist,left_elbow,inverse)
		root_segment(upper_left,weapon_root,left_elbow,Vector3(-0.26 - channels.rotation.z*0.15,-0.72,0.18),inverse)

func root_segment(mesh: MeshInstance3D, frame: Node3D, a: Vector3, b: Vector3, inverse: Transform3D) -> void:
	place_segment(mesh,a,b)
	mesh.transform = inverse * frame.global_transform * mesh.transform
