extends Node3D
class_name IaidoExecution

# 已经被切开了，但结果晚了一瞬间才发生.
#
# The whole design of this node is one sentence: the enemy is dead the instant
# the blade passes, and the world does not admit it until the click. That is why
# nothing here is a death ANIMATION. There is no clip, no fade, no ragdoll — the
# body holds the exact pose it was standing in, with a hairline where the plane
# went through it, and the only thing that changes for three and a half seconds
# is a two-centimetre misalignment the player notices before they can say what
# they noticed.
#
# ─── WHY EVERYTHING HERE IS A PURE FUNCTION OF `t` ────────────────────────────
#
# The ceremony clock is the only clock. The fall is written in CLOSED FORM
# (`v₀·t + ½g·t²`) rather than accumulated per frame, and `stage(t)` recomputes
# the entire pose from `t` on every call. Two reasons, and this codebase has been
# bitten by both:
#
#   * the reviewer's screenshot tool pins the clock (`set_debug_hold`), which can
#     jump `elapsed` by seconds in one call. An accumulator would integrate that
#     jump as one enormous frame and fling the halves off screen; a closed form
#     simply answers "at 7.40s the upper half is 0.31m down".
#   * a frame that is a function of `t` is identical in two renders, which is the
#     only way the release beat can be A/B'd at all.
#
# ─── WHAT THIS NODE DOES NOT DO ──────────────────────────────────────────────
#
# It does not decide anything. Lethality, support and mode were decided by the
# enemy and the director before this was constructed; by the time it exists, the
# body is already logically dead and cannot attack, move or be hit. This node
# owns the VISUAL release and nothing else, and every path out of it — normal,
# aborted, scene torn down, broken clock — ends in `force_resolve()`, because a
# bug in a ceremony must never leave a corpse standing in the world.

const GRAVITY := 9.8

signal released(index: int)
signal resolved(index: int)

var actor: Node3D
var camera: Camera3D
var plane := IaidoCutPlane.none()
var profile: IaidoExecutionProfile
## What this enemy actually does, resolved once from its profile and whether an
## authored split exists. See `IaidoExecutionProfile.resolve_mode()`.
var mode: StringName = IaidoExecutionProfile.TYPE_NONE
var index := 0

var cut_time := 0.0
var release_at := 0.0
var cut_anchor := Vector3.ZERO
var base_basis := Basis.IDENTITY
var body_extent := 0.6
var body_box := AABB()

var pieces: Array[Dictionary] = []
var look: Array[Dictionary] = []
var chips: Array[Dictionary] = []
## The body worn during the hold when the real pieces are authored meshes rather
## than clipped ones — see `_swap_to_authored`. §E §7: the cut-plane shader draws
## the wound, and the real split geometry is swapped in at the click.
var wounded: Node3D
var authored := false
var authored_local := Transform3D.IDENTITY
var halved := false
var built := false
var done := false
var released_flag := false
var fired: Dictionary = {}
var events: Array[StringName] = []


# =============================================================================
# BUILD
# =============================================================================

