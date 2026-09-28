extends SceneTree
##
## WALKTHROUGH renderer — the addendum's §21 "actually walk it".
##
## WHY THIS EXISTS SEPARATELY FROM level_art_review.gd: the review rig shoots 10
## FIXED points. Fixed points are the right tool for before/after on a known
## spot, and they are the wrong tool for the two questions the addendum actually
## asks:
##
##   §28  "10-second test"  — does the composition / height / landmark change
##         every ten seconds of walking?
##   §28  "30-second test"  — is there a memory point every thirty seconds?
##
## Both are questions about a CONTINUOUS path, and a set of stills cannot answer
## either: ten unrelated framings can each be fine while the walk between them
## is a corridor of nothing. So this rig walks the real spine at the real walk
## speed and shoots on a fixed metre interval, which makes the frame index a
## clock (step 10 m at 5.0 m/s = one frame every 2 s).
##
## It is also the only rig that can answer §26 "FIRST-PERSON IS THE TRUTH": the
## camera is the player's own eye, on the walked line, at 1.70 m, looking down
## the tangent of the road the player is actually on.
##
## Usage (NOT --headless: headless disables rendering entirely):
##   godot --path godot --resolution 1280x720 --audio-driver Dummy \
##         --script res://tools/level_art_walk.gd -- --tag=walk01
##
##   --tag=NAME       output folder under .render/levelart/
##   --route=spine|cliff|forest
##   --from=0 --to=625   metre range along the route
##   --step=10        metres between frames (10 m = 2 s at walk speed)
##   --look=45        how far ahead the eye aims, in metres
##   --fov=72
##   --pitch=0        degrees, + looks down
##   --back           shoot BACKWARD (view B of the addendum's five)
##   --lateral=0      metres to the right of the centreline
##
## Output: F:/SEKAI/.render/levelart/<tag>/w###_d####.png
##         plus walk_<tag>.csv — per-frame d / x / y / z / nearest road / how
##         built-up the spot is. The CSV is what makes the 10 s / 30 s tests
##         measurable instead of a vibe.

const OUT_DIR := "F:/SEKAI/.render/levelart/"
const EYE := 1.70
const WARMUP := 3
const FP_ROWS := 6
const FP_COLS := 8

## Named routes. A dictionary of NAME -> constant is not possible here: a
## GDScript class reached through its class_name is a script resource, and
## script.get() resolves properties, not constants. So the mapping is a match.

var _tag := "walk"
var _route := "spine"
var _from := 0.0
var _to := -1.0
var _step := 10.0
var _look := 45.0
var _fov := 72.0
var _pitch := 0.0
var _back := false
var _lateral := 0.0
var _no_shadow := false
var _ambient := -1.0
var _bounce := -1.0

var _scene: Node3D
var _cam: Camera3D
var _rows: Array = []
var _fps: Array = []


## Mean luminance of a rectangle, sampled on a fixed grid, on the same 0-255
## scale the PNG probe reports so the two can be compared directly.
##
## `steps` is deliberately small: this is a composition measure, not a quality
## measure, and 14x14 samples of a 320x180 band is far more than the band's own
## variance needs.
func _region_lum(img: Image, x0: int, y0: int, x1: int, y1: int, steps: int = 14) -> float:
	var acc := 0.0
	var n := 0
	var iw := img.get_width() - 1
	var ih := img.get_height() - 1
	var span := maxi(1, steps - 1)
	for j in steps:
		var y: int = clampi(y0 + (y1 - y0) * j / span, 0, ih)
		for i in steps:
			var x: int = clampi(x0 + (x1 - x0) * i / span, 0, iw)
			var c := img.get_pixel(x, y)
			acc += 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
			n += 1
	return acc / float(n) * 255.0


## 6x8 luminance fingerprint of the whole frame. Two fingerprints close together
## mean two framings that look the same — which is the machine-readable form of
## "ten seconds of walking with nothing new to look at".
func _fingerprint(img: Image) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var w := img.get_width()
	var h := img.get_height()
	for j in FP_ROWS:
		for i in FP_COLS:
			out.append(_region_lum(
				img, w * i / FP_COLS, h * j / FP_ROWS,
				w * (i + 1) / FP_COLS, h * (j + 1) / FP_ROWS, 8
			))
	return out


