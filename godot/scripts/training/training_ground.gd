@tool
extends Node3D
# SEKAI TRAINING GROUND - the visual review hub.
#
# WHAT THIS IS
# Not a level. Not a bigger Combat Sandbox. It is the room where the ART line
# proves that an asset actually works inside the real runtime, and the room where
# anyone can open one scene and see the current state of SEKAI's art without
# booting four different test programs.
#
# WHY IT IS ORGANISED THIS WAY
# The one thing a review space must do is let you get somewhere else FAST, so the
# zones are laid out as a ring around a short central spine rather than a corridor.
# Every zone is reachable from spawn in under ten seconds of walking, and nothing
# is gated. The old 24 x 24 arena could not do this: the dummy stood on the exact
# line the player walks down, so a movement take turned into a shove. Movement and
# combat are physically separated here, and the chain gets its own lab because a
# 20 m weapon cannot be judged in a 24 m room.
#
# THE ROOM IS ALSO A HOST. The two stages the COMBAT line owns — `ChainLab` (zone D)
# and `PlaytestRange` (the three masses on D's deck) — are instanced rather than
# imitated, and this file's part of that bargain is to say where they stand and what
# they do not need to build. A stage that owns its own targets, its own recovery and
# its own geometry is a stage that is the same thing in a review room as it is in the
# game, which is the only version of a review that means anything.
#
# STYLE (brief §22-§23)
# An old training court at the edge of the ruins: dressed stone, timber posts,
# weapon racks, ruin fragments, open sky, clean floor. It is a place in the world,
# not a greybox warehouse. But it stays NEUTRAL - no vegetation mass, no heavy
# fog - because it exists to make animation and VFX readable, and anything
# decorative that competes with them is a defect.
#
# DETERMINISM
# No RNG anywhere. Every position is a literal. A screenshot taken today must be
# comparable with one taken after the next asset lands, and that is only possible
# if the room does not move.
#
# OWNERSHIP
# ART line. `MovementLane` (COMBAT line) is instanced as-is and is NOT rebuilt
# here - it owns its deck plane, kerbs and distance markings, and ART is
# explicitly permitted to replace its meshes later, not to duplicate it.

const TB := preload("res://scripts/training/training_build.gd")
const RACK := preload("res://scripts/training/training_weapon_rack.gd")
const PLAYTEST := preload("res://scripts/training/playtest_range.gd")
const CHAIN_LAB := preload("res://scripts/systems/chain_lab.gd")
const IAIDO_POST := preload("res://scripts/training/iaido_post.gd")

const ENV_DIR := "res://models/environment/mistvale/"
const DUMMY_SCENE := "res://scenes/enemies/TechnicalDummy.tscn"
const DRILL_DUMMY_SCENE := "res://scenes/training/DrillDummy.tscn"

# --- the room -----------------------------------------------------------------
# 112 x 78 m compound. Ground top surface is y = 0, which is also the origin every
# other zone measurement is taken from.
#
# THE WEST EDGE MOVED 10 m OUT when the chain bay was enlarged to hold the real lab.
# A 20 m weapon needs the room, and the room it needs is 32 x 30 — the bay is not
# decoration around the rig, it IS the rig's footprint plus the walk-around that makes
# its kerbs mean something.
#
# THE EAST EDGE MOVED 12 m OUT for the same reason, one weapon later. The east wing is
# three rooms deep now (the gallery, the ring, the hill) and a 12 m ring plus the walk
# around it does not fit in an 18 m strip: a ring you cannot circle is a ring nobody can
# photograph from anywhere except straight on.
const GROUND_MIN := Vector2(-56.0, -58.0)
const GROUND_MAX := Vector2(56.0, 20.0)
const PARAPET_H := 1.25
const PARAPET_T := 0.55

# --- zone rectangles (x0, z0, x1, z1) ----------------------------------------
# Published as constants because the UI, the review markers and any future
# teleport list all read them, and a second copy of these numbers is a bug.
const ZONE_SPAWN := Vector4(-9.0, -12.0, 9.0, 4.0)
const ZONE_COMBAT := Vector4(-14.0, -42.0, 14.0, -20.0)
const ZONE_CHAIN := Vector4(-50.0, -24.0, -18.0, 6.0)
const ZONE_VFX := Vector4(-44.0, -46.0, -20.0, -24.0)
const ZONE_SHOWCASE := Vector4(18.0, -54.0, 56.0, -24.0)
const ZONE_MOVE_EXT := Vector4(11.0, 4.0, 26.0, 13.0)
# THE EAST WING, south of the gallery: a ring to fight on, and a hill to fight over.
const ZONE_DUEL := Vector4(28.0, -22.0, 50.0, -4.0)
const ZONE_TERRAIN := Vector4(28.0, 0.0, 50.0, 18.0)
# THE LONG LANE. 62 x 8 m of nothing, which is the entire point: the chain is 20 m and
# the only way to judge a direction at 20 m is to have 55 m of ground it can be judged
# against. It runs SOUTH of MovementLane's 3.6 m deck (z 6.7 – 10.3) because a range
# that begins inside another stage's floor is a range with a wall in it.
const ZONE_RANGE := Vector4(-54.0, 11.0, 8.0, 19.0)
## Mirror weapon V0.1 lab — between combat court and duel wing.
const ZONE_MIRROR := Vector4(14.0, -22.0, 28.0, -6.0)
const ZONE_GATE_AT := Vector3(0.0, 0.0, -52.0)

# --- the kit's two numbers ----------------------------------------------------
# `ENV01_Stair_Straight_4` climbs 1.44 over a 4 m run (8 risers of 0.18) and
# `ENV01_Ramp_4x2` climbs 0.90 over 4 m. Those are the ONLY two lifts the kit can make,
# so every platform this file raises is a whole number of them. A deck 1.00 m up under a
# ramp whose top is 0.90 is a 10 cm lip: invisible in a still, felt in the hand, and the
# exact class of defect this room exists to avoid.
const LIFT_STAIR := 1.44
const LIFT_RAMP := 0.90

# --- H 擂台 ---------------------------------------------------------------------
const RING_CENTRE := Vector3(38.0, 0.0, -13.0)
const RING_SIZE := 12.0
const RING_DECK_H := LIFT_RAMP
const RING_KERB_H := 0.28
const RING_KERB_T := 0.30
const RING_POST_H := 2.30
const RING_POST_R := 0.16
const RING_RAILS: Array = [1.50, 2.00]   # rail heights, above the deck

# --- I 复杂地形 -----------------------------------------------------------------
## The hill's top surfaces in metres — 0.90 (one kit ramp), 1.44 (one kit stair), 2.34
## (a stair and a ramp). Derived from the kit's two lifts, so a caller that asks "what
## heights does the terrain have" gets the answer the geometry was built from rather
## than a second copy of it.
const TERRAIN_LEVELS: Array = [LIFT_RAMP, LIFT_STAIR, LIFT_STAIR + LIFT_RAMP]

# --- J 远距离大平地 -------------------------------------------------------------
const RANGE_LINE_X := 6.0
const RANGE_Z := 15.0
const RANGE_HALF_W := 4.0
## Distances from the firing line, in metres. The 55 m frame is the far end of the claim.
const RANGE_MARKS: Array = [5.0, 10.0, 20.0, 30.0, 45.0, 55.0]

# --- F the gallery ---------------------------------------------------------------
# The pedestal grid. `GALLERY_BAY_X` splits the zone: west of it is the assembled
# terrace, east of it is the hall of plinths. The pitch inside the hall is DERIVED from
# the hall's own size — the numbers that used to be here (6.0 m columns) put an 8 m
# terrace 2 m inside its neighbour, which is exactly the kind of thing a thumbnail
# cannot show you and a walk-through cannot miss.
#
# THE ZONE IS 30 m DEEP FOR THE SAME REASON. At 22 m the four rows took a 5.5 m pitch,
# and the deepest piece in the kit (`ENV01_RetainingWall_Corner`, a 4 x 4) brings a 4.6 m
# plinth with it — which leaves the aisle between two of its neighbours about a metre
# wide. One metre is a corridor, not a gallery, and the failure is invisible in a plan
# view because every plinth is still disjoint. 30 m gives a 7.5 m pitch and a 2.9 m
# aisle, which is what the word 展台 assumes.
const GALLERY_BAY_X := 33.0
const GALLERY_COLS := 3
const GALLERY_ROWS := 4
const PLINTH_H := 0.30
const PLINTH_MARGIN := 0.30
## The hall, in reading order: north row first, west to east. `ENV01_Terrace_8x8` is not
## here — it is the plaza the assembled bay is built on — and the empty string is the
## reserved slot, which is built as a plinth with a placard so that "this kit can grow"
## is a thing in the room rather than a thing in a document.
const GALLERY_SLOTS: Array = [
	"ENV01_Curb_4", "ENV01_Terrace_StepEdge_4", "ENV01_BridgeRail_4",
	"ENV01_CliffEdge_4", "ENV01_Stair_Landing_2x2", "ENV01_RetainingWall_4x1p5",
	"ENV01_Ramp_4x2", "ENV01_BridgeDeck_4", "ENV01_RetainingWall_Corner",
	"ENV01_Stair_Straight_4", "ENV01_Terrace_4x4", "",
]