## Take the body over. From here the actor is a corpse that has not been told yet.
##
## `release_time` is the ceremony instant of the final click. The per-target
## spread is added HERE rather than by the caller so that "several enemies died
## to one slash" is decided in the one place that knows how many there were.
func begin(
		who: Node3D,
		view: Camera3D,
		cut: IaidoCutPlane,
		which: IaidoExecutionProfile,
		cut_at: float,
		release_time: float,
		ordinal: int) -> bool:

	actor = who
	camera = view
	plane = cut if cut != null else IaidoCutPlane.none()
	profile = which
	index = ordinal
	cut_time = cut_at
	# 20-80ms of spread between bodies killed by the same slash. §P: the CUT is
	# one instant, the FALL is not — ten enemies coming apart on the exact same
	# frame reads as a copy-and-paste, and the cheapest cure is that they don't.
	release_at = release_time + 0.02 + 0.03 * float(ordinal % 3)
	if profile == null:
		profile = IaidoExecutionLibrary.fallback()
	IaidoExecutionLibrary.apply_material(profile)
	set_process(false)
	if actor == null or not is_instance_valid(actor):
		return false

	var sources := _capture_sources()
	authored = profile.split_variants.size() >= 2 and profile.split_variants[0] != null
	mode = profile.resolve_mode(authored or not sources.is_empty())
	if mode == IaidoExecutionProfile.TYPE_NONE:
		# The enemy's answer to the contract is "no". Its own death already ran,
		# and this node must not stand in the way of it.
		done = true
		return false

	_measure(sources)
	_find_anchor()
	base_basis = actor.global_basis
	if mode == IaidoExecutionProfile.TYPE_SPECIAL:
		# One body, whole, with the wound drawn on it — nothing is discarded, so
		# the scar is a state of the surface rather than a cut in it.
		_build_wounded(sources)
		pieces.append({"pivot": wounded, "sign": 0.0, "upper": false, "delay": 0.0, "tip_sign": 1.0})
	elif authored:
		# §E §7 · THE PRODUCTION PATH. The body wears the cut-plane shader for the
		# whole hold and the real split meshes are swapped in on the click, so the
		# player never sees a mesh swap — they see a body that was whole and then
		# was not.
		_build_halves()
		_build_wounded(sources)
	else:
		# The generic path: the two halves ARE the clip-plane cut, so there is
		# nothing to swap and the body is two pieces from the instant it is built.
		_build_halves()
		_build_clipped_halves(sources)
	_build_chips()
	built = true
	# THE SWAP HAPPENS HERE AND IT IS INVISIBLE. The halves are the same meshes,
	# in the same place, wearing the same colour, with `trace = 0` — so the frame
	# before and the frame after are pixel-identical and nothing in the world can
	# tell that the body became two pieces. That is the point: the body is cut
	# before anything looks cut.
	actor.visible = false
	return true


## Every mesh under the actor, with what it takes to draw it again somewhere else.
func _capture_sources() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var found := actor.find_children("*", "MeshInstance3D", true, false)
	if actor is MeshInstance3D:
		found.push_front(actor)
	for node in found:
		var mesh_node := node as MeshInstance3D
		if mesh_node == null or mesh_node.mesh == null:
			continue
		out.append({
			"mesh": mesh_node.mesh,
			"xform": mesh_node.global_transform,
			"material": mesh_node.get_active_material(0),
			"shadow": mesh_node.cast_shadow,
		})
	return out


func _measure(sources: Array[Dictionary]) -> void:
	var box := AABB()
	var first := true
	for entry in sources:
		var mesh: Mesh = entry["mesh"]
		var xform: Transform3D = entry["xform"]
		var local := mesh.get_aabb()
		var lo := Vector3.INF
		var hi := -Vector3.INF
		# All eight corners: an AABB is not invariant under rotation, and a box
		# that is too SMALL would put the pivot inside the body's edge.
		for corner in 8:
			var point := xform * (local.position + Vector3(
				local.size.x if corner & 1 else 0.0,
				local.size.y if corner & 2 else 0.0,
				local.size.z if corner & 4 else 0.0,
			))
			lo = Vector3(minf(lo.x, point.x), minf(lo.y, point.y), minf(lo.z, point.z))
			hi = Vector3(maxf(hi.x, point.x), maxf(hi.y, point.y), maxf(hi.z, point.z))
		var world := AABB(lo, hi - lo)
		if first:
			box = world
			first = false
		else:
			box = box.merge(world)
	if first:
		box = AABB(actor.global_position - Vector3.UP * 0.1, Vector3.ONE * 1.2)
	body_box = box
	body_extent = maxf(maxf(box.size.x, box.size.y), box.size.z) * 0.5


## The point on the cut plane the body rotates about.
##
## THE PLANE ITSELF IS NEVER MOVED — an enemy does not get to re-author the slash.
## What the profile decides is where ON that plane the piece is pivoted, and the
## answer has to be both on the plane and at the height the cut actually crosses
## the body, or the halves will hinge somewhere the wound is not.
func _find_anchor() -> void:
	var height := profile.preferred_cut_height
	match profile.cuttable_region:
		&"upper":
			height = maxf(height, 0.70)
		&"core":
			height = 0.5
	var centre := body_box.get_center()
	var probe := Vector3(
		centre.x,
		body_box.position.y + body_box.size.y * height,
		centre.z)
	if plane.is_valid():
		# Project onto the plane: the pivot is where the blade WENT.
		cut_anchor = probe - plane.normal * plane.signed_distance(probe)
	else:
		cut_anchor = probe
	# A pivot sitting under the floor would make a falling half hinge through it.
	cut_anchor.y = maxf(cut_anchor.y, actor.global_position.y + 0.05)


