extends Node3D
class_name ChainLab
# CHAIN LAB — a stage with enough room for a chain to actually be thrown.
#
# WHY IT EXISTS: the arena cannot answer "is the chain fun?". The arena is 24 x 24
# with an enemy standing on the walking line, so a 4.6m sweep either clips a pillar
# or the dummy, and there is nowhere to throw a head far enough to feel the chain
# go taut. 缚星链 is a weapon about SPACE, so it needs a room that has some: a
# long deck, a wall at the end of it, a fixed anchor, and things of three different
# weights to catch (brief §39).
#
# Everything is built in code and is deterministic, like MovementLane and
# WindProps — ART may replace the meshes, but three things must survive, because
# they are the stage's whole function:
#
#   the WALL        a throw that hits nothing costs the spin, and that only exists
#                   if there is something solid to hit
#   the ANCHOR      hooking something fixed is how §20's tension is reachable
#   three WEIGHTS   light / medium / heavy standing in one place is the only way
#                   to see the weight table behave differently in one shot
#
# The deck's TOP FACE IS AT y = 0 while the arena's floor mesh tops out at 0.25 —
# a quarter of a metre, under a third of an enemy's hurtbox height, so a height in
# the chain's data still reaches the same thing in both rooms. Keeping the deck at
# 0 also keeps the bridge flush with it: a 0.25 lip at the join is taller than
# move_and_slide steps, and the deck would be reachable only by teleport.

const CENTER := Vector3(0.0, 0.0, -31.0)
const DECK_SIZE := Vector3(28.0, 0.9, 24.0)
const DECK_TINT := Color(0.29, 0.30, 0.33)
const KERB_TINT := Color(0.18, 0.19, 0.22)
const MARK_TINT := Color(0.55, 0.53, 0.46)
const INTERVAL_TINT := Color(0.72, 0.45, 0.30)
const MARK_STEP := 2.0
const KERB_HEIGHT := 0.55

# The wall a throw is meant to end on, and the bridge back to the arena.
const WALL_Z := -42.6
# §V4·PASS C — WHY THIS IS 2.05 AND NOT 3.4.
#
# 左甩 is an ARC of radius 2.60 → 4.30, so its forward reach is about 3.48m and the D
# take must stand 3.35m off this face for the bite to land where the trident is not
# buried behind the player's own body. At that standoff a 3.4m wall fills the frame
# from top to bottom: the projected top edge lands ABOVE the lens, so the take showed
# a featureless grey slab with no silhouette, no top, and no way to tell the wall from
# the sky behind it. `tools/probe_wall_frame.gd` measured the top edge at y = −61 px in
# a 720px frame, and `tools/sample_frame.gd` measured the slab at a flat 0.42 across
# everything above the deck line.
#
# The wall cannot move back — the reach is fixed by the move — so the only free number
# is its HEIGHT. 2.05m puts the top edge at about y = 185 px: sky above, wall through
# the middle, deck below, and the bite lands at ~1.15m, which is inside the slab where
# it belongs. The sweep crosses at 1.05–1.25m, so a 2.05m wall still catches every
# arc this weapon has, with ~80cm of headroom.
const WALL_HEIGHT := 2.05
# The height 左甩 crosses the player's own centre line at (its `height_from` 1.25 →
# `height_to` 1.05, read just past halfway round the arc). A painted line here is where
# the weapon actually arrives, so a bite that lands on it can be seen to have landed
# AT a height rather than merely to have stopped.
const WALL_CROSS_HEIGHT := 1.22
# The height of the painted band, i.e. the window 左甩 can arrive in. See `_wall`.
#
# A ZONE AND NOT A HAIRLINE, and the width is the honest part: the arc's arrival
# height depends on WHERE ALONG THE WALL it meets (the sweep descends 1.25 → 1.05 as it
# travels, and the contact azimuth moves with the standoff), so the marking is sized to
# the range the weapon can actually arrive in rather than to one derived number. A thin
# line would also invite the reading that a bite a few centimetres off it MISSED.
const SWEEP_BAND_HEIGHT := 0.48
const BRIDGE_WIDTH := 4.0
const BRIDGE_FROM_Z := -12.0

