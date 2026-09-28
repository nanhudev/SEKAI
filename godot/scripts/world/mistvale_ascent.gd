@tool
extends Node3D
class_name MistvaleAscent
## S-B HERO ASCENT blockout + Guild Terrace composition (brief §4-§15, §20, §22).
##
## WHY THIS IS A SEPARATE BUILDER FROM MistvaleGreybox: the greybox answers
## "does the route network hold". This answers a different and harder question:
## "does the climb have a COMPOSITION". Brief §4 forbids S-B from being one
## 56 step staircase, and brief §20 says to prove that with Godot primitives
## before any final art exists. So this file is a composition, not a mass.
##
## THE ONE GEOMETRIC FACT THAT SHAPES EVERYTHING: the crux is a 40 deg face with
## only ~19 m of run. You cannot put generous landings in it without cutting
## several metres off a mountain, and brief §3 lets you restructure space but
## not rebuild landforms. So "landing" here is delivered by two devices that
## cost NO run:
##
##   ALCOVE   — cut back INTO the uphill rock. You are inside the mountain.
##   BALCONY  — cantilever OUT over the downhill drop. You are above the valley.
##
## Both give the player a place to stand, breathe and turn around, at 1.5-2.5 m
## of route instead of the 8-10 m a flat cut terrace would need. That is the
## design answer to "small platform, rock pressure, then the turn" in §4.
##
## STEP GEOMETRY IS SOLVED, NOT AUTHORED. The number of modules comes from the
## run (7 steps = one 2.00 m module, so n = run / 2.00) and the riser comes from
## whatever the ground actually rises. Nothing here hand-writes an elevation —
## the 68 deg Cliff Route wall came from exactly that mistake.

## WHY NOTHING IN THIS FILE CASTS A SHADOW (measured, not assumed)
##
## Every piece here is a box that is deliberately BURIED: a step mass sinks
## SINK = 1.6 m into the slope, a landing is anchored behind a retaining wall,
## a deck sits on corbels that reach down into the hill. That is correct for a
## blockout, and it is only safe because the ground hides the buried part.
##
## BUT THE GROUND IS NOT IN THE SHADOW MAP. The terrain opts out of casting
## (see mistvale_terrain.gd: a 660x760 m heightfield at 3 m sampling cannot be
## bias-corrected in a directional shadow map and moires the whole valley). So
## the shadow map contains only the discrete casters — and to the shadow map,
## the buried part of a step is not buried at all. It is a 1.6-4.9 m tall blade
## hanging in a void, and a 44 deg sun throws its shadow five metres across the
## treads behind it.
##
## Measured at review point R06 (Guild Terrace, standing on the first flight):
## the whole frame came back at luminance 24/255 while the same camera looking
## the other way was 117. Bisected by hiding one node at a time — Terrain,
## Town, Greybox, Land, Flora and the cliff-route group all changed nothing;
## only the Guild group did. Then, decisively:
##     shadow casting off on that one flight   -> 62
##     shadow casting off on the whole group   -> 70
##     sun.shadow_enabled = false              -> 77
## Shadow bias, normal bias and shadow distance were all swept and NONE of them
## moved the number, which is the signature of a real occluder rather than
## acne: the occluder is metres from the receiver along the light ray.
##
## So the blockout steps out of the shadow pass. When this gets real art, that
## art must not rely on being buried to look solid, or the terrain has to come
## back into the shadow map with a bias that actually works.
const SINK := 1.6                  # how far a step mass buries into the slope
const MODULE_RUN := 2.00           # 7 steps, by the KIT-02a modulus
const RISER_MIN := 0.140
const RISER_MAX := 0.260
const LANDING_MAX_RISE := 1.20        # how far a terrace may stand above the last flight

# --- Palette: blockout only, but the colour story must already read ----------
const C_TREAD := Color(0.58, 0.56, 0.53)
const C_CHEEK := Color(0.46, 0.45, 0.44)
const C_RETAIN := Color(0.39, 0.38, 0.37)
const C_RAIL := Color(0.28, 0.29, 0.31)
const C_RUBBLE := Color(0.51, 0.48, 0.43)
const C_ANCIENT := Color(0.42, 0.47, 0.53)
const C_SOIL := Color(0.40, 0.36, 0.29)
const C_DECK := Color(0.63, 0.61, 0.56)
const C_CIVIC := Color(0.64, 0.60, 0.52)