## Two pivots, both sitting AT THE WOUND, so everything that pivots later pivots
## about the cut and not about the body's feet — which is the difference between a
## slice falling off and a statue tipping over.
func _build_halves() -> void:
	halved = true
	# Where an authored half has to sit so it lands exactly on the body it
	# replaces. The pivots are at the wound, the authored meshes are authored
	# about the enemy's own origin, so the offset is the difference.
	authored_local = Transform3D(base_basis, cut_anchor).affine_inverse() * actor.global_transform
	for side in 2:
		var pivot := Node3D.new()
		pivot.name = "HalfA" if side == 0 else "HalfB"
		pivot.global_transform = Transform3D(base_basis, cut_anchor)
		add_child(pivot)
		pieces.append({
			"pivot": pivot,
			"sign": 1.0 if side == 0 else -1.0,
			"upper": (1.0 if side == 0 else -1.0) * plane.normal.y > 0.0,
			"delay": 0.0 if side == 0 else profile.fall_asymmetry,
			"tip_sign": 1.0 if side == 0 else -1.0,
		})


func _build_clipped_halves(sources: Array[Dictionary]) -> void:
	for side in 2:
		var pivot: Node3D = pieces[side]["pivot"]
		for entry in sources:
			_add_clipped(pivot, entry, 1.0 if side == 0 else -1.0)


## The whole body, with the wound drawn on it and nothing removed.
##
## Used for the boss's authored response, and during the hold whenever the real
## pieces are authored meshes — because the swap must happen at the CLICK, not at
## the cut. The body has to be visibly cut for three seconds before it is visibly
## two pieces, and a body that is two pieces from the start was never held.
func _build_wounded(sources: Array[Dictionary]) -> void:
	wounded = Node3D.new()
	wounded.name = "WoundedBody"
	wounded.global_transform = Transform3D(base_basis, cut_anchor)
	add_child(wounded)
	for entry in sources:
		# `cut_keep` 0 keeps BOTH sides: the whole body, with the wound drawn on
		# it. Nothing is discarded, so the scar is a state of the surface.
		_add_clipped(wounded, entry, 0.0)


## §E §7 · the swap. Invisible in the other direction and this one is supposed to
## be visible: the instant the click lands, the body that was one piece becomes
## two. That is §C's FINAL SHEATH CLICK, and it is the second high point of the
## whole skill — so it is a real change of geometry, not a shader trick.
func _swap_to_authored() -> void:
	if wounded != null and is_instance_valid(wounded):
		wounded.queue_free()
	wounded = null
	# The wounded body's materials die with it, and a stale handle into a freed
	# ShaderMaterial is a crash in the middle of the beat this whole feature
	# exists for. The authored halves carry their own art, and there is nothing
	# left for this node to drive on them.
	look.clear()
	for side in 2:
		var scene: PackedScene = profile.split_variants[side]
		if scene == null:
			continue
		var instance := scene.instantiate() as Node3D
		if instance == null:
			continue
		var pivot: Node3D = pieces[side]["pivot"]
		pivot.add_child(instance)
		instance.transform = authored_local


func _add_clipped(pivot: Node3D, entry: Dictionary, sign: float) -> void:
	var mesh_node := MeshInstance3D.new()
	mesh_node.mesh = entry["mesh"]
	mesh_node.cast_shadow = entry["shadow"]
	mesh_node.material_override = _cleave_material(entry, sign)
	pivot.add_child(mesh_node)
	# Placed in world space so the piece is exactly where the body was. The pivot
	# is already at the wound, so Godot converts this into the right local offset.
	mesh_node.global_transform = entry["xform"]
	look.append({
		"material": mesh_node.material_override,
		"traced": sign != 0.0,
	})


