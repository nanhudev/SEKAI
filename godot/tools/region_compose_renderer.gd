extends SceneTree
##
## Composition renders of the Mistvale region, for the human review the brief
## keeps asking for (§14: "从底部截图：能产生『我要爬上去』").
##
## WHY THIS EXISTS SEPARATELY FROM combat_movie_renderer.gd: that one drives a
## scripted fight in real time. This one is a STILL camera tour — the only thing
## that matters is that the framing is taken from a real eye height on the real
## field, because a composition claim that is not shot from where the player
## stands is not a composition claim.
##
## Usage (NOT --headless: headless disables rendering entirely):
##   godot --path godot --resolution 1600x900 --audio-driver Dummy \
##         --script res://tools/region_compose_renderer.gd
##
## Output: F:/SEKAI/assets_source/review/compose/*.png

const OUT_DIR := "F:/SEKAI/assets_source/review/compose/"
const EYE := 1.70
const WARMUP := 8

var orbit: Array = []
var shots: Array = []


func _initialize() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	var dir := DirAccess.open(OUT_DIR)
	if dir == null:
		DirAccess.make_dir_recursive_absolute(OUT_DIR)

	print("loading MistvaleRegion ...")
	var packed: PackedScene = load("res://scenes/world/MistvaleRegion.tscn")
	var scene: Node3D = packed.instantiate()
	root.add_child(scene)
	# _initialize() runs while the SceneTree is still being set up, so _ready()
	# has NOT fired yet on the builder nodes: Terrain, Greybox and Ascent are all
	# still empty at this point and only fill in on the first frame. Anything that
	# inspects or edits the built scene has to wait for that first frame, or it
	# silently edits nothing — which is exactly how the marker-hiding below
	# reported zero while the renders were full of marker balls.
	await process_frame
	await process_frame
	print("scene built")

	# The review walker fights the render camera for the mouse and for `current`.
	var walker := scene.get_node_or_null("ReviewWalker")
	if walker != null:
		walker.queue_free()
	print("scene ready")

	var cam := Camera3D.new()
	cam.fov = 62.0
	cam.near = 0.1
	cam.far = 2000.0
	root.add_child(cam)
	cam.current = true

	_light_for_review(scene)

	_build_shots()
	print("shots: ", shots.size())
	for s in shots:
		await _capture(cam, s)
	print("DONE")
	quit(0)


## The scene's single key light comes from the south-east, which is correct and
## useless here: the Cliff Route climbs the mountain's south-WEST flank, so every
## composition shot of the ascent came back as a black silhouette. A review
## render that cannot show the thing being reviewed is not a review. This adds a
## render-only fill and lifts ambient — nothing is written back to the scene.
func _light_for_review(scene: Node3D) -> void:
	var fill := DirectionalLight3D.new()
	fill.name = "ReviewFill"
	fill.light_energy = 0.5
	fill.light_color = Color(0.74, 0.82, 0.96)
	fill.shadow_enabled = false
	# LIGHT_ONLY: a DirectionalLight3D in SKY_MODE_LIGHT_AND_SKY also gets its own
	# sun drawn into the procedural sky, so the fill would add a second sun.
	fill.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	fill.rotation = Vector3(deg_to_rad(-34.0), deg_to_rad(206.0), 0.0)
	root.add_child(fill)

	# AMBIENT_SOURCE_COLOR, not the scene's SKY. Sky ambient is directional — it
	# lights upward faces and leaves the lee flank literally black, which is how
	# every ascent shot first came back as a silhouette. A flat ambient sets a
	# floor under the whole region so a shadow can be dark without being empty.
	# EXPOSURE. The first pass ran ambient 1.5 + exposure 1.15 on top of the
	# scene's own sun 1.9 under FILMIC, and the whole region came back as a
	# white sheet: the town, the terraces and the mountain read as one flat
	# mass with no slope legible anywhere. A greybox whose landform cannot be
	# read is not a review of a landform. AGX plus a much lower ambient floor
	# keeps the sky bright without throwing away the ground's modelling —
	# same discipline as the Blender review rig and the training ground.
	var we := scene.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if we != null and we.environment != null:
		we.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		we.environment.ambient_light_color = Color(0.58, 0.65, 0.74)
		we.environment.ambient_light_energy = 0.55
		we.environment.tonemap_mode = Environment.TONE_MAPPER_AGX
		we.environment.tonemap_exposure = 1.0
		we.environment.tonemap_white = 2.4

	var sun := scene.get_node_or_null("Sun") as DirectionalLight3D
	if sun != null:
		sun.light_energy = 1.35

	# Waypoint spheres sit 3 m above the trail and a vista pole is a 10 m cyan
	# mast with a ball on top — and the camera stands ON the trail, at a vista.
	# The first passes of this renderer produced a lens full of marker and no
	# composition at all.
	#
	# Matched by NAME PATTERN rather than by layer path. The layers are built in
	# _ready by the greybox and searchable paths turned out not to be what this
	# tool assumed; the marker names (wp_*, V1..V9, NAR*, MS*, C0*) are stable
	# because they are the masterplan's own IDs.
	var hidden := 0
	var stack: Array = [scene]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
			if not (c is Node3D):
				continue
			# Match the node's own name AND its parent's. The route markers' own
			# MeshInstance3D names collide across the three routes (all three are
			# added to the same parent), so most of them are auto-renamed to
			# @MeshInstance3D@N and no name pattern can catch them — but their
			# parent is always `Routes`.
			var nm := String(c.name)
			var pn := String(c.get_parent().name)
			if (
				nm.begins_with("wp_")
				or nm.begins_with("V")
				or nm.begins_with("NAR")
				or nm.begins_with("MS")
				or nm.begins_with("C0")
				or pn == "Routes"
				or pn == "Vistas"
				or pn == "Narrative"
			):
				(c as Node3D).visible = false
				hidden += 1
	print("markers hidden: ", hidden)
	print("review lighting applied")


