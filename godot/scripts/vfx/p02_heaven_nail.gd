extends "res://scripts/vfx/vfx_prototype.gd"
#
# 02 · 天钉 / HEAVEN NAIL
#
# =============================================================================
# THE CLAIM
# =============================================================================
#
# Something 380 metres long comes down out of the sky and goes into the ground, and
# NOTHING EXPLODES. The brief is explicit about it and the whole clip hangs off
# that: a spike of this size arriving at any speed at all is a fireball in every
# film that has ever shown one, so the rule being broken is not "a big thing fell"
# — it is "a big thing fell and the world simply GAVE WAY, slowly, and stayed
# quiet". The only two things in the frame are a shaft and a circular depression.
#
# =============================================================================
# HOW THE DEPRESSION IS ACTUALLY MADE, AND WHY IT TOOK TWO PASSES
# =============================================================================
#
# PASS 1 was a `discard`: `vfx_prop.gdshader`'s `carve` removes the fragments
# inside a sphere, applied to every world material at once, so the ground under the
# nail was genuinely not there and a piece of the buildings next to it and a piece
# of the road went with it. That half works, and it is still here.
#
# What it does NOT do is look like a DEPRESSION. A hole with no geometry in it
# shows the background through the ground, which is a dark disc — and a dark disc
# with a glowing outline is a graphic, not a crater. The pass-1 still came back
# reading as "a black circle with a circle drawn round it", which is the single
# most useless thing this prototype could have been.
#
# So the crater is now a real object: a paraboloid FUNNEL built as an ArrayMesh and
# scaled from nothing to 23 m across, sunk into the terrain. The carve still
# removes the ground inside the rim, which is what lets you see the funnel instead
# of the terrain covering it. The rim gets a torus of earth piled at its edge,
# because ground that has been pushed down leaves a lip, and a lip is what tells
# the eye the material went DOWN rather than sideways.
#
# =============================================================================
# WHY THE NAIL IS NOT WHERE THE CAMERA EXPECTS IT
# =============================================================================
#
# A 380 m nail standing on the road is 25° of view from 4 m away and about 2° from
# 300 m away, and neither of those is a picture of a nail. So the first beat is
# spent looking UP its length (the one angle at which a shaft reads as a shaft),
# and the crater beat is spent from an external placement, because "the depression
# is circular" is a statement about a shape and a camera standing inside the
# depression cannot make it.

## The nail. Radius 7 m: wide enough to read as a mass at 300 m, narrow enough that
## its own tip is a point from underneath.
const NAIL_R := 7.0
const NAIL_LEN := 380.0
## Where it lands, and where its tip ends up — below ground, because a nail that
## stops exactly at ground level is a pillar.
const NAIL_AT := Vector3(2.4, 0.0, -24.0)
const NAIL_TIP_END := -7.0
## The depression. Radius 0 -> this, and how deep it goes at the centre.
const CRATER_R := 23.0
const CRATER_DEPTH := 7.6

const FALL_START := 0.90
const FALL_END := 4.30
const SETTLE_END := 7.20
const ORBIT_END := 9.40

var nail: MeshInstance3D
var nail_mat: ShaderMaterial
var funnel: MeshInstance3D
var lip: MeshInstance3D
var cracks: Array = []


