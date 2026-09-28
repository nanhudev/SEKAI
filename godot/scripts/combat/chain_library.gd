extends RefCounted
class_name ChainLibrary
# Builds 缚星链 / STAR-BIND CHAIN in code, the same way SwordMovesetLibrary builds
# the sword styles, so the weapon is data and the director never branches on an id.
#
# PHASE 0–1 ONLY. The brief is explicit about what is not here yet: no second
# chain, no wrapping around the body, no rope knots, no climbing, no traversal,
# no ultimate, no signature ceremony. The whole point of this resource is to
# answer one question — IS THE CHAIN FUN? — with a single chain.
#
# The prototype's structures, per brief §2:
#   HANDLE  →  CHAIN  →  TERMINAL HEAD (刃锤 / Anchor Blade)
# The head is between a weighted metal head and a short cutting edge, so the
# weapon can slam, cut, hook and pull instead of only whipping.

const CHAIN_STAR_BIND := &"star_bind"


static func _move(id: StringName, display_name: String, params: Dictionary) -> ChainMove:
	var move := ChainMove.new()
	move.id = id
	move.display_name = display_name
	for key in params:
		move.set(key, params[key])
	return move


static func ids() -> Array[StringName]:
	return [CHAIN_STAR_BIND]


static func build(chain_id: StringName = CHAIN_STAR_BIND) -> ChainMoveset:
	return star_bind()


