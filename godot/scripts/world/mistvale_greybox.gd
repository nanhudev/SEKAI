@tool
extends Node3D
class_name MistvaleGreybox
## GATE 1 blockout for the Mistvale Vertical Slice Region.
##
## Every position here is lifted straight out of
## docs/LD-01-MISTVALE-REGION-MASTERPLAN.md. If the two disagree, the document
## wins and this file is wrong.
##
## Deliberately ugly. Its job is to answer: does the route network hold, can
## you climb it, do the landmarks read, are the combat spaces big enough.
## It is replaced wholesale at GATE 2/3 — nothing here is final art.


# --- Toggles: a blockout that cannot be decluttered cannot be reviewed -------
@export var show_town: bool = true
@export var show_landmarks: bool = true
@export var show_vistas: bool = true
@export var show_combat: bool = true
@export var show_narrative: bool = true
@export var show_routes: bool = true

## How far a blockout box sinks into the terrain so it never floats.
const SINK := 2.0


# =============================================================================
# Data — masterplan coordinates
# =============================================================================

# Town mass. x, z, width, depth, top height. Hand-placed, not generated: the
# masterplan §12 forbids a chessboard, and only hand placement gives the
# irregular corners, half-level platforms and offset buildings it asks for.
const TOWN := [
	# --- Lower Town: Z +40..+95 -------------------------------------------
	[-95.0, 78.0, 30.0, 22.0, 34.0],
	[-55.0, 80.0, 34.0, 20.0, 32.0],
	[-15.0, 82.0, 28.0, 20.0, 33.0],
	[28.0, 80.0, 30.0, 22.0, 34.0],
	[72.0, 78.0, 32.0, 20.0, 32.0],
	[-100.0, 48.0, 26.0, 24.0, 33.0],   # forge quarter NAR-06
	[-60.0, 52.0, 30.0, 22.0, 31.0],
	[-12.0, 50.0, 26.0, 20.0, 32.0],
	[26.0, 52.0, 28.0, 22.0, 33.0],
	[70.0, 50.0, 30.0, 22.0, 31.0],
	[100.0, 32.0, 26.0, 26.0, 33.0],    # Oren house NAR-03
	# --- Market ring: the square itself stays open ------------------------
	[-52.0, 8.0, 26.0, 22.0, 38.0],
	[-50.0, -14.0, 24.0, 20.0, 38.0],
	[52.0, 6.0, 28.0, 22.0, 38.0],
	[54.0, -16.0, 26.0, 20.0, 38.0],
	[-30.0, 26.0, 22.0, 18.0, 36.0],
	[30.0, 28.0, 22.0, 18.0, 36.0],
	# --- Guild Terrace wings -----------------------------------------------
	[-34.0, -44.0, 20.0, 18.0, 54.0],
	[34.0, -44.0, 20.0, 18.0, 54.0],
	# --- Upper Town: Z -70..-120 -------------------------------------------
	[-70.0, -78.0, 28.0, 20.0, 66.0],
	[-30.0, -76.0, 24.0, 18.0, 68.0],
	[16.0, -78.0, 26.0, 20.0, 67.0],
	[58.0, -80.0, 28.0, 22.0, 66.0],
	[-72.0, -108.0, 26.0, 20.0, 74.0],
	[-28.0, -110.0, 22.0, 18.0, 76.0],
	[20.0, -108.0, 26.0, 20.0, 74.0],
	[62.0, -106.0, 24.0, 20.0, 73.0],
	# --- North Gate flanks --------------------------------------------------
	[-30.0, -138.0, 18.0, 14.0, 86.0],
	[30.0, -138.0, 18.0, 14.0, 86.0],
]

# id, x, z, width, depth, top height, base height
const LANDMARKS := [
	["A_BellTower", -40.0, -95.0, 15.0, 15.0, 114.0, 72.0],
	["B_GuildTerrace", 0.0, -45.0, 34.0, 22.0, 64.0, 48.0],
	["C_NorthGate", 0.0, -135.0, 26.0, 8.0, 92.0, 78.0],
	["D_RidgeScar", -30.0, -410.0, 240.0, 5.0, 196.0, 160.0],
	["E_RuinsBeacon", 0.0, -360.0, 10.0, 10.0, 178.0, 152.0],
	["F_TempleCandidate", 55.0, -100.0, 22.0, 18.0, 84.0, 66.0],
]

## Landmarks that a hero kit now builds for real. Their yellow mass is skipped
## rather than switched off with show_landmarks, because the switch is global:
## turning it off to remove these three would also remove the Ridge Scar, the
## Beacon and the Temple Candidate, and those three are still the only thing
## giving the mountain side of the map its scale. See mistvale_landmarks.gd.
const HERO_REPLACED := ["A_BellTower", "B_GuildTerrace", "C_NorthGate"]