func _cleave_material(entry: Dictionary, sign: float) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = load("res://vfx/iaido_cleave.gdshader") as Shader
	var xform: Transform3D = entry["xform"]
	var scale: float = maxf(xform.basis.get_scale().x, 0.0001)
	var mesh: Mesh = entry["mesh"]
	var box := mesh.get_aabb()
	material.set_shader_parameter("cut_plane", plane.local_to(xform))
	material.set_shader_parameter("cut_keep", sign)
	material.set_shader_parameter("albedo", _source_albedo(entry["material"]))
	material.set_shader_parameter("roughness", _source_float(entry["material"], "roughness", 0.80))
	material.set_shader_parameter("metallic", _source_float(entry["material"], "metallic", 0.0))
	material.set_shader_parameter("interior_color", profile.interior_color)
	material.set_shader_parameter("rim_color", profile.rim_color)
	material.set_shader_parameter("rim", profile.interior_rim)
	material.set_shader_parameter("core_emission", profile.core_emission)
	material.set_shader_parameter("core_color", profile.core_color)
	# The band is authored in metres and measured here in the piece's own units.
	material.set_shader_parameter("band", profile.interior_band_m / scale)
	material.set_shader_parameter("body_extent", maxf(maxf(box.size.x, box.size.y), box.size.z) * 0.5)
	material.set_shader_parameter("trace", 0.0)
	material.set_shader_parameter("edge_glow", 0.0)
	material.set_shader_parameter("dissolve", 0.0)
	return material


func _source_albedo(material: Material) -> Color:
	var standard := material as StandardMaterial3D
	if standard != null:
		return standard.albedo_color
	return Color(0.80, 0.80, 0.80)


func _source_float(material: Material, property: String, fallback: float) -> float:
	var standard := material as StandardMaterial3D
	if standard == null:
		return fallback
	return float(standard.get(property))


## A handful of chips off the cut. §M: the enemy being cut IS the effect, so this
## is deliberately a few pieces of the right material and not an explosion.
func _build_chips() -> void:
	if profile.debris_count <= 0:
		return
	if mode == IaidoExecutionProfile.TYPE_SPECIAL:
		return
	var chip_mesh := BoxMesh.new()
	chip_mesh.size = Vector3(0.030, 0.030, 0.030)
	var material := StandardMaterial3D.new()
	material.albedo_color = profile.debris_color
	material.roughness = 0.85
	chip_mesh.material = material
	var along := plane.line_direction(camera)
	var across := plane.normal
	var second := along.cross(across).normalized()
	for i in profile.debris_count:
		var mesh_node := MeshInstance3D.new()
		mesh_node.mesh = chip_mesh
		mesh_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mesh_node.visible = false
		add_child(mesh_node)
		var f := (float(i) / maxf(float(profile.debris_count - 1), 1.0)) - 0.5
		var side := -1.0 if i % 2 == 0 else 1.0
		var wobble := sin(float(i) * 2.399)
		chips.append({
			"mesh": mesh_node,
			"at": cut_anchor + along * (f * body_extent * 1.6) + second * (wobble * 0.05),
			"velocity": (
				across * (side * profile.debris_speed * 0.7)
				+ along * (f * profile.debris_speed)
				+ Vector3.UP * (0.20 + 0.30 * absf(wobble))
			),
			"spin": Vector3(wobble, f, side) * 7.0,
		})


# =============================================================================
# THE CLOCK
# =============================================================================

## The last instant this node can still be doing something. Everything past it is
## a leak, and §12 says a leak here is a body that is logically dead and visually
## still standing.
func lifetime_end() -> float:
	if mode == IaidoExecutionProfile.TYPE_DISSOLVE:
		return release_at + profile.fall_duration + profile.extra_lifetime
	return release_at + profile.fall_duration + profile.fade_duration + profile.extra_lifetime


## The instant the pieces have finished coming apart, in ceremony time. This is
## what has to land before `restore_start`, or the body is still leaving while
## reality is coming back.
func visual_end() -> float:
	if mode == IaidoExecutionProfile.TYPE_DISSOLVE:
		return release_at + profile.fall_duration
	return release_at + profile.fall_duration + profile.fade_duration


func is_finished(t: float) -> bool:
	return done or t >= lifetime_end()


## The whole visual state, as a function of the ceremony clock. See the header.
func stage(t: float) -> void:
	if not built or done:
		return
	var local := t - cut_time
	var trace := IaidoTuning.ease_in_out(IaidoTuning.span(
		local, profile.trace_delay, profile.trace_delay + profile.trace_fade))
	var glow := 0.0
	if t >= release_at:
		glow = 1.0 - IaidoTuning.ease_out_cubic(clampf(
			(t - release_at) / maxf(profile.trace_fade * 1.6, 0.001), 0.0, 1.0))

	# §N · THE THREE EVENTS AUDIO ASKS FOR, announced in the one place that knows
	# when they happened. The cut mark is tiny, the release is the click, and the
	# fall is the material letting go — three cues, and only one of them lands on
	# the same frame as the world collapsing.
	_announce(&"cut_mark", t, cut_time + profile.trace_delay + profile.trace_fade)
	_announce(&"release", t, release_at)
	_announce(&"fall", t, release_at + profile.fall_duration * 0.40)

	for entry in look:
		var material: ShaderMaterial = entry["material"]
		material.set_shader_parameter("trace", trace)
		material.set_shader_parameter("edge_glow", glow)
	_apply_pieces(t, local)
	_apply_chips(t)
	if is_finished(t):
		done = true
		events.append(&"resolved")
		resolved.emit(index)


