extends Node3D
class_name ChainRealitySheet
# 缚星链 ULTIMATE · THE REALITY SHEET — the object the whole skill exists for.
#
# ---------------------------------------------------------------------------
# WHAT IT PROVES BY EXISTING
# ---------------------------------------------------------------------------
#
# The brief's hardest requirement (§四.3) is that the sheet must read as a THING
# THAT WAS TAKEN OFF THE WORLD — not a rectangle, not a screen slice, not a
# shader card. Three separate mechanisms carry that, and all three are here:
#
#   1 · THE PICTURE. Everything the player sees on the sheet is the world as it
#       was, captured into a viewport at the instant of the rip and FROZEN, then
#       sampled through per-vertex UVs baked from the frozen camera. See
#       `_bake_uv` and the header of `chain_reality_sheet.gdshader`.
#
#   2 · THE SILHOUETTE. Four sinusoids at unrelated frequencies modulate the
#       radius, and the amounts are deliberately unequal (`_LOBE_*`): equal
#       harmonics read as a gear, unequal ones read as a tear. A circle is a
#       cushion; this has to have a long side and a short one.
#
#   3 · THE PIECES. The same surface is ALSO built as six meshes, separated by
#       jagged boundaries that wobble per ring. While the sheet is whole they are
#       coincident and invisible; when it tears they are already the pieces, so
#       the split lands on boundaries that were authored rather than computed
#       under pressure at 2.85s.
#
# ---------------------------------------------------------------------------
# THE ONE ERROR THAT WOULD RUIN ALL OF IT, AND HOW IT IS AVOIDED
# ---------------------------------------------------------------------------
#
# `SubViewport.render_target_update_mode = UPDATE_DISABLED` is a FREEZE, not a
# clear: the last rendered image stays. That is exactly what is wanted here, and
# it is also the trap — a viewport that is DISABLED from the start has never been
# rendered and is BLACK, and a black capture means the sheet shows nothing and the
# entire skill reads as a dark shape. So the update mode is a three-step dance and
# the order matters: settle (`UPDATE_ALWAYS`), capture (`UPDATE_ONCE`), freeze
# (`UPDATE_DISABLED`).
#
# ---------------------------------------------------------------------------
# IT IS SELF-CONTAINED ON PURPOSE
# ---------------------------------------------------------------------------
#
# Everything is built in code and nothing here touches `chain_director.gd`,
# `chain_visual.gd` or any scene. The chain line owns the chain; this file owns
# the sheet, and the two meet only through the director that drives both.

const _LOBE_AMPS := [0.62, 0.30, 0.22, 0.12]
const _LOBE_FREQ := [2.0, 3.0, 7.0, 11.0]
const _LOBE_PHASE := [0.70, -1.90, 2.40, -0.30]
const _LOBE_SUM := 1.26

const RING_COUNT := 10
const SECTOR_COUNT := 56

const SHEET_SHADER := preload("res://vfx/chain_reality_sheet.gdshader")
const HOLE_SHADER := preload("res://vfx/chain_reality_hole.gdshader")

var tuning: ChainUltimateTuning

# The frozen capture. `capture_camera` is a copy of the player's camera made at
# the instant of the rip; the viewport renders through it exactly once.
var capture_viewport: SubViewport
var capture_camera: Camera3D

var hole: MeshInstance3D
var sheet_root: Node3D
var sheet_material: ShaderMaterial
var hole_material: ShaderMaterial
var shards: Array[MeshInstance3D] = []

# Where the sheet was when it was still part of the world, in world space. The
# hole stays here for the rest of the ceremony; the sheet does not.
var source_origin := Vector3.ZERO
var source_basis := Basis.IDENTITY
# The capture camera's frozen transform, kept so the baked UVs can be explained
# (and re-derived) without re-reading the viewport.
var capture_transform := Transform3D.IDENTITY