const DECK_LANE := 0.9     # MovementLane's walking surface, so the extension meets it flush

## Test spots this room has that the arena's chain lab does not. The key rows above
## them describe the WEAPON, which is the same everywhere; these describe the ROOM,
## and a card that names an object standing in somebody else's room is a card that
## sends the player looking for it.
const FIXTURE_LEGEND_ROWS: Array = [
	["小假人 · 不死靶   →  B 球场", Color(0.82, 0.74, 0.52)],
	["居合桩 · 可切碎   →  B 球场", Color(0.82, 0.74, 0.52)],
]

var _root: Node3D = null
var _chain_rig: ChainLab = null
var _missing: PackedStringArray = PackedStringArray()


func _ready() -> void:
	_build()


func _build() -> void:
	if _root != null and is_instance_valid(_root):
		_root.queue_free()
	_root = Node3D.new()
	_root.name = "Compound"
	add_child(_root)

	_missing.clear()
	_ground()
	_parapet()
	_spine()
	_spawn_court()
	_combat_court()
	_mirror_test_court()
	_movement_extension()
	_chain_lab()
	_playtest_range()
	_vfx_stage()
	_long_range()
	_duel_ring()
	_terrain_park()
	_environment_showcase()
	_region_gate()
	_review_anchors()

	if _missing.size() > 0:
		push_warning("TrainingGround: %d ENV-01 mesh(es) missing - run the import first: %s"
			% [_missing.size(), ", ".join(_missing)])


# ------------------------------------------------------------------------------
# ENV-01 loading
# ------------------------------------------------------------------------------

func _env(asset: String) -> PackedScene:
	# Callers name a kit piece the way the kit is spoken about ("ENV01_Terrace_8x8"),
	# but ResourceLoader needs the file: without the .glb suffix every lookup failed
	# and the whole showcase zone reported 21 missing meshes while the twelve GLBs
	# sat in res://models/environment/mistvale/ with valid .import files. Resolve the
	# suffix here so a caller can never get it wrong.
	var path := ENV_DIR + asset
	if not path.ends_with(".glb"):
		path += ".glb"
	if not ResourceLoader.exists(path):
		_missing.append(asset)
		return null
	var packed: PackedScene = load(path)
	if packed == null:
		_missing.append(asset)
	return packed


## Places one ENV-01 piece. Returns the instance so a caller can rotate it.
## `rot_deg` is a whole multiple of 90 - the kit's contract is the 2 m grid, so a
## 45 degree kit piece would break the join the kit exists to provide.
##
## AND IT GIVES THE PIECE THE COLLISION THE EXPORT LEFT OUT. See `ENV01_BOXES`.
func _place_env(
	parent: Node3D,
	asset: String,
	at: Vector3,
	rot_y_deg: float = 0.0,
	collide: bool = true
) -> Node3D:
	var packed := _env(asset)
	if packed == null:
		return null
	var node: Node3D = packed.instantiate()
	node.name = asset.get_basename()
	node.position = at
	node.rotation.y = deg_to_rad(rot_y_deg)
	parent.add_child(node)
	if collide:
		_env_collide(parent, asset, at, rot_y_deg)
	return node


# --- ENV-01's real sizes, and the collision it does not ship with --------------
# Sizes are `docs/ASSET_MANIFEST.md`'s, which are measured on the GLB rather than
# transcribed from the brief's prose (the brief writes its table as X x Z x Y, so
# reading it as X x Y x Z turns a 0.16 m curb into a 0.30 m one).
#
# THE KIT HAS NO COLLISION AT ALL. A glTF node without the `-col` suffix imports as a
# bare MeshInstance3D, and none of the twelve have it — so `ENV01_Stair_Straight_4` has
# been a PICTURE of a stair since it was first placed, including the flight the
# movement lane walks up, and `ENV01_RetainingWall_4x1p5` could not retain a leaf. This
# table is therefore not a nicety: it is the only thing that turns the kit into
# geometry, and both the collider and the gallery's plinths are built from it.
const ENV01_BOXES: Dictionary = {
	"ENV01_Terrace_8x8": Vector3(8.000, 0.300, 8.000),
	"ENV01_Terrace_4x4": Vector3(4.000, 0.300, 4.000),
	"ENV01_Terrace_StepEdge_4": Vector3(4.000, 0.300, 0.600),
	"ENV01_Curb_4": Vector3(4.000, 0.160, 0.300),
	"ENV01_Ramp_4x2": Vector3(4.000, 0.900, 2.000),
	"ENV01_Stair_Straight_4": Vector3(4.000, 1.440, 2.000),
	"ENV01_Stair_Landing_2x2": Vector3(2.000, 0.300, 2.000),
	"ENV01_RetainingWall_4x1p5": Vector3(4.000, 1.500, 0.450),
	"ENV01_RetainingWall_Corner": Vector3(4.000, 1.500, 4.000),
	"ENV01_BridgeDeck_4": Vector3(4.000, 0.350, 2.000),
	"ENV01_BridgeRail_4": Vector3(4.000, 1.050, 0.150),
	"ENV01_CliffEdge_4": Vector3(4.000, 1.192, 0.999),
}
## Pieces whose origin is the BOTTOM OF THE RUN, centred across the width, rather than
## the centre of the footprint. Everything else in the kit stands on its own centre.
const ENV01_SLOPED: Array = ["ENV01_Stair_Straight_4", "ENV01_Ramp_4x2"]
## Collider thickness for the two sloped pieces, in metres. Thick enough that a
## fast-moving player cannot tunnel through it, thin enough that the far end of the
## ramp is not buried in the compound's floor.
const SLOPE_COL_THICK := 0.50


## Gives one placed ENV-01 piece a collider sized from `ENV01_BOXES`.
##
## A STAIR BECOMES A TILTED SLAB, NOT EIGHT STEPS. `move_and_slide` walks a 19.8 degree
## plane happily and has nothing to push against on a 0.18 m riser it can only touch
## with the very bottom of a 0.35 m capsule; the visible cost is half a riser of daylight
## under the player's feet and the walkable cost of the alternative is a staircase that
## is scenery. The slab is sunk by half its thickness along the slope normal so its TOP
## face lies on the surface the mesh draws rather than hovering above it.
func _env_collide(parent: Node3D, asset: String, at: Vector3, rot_y_deg: float) -> void:
	var size: Vector3 = ENV01_BOXES.get(asset, Vector3.ZERO)
	if size == Vector3.ZERO:
		return
	var body := StaticBody3D.new()
	body.name = asset.get_basename() + "_Col"
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	if asset in ENV01_SLOPED:
		var theta := atan2(size.y, size.x)
		var normal := Vector3(-sin(theta), cos(theta), 0.0)
		shape.size = Vector3(sqrt(size.x * size.x + size.y * size.y), SLOPE_COL_THICK, size.z)
		cs.rotation.z = theta
		cs.position = Vector3(size.x * 0.5, size.y * 0.5, 0.0) - normal * (SLOPE_COL_THICK * 0.5)
	else:
		shape.size = size
		cs.position = Vector3(0.0, size.y * 0.5, 0.0)
	cs.shape = shape
	body.add_child(cs)
	body.position = at
	body.rotation.y = deg_to_rad(rot_y_deg)
	parent.add_child(body)



# ------------------------------------------------------------------------------
# Ground, edge, spine
# ------------------------------------------------------------------------------

func _ground() -> void:
	var size := Vector3(GROUND_MAX.x - GROUND_MIN.x, 1.0, GROUND_MAX.y - GROUND_MIN.y)
	var centre := Vector3(
		(GROUND_MIN.x + GROUND_MAX.x) * 0.5,
		-0.5,
		(GROUND_MIN.y + GROUND_MAX.y) * 0.5
	)
	TB.slab(_root, "Ground", centre, size, TB.material(TB.STONE_COURT))

	# A darker band under the gate so the north end reads as a threshold rather
	# than as the floor simply stopping.
	TB.flat_mark(_root, "GateApproach", Vector3(ZONE_GATE_AT.x, 0.012, -47.0),
		Vector2(14.0, 10.0), TB.material(TB.STONE_DARK))


