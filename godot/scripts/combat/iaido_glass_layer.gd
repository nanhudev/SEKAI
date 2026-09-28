extends CanvasLayer
class_name IaidoGlassLayer
# SEKAI · Iaido reality glass (V3).
#
# WHAT CHANGED AND WHY
#
# V2 built the panes from a real Voronoi tessellation of the shot plane, which
# fixed the "playing card" problem — the shards were irregular convex polygons
# that genuinely tiled. What it did not fix is that every pane was still a single
# flat glassy colour. A shard of broken REALITY has to be a piece of the picture:
# the player should be able to see the building and the ground and the sky inside
# the glass, chopped along the fracture lines. Fourteen grey-blue polygons are
# confetti no matter how irregular their outlines are.
#
# So V3 does three things:
#
#   1. THE FRACTURE COMES FROM THE UE5 LAB. `ue5_lab/RealityGlass_Lab` computes
#      the tessellation with UE's own Geometry Script (append_voronoi_diagram2d)
#      under a design rule — cells fine next to the cut, coarse away from it,
#      anisotropic, no two neighbours the same size — and bakes the cell
#      polygons to `resources/vfx/reality_fracture.json`. This file loads that
#      bake and falls back to its own tessellation only if the bake is missing.
#      The UE5 project is a design and bake tool; the runtime is Godot.
#
#   2. EVERY PANE CARRIES THE FROZEN WORLD. The vertex UV is the position the
#      vertex had in the shattered plane, so the fragment shader can reconstruct
#      a screen UV and sample a capture of the frame taken at the hero freeze.
#      The image is welded to the pane, so it turns and falls with it.
#
#   3. AT t = 0 THE PANES RECONSTRUCT THE ORIGINAL FRAME. Nothing is offset on
#      detach; each pane starts exactly where it was cut from and then diverges.
#      That is the acceptance test for "these all came from one surface".
#
# They live in their own transparent viewport composited above the world split,
# so a shard is never torn or displaced by the screen shader.

const SHARD_Z := -0.55
const EDGE_VERTEX := Color(1.0, 1.0, 1.0, 1.0)
const BODY_VERTEX := Color(0.0, 0.0, 0.0, 1.0)
const THICKNESS := 0.012
# Width of the bright fracture rim, in the same units as the fracture field
# (1.0 = half the screen height). This is the number that decides whether a
# shard reads as a pane of glass or as an opaque white card.
const RIM_WIDTH := 0.013
const MIN_CELL_AREA := 0.010
# THE MAIN SHARDS, baked by the UE5 lab (`ue5_lab/RealityGlass_Lab`). 18 large
# irregular convex polygons, uneven in size, produced by UE's own Geometry
# Script Voronoi with a deliberately non-uniform sample distribution. These are
# the pieces the surface actually comes apart into.
#
# The FINE 202-cell network is NOT built as geometry. It ships as a texture
# (reality_crack_mask.png) and is sampled in the shard shader, in the same plane
# space as the frozen world, so every shard carries the same internal cracking
# and the network stays continuous across shard boundaries. 202 panes would also
# be 202 draw calls for something that reads better as material.
const SHARD_BAKE := "res://resources/vfx/reality_shards.json"
const CRACK_MASK := "res://resources/vfx/reality_crack_mask.png"
const EDGE_MASK := "res://resources/vfx/reality_edge_mask.png"
const FLOW_MASK := "res://resources/vfx/reality_flow_mask.png"
# The cut's normal, in the bake's plane space, y-DOWN — the frame the shaders
# take `plane_cut_normal` in.
#
# IT IS DERIVED, NOT AUTHORED. This used to be the const
# `Vector2(0.5, 0.8660254)` — the correct number for a -30 degree cut, and a
# second, hard-coded copy of an angle the tuning already owns. Two sources for
# one angle is precisely the fault the shared fracture field exists to delete,
# and it survived only because the angle had never been changed: 玻璃要按照切口
# 裂开 instead of along whatever the bake happened to be built with. It is
# computed in `build()` from the live `IaidoTuning.cut_angle_degrees` now, and
# this default is only what a material gets if `build()` never ran.
var plane_cut_normal := Vector2(0.5, 0.8660254)
# The height pixel figures are authored against, shared with
# iaido_fracture_field.gdshaderinc (IAIDO_AUTHORED_PX). separation_px arrives
# here in those pixels and is converted to plane units with it.
const AUTHORED_PX := 1080.0

enum Behaviour { FALL, DRIFT, VOID, STILL }

@onready var player: CharacterBody3D = get_parent().get_node("Player")
@onready var camera: Camera3D = player.get_node("CameraRig/LookPivot/MotionPivot/ShakePivot/Camera3D")

var viewport: SubViewport
var foreground_camera: Camera3D
var image_rect: TextureRect
var shards: Array[Node3D] = []
var shard_data: Array[Dictionary] = []
var active := false
# TEST A has to be a lie-proof switch.
#
# The panes read `IaidoTuning.fracture_at()` / `shatter_at()` themselves rather
# than taking them off the director's frame dict — that is deliberate, it keeps
# the glass on the world's clock. But it also meant `SEKAI_NO_CRACK=1` zeroed
# the world pass's cracks while the panes went on drawing theirs, so a render
# labelled "no cracks" still had cracks in it. An ablation that only covers one
# of the two surfaces that draw the network is worse than no ablation at all.
var suppress_crack := false
# Does the glass continue the split? Off only under SEKAI_NO_PANE_SPLIT, which
# exists to answer one question: if I take the pane displacement away, does the
# glass reassemble into one surface? If it does, the displacement is what was
# carrying the cut — and if nothing changes, the split was never reaching the
# glass in the first place, which is exactly the bug that shipped.
var suppress_pane_split := false
var baked_aspect := 0.0
var capture: ImageTexture
var capture_aspect := 1.7777
var capture_half := 1.15
# The half-height the capture was taken at. The shards are placed against this
# rather than against the live camera, so the reconstruction is exact even if
# something later nudges the FOV.
# Set by _build_pane_mesh(): the shard's own centre, in the bake's y-up plane
# frame. The mesh is authored in local units, so this is what converts a local
# vertex back into the absolute coordinate the UV needs.
var _uv_origin := Vector2.ZERO
# Baked crack network, loaded once. Missing files degrade to "no internal
# cracking" rather than to a build error.
var crack_tex: Texture2D
var edge_tex: Texture2D
var flow_tex: Texture2D

