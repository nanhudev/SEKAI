extends Node

const SAVE_PATH := "user://save_01.json"

@onready var world: Node3D = $World
@onready var player: SekaiPlayer = $Player
@onready var ui: CanvasLayer = $UI

var menu: Control
var hud: Control
var info_label: Label
var objective_label: Label
var status_label: Label
var beacon_label: Label
var title_label: Label
var game_active := false
var beacons: Dictionary = {"mistvale": false, "forest": false}
var beacon_nodes: Dictionary = {}
var enemy: Node3D
var enemy_hp := 100.0
var frost := 0.0
var frozen := false
var combo := 0
var last_attack := -10.0
var blocking := false
var guard_start := -10.0
var hit_pause := 0.0
var current_message := ""
var message_timer := 0.0
var game_time := 9.0
var save_cooldown := 0.0

func _ready() -> void:
	build_environment()
	build_world()
	build_ui()
	show_menu()
	get_viewport().size_changed.connect(layout_ui)

func _process(delta: float) -> void:
	if not game_active:
		return
	game_time += delta / 300.0
	message_timer -= delta
	save_cooldown = maxf(0.0, save_cooldown - delta)
	if message_timer <= 0.0:
		info_label.text = ""
	var near := nearest_beacon()
	if near != "":
		beacon_label.text = "E  ·  " + ("界碑共鸣 / 传送" if beacons[near] else "唤醒界碑")
	else:
		beacon_label.text = ""
	if Input.is_key_pressed(KEY_F5) and save_cooldown == 0.0:
		save_game()
		save_cooldown = 1.0
	if Input.is_key_pressed(KEY_1):
		player.weapon = "sword"
	if Input.is_key_pressed(KEY_2):
		player.weapon = "staff"
	if Input.is_key_pressed(KEY_Z):
		player.spell = "fire"
	if Input.is_key_pressed(KEY_X):
		player.spell = "frost"
	if Input.is_key_pressed(KEY_C):
		player.spell = "wind"
	if Input.is_key_pressed(KEY_TAB) and player.weapon == "staff":
		status_label.text = "火  Z     冰  X     风  C"
	else:
		status_label.text = "生命 %d   体力 %d   灵力 %d    ·    %s / %s" % [int(player.hp), int(player.stamina), int(player.mana), "剑" if player.weapon == "sword" else "导具", player.spell]
	if enemy != null and enemy_hp > 0:
		enemy.rotation.y += delta * (0.0 if frozen else 0.35)
		if frost > 0 and not frozen:
			frost = maxf(0.0, frost - 5.0 * delta)
		if player.global_position.distance_to(enemy.global_position) < 3.1 and not frozen:
			var seconds := Time.get_ticks_msec() / 1000.0
			if fmod(seconds, 2.7) < delta:
				if blocking:
					if seconds - guard_start < 0.25:
						message("精准格挡", 1.2)
						player.add_trauma(0.34)
						enemy_hp -= 18
					else:
						message("格挡", 0.8)
				else:
					player.hp = maxf(0.0, player.hp - 12)
					player.add_trauma(0.28)
					message("受击", 0.8)

func _unhandled_input(event: InputEvent) -> void:
	if not game_active:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ESCAPE:
				pause_game()
			KEY_E:
				use_beacon()
			KEY_F5:
				save_game()
			KEY_ALT:
				player.dodge()
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			blocking = event.pressed
			if blocking:
				guard_start = Time.get_ticks_msec() / 1000.0
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			attack()

func start_game(continue_save: bool) -> void:
	if continue_save and FileAccess.file_exists(SAVE_PATH):
		load_game()
	else:
		player.global_position = Vector3(0, 2.3, 54)
		player.yaw = 0
		player.rotation.y = 0
		player.hp = 100
		player.mana = 100
		player.stamina = 100
		player.weapon = "sword"
		player.spell = "fire"
		beacons = {"mistvale": false, "forest": false}
		beacon_nodes["mistvale"].set_active(false)
		beacon_nodes["forest"].set_active(false)
	game_active = true
	menu.visible = false
	hud.visible = true
	player.input_enabled = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	message("雾栖镇  ·  Mistvale", 3.4)

