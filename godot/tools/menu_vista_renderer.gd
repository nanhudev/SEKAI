extends SceneTree
##
## Title-screen vistas of Mistvale, rendered from the REAL region scene.
##
## WHY THIS IS NOT region_compose_renderer.gd: that tool frames shots to answer
## level-design questions ("can you read three terraces from here?"). This one
## frames ONE shot to answer a UI question — it has to survive a menu sitting on
## top of it and still say "this is a fantasy RPG, and that is a place".
## Different job, different camera discipline:
##
##   · eye height on a real stand, never an aerial. A title screen shot from a
##     drone reads as a flythrough still, not as somewhere you are about to be.
##   · the world's interest lives in the RIGHT two thirds, because UI PASS 02
##     puts the menu down the left and the world must not be behind it.
##   · almost still. No orbit, no reveal move — the page supplies the drift.
##
## REVIEW MARKERS ARE SWITCHED OFF AT THE SOURCE. region_compose_renderer.gd
## hides them after the fact by name pattern, which it documents as fragile.
## The greybox exposes show_vistas / show_combat / show_narrative / show_routes,
## and setting those BEFORE the node enters the tree means the markers are never
## built at all — no renaming, no name patterns, nothing to get wrong.
##
## Usage (NOT --headless: headless disables rendering entirely):
##   godot --path godot --resolution 1600x900 --audio-driver Dummy \
##         --script res://tools/menu_vista_renderer.gd -- --size=2560x1440
##
## User args:
##   --size=WxH     render resolution (default 1600x900)
##   --out=PATH     output directory
##   --only=53,54   render only these shot ids
##   --name=FILE    fixed output name (needs exactly one shot). This is how the
##                  shipping background is produced, so the UI's path stays put
##                  while the scratch shot list keeps its batch numbering.
##
## Shipping render (the file ui_web/v2/v2.config.js points at):
##   godot --path godot --resolution 2560x1440 --audio-driver Dummy \
##         --script res://tools/menu_vista_renderer.gd \
##         -- --size=2560x1440 --out=F:/SEKAI/assets_source/ui/world/ \
##            --only=53 --name=mistvale_menu_v1
##
## Output default: F:/SEKAI/assets_source/ui/world/

const DEFAULT_OUT := "F:/SEKAI/assets_source/ui/world/"
const EYE := 1.70
const WARMUP := 10

var out_dir := DEFAULT_OUT
var size := Vector2i(1600, 900)
var only: PackedStringArray = PackedStringArray()
## Fixed output filename, for the shot that actually ships.
##
## The shot list is a scratch pad and its names carry the batch number, but the
## UI reads ONE file by a stable path (see ui_web/v2/v2.config.js WORLD.base).
## Letting the shipping name be "53_shelf_final" would mean the next batch that
## renames a shot silently orphans the UI's background — so the shipping render
## is asked for by name.
##
## Only honoured when exactly one shot is rendered: a fixed name for several
## shots would have them overwrite each other.
var fixed_name := ""

var shots: Array = []
## Kept so a shot can move it — see the sun note in _atmosphere().
var _sun: DirectionalLight3D = null
## The atmosphere pass's environment, handed to the capture camera directly —
## see the SubViewport note in _initialize().
var _env: Environment = null
## The SubViewport every shot is captured from, at the exact requested size.
var _vp: SubViewport = null


## Point the key light. `pitch` is negative-down from horizontal; `yaw` 0 = the
## sun stands due south of the subject (A DirectionalLight3D points along -Z).
func _apply_sun(pitch: float, yaw: float) -> void:
	if _sun == null:
		return
	_sun.rotation_degrees = Vector3(-absf(pitch), yaw, 0.0)