# --- the capture rig --------------------------------------------------------
#
# THE GLASS CARRIES THE WORLD. NOT THE FOREGROUND.
#
# `capture_world()` used to read the ROOT viewport, which is the finished
# composite: the 3D world, the split pass on canvas layer 6, the panes on 7 —
# and `ForegroundWeaponLayer` on 8, which draws the player's own sword on its
# own canvas so the split shader can never tear or desaturate it.
#
# That layer is not part of the surface that shatters; it is the thing doing the
# watching. Freezing it into the panes welded a second, complete sword into the
# glass at exactly the pose the blade held at `capture_time` — and it stayed
# there for the rest of the ceremony, because the panes do. The instant the live
# blade left that pose the shot contained 两层刀: one sword in the foreground,
# animated, and one inside the glass, stuck.
#
# So the capture gets a viewport of its own that:
#   * shares the SAME World3D (`world_3d`, not `own_world_3d`) — a second CAMERA
#     on the one world, not a second world;
#   * carries the SAME split material instance, so the frozen picture still
#     carries the cut, the grey drain and the void. A second material would be a
#     second set of numbers for one event, which is the fault this project has
#     already paid for twice;
#   * mirrors the main camera, `cull_mask` included — and the main camera's mask
#     already excludes `ForegroundWeaponLayer.WEAPON_LAYER`, so the weapon is
#     left out here for exactly the reason it is left out of the 3D pass.
#
# Being a SubViewport, it contains no canvas layers at all: no weapon, no HUD,
# and — importantly — not the panes themselves, which would otherwise photograph
# their own past.
var capture_viewport: SubViewport
var capture_camera: Camera3D
var capture_material: ShaderMaterial
var capture_armed := false
var capture_taken := false
var capture_split_material: ShaderMaterial


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 7
	suppress_crack = OS.get_environment("SEKAI_NO_CRACK") != ""
	suppress_pane_split = OS.get_environment("SEKAI_NO_PANE_SPLIT") != ""
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
	# Starts hidden for the same reason `_publish` exists: until the viewport has
	# rendered once there is no frame to blit, and the viewport starts disabled.
	image_rect.visible = false
	add_child(image_rect)
	# A 1x1 placeholder so a shard drawn before the capture degrades to a dark
	# pane instead of sampling an unbound texture.
	var blank := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	blank.fill(Color(0.02, 0.03, 0.05, 1.0))
	capture = ImageTexture.create_from_image(blank)

	# The UE5-baked crack network. In the same plane space as the world capture,
	# so the fragment shader can index it with the very same uv.
	crack_tex = _load_mask(CRACK_MASK)
	edge_tex = _load_mask(EDGE_MASK)
	flow_tex = _load_mask(FLOW_MASK)


func _load_mask(path: String) -> Texture2D:
	if not ResourceLoader.exists(path):
		push_warning("IaidoGlassLayer: missing mask %s" % path)
		return null
	return load(path) as Texture2D


# --- the frozen world -------------------------------------------------------

# Called before the hero freeze, so the rig has had a frame to draw by the time
# `capture_world()` wants its picture. See `capture_viewport` above for why this
# is a rig of its own rather than the root viewport.
func begin_capture(split_material: ShaderMaterial) -> void:
	if capture_taken:
		return
	capture_split_material = split_material
	_ensure_capture_rig()
	capture_armed = capture_viewport != null


func _ensure_capture_rig() -> void:
	if capture_viewport != null:
		return
	capture_viewport = SubViewport.new()
	capture_viewport.name = "GlassWorldCapture"
	capture_viewport.transparent_bg = false
	capture_viewport.handle_input_locally = false
	capture_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	var size := get_viewport().get_visible_rect().size
	capture_viewport.size = Vector2i(size).max(Vector2i(1, 1))
	# SHARING THE WORLD IS THE WHOLE POINT. Assigning `world_3d` implies
	# `own_world_3d`, which is what we want here and the opposite of what the
	# shard viewport wants: the panes get an empty world to live in, the capture
	# wants the arena.
	capture_viewport.world_3d = get_viewport().world_3d
	add_child(capture_viewport)
	capture_camera = Camera3D.new()
	capture_camera.name = "GlassWorldCaptureCamera"
	# The weapon is on WEAPON_LAYER and the main camera does not draw it; the rig
	# must not draw it either, and copying the mask is how that stays true if the
	# mask ever changes.
	capture_camera.cull_mask = camera.cull_mask if camera != null else 0x7ffff
	capture_viewport.add_child(capture_camera)
	if capture_split_material != null and capture_split_material.shader != null:
		# A SECOND MATERIAL, ONE SET OF NUMBERS.
		#
		# The obvious thing here is to hang the SAME ShaderMaterial instance on
		# the rig's rect, and it is wrong. This shader reads its input through
		# `hint_screen_texture`, and a material drawn into two viewports in the
		# same frame resolves that binding once — measured: the moment the rig
		# was armed, the MAIN frame went flat and pale with no wound in it at
		# all, while the rig's own render was fine. So the rig gets a material of
		# its own and every uniform is copied across each armed frame, from the
		# one instance the director writes. There is still exactly one place a
		# number is authored; there are just two readers of it.
		capture_material = ShaderMaterial.new()
		capture_material.shader = capture_split_material.shader
		var rect := ColorRect.new()
		rect.name = "WorldSplit"
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		rect.material = capture_material
		capture_viewport.add_child(rect)
		_mirror_split_uniforms()


# One authority, two readers. The uniform list is asked of the SHADER rather
# than typed out, so a uniform added to `iaido_world_split.gdshader` cannot be
# silently missing from the frozen picture — which is how the panes would end up
# carrying a cut without a void, or a void without a grey.
func _mirror_split_uniforms() -> void:
	if capture_material == null or capture_split_material == null:
		return
	var shader := capture_split_material.shader
	if shader == null:
		return
	for entry in shader.get_shader_uniform_list():
		var uniform_name := String(entry["name"])
		capture_material.set_shader_parameter(
			uniform_name, capture_split_material.get_shader_parameter(uniform_name))


