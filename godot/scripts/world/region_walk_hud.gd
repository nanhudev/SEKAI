extends CanvasLayer
## Regionwalk HUD — where am I, and how do I move.
##
## WHY THIS EXISTS: the region had no player-facing chrome at all. Mounting it
## from the main menu produced a first-person view of a 600 m valley with no
## indication of the controls, the route, or the player's position — which is
## fine for a level-design review, where the reviewer wrote the walker, and
## useless for anyone else asked to "go and look at the map".
##
## IT IS A NAVIGATION AID, NOT A GAME HUD. It reads the zone band out of the
## masterplan's route spine and prints it; it owns no gameplay state and
## nothing depends on it. GATE 1's real HUD is a separate pass.
##
## The zone bands below are distances ALONG ROAD_SPINE (measured with
## MistvaleHeights.route_length), cross-checked against the masterplan's
## landmarks: the bridge lands near d≈210, Lower Town's first terrace at
## d≈360, the market square — which the height field pins to exactly (0,0) —
## at d≈450, and the North Gate is the far end at d≈625.

const SPINE_NAME := "雾谷主线"

## [start_distance, end_distance, name]. Ordered; the last band is open-ended.
const BANDS := [
	[0.0, 55.0, "雾谷东林 · 南口"],
	[55.0, 145.0, "雾谷东林 · 青竹林"],
	[145.0, 195.0, "林缘眺台"],
	[195.0, 255.0, "雾谷渡口 · 石桥"],
	[255.0, 340.0, "南岸缓坡"],
	[340.0, 440.0, "雾栖镇 · 下城区"],
	[440.0, 482.0, "雾栖镇 · 集市广场"],
	[482.0, 545.0, "雾栖镇 · 公会台地"],
	[545.0, 990.0, "雾栖镇 · 上城区 / 北门"],
]


var _walker: Node3D
var _label: Label
var _fps := 0.0
var _spine_len := 0.0


func _ready() -> void:
	layer = 3
	_walker = get_parent().get_node_or_null("ReviewWalker")
	_spine_len = MistvaleHeights.route_length(MistvaleHeights.ROAD_SPINE)
	_build()
	set_process(true)


func _build() -> void:
	var panel := PanelContainer.new()
	panel.position = Vector2(16, 16)
	panel.custom_minimum_size = Vector2(360, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.03, 0.05, 0.06, 0.62)
	style.border_color = Color(0.55, 0.72, 0.75, 0.35)
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	style.set_content_margin_all(10)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	panel.add_child(col)

	var title := Label.new()
	title.text = "雾谷 Mistvale  ·  一级切片漫游"
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", Color(0.88, 0.94, 0.95))
	col.add_child(title)

	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 13)
	_label.add_theme_color_override("font_color", Color(0.70, 0.82, 0.84))
	col.add_child(_label)

	# Controls sit at the bottom-left so they never cover the composition while
	# the player is actually looking at something.
	var keys := Label.new()
	keys.text = "WASD 移动    SHIFT 疾跑    SPACE/Ctrl 升降   左键转向   ESC 菜单"
	keys.add_theme_font_size_override("font_size", 12)
	keys.add_theme_color_override("font_color", Color(0.62, 0.72, 0.74))
	var keys_panel := PanelContainer.new()
	keys_panel.add_theme_stylebox_override("panel", style)
	keys_panel.anchor_top = 1.0
	keys_panel.anchor_bottom = 1.0
	keys_panel.anchor_left = 0.0
	keys_panel.offset_left = 16
	keys_panel.offset_top = -16
	keys_panel.offset_bottom = -16
	keys_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	keys_panel.add_child(keys)
	add_child(keys_panel)


func _process(delta: float) -> void:
	_fps = lerpf(_fps, 1.0 / maxf(delta, 0.0001), 0.08)
	if _walker == null or _label == null:
		return
	var p := _walker.global_position
	var d := _nearest_spine_distance(p.x, p.z)
	_label.text = "%s\n距离主线 %.0f m / %.0f m   海拔 %.1f m\n坐标 (%.0f, %.0f)   %.0f FPS" % [
		_band_name(d), d, _spine_len, p.y, p.x, p.z, _fps
	]


func _band_name(d: float) -> String:
	for b in BANDS:
		if d >= b[0] and d < b[1]:
			return b[2]
	return BANDS[BANDS.size() - 1][2]


## Nearest point on the spine, so the readout stays meaningful when the player
## wanders off the road — which is the whole point of a walkaround.
func _nearest_spine_distance(x: float, z: float) -> float:
	var pts: Array = MistvaleHeights.ROAD_SPINE
	var best := INF
	var best_d := 0.0
	var acc := 0.0
	for i in range(pts.size() - 1):
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var ab := b - a
		var seg := ab.length()
		if seg <= 0.001:
			continue
		var t := clampf((Vector2(x, z) - a).dot(ab) / (seg * seg), 0.0, 1.0)
		var q := a + ab * t
		var dist := Vector2(x, z).distance_to(q)
		if dist < best:
			best = dist
			best_d = acc + seg * t
		acc += seg
	return best_d