# id, x, z, base y, radius; masterplan §6
#
# V7 and V9 were MOVED by the GATE 1 sightline audit (see
# assets_source/review/ld01_06_vista_sightlines.png and ld01_08). The authored
# points could not see what §6 says they must show:
#   V7 (-55,-250) sat behind the -193 m bench: "Mistvale shrinking below me"
#       was blocked by 4.5 m of shoulder 41 m down the ray. Moved 25 m east
#       onto a spur off the switchback — the overlook is now a built feature
#       (KIT-03), not a lucky patch of ground.
#   V9 (-10,-355) is the flat centre of the C-08 pad. The pad's own blend
#       radius lifts the ground 37 m to its south, so the "whole valley" shot
#       was blocked by 6.7 m by the rim of the terrace it stands on. Moved
#       35 m south onto that rim: the ruins' viewing terrace, which is what
#       the ancient platform should have been cut as in the first place.
# V1 carries no marker height here — its framing only works from a ~10 m rock
# shelf above the forest floor (see V1_SHELF_RISE below and masterplan §6).
const VISTAS := [
	["V1_ForestBreak", 155.0, 258.0],
	["V2_BridgeCrest", 10.0, 118.0],
	["V3_FerryLanding", -95.0, 120.0],
	["V4_Market", 0.0, 0.0],
	["V5_GuildTerrace", 0.0, -40.0],
	["V6_BellTowerBalcony", -40.0, -95.0],
	["V7_FirstSwitchback", -37.0, -232.0],
	["V8_CliffLedge", 85.0, -262.0],
	["V9_RuinsForecourt", -19.0, -321.0],
]

## V1 is a rock shelf cut into the old road bank, not a clearing. The
## masterplan authored it at Y = 36 while the field only reaches 31.0 m — the
## 5 m gap was the design asking for a structure. 10.5 m gives the "river +
## distant rooftops" shot a real margin instead of a 0.2 m one.
const V1_SHELF_RISE := 10.5

# id, x, z, radius, system served; masterplan §12
const COMBAT := [
	["C01_CaravanAmbush", 120.0, 205.0, 15.0],
	# Moved from (30, 150): that spot sits inside the river carve, where the
	# audit measured 41.7 deg. (30, 175) is on the genuine south bank.
	["C02_RiverbankFlats", 30.0, 175.0, 15.0],
	["C03_MarketBrawl", 0.0, 0.0, 22.0],
	["C04_ForgeYard", -85.0, 60.0, 14.0],
	["C05_GuildStair", 0.0, -30.0, 12.0],
	["C06_CliffLedge", 85.0, -262.0, 13.0],
	["C07_ForestClearing", -62.0, -232.0, 20.0],
	["C08_RuinsForecourt", -10.0, -355.0, 32.0],
]

# id, x, z; masterplan §10 + §11
const NARRATIVE := [
	["NAR01_Caravan", 120.0, 205.0],
	["NAR02_BellTower", -40.0, -95.0],
	["NAR03_OrenYard", 95.0, 30.0],
	["NAR04_LiaFerry", -95.0, 138.0],
	["NAR05_FrostStorage", -22.0, -12.0],
	["NAR06_Forge", -85.0, 60.0],
	["MS10_BrokenSign", 140.0, 235.0],
	["MS18_BridgeCache", 12.0, 128.0],
	["MS19_OldMarker", -62.0, -228.0],
	["MS20_RuinShard", 72.0, -244.0],
	["MS21_ColdSpring", -58.0, -292.0],
	["MS22_Cairn", -10.0, -350.0],
]

# Main spine plus the two mountain lines; masterplan §7
const SPINE := [
	Vector3(200.0, 34.0, 320.0),
	Vector3(155.0, 36.0, 258.0),
	Vector3(120.0, 22.0, 205.0),
	Vector3(85.0, 20.0, 180.0),
	Vector3(10.0, 12.0, 122.0),
	Vector3(0.0, 34.0, 0.0),
	Vector3(0.0, 48.0, -45.0),
	Vector3(0.0, 78.0, -135.0),
]


# =============================================================================
# Build
# =============================================================================

func _ready() -> void:
	_build()