func _parapet() -> void:
	# The arena had no kill plane and no edge. Ninety metres of open floor with a
	# 5 m drop at the end is a review tool that deletes the reviewer, so the
	# compound is closed. Low enough to see over, high enough to stop a sprint.
	var m := TB.material(TB.STONE_STRUCT)
	var w := GROUND_MAX.x - GROUND_MIN.x
	var d := GROUND_MAX.y - GROUND_MIN.y
	var cx := (GROUND_MIN.x + GROUND_MAX.x) * 0.5
	var cz := (GROUND_MIN.y + GROUND_MAX.y) * 0.5
	var y := PARAPET_H * 0.5

	TB.slab(_root, "Parapet_N", Vector3(cx, y, GROUND_MIN.y), Vector3(w, PARAPET_H, PARAPET_T), m)
	TB.slab(_root, "Parapet_S", Vector3(cx, y, GROUND_MAX.y), Vector3(w, PARAPET_H, PARAPET_T), m)
	TB.slab(_root, "Parapet_W", Vector3(GROUND_MIN.x, y, cz), Vector3(PARAPET_T, PARAPET_H, d), m)
	TB.slab(_root, "Parapet_E", Vector3(GROUND_MAX.x, y, cz), Vector3(PARAPET_T, PARAPET_H, d), m)


func _spine() -> void:
	# One 6 m paved route from the south court to the gate. Everything else hangs
	# off it, which is what makes "run anywhere in ten seconds" true.
	var m := TB.material(TB.STONE_STRUCT)
	TB.flat_mark(_root, "Spine_S", Vector3(0.0, 0.014, -3.0), Vector2(6.0, 20.0), m)
	TB.flat_mark(_root, "Spine_N", Vector3(0.0, 0.014, -31.0), Vector2(6.0, 22.0), m)


# ------------------------------------------------------------------------------
# A - SPAWN / EQUIPMENT COURT  (brief §2A)
# ------------------------------------------------------------------------------

func _spawn_court() -> void:
	var rect := ZONE_SPAWN
	var court := _court_pad("SpawnCourt", rect, TB.material(TB.STONE_STRUCT))

	# Racks stand on a plinth along the north edge, facing the player as they
	# spawn, so the first thing in frame is the equipment. The plinth sits INSIDE
	# the court (z0 + 1.6), not behind it - a rack outside the court is a rack the
	# player has to leave the room to reach.
	var plinth_z := rect.y + 1.6
	TB.slab(court, "RackPlinth", Vector3(0.0, 0.21, plinth_z - 0.5),
		Vector3(13.0, 0.42, 1.2), TB.material(TB.STONE_COURT))

	# Diegetic switching (brief §4). The player walks up and takes the weapon.
	# Both racks call the same equip path, so adding a third weapon later is a
	# row in this list and nothing else.
	_rack(court, &"sword", "剑 · SWORD", Vector3(-4.6, 0.42, plinth_z - 0.5), 0.0)
	_rack(court, &"phantom_chain", "虚链 · PHANTOM", Vector3(0.0, 0.42, plinth_z - 0.5), 0.0)
	_rack(court, &"chain", "缚星链 · CHAIN", Vector3(4.6, 0.42, plinth_z - 0.5), 0.0)

	TB.label(_root, "ZoneA", "A  SPAWN / EQUIPMENT", Vector3(rect.x + 1.0, 2.6, rect.w - 1.0), 0.55)


func _rack(parent: Node3D, weapon: StringName, text: String, at: Vector3, rot_y: float) -> void:
	var r: Node3D = RACK.new()
	r.name = "Rack_" + String(weapon)
	r.set("weapon_id", weapon)
	r.set("display_text", text)
	r.position = at
	r.rotation.y = deg_to_rad(rot_y)
	parent.add_child(r)


# ------------------------------------------------------------------------------
# B - COMBAT COURT  (brief §2B)
# ------------------------------------------------------------------------------

func _combat_court() -> void:
	var rect := ZONE_COMBAT
	var court := _court_pad("CombatCourt", rect, TB.material(TB.STONE_COURT))

	# Two dummy stations, deliberately OFF the spine. The brief is explicit that
	# a dummy must not stand on the movement line; the spine runs down x = 0, so
	# the stations sit at x = +/- 7 with a clear 14 m gap between them.
	_dummy_station(court, "Dummy_W", Vector3(-7.0, 0.0, rect.y + 8.0))
	_dummy_station(court, "Dummy_E", Vector3(7.0, 0.0, rect.y + 8.0))

	# Training posts: the thing that makes a court read as a court rather than a
	# car park, and the thing that gives a chain sweep something honest to hit.
	var post_mat := TB.material(TB.TIMBER)
	var post_tops := TB.material(TB.ACCENT)
	for i in range(3):
		var x := -4.0 + float(i) * 4.0
		var z := rect.w - 4.0
		TB.post(court, "Post_%d" % i, Vector3(x, 0.30, z), 1.9, 0.14, post_mat, true)
		TB.post(court, "PostCap_%d" % i, Vector3(x, 2.20, z), 0.22, 0.19, post_tops, false)

	# THE TWO PRACTICE FIXTURES, on the court's far edge facing the way the player
	# arrives so that walking in is walking into something to hit.
	#
	# 11 m APART, and the number is a measurement rather than a spacing. The signature's
	# collector takes up to three bodies inside a 45 degree cone, so a pair close
	# together would be cut by one slash — which is a fine demo and a useless test:
	# "I cut the post" is only a clean claim when the room agrees about which body the
	# blade was pointed at.
	_drill_station(court, "DrillDummy", Vector3(-5.5, 0.0, rect.y + 3.5))
	_iaido_station(court, "IaidoPost", Vector3(5.5, 0.0, rect.y + 3.5))

	TB.label(_root, "ZoneB", "B  COMBAT COURT", Vector3(rect.x + 1.0, 2.6, rect.w - 1.0), 0.55)


## MIRROR V0.1 TEST COURT — position / angle / travel fixtures only.
func _mirror_test_court() -> void:
	var rect := ZONE_MIRROR
	var court := _court_pad("MirrorCourt", rect, TB.material(TB.STONE_COURT))
	TB.label(_root, "ZoneMirror", "MIRROR TEST · 3 / RMB / Q", Vector3(rect.x + 1.0, 2.6, rect.w - 1.0), 0.45)

	# TEST A — static dummy for A1 echo (side cut).
	_dummy_station(court, "Mirror_A", Vector3(18.0, 0.0, -18.0))
	TB.label(_root, "Mirror_A_Label", "A · A1 ECHO", Vector3(18.0, 2.1, -18.0), 0.28, TB.ACCENT)

	# TEST B — two dummies at ~90° for A2 refraction.
	_dummy_station(court, "Mirror_B1", Vector3(22.0, 0.0, -14.0))
	_dummy_station(court, "Mirror_B2", Vector3(26.0, 0.0, -18.0))
	TB.label(_root, "Mirror_B_Label", "B · A2 REFRACT 90°", Vector3(24.0, 2.1, -16.0), 0.28, TB.ACCENT)

	# TEST C — moving body for travel behind.
	_mirror_patrol(court, "Mirror_C", Vector3(20.0, 0.1, -10.0))
	TB.label(_root, "Mirror_C_Label", "C · TRAVEL BEHIND", Vector3(20.0, 2.1, -10.0), 0.28, TB.ACCENT)

	# TEST D — wall / pillar for placement + safe exit.
	var wall_mat := TB.material(TB.STONE_DARK)
	TB.slab(court, "Mirror_Wall", Vector3(16.5, 1.4, -12.0), Vector3(0.55, 2.8, 4.0), wall_mat)
	TB.post(court, "Mirror_Pillar", Vector3(25.0, 0.0, -11.0), 2.6, 0.28, wall_mat, true)
	TB.label(_root, "Mirror_D_Label", "D · PLACE / SAFE EXIT", Vector3(16.5, 3.2, -12.0), 0.28, TB.ACCENT)


func _mirror_patrol(parent: Node3D, node_name: String, at: Vector3) -> void:
	_fixture_pad(parent, node_name, at)
	if not ResourceLoader.exists(DUMMY_SCENE):
		_missing.append(DUMMY_SCENE)
		return
	var packed: PackedScene = load(DUMMY_SCENE)
	if packed == null:
		_missing.append(DUMMY_SCENE)
		return
	var dummy: Node3D = packed.instantiate()
	dummy.name = node_name + "_Dummy"
	dummy.position = at
	parent.add_child(dummy)
	var driver := Node.new()
	driver.name = node_name + "_Patrol"
	driver.set_script(load("res://scripts/training/mirror_patrol_driver.gd"))
	driver.set("target", dummy)
	driver.set("center", at)
	driver.set("radius", 2.4)
	parent.add_child(driver)


