extends RefCounted
# Painted-stone helpers for the SEKAI Training Ground.
#
# ART-owned. Everything here is deterministic: no RNG, no time, no engine state.
# Two runs of the same code must produce byte-identical geometry, because the
# whole point of this scene is that a screenshot taken today can be compared with
# one taken after an asset lands.
#
# The training ground is deliberately NEUTRAL (brief §22-§23): stone, timber,
# posts, open sky, a clean floor. It is a place in the world - an old training
# court at the edge of the ruins - but it must never compete with the animation or
# the VFX it exists to show. No vegetation mass, no heavy fog.

# --- palette ------------------------------------------------------------------
# Cool dressed stone for floors, a warmer stone for structure, dark timber for
# racks and posts, and one saturated accent the player can actually see at range.
const STONE_COURT := Color(0.44, 0.44, 0.47)
const STONE_STRUCT := Color(0.52, 0.49, 0.44)
const STONE_DARK := Color(0.30, 0.30, 0.33)
const TIMBER := Color(0.29, 0.21, 0.15)
const ACCENT := Color(0.74, 0.47, 0.32)
const NEUTRAL_FLOOR := Color(0.62, 0.62, 0.63)

const ROUGH := 0.9


static func material(colour: Color, roughness: float = ROUGH, emissive: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = colour
	m.roughness = roughness
	m.metallic = 0.0
	if emissive > 0.0:
		m.emission_enabled = true
		m.emission = colour
		m.emission_energy_multiplier = emissive
	return m


# --- geometry -----------------------------------------------------------------
# One slab = an optional visible box + an optional matching collision box. Keeping
# them in one call is what stops the classic failure where a wall renders and
# cannot be walked into, or a floor is solid and invisible.
static func slab(
	parent: Node3D,
	owner_name: String,
	centre: Vector3,
	size: Vector3,
	mat: Material,
	collide: bool = true,
	bake_uv: bool = false
) -> MeshInstance3D:
	var body: Node3D
	if collide:
		var sb := StaticBody3D.new()
		body = sb
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		cs.shape = shape
		sb.add_child(cs)
	else:
		body = Node3D.new()
	body.name = owner_name
	body.position = centre
	parent.add_child(body)

	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	var box := BoxMesh.new()
	box.size = size
	# BoxMesh has no per-face UV control, but a triplanar-ish scale keeps a tiled
	# material from stretching into stripes on a long slab.
	if bake_uv:
		box.uv2_scale = Vector3(1.0, 1.0, 1.0)
	box.material = mat
	mi.mesh = box
	body.add_child(mi)
	return mi


# A cylinder post - handrails, posts, the anchor pin in the chain lab.
static func post(
	parent: Node3D,
	owner_name: String,
	base: Vector3,
	height: float,
	radius: float,
	mat: Material,
	collide: bool = false
) -> void:
	var body: Node3D
	if collide:
		var sb := StaticBody3D.new()
		body = sb
		var cs := CollisionShape3D.new()
		var shape := CylinderShape3D.new()
		shape.height = height
		shape.radius = radius
		cs.shape = shape
		sb.add_child(cs)
	else:
		body = Node3D.new()
	body.name = owner_name
	body.position = base + Vector3(0.0, height * 0.5, 0.0)
	parent.add_child(body)

	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	var cyl := CylinderMesh.new()
	cyl.height = height
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.radial_segments = 12
	cyl.material = mat
	mi.mesh = cyl
	body.add_child(mi)


# A flat area marker on the floor - used for the review stations and the zone
# labels. No collision, drawn just above the deck so it cannot z-fight.
static func flat_mark(parent: Node3D, owner_name: String, centre: Vector3, size: Vector2, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	mi.name = owner_name
	var quad := QuadMesh.new()
	quad.size = size
	quad.orientation = PlaneMesh.FACE_Y
	quad.material = mat
	mi.mesh = quad
	mi.position = centre
	parent.add_child(mi)


static func label(parent: Node3D, owner_name: String, text: String, at: Vector3, size: float = 0.5, colour: Color = Color(0.92, 0.92, 0.95)) -> Label3D:
	var l := Label3D.new()
	l.name = owner_name
	l.text = text
	l.font_size = 96
	l.pixel_size = size / 96.0
	l.position = at
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = false
	l.modulate = colour
	l.outline_size = 12
	l.outline_modulate = Color(0.05, 0.05, 0.07, 0.85)
	parent.add_child(l)
	return l