# --- Toggles ---------------------------------------------------------------
@export var show_flights: bool = true
@export var show_dressing: bool = true
@export var show_decks: bool = true
@export var show_guild: bool = true


# =============================================================================
# Authoring data
# =============================================================================

const CLIFF_ROUTE := 0
const GUILD_ROUTE := 1
## Start of the hero ascent, in metres along the Cliff Route. 216 m puts the
## first beat just after the cliff ledge, where the flank turns and the town
## stops being visible — the moment the climb is supposed to *begin*.
const CLIFF_START := 216.0
const GUILD_START := 6.0

## The climbing sequence. Order IS the design: §4 asks for
## steps -> bay -> rock pressure -> turn -> steps -> view opens -> fragments ->
## final steep flight -> forecourt, and that is literally this list.
##
## FLIGHT RUNS ARE MULTIPLES OF 2.00 m on purpose. The modulus fixes the tread
## at 2.00/7 = 0.2857 m, so a flight's length decides how many steps it has —
## not the other way round. A 5 m "flight" would have to use a 0.238 m tread,
## which is a different stair pretending to be this one.
##
## FLIGHTS ALSO ONLY EXIST BETWEEN D=238 AND D=260. Below that the measured
## grade is 22-31 deg, which is walking; above it the grade has already eased to
## 28 deg. Putting steps on either is how you get a staircase nobody notices.
const BEATS := [
	{"k": "WALK", "run": 16.0, "waist": 2.8,
		"label": "山腹横切 — 城镇已被山肩挡住，只剩钟塔在身后"},
	{"k": "GATE", "run": 3.0, "waist": 2.4,
		"label": "旧门框遗构 — 路线第一次被「人工」标记"},
	{"k": "WALK", "run": 3.0, "waist": 2.6,
		"label": "阶前坡 — 24 deg，脚步开始抬高"},
	{"k": "FLIGHT", "run": 8.0, "waist": 2.6, "riser": 0.24,
		"label": "第一段阶 — 28 级，全线最宽的一段"},
	{"k": "ALCOVE", "run": 2.0, "waist": 2.2,
		"label": "岩凹 — 侧向挖进山体的休憩位，岩壁压在头顶"},
	{"k": "FLIGHT", "run": 6.0, "waist": 2.3, "riser": 0.24,
		"label": "第二段阶 — 21 级，收窄"},
	{"k": "BALCONY", "run": 2.0, "waist": 2.4,
		"label": "半空挑台 — 侧向悬出，回头是钟塔和你走过的整条坡"},
	{"k": "FLIGHT", "run": 4.0, "waist": 2.4, "riser": 0.20,
		"label": "第三段阶 — 14 级，出坡"},
	{"k": "SHELF", "run": 2.0, "waist": 3.2,
		"label": "天然岩台 — 路线轻转，视野打开"},
	{"k": "WALK", "run": 8.0, "waist": 3.0,
		"label": "破口旧墙 — 人工痕迹从「旧」变成「看不懂」"},
	{"k": "FRAGMENT", "run": 8.0, "waist": 3.2,
		"label": "遗迹碎片带 — 尺度与逻辑不再像人所能建"},
	{"k": "ARRIVAL", "run": 16.9, "waist": 5.0,
		"label": "前场 — 铺装、残墙、信标基座"},
]