func pause_game() -> void:
	game_active = false
	player.input_enabled = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	save_game()
	show_menu()

func show_menu() -> void:
	game_active = false
	player.input_enabled = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	menu.visible = true
	hud.visible = false
	var continue_button: Button = menu.get_node("Panel/Buttons/Continue")
	continue_button.disabled = not FileAccess.file_exists(SAVE_PATH)

func save_game() -> void:
	var data := {
		"version": 1,
		"position": [player.global_position.x, player.global_position.y, player.global_position.z],
		"yaw": player.yaw,
		"pitch": player.pitch,
		"hp": player.hp,
		"mana": player.mana,
		"stamina": player.stamina,
		"weapon": player.weapon,
		"spell": player.spell,
		"time": game_time,
		"beacons": beacons,
		"enemy_hp": enemy_hp,
		"frost": frost,
		"frozen": frozen
	}
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data))
		message("旅程已保存", 1.4)

func load_game() -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not file:
		return
	var data = JSON.parse_string(file.get_as_text())
	if not data is Dictionary:
		return
	var p: Array = data.get("position", [0, 2.3, 54])
	player.global_position = Vector3(float(p[0]), float(p[1]), float(p[2]))
	player.yaw = float(data.get("yaw", 0.0))
	player.pitch = float(data.get("pitch", 0.0))
	player.rotation.y = player.yaw
	player.head.rotation.x = player.pitch
	player.hp = float(data.get("hp", 100.0))
	player.mana = float(data.get("mana", 100.0))
	player.stamina = float(data.get("stamina", 100.0))
	player.weapon = str(data.get("weapon", "sword"))
	player.spell = str(data.get("spell", "fire"))
	game_time = float(data.get("time", 9.0))
	beacons = data.get("beacons", {"mistvale": false, "forest": false})
	for key in beacon_nodes:
		beacon_nodes[key].set_active(bool(beacons.get(key, false)))
	enemy_hp = float(data.get("enemy_hp", 100.0))
	frost = float(data.get("frost", 0.0))
	frozen = bool(data.get("frozen", false))
	enemy.visible = enemy_hp > 0.0

func nearest_beacon() -> String:
	for key in beacon_nodes:
		if player.global_position.distance_to(beacon_nodes[key].global_position) < 3.5:
			return key
	return ""

func use_beacon() -> void:
	var key := nearest_beacon()
	if key == "":
		return
	if not beacons[key]:
		beacons[key] = true
		beacon_nodes[key].set_active(true)
		message("界碑已共鸣  ·  " + ("雾栖镇" if key == "mistvale" else "森林边缘"), 3.0)
		save_game()
		return
	var other := "forest" if key == "mistvale" else "mistvale"
	if beacons[other]:
		player.global_position = beacon_nodes[other].global_position + Vector3(0, 1.5, 4)
		message("界碑传送  ·  " + ("森林边缘" if other == "forest" else "雾栖镇"), 3.0)
		save_game()
	else:
		message("尚未发现其他界碑", 2.0)

func attack() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if player.weapon == "sword":
		if now - last_attack < 0.19:
			return
		combo = (combo % 3) + 1 if now - last_attack < 0.9 else 1
		last_attack = now
		var heavy := Input.is_key_pressed(KEY_SHIFT)
		player.add_trauma(0.17 if heavy else 0.06)
		message(("重击" if heavy else "剑击 %d" % combo), 0.6)
		if enemy_hit(3.0):
			if heavy and frozen:
				enemy_hp = 0
				frozen = false
				enemy.visible = false
				player.add_trauma(0.55)
				message("碎裂  ·  SHATTER", 3.0)
			else:
				enemy_hp -= 30.0 if heavy else 12.0 + combo * 3.0
				player.add_trauma(0.1)
				if enemy_hp <= 0:
					enemy.visible = false
	else:
		if player.mana < 8:
			message("灵力不足", 1.0)
			return
		player.mana -= 8
		player.add_trauma(0.09)
		match player.spell:
			"fire":
				message("火焰术", 0.9)
				if enemy_hit(14.0):
					enemy_hp -= 21
			"frost":
				message("冰霜之息", 0.9)
				if enemy_hit(9.0):
					frost += 35
					if frost >= 100:
						frozen = true
						message("冻结", 1.3)
			"wind":
				message("风压", 0.9)
				if enemy_hit(8.0):
					enemy.position += player.forward() * 1.5
					enemy_hp -= 4
		if enemy_hp <= 0:
			enemy.visible = false