static func star_bind() -> ChainMoveset:
	var chain := ChainMoveset.new()
	chain.id = CHAIN_STAR_BIND
	chain.display_name = "缚星链 · STAR-BIND CHAIN"
	# FORM I · 实链. The prototype is the WEIGHT answer: it owns the weight table, the
	# impact cost and the haul, and none of those are scaffolding to be replaced —
	# they are what this form IS. 游链 (§6) and 律链 (§12) are separate resources,
	# not bigger versions of this one.
	chain.form_name = "实链"
	chain.form_id = &"solid"

	var moves: Dictionary = {}

	# ---------------------------------------------------------------- Light 1
	# 横缚 · fast, wide, medium damage, low precision. 145° authored from -72.5
	# so the arc is centred on where the player is facing: you aim the middle of
	# the sweep, not its start.
	moves[&"ch_sweep"] = _move(&"ch_sweep", "横缚", {
		"path": ChainMove.Path.ARC,
		"note": "快速甩出，范围明显大于剑。密度低，准度低，可被移动取消。",
		"startup": 0.14, "active": 0.20, "recovery": 0.20,
		"damage": 16.0, "poise_damage": 16.0, "impulse": 2.0,
		"start_azimuth_degrees": -72.5, "arc_degrees": 145.0,
		"radius_from": 2.5, "radius_to": 3.4,
		"height_from": 1.20, "height_to": 1.05,
		# §8: WHIP, not OUT — the first cut has to hand the second one a chain that
		# is still travelling. See ChainMove.Ease.WHIP.
		"ease": ChainMove.Ease.WHIP, "ease_power": 2.2,
		"momentum_gain": 0.30, "momentum_whiff_cost": 0.14, "steer": 0.35,
		# A wide sweep is the CHEAPEST way to spend spin: it is meant to be used on
		# crowds and light bodies, and its landing cost is small enough that a
		# three-cut chain against light enemies still comes out ahead on momentum.
		"impact_momentum_cost": 0.05, "impact_hitstop": 0.032, "impact_deflect_degrees": 5.0,
		"camera_trauma": 0.04, "fov_kick": -1.0, "roll_kick": 0.9,
	})

	# ---------------------------------------------------------------- Light 2
	# 返扫 · the second cut has to CARRY the first one's momentum. It starts where
	# the head already is and unwinds the other way, so the chain is never still
	# between the two — no reset, no teleport, no second wind-up.
	moves[&"ch_return"] = _move(&"ch_return", "返扫", {
		"path": ChainMove.Path.ARC,
		"note": "第一击结束不回收链头，利用惯性反方向再扫一次。WHOOOSH → carry. 这一击的伤害来自上一击还没停下。",
		"startup": 0.10, "active": 0.19, "recovery": 0.19,
		"damage": 18.0, "poise_damage": 18.0, "impulse": 2.2,
		"continue_from_head": true, "arc_degrees": -150.0,
		# §7 CARRY. 26° of overrun BEFORE the reverse, and the radius opens while
		# it happens: the head keeps going the way cut 1 threw it, the chain goes
		# slack, and only then does the return sweep reel it back. That is §3's
		# loose → tighten → straight spent on a CUT instead of only on a throw —
		# and it is the difference between 返扫 BEING the second beat and being a
		# second swing that happens to start nearby.
		"carry_anticipation_degrees": 26.0,
		"radius_from": 3.72, "radius_to": 3.9,
		"height_from": 1.05, "height_to": 1.00,
		# WHIP as well, and for the same reason: 返扫 carries the head through into
		# the slam instead of stopping in front of it.
		"ease": ChainMove.Ease.WHIP, "ease_power": 2.4,
		"momentum_gain": 0.34, "momentum_whiff_cost": 0.12, "steer": 0.38,
		"impact_momentum_cost": 0.05, "impact_hitstop": 0.032, "impact_deflect_degrees": 5.0,
		"camera_trauma": 0.05, "fov_kick": -1.1, "roll_kick": -1.1,
	})

	# ---------------------------------------------------------------- Light 3
	# 下砸 · the chain shortens its radius and comes down overhead. The payoff of
	# 横/横/纵 is that the third cut is a DIFFERENT AXIS, not a bigger number.
	moves[&"ch_slam"] = _move(&"ch_slam", "下砸", {
		"path": ChainMove.Path.SLAM,
		"note": "收短半径后过顶下砸。是纵的答案，不是更大的伤害 —— 前两击都在一个平面上，这一击换了轴。",
		"startup": 0.20, "active": 0.15, "recovery": 0.34,
		"damage": 26.0, "poise_damage": 30.0, "impulse": 2.6,
		"arc_degrees": 0.0,
		"radius_from": 3.9, "radius_to": 2.1,
		"peak_height": 2.55, "height_from": 2.55, "height_to": 0.42,
		"ease": ChainMove.Ease.IN, "ease_power": 2.0,
		"momentum_gain": 0.22, "momentum_whiff_cost": 0.20, "steer": 0.18,
		"momentum_speed_scale": 0.30,
		# 下砸 is where the weight is: the biggest stop and the biggest bend of the
		# three-cut chain, so the third cut is a different AXIS *and* a different
		# kind of impact.
		"impact_momentum_cost": 0.09, "impact_hitstop": 0.055, "impact_deflect_degrees": 7.0,
		"camera_trauma": 0.10, "fov_kick": -2.0,
	})

	# ------------------------------------------------------- Heavy: orbit 甩星
	# Release of the orbit. Radius always reaches the limit: a properly thrown
	# chain ALWAYS ends up taut, and that is how the player meets TENSION without
	# ever being told it exists.
	moves[&"ch_launch"] = _move(&"ch_launch", "甩星", {
		"path": ChainMove.Path.RADIAL,
		"note": "蓄势回旋的释放。蓄得越久，链头越快越重；提前释放更早到，但更轻。链头必然到达最大半径 —— 扔出去的链一定绷紧。",
		"startup": 0.06, "active": 0.44, "recovery": 0.34,
		"damage": 22.0, "poise_damage": 26.0, "impulse": 3.0,
		"arc_degrees": 0.0,
		"radius_from": 3.3, "radius_to": 4.6,
		"height_from": 1.10, "height_to": 1.05,
		"ease": ChainMove.Ease.OUT, "ease_power": 1.8,
		"momentum_gain": 0.10, "momentum_whiff_cost": 0.10, "steer": 0.50,
		"impact_momentum_cost": 0.07, "impact_hitstop": 0.050, "impact_deflect_degrees": 6.0,
		"camera_trauma": 0.09, "fov_kick": 2.4,
	})

	# ------------------------------------------------------------ Taut: Light
	# 绷切 · the chain is stretched to its limit; this cuts back ALONG that line.
	# It exists only while taut, which is what makes pressure a resource.
	moves[&"ch_snap"] = _move(&"ch_snap", "绷切", {
		"path": ChainMove.Path.RADIAL,
		"note": "沿绷紧方向快速切回。只在链绷紧时可用 —— 压力本身是资源。",
		"startup": 0.05, "active": 0.14, "recovery": 0.20,
		"damage": 24.0, "poise_damage": 26.0, "impulse": 2.4,
		"continue_from_head": true, "arc_degrees": 0.0,
		"radius_from": 4.6, "radius_to": 1.30,
		"height_from": 1.05, "height_to": 1.10,
		"ease": ChainMove.Ease.IN, "ease_power": 1.6,
		"momentum_gain": 0.16, "momentum_whiff_cost": 0.0, "steer": 0.45,
		"requires_taut": true,
		"impact_momentum_cost": 0.06, "impact_hitstop": 0.045, "impact_deflect_degrees": 5.5,
		"camera_trauma": 0.07, "fov_kick": -1.6, "roll_kick": 1.4,
	})

	# ------------------------------------------------------------ Taut: Heavy
	# 曳 · pull the thing the chain is connected to, or pull yourself to it.
	# Which one happens is the weight table's decision, not a special case here.
	moves[&"ch_yank"] = _move(&"ch_yank", "曳", {
		"path": ChainMove.Path.RADIAL,
		"note": "拉目标 / 拉自己。谁被拉动由重量决定，不由招式决定 —— 重型敌人是你的锚。",
		"startup": 0.10, "active": 0.20, "recovery": 0.26,
		"damage": 8.0, "poise_damage": 20.0, "impulse": 1.0,
		"continue_from_head": true, "arc_degrees": 0.0,
		"radius_from": 4.6, "radius_to": 3.6,
		"height_from": 1.05, "height_to": 1.05,
		"ease": ChainMove.Ease.OUT, "ease_power": 2.0,
		"momentum_gain": 0.0, "momentum_whiff_cost": 0.0, "steer": 0.60,
		"requires_taut": true, "pulls": true,
		"impact_momentum_cost": 0.04, "impact_hitstop": 0.030, "impact_deflect_degrees": 3.0,
		"camera_trauma": 0.08, "fov_kick": -2.6,
	})

	# ------------------------------------------------------------------- Hook
	# 缠锁 · thrown forward. Hitting something that can be hooked ATTACHES the
	# chain to it; hitting a wall costs the spin; hitting nothing leaves a taut
	# line hanging in the air, which is still a place the player can act from.
	moves[&"ch_hook"] = _move(&"ch_hook", "缠锁", {
		"path": ChainMove.Path.RADIAL,
		"note": "向前抛出链头。命中可钩目标即挂住；命中墙则掉速回收。",
		"startup": 0.16, "active": 0.26, "recovery": 0.30,
		"damage": 6.0, "poise_damage": 8.0, "impulse": 1.4,
		"arc_degrees": 0.0,
		"radius_from": 1.9, "radius_to": 4.6,
		"height_from": 1.15, "height_to": 1.15,
		"ease": ChainMove.Ease.OUT, "ease_power": 1.4,
		"momentum_gain": 0.0, "momentum_whiff_cost": 0.0, "steer": 0.80,
		"hooks": true,
		"momentum_speed_scale": 0.0,
		# THE ONLY MOVE THAT GOES WHERE YOU LOOK (§13). It is the throw: a chain is
		# released toward the aim, so looking up has to put the head up — otherwise
		# nothing raised (a gantry, a ruin ring, a tree limb) is ever hookable, and
		# FORM II's whole subject is anchoring onto exactly those.
		"aim_pitch_scale": 1.0,
		"camera_trauma": 0.03, "fov_kick": 0.8,
	})

	# ---------------------------------------------------- Bound: Light / Heavy
	# 拉近斩 · the chain is already wound around the target, so this is the cut
	# that is only available BECAUSE 缚 happened.
	moves[&"ch_pull_cut"] = _move(&"ch_pull_cut", "拉近斩", {
		"path": ChainMove.Path.RADIAL,
		"note": "快速收链，链头在返回途中攻击。只有缚住之后才存在。",
		"startup": 0.07, "active": 0.16, "recovery": 0.22,
		"damage": 22.0, "poise_damage": 22.0, "impulse": 2.0,
		"continue_from_head": true, "arc_degrees": 0.0,
		"radius_from": 4.6, "radius_to": 1.35,
		"height_from": 1.05, "height_to": 1.10,
		"ease": ChainMove.Ease.IN, "ease_power": 1.5,
		"momentum_gain": 0.18, "momentum_whiff_cost": 0.0, "steer": 0.35,
		"releases_hook": true,
		"impact_momentum_cost": 0.06, "impact_hitstop": 0.040, "impact_deflect_degrees": 5.0,
		"camera_trauma": 0.08, "fov_kick": -1.8, "roll_kick": 1.0,
	})

	# 地砸 · the heavy exit. Uses the chain to put a light enemy into the floor.
	moves[&"ch_ground_slam"] = _move(&"ch_ground_slam", "地砸", {
		"path": ChainMove.Path.SLAM,
		"note": "利用链把敌人砸向地面。削势刻意压在 35 以下 —— 单靠链砸不出脆化，配上冰才成立。",
		"startup": 0.14, "active": 0.20, "recovery": 0.34,
		"damage": 30.0, "poise_damage": 32.0, "impulse": 2.4,
		"arc_degrees": 0.0,
		"radius_from": 2.0, "radius_to": 1.30,
		"peak_height": 1.85, "height_from": 1.85, "height_to": 0.40,
		"ease": ChainMove.Ease.IN, "ease_power": 1.8,
		"momentum_gain": 0.10, "momentum_whiff_cost": 0.16, "steer": 0.20,
		"pulls": true, "releases_hook": true, "momentum_speed_scale": 0.25,
		"impact_momentum_cost": 0.09, "impact_hitstop": 0.070, "impact_deflect_degrees": 7.5,
		"camera_trauma": 0.13, "fov_kick": -2.4,
	})

	# ---------------------------------------------------------------- Guard
	# 拨链 · DEFLECT SWING. A short arc in front of the body that sweeps an
	# attack aside. Deliberately NOT a sword parry: there is no clash of blades,
	# the trajectory is disturbed. Visually and mechanically different on purpose.
	moves[&"ch_deflect"] = _move(&"ch_deflect", "拨链", {
		"path": ChainMove.Path.ARC,
		"note": "防御：在身前扫出短弧，把轻攻击拨开。不是剑式格挡 —— 没有碰撞，只有被改变的轨迹。重击拨不动。",
		"startup": 0.06, "active": 0.22, "recovery": 0.20,
		"damage": 0.0, "poise_damage": 0.0, "impulse": 0.0,
		"start_azimuth_degrees": -55.0, "arc_degrees": 110.0,
		"radius_from": 1.05, "radius_to": 1.65,
		"height_from": 1.10, "height_to": 1.05,
		"ease": ChainMove.Ease.OUT, "ease_power": 2.0,
		"momentum_gain": 0.0, "momentum_whiff_cost": 0.0, "steer": 0.20,
		"deflects": true,
		# A guard arc does not land on anything: it is not a strike, so it pays
		# nothing for a contact it never makes.
		"impact_momentum_cost": 0.0, "impact_hitstop": 0.0, "impact_deflect_degrees": 0.0,
		"camera_trauma": 0.0, "fov_kick": -0.8, "roll_kick": 0.6,
	})

	# The orbit's own hit profile. Not selectable: the player never "plays" the
	# orbit, they hold it, and this is what it does while held.
	var orbit := _move(&"ch_orbit", "回旋", {
		"path": ChainMove.Path.ARC,
		"note": "蓄势期间链头本身是危险的。",
		"startup": 0.0, "active": 1.0, "recovery": 0.0,
		"damage": chain.orbit_damage, "poise_damage": chain.orbit_poise, "impulse": 2.4,
		"arc_degrees": 360.0,
		"radius_from": chain.orbit_radius, "radius_to": chain.orbit_radius,
		"height_from": chain.orbit_height, "height_to": chain.orbit_height,
		"ease": ChainMove.Ease.LINEAR, "ease_power": 1.0,
		"momentum_gain": 0.0, "momentum_whiff_cost": 0.0, "steer": 0.0,
		# THE ORBIT IS THE ONE THING THAT MUST NOT PAY FOR ITS HITS. It lands every
		# orbit_hit_interval seconds by design, so any per-hit spin cost would turn
		# holding Heavy against a crowd into a race the player loses. What it gets
		# instead is a tick of stop — the grind of links across armour.
		"impact_momentum_cost": 0.0, "impact_hitstop": 0.015, "impact_deflect_degrees": 2.0,
		"camera_trauma": 0.0, "fov_kick": 0.0,
	})
	moves[&"ch_orbit"] = orbit

	chain.moves = moves
	return chain