# Called once, at the hero freeze frame, while the cut is fully open. This is
# the frame the glass is made of: whatever the player is looking at when the
# world stops is what ends up inside the shards.
func capture_world() -> void:
	if capture_viewport == null:
		return
	# The rig is switched off in the same call that reads it, so a ceremony that
	# never reaches the freeze cannot leave a full-resolution 3D pass running.
	capture_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	capture_armed = false
	capture_taken = true
	var image := capture_viewport.get_texture().get_image()
	if image == null:
		push_warning("IaidoGlassLayer: world capture returned no image")
		return
	capture = ImageTexture.create_from_image(image)
	capture_aspect = float(image.get_width()) / maxf(float(image.get_height()), 1.0)
	_apply_capture()


func _apply_capture() -> void:
	var raw := 1.0 if OS.get_environment("SEKAI_RAW_CAPTURE") != "" else 0.0
	for data in shard_data:
		var material := data.get("material") as ShaderMaterial
		if material == null:
			continue
		material.set_shader_parameter("world_capture", capture)
		material.set_shader_parameter("capture_aspect", capture_aspect)
		material.set_shader_parameter("capture_half", capture_half)
		material.set_shader_parameter("debug_raw", raw)


# --- build ------------------------------------------------------------------

func build(tuning: IaidoTuning) -> void:
	_clear()
	# A new ceremony gets a new freeze. Without this the second Iaido of a
	# session would keep the first one's picture and never re-arm the rig.
	capture_taken = false
	capture_armed = false
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260927
	var aspect := _aspect()
	baked_aspect = aspect
	var extent := maxf(tuning.shard_size, 0.4)
	capture_half = extent

	var cells := _load_baked_cells(extent)
	if cells.is_empty():
		cells = _tessellate(tuning, aspect, extent, rng)
	if cells.is_empty():
		return

	var angle := deg_to_rad(tuning.cut_angle_degrees)
	var along := Vector2(cos(angle), sin(angle))
	var across := Vector2(-sin(angle), cos(angle))
	# THE CUT, READ OFF THE TUNING RATHER THAN REMEMBERED.
	#
	# `along` / `across` above are the SHADER's frame — screen uv, y-down. This
	# is the same normal in the frame the shaders are handed it in, and it is
	# what the shard material gets below, so the network a pane draws lands on
	# the same pixels as the world's.
	plane_cut_normal = across
	# ...and this is the same line again in the frame the POLYGONS live in.
	#
	# The bake is y-up plane coordinates while `rel` is y-down, related by
	# `rel = vec2(p.x, -p.y)`, so `rel · nrm = 0` becomes
	# `p · vec2(nrm.x, -nrm.y) = 0`. Flipping the y of the normal is the entire
	# conversion, and getting it wrong splits the glass along the MIRROR of the
	# cut — at -30 degrees that is a visibly different line, not a subtly wrong
	# one.
	var cut_normal_plane := Vector2(across.x, -across.y)

	# THE ORDER OF THE BREAK IS THE ORDER OF THE SLASH.
	#
	# 顺着斩击方向一步一步碎裂. Panes are sorted ALONG the cut — from the end the
	# blade entered to the end it left — and each one lets go when the front
	# reaches its own position on the line. That turns the collapse into a wave
	# travelling down the slash instead of a sheet giving way all at once, and it
	# is the same wave the world shader is draining on, so a pane is never left
	# floating over world it no longer matches.
	#
	# Half the frame's extent measured ALONG the cut, in plane units. This has to
	# be the same number the shader derives from `aspect`, or the wave in the
	# glass and the wave in the world travel at different speeds.
	var along_half: float = absf(along.x) * aspect * extent + absf(along.y) * extent
	cells.sort_custom(func(a: PackedVector2Array, b: PackedVector2Array) -> bool:
		return _centroid(a).dot(along) < _centroid(b).dot(along)
	)

	# 玻璃要按照切口裂开，而不是随便裂开.
	#
	# THE GLASS IS SPLIT BY THE CUT ITSELF — not merely displaced across it.
	#
	# What this used to do: a Voronoi cell that straddled the wound stayed
	# whole, and `stage()` pushed it bodily toward whichever side its centroid
	# fell on. So the panes nearest the cut — the ones a viewer actually looks
	# at — were pushed ACROSS the wound and covered it up, and the glass read as
	# a mosaic that had been shoved sideways rather than as a surface that had
	# been cut. The wound in the glass was in the displacement and nowhere else.
	#
	# Now every cell the line actually crosses is CLIPPED IN TWO along it. The
	# bake is convex, so a half-plane clip is exact: the two halves reassemble
	# into the original outline to the last vertex, which is what keeps the
	# acceptance test true — at t=0 the panes still ARE the original frame, the
	# seam between them being zero-width until the halves separate. Then each
	# half inherits the displacement of its own side, exactly as before.
	var cut_cells: Array[PackedVector2Array] = []
	var cut_sides: Array[float] = []
	for cell in cells:
		# `_clip_half_plane` keeps dot(point - mid, normal) <= 0. The cut line
		# passes through the plane origin (`cut_center` is the frame centre), so
		# `mid` is zero and the two halves of one cell are the two signs of the
		# distance to the line.
		var pos_half := _clip_half_plane(cell, Vector2.ZERO, -cut_normal_plane)
		var neg_half := _clip_half_plane(cell, Vector2.ZERO, cut_normal_plane)
		if pos_half.size() >= 3 and absf(_polygon_area(pos_half)) >= MIN_CELL_AREA:
			cut_cells.append(pos_half)
			cut_sides.append(1.0)
		if neg_half.size() >= 3 and absf(_polygon_area(neg_half)) >= MIN_CELL_AREA:
			cut_cells.append(neg_half)
			cut_sides.append(-1.0)
	if cut_cells.is_empty():
		return
	cells = cut_cells

	# WHICH PANES COME LOOSE FIRST.
	#
	# 玻璃已经坏了，只是还没有掉. Before the final click only a handful of panes
	# are allowed to have moved at all — the design asks for two to five — and
	# the ones a real break would release first are the ones sitting against the
	# wound, because that is where the stress is. So the choice is made by
	# distance to the cut line rather than by index: an index would pick whatever
	# happened to be first in the bake, which has nothing to do with where the
	# break is.
	var order_loose: Array[int] = []
	for i in cells.size():
		order_loose.append(i)
	order_loose.sort_custom(func(a: int, b: int) -> bool:
		var da := absf(_centroid(cells[a]).dot(across))
		var db := absf(_centroid(cells[b]).dot(across))
		return da < db
	)
	var loose_count := clampi(tuning.shard_loose_count, 0, cells.size())
	var loose_set := {}
	for i in loose_count:
		loose_set[order_loose[i]] = true

	for i in cells.size():
		var poly := cells[i]
		var centre := _centroid(poly)
		# WHICH SIDE OF THE WOUND THIS PIECE BELONGS TO.
		#
		# Decided when the piece was cut out of its parent cell, not guessed
		# afterwards from where its centroid happens to fall. A piece exists at
		# all only because the cut passed through it, so its side is a property
		# of the cut and not a question to be answered a second time — and
		# answering it a second time is how the two halves of one cell could
		# both end up on the same side of the line.
		var side := cut_sides[i]
		# Where this pane sits along the slash, 0..1, on exactly the axis the
		# shader's `travel` is measured on.
		var travel := clampf(centre.dot(along) / maxf(along_half, 0.001) * 0.5 + 0.5, 0.0, 1.0)
		# y-up, matching the bake and the shader. Negating y here used to flip
		# the whole collapse vertically relative to the picture it sits on.
		var outward := Vector3(across.x, across.y, 0.0).normalized() * side
		# The main collapse is mixed so no two pieces share a story. Each
		# behaviour gets its own velocity profile further down.
		# §25: some fall, some drift backward, some rotate slowly, and a few come
		# toward the camera. The four behaviours cycle so no two neighbours share
		# a story, and `depth` below is what turns the sheet into a volume. The
		# broken-but-holding panes are no longer a special case here — they keep
		# whichever behaviour they were assigned and simply do not get to act on
		# it until `loose` (one of them) or `collapse_start` (all of them).
		var behaviour: int = [Behaviour.FALL, Behaviour.DRIFT, Behaviour.VOID, Behaviour.STILL][i % 4]
		var speed := rng.randf_range(0.55, 1.30)
		var drift := rng.randf_range(-0.40, 0.40)
		var velocity := Vector3.ZERO
		var gravity := 0.0
		# Depth is part of the motion, but only a little: a shard that flies at
		# the camera is a jump scare, and a whole sheet doing it is an explosion.
		#
		# The multipliers below were halved after reviewing the first V4
		# collapse: at the old values the panes crossed the frame within 250ms
		# and the result read as an explosion of glass cards rather than as a
		# surface that had lost its integrity. §M wants the pieces to separate
		# slowly enough that the frozen world is still legible across them.
		var depth := rng.randf_range(-0.03, 0.03)
		match behaviour:
			Behaviour.FALL:
				velocity = outward * speed * 0.20 + Vector3(drift * 0.14, 0.06, depth * 0.4)
				gravity = tuning.shard_gravity
			Behaviour.DRIFT:
				velocity = outward * speed * 0.30 + Vector3(drift * 0.17, 0.035, depth * 0.7)
			Behaviour.VOID:
				# Slides back toward the wound it came from.
				velocity = -outward * speed * 0.12 + Vector3(drift * 0.07, -0.03, -depth * 0.3)
			Behaviour.STILL:
				velocity = outward * 0.026 + Vector3(drift * 0.03, 0.0, depth * 0.12)
		var data := {
			"centre": centre,
			"basis": Vector3(centre.x, centre.y, 0.0),
			# THE SIDE OF THE CUT THIS PIECE BELONGS TO, in the shader's own
			# sign convention (see `stage()`), carried from the clip that made
			# it.
			"side": side,
			# WHERE THIS PANE SITS ALONG THE SLASH.
			#
			# The MATERIAL handover still runs down the line — `stage()` reads
			# this through the same curve the world drains on, so the two can
			# never disagree about where the front is — but the pane's PHYSICAL
			# release no longer does. Arriving and letting go are separate clocks.
			"travel": travel,
			# WHEN THIS PANE IS ALLOWED TO MOVE.
			#
			# 玻璃已经坏了，只是还没有掉. The handful of panes nearest the wound
			# come free at `loosen_start` and are allowed `loose_drift_scale` of
			# their velocity, which is a few millimetres: enough to read as "not
			# attached any more", not enough to read as "falling". Everything else
			# waits for the final click, which is where the design puts structural
			# failure.
			#
			# V6 ran the material handover and the release off ONE clock, so the
			# whole surface had come apart and flown before the blade was half way
			# home — and by the final click, the moment that is supposed to be the
			# collapse, there was nothing left to fail.
			"loose": tuning.loosen_start if loose_set.has(i) else tuning.collapse_start,
			"loose_scale": tuning.loose_drift_scale if loose_set.has(i) else 0.0,
			"hover": rng.randf_range(tuning.shard_min_delay, tuning.shard_max_delay),
			"velocity": velocity,
			"gravity": gravity,
			"spin": rng.randf_range(-1.0, 1.0),
			# Angular VELOCITY, in radians per second. Rotations accumulate over
			# the collapse instead of being handed out at t=0, so the panes start
			# as an exact picture and come apart from it.
			"angular": Vector3(
				rng.randf_range(-0.55, 0.55),
				rng.randf_range(-0.75, 0.75),
				rng.randf_range(-1.20, 1.20)
			),
			"outward": outward,
			"tint": rng.randf_range(0.94, 1.06),
		}
		# The ABSOLUTE bake polygon, not one pre-centred here: _build_pane_mesh
		# needs the absolute coordinates to write the UV, and centres the
		# geometry itself. Passing an already-centred polygon subtracted the
		# origin twice, which collapsed every shard's UV to a small patch around
		# the middle of the frame — all eighteen panes showed the same thing.
		var holder := _make_shard(poly, centre, data)
		shard_data.append(data)
		shards.append(holder)
	_apply_capture()