func _initialize() -> void:
	_parse_args()
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)
	DisplayServer.window_set_size(size)

	if DirAccess.open(out_dir) == null:
		DirAccess.make_dir_recursive_absolute(out_dir)

	print("loading MistvaleRegion ...")
	var packed: PackedScene = load("res://scenes/world/MistvaleRegion.tscn")
	var scene: Node3D = packed.instantiate()

	# Markers off BEFORE the tree is entered, so the builders never spawn them.
	# See the header: this is the whole reason this tool does not reuse the
	# compose renderer's hide-after-the-fact pass.
	var gb := scene.get_node_or_null("Greybox")
	if gb != null:
		gb.set("show_vistas", false)
		gb.set("show_combat", false)
		gb.set("show_narrative", false)
		gb.set("show_routes", false)
		print("review markers: disabled at source")

	root.add_child(scene)
	# _initialize() runs while the SceneTree is still coming up, so the builder
	# nodes' _ready() has NOT fired: Terrain / Greybox / Ascent are all still
	# empty here and only fill in on the first frame. Anything that inspects the
	# built scene has to wait, or it silently inspects nothing.
	await process_frame
	await process_frame
	print("scene built")

	# The review walker is a CharacterBody3D with its own Camera3D and it fights
	# the render camera for `current` and for the mouse.
	var walker := scene.get_node_or_null("ReviewWalker")
	if walker != null:
		walker.queue_free()
	# The walker's HUD is a CanvasLayer on the REGION root (not a child of the
	# walker), so freeing the walker does not free it. It draws into the WINDOW
	# viewport; the SubViewport below would not include it anyway, but a debug
	# layer has no business surviving a shipping render — free it.
	var hud := scene.get_node_or_null("RegionWalkHUD")
	if hud != null:
		hud.queue_free()

	_atmosphere(scene)
	_sky_clouds(scene)

	## Capture happens in a SubViewport at the EXACT requested size. The old
	## code captured the window backbuffer, and Windows clamps a window to the
	## monitor's work area: a --size=2560x1440 request on a 1080p screen came
	## back as a ~1924x1061 image — silently the wrong size AND the wrong
	## aspect (16:8.8), which cover-fit then crops. A SubViewport has no work
	## area. It also cannot see the window's CanvasLayers, which is what kept
	## the walker HUD out of the frame even before the free above.
	_vp = SubViewport.new()
	_vp.size = Vector2i(size)
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_vp)
	var cam := Camera3D.new()
	cam.near = 0.1
	cam.far = 4000.0
	_vp.add_child(cam)
	cam.current = true
	# A SubViewport does not inherit the WorldEnvironment node that sits in the
	# window's tree — Camera3D.environment overrides it, so hand the atmosphere
	# pass's environment to the camera directly.
	if _env != null:
		cam.environment = _env

	_build_shots()
	var todo: Array = []
	for s in shots:
		if only.size() > 0 and not only.has(String(s["id"])):
			continue
		todo.append(s)
	if fixed_name != "" and todo.size() != 1:
		print("WARN --name= ignored: it needs exactly one shot, got %d" % todo.size())
		fixed_name = ""
	var done := 0
	for s in todo:
		await _capture(cam, s)
		done += 1
	print("DONE  rendered=%d  size=%dx%d  out=%s" % [done, size.x, size.y, out_dir])
	quit(0)


func _parse_args() -> void:
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		if s.begins_with("--size="):
			var parts := s.substr(7).split("x")
			if parts.size() == 2:
				size = Vector2i(int(parts[0]), int(parts[1]))
		elif s.begins_with("--out="):
			out_dir = s.substr(6)
		elif s.begins_with("--only="):
			only = PackedStringArray(s.substr(7).split(","))
		elif s.begins_with("--name="):
			fixed_name = s.substr(7)