func _build() -> void:
	for child in get_children():
		child.queue_free()

	if show_town:
		var town := _layer("Town")
		for b in TOWN:
			_box(town, b[0], b[1], b[2], b[3], b[4], Color(0.62, 0.55, 0.44))

	if show_landmarks:
		var marks := _layer("Landmarks")
		for l in LANDMARKS:
			if HERO_REPLACED.has(l[0]):
				continue
			_box(marks, l[1], l[2], l[3], l[4], l[5], Color(0.95, 0.72, 0.28), l[6], l[0])

	if show_vistas:
		var v := _layer("Vistas")
		for e in VISTAS:
			# V1's framing only exists from the rock shelf. Put the marker where
			# the player would actually stand, or the walkthrough silently
			# re-tests the ground and finds the view broken again.
			var rise := V1_SHELF_RISE if e[0].begins_with("V1") else 0.0
			_pole(v, e[1], e[2], Color(0.35, 0.85, 0.95), e[0], rise)

	if show_combat:
		var c := _layer("Combat")
		for e in COMBAT:
			_disc(c, e[1], e[2], e[3], Color(0.92, 0.30, 0.28), e[0])

	if show_narrative:
		var n := _layer("Narrative")
		for e in NARRATIVE:
			_pole(n, e[1], e[2], Color(0.85, 0.35, 0.90), e[0])

	if show_routes:
		var r := _layer("Routes")
		# One sub-node per line. All three markers sets share this parent, so
		# without this the second and third set collide on wp_00..wp_07 and get
		# silently renamed — which is how the route markers stopped being
		# addressable by name at all.
		_route(_layer("Spine", r), SPINE, Color(0.40, 0.95, 0.55))
		_route(_layer("ForestTrail", r), MistvaleHeights.FOREST_TRAIL, Color(0.55, 0.78, 1.0))
		_route(_layer("CliffRoute", r), MistvaleHeights.CLIFF_ROUTE, Color(1.0, 0.78, 0.40))


func _layer(name_: String, parent: Node3D = null) -> Node3D:
	var n := Node3D.new()
	n.name = name_
	if parent == null:
		add_child(n)
	else:
		parent.add_child(n)
	return n


## A blockout mass. `top` is the roof height; `base` overrides the ground
## sample when a landmark deliberately starts on a podium (the bell tower
## footing, the ruins platform).
func _box(
	parent: Node3D,
	x: float,
	z: float,
	w: float,
	d: float,
	top: float,
	color: Color,
	base: float = NAN,
	name_: String = ""
) -> void:
	var ground := MistvaleHeights.height_at(x, z)
	var y0 := ground - SINK if is_nan(base) else base
	var h := maxf(top - y0, 1.0)

	var mesh := BoxMesh.new()
	mesh.size = Vector3(w, h, d)

	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _mat(color)
	mi.position = Vector3(x, y0 + h * 0.5, z)
	if name_ != "":
		mi.name = name_
	parent.add_child(mi)


func _pole(
	parent: Node3D, x: float, z: float, color: Color, name_: String,
	rise: float = 0.0
) -> void:
	var ground := MistvaleHeights.height_at(x, z) + rise
	var n := Node3D.new()
	n.name = name_
	n.position = Vector3(x, ground, z)

	var stem := CylinderMesh.new()
	stem.top_radius = 0.35
	stem.bottom_radius = 0.35
	stem.height = 9.0
	var smi := MeshInstance3D.new()
	smi.mesh = stem
	smi.material_override = _mat(color)
	smi.position = Vector3(0.0, 4.5, 0.0)
	n.add_child(smi)

	var head := SphereMesh.new()
	head.radius = 1.4
	head.height = 2.8
	var hmi := MeshInstance3D.new()
	hmi.mesh = head
	hmi.material_override = _mat(color)
	hmi.position = Vector3(0.0, 10.0, 0.0)
	n.add_child(hmi)

	parent.add_child(n)


func _disc(
	parent: Node3D, x: float, z: float, radius: float, color: Color, name_: String
) -> void:
	var ground := MistvaleHeights.height_at(x, z)
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = 0.4

	var mi := MeshInstance3D.new()
	mi.name = name_
	mi.mesh = mesh
	mi.material_override = _mat(color, 0.35)
	mi.position = Vector3(x, ground + 0.3, z)
	parent.add_child(mi)


## Waypoint markers sit ON the terrain. MistvaleHeights' route data is XZ only —
## see the header of FOREST_TRAIL for why the elevation is not authored.
##
## Two point conventions arrive here: SPINE is a list of Vector3 (X, Y, Z) while
## the mountain routes are Vector2 (X, Z). Reading a Vector3 into a typed Vector2
## does not fail loudly — it aborts the whole marker pass, so the spine silently
## vanished from the blockout while the two trails drew fine.
func _route(parent: Node3D, pts: Array, color: Color) -> void:
	var mesh := SphereMesh.new()
	mesh.radius = 1.1
	mesh.height = 2.2
	for i in pts.size():
		var e: Variant = pts[i]
		var px: float = e.x
		var pz: float = e.z if e is Vector3 else e.y
		var mi := MeshInstance3D.new()
		mi.name = "wp_%02d" % i
		mi.mesh = mesh
		mi.material_override = _mat(color)
		mi.position = Vector3(px, MistvaleHeights.height_at(px, pz) + 3.0, pz)
		parent.add_child(mi)


func _mat(color: Color, alpha: float = 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(color.r, color.g, color.b, alpha)
	m.roughness = 0.95
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m
