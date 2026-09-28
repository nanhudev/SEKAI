extends SceneTree
##
## LEVEL ART REVIEW CAMERA — the fixed eyes the self-iteration loop shoots from.
##
## WHY THIS IS THE FIRST THING THAT HAD TO EXIST: every previous level-art pass
## was reviewed from ad-hoc cameras chosen after the fact, which means every
## "before / after" claim compared two different framings. A map cannot be
## iterated when the camera moves between iterations. Ten points, five views
## each, same coordinates every single run, forever.
##
##   VIEW A  PLAYER FORWARD   eye 1.70 m, looking down the route of travel
##   VIEW B  PLAYER BACKWARD  180 deg from A — does the way back hold up?
##   VIEW C  45 DEG SIDE      three-quarter, 26 m off the route, 14 m up
##   VIEW D  VISTA            framing the landmark this point is supposed to see
##   VIEW E  AERIAL DEBUG     150 m up, 52 deg down — macro organisation only
##
## Usage (NOT --headless: headless disables rendering entirely):
##   Godot --path F:/SEKAI/godot --resolution 1280x720 --audio-driver Dummy \
##         --script res://tools/level_art_review.gd
##
## Output: F:/SEKAI/.render/levelart/<TAG>/R01_A.png ...
## Set TAG below (or pass `--tag=xxx`, read as a user arg).

const TAG := "p13"
const OUT_DIR := "F:/SEKAI/.render/levelart/"
const EYE := 1.70
const WARMUP := 6

## Command-line overrides, so a bisect is one shell line instead of an edit:
##   --tag=p13b            output sub-directory
##   --only=R04,R06        which review points to shoot
##   --hide=Greybox,Land/Roads   nodes to hide (comma separated)
##   --tint=Land/Roads#ff0000    repaint a subtree flat
##   --print-cam           dump every camera's world transform before shooting
##   --noshadow            turn the scene sun's shadow off (bisect: is the
##                         darkness geometry+light, or the shadow map?)
##   --sbias=f --snbias=f --sdist=f   override the scene sun's shadow bias,
##                         normal bias and max distance for the same bisect.
##                         These are RENDER DIAGNOSTICS, not art direction: the
##                         measured value gets written back into the scene.
##   --nocast=path         stop a subtree from CASTING shadows. Distinguishes
##                         "this object is being shadowed by something else"
##                         from "this object is shadowing itself", which is the
##                         one question bias tuning cannot answer.
##
## WHY: the loop fixes one thing per round and then has to PROVE the fix.
## Editing four consts per bisect and then editing them back is how a previous
## round ended up shipping a render that was still hiding a layer.
var _tag := TAG
var _only: Array = []
var _hide: Array = []
var _tint: Array = []
var _print_cam := false
var _no_shadow := false
var _sbias := -1.0
var _snbias := -1.0
var _sdist := -1.0
var _nocast := ""

func _args() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--tag="):
			_tag = a.substr(6)
		elif a.begins_with("--only="):
			_only = a.substr(7).split(",")
		elif a.begins_with("--hide="):
			_hide = a.substr(7).split(",")
		elif a.begins_with("--tint="):
			var spec := a.substr(7).split("#")
			if spec.size() == 2:
				_tint.append(spec)
		elif a == "--print-cam":
			_print_cam = true
		elif a == "--noshadow":
			_no_shadow = true
		elif a.begins_with("--sbias="):
			_sbias = float(a.substr(8))
		elif a.begins_with("--snbias="):
			_snbias = float(a.substr(9))
		elif a.begins_with("--sdist="):
			_sdist = float(a.substr(8))
		elif a.begins_with("--nocast="):
			_nocast = a.substr(9)

## Which review points to shoot this run. Empty = all ten.
## The vertical slice is R01..R06; shoot those while iterating on it and run
## the full ten only when the slice is being signed off.
const ONLY: Array = []