## THE SMALL ONE THAT CANNOT BE KILLED. It absorbs a session instead of ending a combo:
## a target that dies in two hits turns a combo test into a sequence of dummies.
func _drill_station(parent: Node3D, node_name: String, at: Vector3) -> void:
	_fixture_pad(parent, node_name, at)
	if not ResourceLoader.exists(DRILL_DUMMY_SCENE):
		_missing.append(DRILL_DUMMY_SCENE)
		return
	var packed: PackedScene = load(DRILL_DUMMY_SCENE)
	if packed == null:
		_missing.append(DRILL_DUMMY_SCENE)
		return
	var body: Node3D = packed.instantiate()
	body.name = node_name
	# A hand's width above the floor, the convention every station in this room uses.
	body.position = at + Vector3(0.0, 0.10, 0.0)
	parent.add_child(body)
	TB.label(_root, node_name + "_Label", "小假人 · 不死靶", at + Vector3(0.0, 1.92, 0.0),
		0.30, TB.ACCENT)


## THE ONE THE SIGNATURE CUTS IN TWO. See `iaido_post.gd` — it is the only object in
## the project that a 聚合斩 can actually take apart and that puts itself back.
func _iaido_station(parent: Node3D, node_name: String, at: Vector3) -> void:
	_fixture_pad(parent, node_name, at)
	var post: Node3D = IAIDO_POST.new()
	post.name = node_name
	post.position = at
	parent.add_child(post)
	TB.label(_root, node_name + "_Label", "居合桩 · 可切碎 / 自复", at + Vector3(0.0, 2.70, 0.0),
		0.30, TB.ACCENT)


func _fixture_pad(parent: Node3D, node_name: String, at: Vector3) -> void:
	TB.flat_mark(parent, node_name + "_Pad", Vector3(at.x, 0.016, at.z), Vector2(3.0, 3.0),
		TB.material(TB.STONE_DARK))


func _dummy_station(parent: Node3D, node_name: String, at: Vector3) -> void:
	# A 3 m pad under each dummy so the player can tell at a glance where the
	# target lives without the target being on the walking line.
	TB.flat_mark(parent, node_name + "_Pad", Vector3(at.x, 0.016, at.z),
		Vector2(3.0, 3.0), TB.material(TB.STONE_DARK))
	var marker := Marker3D.new()
	marker.name = node_name
	marker.position = at
	parent.add_child(marker)

	# The dummy is instanced HERE rather than in the .tscn so that its position
	# and the station pad cannot drift apart. The old arena's real bug was not
	# that the dummy existed, it was that its position and the walking line were
	# maintained in two places. One of them is enough.
	if ResourceLoader.exists(DUMMY_SCENE):
		var packed: PackedScene = load(DUMMY_SCENE)
		if packed != null:
			var dummy: Node3D = packed.instantiate()
			dummy.name = node_name + "_Dummy"
			dummy.position = at + Vector3(0.0, 0.25, 0.0)
			parent.add_child(dummy)
	else:
		_missing.append(DUMMY_SCENE)


# ------------------------------------------------------------------------------
# C - MOVEMENT LANE  (brief §2C)
# ------------------------------------------------------------------------------
# MovementLane itself is instanced from the scene file, not rebuilt here - it is
# COMBAT's stage and its header asks ART to replace meshes, not to fork it. This
# function adds only the parts the brief asks for that it does not already have:
# stairs, a second landing, and a turn.

func _movement_extension() -> void:
	var rect := ZONE_MOVE_EXT
	var m := TB.material(TB.STONE_COURT)
	var kerb := TB.material(TB.STONE_DARK)

	var z_mid := (rect.y + rect.w) * 0.5   # the lane's centreline, z = 8.5

	# Landing that picks the player up off MovementLane's 0.9 m deck.
	TB.slab(_root, "Move_Landing0", Vector3((rect.x + rect.x + 4.0) * 0.5, DECK_LANE * 0.5, z_mid),
		Vector3(4.0, DECK_LANE, 4.0), m)

	# Stairs, using the real ENV-01 kit rather than a primitive: this is the first
	# place in the project where a stair the ART line owns is walked on inside the
	# runtime. ENV01_Stair_Straight_4 is one 2 m run rising 1.44 m.
	var step_y := DECK_LANE
	_place_env(_root, "ENV01_Stair_Straight_4", Vector3(rect.x + 5.0, step_y, z_mid), 0.0)
	step_y += 1.44

	# Landing between the two flights - the brief asks for a landing and a turn,
	# and a landing is also where a movement animation actually gets judged,
	# because it is the only place the player changes state with no obstacle.
	TB.slab(_root, "Move_Landing1", Vector3(rect.x + 8.0, step_y - 0.15 + 0.15 * 0.5, z_mid),
		Vector3(2.0, 0.30, 4.0), m)
	TB.slab(_root, "Move_Landing1_Kerb", Vector3(rect.x + 8.0, step_y + 0.10, z_mid - 2.06),
		Vector3(2.0, 0.42, 0.12), kerb)

	# Turn: the route bends 90 degrees to the north. A straight 20 m lane tells
	# you nothing about how a turn feels, and 风步 in particular is a turning
	# art - the move is a loop, and a loop needs a corner in it.
	var turn := _place_env(_root, "ENV01_Stair_Straight_4", Vector3(rect.x + 10.0, step_y, z_mid - 1.0), 90.0)
	if turn != null:
		turn.position = Vector3(rect.x + 10.0, step_y, z_mid - 1.0)
	step_y += 1.44

	TB.slab(_root, "Move_Upper", Vector3(rect.x + 10.0, step_y - 0.15 + 0.15 * 0.5, z_mid - 4.5),
		Vector3(4.0, 0.30, 5.0), m)

	TB.label(_root, "ZoneC", "C  MOVEMENT LANE", Vector3(rect.x + 0.5, 2.4, rect.w - 0.5), 0.55)


# ------------------------------------------------------------------------------
# D - CHAIN LAB  (brief §2D)
# ------------------------------------------------------------------------------
# The largest zone in the compound, because it is the only one whose size is set by a
# weapon: 缚星链 is 20 m and is judged by whether its direction reads at 15 m, so the
# bay's real deliverable is NEGATIVE space and the props in it exist to be hit, not to
# fill the room.
#
# IT CONTAINS COMBAT'S OWN CHAIN LAB. The bay is not a re-drawing of the lab (which is
# what it used to be, and what the REQ filed as 「两个链实验室不该同时存在」): it is a
# HOST for it. The rig arrives whole — deck markings, three weights or none, the anchor
# post, the overhead gantry, the crates, and the wall at the far end that a throw is
# supposed to end on — and this function's whole job is to say where it stands and which
# parts of it the compound already provides.

func _chain_lab() -> void:
	var rect := ZONE_CHAIN
	var centre := Vector3((rect.x + rect.z) * 0.5, 0.0, (rect.y + rect.w) * 0.5)

	# THE BAY IS PAINTED, NOT LAID. The rig's own deck tops out at y = 0 and so does the
	# compound's ground, so a third slab at 0.15 would be a coplanar duplicate of two
	# floors at once — z-fighting across a 28 m deck, which is the one surface every
	# review of this room is a review OF. The collision is the compound's; this is a
	# differently coloured rectangle of floor, which is all the bay ever needed to be to
	# read as a different room.
	TB.flat_mark(_root, "ChainBayFloor", centre + Vector3(0.0, 0.008, 0.0),
		Vector2(CHAIN_LAB.DECK_SIZE.x, CHAIN_LAB.DECK_SIZE.z), TB.material(TB.STONE_DARK))

	# THE ONE CHAIN LAB, AND IT IS COMBAT'S.
	#
	# There used to be two. This bay carried a hand-written copy of the lab's contents —
	# three masses, an anchor post, three crates, a pillar, a wall — while `ChainLab` (the
	# rig every chain test, every chain take and every tuning number actually measures)
	# stood in the arena, on coordinates nothing else in this room shared. The copy is
	# gone and the rig is HERE, at this bay's own centre, which is what makes the room's
	# answer about the chain the same answer the game gives.
	#
	# The four switches are what "hosted" means: the bay supplies the FLOOR, this stage
	# supplies everything standing on it. See `chain_lab.build_deck` / `build_targets`.
	var lab: ChainLab = CHAIN_LAB.new()
	lab.name = "ChainRig"
	lab.origin = centre - CHAIN_LAB.CENTER
	lab.build_deck = false
	lab.build_bridge = false
	lab.build_targets = false
	lab.legend_extra_rows = FIXTURE_LEGEND_ROWS
	_root.add_child(lab)
	_chain_rig = lab

	TB.label(_root, "ZoneD", "D  CHAIN LAB · 缚星链",
		Vector3(rect.x + 1.4, 2.6, rect.w - 1.0), 0.55)