## Guild Terrace: CIVIC, not a mountain path (§3). Wide flights, generous
## landings, a balustrade, and the guild entrance as the terminating axis.
##
## The climb only exists between D=35 and D=55 — the market's north edge is
## flat for 29 m. So the composition puts a real public PLAZA there rather than
## forcing steps onto level ground: §13 asks for evidence that residents walk
## this way, and 29 m of frontage is that evidence.
const GUILD_BEATS := [
	{"k": "WALK", "run": 29.0, "waist": 9.0,
		"label": "市场北缘公共广场 — 居民真的会走这条路"},
	{"k": "FLIGHT", "run": 6.0, "waist": 4.4, "riser": 0.16,
		"label": "第一段宽阶 — 21 级，四米喉宽"},
	{"k": "LANDING", "run": 2.0, "waist": 7.0,
		"label": "下平台 — 栏杆，回望市场与钟塔"},
	{"k": "FLIGHT", "run": 6.0, "waist": 4.4, "riser": 0.16,
		"label": "第二段宽阶 — 21 级"},
	{"k": "LANDING", "run": 2.0, "waist": 8.0,
		"label": "中平台 — C-05 战斗空间，公会正面升起"},
	{"k": "FLIGHT", "run": 4.0, "waist": 4.4, "riser": 0.16,
		"label": "第三段宽阶 — 14 级，收窄，接近入口"},
	{"k": "ARRIVAL", "run": 14.0, "waist": 10.0,
		"label": "公会前庭 — 正对公会入口的轴线"},
]


# =============================================================================
# Layout — the numbers, computed from the field. Shared with the audit tool.
# =============================================================================

static func route_for(which: int) -> Array:
	if which == GUILD_ROUTE:
		return [Vector2(0.0, 8.0), Vector2(0.0, -62.0)]
	return MistvaleHeights.CLIFF_ROUTE


static func cliff_layout() -> Array:
	return layout(CLIFF_ROUTE, CLIFF_START, BEATS)


static func guild_layout() -> Array:
	return layout(GUILD_ROUTE, GUILD_START, GUILD_BEATS)


static func _ground(pts: Array, d: float) -> float:
	var p := MistvaleHeights.route_at(pts, d)
	return MistvaleHeights.height_at(p.x, p.y)


## Walk the authored beats and resolve every dimension against the field.
##
## THE INVERSION THAT MATTERS: for a fixed-tread system the module count comes
## from the RUN (7 steps occupy exactly 2.00 m), and the riser is then whatever
## the ground demands. Solving it the other way round — picking a nice riser and
## letting the run fall out — is how you end up with a 0.23 m tread or a flight
## that lands a metre short of the trail.
static func layout(which: int, start_d: float, beats: Array) -> Array:
	var pts := route_for(which)
	var out := []
	var d := start_d
	var sh := _ground(pts, d)
	for b in beats:
		var kind: String = b["k"]
		var run: float = b["run"]
		var g0 := _ground(pts, d)
		var g1 := _ground(pts, d + run)
		var rec := {
			"kind": kind,
			"label": b.get("label", ""),
			"d0": d,
			"d1": d + run,
			"run": run,
			"waist": float(b.get("waist", 2.6)),
			"want": float(b.get("riser", 0.0)),
			"g0": g0,
			"g1": g1,
			"mid": (g0 + g1) * 0.5,
			"sh0": sh,
			"steps": 0,
			"modules": 0,
			"riser": 0.0,
			"tread": 0.0,
			"pitch": 0.0,
			"rise": 0.0,
			"drift": 0.0,
		}
		match kind:
			"FLIGHT", "STAIR":
				var rise := g1 - sh
				if rise < 0.25:
					rise = 0.0
				# MODULES FROM THE RUN, RISER FROM THE GROUND. Never the other
				# way round: adjusting the module count to chase a nicer riser
				# silently changes the tread, and a stair whose tread changes
				# between flights is not one construction language.
				var n := maxi(int(round(run / MODULE_RUN)), 1)
				var riser := 0.0
				var pitch := 0.0
				var tread := 0.0
				if rise > 0.0:
					tread = run / float(7 * n)
					riser = rise / float(7 * n)
					pitch = rad_to_deg(atan(riser / tread))
				rec["rise"] = rise
				rec["modules"] = n
				rec["riser"] = riser
				rec["tread"] = tread
				rec["pitch"] = pitch
				rec["steps"] = 7 * n
				rec["drift"] = riser - float(rec["want"]) if rise > 0.0 else 0.0
				sh += rise
			"LANDING":
				# Anchored to the UPHILL end, not a blend. A public terrace is
				# built UP behind a retaining wall — that is what makes it read
				# as civic architecture rather than a ditch. Blending instead
				# leaves the terrace half cut and forces the next flight to
				# climb the cut back, which measured 38.6 deg on what is
				# supposed to be the guild's gentle public stair.
				var want := clampf(g1, sh, sh + LANDING_MAX_RISE)
				sh = lerpf(sh, want, 0.9)
			"ALCOVE", "BALCONY":
				# A bay in a 40 deg face is a WIDTH feature, not a length one.
				# The path itself keeps the ground's grade and the niche is cut
				# sideways into the hill (or cantilevered sideways off it). This
				# is why these cost no run and force no neighbouring flight to
				# steepen — an earlier version made them level along the path
				# and pushed the next flight to 46 deg.
				sh = g1
			_:
				sh = g1
		rec["sh1"] = sh
		rec["cut"] = maxf(g1 - sh, 0.0)      # rock to remove at the uphill end
		rec["fill"] = maxf(sh - g0, 0.0)     # structure standing above grade
		# How far the built line departs from the ground it stands on, sampled
		# along the whole beat. This is the number that says whether a beat is
		# earthworks or a structure — a flight's total rise is NOT "fill", and
		# reporting it as such would hide a real 3 m cut behind an honest 3 m
		# climb.
		var dev := 0.0
		var probes := 8
		for pi in probes + 1:
			var t := float(pi) / float(probes)
			dev = maxf(dev, absf(_ground(pts, d + run * t) - lerpf(rec["sh0"], sh, t)))
		rec["dev"] = dev
		out.append(rec)
		d += run
	return out