const ENTRY := Vector3(0.0, 0.9, -22.0)
const ANCHOR_POSITION := Vector3(6.5, 0.0, -26.0)

# THE HIGH ANCHOR (brief §45). The pillar above is a fixed point at ground level —
# it answers "hook something that will not move", which is §20's tension. This one
# answers a different question: "hook something OVER YOUR HEAD", which is the whole
# subject of 游链 (§6–§9: swing, redirect, orbit) and the reason the training ground
# needs a point above the player rather than only one in front of them.
#
# It is a crossbar on a post, and only the BAR is hookable: the anchor's own volume
# hangs below the arm, so a throw aimed up meets the bar and attaches instead of
# being stopped by it as a wall. That distinction is why this is not just a second
# pillar with a taller height — a solid post is something the chain bounces off.
#
# THE HEIGHT IS A REACHABILITY NUMBER, not a decoration. The head travels in polar
# coordinates, so a hook aimed upward lands at `radius = horizontal distance` and
# `height = 1.15 + sin(pitch) * radius`; the bar's centre is therefore placed where a
# player standing a natural throwing distance away has to look up about 28°. Higher
# than this and hooking it becomes a precision stunt, which a training ground fixture
# must never be.
const HIGH_ANCHOR_POSITION := Vector3(-6.4, 2.30, -26.6)
const GANTRY_POST := Vector3(-8.6, 0.0, -26.6)
const GANTRY_ARM_Y := 3.42
const GANTRY_RADIUS := 0.22
const CRATE_STARTS: Array[Vector3] = [
	Vector3(4.0, 0.5, -23.6),
	Vector3(4.9, 0.5, -24.7),
	Vector3(3.3, 1.4, -24.2),
]

const DUMMY_SCENE := preload("res://scenes/enemies/TechnicalDummy.tscn")

# Three weights, at three distances, all inside one throw of each other. This is
# the layout that makes the weight table's argument visible: the same hook, the
# same pull, three different outcomes.
const SLOTS: Array[Dictionary] = [
	{"weight": ElementLibrary.WEIGHT_LIGHT, "position": Vector3(-2.4, 0.0, -25.4)},
	{"weight": ElementLibrary.WEIGHT_MEDIUM, "position": Vector3(0.6, 0.0, -26.4)},
	{"weight": ElementLibrary.WEIGHT_HEAVY, "position": Vector3(-0.4, 0.0, -29.2)},
]

## WHERE THIS STAGE IS PLACED. Every position below is authored around `CENTER`
## and then shifted by this, so ONE definition of the rig can be hosted twice:
##
##   zero        the arena (CombatSandbox). This is the default, and it is what
##               every existing caller and every chain test reads — the published
##               constants (`WALL_Z`, `CENTER`, `DECK_SIZE`, `HIGH_ANCHOR_POSITION`,
##               `GANTRY_POST`) stay the WORLD coordinates of that hosting, so
##               `chain_integration` / `chain_physicality` / `chain_v4_slice` are
##               untouched by this.
##   non-zero    ART's Training Ground compound, which hosts this same rig inside
##               zone D (see `training_ground._chain_lab`). That is the whole
##               point: 训练场只有一套链房，它是这个类，放的位置是参数。
##
## Set it BEFORE `add_child()`; `_ready()` builds immediately.
var origin := Vector3.ZERO
## The arena needs a walkable bridge back to itself — it is a pocket in another
## room. A host that is already a compound with a floor everywhere wants no stub
## running off toward a wall that is not there.
var build_bridge := true
## The arena needs this to BE a room. ART's compound is already a paved court at
## exactly the height the rig authors its contents against (y = 0), so a second 0.9 m
## slab there is not a floor, it is a coplanar duplicate of one — and two top faces at
## the same y is z-fighting, which is the one thing a review stage must not ship.
## With it off, the rig contributes KERBS, MARKINGS, WALL, ANCHORS, CRATES and the
## weight table, and the host contributes the ground.
var build_deck := true
## Three weights in one throw is the arena's demonstration of the weight table. A host
## that already has its own masses ON the rig's centreline — ART's compound stands the
## playtest range's light/medium/heavy at 3 / 6 / 9 m straight down this deck — would
## be standing two sets of targets inside each other, so it asks for the rig's own to
## be left out. The layout they replace is not lost: it is still what the arena shows.
var build_targets := true
## Rows the HOST adds to the key legend, as `[text, tint]`.
##
## The keys above are the same in every room; the test spots are not. The arena's lab
## has three, ART's compound has five, and a fixture one of them does not contain must
## not be listed by the legend standing in it — the whole reason the legend exists is
## that 用户不知道怎么测试, and a card naming an object that is not there is worse than
## no card.
var legend_extra_rows: Array = []