# The UE5 bake: every cell polygon, in screen half-height units, ordered from
# the wound outward. Metadata is read but not trusted — a malformed or empty
# bake falls through to the built-in tessellation rather than shipping a
# ceremony with no glass in it.
func _load_baked_cells(extent: float) -> Array[PackedVector2Array]:
	var cells: Array[PackedVector2Array] = []
	if not FileAccess.file_exists(SHARD_BAKE):
		push_warning("IaidoGlassLayer: no shard bake at %s, tessellating in engine" % SHARD_BAKE)
		return cells
	var text := FileAccess.get_file_as_string(SHARD_BAKE)
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY or not parsed.has("cells"):
		push_warning("IaidoGlassLayer: shard bake is malformed")
		return cells
	var baked_half := float(parsed.get("half", extent))
	if absf(baked_half - extent) > 0.0001:
		# The bake was made at a different plane size; scale it so the pattern
		# still lands on the same part of the screen.
		push_warning("IaidoGlassLayer: shard bake half=%.3f, tuning shard_size=%.3f" % [baked_half, extent])
	for entry in parsed["cells"]:
		var poly := PackedVector2Array()
		for point in entry.get("polygon", []):
			poly.append(Vector2(float(point[0]), float(point[1])))
		if poly.size() >= 3 and absf(_polygon_area(poly)) >= MIN_CELL_AREA:
			cells.append(poly)
	return cells