func _fp_dist(a: PackedFloat32Array, b: PackedFloat32Array) -> float:
	if a.is_empty() or a.size() != b.size():
		return 0.0
	var acc := 0.0
	for i in a.size():
		acc += absf(a[i] - b[i])
	return acc / float(a.size())


## Row, as a % of frame height, where the bright top band collapses: a crude
## skyline. Watching this number walk tells you whether the eye height and the
## landform in front of it are changing, independently of what is painted there.
func _horizon(img: Image) -> float:
	var w := img.get_width()
	var h := img.get_height()
	var top := _region_lum(img, 0, 0, w, maxi(1, h / 20))
	var y0 := h / 20
	var y1 := h * 3 / 4
	var steps := 120
	for k in steps:
		var y: int = y0 + (y1 - y0) * k / steps
		var row := _region_lum(img, 0, y, w, y + maxi(1, h / 120))
		if top - row > 28.0:
			return 100.0 * float(y) / float(h)
	return 100.0


func _initialize() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)
	DisplayServer.window_set_size(Vector2i(1280, 720))
	_args()

	var out := OUT_DIR + _tag + "/"
	if not DirAccess.dir_exists_absolute(out):
		DirAccess.make_dir_recursive_absolute(out)

	print("--- LEVEL ART WALK  tag=", _tag, " route=", _route, " ---")
	var packed: PackedScene = load("res://scenes/world/MistvaleRegion.tscn")
	_scene = packed.instantiate()
	root.add_child(_scene)
	# Same trap as the review rig: _initialize() runs before the builder nodes'
	# _ready(), so the terrain / land / town are still empty shells on the frame
	# this function starts on. Height-sampling before that puts the camera at
	# Y = 0, i.e. several metres under the valley floor.
	await process_frame
	await process_frame
	await process_frame

	var walker := _scene.get_node_or_null("ReviewWalker")
	if walker != null:
		# Fights the render camera for `current` and for the mouse.
		walker.queue_free()

	# Canvas chrome does not belong in an art frame. The region walk HUD was
	# added so a person can navigate the map; every walk still would otherwise
	# carry a screenshot of a navigation panel over the composition it exists to
	# judge. The route/band data is already in the CSV.
	var hud := _scene.get_node_or_null("RegionWalkHUD")
	if hud != null:
		hud.queue_free()

	_hide_markers()

	var we := _scene.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if we != null and we.environment != null:
		# Mist off: the review is of the geometry, and at 45 m the fog is what
		# the shot would mostly be of. Same call as the review rig.
		we.environment.fog_enabled = false
		if _ambient >= 0.0:
			# Bisect only. gl_compatibility has no GI, so a shadowed surface is
			# lit by ambient plus the fills and nothing else; how dark a shadow
			# reads is therefore an AMBIENT decision, not a shadow-map one.
			we.environment.ambient_light_energy = _ambient
			print("bisect: ambient_light_energy = ", _ambient)
	if _bounce >= 0.0:
		var b := _scene.get_node_or_null("Bounce") as DirectionalLight3D
		if b != null:
			b.light_energy = _bounce
			print("bisect: bounce energy = ", _bounce)
	if _no_shadow:
		var sun := _scene.get_node_or_null("Sun") as DirectionalLight3D
		if sun != null:
			# Bisect only: is a dark frame a shadow on the geometry, or is the
			# geometry simply facing away from the sun? Identical trick to the
			# review rig, and the one that found the buried stair slabs.
			sun.shadow_enabled = false
			print("bisect: sun shadow DISABLED")

	_cam = Camera3D.new()
	_cam.fov = _fov
	_cam.near = 0.1
	_cam.far = 3000.0
	root.add_child(_cam)
	_cam.current = true

	await _walk()
	_write_csv(out)
	print("DONE -> ", out, "  frames=", _rows.size())
	quit(0)