func enemy_hit(max_range: float) -> bool:
	if enemy == null or enemy_hp <= 0:
		return false
	var to_enemy := enemy.global_position + Vector3.UP - player.camera.global_position
	return to_enemy.length() < max_range and player.forward().dot(to_enemy.normalized()) > 0.82

func message(value: String, duration: float) -> void:
	current_message = value
	message_timer = duration
	info_label.text = value

func box(parent: Node3D, name: String, pos: Vector3, size: Vector3, color: Color, solid := false) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	mesh.name = name
	var cube := BoxMesh.new()
	cube.size = size
	mesh.mesh = cube
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.9
	mesh.material_override = mat
	mesh.position = pos
	parent.add_child(mesh)
	if solid:
		var body := StaticBody3D.new()
		body.name = name + "Collision"
		body.position = pos
		parent.add_child(body)
		var shape := CollisionShape3D.new()
		var cube_shape := BoxShape3D.new()
		cube_shape.size = size
		shape.shape = cube_shape
		body.add_child(shape)
	return mesh

func make_district(name: String) -> Node3D:
	var node := Node3D.new()
	node.name = name
	world.add_child(node)
	return node

func build_environment() -> void:
	var env := WorldEnvironment.new()
	env.name = "Environment"
	world.add_child(env)
	var resource := Environment.new()
	resource.background_mode = Environment.BG_COLOR
	resource.background_color = Color("91b9c2")
	resource.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	resource.ambient_light_color = Color("dbe6df")
	resource.ambient_light_energy = 0.55
	resource.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = resource
	var sun := DirectionalLight3D.new()
	sun.name = "MorningSun"
	sun.light_color = Color("ffe4b6")
	sun.light_energy = 1.1
	sun.rotation_degrees = Vector3(-42, -32, 0)
	sun.shadow_enabled = true
	world.add_child(sun)