var targets: Array[Node3D] = []
var anchor: ChainAnchor
var high_anchor: ChainAnchor
var crates: Array[ChainCrate] = []
var legend: CanvasLayer
# The legend is built deferred, so "should it be showing" has to outlive the call that
# asks. See `set_legend_visible`.
var _legend_wanted := true


# §17 — THE KEY LEGEND, AND WHY ITS KEYS ARE GENERATED RATHER THAN TYPED.
#
# The brief for this pass listed the keys as "Hold E Skill 1 / Q Skill 2 / F Ultimate".
# NONE OF THOSE THREE IS BOUND. The build creates `style_skill_1` on F3, `style_skill_2` on
# F4 and `heavy_attack` on F; E is `cast_selected` and Q does not exist at all. A legend
# that names the wrong keys is worse than no legend — the whole reason this exists is
# 用户不知道怎么测试 — so every key below is READ OUT OF `InputMap` on the frame it is
# drawn. The action names are the contract; the letters are what the project actually
# bound, and the two cannot drift apart without the label changing with them.
const LEGEND_ROWS: Array = [
	["轻击连段  A1 → A2 → A3", &"light_attack"],
	["缚 · 勾住 (Skill 1)", &"skill_1"],
	["锁 · 束缚 (Skill 3)", &"skill_3"],
	["重击 / 蓄力 (Skill 2 · 按住)", &"skill_2"],
	["格挡 (按住)", &"block"],
	# 聚合斩 AND 无明一刻 WERE NOT ON THIS CARD, which mattered the moment the room
	# grew a target that only exists to be cut in half by one of them. A fixture whose
	# instruction is "press the signature" and a legend that does not name the
	# signature's key is the same failure as the wrong letter, one step quieter.
	["聚合斩 · 居合 (Sword Skill 1)", &"skill_1"],
	["无明一刻 · 大招", &"ultimate"],
]
const LEGEND_MOVE_ROWS: Array = [
	["闪避 → 疾跑 (Shift)", &"dodge_sprint"],
	["慢走 (按住)", &"walk"],
	["交互", &"interact"],
]


func _ready() -> void:
	_deck()
	_kerbs()
	_markings()
	_bridge()
	_wall()
	_anchor()
	_high_anchor()
	_crates()
	_spawn_targets()
	_clear_overlapping_dressing()
	# DEFERRED, because the keys do not exist yet. Every binding in this project is created
	# at RUNTIME by the node that owns it (`player_movement`, `combat_controller`,
	# `weapon_manager`), and `_ready` runs children-first in tree order — so a legend built
	# inline reads a half-empty `InputMap` and prints blanks for whichever half had not run.
	# Deferred lands after every `_ready` in the frame, which is the first moment the map is
	# the one the player will actually be using.
	_build_legend.call_deferred()