func build() -> void:
	super()
	t_end = 11.0
	lab.set_sky("dusk")
	# The light is put BEHIND the nail so its descent is a silhouette rather than a
	# lit cylinder — a lit cylinder reads as a pillar, and a silhouette reads as
	# something arriving.
	lab.sun.light_energy = 0.85
	lab.sun.rotation_degrees = Vector3(-18.0, 152.0, 0.0)

	# THE NAIL. A cylinder and not a cone: a cone has a point, and a point is what
	# makes an impact look like a dart. This one goes in blunt.
	var cyl := CylinderMesh.new()
	cyl.top_radius = NAIL_R
	cyl.bottom_radius = NAIL_R * 1.10
	cyl.height = NAIL_LEN
	cyl.radial_segments = 24
	cyl.rings = 1
	nail = MeshInstance3D.new()
	nail.mesh = cyl
	# Metallic 0.22 and not more: in `gl_compatibility` a metallic surface with no
	# reflection probe to sample renders as a black silhouette, which is what the
	# nail is here anyway — but the shaft still needs one face that is not black or
	# its slow movement against the sky is invisible.
	nail_mat = world_mat(Color(0.140, 0.144, 0.158), 0.66, 0.22)
	nail.material_override = nail_mat
	nail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	stage.add_child(nail)

	# A thin bright seam down the shaft's near side, so the silhouette is not a
	# featureless black bar and its slow movement is visible against the sky.
	var seam: ShaderMaterial = lab.glow_mat(Color(0.80, 0.88, 1.00), 1.4, 0.0, 0.0)
	var seam_mesh := BoxMesh.new()
	seam_mesh.size = Vector3(0.30, NAIL_LEN * 0.94, 0.30)
	var seam_node := MeshInstance3D.new()
	seam_node.mesh = seam_mesh
	seam_node.material_override = seam
	seam_node.position = Vector3(0.0, 0.0, NAIL_R * 0.985)
	seam_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	nail.add_child(seam_node)

	# THE FUNNEL. Built at unit radius and unit depth so the node's scale IS the
	# crater's size, which means "the depression opens" is one `scale` assignment
	# and cannot drift from the rim it has to meet.
	funnel = MeshInstance3D.new()
	funnel.mesh = _funnel_mesh(1.0, 1.0, 48, 7)
	funnel.material_override = world_mat(Color(0.190, 0.183, 0.162), 0.95)
	funnel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	stage.add_child(funnel)

	# THE LIP. 1.6 m of earth piled at the rim, half-buried. A hole with a clean
	# edge is a hole; a hole with material heaped around it is ground that was
	# pushed. Scaled on all three axes together so the tube keeps its proportions
	# as the crater opens.
	lip = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = CRATER_R * 1.00
	torus.outer_radius = CRATER_R * 1.14
	torus.rings = 56
	torus.ring_segments = 8
	lip.mesh = torus
	lip.material_override = world_mat(Color(0.298, 0.290, 0.274), 1.0)
	lip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	stage.add_child(lip)

	# CRACKS. Eight hairlines radiating OUT FROM THE RIM — not across the crater,
	# which is what the second pass did and what made the overhead shot look like a
	# white asterisk drawn on a dark disc. They are cracks in the ground that is
	# still there, so they start at the rim's outside edge and run away from it, and
	# they are deliberately weak.
	for i in 8:
		var m: ShaderMaterial = lab.glow_mat(Color(0.60, 0.68, 0.84), 0.32, 0.0, 0.0)
		m.set_shader_parameter("alpha", 0.0)
		var box := BoxMesh.new()
		box.size = Vector3(0.16, 0.05, 1.0)
		var node := MeshInstance3D.new()
		node.mesh = box
		node.material_override = m
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		stage.add_child(node)
		cracks.append({"node": node, "mat": m, "ang": TAU * float(i) / 8.0 + 0.17})