var built := false
var capture_state := 0  # 0 idle · 1 settling · 2 armed · 3 frozen
var _settle_frames := 0
var _restore_after_capture: Array = []
# The camera's own numbers AT THE MOMENT THE PICTURE WAS TAKEN, kept as fields so
# a renderer can compare them against the camera the frame is finally drawn with.
# The two have to agree or the film is a photograph of a view that was never on
# screen, and the mismatch is invisible in the code: `arm` reads `camera.fov`,
# but `_drive_camera` runs AFTER `_drive_sheet` in the director, so the value it
# reads is the PREVIOUS frame's. On the rip frame those two differ by the whole
# fov close (5 degrees), which puts the film's content 9% off the world's.
var capture_fov := 0.0
var capture_eye := Vector3.ZERO
# The UV bake's constants, resolved once in `arm`. Per-vertex they were a matrix
# multiply, a subtraction and three dots; here they are three dots and two
# multiplies. There is deliberately no forward vector among them — see `_uv_for`.
var _uv_scale := Vector2(0.5, 0.5)

# Per-shard separation, authored from the tear. Not integrated: `apply` writes it
# fresh every frame from the tear progress, so a scrubbed frame is exact.
var _shard_dir: Array[Vector3] = []
var _shard_turn: Array[Vector3] = []
var _shard_leads: Array[float] = []


func _ready() -> void:
	# The sheet is a COORDINATE SYSTEM, not a place: every coordinate it deals in
	# is already world space, so a parent transform would only ever be in the way.
	# (The same note, and the same bug, as `ChainVisual._ready`.)
	transform = Transform3D.IDENTITY