## The key actually bound to an action, as the player would read it on their keyboard.
## Empty when the action has no binding at all, so a legend row that describes something
## this build does not have says so instead of printing a plausible-looking lie.
static func key_of(action: StringName) -> String:
	if not InputMap.has_action(action):
		return ""
	for e in InputMap.action_get_events(action):
		if e is InputEventMouseButton:
			match (e as InputEventMouseButton).button_index:
				MOUSE_BUTTON_LEFT: return "LMB"
				MOUSE_BUTTON_RIGHT: return "RMB"
				MOUSE_BUTTON_MIDDLE: return "MMB"
				_: return "?"
		if e is InputEventKey:
			# `physical_keycode` FIRST, because the key that matters is the one under the
			# player's finger and this project's bindings are positional — but falling back
			# to `keycode` matters: an event created with only a logical key has a physical
			# code of 0, and `get_keycode_string(0)` is the empty string, so a legend reading
			# only the physical code prints a BLANK KEY for that row. A blank where a key
			# should be reads as "this action exists and has no button", which is a lie.
			var key := (e as InputEventKey)
			var code := key.physical_keycode if key.physical_keycode != 0 else key.keycode
			var name := OS.get_keycode_string(code)
			if not name.is_empty():
				return name
	return ""


func _legend_line(slot: String, text: String) -> String:
	return "%s  %s" % [slot, text]


func _build_legend() -> void:
	legend = CanvasLayer.new()
	legend.name = "TrainingLegend"
	# Under any real HUD, over the world. There is no HUD in the training ground; this is
	# furniture of the STAGE, not of the interface, which is why it lives here and does not
	# reach into `combat_hud.gd`.
	legend.layer = 1
	add_child(legend)
	legend.visible = _legend_wanted
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_TOP_LEFT)
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_top", 14)
	legend.add_child(margin)
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.06, 0.08, 0.72)
	style.content_margin_left = 12.0
	style.content_margin_right = 14.0
	style.content_margin_top = 9.0
	style.content_margin_bottom = 10.0
	panel.add_theme_stylebox_override("panel", style)
	margin.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 2)
	panel.add_child(column)

	# the key column is as wide as the widest key, so the descriptions line up whatever
	# the bindings happen to be
	var slots: Array[String] = []
	for row in LEGEND_ROWS + LEGEND_MOVE_ROWS:
		slots.append(key_of(row[1]))
	var weapon_slot := "1 / 2"
	slots.append(weapon_slot)
	var slot_width := 3
	for s in slots:
		slot_width = maxi(slot_width, s.length())
	for row in LEGEND_ROWS + LEGEND_MOVE_ROWS:
		column.add_child(_legend_label(_legend_line(key_of(row[1]).rpad(slot_width), row[0]), 15, Color(0.90, 0.91, 0.93)))
	column.add_child(_legend_label(_legend_line(weapon_slot.rpad(slot_width), "剑  /  缚星链"), 15, Color(0.90, 0.91, 0.93)))
	column.add_child(_legend_label("", 7, Color(1, 1, 1, 0)))
	column.add_child(_legend_label("A  空挥 · 无目标", 14, Color(0.62, 0.78, 0.62)))
	column.add_child(_legend_label("B  木桩 · 轻/中/重三档", 14, Color(0.62, 0.78, 0.62)))
	column.add_child(_legend_label("C  石墙 · 咬住 / 绷紧", 14, Color(0.62, 0.78, 0.62)))
	for row in legend_extra_rows:
		column.add_child(_legend_label(String(row[0]), 14, row[1] as Color))


func _legend_label(text: String, size: int, tint: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", tint)
	# An outline rather than a background per row: the deck is mid-grey and the wall is
	# pale, and a legend that is only legible over one of them is not a legend.
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.85))
	label.add_theme_constant_override("outline_size", 6)
	return label


## For takes: a still that is about the STOW does not want a key list in the corner. The
## node is hidden rather than freed so the layer index and the layout survive a toggle.
##
## THE INTENT IS REMEMBERED, because the legend is built DEFERRED (see `_ready`) and a
## caller that hides it in the same frame can otherwise be undone a frame later — the
## hidden-then-rebuilt legend comes back visible, and a review artefact ends up with a
## key table in the corner depending on which of two orderings happened to run first.
func set_legend_visible(shown: bool) -> void:
	_legend_wanted = shown
	if legend != null:
		legend.visible = shown