# Fallback only. Deliberately the same design rule as the UE5 lab — fine near
# the cut, coarse away from it — so a missing bake degrades the pattern rather
# than changing what it means.
func _tessellate(tuning: IaidoTuning, aspect: float, extent: float, rng: RandomNumberGenerator) -> Array[PackedVector2Array]:
	var angle := deg_to_rad(tuning.cut_angle_degrees)
	var along := Vector2(cos(angle), sin(angle))
	var across := Vector2(-sin(angle), cos(angle))
	var count := clampi(tuning.shard_count * 2, 12, 40)
	var hx := extent * aspect
	var seeds: Array[Vector2] = []
	for i in count:
		var band := float(i % 5) / 5.0
		var u := rng.randf_range(-1.15, 1.15) * hx
		var v := rng.randf_range(-1.0, 1.0) * extent * (0.35 + band * 0.95)
		seeds.append(along * u + across * v)
	var cells: Array[PackedVector2Array] = []
	for i in count:
		var poly := PackedVector2Array([
			Vector2(-hx * 1.2, -extent * 1.2), Vector2(hx * 1.2, -extent * 1.2),
			Vector2(hx * 1.2, extent * 1.2), Vector2(-hx * 1.2, extent * 1.2),
		])
		for j in count:
			if i == j:
				continue
			var offset := seeds[j] - seeds[i]
			if offset.length_squared() < 0.000001:
				continue
			poly = _clip_half_plane(poly, (seeds[i] + seeds[j]) * 0.5, offset.normalized())
			if poly.size() < 3:
				break
		if poly.size() >= 3 and absf(_polygon_area(poly)) >= MIN_CELL_AREA:
			cells.append(poly)
	return cells


func _make_shard(polygon: PackedVector2Array, centre: Vector2, data: Dictionary) -> Node3D:
	var holder := Node3D.new()
	holder.name = "Shard"
	holder.visible = false
	viewport.add_child(holder)

	var material := ShaderMaterial.new()
	material.shader = preload("res://vfx/iaido_glass_shard.gdshader")
	material.set_shader_parameter("world_capture", capture)
	material.set_shader_parameter("capture_aspect", capture_aspect)
	material.set_shader_parameter("capture_half", capture_half)
	material.set_shader_parameter("shard_centre", centre)
	material.set_shader_parameter("opacity", 0.0)
	material.set_shader_parameter("glass_tint", 0.06)
	if crack_tex != null:
		material.set_shader_parameter("crack_mask", crack_tex)
	if edge_tex != null:
		material.set_shader_parameter("edge_mask", edge_tex)
	if flow_tex != null:
		material.set_shader_parameter("flow_mask", flow_tex)
	# The cut, in the same plane space the bake was authored in, so the crack
	# front can grow outward from the wound. All four are driven from
	# `IaidoTuning.fracture_at()` / `shatter_at()` / `stream_at()` in `stage()`,
	# which is the same authority the world pass reads.
	material.set_shader_parameter("plane_cut_normal", plane_cut_normal)
	material.set_shader_parameter("fracture", 0.0)
	material.set_shader_parameter("shatter", 0.0)
	material.set_shader_parameter("stream", 0.0)
	material.set_shader_parameter("dissolve", 0.0)

	var instance := MeshInstance3D.new()
	instance.name = "Pane"
	instance.mesh = _build_pane_mesh(polygon, centre)
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(instance)
	data["material"] = material
	return holder


# A convex polygon extruded to a thin pane.
#
# Two channels ride on the mesh:
#   COLOR.r  how close the vertex is to the fracture edge, so the shader can
#            keep a thin bright rim over an otherwise transparent body;
#   UV       the vertex's ORIGINAL position on the shattered plane, which is
#            what lets the fragment shader look up the piece of world this pane
#            was cut out of.
#
# The panes have to be built as an OUTER RING plus an interior, not as a fan
# straight from the boundary to the centroid: a fan spreads the bright gradient
# across the whole pane, which is what made an earlier pass read as opaque white
# slabs.
func _build_pane_mesh(polygon: PackedVector2Array, origin: Vector2) -> ArrayMesh:
	var count := polygon.size()
	var half := THICKNESS * 0.5
	# GEOMETRY IS LOCAL, UV IS ABSOLUTE. Both facts are load-bearing.
	#
	# The geometry is built around the shard's own centre and left in plane
	# units; the holder's `scale` (set in stage()) is what turns those units into
	# metres at SHARD_Z. Doing the conversion here instead would bake the live
	# camera FOV into the mesh, and the shards are built long before the
	# ceremony pulls the FOV in — the panes would then be off by the ratio
	# between the gameplay FOV and the draw FOV, which is roughly 6x.
	#
	# The UV, by contrast, must NOT be local. It carries the vertex's absolute
	# position on the shattered plane, which is the only reason the frozen world
	# stays welded to the pane as the pane flies away (§G).
	# The bake is authored y-UP, exactly like the shader's plane_to_uv() reads
	# it: plane +y is screen up. Everything downstream must agree, so the mesh,
	# the holder basis and the UV all use y-up. An earlier revision flipped y
	# for the geometry and the placement but not for the UV, which mirrored
	# every pane's content vertically against where it was placed.
	_uv_origin = origin
	var flat := PackedVector2Array()
	for point in polygon:
		flat.append(point - _uv_origin)
	var centre := Vector2.ZERO
	for point in flat:
		centre += point
	centre /= maxf(float(count), 1.0)
	var inner := PackedVector2Array()
	for point in flat:
		var offset := point - centre
		var shrink := maxf(0.0, 1.0 - RIM_WIDTH / maxf(offset.length(), 0.0001))
		inner.append(centre + offset * shrink)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for z in [half, -half]:
		for k in count:
			var n := (k + 1) % count
			_rim_quad(st, flat[k], flat[n], inner[n], inner[k], z)
			_vertex(st, inner[k], BODY_VERTEX, z)
			_vertex(st, inner[n], BODY_VERTEX, z)
			_vertex(st, centre, BODY_VERTEX, z)
	# the fracture edge itself, seen side-on: the only genuinely solid part
	for k in count:
		var n := (k + 1) % count
		_vertex(st, flat[k], EDGE_VERTEX, half)
		_vertex(st, flat[n], EDGE_VERTEX, half)
		_vertex(st, flat[n], EDGE_VERTEX, -half)
		_vertex(st, flat[k], EDGE_VERTEX, half)
		_vertex(st, flat[n], EDGE_VERTEX, -half)
		_vertex(st, flat[k], EDGE_VERTEX, -half)
	st.generate_normals()
	return st.commit()