# =============================================================================
# Build
# =============================================================================

func _ready() -> void:
	_build()


func _build() -> void:
	for c in get_children():
		c.queue_free()
	_build_sequence(CLIFF_ROUTE, cliff_layout(), "Ascent")
	_build_decks()
	if show_guild:
		_build_sequence(GUILD_ROUTE, guild_layout(), "Guild")


func _build_sequence(which: int, rows: Array, group: String) -> void:
	var root := Node3D.new()
	root.name = group
	add_child(root)
	for rec in rows:
		var unit := _unit(which, rec, root)
		match rec["kind"]:
			"FLIGHT", "STAIR":
				if show_flights:
					_flight(unit, rec)
				_dress_flight(unit, rec)
			"LANDING":
				_landing(unit, rec)
			"ALCOVE":
				_alcove(unit, rec)
			"BALCONY":
				_balcony(unit, rec)
			"GATE":
				_gate(unit, rec)
			"BROKEN":
				_rubble(unit, rec, 7)
			"SHELF":
				_shelf(unit, rec)
			"FRAGMENT":
				_fragments(unit, rec)
				if show_dressing:
					_rubble(unit, rec, 5)
			"ARRIVAL":
				_arrival(unit, which, rec)
			"WALK":
				_kerb(unit, rec)


## A container whose local -Z is the direction of travel, whose +X is the
## player's right, and whose origin sits at the structure height at d0.
func _unit(which: int, rec: Dictionary, parent: Node3D) -> Node3D:
	var pts := route_for(which)
	var t := MistvaleHeights.route_tangent(pts, rec["d0"] + rec["run"] * 0.5)
	var p := MistvaleHeights.route_at(pts, rec["d0"])
	var n := Node3D.new()
	n.name = "%s_%s_%03d" % [rec["kind"], String(rec["label"]).substr(0, 6), int(rec["d0"])]
	n.position = Vector3(p.x, rec["sh0"], p.y)
	n.rotation.y = atan2(-t.x, -t.y)
	parent.add_child(n)
	return n


## Local placement: `fwd` along travel, `lat` to the player's right, `up` above
## the structure height. (Godot nodes face -Z, so forward is -fwd.)
static func _at(fwd: float, lat: float, up: float) -> Vector3:
	return Vector3(lat, up, -fwd)