func build_world() -> void:
	var terrain := make_district("Terrain")
	var lower := make_district("LowerTown")
	var center := make_district("CentralTown")
	var guild := make_district("GuildDistrict")
	var upper := make_district("UpperTown")
	var north := make_district("NorthGate")
	var forest := make_district("ForestEdge")
	var river := make_district("Riverside")
	var stone := Color("99968a")
	var grass := Color("758c69")
	var earth := Color("9d896b")
	var path := Color("c7b692")
	box(terrain, "SouthApproach", Vector3(0, 0, 48), Vector3(65, 2, 30), grass, true)
	box(lower, "LowerTerrace", Vector3(0, 1, 26), Vector3(60, 2, 24), grass, true)
	box(center, "CentralTerrace", Vector3(0, 4.5, 0), Vector3(54, 5, 30), grass, true)
	box(guild, "GuildTerrace", Vector3(0, 10, -24), Vector3(38, 6, 22), stone, true)
	box(upper, "UpperTerrace", Vector3(0, 14.5, -48), Vector3(48, 9, 27), grass, true)
	box(north, "NorthGateTerrace", Vector3(0, 19, -71), Vector3(36, 6, 22), stone, true)
	box(forest, "ForestTerrace", Vector3(0, 22, -101), Vector3(74, 6, 42), grass, true)
	box(river, "River", Vector3(-27, 0.12, 25), Vector3(11, 0.15, 74), Color("579aab"))
	for i in range(16):
		var z := 43.0 - i * 8.1
		var y := 0.5 + float(i) * 1.5
		box(terrain, "RoadStep%02d" % i, Vector3(0, y, z), Vector3(7, 0.4, 8.1), path, true)
	for i in range(11):
		var z := 39.0 - i * 9.3
		var y := 0.2 + float(i) * 1.95
		box(terrain, "RoadRamp%02d" % i, Vector3(0, y, z), Vector3(5.5, 0.65, 9.3), path, true)
	build_house(lower, Vector3(-14, 2, 29), 8, 6, false)
	build_house(lower, Vector3(14, 2, 30), 7, 7, false)
	build_house(center, Vector3(-17, 7, 5), 8, 7, false)
	build_house(center, Vector3(17, 7, -2), 8, 6, false)
	build_house(upper, Vector3(-17, 18, -49), 8, 7, false)
	build_house(upper, Vector3(17, 18, -51), 8, 7, false)
	build_house(guild, Vector3(0, 13, -23), 20, 12, true)
	var tree := make_district("CentralTree")
	box(tree, "Trunk", Vector3(-9, 10, 0), Vector3(1.7, 6, 1.7), Color("70563d"))
	var crown := SphereMesh.new()
	crown.radius = 5.5
	crown.height = 9
	var canopy := MeshInstance3D.new()
	canopy.mesh = crown
	canopy.position = Vector3(-9, 15, 0)
	var leaves := StandardMaterial3D.new()
	leaves.albedo_color = Color("52785c")
	canopy.material_override = leaves
	tree.add_child(canopy)
	for i in range(20):
		var angle := i * TAU / 20.0
		var r := 13.0 + float(i % 4) * 5.0
		var trunk_pos := Vector3(cos(angle) * r, 25, -104 + sin(angle) * 14)
		box(forest, "ForestTree%02d" % i, trunk_pos, Vector3(0.7, 5, 0.7), Color("65533d"))
		var crown_pos := trunk_pos + Vector3(0, 3.8, 0)
		box(forest, "ForestCrown%02d" % i, crown_pos, Vector3(3.4, 4.3, 3.4), Color("526f5a"))
	box(north, "GateLeft", Vector3(-7, 26, -75), Vector3(3, 8, 3), stone, true)
	box(north, "GateRight", Vector3(7, 26, -75), Vector3(3, 8, 3), stone, true)
	box(north, "GateLintel", Vector3(0, 31, -75), Vector3(17, 2, 3), stone, true)
	var beacon_scene := load("res://scenes/beacon.tscn") as PackedScene
	beacon_nodes["mistvale"] = beacon_scene.instantiate()
	beacon_nodes["mistvale"].name = "MistvaleBeacon"
	beacon_nodes["mistvale"].position = Vector3(9, 7.2, 2)
	center.add_child(beacon_nodes["mistvale"])
	beacon_nodes["forest"] = beacon_scene.instantiate()
	beacon_nodes["forest"].name = "ForestBeacon"
	beacon_nodes["forest"].position = Vector3(8, 25.2, -110)
	forest.add_child(beacon_nodes["forest"])
	enemy = Node3D.new()
	enemy.name = "LesserRuinSentinel"
	enemy.position = Vector3(0, 25.5, -101)
	forest.add_child(enemy)
	box(enemy, "Core", Vector3(0, 1.7, 0), Vector3(1.0, 1.0, 1.0), Color("9aadc0"))
	box(enemy, "LeftArmor", Vector3(-0.95, 1.8, 0), Vector3(0.7, 1.4, 0.75), stone)
	box(enemy, "RightArmor", Vector3(0.88, 2.1, 0), Vector3(0.65, 1.2, 0.8), stone)
	box(enemy, "Crown", Vector3(0, 2.7, 0), Vector3(1.6, 0.65, 0.75), stone)