## Build everything and freeze a copy of the world. `hide_during_capture` is
## everything that must NOT appear in the captured image — the anchor, the chain
## itself, the player's weapon — because the sheet is a picture of the world
## BEFORE the rip and anything that was added for the rip is not part of it.
##
## `fov_deg` is the fov the frame will actually be DRAWN with at this instant. It
## is passed in rather than read from `camera.fov` on purpose, and the difference
## is not academic: the camera's fov is composed by the feedback controller one
## frame later than the director runs, so reading it here returns the previous
## frame's value — 75.0 where the frame is drawn at 70.0. Both the capture and the
## UV bake below are projections through this frustum, so a wrong fov scales the
## film's entire content about the screen centre and the film stops agreeing with
## the world it was torn out of.
func arm(
	camera: Camera3D,
	next_tuning: ChainUltimateTuning,
	hide_during_capture: Array,
	fov_deg: float
) -> bool:
	if built:
		return false
	tuning = next_tuning
	if camera == null or not camera.is_inside_tree():
		push_error("ChainRealitySheet.arm: no camera")
		return false

	# ---- THE SOURCE FRAME ------------------------------------------------
	# The sheet is born as a flat piece of the view, perpendicular to the way the
	# player was looking and sitting at the anchor's own depth. Its local XY is
	# therefore the camera's XY, which is what lets the cut list be authored as
	# screen-shaped strokes in `chain_ultimate_tuning.gd`.
	source_basis = camera.global_transform.basis.orthonormalized()
	source_origin = _sheet_origin_at_rip(camera)
	capture_transform = Transform3D(source_basis, source_origin)

	var view_size := _capture_size(camera)
	# THE FRUSTUM IS THE PASSED-IN ONE, and it is used TWICE — here for the UV
	# bake and below for the capture camera — so the photograph and the mesh can
	# never disagree about which view they are describing.
	var half_h := tan(deg_to_rad(fov_deg * 0.5))
	var aspect := float(view_size.x) / maxf(float(view_size.y), 1.0)
	# THE DEPTH IS THE PLANE'S OWN DISTANCE, AND IT IS A CONSTANT.
	#
	# This is the one piece of the bake that is easy to get wrong in a way that
	# still produces a picture. The film lies IN the plane whose normal is the
	# camera's forward axis, so every vertex of it is the SAME distance from the
	# camera — that distance, `anchor_distance`, and nothing else. The first
	# version measured each vertex's depth ALONG the view axis instead, which is
	# the component of a vector that is already perpendicular to it: zero for
	# every vertex, floored to 0.05 by the guard, and the projection became
	# `q / 0.05` — twenty times too large. Every vertex clamped to the edge of the
	# texture and the film rendered as one smeared wash of sky, which is exactly
	# what it looked like on the first render and is why this comment is long.
	_uv_scale = Vector2(
		1.0 / (half_h * aspect * maxf(tuning.anchor_distance, 0.1)),
		1.0 / (half_h * maxf(tuning.anchor_distance, 0.1)))

	# ---- 1 · THE CAPTURE RIG --------------------------------------------
	capture_viewport = SubViewport.new()
	capture_viewport.name = "SheetCapture"
	capture_viewport.size = view_size
	capture_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	capture_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	capture_viewport.transparent_bg = false
	capture_viewport.disable_3d = false
	capture_viewport.msaa_3d = Viewport.MSAA_DISABLED
	add_child(capture_viewport)

	capture_camera = Camera3D.new()
	capture_camera.name = "SheetCaptureCamera"
	capture_camera.fov = fov_deg
	capture_camera.near = camera.near
	capture_camera.far = camera.far
	capture_camera.current = true
	capture_viewport.add_child(capture_camera)
	# A `SubViewport` is not a `Node3D`, so this camera's LOCAL transform is
	# already its world one, and the copy is exact.
	capture_camera.transform = camera.global_transform
	capture_fov = fov_deg
	capture_eye = camera.global_position
	print("  ARM capture: fov=%.2f eye=%s" % [capture_fov, capture_eye])

	# ---- 2 · THE MATERIALS ----------------------------------------------
	sheet_material = ShaderMaterial.new()
	sheet_material.shader = SHEET_SHADER
	sheet_material.render_priority = 2
	hole_material = ShaderMaterial.new()
	hole_material.shader = HOLE_SHADER
	hole_material.render_priority = 1

	# ---- 3 · THE GEOMETRY -----------------------------------------------
	# One full surface for the wound, and `shard_count` meshes for the pieces.
	# They share the UV bake, the lobe outline and the source frame, so the
	# pieces cannot disagree with the whole they came from.
	var full := _build_surface(-1)
	var hole_mesh := MeshInstance3D.new()
	hole_mesh.name = "RealityHole"
	hole_mesh.mesh = full
	hole_mesh.material_override = hole_material
	hole_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(hole_mesh)
	# The wound does not move for the rest of the ceremony. It is the place the
	# sheet used to be, and the sheet is the only thing that leaves.
	hole_mesh.global_transform = Transform3D(
		_aspect_basis(source_basis), source_origin)
	hole = hole_mesh

	sheet_root = Node3D.new()
	sheet_root.name = "RealitySheet"
	add_child(sheet_root)
	sheet_root.transform = Transform3D.IDENTITY

	for k in tuning.shard_count:
		var mesh := _build_surface(k)
		if mesh == null:
			continue
		var piece := MeshInstance3D.new()
		piece.name = "Shard%d" % k
		piece.mesh = mesh
		piece.material_override = sheet_material
		piece.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		sheet_root.add_child(piece)
		shards.append(piece)
		_author_separation(k)

	# ---- 4 · HIDE WHAT IS NOT PART OF THE WORLD -------------------------
	# The anchor and the chain are both things the rip ADDED. If they were in the
	# capture the sheet would show a picture of its own cause.
	var restored: Array = []
	for node in hide_during_capture:
		var n3 := node as Node3D
		if n3 == null or not is_instance_valid(n3):
			continue
		restored.append([n3, n3.visible])
		n3.visible = false
	sheet_root.visible = false

	built = true
	capture_state = 1
	_settle_frames = 0
	# The hidden nodes come back as soon as the capture is taken — see
	# `_process`. They are stored on the object rather than in a local because
	# the capture finishes on a LATER frame than this call.
	_restore_after_capture = restored
	return true


## Advance the capture's three-step dance. Called by the director every frame;
## MUST NOT be folded into `apply` because the capture has to happen on a frame
## of its own, with the sheet still invisible.
func step_capture() -> void:
	if not built:
		return
	match capture_state:
		1:
			# One settle frame with the rig live, so the viewport has rendered
			# the world at least once before it is asked for a picture of it.
			_settle_frames += 1
			if _settle_frames >= 2:
				capture_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
				capture_state = 2
		2:
			# The once-frame has been drawn. Freeze it, hand the world back, and
			# show the sheet. From here the texture is a photograph.
			capture_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
			sheet_material.set_shader_parameter("capture_tex", capture_viewport.get_texture())
			for entry in _restore_after_capture:
				var n3 := entry[0] as Node3D
				if is_instance_valid(n3):
					n3.visible = bool(entry[1])
			_restore_after_capture.clear()
			sheet_root.visible = true
			capture_state = 3