# ------------------------------------------------------------------------------
# D2 - PLAYTEST RANGE  (COMBAT-owned; the instrument lives in its own file)
# ------------------------------------------------------------------------------
# Deliberately NOT built here. This file is the room's LAYOUT and the ART line owns
# it; the three weights at 3 / 6 / 9 m, the training health and the RESET are the
# COMBAT line's playtest instrument. Keeping them in their own script means either
# line can change its half without editing the other's file - the same bargain
# `region_gate.gd` already struck, and the reason the diff here is three lines.

func _playtest_range() -> void:
	var range_node: Node3D = PLAYTEST.new()
	range_node.name = "PlaytestRange"
	# THE RANGE STANDS AT THE LAB'S DOOR. Handed over rather than typed again: the
	# number belongs to the rig, and a second copy of it here is a copy that starts
	# lying the day somebody moves the bay. Laid flat (y = 0) because the door's own
	# height is an eye position, and this is where a person's feet go.
	var entry := PLAYTEST.STAND
	if _chain_rig != null:
		entry = _chain_rig.entry_position()
	range_node.set("stand", Vector3(entry.x, 0.0, entry.z))
	# The lab's own wall is 20 m beyond the last mass and it is the wall the weapon is
	# tuned against; a 3 m plate at 12 m would stand in front of it and chop the bay's
	# clean centre in half.
	range_node.set("build_backstop", false)
	_root.add_child(range_node)


# ------------------------------------------------------------------------------
# E - VFX STAGE  (brief §2E)
# ------------------------------------------------------------------------------
# The one zone whose job is to be photographed. Flat neutral deck, a clean
# backdrop, and a fixed capture anchor so two shots of the same effect are
# actually comparable instead of merely similar.

func _vfx_stage() -> void:
	var rect := ZONE_VFX
	var cx := (rect.x + rect.z) * 0.5
	var cz := (rect.y + rect.w) * 0.5

	# Neutral floor: deliberately NOT the stone tint. A tinted floor lies about
	# the colour of a shader, which is the single most common way a VFX review
	# goes wrong.
	TB.slab(_root, "VFX_Deck", Vector3(cx, -0.06, cz), Vector3(18.0, 0.24, 16.0),
		TB.material(TB.NEUTRAL_FLOOR, 0.75))

	# Backdrop: mid grey, no detail, tall enough to frame a 4 m effect.
	TB.slab(_root, "VFX_Backdrop", Vector3(cx, 5.0, rect.y - 0.4), Vector3(18.0, 10.0, 0.4),
		TB.material(Color(0.52, 0.53, 0.55), 1.0))

	# A ground grid in a darker neutral. Cutting a Voronoi shard network over a
	# featureless floor makes it impossible to tell whether the world split or the
	# camera moved; the grid is the reference that answers it.
	var grid := TB.material(Color(0.46, 0.47, 0.49), 1.0)
	for i in range(-3, 4):
		var off := float(i) * 3.0
		TB.flat_mark(_root, "VFX_GridX_%d" % i, Vector3(cx + off, 0.062, cz), Vector2(0.06, 16.0), grid)
		TB.flat_mark(_root, "VFX_GridZ_%d" % i, Vector3(cx, 0.062, cz + off), Vector2(18.0, 0.06), grid)

	var anchor := Marker3D.new()
	anchor.name = "CaptureAnchor_VFX"
	anchor.position = Vector3(cx, 1.70, cz + 11.0)
	_look_at(anchor, Vector3(cx, 2.2, cz))
	_root.add_child(anchor)

	TB.label(_root, "ZoneE", "E  VFX STAGE", Vector3(rect.x + 1.0, 2.4, rect.w + 0.6), 0.55)


func _look_at(node: Node3D, target: Vector3) -> void:
	# Look_at needs the node in the tree to be meaningful, and a Marker3D is
	# never transformed by its parent's scale here, so a direct basis build is
	# both cheaper and free of the top-level / zero-length failure modes.
	var origin := node.position
	var dir := (target - origin)
	if dir.length_squared() < 0.000001:
		return
	dir = dir.normalized()
	var right := Vector3.UP.cross(dir)
	if right.length_squared() < 0.000001:
		right = Vector3.RIGHT
	right = right.normalized()
	var up := dir.cross(right).normalized()
	node.basis = Basis(right, up, -dir)


# ------------------------------------------------------------------------------
# J - 远距离大平地 LONG RANGE
# ------------------------------------------------------------------------------
# 62 x 8 m of unbroken floor. Nothing is built in it on purpose: the deliverable is the
# absence, and the only thing laid on it is the ruler you read the absence against.
#
# It runs east-west along the compound's south edge, which is the one long axis this
# room did not already have — the chain bay's long axis is north-south — and it stops
# at a 2.6 m backstop rather than at the parapet, because a cleared line that ends at a
# 1.25 m wall is a cleared line that reads as "the ground ran out".

func _long_range() -> void:
	var rect := ZONE_RANGE
	var host := Node3D.new()
	host.name = "LongRange"
	_root.add_child(host)

	var kerb := TB.material(TB.STONE_DARK)
	var half := RANGE_HALF_W

	# The lane's edges, so an 8 m wide strip of the same stone as everything else still
	# reads as a strip. 0.16 m: the ENV-01 curb's own height, so the ruler and the kit
	# agree about what "a kerb" is.
	var length := rect.z - rect.x
	var mid_x := (rect.x + rect.z) * 0.5
	TB.slab(host, "RangeKerb_N", Vector3(mid_x, 0.08, RANGE_Z - half - 0.15),
		Vector3(length, 0.16, 0.30), kerb, false)
	TB.slab(host, "RangeKerb_S", Vector3(mid_x, 0.08, RANGE_Z + half + 0.15),
		Vector3(length, 0.16, 0.30), kerb, false)

	# The marks. Each one is a transverse bar the full width of the lane plus the number
	# that gives it meaning, so "45 m" is a thing you can stand on the wrong side of
	# rather than a thing you have to remember.
	for d in RANGE_MARKS:
		var x: float = RANGE_LINE_X - float(d)
		TB.flat_mark(host, "RangeMark_%d" % int(d), Vector3(x, 0.012, RANGE_Z),
			Vector2(0.30, half * 2.0 - 0.4), kerb)
		TB.label(host, "RangeMarkLabel_%d" % int(d), "%d m" % int(d),
			Vector3(x, 0.60, RANGE_Z - half + 0.55), 0.30, TB.ACCENT)

	# The firing line, in the accent colour: the one mark that is a position rather than
	# a distance.
	TB.flat_mark(host, "RangeFiringLine", Vector3(RANGE_LINE_X, 0.014, RANGE_Z),
		Vector2(0.40, half * 2.0 - 0.4), TB.material(TB.ACCENT))
	for sign_z in [-1.0, 1.0]:
		var pz: float = RANGE_Z + sign_z * (half - 0.10)
		TB.post(host, "RangePost_%d" % int(sign_z), Vector3(RANGE_LINE_X, 0.0, pz),
			1.70, 0.09, TB.material(TB.TIMBER), true)

	# The backstop, and the frame 55 m out. The frame is what gives the eye a datum at
	# the far end of an empty lane; without it "can I read a direction at 20 m" is a
	# question asked against fog.
	TB.slab(host, "RangeBackstop", Vector3(rect.x + 1.0, 1.30, RANGE_Z),
		Vector3(1.2, 2.60, half * 2.0 + 1.0), TB.material(TB.STONE_STRUCT))

	var far_x: float = RANGE_LINE_X - float(RANGE_MARKS[RANGE_MARKS.size() - 1])
	var frame := TB.material(TB.TIMBER)
	for sign_z in [-1.0, 1.0]:
		TB.post(host, "RangeFramePost_%d" % int(sign_z),
			Vector3(far_x, 0.0, RANGE_Z + sign_z * 1.8), 2.20, 0.10, frame, true)
	TB.slab(host, "RangeFrameBar", Vector3(far_x, 2.14, RANGE_Z),
		Vector3(0.18, 0.18, 4.0), frame, false)
	TB.slab(host, "RangeFramePlate", Vector3(far_x, 1.30, RANGE_Z),
		Vector3(0.18, 1.60, 2.60), TB.material(TB.STONE_COURT))

	TB.label(_root, "ZoneJ", "J  远距离大平地 · LONG RANGE",
		Vector3(RANGE_LINE_X + 0.4, 3.1, RANGE_Z - half - 0.4), 0.60)
	TB.label(_root, "RangeStartLabel", "起点 · FIRING LINE",
		Vector3(RANGE_LINE_X, 2.30, RANGE_Z), 0.34, TB.ACCENT)