## ---------------------------------------------------------------------------
## Atmosphere — render-only. NOTHING here is written back to the scene file.
## ---------------------------------------------------------------------------
## The region ships tuned for legibility at 600 m ("GATE 5 owns the real
## atmosphere pass"), which is correct for design review and wrong for a title
## screen: flat ambient, thin fog, and a horizon that runs away as one grey
## sheet. A title screen wants DEPTH — the far ground has to disappear into haze
## so the eye reads three planes (foreground, town, mountain) instead of one.
func _atmosphere(scene: Node3D) -> void:
	var we := scene.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if we != null and we.environment != null:
		_env = we.environment
		var e := _env
		# AGX, not FILMIC. Filmic blew the town, terraces and mountain into one
		# white mass on the compose pass; AGX holds the ground's modelling.
		e.tonemap_mode = Environment.TONE_MAPPER_AGX
		# 0.82, not 1.0. At 1.0 with a 1.45 sun the town's warm tan albedo
		# saturated to flat cream and every surface lost its modelling — batch 3
		# came back as one white paste with a grey sky. Pulling exposure down
		# restores the value separation that the blockout has no texture to
		# provide.
		e.tonemap_exposure = 0.92
		e.tonemap_white = 2.2

		# Flat ambient so a shadow can be dark without being empty. Sky ambient
		# is directional: it lights up-facing surfaces and leaves the lee flank
		# black, which is how compose shots first came back as silhouettes.
		e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		e.ambient_light_color = Color(0.52, 0.60, 0.72)
		e.ambient_light_energy = 0.52

		# Fog is the depth in this frame. The valley is humid and the far plane
		# is empty greybox — haze is what makes that read as distance instead of
		# as a missing asset.
		e.fog_enabled = true
		e.fog_light_color = Color(0.86, 0.87, 0.86)
		e.fog_light_energy = 1.12
		e.fog_density = 0.0034
		e.fog_aerial_perspective = 0.6
		e.fog_sky_affect = 0.24
		# Height fog is what keeps this from being a screen filter: mist pools
		# BELOW the given altitude and thins above it, so the valley goes soft
		# while the ridge and the sky stay clean.
		#
		# 0.042 was too much and produced a specific, ugly artefact worth naming:
		# at that rate the height term for anything above ~150 m is essentially
		# zero, so the distant ridge went to 96 % haze (invisible) while the scar
		# sitting on TOP of that ridge at 196 m stayed perfectly crisp — and the
		# result read as a cream plank floating in the sky. If the mountain is
		# invisible, its crest is not a crest. 0.011 keeps both.
		if e.get("fog_height") != null:
			e.fog_height = 58.0
			e.fog_height_density = 0.011
		else:
			print("note: fog_height unavailable — falling back to uniform depth fog")

		# The sky is not decoration; it is most of the frame in a north-facing
		# shot and it is where "misty river valley" is won or lost. The scene
		# ships a saturated postcard blue (0.38, 0.54, 0.76) which reads as
		# "generic fantasy wallpaper" — the exact signature this pass exists to
		# remove. Desaturated toward a hazy high overcast, with the horizon only
		# faintly warmer than the zenith so the mountain has something to
		# separate against.
		var sky: Sky = e.sky
		if sky != null and sky.sky_material is ProceduralSkyMaterial:
			var sm: ProceduralSkyMaterial = sky.sky_material
			sm.sky_top_color = Color(0.44, 0.53, 0.64)
			sm.sky_horizon_color = Color(0.79, 0.81, 0.81)
			sm.sky_curve = 0.16
			sm.ground_bottom_color = Color(0.30, 0.32, 0.33)
			sm.ground_horizon_color = Color(0.70, 0.72, 0.71)
			sm.sun_angle_max = 1.2
			sm.sun_curve = 0.08
		else:
			print("note: sky material is not ProceduralSkyMaterial — left as-is")

	# The sun is the one light that matters, and its DIRECTION IS A COMPOSITION
	# DECISION, not a scene property.
	#
	# A camera looking north sees the town's SOUTH faces; a camera looking south
	# sees its NORTH faces. One sun cannot front-light both — and getting this
	# wrong is not a subtle shading issue: batch 3's south-facing shots came back
	# with the entire foreground slope in shadow as a flat navy mass, because the
	# scene's key light sits in the south-east and every surface facing the lens
	# was therefore facing away from it.
	#
	# So each shot carries its own sun. A DirectionalLight3D points along its own
	# -Z, so rotation.y = 0 aims it at north — i.e. the sun stands due south of
	# whatever you are looking at. Pick the yaw to put the light behind the
	# camera's shoulder, lower it for long shadows, and the blockout gains the one
	# thing untextured boxes cannot otherwise have: directional modelling.
	var sun := scene.get_node_or_null("Sun") as DirectionalLight3D
	_sun = sun
	if sun != null:
		sun.light_energy = 1.45
		sun.light_color = Color(1.0, 0.92, 0.80)
		sun.light_indirect_energy = 0.36
		sun.shadow_enabled = true
		sun.directional_shadow_max_distance = 400.0
		sun.shadow_bias = 0.05
		_apply_sun(20.0, 22.0)

	# A cool counter-light from behind so the mountain's north face is not a
	# hole. LIGHT_ONLY because a DirectionalLight3D in LIGHT_AND_SKY mode also
	# draws its own sun into the procedural sky and we would get two.
	var fill := DirectionalLight3D.new()
	fill.name = "MenuFill"
	fill.light_energy = 0.42
	fill.light_color = Color(0.72, 0.80, 0.95)
	fill.shadow_enabled = false
	fill.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	fill.rotation = Vector3(deg_to_rad(-26.0), deg_to_rad(196.0), 0.0)
	root.add_child(fill)
	print("atmosphere applied")