func _vertex(st: SurfaceTool, point: Vector2, colour: Color, z: float) -> void:
	st.set_color(colour)
	# point is local (plane units, centred on the shard); the UV has to be the
	# ABSOLUTE bake coordinate, so the shard's origin is added back. Both are
	# y-up, so there is no flip anywhere in this function.
	st.set_uv(point + _uv_origin)
	st.add_vertex(Vector3(point.x, point.y, z))


func _rim_quad(st: SurfaceTool, a: Vector2, b: Vector2, bi: Vector2, ai: Vector2, z: float) -> void:
	_vertex(st, a, EDGE_VERTEX, z)
	_vertex(st, b, EDGE_VERTEX, z)
	_vertex(st, bi, BODY_VERTEX, z)
	_vertex(st, a, EDGE_VERTEX, z)
	_vertex(st, bi, BODY_VERTEX, z)
	_vertex(st, ai, BODY_VERTEX, z)


# --- staging ----------------------------------------------------------------

# Plane units -> metres at SHARD_Z, taken LIVE.
#
# A capture is a SCREEN image, so a point at plane coordinate p always sits at
# the same place on the frame (p / 2*half of it) whatever the camera FOV is. The
# scale therefore has to follow the live FOV: the frame moves under the effect,
# not the other way round.
#
# Snapshotting the FOV at capture time is exactly the bug that made every pane a
# small copy of the middle of the frame. The ceremony widens the FOV from 75
# degrees to 88, so panes sized for 75 came out about 24% too small and, far
# worse, their content no longer landed where the world behind them was — the
# two only agree when the pane's screen extent matches its bake extent.
func plane_scale() -> float:
	if camera == null or not is_instance_valid(camera):
		return 0.0001
	return maxf(tan(deg_to_rad(maxf(camera.fov, 1.0) * 0.5)) * absf(SHARD_Z), 0.0001)