## A paraboloid dish: unit radius at the top, `depth` deep at the centre, with the
## wall's own analytic normals. Explicit arrays and not a `SurfaceTool`, because a
## SurfaceTool-built mesh has already rendered as nothing in this project once.
func _funnel_mesh(radius: float, depth: float, segments: int, rings: int) -> ArrayMesh:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	for r in rings + 1:
		var u := float(r) / float(rings)
		var rad := radius * (1.0 - 0.90 * u)
		var y := -depth * pow(u, 1.55)
		# dr/du and dy/du of the profile above, so the normal is exact rather than
		# averaged out of the triangles.
		var dr := -radius * 0.90
		var dy := -depth * 1.55 * pow(maxf(u, 0.0001), 0.55)
		var nr := dy
		var ny := -dr
		var nl := sqrt(nr * nr + ny * ny)
		for s in segments + 1:
			var a := TAU * float(s) / float(segments)
			verts.append(Vector3(cos(a) * rad, y, sin(a) * rad))
			norms.append(Vector3(nr / nl * cos(a), ny / nl, nr / nl * sin(a)))
			uvs.append(Vector2(float(s) / float(segments), u))
	for r in rings:
		for s in segments:
			var a0 := r * (segments + 1) + s
			var a1 := a0 + 1
			var b0 := a0 + segments + 1
			var b1 := b0 + 1
			idx.append(a0)
			idx.append(b0)
			idx.append(a1)
			idx.append(a1)
			idx.append(b0)
			idx.append(b1)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func apply(t: float) -> void:
	# ---- the fall, and the only curve in the clip that is fast -----------------
	# The nail does not accelerate. Constant speed is the whole point: an
	# accelerating object reads as a weapon and a constant one reads as a verdict.
	var fall := span(t, FALL_START, FALL_END)
	var tip := lerpf(NAIL_LEN * 0.5 - 18.0, NAIL_TIP_END, fall)
	# ...and a small settle AFTER it stops, because something that stops dead looks
	# like a paused video.
	tip -= 1.5 * ease_out_quint(span(t, FALL_END, SETTLE_END))

	nail.position = Vector3(NAIL_AT.x, tip + NAIL_LEN * 0.5, NAIL_AT.z)
	lab.weapon_root.visible = t < 2.30

	# ---- the depression --------------------------------------------------------
	# It opens only once the tip is in the ground, and it opens SLOWLY: the radius
	# is the clip's clock and it is deliberately behind the nail, so the nail is
	# always waiting for the ground rather than the ground reacting to the nail.
	var bite := ease_in_out(span(t, FALL_END - 0.30, SETTLE_END + 0.60))
	var r := CRATER_R * bite
	var ground_y: float = lab.ground_height(NAIL_AT.x, NAIL_AT.z)

	lab.broadcast("carve_center", Vector3(NAIL_AT.x, ground_y - 5.0, NAIL_AT.z))
	lab.broadcast("carve_radius", r)
	lab.broadcast("carve_keep_inside", 0.0)
	lab.broadcast("carve_soft", 0.0)

	funnel.visible = r > 0.4
	funnel.position = Vector3(NAIL_AT.x, ground_y + 0.05, NAIL_AT.z)
	funnel.scale = Vector3(r, CRATER_DEPTH * bite, r)

	lip.visible = r > 0.4
	lip.position = Vector3(NAIL_AT.x, ground_y - CRATER_DEPTH * 0.10 * bite, NAIL_AT.z)
	lip.scale = Vector3.ONE * maxf(bite, 0.001)

	for c in cracks:
		var node: MeshInstance3D = c["node"]
		var ang: float = c["ang"]
		var reach := r * (0.55 + 0.75 * n1(float(cracks.find(c)) * 7.3, 0.0))
		# The hairline's INNER end sits on the rim, so the bar's centre is pushed
		# out by half its own length plus the rim radius.
		node.position = Vector3(NAIL_AT.x, ground_y + 0.06, NAIL_AT.z)
		node.position += Vector3(cos(ang), 0.0, sin(ang)) * (r * 1.04 + reach * 0.5)
		node.rotation_degrees = Vector3(0.0, -rad_to_deg(ang) + 90.0, 0.0)
		node.scale = Vector3(1.0, 1.0, maxf(reach, 0.01))
		(c["mat"] as ShaderMaterial).set_shader_parameter(
			"alpha", 0.55 * clampf(bite * 1.6 - 0.30, 0.0, 1.0))

	_camera(t, tip, r, ground_y)


