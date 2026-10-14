extends Node
# A sword drill host inside the existing court. No environment rebuilding.
var player: CharacterBody3D
var combat: CombatController
var debug_label: Label
var debug_on := false

func _ready() -> void:
	call_deferred("build")

func build() -> void:
	player = get_parent().get_node("Player")
	combat = player.get_node("CombatController")
	# Existing art-hub fixtures remain usable targets; this drill has one active foe.
	for actor in get_tree().get_nodes_in_group(&"hostiles"):
		var attack := actor.get_node_or_null("AttackHitbox") as CombatHitbox
		if attack != null:
			actor.set_process(false)
			actor.set_physics_process(false)
			attack.set_active(false)
	player.position = Vector3(0,0.9,-30)
	var zone := preload("res://scripts/training/sword_combo_zone.gd").new()
	zone.name = "SwordDistanceDrill"
	get_parent().add_child(zone)
	zone.build(player)
	zone.set_clean(true)
	var scene: PackedScene = load("res://scenes/enemies/TechnicalDummy.tscn")
	var sentinel := scene.instantiate()
	sentinel.set_script(preload("res://scripts/training/training_sentinel.gd"))
	sentinel.name = "TrainingSentinel"
	get_parent().add_child(sentinel)
	sentinel.position = Vector3(8,0.1,-30)
	var specs := {&"body":Color(0.52,0.40,0.35),&"wood":Color(0.44,0.28,0.16),&"stone":Color(0.42,0.45,0.48),&"metal":Color(0.60,0.66,0.70)}
	var i := 0
	for material in specs:
		var prop := StaticBody3D.new()
		prop.name = "Material_"+String(material)
		prop.add_to_group("surface_flesh" if material == &"body" else "surface_"+String(material))
		get_parent().add_child(prop)
		prop.position = Vector3(-11+float(i)*2.4,0.1,-27)
		var mesh := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.8,1.6,0.7)
		mesh.mesh = box
		mesh.position.y = 0.8
		var mat := StandardMaterial3D.new()
		mat.albedo_color = specs[material]
		mat.metallic = 0.7 if material == &"metal" else 0.0
		mat.roughness = 0.32 if material == &"metal" else 0.8
		mesh.material_override = mat
		prop.add_child(mesh)
		CombatHurtbox.build_for(prop,box.size,mesh.position)
		i += 1
	var layer := CanvasLayer.new()
	add_child(layer)
	debug_label = Label.new()
	debug_label.position = Vector2(16,480)
	debug_label.add_theme_font_size_override("font_size",16)
	debug_label.add_theme_color_override("font_shadow_color",Color.BLACK)
	debug_label.add_theme_constant_override("shadow_offset_x",2)
	debug_label.add_theme_constant_override("shadow_offset_y",2)
	layer.add_child(debug_label)
	debug_label.visible = false

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F6:
		debug_on = not debug_on
		if debug_label != null:
			debug_label.visible = debug_on

func _process(_delta: float) -> void:
	if not debug_on or combat == null:
		return
	var phase := "idle"
	if combat.active_move != null:
		phase = SwordPoseSampler.Phase.keys()[SwordPoseSampler.phase_of(combat.active_move,combat.active_move.raw_time_at(combat.state_time,combat.move_startup_scale),combat.recovery_scale())]
	debug_label.text = "%s / A%d / %s\nBuffer: %s / Hits: %d / PG: %.0f ms\nFPS: %d / draw calls: %d" % [CombatController.State.keys()[combat.state],combat.combo_index+1,phase,combat.buffer.pending,combat.hits_landed,combat.moveset.guard.perfect_guard_window*1000,Engine.get_frames_per_second(),Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)]