func stage(time: float, tuning: IaidoTuning, separation_px: float = 0.0, split_shear: float = 0.5) -> void:
	if shards.is_empty():
		_publish(false)
		return
	var restore := IaidoTuning.ease_in_out(IaidoTuning.span(time, tuning.restore_start, tuning.restore_end))
	# NOTHING IS GLASS UNTIL THE FRACTURE HAS STARTED.
	#
	# The panes carry a capture of the frame, and before `capture_time` the only
	# thing they can sample is the 1x1 placeholder — a dark blue chip.
	#
	# BUT `capture_time` ALONE IS NOT THE GATE. `arrived` is a smoothstep whose
	# lower edge sits BELOW zero travel, so at stream = 0 the panes at the entry
	# end of the slash are already about 30% arrived, and with the capture taken
	# inside the hero hold they would be laying a picture of a split world over a
	# world that is split in the same way but has not been touched yet. Harmless
	# in itself, and still wrong: the surface does not become glass before the
	# front that turns it into glass exists. That is the gate.
	if time < tuning.glass_start:
		for shard in shards:
			shard.visible = false
		_publish(false)
		return
	# Placed against the half-height the capture was taken at, not the live one.
	# The same number is the shard meshes' scale, because the meshes are authored
	# in plane units and this is plane units -> metres at SHARD_Z.
	var half_h := plane_scale()
	var k := maxf(tuning.shard_drag, 0.001)
	var collapse := IaidoTuning.span(time, tuning.collapse_start, tuning.collapse_end)
	# One number for the whole sweep; only the stagger below is per pane.
	var devour := IaidoTuning.ease_in_out(
		IaidoTuning.span(time, tuning.devour_start, tuning.devour_end))
	# §H: THE NETWORK THE PANES CARRY IS THE NETWORK THE WORLD WAS DRAWN WITH.
	#
	# Not a second set of ramps over the same window. The director pushes
	# `IaidoTuning.fracture_at()` / `shatter_at()` / `stream_at()` at the world
	# pass, and this asks the same three functions for the same values at the
	# same instant — so a pane still lying over live world draws its cracks
	# exactly where the world already drew them, instead of a few frames away
	# from them with a different strength.
	#
	# This used to be an independent `span(time, glass_start, glass_stream_end)`
	# ease with its own multipliers. That is a second clock for a thing that
	# already had one, and it is why a region could be barely cracked in the
	# glass and wide open in the world behind it.
	var fracture := tuning.fracture_at(time)
	var shatter := tuning.shatter_at(time)
	var stream := tuning.stream_at(time)
	if suppress_crack:
		fracture = 0.0
		shatter = 0.0
	var dissolve := IaidoTuning.ease_in_out(
		IaidoTuning.span(time, tuning.restore_start, tuning.restore_end))
	var any_visible := false

	# THE GLASS CONTINUES THE SPLIT.
	#
	# This is the fix for "玻璃还是没有被裂缝斩开". The panes used to reassemble
	# one continuous frozen picture: the mosaic covered 92% of the frame from
	# 6.7s onward with the two halves still welded together, so the crack the
	# world had opened healed the instant the glass took over — the read went
	# back to "a complete picture with a line drawn on it", which is §1's
	# forbidden result.
	#
	# So each pane now inherits the displacement of the half it belongs to: the
	# same separation, the same 45/55 bias, the same along-cut shear the world
	# shader applies to its sample, passed in from the director's frame (one
	# authority — recomputing the track here would be a second clock). The pane's
	# content is welded to its geometry, so the frozen image moves with it and
	# the wound in the glass is as real as the wound in the world.
	#
	# Frame of reference: the pane plane is y-up plane units, the world shader's
	# `rel` is y-down uv — hence the sign flips below. Derivation, so nobody
	# has to redo it: plane_to_uv() maps (dx, dy) to a uv shift of
	# (dx/(2h-aspect), -dy/(2h)), and the shader's aspect-units displacement
	# converts to uv by dividing x by aspect. Authored pixels convert with
	# IAIDO_AUTHORED_PX (1080), the same constant the shared field uses.
	var two_h := 2.0 * capture_half
	var cut_a := deg_to_rad(tuning.cut_angle_degrees)
	var tangent_s := Vector2(cos(cut_a), sin(cut_a))
	var nrm_s := Vector2(-sin(cut_a), cos(cut_a))

	for i in shards.size():
		var holder := shards[i]
		var data: Dictionary = shard_data[i]
		# THE PANE'S ARRIVAL IS THE WORLD'S ARRIVAL.
		#
		# Fading on `time - detach` would be a second, independent clock: the
		# pane would fade in on a linear ramp while the world disappeared on the
		# eased front, and the two would visibly disagree at the head of the
		# wave. Asking the tuning for the same term the shader uses costs one
		# call and removes the whole class of bug.
		#
		# AND THE ARRIVAL IS TWO-DIMENSIONAL. 玻璃从裂痕蔓延.
		#
		# `stream_arrived` alone only knows how far ALONG the slash the front
		# has run, and every point on the frame answers that eventually — so the
		# panes tiled the whole picture, corner to corner, and the wound stopped
		# being the source of anything. A pane is a piece of the surface, and the
		# surface has only become glass where the fracture front has actually
		# GROWN TO, measured outward from the cut. That is `grown_at()`, the
		# mirror of the `iaido_grown()` the world pass eats on, so the boundary
		# between "still world" and "now glass" is the same boundary in both
		# layers rather than two fronts that happen to start together.
		#
		# `ad` is the pane's centre's distance from the cut in the shard
		# shader's own frame: `rel = vec2(plane.x, -plane.y) / (2 * capture_half)`
		# and `ad = |rel · plane_cut_normal| * IAIDO_AUTHORED_PX`. Recomputed
		# here rather than approximated, because a pane that thinks it is closer
		# to the wound than it is appears over world that is still there.
		var centre: Vector2 = data["centre"]
		var ad := absf(Vector2(centre.x, -centre.y).dot(plane_cut_normal)) \
			/ maxf(two_h, 0.0001) * AUTHORED_PX
		var arrived := tuning.cover_at(time, float(data["travel"]), ad)
		if arrived < 0.001 or restore >= 1.0:
			holder.visible = false
			continue
		var basis: Vector3 = data["basis"]
		var velocity: Vector3 = data["velocity"]
		var outward: Vector3 = data["outward"]
		var gravity := float(data["gravity"])
		# TWO CLOCKS, ADDED IN ONE PLACE.
		#
		# CEREMONY TIME, NOT WALL TIME. `since` removes every dead window between
		# the pane coming loose and now, so a pane already in the air hangs
		# exactly where it was when a time stop lands — and it is the pane, not
		# the camera, that gives a fake stop away. A shard still falling through
		# a frozen frame is visible in one glance.
		#
		# `drift`  what this pane is allowed to have done since it came loose.
		#          For the handful nearest the wound that is a small fraction of
		#          its own velocity; for every other pane it is exactly zero,
		#          because `loose_scale` is zero — they have not come loose.
		#          This is the 玻璃已经坏了，只是还没有掉 state: the surface is
		#          visibly broken and visibly still holding.
		# `burst`  the final click, which sets every pane free at once. The gap
		#          either side of this instant is supposed to be enormous.
		#
		# The 30-90ms hang is applied to `drift` only. It exists so the break
		# reads as weight rather than as an animation starting; a delay in front
		# of the collapse would put the largest movement in the ceremony a tenth
		# of a second after the beat that caused it.
		var drift := maxf(
			tuning.since(time, float(data["loose"])) - float(data["hover"]), 0.0)
		drift *= float(data["loose_scale"])
		var burst := tuning.since(time, tuning.collapse_start)
		var moving := drift + burst
		var terminal := Vector3(0.0, -gravity, 0.0) / k
		var decay := (1.0 - exp(-k * moving)) / k
		var offset := (velocity - terminal) * decay + terminal * moving
		offset += outward * collapse * 0.05
		# THIS PANE'S SIDE OF THE WOUND, in the world shader's own frame.
		#
		# The side sign is the SHADER's, not the build's: the shader reads
		# dot(rel, nrm) with rel y-down, and the build's `across` is y-up — the
		# two mirror in y. Getting this wrong moves a pane TOWARD the wound,
		# which doubles the misregistration instead of continuing it.
		#
		# It is READ, not recomputed. `build()` cut this piece out of its parent
		# along the wound and stamped which half it is, so the sign here cannot
		# disagree with the geometry the piece was made from.
		var side_s := float(data["side"])
		var amp := 2.0 * (tuning.split_bias if side_s >= 0.0 else 1.0 - tuning.split_bias)
		var sep_eff := 0.0 if suppress_pane_split else separation_px
		var move_aspect := (nrm_s + tangent_s * split_shear) \
			* (side_s * amp * sep_eff / AUTHORED_PX)
		var move_plane := Vector2(
			move_aspect.x / baked_aspect * two_h * capture_aspect,
			-move_aspect.y * two_h)
		offset += Vector3(move_plane.x, move_plane.y, 0.0)
		# The pane's own uv displacement, δ. Used twice below: the geometry
		# offset already went into `offset` via move_plane, and the capture
		# sample is compensated by the SAME vector (see the material block).
		var move_uv := Vector2(
			move_aspect.x / baked_aspect,
			move_aspect.y)
		if restore > 0.0:
			offset = offset.lerp(Vector3.ZERO, restore)
		holder.position = basis * half_h + Vector3(0.0, 0.0, SHARD_Z) + offset * half_h

		# ROTATION STARTS AT ZERO.
		#
		# This used to add a random `spin` of 0..TAU to the in-plane angle at
		# t=0, so every pane arrived already turned by an arbitrary angle. That
		# single term is why the collapse never reassembled into the picture and
		# read as a kaleidoscope of tilted cards: §G's acceptance test is that
		# the pieces at t=0 ARE the original frame. Independent rotation is
		# earned over time through `angular`, never granted at the start.
		var angular: Vector3 = data["angular"]
		var spin_dir := float(data["spin"]) * 0.35 + 0.65
		holder.rotation = Vector3(
			angular.x * moving,
			angular.y * moving * 0.7,
			angular.z * spin_dir * moving
		)
		# THE PANES ARE PART OF THE WORLD, SO THE DEVOUR TAKES THEM TOO.
		#
		# 吞噬. The devour front in the world shader can only reach what the 3D pass
		# drew — the standing world and the weapon. The panes live on their own
		# CanvasLayer above it, so they are the one layer the emptiness provably
		# cannot touch, and a mosaic of bright, clean, perfectly lit panes hanging
		# over an absolute void does not read as "reality was eaten": it reads as a
		# HUD drawn on top of a black frame. That is the same fault the user reported
		# about the hand and the sword, one layer further out.
		#
		# Eaten ALONG THE CUT rather than all at once, using the same `travel` the
		# detach order uses, so the surface is consumed as a sweep that follows the
		# slash — the direction the whole ceremony has been moving in — instead of
		# fading off the screen as a single global dissolve.
		#
		# This is deliberately NOT undone by `restore`: the restore puts the WORLD
		# back, and the glass was never part of the world that comes back. A pane
		# that reassembled would be a second ending competing with the real one.
		var eaten := clampf(
			(devour - float(data["travel"]) * 0.35) / 0.65, 0.0, 1.0)
		var fade := arrived * (1.0 - restore) * (1.0 - IaidoTuning.ease_in_out(eaten))
		holder.scale = Vector3.ONE * (half_h * lerpf(1.0, 0.25, restore))
		var material := data.get("material") as ShaderMaterial
		if material != null:
			material.set_shader_parameter("opacity", fade)
			material.set_shader_parameter("fracture", fracture)
			material.set_shader_parameter("shatter", shatter)
			material.set_shader_parameter("stream", stream)
			material.set_shader_parameter("dissolve", dissolve)
			# CONTENT COMPENSATION, so the pane shows the world's MATERIAL at
			# the screen point it lands on, not the frozen screen at its own
			# plane point. capture(u) = M(u − m) — the frozen screen already
			# carries the split — and the pane at plane p displays at
			# s = p + δ, so it must sample the capture at p + δ to show
			# M(s − m). The sample shift is therefore +δ, the pane's own uv
			# displacement. Negating it stacks three displacements and the
			# whole mosaic slides.
			material.set_shader_parameter("split_sample", move_uv)
		holder.visible = fade > 0.01
		any_visible = any_visible or holder.visible

	_publish(any_visible)