func _camera(t: float, tip: float, r: float, ground_y: float) -> void:
	if t < 2.30:
		# FIRST PERSON, LOOKING UP THE SHAFT. The tip starts above the frame and
		# comes down into it, which is the only arrival a fixed camera can show.
		lab.review_off()
		var eye := Vector3(0.30, lab.ground_height(0.30, -2.0) + 1.72, -2.0)
		var aim := Vector3(NAIL_AT.x, maxf(tip + 52.0, 30.0), NAIL_AT.z)
		camera(eye, aim, 66.0, sin(t * 0.51) * 0.008)
		return

	if t < SETTLE_END - 2.40:
		# CLIMBING AS IT COMES DOWN, so the nail's real length enters the picture at
		# the same rate the tip enters the ground.
		lab.review_off()
		var u := ease_in_out(span(t, 2.30, SETTLE_END - 2.40))
		var eye2 := Vector3(0.30, 1.72, -2.0).lerp(Vector3(-30.0, 26.0, 22.0), u)
		var aim2 := Vector3(NAIL_AT.x, lerpf(150.0, 24.0, u), NAIL_AT.z)
		camera(eye2, aim2, lerpf(66.0, 54.0, u), 0.0)
		return

	if t < SETTLE_END:
		# THE CRATER BEAT. High enough that 23 m of depression is inside the frame
		# and off the road axis, because a circle seen along the road is an
		# ellipse.
		lab.review_off()
		# SETTLED BY 5.60 AND HELD UNTIL 7.20. The crater beat is the beat that says
		# "380 m of nail went into the ground and the ground took it", and it has to
		# be a still: V1 used the whole 2.4 s on a rallegro of small moves, so the
		# strongest composition in the clip was never actually presented.
		var v := ease_in_out(span(t, SETTLE_END - 2.40, 5.60))
		var eye3 := Vector3(-30.0, 26.0, 22.0).lerp(Vector3(-52.0, 44.0, 34.0), v)
		camera(eye3, Vector3(NAIL_AT.x, ground_y, NAIL_AT.z), lerpf(54.0, 46.0, v), 0.0)
		return

	if t < ORBIT_END:
		# A SLOW ORBIT THAT NEVER CROSSES THE NAIL: the shot is about the two things
		# the nail left behind, and a move that passes behind the shaft would put
		# the shaft between the lens and the crater for a third of it.
		lab.review_off()
		var w := ease_in_out(span(t, SETTLE_END, ORBIT_END))
		var ang := lerpf(-2.30, -1.15, w)
		var rad := lerpf(78.0, 62.0, w)
		var eye4 := Vector3(NAIL_AT.x + cos(ang) * rad, lerpf(44.0, 30.0, w), NAIL_AT.z + sin(ang) * rad)
		camera(eye4, Vector3(NAIL_AT.x, ground_y - 1.0, NAIL_AT.z), lerpf(46.0, 42.0, w), 0.0)
		return

	# BACK TO THE EYE, OUTSIDE THE RIM. The last thing the player sees is what they
	# are standing next to: the ground falls away two metres in front of them and
	# the shaft goes up out of the top of the frame. No explosion ever happened.
	#
	# 27.5 m from the centre is 4 m clear of the lip's outer edge, and it is the
	# smallest radius at which the eye is still on ground the carve did not take —
	# the sphere is centred 5 m under the surface, so at ground level its bite only
	# reaches 22.4 m.
	lab.review_off()
	var z := ease_in_out(span(t, ORBIT_END, t_end - 1.0))
	var rim := 27.5
	var ex := NAIL_AT.x + cos(0.32) * rim
	var ez := NAIL_AT.z + sin(0.32) * rim
	var eye5 := Vector3(ex, lab.ground_height(ex, ez) + 1.70, ez)
	# The aim starts on the shaft's near side and settles into the dish, so the
	# movement ends by looking at what the nail did rather than at the nail.
	camera(eye5, Vector3(NAIL_AT.x - 1.4, lerpf(ground_y + 1.4, ground_y - 2.6, z),
		NAIL_AT.z + 1.6), lerpf(60.0, 64.0, z), 0.0)


func phase_name(t: float) -> String:
	if t < FALL_START:
		return "起手 · 天上的东西在下降"
	if t < FALL_END:
		return "缓慢插入 %.0f%%" % (100.0 * span(t, FALL_START, FALL_END))
	if t < SETTLE_END:
		return "地陷 · 没有爆炸"
	if t < ORBIT_END:
		return "圆形凹陷 · 钉子留在那里"
	return "回到地面 · 世界安静"