func _args() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--tag="):
			_tag = a.substr(6)
		elif a.begins_with("--route="):
			_route = a.substr(8)
		elif a.begins_with("--from="):
			_from = float(a.substr(7))
		elif a.begins_with("--to="):
			_to = float(a.substr(5))
		elif a.begins_with("--step="):
			_step = maxf(2.0, float(a.substr(7)))
		elif a.begins_with("--look="):
			_look = float(a.substr(7))
		elif a.begins_with("--fov="):
			_fov = float(a.substr(6))
		elif a.begins_with("--pitch="):
			_pitch = float(a.substr(8))
		elif a.begins_with("--lateral="):
			_lateral = float(a.substr(10))
		elif a == "--back":
			_back = true
		elif a == "--noshadow":
			_no_shadow = true
		elif a.begins_with("--ambient="):
			_ambient = float(a.substr(10))
		elif a.begins_with("--bounce="):
			_bounce = float(a.substr(9))


func _points() -> Array:
	match _route:
		"cliff":
			return MistvaleHeights.CLIFF_ROUTE
		"forest":
			return MistvaleHeights.FOREST_TRAIL
		"forge":
			return MistvaleHeights.ROAD_FORGE
		"ferry":
			return MistvaleHeights.ROAD_FERRY
		"bank":
			return MistvaleHeights.ROAD_BANK
		_:
			return MistvaleHeights.ROAD_SPINE


## Same rule as the review rig: the player walks on the WALKABLE surface, which
## at the bridge crest is the deck, not the river bed 3 m below it.
func _h(x: float, z: float) -> float:
	var land := _scene.get_node_or_null("Land")
	if land != null and land.has_method("surface_height"):
		return land.surface_height(x, z)
	return MistvaleHeights.height_at(x, z)


func _hide_markers() -> void:
	var hidden := 0
	var stack: Array = [_scene]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
			if not (c is Node3D):
				continue
			var nm := String(c.name)
			var pn := String(c.get_parent().name)
			if (nm.begins_with("wp_") or nm.begins_with("V") or nm.begins_with("NAR")
					or nm.begins_with("MS") or nm.begins_with("C0")
					or pn == "Routes" or pn == "Vistas" or pn == "Narrative"
					or pn == "Combat"):
				(c as Node3D).visible = false
				hidden += 1
	print("markers hidden: ", hidden)


## The route point at d, offset `lat` m to the player's right, at walking eye
## height. Right = tangent rotated -90 deg in XZ, matching the node frame.
func _eye(d: float, lat: float) -> Vector3:
	var pts := _points()
	var p := MistvaleHeights.route_at(pts, d)
	var t := MistvaleHeights.route_tangent(pts, d)
	var rx := -t.y
	var rz := t.x
	var x: float = p.x + rx * lat
	var z: float = p.y + rz * lat
	return Vector3(x, _h(x, z) + EYE, z)


## The eye aims at a point on the SAME walked line, `_look` metres further on,
## also at eye height. Aiming at ground level instead would tilt every shot
## down and turn a walk into a floor inspection.
func _aim(d: float, lat: float) -> Vector3:
	var pts := _points()
	var p := MistvaleHeights.route_at(pts, d)
	var t := MistvaleHeights.route_tangent(pts, d)
	var rx := -t.y
	var rz := t.x
	var x: float = p.x + rx * lat
	var z: float = p.y + rz * lat
	return Vector3(x, _h(x, z) + EYE - tan(deg_to_rad(_pitch)) * _look, z)