## Hide the greybox debug furniture? The blockout's marker poles are 10 m cyan
## masts standing exactly where the vistas are — leave them on and every vista
## shot is a shot of a cyan ball.
const HIDE_MARKERS := true
## Hide the greybox town/landmark BOXES. Turn this on once the house kit exists;
## leaving it off is what lets a pass claim progress while the town is still
## 30 flat-shaded boxes.
const HIDE_GREYBOX := false

## Fog is a GATE 5 atmosphere concern and at review time it is actively harmful:
## it washes out every long shot into a flat sheet, so half of this pass's
## frames could not be judged at all. Off for review, left alone in the scene.
const FOG_OFF := true

## Review exposure. These are the numbers the SCENE should be carrying; they
## live here so they can be dialled in against a render instead of against a
## guess, and get copied back into MistvaleRegion.tscn once they are right.
##
## WHY THE SCENE WAS UNDER-LIT BY ~4x — the whole first half of this pass was
## reviewed against it and it invalidated every "the ground is too dark" note:
## the environment was set to TONE_MAPPER_AGX, which the project's
## gl_compatibility renderer does not implement, so the tonemap was a no-op; and
## the ambient had been cut to 0.55 to cure an over-exposure that was actually
## caused by the terrain palette bug. Two bugs, one compensating the other, and
## the compensation stayed after the cause was fixed.
##
## MEASURED, not guessed: a flat #808080 surface under this rig has to land near
## mid-grey. The first calibration put it at (51,61,71) — ambient-only shading,
## barely visible — which is what the numbers above are correcting.
const AMBIENT := 1.05
const SUN := 2.20
const EXPOSURE := 1.10
## Shadows are kept ON by default — a level review with no shadows hides
## exactly the thing that makes a landform read. Flags exist so the two can be
## ruled out as the cause when the ground comes back wrong.
const SHADOW_OFF := false

## Root-level child nodes to hide for this run, by name. Exists for BISECTION:
## when a shot comes back wrong, hiding one layer at a time identifies the
## culprit in one render instead of five rounds of source reading. The pass-02
## black foreground was attributed to three different causes before this flag
## existed; it has to be possible to ask the renderer which one it is.
const HIDE_LAYERS: Array = []

## [path, "#rrggbb"] — repaint a layer with a flat, fully rough material.
##
## The last resort of the bisect: when a layer is proven to be the culprit but
## the mesh data is provably clean (normals up, colour mid-grey, no shadow), the
## question left is whether the renderer is even drawing the thing you think it
## is. Painting it red answers that in one frame.
const DEBUG_TINT: Array = []


# =============================================================================
# The ten fixed review points
# =============================================================================
#
# `x`, `z` only. Height is never authored — see the standing rule in
# MistvaleHeights: a hand-written Y that disagrees with the field turns into a
# wall or a floating camera later. `to` for VIEW D is the landmark this point
# must be able to see; where a masterplan vista already exists (V1..V9) the
# coordinate is that vista's, so the review point and the design claim are the
# same thing.
## NOTE ON PLACEMENT: a review point must stand in a SPACE, not inside a mass.
## R06, R07 and R08 were authored on the masterplan's landmark coordinates and
## all three put the camera inside the greybox block that stands there — the
## "Guild Terrace" shot was the inside of a yellow box. They are now on the
## approach to the landmark rather than on the landmark itself.
const POINTS := [
	{ "id": "R01", "name": "prologue_approach", "x": 200.0, "z": 320.0,
	  "to": Vector3(60.0, 30.0, 180.0), "note": "East Forest — the valley must reveal itself" },
	{ "id": "R02", "name": "mistvale_reveal", "x": 155.0, "z": 258.0,
	  "to": Vector3(0.0, 34.0, 60.0), "note": "V1 Forest Break — river + distant rooftops" },
	{ "id": "R03", "name": "lower_town", "x": -45.0, "z": 85.0,
	  "to": Vector3(0.0, 34.0, 0.0), "note": "Lower Town street — buildings must close it in" },
	{ "id": "R04", "name": "river", "x": 10.0, "z": 122.0,
	  "to": Vector3(10.0, 9.0, 96.0), "note": "V2 Bridge Crest — the crossing and the water" },
	{ "id": "R05", "name": "market", "x": 0.0, "z": 0.0,
	  "to": Vector3(0.0, 50.0, -45.0), "note": "V4 Market — guild axis must read" },
	{ "id": "R06", "name": "guild_terrace", "x": 0.0, "z": -30.0,
	  "to": Vector3(0.0, 34.0, 40.0), "note": "V5 Guild Terrace — civic space over the valley" },
	{ "id": "R07", "name": "bell_tower", "x": -42.0, "z": -78.0,
	  "to": Vector3(0.0, 40.0, 40.0), "note": "V6 Bell Tower balcony — the whole town below" },
	{ "id": "R08", "name": "north_gate", "x": 0.0, "z": -120.0,
	  "to": Vector3(-10.0, 130.0, -330.0), "note": "North Gate — the mountain must threaten" },
	{ "id": "R09", "name": "mountain_ascent", "x": -37.0, "z": -232.0,
	  "to": Vector3(0.0, 34.0, 40.0), "note": "V7 First Switchback — Mistvale shrinking below" },
	{ "id": "R10", "name": "ruins_approach", "x": -19.0, "z": -321.0,
	  "to": Vector3(0.0, 178.0, -360.0), "note": "V9 Ruins Forecourt — the beacon" },
]