func entry_position() -> Vector3:
	return ENTRY + origin


func slot_position(weight: StringName) -> Vector3:
	for slot in SLOTS:
		if slot["weight"] == weight:
			return (slot["position"] as Vector3) + origin
	return ENTRY + origin


func target_for(weight: StringName) -> Node3D:
	for target in targets:
		if is_instance_valid(target) and target.call("weight_class") == weight:
			return target
	return null


func reset() -> void:
	# Back to the starting picture. Rigid bodies do not restore themselves, and a
	# take that begins with the crates already thrown across the room is measuring
	# the previous take.
	for i in crates.size():
		if is_instance_valid(crates[i]):
			crates[i].freeze = true
			var home: Vector3 = (CRATE_STARTS[i] if i < CRATE_STARTS.size() else CENTER) + origin
			crates[i].global_position = home
			crates[i].linear_velocity = Vector3.ZERO
			crates[i].angular_velocity = Vector3.ZERO
			crates[i].freeze = false
	for target in targets:
		if is_instance_valid(target):
			target.call("reset_dummy")


func _material(tint: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = tint
	material.roughness = 0.94
	return material


func _solid(size: Vector3, tint: Color, pos: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = pos
	add_child(body)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	var mesh := MeshInstance3D.new()
	var mesh_box := BoxMesh.new()
	mesh_box.size = size
	mesh.mesh = mesh_box
	mesh.material_override = _material(tint)
	body.add_child(mesh)
	return body


func _flat(size: Vector3, tint: Color, pos: Vector3) -> void:
	# Paint, not geometry: a marking that caught a footstep would be a bug.
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = _material(tint)
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh.position = pos
	add_child(mesh)


func _deck() -> void:
	# Top face at y = 0: the chain's heights are authored relative to the floor the
	# player stands on, so the lab and the arena have to agree about where that is.
	if not build_deck:
		return
	_solid(DECK_SIZE, DECK_TINT, CENTER + origin + Vector3(0.0, -DECK_SIZE.y * 0.5, 0.0))


func _kerbs() -> void:
	var half_x := DECK_SIZE.x * 0.5 - 0.15
	var half_z := DECK_SIZE.z * 0.5 - 0.15
	for side in [-1.0, 1.0]:
		_solid(
			Vector3(0.3, KERB_HEIGHT, DECK_SIZE.z),
			KERB_TINT,
			CENTER + origin + Vector3(side * half_x, KERB_HEIGHT * 0.5, 0.0)
		)
	# THE NEAR END HAS A DOORWAY, NOT A KERB. The bridge lands on this edge, and a
	# 0.55m kerb across the join is taller than a step — so a full-width kerb here
	# makes the whole deck reachable only by teleport, which is exactly the failure
	# the movement lane's ramp had. Two segments flank a BRIDGE_WIDTH gap instead,
	# so the ground still states "the deck ends here" everywhere the deck does end.
	var opening := BRIDGE_WIDTH + 0.8
	var segment := (DECK_SIZE.x - opening) * 0.5
	for side in [-1.0, 1.0]:
		_solid(
			Vector3(segment, KERB_HEIGHT, 0.3),
			KERB_TINT,
			CENTER + origin + Vector3(
				side * (opening * 0.5 + segment * 0.5), KERB_HEIGHT * 0.5, half_z
			)
		)
	# The far end needs no kerb: the wall stands there, full width and full height.


func _markings() -> void:
	# The ground states the distance, so "it reached the end of the chain" is a
	# thing a viewer can check instead of take on faith.
	var count := int(DECK_SIZE.z / MARK_STEP)
	var start_z := CENTER.z - DECK_SIZE.z * 0.5 + MARK_STEP
	for i in range(count):
		var z := start_z + float(i) * MARK_STEP
		var interval := i % 4 == 0
		_flat(
			Vector3(DECK_SIZE.x - 1.2, 0.03, 0.16 if interval else 0.09),
			INTERVAL_TINT if interval else MARK_TINT,
			Vector3(CENTER.x + origin.x, origin.y + 0.02, z + origin.z)
		)


func _bridge() -> void:
	# Only the arena needs this. See `build_bridge`.
	if not build_bridge:
		return
	# A way over on foot, so this is part of the world rather than a pocket only a
	# teleport reaches. The arena floor ends at z = -12 and the lab starts at z = -19.
	var length := absf(BRIDGE_FROM_Z - (CENTER.z + DECK_SIZE.z * 0.5))
	var middle := (BRIDGE_FROM_Z + (CENTER.z + DECK_SIZE.z * 0.5)) * 0.5
	_solid(
		Vector3(BRIDGE_WIDTH, 0.6, length),
		DECK_TINT,
		Vector3(origin.x, -0.3 + origin.y, middle + origin.z)
	)


func _wall() -> void:
	# THE THING A THROW ENDS ON. Without it, momentum loss on impact does not exist
	# and the chain has no reason to respect space (§21).
	_solid(
		Vector3(DECK_SIZE.x, WALL_HEIGHT, 0.7),
		Color(0.24, 0.25, 0.28),
		Vector3(CENTER.x + origin.x, origin.y + WALL_HEIGHT * 0.5, WALL_Z + origin.z)
	)
	# §V4·PASS C — A BAND FOR THE BITE TO LAND IN. Painted, not geometry, in the deck's
	# own marking language. Without it the wall is a flat slab carrying nothing, so the
	# frame can only show that the head stopped, never where — and "it bit the wall" and
	# "it hung in front of the wall" are the same picture.
	#
	# A BAND AND NOT A LINE, because a hairline invites the reading that a bite a few
	# centimetres off it MISSED. 左甩 arrives between 1.05m and 1.25m depending on where
	# along the arc it meets the wall, so the marking is that whole window and every
	# landing is inside it.
	_flat(
		Vector3(DECK_SIZE.x, SWEEP_BAND_HEIGHT, 0.05),
		MARK_TINT,
		Vector3(CENTER.x + origin.x, WALL_CROSS_HEIGHT + origin.y, WALL_Z + 0.35 + 0.03 + origin.z)
	)


func _anchor() -> void:
	# A FIXED POINT (§20). Made of the same contract an enemy is: it says it is
	# heavy, so the chain moves the player instead of the pillar — no anchor-
	# specific code anywhere in the weapon.
	anchor = ChainAnchor.new()
	anchor.name = "ChainAnchor"
	anchor.radius = 0.6
	anchor.height = 4.4
	anchor.position = ANCHOR_POSITION + origin
	add_child(anchor)


func _high_anchor() -> void:
	# The structure is REAL geometry (it can be walked into and thrown past), and the
	# hookable part is only the bar. A two-post gantry rather than a cantilever so the
	# arm is not floating: one post takes the load, the second sits where the player
	# can see that the span is a span.
	_solid(
		Vector3(GANTRY_RADIUS * 2.0, GANTRY_ARM_Y - 0.13, GANTRY_RADIUS * 2.0),
		KERB_TINT,
		GANTRY_POST + origin + Vector3(0.0, (GANTRY_ARM_Y - 0.13) * 0.5, 0.0)
	)
	var arm_len := absf(GANTRY_POST.x - HIGH_ANCHOR_POSITION.x) + 0.6
	var arm_mid := (GANTRY_POST.x + HIGH_ANCHOR_POSITION.x) * 0.5 + 0.3
	_solid(
		Vector3(arm_len, 0.26, GANTRY_RADIUS * 2.0),
		KERB_TINT,
		Vector3(arm_mid + origin.x, GANTRY_ARM_Y + origin.y, GANTRY_POST.z + origin.z)
	)
	# The bar the chain catches, hanging under the arm. Its volume stops BELOW the
	# arm's underside on purpose: the sweep ray tests the solid world first, so a
	# hookable box that overlapped the arm would never be reached — the head would
	# register a wall hit on the arm it was aimed at.
	high_anchor = ChainAnchor.new()
	high_anchor.name = "ChainHighAnchor"
	high_anchor.radius = 0.26
	high_anchor.height = 0.95
	high_anchor.position = HIGH_ANCHOR_POSITION + origin
	add_child(high_anchor)
	# A mark on the bar so the one hookable thing overhead is FINDABLE (§32).
	for side in [-1.0, 1.0]:
		_flat(
			Vector3(0.13, 0.13, 0.13),
			INTERVAL_TINT,
			HIGH_ANCHOR_POSITION + origin + Vector3(side * 0.27, 0.0, 0.0)
		)


func _crates() -> void:
	for i in CRATE_STARTS.size():
		var crate := ChainCrate.new()
		crate.name = "Crate%d" % i
		crate.position = CRATE_STARTS[i] + origin
		add_child(crate)
		crates.append(crate)


func _spawn_targets() -> void:
	# Three weights standing in one room. They live HERE rather than in the sandbox
	# because a stage owning its own enemies is what makes the weight table's
	# argument visible in a single glance — and the dummy finds the player through
	# the player's group, so it does not care whose child it is.
	if not build_targets:
		return
	for slot in SLOTS:
		var dummy := DUMMY_SCENE.instantiate() as Node3D
		dummy.name = "Target_%s" % String(slot["weight"])
		dummy.set("weight", slot["weight"])
		add_child(dummy)
		dummy.global_position = (slot["position"] as Vector3) + origin
		dummy.rotation.y = 0.0
		targets.append(dummy)


# THE ROOM CANNOT CONTAIN THE OTHER ROOM'S RUBBLE.
#
# ArenaDressing predates this stage and scatters 39 placeholder pieces across
# z = -3..-22 without knowing the deck is here, so eight of them land inside it —
# including two four-metre pillars, one of which stands square in the bridge
# doorway. They have no collision, so this is a framing problem rather than a
# movement one, but a stage with someone else's rubble standing in the middle of it
# is not a stage, and every one of these shows up in a 4.6m sweep.
#
# Hiding rather than deleting: both rooms are deterministic placeholders ART is
# going to replace wholesale, so nothing is lost by suppressing the overlap now —
# and if the lab ever moves, the dressing is still complete underneath.
func _clear_overlapping_dressing() -> void:
	var parent := get_parent()
	if parent == null:
		return
	var dressing := parent.get_node_or_null("ArenaDressing")
	if dressing == null:
		return
	# A tall column over the deck plus the bridge corridor, both grown sideways so
	# a piece that merely leans over the edge is caught too.
	const pad := 0.5
	const COLUMN_HEIGHT := 12.0
	var deck_min := CENTER + origin - DECK_SIZE * 0.5
	var deck := AABB(
		Vector3(deck_min.x - pad, 0.0, deck_min.z - pad),
		Vector3(DECK_SIZE.x + pad * 2.0, COLUMN_HEIGHT, DECK_SIZE.z + pad * 2.0)
	)
	var deck_near_z := CENTER.z + origin.z + DECK_SIZE.z * 0.5
	var bridge := AABB(
		Vector3(-(BRIDGE_WIDTH * 0.5 + pad) + origin.x, 0.0, BRIDGE_FROM_Z + origin.z),
		Vector3(BRIDGE_WIDTH + pad * 2.0, COLUMN_HEIGHT, absf(BRIDGE_FROM_Z - deck_near_z))
	)
	var hidden := 0
	for child in dressing.get_children():
		var mesh_node := child as MeshInstance3D
		if mesh_node == null or mesh_node.mesh == null:
			continue
		# Ask the MESH for its box and transform it, rather than reading
		# VisualInstance3D.get_aabb(): that one is filled in by the renderer and
		# stays empty in a headless run, so the same code would hide the pillars in
		# the video and miss them in the test that is supposed to prove it does.
		var box := mesh_node.global_transform * mesh_node.mesh.get_aabb()
		if deck.intersects(box) or bridge.intersects(box):
			mesh_node.visible = false
			hidden += 1
	if hidden > 0:
		print("ChainLab: hid %d ArenaDressing placeholder(s) inside the deck/bridge footprint" % hidden)