func frozen() -> bool:
	return capture_state == 3


## Everything the shaders need for this frame, written fresh from `state` (the
## tuning's own `evaluate`). Nothing here accumulates, so a frame rendered at
## 2.31s is the same frame whether it is the fifth or the five hundredth.
func apply(state: Dictionary, cam_basis: Basis, sheet_center: Vector3) -> void:
	if not built or not frozen():
		return
	var t := float(state["t"])

	# ---- WHERE THE SHEET IS ---------------------------------------------
	# It does not move as a rigid body: the peel in the vertex shader is what
	# carries it, and this transform only has to put the sheet's origin in the
	# right PLACE and ORIENTATION. The two together are what makes the freed part
	# travel while the attached part stays welded to the world.
	#
	# THE FILM'S PROPORTIONS LIVE HERE, AND ONLY HERE. The mesh is built as a
	# unit disc in a round outline; the fact that a torn-off piece of a 16:9 view
	# is wider than it is tall is this one scale, applied in the sheet's OWN
	# axes before the orientation. It is deliberately not folded into `_polar`:
	# `v_r` (the mesh's red channel) is the outline's normalised radius and the
	# shaders' rim falloff, peel front and curl all read it, and an edge that
	# reaches 0.85 of nominal on one side and 1.55 on the other would put the rim
	# fade in the wrong place on every side but one.
	sheet_root.transform = Transform3D(
		_aspect_basis(tuning.sheet_basis(t, cam_basis)), sheet_center)

	# ---- THE CONTRACTION -------------------------------------------------
	# `state["pull"]` is already `ease_in_out(span(t, t_pull_start, t_float_start))`,
	# which is exactly the input `ChainUltimateTuning.sheet_contract_at` is built
	# on — so this is that function read off the state rather than re-derived, and
	# the picture coming in cannot drift from the film coming off.
	#
	# `radius` is the film's radius RIGHT NOW and it replaces `tuning.sheet_radius`
	# in every metric uniform below. A uniform in metres written against the BUILT
	# radius while the vertices live at the contracted one is a unit that means two
	# things in two files, which is the failure this project has a standing rule
	# against.
	var contract := lerpf(1.0, tuning.sheet_contract_end, float(state["pull"]))
	var radius := tuning.sheet_radius * contract

	# ---- THE SURFACE -----------------------------------------------------
	sheet_material.set_shader_parameter("clock", t)
	sheet_material.set_shader_parameter("sheet_radius", radius)
	sheet_material.set_shader_parameter("contract", contract)
	sheet_material.set_shader_parameter("warp", tuning.sheet_warp)
	sheet_material.set_shader_parameter("ripple", tuning.sheet_ripple)
	sheet_material.set_shader_parameter("ripple_hz", tuning.sheet_ripple_hz)
	sheet_material.set_shader_parameter("curl", tuning.sheet_curl)
	sheet_material.set_shader_parameter("edge_inner", tuning.sheet_edge_inner)
	sheet_material.set_shader_parameter("ink_width", tuning.tear_ink_width * contract)
	sheet_material.set_shader_parameter("white_width", tuning.tear_edge_width * contract)
	# THE PEEL'S SLIDE, NOT THE BODY'S HAUL. The film as a whole is carried by
	# this node's transform (see `sheet_center_at`); what the vertex shader adds is
	# only the extra travel of the part that has already let go, so the sheet
	# comes off its lower edge first instead of sliding away as a rigid plate.
	sheet_material.set_shader_parameter("pull_amount", tuning.sheet_peel_slide)
	sheet_material.set_shader_parameter("lift_amount", tuning.sheet_peel_lift)

	# ---- THE PEEL --------------------------------------------------------
	# The front runs from below the sheet's bottom edge to above its top one, so
	# the first and last moments of the peel are not two dead frames.
	sheet_material.set_shader_parameter("peel", lerpf(-0.05, 1.05, float(state["pull"])))

	# ---- THE CUTS --------------------------------------------------------
	var segs := PackedVector4Array()
	var opens := PackedFloat32Array()
	var glows := PackedFloat32Array()
	var open_state: Array = state["cut_open"]
	for i in ChainUltimateTuning.CUT_SLOTS:
		var seg := Vector4.ZERO
		var open := 0.0
		if i < tuning.cuts.size():
			var c := tuning.cuts[i]
			# Authored in sheet radii, handed to the shader in metres: the shader
			# compares against real distances, and a unit that means two things
			# in two files is a unit that will be wrong in one of them.
			seg = Vector4(c.x, c.y, c.z, c.w) * radius
			open = float(open_state[i]) if i < open_state.size() else 0.0
			# The gap is a width in metres and the vertex it is measured against
			# lives in the contracted mesh, so it contracts with the film. Without
			# this an opening of `cut_open_width` on a film a third of its built
			# size would be a third-of-a-metre trench across a 5m sheet.
			open *= contract
		if i < tuning.cuts.size():
			segs.append(seg)
			opens.append(open)
			# `decay`, not `exp(-since)`: a stroke that has not been made yet has
			# no heat on its lip. The shader gates both the lip and the ink on
			# `open > 0`, so this was invisible while every stroke was closed — and
			# would have become visible the moment anything else read the channel.
			glows.append(ChainUltimateTuning.decay(t, tuning.cut_time(i), 5.0))
		else:
			segs.append(Vector4.ZERO)
			opens.append(0.0)
			glows.append(0.0)
	sheet_material.set_shader_parameter("cut_seg", segs)
	sheet_material.set_shader_parameter("cut_open", opens)
	sheet_material.set_shader_parameter("cut_glow", glows)

	# ---- THE END ---------------------------------------------------------
	sheet_material.set_shader_parameter("tear", float(state["tear"]))
	sheet_material.set_shader_parameter("flash", float(state["flash"]))
	sheet_material.set_shader_parameter("dissolve", float(state["dissolve"]))

	# ---- THE PIECES ------------------------------------------------------
	_apply_separation(float(state["tear"]), t)

	# ---- THE WOUND -------------------------------------------------------
	# The wound's mesh is the same plate at its BUILT size, and that is the point:
	# the wound is the place the film came FROM, so it is the film's shape and the
	# film's size forever. It does not contract with the film, it does not move with
	# the film, and — the fix — it no longer has to be COMPARED against the film's
	# rim. V1's `outside = smoothstep(contract …)` was that comparison, and it is
	# what drew an annulus of void around a shrunken picture, which is the iris the
	# user asked to have deleted. See the header of `chain_reality_hole.gdshader`.
	hole_material.set_shader_parameter("clock", t)
	hole_material.set_shader_parameter("sheet_radius", tuning.sheet_radius)
	hole_material.set_shader_parameter("peel", lerpf(-0.05, 1.05, float(state["pull"])))
	hole_material.set_shader_parameter("close", float(state["hole_close"]))
	hole_material.set_shader_parameter("edge", clampf(1.0 - float(state["dissolve"]) * 1.4, 0.0, 1.0))
	hole_material.set_shader_parameter("glow", clampf(1.0 - float(state["tear"]) * 1.2, 0.0, 1.0))