# ------------------------------------------------------------------------------
# H - 擂台 DUEL RING
# ------------------------------------------------------------------------------
# A RAISED SQUARE, raised by exactly `LIFT_RAMP`. That number is not decoration:
# `ENV01_Ramp_4x2` is the only kit piece that climbs 0.90, so a deck 0.90 high is a deck
# a real kit ramp can serve. Make it 1.00 and the ramp's top ends 10 cm under the edge —
# a lip invisible in a still and felt in the hand within one step.
#
# The kerb is 0.28: low enough to cross, high enough to read as a ring rather than a
# podium. It is CUT on the west side where the ramp arrives, because a ring with no
# doorway is a plinth, and the doorway is the reason this is a place to fight rather
# than a place to be photographed.

func _duel_ring() -> void:
	var rect := ZONE_DUEL
	var c := RING_CENTRE
	var host := Node3D.new()
	host.name = "DuelRing"
	_root.add_child(host)

	var half := RING_SIZE * 0.5
	var deck := RING_DECK_H
	var stone := TB.material(TB.STONE_COURT)
	var kerb_m := TB.material(TB.STONE_STRUCT)
	var timber := TB.material(TB.TIMBER)
	var kerb_y := deck + RING_KERB_H * 0.5

	# One slab, so the fighting surface and the thing you stand on cannot disagree.
	TB.slab(host, "RingDeck", Vector3(c.x, deck * 0.5, c.z),
		Vector3(RING_SIZE, deck, RING_SIZE), stone)

	# The mat, a darker inlay 0.4 m inside the kerb: the line that tells you where the
	# ring stops, plus a centre mark and two start marks, i.e. the smallest set of lines
	# that turns a bare square into a ring.
	TB.flat_mark(host, "RingMat", Vector3(c.x, deck + 0.006, c.z),
		Vector2(RING_SIZE - 0.8, RING_SIZE - 0.8), TB.material(TB.STONE_DARK))
	TB.flat_mark(host, "RingCentre", Vector3(c.x, deck + 0.010, c.z),
		Vector2(2.6, 2.6), TB.material(TB.ACCENT))
	for sign_x in [-1.0, 1.0]:
		TB.flat_mark(host, "RingStart_%d" % int(sign_x),
			Vector3(c.x + sign_x * 3.2, deck + 0.010, c.z),
			Vector2(1.4, 1.4), TB.material(TB.STONE_STRUCT))

	# THE RAMP, and therefore the doorway. `ENV01_Ramp_4x2`'s origin is the bottom of its
	# run and it climbs toward +X, so the ramp's top lands on the deck's west face and
	# its own top surface IS the deck's surface. Nothing is derived twice.
	var ramp_x := c.x - half - 4.0
	_place_env(host, "ENV01_Ramp_4x2", Vector3(ramp_x, 0.0, c.z), 0.0)

	var gate_z := 2.0   # the ramp's own width; the kerb opens exactly this wide
	var west_len := (half * 2.0 - gate_z) * 0.5
	var west_span := half - west_len * 0.5
	TB.slab(host, "RingKerb_N", Vector3(c.x, kerb_y, c.z - half),
		Vector3(RING_SIZE + RING_KERB_T * 2.0, RING_KERB_H, RING_KERB_T), kerb_m, false)
	TB.slab(host, "RingKerb_S", Vector3(c.x, kerb_y, c.z + half),
		Vector3(RING_SIZE + RING_KERB_T * 2.0, RING_KERB_H, RING_KERB_T), kerb_m, false)
	TB.slab(host, "RingKerb_E", Vector3(c.x + half, kerb_y, c.z),
		Vector3(RING_KERB_T, RING_KERB_H, RING_SIZE), kerb_m, false)
	# West side, in two pieces: the gap between them is the gate the ramp comes through.
	TB.slab(host, "RingKerb_W_North", Vector3(c.x - half, kerb_y, c.z - west_span),
		Vector3(RING_KERB_T, RING_KERB_H, west_len), kerb_m, false)
	TB.slab(host, "RingKerb_W_South", Vector3(c.x - half, kerb_y, c.z + west_span),
		Vector3(RING_KERB_T, RING_KERB_H, west_len), kerb_m, false)

	# Four posts and three sides of rail. The west side is left unrailed because the only
	# way in is there — and because a rail across your own doorway is the first thing a
	# reviewer walks into.
	var inset := half - 0.5
	for corner in [Vector2(-1.0, -1.0), Vector2(1.0, -1.0),
			Vector2(-1.0, 1.0), Vector2(1.0, 1.0)]:
		TB.post(host, "RingPost_%s_%s" % [_sign(corner.x), _sign(corner.y)],
			Vector3(c.x + corner.x * inset, deck, c.z + corner.y * inset),
			RING_POST_H, RING_POST_R, timber, true)
	var rail_span := RING_SIZE - 1.0
	for h in RING_RAILS:
		var ry: float = deck + float(h)
		TB.slab(host, "RingRail_N_%d" % int(float(h) * 100.0),
			Vector3(c.x, ry, c.z - inset), Vector3(rail_span, 0.10, 0.10), timber, false)
		TB.slab(host, "RingRail_S_%d" % int(float(h) * 100.0),
			Vector3(c.x, ry, c.z + inset), Vector3(rail_span, 0.10, 0.10), timber, false)
		TB.slab(host, "RingRail_E_%d" % int(float(h) * 100.0),
			Vector3(c.x + inset, ry, c.z), Vector3(0.10, 0.10, rail_span), timber, false)

	# THE ZONE'S NAME GOES ON THE FAR SIDE FROM THE CAMERA THAT REVIEWS IT. Every other
	# zone in the compound puts its label on the south-west corner, because every other
	# zone is reviewed from the south edge looking north, so the label sits behind the
	# reviewer's shoulder and out of frame. This room is the exception twice over: its
	# only doorway is the west face, so its camera stands ON the west edge, and a label
	# at `rect.x + 1.2` lands 4 m away at the edge of the lens — a wall of text where the
	# room should be. North-east instead: 25 m out, legible, and behind the ring.
	TB.label(_root, "ZoneH", "H  擂台 · DUEL RING",
		Vector3(rect.z - 1.4, 3.0, rect.y + 1.0), 0.60)
	TB.label(host, "RingPlate", "擂台  DUEL RING",
		Vector3(c.x, deck + RING_POST_H + 0.45, c.z - half - 0.8), 0.42, TB.ACCENT)


# ------------------------------------------------------------------------------
# I - 复杂地形 TERRAIN PARK
# ------------------------------------------------------------------------------
# FOUR LEVELS, AND EVERY RISE IS A KIT RISE. Ground, 0.90 (kit ramp), 1.44 (kit stair),
# 2.34 (stair + ramp). Nothing here is a height somebody picked: a hill whose steps are
# 1.20 m is a hill you have to jump up, and the point of a terrain test is to walk it.
#
# IT IS BUILT UP, NEVER CUT DOWN. The compound is one 112 x 78 m slab and there is no
# runtime mesh boolean in this project (see ART_REQUESTS); a pit would have to be a hole
# in the floor every other zone stands on. So the "valley" is the ground and everything
# else is stacked on it, which is also why the low terrace exists at all — without it
# there is no second floor to look down from.