var _cam: Camera3D
var _scene: Node3D
var _shots: Array = []


func _initialize() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)
	DisplayServer.window_set_size(Vector2i(1280, 720))
	_args()
	if _only.is_empty():
		_only = ONLY
	if _hide.is_empty():
		_hide = HIDE_LAYERS
	if _tint.is_empty():
		_tint = DEBUG_TINT
	var out := OUT_DIR + _tag + "/"
	if not DirAccess.dir_exists_absolute(out):
		DirAccess.make_dir_recursive_absolute(out)

	print("--- LEVEL ART REVIEW  tag=", _tag, " only=", _only, " ---")
	var packed: PackedScene = load("res://scenes/world/MistvaleRegion.tscn")
	_scene = packed.instantiate()
	root.add_child(_scene)
	# _initialize() runs before _ready() has fired on the builder nodes, so the
	# terrain / land / town layers are still empty shells here. Measured: the
	# first version height-sampled an unbuilt scene and every camera sat at
	# Y = 0, i.e. underground.
	await process_frame
	await process_frame
	await process_frame

	var walker := _scene.get_node_or_null("ReviewWalker")
	if walker != null:
		walker.queue_free()

	_lighting()
	_hide_furniture()
	for name_ in _hide:
		# Accepts a path, e.g. "Land/Roads", so a single sub-layer can be
		# bisected out without hiding the whole system it belongs to.
		var n := _scene.get_node_or_null(NodePath(String(name_)))
		if n != null and n is Node3D:
			(n as Node3D).visible = false
			print("bisect: hidden ", name_)
		else:
			print("bisect: NOT FOUND ", name_)
	for spec in _tint:
		var path := String(spec[0])
		var col := Color(String(spec[1]))
		var root_n := _scene.get_node_or_null(NodePath(path))
		if root_n == null:
			print("tint: NOT FOUND ", path)
			continue
		var dbg := StandardMaterial3D.new()
		dbg.albedo_color = col
		dbg.roughness = 1.0
		dbg.cull_mode = BaseMaterial3D.CULL_DISABLED
		var cnt := 0
		var st: Array = [root_n]
		while not st.is_empty():
			var m: Node = st.pop_back()
			for c in m.get_children():
				st.append(c)
				if c is MeshInstance3D:
					(c as MeshInstance3D).material_override = dbg
					cnt += 1
		print("tint: %s painted %d meshes %s" % [path, cnt, col])

	if _nocast != "":
		var nc := _scene.get_node_or_null(NodePath(_nocast))
		if nc == null:
			print("nocast: NOT FOUND ", _nocast)
		else:
			var hit := 0
			var st2: Array = [nc]
			while not st2.is_empty():
				var m: Node = st2.pop_back()
				for c in m.get_children():
					st2.append(c)
				if m is GeometryInstance3D:
					(m as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
					hit += 1
			print("nocast: %s -> %d casters disabled" % [_nocast, hit])

	_cam = Camera3D.new()
	_cam.fov = 72.0
	_cam.near = 0.1
	_cam.far = 2500.0
	root.add_child(_cam)
	_cam.current = true

	_build_shots()
	print("shots: ", _shots.size())
	for s in _shots:
		await _capture(s)
	print("DONE -> ", out)
	quit(0)


## Review light: enough to read landform, not enough to flatter it.
##
## The scene sun is authored for the game's own mood and leaves the mountain's
## lee flank black, which makes an unreviewable screenshot. This is RENDER ONLY
## — nothing is written back into the scene.
func _lighting() -> void:
	# NO FILL LIGHT ANY MORE.
	#
	# This rig used to add its own DirectionalLight3D with
	# sky_mode = SKY_MODE_LIGHT_ONLY, which sounds like a fill and is not:
	# LIGHT_ONLY means the light contributes to the SKY and nothing else, so it
	# never touched a single triangle of the map. It was a decoration that let
	# two passes believe shadowed geometry was being opened up when the scene
	# was still lit by a single key and 0.32 ambient. The scene now carries a
	# real sky-bounce light (see MistvaleRegion.tscn / Bounce); if a view is
	# still dark, that is a scene bug and has to be fixed in the scene.
	#
	# The rig used to set its own ambient, sun energy and tonemap, which meant
	# the review was judging a scene that did not exist: the lighting it showed
	# was the rig's, not the game's, and when the SCENE's sun turned out to be
	# pointing below the horizon the rig had been quietly papering over it for
	# two entire passes. A review camera must look through the game's own eyes.
	#
	# The only things still touched are the two that are legitimately a review
	# concern rather than a game one, and both are behind flags.
	var we := _scene.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if FOG_OFF and we != null and we.environment != null:
		we.environment.fog_enabled = false
	var sun := _scene.get_node_or_null("Sun") as DirectionalLight3D
	if sun != null:
		if SHADOW_OFF or _no_shadow:
			sun.shadow_enabled = false
		if _sbias >= 0.0:
			sun.shadow_bias = _sbias
		if _snbias >= 0.0:
			sun.shadow_normal_bias = _snbias
		if _sdist >= 0.0:
			sun.directional_shadow_max_distance = _sdist


func _hide_furniture() -> void:
	if not HIDE_MARKERS:
		return
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

	if HIDE_GREYBOX:
		var gb := _scene.get_node_or_null("Greybox")
		if gb != null:
			for c in gb.get_children():
				if String(c.name) == "Town" or String(c.name) == "Landmarks":
					c.visible = false
					print("greybox ", c.name, " hidden")


# =============================================================================
# Shot construction
# =============================================================================

## Where the player's feet are. NOT MistvaleHeights.height_at — at the bridge
## crest the ground is the river bed 3 m below the deck, and sampling it put the
## "V2 Bridge Crest" review camera under the bridge.
func _h(x: float, z: float) -> float:
	var land := _scene.get_node_or_null("Land")
	if land != null and land.has_method("surface_height"):
		return land.surface_height(x, z)
	return MistvaleHeights.height_at(x, z)


## Direction of travel at a review point: the tangent of the nearest road, taken
## from whichever road the masterplan actually walks through here.
##
## Derived rather than hand-authored because a "forward" shot that looks along
## the wrong road is not a forward shot — it is a shot of a hedge.
func _heading(x: float, z: float) -> Vector2:
	var best_d := 1e9
	var best_t := Vector2(0.0, -1.0)
	for road in MistvaleHeights.ROADS:
		var pts: Array = road[0]
		var total := MistvaleHeights.route_length(pts)
		var d := 0.0
		while d <= total:
			var p := MistvaleHeights.route_at(pts, d)
			var dd := Vector2(p.x - x, p.y - z).length()
			if dd < best_d:
				best_d = dd
				best_t = MistvaleHeights.route_tangent(pts, d)
			d += 4.0
	return best_t


func _build_shots() -> void:
	for p in POINTS:
		if not _only.is_empty() and not _only.has(p["id"]):
			continue
		var x: float = p["x"]
		var z: float = p["z"]
		var gy := _h(x, z)
		var t := _heading(x, z)
		# Yaw from a tangent. Godot's forward is -Z, and a node rotated by `yaw`
		# about Y points at (-sin yaw, 0, -cos yaw). So to point that tangent
		# down the camera's forward, yaw = atan2(-t.x, -t.y).
		#
		# The first version used atan2(t.x, t.y), which is exactly 180 deg out:
		# every "PLAYER FORWARD" shot in pass 01 and 02 was the backward shot
		# and vice versa, and the two views were being reviewed under each
		# other's captions.
		var yaw := atan2(-t.x, -t.y)
		var eye := Vector3(x, gy + EYE, z)

		# --- A: forward ----------------------------------------------------
		_shots.append({
			"name": "%s_A_forward" % p["id"], "fov": 72.0,
			"pos": eye,
			"to": eye + Vector3(-sin(yaw) * 40.0, -1.2, -cos(yaw) * 40.0),
			"note": p["note"],
		})
		# --- B: backward ---------------------------------------------------
		_shots.append({
			"name": "%s_B_back" % p["id"], "fov": 72.0,
			"pos": eye,
			"to": eye + Vector3(sin(yaw) * 40.0, -1.2, cos(yaw) * 40.0),
			"note": "B — the way back must also compose",
		})
		# --- C: 45 deg side ------------------------------------------------
		# Off to the route's left and up, looking back at the point: this is the
		# shot that shows whether the space has layers or is one flat plane.
		var lat := Vector2(-t.y, t.x)
		var cy := yaw - deg_to_rad(45.0)
		_shots.append({
			"name": "%s_C_side" % p["id"], "fov": 60.0,
			"pos": eye + Vector3(lat.x * 26.0, 14.0, lat.y * 26.0),
			"to": eye + Vector3(-sin(cy) * 14.0, 0.6, -cos(cy) * 14.0),
			"note": "C — spatial layering",
		})
		# --- D: vista ------------------------------------------------------
		_shots.append({
			"name": "%s_D_vista" % p["id"], "fov": 58.0,
			"pos": eye, "to": p["to"] as Vector3,
			"note": p["note"],
		})
		# --- E: aerial debug -----------------------------------------------
		_shots.append({
			"name": "%s_E_aerial" % p["id"], "fov": 55.0,
			"pos": Vector3(x + 60.0, gy + 150.0, z + 90.0),
			"to": Vector3(x, gy, z),
			"note": "E — macro organisation (debug only)",
		})


func _capture(s: Dictionary) -> void:
	_cam.fov = float(s["fov"])
	_cam.look_at_from_position(s["pos"] as Vector3, s["to"] as Vector3, Vector3.UP)
	if _print_cam:
		print("cam %-18s pos(%.1f %.1f %.1f) -> to(%.1f %.1f %.1f)  fov %.0f"
			% [s["name"], (s["pos"] as Vector3).x, (s["pos"] as Vector3).y,
			   (s["pos"] as Vector3).z, (s["to"] as Vector3).x,
			   (s["to"] as Vector3).y, (s["to"] as Vector3).z, float(s["fov"])])
	for _i in WARMUP:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	if img == null:
		print("FAIL ", s["name"], " — readback null")
		return
	var path := OUT_DIR + _tag + "/" + String(s["name"]) + ".png"
	var err := img.save_png(path)
	print("%-22s %s  %s" % [s["name"], "ok" if err == OK else "ERR %d" % err, s["note"]])