func _slab(
	parent: Node3D,
	pos: Vector3,
	size: Vector3,
	color: Color,
	name_: String = "",
	pitch: float = 0.0
) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _mat(color)
	mi.position = pos
	mi.rotation.x = pitch
	# BLOCKOUT DOES NOT CAST SHADOWS — and this is not a stylistic choice, it
	# is arithmetic. See the long note below.
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if name_ != "":
		mi.name = name_
	parent.add_child(mi)
	return mi


# =============================================================================
# Pieces
# =============================================================================

## A flight of real steps. Solid mass, so no step can float over the slope.
func _flight(unit: Node3D, rec: Dictionary) -> void:
	var steps: int = rec["steps"]
	if steps <= 0:
		return
	var run: float = rec["run"]
	var waist: float = rec["waist"]
	var riser: float = rec["riser"]
	var tread := run / float(steps)
	for i in steps:
		var top := float(i + 1) * riser
		var h := top + SINK
		# Outer edge erodes a little faster than the middle — the brief asks for
		# detail with a CAUSE, and this is the cheapest one that reads at speed.
		var w := waist * (0.93 + 0.07 * _h01(float(i) * 0.37))
		_slab(
			unit,
			_at((float(i) + 0.5) * tread, 0.0, top - h * 0.5),
			Vector3(w, h, tread * 1.08),
			C_TREAD,
			"step_%02d" % i
		)


## Cheek walls and the exposed-side rail. These are what turn a ramp into a
## built thing: brief §10's SECONDARY structure.
func _dress_flight(unit: Node3D, rec: Dictionary) -> void:
	if not show_dressing:
		return
	var steps: int = rec["steps"]
	if steps <= 0:
		return
	var run: float = rec["run"]
	var waist: float = rec["waist"]
	var rise := float(steps) * float(rec["riser"])
	var pitch := atan2(rise, run)
	for s in [-1.0, 1.0]:
		_slab(
			unit,
			_at(run * 0.5, s * (waist * 0.5 + 0.17), rise * 0.5 + 0.32),
			Vector3(0.34, 0.80, sqrt(run * run + rise * rise)),
			C_CHEEK,
			"cheek_%s" % ("r" if s > 0.0 else "l"),
			pitch
		)
	# Rail only on the exposed side, and only where there is a real drop.
	var drop := _drop_side(unit, run, waist)
	if drop != 0.0:
		var posts := maxi(int(run / 1.7), 2)
		for i in posts + 1:
			var f := run * float(i) / float(posts)
			var top := rise * f / run
			_slab(
				unit,
				_at(f, drop * (waist * 0.5 + 0.13), top + 0.52),
				Vector3(0.11, 0.98, 0.11),
				C_RAIL,
				"post_%02d" % i
			)
		for lvl in [0.30, 0.86]:
			_slab(
				unit,
				_at(run * 0.5, drop * (waist * 0.5 + 0.13), rise * 0.5 + lvl),
				Vector3(0.08, 0.08, sqrt(run * run + rise * rise)),
				C_RAIL,
				"rail_%.2f" % lvl,
				pitch
			)


## Which side falls away, +1 = player's right, -1 = left, 0 = neither.
func _drop_side(unit: Node3D, run: float, waist: float) -> float:
	var best := 0.0
	var deepest := 1.2
	for s in [-1.0, 1.0]:
		var probe := unit.to_global(_at(run * 0.5, s * (waist * 0.5 + 3.2), 0.0))
		var here := unit.to_global(_at(run * 0.5, 0.0, 0.0))
		var drop := here.y - MistvaleHeights.height_at(probe.x, probe.z)
		if drop > deepest:
			deepest = drop
			best = s
	return best


## A bay. Level deck, retaining wall on the downhill side, cut face uphill.
func _landing(unit: Node3D, rec: Dictionary) -> void:
	var run: float = rec["run"]
	var waist: float = rec["waist"]
	_slab(
		unit,
		_at(run * 0.5, 0.0, -0.35),
		Vector3(waist, 0.70, run),
		C_TREAD,
		"deck"
	)
	_retain(unit, run, waist)
	if show_dressing:
		_parapet(unit, run, waist)