func _terrain_park() -> void:
	var rect := ZONE_TERRAIN
	var host := Node3D.new()
	host.name = "TerrainPark"
	_root.add_child(host)

	var low := TERRAIN_LEVELS[0]      # 0.90
	var mid := TERRAIN_LEVELS[1]      # 1.44
	var high := TERRAIN_LEVELS[2]     # 2.34
	var slab_m := TB.material(TB.STONE_COURT)

	# --- the middle terrace: the hill's body, and the deck the bridge lands on ----
	TB.slab(host, "TerraceMain", Vector3(38.0, mid * 0.5, 8.0), Vector3(8.0, mid, 8.0), slab_m)
	# --- the high shelf on top of it --------------------------------------------
	TB.slab(host, "TerraceHigh", Vector3(40.0, mid + (high - mid) * 0.5, 8.0),
		Vector3(4.0, high - mid, 4.0), slab_m)
	# --- an equal-height tower 4 m east, so the high shelf is a level and not a peak -
	TB.slab(host, "PlateauEast", Vector3(44.0, high * 0.5, 8.0), Vector3(4.0, high, 4.0), slab_m)
	# --- the far pillar: the other end of the bridge, and deliberately thin enough
	#     that the bridge is the only sane way across --------------------------------
	TB.slab(host, "PillarWest", Vector3(30.0, mid * 0.5, 8.0), Vector3(4.0, mid, 4.0), slab_m)
	# --- the low terrace, south, one kit ramp up ---------------------------------
	TB.slab(host, "TerraceLow", Vector3(37.0, low * 0.5, 15.5), Vector3(8.0, low, 5.0), slab_m)
	# --- cover: three blocks at three different heights, which is what makes a hill
	#     tactically different from a ramp ----------------------------------------
	TB.slab(host, "Cover_A", Vector3(45.0, 0.225, 15.0), Vector3(2.0, 0.45, 2.0), slab_m)
	TB.slab(host, "Cover_B", Vector3(29.0, 0.60, 13.0), Vector3(2.0, 1.20, 2.0), slab_m)

	# --- the ways up, all three of them the kit's own numbers --------------------
	_place_env(host, "ENV01_Stair_Straight_4", Vector3(30.0, 0.0, 5.0), 0.0)
	_place_env(host, "ENV01_Ramp_4x2", Vector3(38.0, mid, 5.0), 0.0)
	_place_env(host, "ENV01_Ramp_4x2", Vector3(29.0, 0.0, 15.5), 0.0)

	# --- the bridge: 4 m of deck between the pillar and the hill, at the middle
	#     terrace's height, with a 1.44 m gap you can walk under -------------------
	_place_env(host, "ENV01_BridgeDeck_4", Vector3(32.0, mid, 8.0), 0.0)
	_place_env(host, "ENV01_BridgeRail_4", Vector3(32.0, mid, 6.925), 0.0)
	_place_env(host, "ENV01_BridgeRail_4", Vector3(32.0, mid, 9.075), 0.0)

	# --- dressing that is also structure: the broken rock edge along the hill's south
	#     face, a bench lip on top, kerbs along the low terrace -------------------
	_place_env(host, "ENV01_CliffEdge_4", Vector3(36.0, 0.0, 12.0), 0.0)
	_place_env(host, "ENV01_CliffEdge_4", Vector3(40.0, 0.0, 12.0), 0.0)
	_place_env(host, "ENV01_Terrace_StepEdge_4", Vector3(38.0, mid, 12.0), 0.0)
	_place_env(host, "ENV01_Curb_4", Vector3(35.0, low, 13.0), 0.0)
	_place_env(host, "ENV01_Curb_4", Vector3(39.0, low, 13.0), 0.0)

	# Same reason as zone H: the hill is reviewed from the south-west, so the label goes
	# to the north-east corner. A 0.60 m title 4 m from the lens is not a title.
	TB.label(_root, "ZoneI", "I  复杂地形 · TERRAIN PARK",
		Vector3(rect.z - 1.4, 3.4, rect.y + 1.0), 0.60)


# ------------------------------------------------------------------------------
# F - ENVIRONMENT GALLERY  (brief §2F / §18)
# ------------------------------------------------------------------------------
# TWO ROOMS IN ONE ZONE, and both are needed.
#
#   THE WEST BAY   the kit ASSEMBLED — a plaza, a stair and an upper terrace that
#                  actually meet. This answers "do these pieces join", which no amount
#                  of looking at them one at a time can answer.
#   THE HALL       the kit one piece per PLINTH, with its name under it. This answers
#                  "is this piece correct", which the assembly cannot.
#
# THE PLINTHS ARE THE POINT (the ask: 摆放像展台). A kit piece lying on the floor of a
# courtyard is a crate; the same piece on a 0.30 m base with a label is an exhibit, and
# the label is what stops the gallery being a room you have to already know.
#
# AND THE PITCH IS DERIVED, NOT TYPED. The previous layout used a 6.0 m column pitch
# for a set whose widest member is 8.0 m, so `ENV01_Terrace_8x8` overlapped its
# neighbour by 2 m and nobody could see it in a thumbnail. The cell below is computed
# from the hall's own width and depth, and the plinth from the piece's own footprint —
# so the layout cannot drift from the objects it is laying out. `training_ground_boot`
# asserts the plinths are pairwise disjoint, which is the same claim said as a number.

func _environment_showcase() -> void:
	var rect := ZONE_SHOWCASE
	var host := Node3D.new()
	host.name = "Gallery"
	_root.add_child(host)

	# THE FLOOR IS PAINTED, NOT LAID. A 0.15 m court pad would be a step at every edge of
	# a room whose whole subject is measured heights; a tinted rectangle says "different
	# room" and costs the geometry nothing.
	TB.flat_mark(host, "GalleryFloor", Vector3((rect.x + rect.z) * 0.5, 0.010,
		(rect.y + rect.w) * 0.5), Vector2(rect.z - rect.x - 1.0, rect.w - rect.y - 1.0),
		TB.material(TB.STONE_DARK))

	# The backdrop, so the hall's north row has a wall to be read against and the room
	# does not simply open onto the field behind it.
	TB.slab(host, "GalleryBackdrop", Vector3((rect.x + rect.z) * 0.5, 1.30, rect.y - 0.4),
		Vector3(rect.z - rect.x, 2.60, 0.50), TB.material(TB.STONE_STRUCT))
	TB.slab(host, "GalleryBackdropCap", Vector3((rect.x + rect.z) * 0.5, 2.66, rect.y - 0.4),
		Vector3(rect.z - rect.x + 0.4, 0.12, 0.62), TB.material(TB.STONE_COURT))

	_gallery_assembly(host)
	_gallery_hall(host)

	# ON THE FAR EASTERN EDGE, HAVING BEEN ON THE NORTH-WEST CORNER — where it was behind
	# the backdrop. The backdrop stands 0.4 m north of the zone, so `rect.y - 1.4` put the
	# room's own name on the wrong side of the room's own wall: legible from the field
	# outside, invisible from every aisle inside.
	TB.label(_root, "ZoneF", "F  ENVIRONMENT GALLERY · ENV-01 展廊",
		Vector3(rect.z - 2.0, 3.2, rect.w - 1.0), 0.55)


## The kit actually put together, at the west end. Heights are the kit's own lifts:
## a 0.30 plaza, a 1.44 stair off it, and the upper terrace on the stair's top.
func _gallery_assembly(host: Node3D) -> void:
	var cx := 25.0
	var plaza_z := -30.0
	var upper_z := -40.0

	_place_env(host, "ENV01_Terrace_8x8", Vector3(cx, 0.0, plaza_z), 0.0)
	# The stair's origin is the BOTTOM of its run and it climbs +X; rotated +90 about Y
	# the run points at -Z, which is where the upper terrace is. This is the join the
	# old assembly got wrong: it placed an unrotated stair between two terraces offset
	# along Z, i.e. a staircase running sideways past both of them.
	_place_env(host, "ENV01_Stair_Straight_4", Vector3(cx, 0.30, plaza_z - 4.0), 90.0)
	_place_env(host, "ENV01_Terrace_4x4", Vector3(cx, 0.30 + LIFT_STAIR, upper_z), 0.0)
	_place_env(host, "ENV01_Curb_4", Vector3(cx, 0.30, plaza_z + 4.0), 0.0)
	_place_env(host, "ENV01_Terrace_StepEdge_4", Vector3(cx - 2.0, 0.30, plaza_z), 90.0)
	# A pier under the upper terrace, so a cantilever is not mistaken for a joint. It
	# stops short of the stair's own footprint so the two do not interpenetrate.
	TB.slab(host, "AssemblyPier", Vector3(cx, (0.30 + LIFT_STAIR) * 0.5, upper_z),
		Vector3(4.4, 0.30 + LIFT_STAIR, 4.0), TB.material(TB.STONE_STRUCT))

	TB.label(_root, "GalleryAssembly", "F2  ENV-01 · ASSEMBLED  组装验证",
		Vector3(cx, 4.4, upper_z + 2.0), 0.45)