func _announce(name: StringName, t: float, at: float) -> void:
	if fired.has(name) or t < at:
		return
	fired[name] = true
	events.append(name)
	if name == &"release":
		released_flag = true
		if authored and mode == IaidoExecutionProfile.TYPE_CLEAVE:
			_swap_to_authored()
		released.emit(index)


func _apply_pieces(t: float, local: float) -> void:
	# The 1-3cm misalignment that says "this is already over". It is a CREEP, not
	# a fall: it starts once the hairline is legible, it stops, and everything
	# about the pose until the click is otherwise untouched — §C, 它还没有真正倒.
	#
	# HALVED, because `hold_separation_m` is the distance BETWEEN the two pieces
	# and each of them contributes half of its own accord. It is the same
	# quantity `separation()` reports and the same one the profile is authored
	# in, so the number in the .tres is the number §C asks for: 1-3cm of visible
	# misalignment, not 1-3cm per side and 2-6cm on screen.
	var creep := IaidoTuning.ease_in_out(IaidoTuning.span(local, profile.align_start, profile.align_end))
	var hold := creep * profile.hold_separation_m * 0.5
	var along := plane.line_direction(camera)
	var topple := plane.topple_axis(camera)

	for piece in pieces:
		var pivot: Node3D = piece["pivot"]
		if pivot == null or not is_instance_valid(pivot):
			continue
		var sign: float = piece["sign"]
		var upper: bool = piece["upper"]
		var head: float = release_at + float(piece["delay"])
		var travel: float = minf(maxf(t - head, 0.0), profile.fall_duration)
		var span := IaidoTuning.ease_out_cubic(
			clampf(travel / maxf(profile.fall_duration, 0.001), 0.0, 1.0))

		var offset := -plane.normal * (sign * hold)
		var tilt := 0.0
		var roll := 0.0

		if mode == IaidoExecutionProfile.TYPE_DISSOLVE:
			# The placeholder: no geometry to fall with, so the two halves stay put
			# and come apart along the cut. Legible, obviously provisional, and it
			# never blocks a single enemy from being shipped.
			offset += -plane.normal * (sign * 0.004 * span)
		elif mode == IaidoExecutionProfile.TYPE_SPECIAL:
			# One body. It loses its argument with gravity along the wound.
			tilt = span * deg_to_rad(profile.tip_angle_deg)
			offset += along * (span * profile.fall_spread * 0.5)
			offset += Vector3.DOWN * (span * span * body_extent * 0.75)
		else:
			# 失去支撑, not a cannon: small separation, small inherited velocity,
			# then gravity. And an UPPER piece and a LOWER piece do not do the same
			# thing — the top slides off and drops the height of the cut, the bottom
			# mostly stays planted and topples over. §K's asymmetry is this.
			var drop_limit := 0.16 if not upper else maxf(cut_anchor.y - actor.global_position.y + 0.12, 0.22)
			var drop := minf(0.5 * GRAVITY * profile.gravity_scale * travel * travel, drop_limit)
			var lateral := profile.fall_spread * (1.0 if upper else 0.55)
			offset += -plane.normal * (sign * profile.release_force * travel)
			offset += along * (sign * lateral * span)
			offset += Vector3.DOWN * drop
			tilt = span * deg_to_rad(profile.tip_angle_deg) * (0.75 if upper else 1.25) * float(piece["tip_sign"])
			roll = span * deg_to_rad(profile.spin_deg_per_s) * 0.05 * float(piece["tip_sign"])

		var rotation := base_basis
		if absf(tilt) > 0.00001:
			rotation = Basis(topple, tilt) * rotation
		if absf(roll) > 0.00001:
			rotation = Basis(plane.normal, roll) * rotation
		pivot.global_transform = Transform3D(rotation, cut_anchor + offset)

	# The dissolve is what takes the pieces off the frame, and it runs from the
	# wound outward — the same order as everything else in this ceremony, because
	# the wound is the cause of all of it.
	var out := 0.0
	if mode == IaidoExecutionProfile.TYPE_DISSOLVE:
		out = clampf((t - release_at) / maxf(profile.fall_duration, 0.001), 0.0, 1.0)
	else:
		out = clampf(
			(t - release_at - profile.fall_duration) / maxf(profile.fade_duration, 0.001),
			0.0, 1.0)
	for entry in look:
		var material: ShaderMaterial = entry["material"]
		# A body with no split has no piece coming apart, so its wound can only be
		# the ramp's origin — it holds its surface slightly longer.
		material.set_shader_parameter("dissolve", out if bool(entry["traced"]) else out * 0.82)

	# Authored halves are real geometry wearing the artist's own materials, which
	# means nothing can fade them: they leave by leaving. They are taken out at
	# the same instant the world's own collapse is closing over the frame, so the
	# removal lands inside the event it belongs to rather than beside it.
	if authored and t >= visual_end():
		for piece in pieces:
			var pivot: Node3D = piece["pivot"]
			if pivot != null and is_instance_valid(pivot):
				pivot.visible = false