func _retain(unit: Node3D, run: float, waist: float) -> void:
	var drop := _drop_side(unit, run, waist)
	if drop == 0.0:
		return
	_slab(
		unit,
		_at(run * 0.5, drop * (waist * 0.5 + 0.22), -1.45),
		Vector3(0.44, 2.90, run),
		C_RETAIN,
		"retain"
	)


func _parapet(unit: Node3D, run: float, waist: float) -> void:
	var drop := _drop_side(unit, run, waist)
	if drop == 0.0:
		return
	_slab(
		unit,
		_at(run * 0.5, drop * (waist * 0.5 + 0.16), 0.34),
		Vector3(0.30, 0.68, run),
		C_CHEEK,
		"parapet"
	)


## CIVIC balustrade — the guild terrace reads as public space mainly through
## this, not through the steps.
func _balustrade(unit: Node3D, run: float, waist: float) -> void:
	for s in [-1.0, 1.0]:
		_slab(
			unit,
			_at(run * 0.5, s * (waist * 0.5 + 0.20), 0.06),
			Vector3(0.40, 1.04, run),
			C_CIVIC,
			"bala_%s" % ("r" if s > 0.0 else "l")
		)


## Cut sideways into the uphill rock. The floor is LEVEL ACROSS and follows the
## path's grade ALONG, which is what makes it free: no run is consumed, so the
## flights on either side keep the grade of the rock they are cut into.
func _alcove(unit: Node3D, rec: Dictionary) -> void:
	var run: float = rec["run"]
	var waist: float = rec["waist"]
	var up := float(rec["mid"]) - float(rec["sh0"])
	var depth := 2.8
	var uphill := -_drop_side(unit, run, waist)
	if uphill == 0.0:
		uphill = -1.0
	_slab(unit, _at(run * 0.5, 0.0, up - 0.30), Vector3(waist, 0.60, run), C_TREAD, "floor")
	# the recess: back wall plus two jambs, cut into the hill
	_slab(
		unit,
		_at(run * 0.5, uphill * (waist * 0.5 + depth * 0.5), up + 1.20),
		Vector3(depth, 3.40, run + 0.6),
		C_RETAIN,
		"alcove_back"
	)
	for s in [-1.0, 1.0]:
		_slab(
			unit,
			_at(run * 0.5 + s * (run * 0.5 + 0.25), uphill * (waist * 0.5 + depth * 0.5), up + 1.20),
			Vector3(depth, 3.40, 0.5),
			C_RETAIN,
			"alcove_jamb"
		)
	_slab(
		unit,
		_at(run * 0.5, uphill * (waist * 0.5 + 0.55), up + 0.22),
		Vector3(0.9, 0.44, run * 0.8),
		C_CIVIC,
		"bench"
	)


## Cantilevered sideways over the drop. The parapet is deliberately low: the
## point of this beat is that you can see down and see how far you have come.
func _balcony(unit: Node3D, rec: Dictionary) -> void:
	var run: float = rec["run"]
	var waist: float = rec["waist"]
	var up := float(rec["mid"]) - float(rec["sh0"])
	var out := _drop_side(unit, run, waist)
	if out == 0.0:
		out = 1.0
	var proj := 3.4
	_slab(
		unit,
		_at(run * 0.5, out * (waist * 0.5 + proj * 0.5), up - 0.30),
		Vector3(proj, 0.60, run),
		C_DECK,
		"cantilever"
	)
	# corbels beneath, so it reads as carried rather than floating
	for i in 3:
		_slab(
			unit,
			_at(run * (0.18 + 0.32 * float(i)), out * (waist * 0.5 + proj * 0.55), up - 1.30),
			Vector3(proj * 0.7, 1.60, 0.42),
			C_RETAIN,
			"corbel_%d" % i
		)
	_slab(
		unit,
		_at(run * 0.5, out * (waist * 0.5 + proj - 0.18), up + 0.34),
		Vector3(0.28, 0.76, run + 0.5),
		C_RAIL,
		"parapet"
	)