# ===========================================================================
# THE PIECES
# ===========================================================================

## Author one shard's flight. Deterministic from the index alone — no random
## numbers at runtime, because a take has to be repeatable to be reviewable.
func _author_separation(k: int) -> void:
	# Golden-angle spacing so six pieces leave in six different directions
	# instead of in a fan. The brief asks for 裂片翻飞 and explicitly NOT for an
	# explosion, so the angles are spread but the distances are small.
	var golden := 2.399963
	var angle := fmod(float(k) * golden, TAU)
	var radial := Vector3(cos(angle), sin(angle), 0.0)
	_shard_dir.append(radial)
	# Some pieces lead and some lag: `leads` staggers the start of each piece's
	# travel by up to 60ms, which is the difference between a tear and a pop.
	_shard_leads.append(fmod(float(k) * 0.37, 1.0))
	var turn := Vector3(
		sin(float(k) * 1.7 + 0.3), cos(float(k) * 2.3 - 0.8), sin(float(k) * 0.9))
	_shard_turn.append(turn.normalized())


func _apply_separation(tear: float, t: float) -> void:
	for k in shards.size():
		var piece := shards[k]
		if not is_instance_valid(piece):
			continue
		# Each piece starts moving a little later than the one before it, so the
		# break has a direction. `tear` is already eased; the lead is applied to
		# the EASING'S INPUT rather than to its output, so a lagging piece is at
		# the beginning of the same motion and not merely at a smaller version of
		# the end one.
		var lead := _shard_leads[k] * 0.55
		var u := clampf((tear - lead) / maxf(1.0 - lead, 0.0001), 0.0, 1.0)
		u = ChainUltimateTuning.ease_out_cubic(u)
		var travel := _shard_dir[k] * (tuning.shard_spread * u)
		# A little outward spin and tumble. No gravity: these are surfaces, not
		# debris, and the brief is explicit that they must not fall or bounce.
		var spin := deg_to_rad(tuning.shard_spin) * u
		var tumble := deg_to_rad(tuning.shard_tumble) * u
		var axis := _shard_turn[k]
		var basis := Basis(axis, tumble)
		basis = basis * Basis(Vector3(0.0, 0.0, 1.0), spin * (1.0 if k % 2 == 0 else -1.0))
		piece.transform = Transform3D(basis, travel)