func _apply_chips(t: float) -> void:
	for chip in chips:
		var mesh_node: MeshInstance3D = chip["mesh"]
		if mesh_node == null or not is_instance_valid(mesh_node):
			continue
		var life := minf(maxf(t - release_at, 0.0), profile.fall_duration * 0.8)
		mesh_node.visible = t >= release_at
		if not mesh_node.visible:
			continue
		var position: Vector3 = chip["at"] + chip["velocity"] * life
		position.y -= 0.5 * GRAVITY * profile.gravity_scale * life * life
		mesh_node.global_position = position
		mesh_node.global_rotation = (chip["spin"] as Vector3) * life


# =============================================================================
# READOUT — for the director, the debug panel and the tests
# =============================================================================

## How far the two halves are from each other, in metres, at this instant.
func separation() -> float:
	if not halved or pieces.size() < 2:
		return 0.0
	var a: Node3D = pieces[0]["pivot"]
	var b: Node3D = pieces[1]["pivot"]
	if a == null or b == null or not is_instance_valid(a) or not is_instance_valid(b):
		return 0.0
	# Measured ALONG THE CUT NORMAL, because that is the direction the world's own
	# two halves moved: the two numbers have to mean the same thing or the enemy
	# and the world cannot be said to have been cut by the same blade.
	return absf(plane.normal.dot(a.global_position - b.global_position))


func piece_position(piece_index: int) -> Vector3:
	if piece_index < 0 or piece_index >= pieces.size():
		return Vector3.ZERO
	var pivot: Node3D = pieces[piece_index]["pivot"]
	if pivot == null or not is_instance_valid(pivot):
		return Vector3.ZERO
	return pivot.global_position


func is_released(t: float) -> bool:
	return t >= release_at


func piece_count() -> int:
	return pieces.size()


## Read-and-clear. The director forwards these to AUDIO: the cut mark, the
## release and the fall are three separate cues and only one of them is
## percussive — §N, no single "anime slash death.wav" for every enemy.
func take_events() -> Array[StringName]:
	var out := events.duplicate()
	events.clear()
	return out


## §12 · THE FAIL-SAFE.
##
## Every way out of this node goes through here: the normal end of the ceremony, a
## player death, an abort, a scene change, a broken clock. Whatever happened, the
## body does not stay standing — a corpse the player can walk up to and find still
## upright is worse than no execution system at all.
func force_resolve() -> void:
	if not done:
		done = true
		events.append(&"resolved")
		resolved.emit(index)
	if actor != null and is_instance_valid(actor):
		actor.visible = false
		_set_actor_inert(actor)
	pieces.clear()
	look.clear()
	chips.clear()
	wounded = null
	halved = false
	built = false


## Belt and braces. The enemy is supposed to have made itself inert the moment it
## learned it was dead; this is here so that a future enemy that forgets still
## cannot attack the player from inside a ceremony.
static func _set_actor_inert(node: Node3D) -> void:
	var hitbox: Node = node.get("attack_hitbox")
	if hitbox != null and hitbox.has_method("set_active"):
		hitbox.call("set_active", false)
	var hurtbox := node.get_node_or_null("Hurtbox") as Area3D
	if hurtbox != null:
		hurtbox.monitorable = false