## A broken ancient door frame: two jambs, a fallen lintel.
func _gate(unit: Node3D, rec: Dictionary) -> void:
	var run: float = rec["run"]
	var waist: float = rec["waist"]
	for s in [-1.0, 1.0]:
		_slab(
			unit,
			_at(run * 0.5, s * (waist * 0.5 + 0.45), 1.55),
			Vector3(0.90, 4.10, 0.90),
			C_ANCIENT,
			"jamb_%s" % ("r" if s > 0.0 else "l")
		)
	_slab(
		unit,
		_at(run * 0.5 + 1.1, 0.9, 0.32),
		Vector3(1.30, 0.80, 4.60),
		C_ANCIENT,
		"lintel_fallen"
	)


func _rubble(unit: Node3D, rec: Dictionary, count: int) -> void:
	var run: float = rec["run"]
	var waist: float = rec["waist"]
	for i in count:
		var f := _h01(float(i) * 3.1 + rec["d0"])
		var g := _h01(float(i) * 7.7 + rec["d0"] * 0.3)
		var lat := (f - 0.5) * waist * 1.25
		var s := 0.30 + g * 0.55
		_slab(
			unit,
			_at(run * f, lat, s * 0.30),
			Vector3(s * 1.4, s, s),
			C_RUBBLE,
			"rub_%02d" % i,
			(_jitter(g) - 0.5) * 0.6
		)


func _shelf(unit: Node3D, rec: Dictionary) -> void:
	var run: float = rec["run"]
	var waist: float = rec["waist"]
	_slab(
		unit,
		_at(run * 0.5, 0.0, -0.55),
		Vector3(waist * 1.5, 1.10, run * 1.1),
		C_RETAIN,
		"slab"
	)
	_slab(
		unit,
		_at(run * 0.5, -0.9, 0.34),
		Vector3(1.7, 1.5, 1.4),
		C_RETAIN,
		"outcrop",
		-0.22
	)


## Ancient blocks. One upright, the rest toppled. Scale deliberately overshoots
## anything a person would carry.
func _fragments(unit: Node3D, rec: Dictionary) -> void:
	var run: float = rec["run"]
	var waist: float = rec["waist"]
	_slab(
		unit,
		_at(0.0, -(waist * 0.5 + 0.5), 0.8),
		Vector3(1.0, 2.6, 1.0),
		C_ANCIENT,
		"marker_upright"
	)
	var spots := [[0.25, 0.8, 0.9, 2.2], [0.55, -0.9, 0.7, 1.7], [0.78, 0.5, 1.1, 2.9]]
	for i in spots.size():
		var sp: Array = spots[i]
		_slab(
			unit,
			_at(run * float(sp[0]), float(sp[1]) * waist * 0.5, float(sp[2]) * 0.5),
			Vector3(float(sp[3]), float(sp[2]), 1.5),
			C_ANCIENT,
			"block_%d" % i,
			(_jitter(float(sp[0]) * 5.0) - 0.5) * 0.35
		)


func _kerb(unit: Node3D, rec: Dictionary) -> void:
	if not show_dressing:
		return
	var run: float = rec["run"]
	var waist: float = rec["waist"]
	for s in [-1.0, 1.0]:
		_slab(
			unit,
			_at(run * 0.5, s * (waist * 0.5 + 0.12), -0.05),
			Vector3(0.26, 0.34, run),
			C_RETAIN,
			"kerb_%s" % ("r" if s > 0.0 else "l")
		)