## The hall: one plinth per piece, pitch derived from the hall's own size.
func _gallery_hall(host: Node3D) -> void:
	var rect := ZONE_SHOWCASE
	var x0 := GALLERY_BAY_X
	var x1 := rect.z
	var z0 := rect.y
	var z1 := rect.w
	var pitch_x := (x1 - x0) / float(GALLERY_COLS)
	var pitch_z := (z1 - z0) / float(GALLERY_ROWS)

	var plinth_m := TB.material(TB.STONE_COURT)
	var reserved_m := TB.material(TB.STONE_STRUCT)
	var placed := 0

	# The pieces live under their own node so that "what is standing on a plinth" is a
	# question the scene tree can answer. It could not before: the exhibits shared the
	# Gallery node with the assembled bay, so `ENV01_Curb_4` existed twice and the second
	# one was auto-renamed. A check that has to guess which node it is looking at is a
	# check that will pass on the wrong one.
	var exhibits := Node3D.new()
	exhibits.name = "Exhibits"
	host.add_child(exhibits)

	for i in range(GALLERY_SLOTS.size()):
		var row := i / GALLERY_COLS
		var col := i % GALLERY_COLS
		if row >= GALLERY_ROWS:
			break
		var cx: float = x0 + (float(col) + 0.5) * pitch_x
		var cz: float = z0 + (float(row) + 0.5) * pitch_z
		var asset: String = GALLERY_SLOTS[i]

		# The reserved slot is built rather than skipped: an empty plinth with a label
		# is the same statement as zone A's empty weapon stand, and it costs one box.
		var size: Vector3 = ENV01_BOXES.get(asset, Vector3(2.0, 0.30, 2.0))
		var plinth := Vector3(size.x + PLINTH_MARGIN * 2.0, PLINTH_H,
			size.z + PLINTH_MARGIN * 2.0)
		TB.slab(host, "Plinth_%d" % i, Vector3(cx, PLINTH_H * 0.5, cz), plinth,
			plinth_m if asset != "" else reserved_m)

		if asset == "":
			TB.label(host, "Exhibit_%d" % i, "预留 · RESERVED",
				Vector3(cx, PLINTH_H + 0.55, cz + _label_side(row) * 0.6), 0.30,
				TB.ACCENT)
			continue

		# THE KIT'S TWO CLIMBING PIECES ORIGIN AT THE FOOT OF THE RUN — see
		# `ENV01_SLOPED` — so at the plinth's centre they climb straight off it.
		# `ENV01_Stair_Straight_4` is 4 m long and its origin is the bottom step, so
		# placed at the centre it runs 2 m past the plinth and 2 m of pedestal holds
		# nothing: the stair ends up standing in the aisle that the aisle exists to
		# provide. The plinth is centred on the PIECE, so the piece is drawn back by half
		# its own run. Its size already came from the piece, so the plinth needs no
		# change — and the boot test now measures the piece rather than the pedestal,
		# which is the check that would have caught this the first time.
		var at := Vector3(cx, PLINTH_H, cz)
		if asset in ENV01_SLOPED:
			at.x -= size.x * 0.5
		_place_env(exhibits, asset, at, 0.0)
		placed += 1
		TB.label(host, "Exhibit_%d" % i, asset.trim_prefix("ENV01_"),
			Vector3(cx, 0.55, cz + _label_side(row) * (plinth.z * 0.5 + 0.30)), 0.26,
			TB.ACCENT)

	# At the far north-east corner rather than the middle of the room, so that the title of
	# the hall is not painted across the central aisle the aisle review shot looks down.
	TB.label(_root, "GalleryHall", "F1  ENV-01 · 一件一座（%d 件）" % placed,
		Vector3(x1 - 3.0, 3.4, z0 + 2.5), 0.45)


## Which side of its plinth a placard goes on. Rows 0 and 1 are north of the central
## aisle and face into it; rows 2 and 3 are south of it and do the same. A placard
## behind its own exhibit is a placard nobody reads.
func _label_side(row: int) -> float:
	return 1.0 if row < GALLERY_ROWS / 2 else -1.0


## "p" / "n" for a sign. A name assembled from two corners as "%d%d" gives "1-1", which
## reads as either (1, -1) or (11) — the kind of ambiguity that costs an afternoon.
static func _sign(v: float) -> String:
	return "p" if v > 0.0 else "n"



# ------------------------------------------------------------------------------
# G - REGION GATE  (brief §2G / §20)
# ------------------------------------------------------------------------------

func _region_gate() -> void:
	var gate: Node3D = preload("res://scripts/training/region_gate.gd").new()
	gate.name = "RegionGate"
	gate.position = ZONE_GATE_AT
	_root.add_child(gate)


# ------------------------------------------------------------------------------
# Review anchors (brief §21 / §30)
# ------------------------------------------------------------------------------
# Fixed eye positions, one per zone. The brief's third acceptance view is "actual
# game context", and a context shot from a camera you chose yesterday is worth
# nothing. These are the cameras.

func _review_anchors() -> void:
	var host := Node3D.new()
	host.name = "ReviewAnchors"
	_root.add_child(host)

	_anchor(host, "Review_Spawn", Vector3(0.0, 1.7, ZONE_SPAWN.w + 3.0), Vector3(0.0, 1.4, ZONE_SPAWN.y + 1.0))
	_anchor(host, "Review_Combat", Vector3(0.0, 1.7, ZONE_COMBAT.w + 4.0), Vector3(0.0, 1.4, ZONE_COMBAT.y + 6.0))
	_anchor(host, "Review_Fixtures", Vector3(0.0, 1.8, ZONE_COMBAT.y + 11.5), Vector3(0.0, 1.3, ZONE_COMBAT.y + 3.5))
	_anchor(host, "Review_Movement", Vector3(0.0, 1.7, 12.0), Vector3(11.0, 1.4, 8.5))
	# INSIDE THE BAY, BEHIND THE LAB'S DOOR, LOOKING DOWN THE DECK — which is where the
	# player entering it stands, so the shot answers "what does walking in look like".
	_anchor(host, "Review_Chain", Vector3(-34.0, 1.7, 5.0), Vector3(-34.0, 1.4, -14.0))
	_anchor(host, "Review_VFX", Vector3(-32.0, 1.7, -12.0), Vector3(-32.0, 2.4, -35.0))
	_anchor(host, "Review_Showcase", Vector3(30.0, 1.8, -21.0), Vector3(44.0, 1.2, -38.0))
	# STANDING AT THE RING'S ONLY DOORWAY: the ramp is the west face, so this is the one
	# camera position from which "there is a way up and the deck is above you" is true.
	_anchor(host, "Review_Duel", Vector3(25.0, 2.4, -13.0), Vector3(38.0, 1.6, -13.0))
	# LOW, AND THAT IS THE WHOLE POINT. A camera at 3.8 m over a hill whose levels are 0.90,
	# 1.44 and 2.34 m looks almost straight down and sees four pale tops — which is the one
	# view in which a five-step staircase and a flat shelf are the same picture. From 2.8 m
	# the risers are between the eye and the far floors, and "these are storeys" is a thing
	# the frame says rather than a thing the caption claims.
	_anchor(host, "Review_Terrain", Vector3(23.0, 2.8, 19.5), Vector3(37.0, 1.25, 8.0))
	# AT THE FIRING LINE, FACING DOWN THE 62 m. A range photographed from the side is a
	# photograph of a kerb.
	_anchor(host, "Review_Range", Vector3(RANGE_LINE_X, 1.7, RANGE_Z), Vector3(-52.0, 1.2, RANGE_Z))
	_anchor(host, "Review_Gate", Vector3(0.0, 1.7, -43.0), Vector3(0.0, 1.6, -52.0))


func _anchor(parent: Node3D, node_name: String, eye: Vector3, look: Vector3) -> void:
	var a := Marker3D.new()
	a.name = node_name
	a.position = eye
	_look_at(a, look)
	parent.add_child(a)


# ------------------------------------------------------------------------------

func _court_pad(node_name: String, rect: Vector4, mat: Material) -> Node3D:
	var host := Node3D.new()
	host.name = node_name
	_root.add_child(host)

	var w := rect.z - rect.x
	var d := rect.w - rect.y
	TB.slab(host, "Pad", Vector3((rect.x + rect.z) * 0.5, 0.075, (rect.y + rect.w) * 0.5),
		Vector3(w, 0.15, d), mat)
	return host


## Zone table for the UI and any future teleport list. One source of truth.
static func zones() -> Array:
	return [
		{"id": "A", "name": "Spawn / Equipment", "rect": ZONE_SPAWN},
		{"id": "B", "name": "Combat Court", "rect": ZONE_COMBAT},
		{"id": "M", "name": "Mirror Test", "rect": ZONE_MIRROR},
		{"id": "D", "name": "Chain Lab", "rect": ZONE_CHAIN},
		{"id": "E", "name": "VFX Stage", "rect": ZONE_VFX},
		{"id": "F", "name": "Environment Gallery", "rect": ZONE_SHOWCASE},
		{"id": "H", "name": "Duel Ring 擂台", "rect": ZONE_DUEL},
		{"id": "I", "name": "Terrain Park 复杂地形", "rect": ZONE_TERRAIN},
		{"id": "J", "name": "Long Range 远距离大平地", "rect": ZONE_RANGE},
		{"id": "C", "name": "Movement Lane", "rect": ZONE_MOVE_EXT},
	]