func build_house(parent: Node3D, p: Vector3, w: float, d: float, landmark: bool) -> void:
	var wall := Color("c5b79a")
	var roof := Color("465e5b")
	box(parent, "HouseWall", p + Vector3(0, 2.4, 0), Vector3(w, 4.8, d), wall, true)
	box(parent, "HouseRoof", p + Vector3(0, 5.2, 0), Vector3(w + 1.4, 1.0, d + 1.4), roof)
	if landmark:
		box(parent, "GuildTower", p + Vector3(-w * 0.27, 8, -d * 0.1), Vector3(4, 7, 4), wall)
		box(parent, "GuildTowerRoof", p + Vector3(-w * 0.27, 12, -d * 0.1), Vector3(5, 1, 5), roof)
		box(parent, "GuildBanner", p + Vector3(0, 4.3, d * 0.5 + 0.08), Vector3(2.1, 2.3, 0.1), Color("7d5649"))

func build_ui() -> void:
	menu = Control.new()
	menu.name = "Menu"
	menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.add_child(menu)
	var backdrop := ColorRect.new()
	backdrop.color = Color("0b1b20")
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu.add_child(backdrop)
	var art_path := "res://art/sekai-title-key-art.png"
	if ResourceLoader.exists(art_path):
		var art := TextureRect.new()
		art.texture = load(art_path)
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		art.modulate = Color(0.8, 0.85, 0.83, 0.7)
		menu.add_child(art)
	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.position = Vector2(95, 165)
	panel.custom_minimum_size = Vector2(410, 490)
	menu.add_child(panel)
	var column := VBoxContainer.new()
	column.name = "Buttons"
	column.add_theme_constant_override("separation", 16)
	panel.add_child(column)
	title_label = Label.new()
	title_label.text = "世界之外\nS E K A I"
	title_label.add_theme_font_size_override("font_size", 43)
	column.add_child(title_label)
	var subtitle := Label.new()
	subtitle.text = "雾栖镇  ·  GODOT FOUNDATION"
	subtitle.add_theme_font_size_override("font_size", 17)
	column.add_child(subtitle)
	for spec in [["Continue", "继续旅程"], ["NewGame", "新的旅程"], ["Save", "保存旅程"], ["Exit", "退出游戏"]]:
		var button := Button.new()
		button.name = spec[0]
		button.text = spec[1]
		button.custom_minimum_size.y = 48
		column.add_child(button)
	column.get_node("Continue").pressed.connect(func(): start_game(true))
	column.get_node("NewGame").pressed.connect(func(): start_game(false))
	column.get_node("Save").pressed.connect(func(): save_game())
	column.get_node("Exit").pressed.connect(func(): get_tree().quit())
	hud = Control.new()
	hud.name = "HUD"
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(hud)
	objective_label = Label.new()
	objective_label.text = "走向北门  ·  寻找森林界碑"
	objective_label.position = Vector2(36, 30)
	objective_label.add_theme_font_size_override("font_size", 18)
	hud.add_child(objective_label)
	info_label = Label.new()
	info_label.position = Vector2(48, 135)
	info_label.add_theme_font_size_override("font_size", 30)
	hud.add_child(info_label)
	beacon_label = Label.new()
	beacon_label.position = Vector2(500, 590)
	beacon_label.add_theme_font_size_override("font_size", 22)
	hud.add_child(beacon_label)
	status_label = Label.new()
	status_label.position = Vector2(36, 665)
	status_label.add_theme_font_size_override("font_size", 17)
	hud.add_child(status_label)
	var crosshair := Label.new()
	crosshair.text = "+"
	crosshair.name = "Crosshair"
	crosshair.add_theme_font_size_override("font_size", 22)
	hud.add_child(crosshair)
	layout_ui()

func layout_ui() -> void:
	if hud == null:
		return
	var size := get_viewport().get_visible_rect().size
	status_label.position = Vector2(36, size.y - 55)
	beacon_label.position = Vector2(size.x * 0.5 - 100, size.y * 0.68)
	hud.get_node("Crosshair").position = size * 0.5 - Vector2(5, 16)