## ---------------------------------------------------------------------------
## Cloud decks
## ---------------------------------------------------------------------------
## ProceduralSkyMaterial has no clouds, so the sky is otherwise a clean vertical
## gradient — which is the single most recognisable signature of a generated
## background. Two scrolling noise decks give it weather instead. They are
## render-only props: they are not saved into the scene and are not canon art.
##
## They also double as the movie's motion source — see menu_vista_movie.gd,
## which drives `offset_uv` on these same two materials.
const CLOUD_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;
uniform sampler2D noise_tex : filter_linear, repeat_enable;
uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float uv_scale = 3.0;
uniform vec2 drift = vec2(0.0, 0.0);
uniform float coverage : hint_range(0.0, 1.0) = 0.5;
uniform float softness : hint_range(0.01, 1.0) = 0.30;
varying vec2 v_uv;
void vertex() { v_uv = UV; }
void fragment() {
	vec2 p = v_uv * uv_scale + drift;
	float n = texture(noise_tex, p).r;
	float a = smoothstep(coverage, coverage + softness, n);
	ALBEDO = tint.rgb;
	ALPHA = a * tint.a;
}
"""


func _sky_clouds(scene: Node3D) -> void:
	# Two decks rather than one: a higher, thinner sheet that barely moves and a
	# lower, softer bank that moves faster. One deck reads as a texture; two
	# read as weather.
	_deck(scene, {
		"name": "CloudDeckHigh",
		"y": 620.0,
		"span": 7000.0,
		"tint": Color(1.0, 0.98, 0.94, 0.42),
		"uv_scale": 2.2,
		"coverage": 0.46,
		"softness": 0.44,
		"seed": 11,
	})
	_deck(scene, {
		"name": "CloudDeckLow",
		"y": 380.0,
		"span": 5200.0,
		"tint": Color(0.92, 0.94, 0.97, 0.40),
		"uv_scale": 3.4,
		"coverage": 0.44,
		"softness": 0.38,
		"seed": 29,
	})
	print("cloud decks: 2")


func _deck(parent: Node3D, cfg: Dictionary) -> void:
	var noise := FastNoiseLite.new()
	noise.seed = int(cfg["seed"])
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.006
	noise.fractal_octaves = 5
	noise.fractal_lacunarity = 2.1

	var tex := NoiseTexture2D.new()
	tex.width = 512
	tex.height = 512
	tex.seamless = true
	tex.noise = noise

	var sh := Shader.new()
	sh.code = CLOUD_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("noise_tex", tex)
	mat.set_shader_parameter("tint", cfg["tint"])
	mat.set_shader_parameter("uv_scale", float(cfg["uv_scale"]))
	mat.set_shader_parameter("coverage", float(cfg["coverage"]))
	mat.set_shader_parameter("softness", float(cfg["softness"]))
	mat.set_shader_parameter("drift", Vector2.ZERO)

	var plane := PlaneMesh.new()
	plane.size = Vector2(float(cfg["span"]), float(cfg["span"]))
	var mi := MeshInstance3D.new()
	mi.name = String(cfg["name"])
	mi.mesh = plane
	mi.material_override = mat
	mi.position = Vector3(0.0, float(cfg["y"]), -80.0)
	# Clouds are above the camera looking down at them; the plane's own winding
	# must not hide it, hence cull_disabled in the shader.
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


## ---------------------------------------------------------------------------
## Shot list
## ---------------------------------------------------------------------------
func _h(x: float, z: float) -> float:
	return MistvaleHeights.height_at(x, z)


## Camera at eye height on the ground, at (x, z).
func _stand(x: float, z: float, eye: float = EYE) -> Vector3:
	return Vector3(x, _h(x, z) + eye, z)


func _build_shots() -> void:
	## BATCH 5 — the last pass, and what batches 1-4 taught.
	##
	## 1. A greybox carries SILHOUETTE, MASSING and DEPTH, not surface. Up close
	##    it is legible as a plan and illegible as a place — no windows, doors,
	##    streets or roofs, so every street-level frame is a wall of blank box
	##    (batches 1-2). Distance is not a compromise; it is the only place the
	##    massing reads at all.
	## 2. A LONG LENS turns four boxes into a settlement: it compresses the
	##    terraces so they stack instead of splaying, and fills the frame with
	##    subject instead of empty ground plane.
	## 3. THE SUN FOLLOWS THE CAMERA. Looking north you see south faces, looking
	##    south you see north faces; one azimuth cannot light both (batch 3's
	##    south-facing shots came back as flat navy shadow). `sun_yaw` is per shot.
	## 4. HEIGHT FOG HAS A CEILING. Above roughly 150 m it stops doing anything,
	##    so an over-strong height density erases the mountain and leaves the
	##    scar — which sits on top of that mountain — as a plank in the sky.
	## 5. CAMERA HEIGHT ABOVE THE NEAR ROOFS IS WHAT FRAMES THIS REGION. From the
	##    river at eye level the lower town is a wall across the bottom 60 % of
	##    the frame; from the forest terrace at ~33 m the same blocks drop to a
	##    foreground band and the town becomes the subject.
	##
	## Every shot below also aims to the LEFT of the town, so the town lands
	## right of centre and the left third stays quiet — that is where UI PASS 02
	## puts the logo and the menu, and text must not sit on the best vista.

	## The one that is meant to ship. Elevated near bank, long lens, town right
	## of centre under a hazed valley with the ridge crest above it.
	shots.append({
		"id": "50",
		"name": "50_vista_final",
		"pos": _stand(150.0, 252.0, 2.2),
		"to": Vector3(-58.0, 96.0, -70.0),
		"fov": 32.0,
		"sun_pitch": 17.0,
		"sun_yaw": 30.0,
	})

	# Variants of the same vantage: wider, and tighter on the rooftops.
	shots.append({
		"id": "51",
		"name": "51_vista_wide",
		"pos": _stand(150.0, 252.0, 2.2),
		"to": Vector3(-56.0, 104.0, -90.0),
		"fov": 40.0,
		"sun_pitch": 17.0,
		"sun_yaw": 30.0,
	})
	shots.append({
		"id": "52",
		"name": "52_vista_tight",
		"pos": _stand(150.0, 252.0, 2.2),
		"to": Vector3(-46.0, 88.0, -60.0),
		"fov": 27.0,
		"sun_pitch": 17.0,
		"sun_yaw": 30.0,
	})

	# V1's rock shelf — the region's own designed first sight of the town, and
	# the only vantage with the forest on the near side.
	shots.append({
		"id": "53",
		"name": "53_shelf_final",
		"pos": Vector3(155.0, 41.5 + 10.5 + EYE, 258.0),
		"to": Vector3(-62.0, 92.0, -40.0),
		"fov": 30.0,
		"sun_pitch": 19.0,
		"sun_yaw": 34.0,
	})
	shots.append({
		"id": "54",
		"name": "54_shelf_wide",
		"pos": Vector3(155.0, 41.5 + 10.5 + EYE, 258.0),
		"to": Vector3(-60.0, 100.0, -70.0),
		"fov": 36.0,
		"sun_pitch": 19.0,
		"sun_yaw": 34.0,
	})

	# From the caravan road further south and higher: the whole valley in one
	# frame with the town small on its terrace.
	shots.append({
		"id": "55",
		"name": "55_road_final",
		"pos": _stand(196.0, 286.0, 2.2),
		"to": Vector3(-70.0, 110.0, -80.0),
		"fov": 30.0,
		"sun_pitch": 18.0,
		"sun_yaw": 32.0,
	})


func _capture(cam: Camera3D, s: Dictionary) -> void:
	cam.fov = float(s["fov"])
	# Per-shot light. Default: sun in the south (yaw 22), which front-lights the
	# south faces a north-looking camera sees.
	var sp: float = float(s.get("sun_pitch", 20.0))
	var sy: float = float(s.get("sun_yaw", 22.0))
	_apply_sun(sp, sy)
	cam.look_at_from_position(s["pos"] as Vector3, s["to"] as Vector3, Vector3.UP)
	for i in WARMUP:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := _vp.get_texture().get_image()
	if img == null:
		print("FAIL ", s["name"], " — readback null")
		return
	var file := fixed_name if fixed_name != "" else String(s["name"])
	var path := out_dir + file + ".png"
	var err := img.save_png(path)
	print("%-30s %s  sun=%.0f/%.0f" % [s["name"], "ok" if err == OK else "ERR %d" % err, sp, sy])