# THE BLIT IS NOT THE VIEWPORT.
#
# `image_rect` is a full-rect Control sampling the SubViewport's texture, and
# `UPDATE_DISABLED` does not CLEAR that texture — it freezes it. So the instant
# the last pane is culled the viewport stops rendering and the blit goes on
# drawing the last frame it was given: the whole glass layer hangs on screen,
# opaque, for the rest of the ceremony, and the only clue that it is stale is
# that it never changes again.
#
# This was measured, not reasoned about. A fresh process rendering t=9.20 draws
# the empty void (correct: the world is devoured, the panes are gone); the very
# same instant reached by stepping the timeline in one process drew a full mosaic
# of bright panes over it. Both are the same code and the same numbers, and the
# only difference is whether the viewport had a previous frame to freeze.
#
# So activation is one call, and it always moves the blit and the viewport
# together. Four separate call sites used to set the update mode and only one of
# them knew about `image_rect` at all.
func _publish(any_visible: bool) -> void:
	active = any_visible
	if image_rect != null:
		image_rect.visible = any_visible
	if viewport != null:
		viewport.render_target_update_mode = (
			SubViewport.UPDATE_ALWAYS if any_visible else SubViewport.UPDATE_DISABLED)


func reset() -> void:
	capture_taken = false
	capture_armed = false
	if capture_viewport != null:
		capture_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	for shard in shards:
		if is_instance_valid(shard):
			shard.visible = false
	_publish(false)


func _clear() -> void:
	for shard in shards:
		if is_instance_valid(shard):
			shard.queue_free()
	shards.clear()
	shard_data.clear()
	_publish(false)


func _process(_delta: float) -> void:
	if viewport == null:
		return
	var size := Vector2i(get_viewport().get_visible_rect().size)
	if viewport.size != size:
		viewport.size = size.max(Vector2i(1, 1))
	foreground_camera.fov = camera.fov
	foreground_camera.keep_aspect = camera.keep_aspect
	# The capture rig is a SECOND CAMERA ON THE SAME WORLD, so it has to be told
	# where to stand. It is only driven while armed — a few frames before the
	# freeze — so the ceremony pays for one extra 3D pass for that window and
	# nothing at all for the other eight seconds.
	if capture_armed and capture_viewport != null and not capture_taken:
		var wanted := size.max(Vector2i(1, 1))
		if capture_viewport.size != wanted:
			capture_viewport.size = wanted
		if camera != null and is_instance_valid(camera):
			capture_camera.global_transform = camera.global_transform
			capture_camera.fov = camera.fov
			capture_camera.near = camera.near
			capture_camera.far = camera.far
			capture_camera.keep_aspect = camera.keep_aspect
			capture_camera.cull_mask = camera.cull_mask
		_mirror_split_uniforms()
		capture_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS


# --- geometry helpers -------------------------------------------------------

func _aspect() -> float:
	var rect := get_viewport().get_visible_rect().size
	return rect.x / maxf(rect.y, 1.0)


# Keeps the half-plane where dot(point - mid, normal) <= 0.
func _clip_half_plane(poly: PackedVector2Array, mid: Vector2, normal: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	var count := poly.size()
	if count < 3:
		return out
	for i in count:
		var current := poly[i]
		var following := poly[(i + 1) % count]
		var d_current := (current - mid).dot(normal)
		var d_following := (following - mid).dot(normal)
		if d_current <= 0.0:
			out.append(current)
		if (d_current < 0.0 and d_following > 0.0) or (d_current > 0.0 and d_following < 0.0):
			var ratio := d_current / (d_current - d_following)
			out.append(current.lerp(following, ratio))
	return out


func _centroid(poly: PackedVector2Array) -> Vector2:
	var sum := Vector2.ZERO
	for point in poly:
		sum += point
	return sum / maxf(float(poly.size()), 1.0)


func _polygon_area(poly: PackedVector2Array) -> float:
	var area := 0.0
	var count := poly.size()
	for i in count:
		var a := poly[i]
		var b := poly[(i + 1) % count]
		area += a.x * b.y - b.x * a.y
	return area * 0.5