## The ruins forecourt: pavement, ruined wall stubs, the beacon footing.
func _arrival(unit: Node3D, which: int, rec: Dictionary) -> void:
	var run: float = rec["run"]
	var waist: float = rec["waist"]
	var civic := which == GUILD_ROUTE
	if civic:
		_slab(unit, _at(run * 0.5, 0.0, -0.30), Vector3(waist, 0.60, run), C_CIVIC, "paving")
		_balustrade(unit, run, waist)
		# The axis terminator: the guild frontage, dead ahead.
		_slab(unit, _at(run + 1.4, 0.0, 3.4), Vector3(14.0, 7.6, 2.2), C_CIVIC, "guild_front")
		return
	_slab(unit, _at(run * 0.5, 0.0, -0.30), Vector3(waist * 1.6, 0.60, run), C_TREAD, "paving")
	for i in 5:
		var f := 0.12 + 0.18 * float(i)
		var s := 1.0 if i % 2 == 0 else -1.0
		_slab(
			unit,
			_at(run * f, s * (waist * 0.75 + 1.2), 0.85 + 0.5 * float(i % 3)),
			Vector3(1.1, 2.2 + 1.2 * float(i % 3), 3.6),
			C_ANCIENT,
			"wall_%d" % i
		)
	_slab(unit, _at(run * 0.62, 0.0, 0.9), Vector3(3.2, 2.4, 3.2), C_ANCIENT, "beacon_foot")


# =============================================================================
# Look-back decks (brief §6) — measured, not guessed
# =============================================================================
#
# tools/audit_ascent.gd casts a ray from every station back to the market, the
# bell tower, the river and the guild. Result: the corridor itself is blocked
# to the town by 0.6-1.8 m for its first 90 m, and the blocker sits just 11-60 m
# away — a local hump, not a mountain. The deck search then shows +2.0 m reopens
# market + river + guild + tower simultaneously.
#
# So the early look-back is a 2 m stone platform, exactly the way V1 turned out
# to be a shelf: when a view is short by a metre or two, the answer is a
# structure, not a landform.
const DECK_DIST := 76.0
const DECK_RISE := 2.0
const DECK_SIZE := 5.0


func _build_decks() -> void:
	if not show_decks:
		return
	var root := Node3D.new()
	root.name = "Decks"
	add_child(root)
	var pts := route_for(CLIFF_ROUTE)
	var p := MistvaleHeights.route_at(pts, DECK_DIST)
	var t := MistvaleHeights.route_tangent(pts, DECK_DIST)
	var g := MistvaleHeights.height_at(p.x, p.y)
	var out := 1.0 if (
		MistvaleHeights.height_at(p.x - t.y * 4.0, p.y + t.x * 4.0) < g
	) else -1.0
	var n := Node3D.new()
	n.name = "L1_MileStoneDeck"
	n.position = Vector3(p.x, g, p.y)
	n.rotation.y = atan2(-t.x, -t.y)
	root.add_child(n)
	_slab(
		n,
		_at(0.0, out * (DECK_SIZE * 0.5 + 0.6), DECK_RISE - 0.30),
		Vector3(DECK_SIZE, 0.60, DECK_SIZE),
		C_DECK,
		"deck"
	)
	for i in 4:
		var a := TAU * float(i) / 4.0
		_slab(
			n,
			_at(
				sin(a) * DECK_SIZE * 0.45,
				out * (DECK_SIZE * 0.5 + 0.6) + cos(a) * DECK_SIZE * 0.45,
				DECK_RISE + 0.30
			),
			Vector3(0.22, 1.10, 0.22),
			C_RAIL,
			"deck_post_%d" % i
		)
	_slab(
		n,
		_at(0.0, out * (DECK_SIZE + 0.5), DECK_RISE + 0.72),
		Vector3(0.18, 0.18, DECK_SIZE),
		C_RAIL,
		"deck_rail"
	)
	# the two corbels that carry it, so it does not read as floating
	for s in [-1.0, 1.0]:
		_slab(
			n,
			_at(s * DECK_SIZE * 0.30, out * (DECK_SIZE * 0.45 + 0.6), -0.90),
			Vector3(0.7, 2.00, 0.7),
			C_RETAIN,
			"deck_corbel_%s" % ("r" if s > 0.0 else "l")
		)


# =============================================================================
# Helpers
# =============================================================================

static func _h01(n: float) -> float:
	var s := sin(n * 127.1 + 311.7) * 43758.5453
	return s - floor(s)


static func _jitter(n: float) -> float:
	return _h01(n)


func _mat(color: Color, alpha: float = 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(color.r, color.g, color.b, alpha)
	m.roughness = 0.95
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m