func _walk() -> void:
	var pts := _points()
	var total := MistvaleHeights.route_length(pts)
	var end := _to if _to > 0.0 else total
	var d := _from
	var i := 0
	while d <= end:
		var lat := _lateral
		var pos := _eye(d, lat)
		var to: Vector3
		if _back:
			to = _aim(maxf(0.0, d - _look), lat)
		else:
			to = _aim(minf(total, d + _look), lat)
		_cam.fov = _fov
		_cam.look_at_from_position(pos, to, Vector3.UP)
		for _k in WARMUP:
			await process_frame
		await RenderingServer.frame_post_draw
		var img := root.get_texture().get_image()
		if img != null:
			var nm := "w%03d_d%04d.png" % [i, int(d)]
			img.save_png(OUT_DIR + _tag + "/" + nm)
		var t := MistvaleHeights.route_tangent(pts, d)
		var yaw := rad_to_deg(atan2(-t.x, -t.y)) if not _back else rad_to_deg(atan2(t.x, t.y))
		var row := {
			"frame": i, "d": snappedf(d, 0.1),
			"x": snappedf(pos.x, 0.1), "y": snappedf(pos.y, 0.1), "z": snappedf(pos.z, 0.1),
			"yaw": snappedf(yaw, 0.1),
			"path": snappedf(MistvaleHeights.path_distance(pos.x, pos.z), 0.1),
			"settle": snappedf(MistvaleHeights.settlement_factor(pos.x, pos.z), 0.01),
			"slope": snappedf(MistvaleHeights.slope_deg(pos.x, pos.z), 0.1),
			"skyL": 0.0, "midL": 0.0, "gndL": 0.0, "horiz": 0.0,
			"d1": 0.0, "d10": 0.0, "d30": 0.0,
		}
		# --- The §28 10 s / 30 s tests, measured on the frame we just shot ----
		#
		# These are computed HERE rather than in a Python probe reading the PNGs
		# back, because Godot writes Paeth-filtered PNG rows (measured: 523 of
		# 720 rows on a typical frame) and reversing that filter in pure Python
		# costs ~0.9 s per frame — a minute of decoding to learn numbers the
		# renderer already has in memory. The PNGs stay: they are for the human
		# eye and for the single-frame probes (grid / box).
		if img != null:
			var fp := _fingerprint(img)
			_fps.append(fp)
			var hh := img.get_height()
			row["skyL"] = snappedf(_region_lum(img, 0, 0, img.get_width(), hh / 4), 0.1)
			row["midL"] = snappedf(_region_lum(img, 0, hh / 3, img.get_width(), hh * 2 / 3), 0.1)
			row["gndL"] = snappedf(_region_lum(img, 0, hh * 3 / 4, img.get_width(), hh), 0.1)
			row["horiz"] = snappedf(_horizon(img), 0.1)
			if _fps.size() >= 2:
				row["d1"] = snappedf(_fp_dist(fp, _fps[_fps.size() - 2]), 0.01)
			if _fps.size() >= 6:
				row["d10"] = snappedf(_fp_dist(fp, _fps[_fps.size() - 6]), 0.01)
			if _fps.size() >= 16:
				row["d30"] = snappedf(_fp_dist(fp, _fps[_fps.size() - 16]), 0.01)
		_rows.append(row)
		i += 1
		d += _step


func _write_csv(out: String) -> void:
	var cols := [
		"frame", "d", "x", "y", "z", "yaw", "path", "settle", "slope",
		"skyL", "midL", "gndL", "horiz", "d1", "d10", "d30",
	]
	var f := FileAccess.open(out + "walk_" + _tag + ".csv", FileAccess.WRITE)
	if f != null:
		f.store_line(",".join(cols))
		for r in _rows:
			var parts: Array = []
			for c in cols:
				parts.append(str(r[c]))
			f.store_line(",".join(parts))
		f.close()
	# Straight to stdout as well: the CSV is for later, this table is for the
	# pass that is happening now. Columns are the two tests the addendum asks
	# for, plus the three that say whether the shot is even lit.
	print("frame    d    x      z   skyL midL gndL  horiz%   d1   d10   d30")
	for r in _rows:
		print("%5d %5.0f %6.0f %6.0f  %4.0f %4.0f %4.0f  %5.1f  %4.1f  %5.1f %5.1f"
			% [r["frame"], r["d"], r["x"], r["z"], r["skyL"], r["midL"], r["gndL"],
			   r["horiz"], r["d1"], r["d10"], r["d30"]])