func _h(x: float, z: float) -> float:
	return MistvaleHeights.height_at(x, z)


func _rp(d: float) -> Vector2:
	return MistvaleHeights.route_at(MistvaleHeights.CLIFF_ROUTE, d)


## d = distance along the Cliff Route; lat = metres to the player's right.
func _on_route(d: float, lat: float, eye: float) -> Vector3:
	var p := _rp(d)
	var t := MistvaleHeights.route_tangent(MistvaleHeights.CLIFF_ROUTE, d)
	# right = -tangent rotated 90 deg in the XZ plane, matching the node frame
	var rx := -t.y
	var rz := t.x
	var x := p.x + rx * lat
	var z := p.y + rz * lat
	return Vector3(x, _h(x, z) + eye, z)


func _build_shots() -> void:
	# --- S-B: the climb, from the bottom --------------------------------
	shots.append({
		"name": "01_sb_from_below",
		"pos": _on_route(231.0, 0.0, EYE),
		"to": _on_route(250.0, 0.0, 9.0),
		"fov": 76.0,
		"note": "§14 从底部 — 应产生「我要爬上去」",
	})
	shots.append({
		"name": "02_sb_profile",
		"pos": _on_route(244.0, -16.0, 7.0),
		"to": _on_route(250.0, 0.0, 4.0),
		"fov": 44.0,
		"note": "侧视 — 三级台地 + 岩凹 + 挑台 的剖面关系（构图主图）",
	})
	shots.append({
		"name": "03_sb_first_flight",
		"pos": _on_route(237.0, 0.0, EYE),
		"to": _on_route(247.0, 0.0, 4.0),
		"fov": 76.0,
		"note": "第一段阶起步 — 28 级，最宽的一段",
	})
	shots.append({
		"name": "03b_sb_alcove",
		"pos": _on_route(243.5, -2.4, EYE),
		"to": _on_route(248.0, -3.4, 1.2),
		"fov": 76.0,
		"note": "岩凹 — 侧向挖进山体，岩壁压在头顶",
	})
	shots.append({
		"name": "04_sb_mid_lookback",
		"pos": _on_route(250.0, 0.0, EYE),
		"to": Vector3(-40.0, 114.0, -95.0),
		"fov": 66.0,
		"note": "§6 爬到中段回头 — 钟塔必须还在（实测：唯一全程可见的地标）",
	})
	shots.append({
		"name": "05_sb_balcony_lookdown",
		"pos": _on_route(255.0, 3.8, EYE),
		"to": _on_route(246.0, 0.0, -3.0),
		"fov": 78.0,
		"note": "半空挑台 — 悬出山外，看自己走过的坡",
	})
	shots.append({
		"name": "06_sb_top_lookback",
		"pos": _on_route(264.0, 0.0, EYE),
		"to": Vector3(0.0, 44.0, -20.0),
		"fov": 66.0,
		"note": "登顶回望 — 城镇应该已经被山肩吃掉，只剩钟塔",
	})
	# The route's last point is (-10,-355) and the beacon stands at (0,-360):
	# 11 m apart, with the beacon's base 8 m above the eye. Shot from d=276 the
	# camera aimed 60 deg up a 10 m column from 16 m out, and every render came
	# back as a scrap of yellow against sky. Backed off to d=243 (~47 m) — but
	# that alone still put the column's top out of frame, because aiming at its
	# BASE means aiming 5 deg above a horizon that is already the top of the
	# frame. Aim at the middle of the shaft instead.
	shots.append({
		"name": "07_sb_arrival",
		"pos": _on_route(243.0, 0.0, EYE),
		"to": Vector3(0.0, 164.0, -360.0),
		"fov": 62.0,
		"note": "前场 — 信标正对（远看全貌，不是贴着柱子抬头）",
	})

	# --- The look-back deck the audit called for ------------------------
	var dp := _rp(76.0)
	shots.append({
		"name": "08_deck_L1_lookback",
		"pos": Vector3(dp.x, _h(dp.x, dp.y) + 2.0 + EYE, dp.y),
		"to": Vector3(0.0, 34.0, 0.0),
		"fov": 64.0,
		"note": "§6 里程石台 +2.0 m — 实测这是唯一能同时重开市场+河谷+公会的抬升量",
	})

	# --- Guild Terrace: the civic axis ----------------------------------
	shots.append({
		"name": "09_guild_from_market",
		"pos": Vector3(0.0, _h(0.0, 4.0) + EYE, 4.0),
		"to": Vector3(0.0, 46.0, -50.0),
		"fov": 62.0,
		"note": "§3 CIVIC — 从市场看公会台地，轴线必须成立",
	})
	shots.append({
		"name": "10_guild_mid_landing",
		"pos": Vector3(0.0, 40.5, -33.0),
		"to": Vector3(0.0, 34.0, 20.0),
		"fov": 68.0,
		"note": "中平台回望 — 公共空间应该压过陡度",
	})
	shots.append({
		"name": "11_guild_forecourt",
		"pos": Vector3(0.0, 50.2, -46.0),
		"to": Vector3(0.0, 50.0, -62.0),
		"fov": 62.0,
		"note": "公会前庭 — 正对入口的收束",
	})

	# --- Region-scale composition --------------------------------------
	shots.append({
		"name": "12_aerial_town_mountain",
		"pos": Vector3(330.0, 260.0, 250.0),
		"to": Vector3(10.0, 70.0, -150.0),
		"fov": 55.0,
		"note": "城镇 / 河谷 / 北山 的宏观关系",
	})
	shots.append({
		"name": "13_aerial_ascent",
		"pos": Vector3(150.0, 210.0, -200.0),
		"to": Vector3(35.0, 130.0, -336.0),
		"fov": 58.0,
		"note": "崖路上升段全长 — 看三级台地是否读得出来",
	})
	shots.append({
		"name": "14_aerial_ruins",
		"pos": Vector3(70.0, 215.0, -250.0),
		"to": Vector3(-10.0, 140.0, -358.0),
		"fov": 58.0,
		"note": "遗迹前场与望台",
	})


func _capture(cam: Camera3D, s: Dictionary) -> void:
	cam.fov = float(s["fov"])
	cam.look_at_from_position(s["pos"] as Vector3, s["to"] as Vector3, Vector3.UP)
	for i in WARMUP:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	if img == null:
		print("FAIL ", s["name"], " — readback null")
		return
	var path := OUT_DIR + String(s["name"]) + ".png"
	var err := img.save_png(path)
	print("%-26s %s  %s" % [s["name"], "ok" if err == OK else "ERR %d" % err, s["note"]])