# ===========================================================================
# THE MESH
# ===========================================================================

## Build the sheet's surface, optionally restricted to one shard.
##
## `shard_index` is negative for the WHOLE surface (used by the wound) and
## 0..shard_count-1 for one piece. Both go through this one function so the
## outline, the UV bake and the source frame are literally the same arithmetic —
## a piece built by a second code path would be a piece that does not fit the hole
## it came out of.
##
## EVERY VERTEX CARRIES TWO NUMBERS, and the second one is why the tear reads:
##
##   COLOR.r  the outline's normalised radius — the shader's rim fade, peel front
##            and curl all read it, so the sheet's edge is where the sheet's edge
##            actually is and not where a circle would be.
##   COLOR.g  the distance to THIS SHARD'S MESH BOUNDARY, normalised over 6cm and
##            inverted, so 0 is ON the boundary and 1 is well inside.
##
## The second one is baked because a fragment shader cannot ask a mesh where its
## own edge is. Without it the pieces of a tear are six grey polygons coming
## apart: the split between them has no white edge and no ink line, so the
## manga language of PHASE 7 has nothing to attach to. See `_shard_boundaries`.
func _build_surface(shard_index: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var lobes := _lobe_table()
	var tri_count := 0

	for ring in RING_COUNT:
		for sector in SECTOR_COUNT:
			# The shard boundary. A wedge cut is a boundary in ANGLE, and a
			# straight radial boundary reads as a pie chart — so the boundary
			# index is shifted per ring by a small wobble, which makes the split
			# run as a jagged staircase. That staircase is the difference between
			# "six slices" and "torn into six".
			if shard_index >= 0:
				var wobble := 0.055 * sin(float(ring) * 2.7 + 1.1)
				var u := float(sector) / float(SECTOR_COUNT) + wobble
				var here := int(floor(fposmod(u, 1.0) * float(tuning.shard_count)))
				if here % tuning.shard_count != shard_index:
					continue
			var next_sector: int = (sector + 1) % SECTOR_COUNT
			if ring == 0:
				# The innermost ring is a fan of triangles through the centre.
				# The OUTER vertex is `_polar(1, …)`, not `_polar(0, …)`: ring 0
				# is the centre itself and returns ZERO, so passing it here would
				# emit a degenerate triangle and leave a hole at the middle of the
				# sheet the size of the first ring.
				_tri(st,
					_vert(0, sector, lobes, shard_index),
					_vert(1, sector, lobes, shard_index),
					_vert(1, next_sector, lobes, shard_index))
				tri_count += 1
			else:
				_tri(st,
					_vert(ring, sector, lobes, shard_index),
					_vert(ring, next_sector, lobes, shard_index),
					_vert(ring + 1, next_sector, lobes, shard_index))
				_tri(st,
					_vert(ring, sector, lobes, shard_index),
					_vert(ring + 1, next_sector, lobes, shard_index),
					_vert(ring + 1, sector, lobes, shard_index))
				tri_count += 2

	if tri_count == 0:
		return null
	st.index()
	return st.commit()


## One vertex, as `[position, uv2, color]`.
##
## THE COLOR CHANNELS ARE THE MESH'S OWN COORDINATE SYSTEM, and every one of them
## is a QUANTITY THAT IS UNIFORM AROUND THE OUTLINE — which is the whole point.
## The outline's radius varies by ±16% around the rim (`_lobe_table`), so a
## quantity normalised by the NOMINAL radius, which is what the first version
## baked, is 0.82 at one edge and 1.16 at another. Every threshold compared
## against it then fires at a different place on every side: the rim fade is a
## crisp line on the short lobes and a 50cm blur on the long ones, and the curl
## only exists on one half of the sheet.
##
##   R  the normalised radius, 1.0 ON the outline wherever that is.
##   G  the distance to this shard's own mesh boundary, over 6cm, inverted.
##   B  the peel coordinate: 0 at the outline's bottom, 1 at its top.
func _vert(
	ring: int, sector: int, lobes: PackedFloat32Array, shard_index: int
) -> Array:
	var p := _polar(ring, sector, lobes)
	var lobe: float = maxf(lobes[sector % SECTOR_COUNT], 0.001)
	# `_polar` builds the vertex at `sheet_radius * u * lobe`, so dividing by the
	# lobe gives back `u` — the ring's own fraction of the way out.
	var u := clampf(float(ring) / float(RING_COUNT), 0.0, 1.0)
	var d_rim := tuning.sheet_radius * (1.0 - u) * lobe
	var d := d_rim
	if shard_index >= 0 and p.length() > 0.0001:
		# Distance to the wedge's two boundary LINES, as an arc length. The
		# boundaries are per-ring (that is the wobble), so they are re-derived
		# here for this vertex's ring rather than taken from one representative
		# ring — a straight-ish seam through a staircase mesh is a seam that only
		# touches the mesh at one corner.
		var bounds := _shard_boundaries(shard_index, ring)
		var ang := atan2(p.y, p.x)
		var d_ang := minf(
			absf(wrapf(ang - bounds[0], -PI, PI)),
			absf(wrapf(ang - bounds[1], -PI, PI))) * p.length()
		d = minf(d, d_ang)
	# The peel runs bottom-to-top in the OUTLINE's own frame, so it is `u`
	# projected on the sheet's own vertical axis and normalised by the outline's
	# height at that angle.
	var peel := 0.5 + 0.5 * clampf(sin(atan2(p.y, p.x)), -1.0, 1.0) * u
	return [p, _uv_for(p), Color(u, clampf(d / 0.06, 0.0, 1.0), peel, 1.0)]


## The two angles that bound shard `shard_index` at `ring`, in the SAME arithmetic
## `_build_surface` uses to decide which sectors belong to it — derived from it
## rather than written down twice, because a boundary that is one place in the
## mesh and another place in the shading is a seam that floats off its own edge.
func _shard_boundaries(shard_index: int, ring: int) -> PackedFloat32Array:
	var wobble := 0.055 * sin(float(ring) * 2.7 + 1.1)
	var count := float(maxi(tuning.shard_count, 1))
	var k := float(shard_index)
	return PackedFloat32Array([
		(k / count - wobble) * TAU,
		((k + 1.0) / count - wobble) * TAU,
	])


func _tri(st: SurfaceTool, a: Array, b: Array, c: Array) -> void:
	for v in [a, b, c]:
		st.set_uv2(v[1])
		st.set_color(v[2])
		st.add_vertex(v[0])


## One vertex of the outline: `ring` (0 is the centre) and `sector` around it.
func _polar(ring: int, sector: int, lobes: PackedFloat32Array) -> Vector3:
	if ring == 0:
		return Vector3.ZERO
	var u := float(ring) / float(RING_COUNT)
	var radius := tuning.sheet_radius * u * float(lobes[sector % SECTOR_COUNT])
	var angle := TAU * float(sector) / float(SECTOR_COUNT)
	return Vector3(cos(angle) * radius, sin(angle) * radius, 0.0)


## The film's real proportions, in the sheet's own axes. See `apply`.
func _aspect_basis(base: Basis) -> Basis:
	if tuning == null:
		return base
	return base * Basis.from_scale(
		Vector3(tuning.sheet_aspect.x, tuning.sheet_aspect.y, 1.0))


## A local vertex coordinate as the WORLD saw it. Everything the sheet deals in
## locally is the unscaled disc; anything measured against the capture, the
## anchor or the blade has to go through here first.
func _scaled(p: Vector3) -> Vector3:
	if tuning == null:
		return p
	return Vector3(p.x * tuning.sheet_aspect.x, p.y * tuning.sheet_aspect.y, p.z)


## The outline, as a radius multiplier per sector.
##
## THE FOUR NUMBERS THAT DECIDE WHETHER THIS IS A MEMBRANE OR A DISC. Unequal
## amplitudes and unrelated frequencies (2, 3, 7, 11 — no harmonic of one is
## another) so the sum has no period the eye can find. Four equal harmonics give
## a gear; two give an egg; these four give a shape with one long side, one short
## one, and a ragged edge, which is what a torn film has.
func _lobe_table() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(SECTOR_COUNT)
	for s in SECTOR_COUNT:
		var angle := TAU * float(s) / float(SECTOR_COUNT)
		var sum := 0.0
		for i in _LOBE_AMPS.size():
			# `sheet_lobe_low` / `sheet_lobe_high` scale the two halves of the
			# table: the low pair gives the big asymmetry, the high pair the edge.
			var freq_scale := tuning.sheet_lobe_high / 7.0 if i >= 2 else 1.0
			var amp: float = _LOBE_AMPS[i] * (tuning.sheet_lobe_low / 2.0 if i < 2 else 1.0)
			sum += amp * sin(float(_LOBE_FREQ[i]) * freq_scale * angle + float(_LOBE_PHASE[i]))
		out[s] = 1.0 + tuning.sheet_lobe * (sum / _LOBE_SUM)
	return out


## The frozen capture UV for a vertex, baked at build time.
##
## The sheet was, at the instant of the rip, a flat piece of the view: it lay in
## a plane perpendicular to the camera's axis at a known depth. So the projection
## is a uniform scale and nothing more — the vertex's two in-plane coordinates
## against the camera's own axes, divided by the depth and the half-angle
## tangents, which `arm` has already folded into `_uv_scale`. No matrix, no Y
## convention, no aspect; three dots and two multiplies per vertex, and it is done
## once.
func _uv_for(p: Vector3) -> Vector2:
	# `_scaled` first: the mesh's local coordinates are the unscaled disc, and the
	# capture was taken of the world. Skipping it bakes a UV that is right at the
	# centre and wrong by the aspect factor at every edge.
	var q := _scaled(p)
	var x := q.dot(source_basis.x) * _uv_scale.x
	var y := q.dot(source_basis.y) * _uv_scale.y
	return Vector2(0.5 + x * 0.5, 0.5 - y * 0.5)


func _sheet_origin_at_rip(camera: Camera3D) -> Vector3:
	# The sheet's own origin: `anchor_distance` straight out along the aim, at
	# the same height as the eye plus the authored rise.
	#
	# MEASURED FROM THE CAMERA, not from the player's feet: the anchor is placed
	# by the director from the camera too, and two different origins for the same
	# point is exactly how a sheet ends up not covering the hole it came from.
	var fwd := -camera.global_transform.basis.z.normalized()
	var up := camera.global_transform.basis.y.normalized()
	return camera.global_position + fwd * tuning.anchor_distance + up * tuning.anchor_rise


func _capture_size(camera: Camera3D) -> Vector2i:
	if camera == null:
		return Vector2i(1280, 720)
	var rect := camera.get_viewport().get_visible_rect().size
	return Vector2i(
		maxi(int(rect.x), 64),
		maxi(int(rect.y), 64)
	)


func teardown() -> void:
	for entry in _restore_after_capture:
		var n3 := entry[0] as Node3D
		if is_instance_valid(n3):
			n3.visible = bool(entry[1])
	_restore_after_capture.clear()
	for piece in shards:
		if is_instance_valid(piece):
			piece.queue_free()
	shards.clear()
	if is_instance_valid(hole):
		hole.queue_free()
	if is_instance_valid(sheet_root):
		sheet_root.queue_free()
	if is_instance_valid(capture_viewport):
		capture_viewport.queue_free()
	built = false
	capture_state = 0


func _exit_tree() -> void:
	built = false
