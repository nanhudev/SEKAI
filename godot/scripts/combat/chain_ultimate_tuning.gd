extends Resource
class_name ChainUltimateTuning
# 缚星链 · I 技能 / ULTIMATE — VOID ANCHOR · REALITY SHEET RIP · MANGA TEAR
#
# 一条链, 一次突刺, 一块被扯下来的现实.
#
# ---------------------------------------------------------------------------
# WHAT THIS IS AND WHAT IT IS NOT
# ---------------------------------------------------------------------------
#
# The brief's sentence, which is the whole design: the player drives the trident
# head forward into an anchor that is NOT a physical object — it is a point the
# RULE generates — and then uses that point to drag the space in front of them
# off the surface of the world like a sheet of cloth.
#
# So the thing being cut is not the ENEMY and it is not the WORLD. It is a piece
# of the world's own SURFACE, taken off in one piece, floating, and then cut to
# pieces while it hangs there. The enemy is what is standing behind it.
#
# WHAT IS DELIBERATELY ABSENT (brief §二.1 — 不要真实物理模拟):
#   · no rope physics, no cloth simulation, no fracture simulation as the driver
#   · no free-drawn player strokes in this pass (brief §五.3)
# Every quantity below is a NUMBER and every one of them is a pure function of
# the ceremony clock. Nothing in this ceremony integrates anything over time.
#
# ---------------------------------------------------------------------------
# THE CLOCK DISCIPLINE (this is why the file is shaped this way)
# ---------------------------------------------------------------------------
#
# PAST4's renderer taught this line the hard way: a director that ACCUMULATES
# state cannot be scrubbed. Rendering one frame at t=5.70 from a shot list and
# rendering it as frame 183 of a continuous take gave frames that differed in
# 55,000 pixels — because the second one had arrived at 5.70 by walking through
# everything before it and the first one had simply been told it was 5.70.
#
# So: `evaluate(t)` in the director is a PURE FUNCTION. Every number here is
# derived from `t` and from nothing else. The ceremony can be entered at any
# time, in any order, and the picture is the same picture. That is also the only
# version of this that is worth authoring, because it means a key frame can be
# re-rendered without re-rendering the take.
#
# ---------------------------------------------------------------------------
# THE NINE BEATS (brief §三 — 第一版必须严格按此实现)
# ---------------------------------------------------------------------------
#
#   0.00  PHASE 0  · 起手      the FOV closes, the world's sound drops away.
#                              Nothing has happened yet. That is the point.
#   0.15  PHASE 1  · 前刺      straight, fast, unadorned. 直、狠、准.
#   0.45  PHASE 2  · 命中锚点  the head does not fly through — it STOPS DEAD.
#   0.65  PHASE 3  · 绕两圈    exactly two turns, tightening. The ritual.
#   1.25  PHASE 4  · 扯膜      the core. Irregular, soft-edged, not a rectangle.
#   1.85  PHASE 5  · 漂浮      a beat of nothing, so the eye can learn the object.
#   2.15  PHASE 6  · 斩碎      the trident becomes a blade-pen. Five cuts.
#   2.85  PHASE 7  · 漫画撕裂  torn open along the cuts. White edge, ink line.
#   3.20  PHASE 8  · 恢复      the world is handed back, and it is the same world.
#
# ---------------------------------------------------------------------------
# WHAT IS *NOT* TUNED HERE, ON PURPOSE
# ---------------------------------------------------------------------------
#
# Nothing about the enemy. The brief §五.1 asks for a single-target prototype and
# §五.2 says the anchor does not have to land on anything real. Damage is one
# number, applied once, at the tear; where it lands is the director's business.

# ===========================================================================
# 0 · TIMELINE
# ===========================================================================
# One place. A time that is written down twice is a time that will disagree with
# itself, and the debug strip in `tools/chain_ultimate_renderer.gd` reads these
# fields directly so the strip cannot go stale against them.

@export_group("A · Timeline")
@export var t_thrust_start := 0.15
@export var t_bite := 0.45
@export var t_coil_start := 0.65
@export var t_pull_start := 1.25
@export var t_float_start := 1.85
@export var t_cut_start := 2.15
@export var t_tear_start := 2.85
@export var t_restore_start := 3.20
@export var t_end := 3.55

# How long the head takes to LAND once it has been thrown. 0.30 is the brief's
# 0.15 -> 0.45 and it is authored as an ARRIVAL TIME rather than a speed, because
# the read that matters is "it is there before you can doubt it", not "X m/s".
@export var thrust_travel := 0.30
# The bite. The head stops AT the anchor over this long and then drives a few
# centimetres PAST it — the same beat 缚星链 already uses for a wall (§19 of the
# chain brief), reused so the two weapons speak one language about stopping.
@export var bite_time := 0.10

# ===========================================================================
# 1 · THE VOID ANCHOR
# ===========================================================================
#
# 它看起来像一个局部压缩的空间核心. Not a sci-fi UI orb (brief §二.2 explicitly
# forbids it), not a magic fireball. What it is: a small sphere of space that has
# been squeezed, with the compression's own stress rings standing in it, and the
# trident through the middle of it.

@export_group("B · Void Anchor")
# 6m in front, which the brief allows as "5-8m, adjusted for terrain". The number
# matters for one reason: the sheet is 2.2m across and the camera must be able to
# hold BOTH the anchor and the player's own hand in one frame at 75 degrees.
@export var anchor_distance := 6.0
# Lifted this far above the eye line. A core exactly on the crosshair reads as a
# UI reticle, so it goes slightly high. Small, because the film now covers the
# whole frame (see `sheet_radius`) and its own lower edge is nowhere near the
# floor — the composition question the old value was solving no longer exists.
@export var anchor_rise := 0.30
@export var anchor_radius := 0.34
# The core's own inward pull, in metres of surface displacement. Small: this is a
# core under stress, not a black hole.
@export var anchor_implode := 0.085
@export var anchor_ring_width := 0.035

# ===========================================================================
# 2 · THE COIL — 绕两圈, 不多不少
# ===========================================================================
#
# The brief is explicit that the two turns are a RITUAL, not a wind-up: they are
# what separates "the chain hit something" from "the chain has established a rule
# around a point". So the count is a fact the tests check, not a style choice.

@export_group("C · The Coil")
# EXACTLY this many turns. `tests/chain_ultimate_integration.gd` asserts the
# director's integral of d(angle)/dt over the coil window is 2.000 turns, so this
# number cannot be quietly changed into 1.9.
@export var coil_turns := 2.0
# The head's orbit radius while it is winding, as a fraction of the anchor's own
# radius. It starts WIDE (the head is still out at the end of its throw) and
# closes to this, which is what 越缠越紧 has to mean geometrically: if the orbit
# radius stayed constant, two turns of it would be a hoop, not a wrap.
@export var coil_radius_start := 0.86
@export var coil_radius_end := 0.30
# Every turn is slightly faster than the one before it. 1.0 would be a metronome;
# 1.55 makes the second turn arrive before the eye predicts it, which is where the
# "力量和张力在累积" read actually comes from.
@export var coil_accel := 1.55
# Total angle the rope itself turns through on its way out, in degrees, as the
# chain wraps. Visual only — it is fed to the chain drawing, never to a solver.
@export var coil_wrap_degrees := 620.0

# ===========================================================================
# 3 · THE REALITY SHEET — 整招是否高级的关键
# ===========================================================================
#
# THREE THINGS THE BRIEF ASKS FOR AND THE THREE NUMBERS THAT OWN THEM:
#
#   A · IT IS NOT A RECTANGLE.  `sheet_radius` is modulated per angle by two
#       octaves, so the silhouette is organic. `sheet_lobe` is how far the
#       outline may wander as a FRACTION of the radius — at 0.18 the outline
#       moves by up to 40cm on a 2.2m sheet, which is the difference between a
#       torn membrane and a disc.
#
#   B · IT IS NOT A HARD GLASS PANE.  `sheet_warp` bends the surface out of
#       plane and `sheet_ripple` runs travelling tension waves across it. Glass
#       holds a plane; a membrane does not.
#
#   C · IT IS 2D-ISED.  The sheet is a FLAT piece of the world's surface, lifted
#       off. Its thickness is zero by construction and it stays zero — the
#       volume read comes from the rim curl (`sheet_curl`), where the edge of the
#       sheet bends back toward the viewer like the lip of a pulled-off film.

@export_group("D · The Reality Sheet")
# ---------------------------------------------------------------------------
# THE FILM IS A PATCH OF THE WORLD, AND THE WORLD IS WHAT PROVES IT WAS THERE.
#
# V1 SAID THE OPPOSITE AND THE USER REJECTED IT BY NAME. V1's rule was "the film
# is the ENTIRE VIEW, taken off in one piece", and it was implemented faithfully:
# at the rip the film filled the frame, the room was hidden for the length of the
# breach, and the contraction opened black around the film's rim. The verdict on
# that render was
#
#     黑色不规则 Iris / Screen Mask
#     ——「玩家没有看懂"我把现实扯下来了一张"」
#
# and the reading is exact, not a matter of taste. Room off + film covering the
# frame + film contracting leaves every pixel outside the contracted film as void,
# which is a BORDER AROUND A WINDOW. Nothing about it says "this came off
# something", because nothing around it is left for it to have come off of.
#
# SO THE FILM IS A PATCH, AND THE WORLD STAYS. The user's own numbers, in one
# breath: 「玩家仍然看到完整训练场。但前方约 35-55% 视野面积的一块现实，被三叉头 +
# 锁链从世界表面 PEEL OFF」. Two ends, and this number is chosen to land both:
#
#   AT THE RIP    the patch's bounding ellipse is ~24% of the frame's area — big
#                 enough that its absence is unmistakably a missing piece, small
#                 enough that the room is legible all the way around it.
#   AT THE HOLD   it has been hauled toward the player (see `sheet_pull_distance`)
#                 where the same patch covers ~41%, the middle of the user's band.
#
# Both ends are measured rather than asserted: `ChainUltimateLab.film_frame_coverage`
# warns when either leaves its band, and `tests/chain_ultimate_integration.gd` §3
# takes the tight measurement off the built mesh.
@export var sheet_radius := 2.60
# ---------------------------------------------------------------------------
# AND IT NO LONGER CONTRACTS. THIS IS THE OTHER HALF OF DELETING THE IRIS.
#
# The contraction was V1's only way to expose the void, and its argument was
# geometrically airtight: a film hauled toward the player only ever gets BIGGER on
# screen, so motion alone can never reveal what is behind it — the rim has to come
# in. That is true. It is also the wrong answer, because the rim coming in is what
# BOUNDS the picture, and the bounded picture is a window.
#
# V2 exposes the wound the other way: THE FILM LEAVES SIDEWAYS. It travels toward
# the player and down-and-across (see `sheet_drift`), so the place it came from
# stops being hidden behind it and starts being visible BESIDE it. The wound is
# then readable not because the film shrank but because the film moved off it —
# which is also, incidentally, what pulling a sheet off something actually looks
# like.
#
# 1.0 means no contraction at all. The field is KEPT rather than deleted because
# `sheet_contract_at` is the single owner of this quantity, and a second reader
# reaching for `sheet_radius` directly is the class of bug this project keeps a
# standing rule about; at 1.0 every existing reader agrees by construction.
@export var sheet_contract_end := 1.0
# ---------------------------------------------------------------------------
# AND IT IS NOT ROUND. THE ASPECT IS A COMPOSITION NUMBER, NOT A STYLE ONE.
#
# MEASURED, because the first version of this was a circle (1, 1) and it was
# wrong for a reason that has nothing to do with taste: at fov 70 the frame is
# 1.778 times as wide as it is tall, so an aspect of 1.0 covers 1.78 times as much
# of the picture's HEIGHT as of its WIDTH. A tall narrow sliver is a shard, not a
# sheet, and no amount of outline noise fixes a shape whose proportions are wrong.
#
# THE ASPECT IS THEREFORE THE FRAME'S OWN, plus a little: 1.55 / 0.85 = 1.824
# against the frame's 1.778. Slightly wider than a screen, so it cannot be mistaken
# for a crop of one, and close enough that it grows on both axes at once. The brief
# allows it explicitly: 可以近似椭圆 / 泪滴 / 软布片, but NOT 规整.
@export var sheet_aspect := Vector2(1.55, 0.85)
# How far the outline wanders, as a fraction of the radius. See above.
@export var sheet_lobe := 0.185
# Lobe frequencies. The low one gives the sheet a big asymmetric TEAR shape (one
# long side, one short); the high one gives it its ragged edge. Both are needed:
# the low one alone reads as a blob, the high one alone reads as a buzzsaw.
@export var sheet_lobe_low := 2.0
@export var sheet_lobe_high := 7.0
@export var sheet_warp := 0.075
@export var sheet_ripple := 0.022
@export var sheet_ripple_hz := 3.1
@export var sheet_curl := 0.30
# Where the edge stops being opaque. A fifth of the radius was a soft blob with
# no silhouette at all: the whole question of this effect is "is this a THING that
# came off the world", and a thing with no edge cannot be one.
#
# IT WAS 0.90 AND THAT WAS STILL SOFT ENOUGH TO BE A GLOW. The film covers the
# whole frame at the rip, so a fringe measured in fractions of the radius is a
# fringe measured on the film's BUILT radius (9m) — a 10% fade is 90cm of material,
# which at the float's contracted size is a 40-pixel halo the eye reads as bloom
# rather than as the edge of a piece of something. 0.94 leaves 6% — about 18px
# there — which is still a soft edge and is no longer a light.
@export var sheet_edge_inner := 0.94
@export var sheet_edge_soft := 0.10
# ---- the peel -------------------------------------------------------------
# The sheet is not teleported off the world. It comes away along a DIRECTION: the
# lower edge lets go first and the tear travels upward, which is the difference
# between "a layer peeled off" and "a picture that faded in".
@export var peel_time := 0.34
@export var peel_tilt := 0.55
# How far toward the player the film is hauled once it is free, in metres. This is
# the NODE's travel — the whole film as a body — and it does two jobs now: it is
# what grows the patch from ~24% of the frame to ~41%, and it is what separates
# the film from its own wound in DEPTH.
#
# IT IS NOT THE PEEL, and the two used to both be called "the pull". See
# `sheet_peel_slide` for the other half of it.
@export var sheet_pull_distance := 1.50
# AND IT GOES ASIDE, WHICH IS THE WHOLE REASON THE WOUND IS EVER VISIBLE.
#
# In the camera's own axes: x is right, y is UP, so a negative y drifts the film
# downward. Read the pair as a sentence — it is dragged toward the player, across
# to the right and DOWN, so the piece of world it came off is left standing above
# and to the left of it.
#
# WHY THE LATERAL TERM IS NOT OPTIONAL, AND WHY IT IS THIS BIG. Toward-the-player
# alone makes the film bigger while keeping it concentric with its wound, so a
# film covering 40% of the frame sits exactly on top of a wound covering 24% and
# hides it COMPLETELY — the hero frame would show a floating sheet over an intact
# world, which is the one thing the user says a single still has to make readable.
#
# But the film also grows as it comes closer, so it is always bigger than the hole
# it came out of, and clearing that hole entirely is not available: it would need a
# 6-7m offset, which puts the film off the side of the screen. The composition is
# therefore a TRADE, and these two numbers are the solved end of it — swept over
# forward travel, lateral and vertical drift, and picked on three constraints at
# once:
#
#   the wound is 47% exposed    — a large irregular bite of missing world, with the
#                                 film readable as the thing that fills it
#   the film is 83% on screen   — and 100% within the frame horizontally, so the
#                                 five cuts that follow land on material
#   the hold is 40% of frame    — the middle of the user's 35-55% band
#
# (Computed for the 70-degree frame the ceremony holds; the numbers go stale if
# `anchor_distance`, `sheet_radius`, `fov_close` or `sheet_pull_distance` move, and
# `ChainUltimateLab.film_frame_coverage` is the live reading.)
@export var sheet_drift := Vector2(1.60, -2.00)
# THE PEEL'S OWN EXTRA TRAVEL, on top of the body's. The freed part slides this
# much further toward the player than the part still welded to the world, and
# lifts this much, which is what makes the film come away from its LOWER edge
# first instead of sliding off as a rigid plate.
#
# It is small on purpose. It used to be `sheet_pull_distance` itself (1.35), so
# the body was moved by 1.35 AND the freed vertices by another 1.35 — 2.7m of
# pull, a film that had moved twice as far as the blade cutting it, and a picture
# whose outline no longer had anything to do with the hole it came out of.
@export var sheet_peel_slide := 0.18
@export var sheet_peel_lift := 0.06

# ===========================================================================
# 4 · THE FIVE CUTS — 三叉尖是笔刀
# ===========================================================================
#
# 精准、凶狠、连续地割裂那张被扯下来的现实膜. Not an explosion: a penknife.
#
# Each cut is a SEGMENT in the sheet's own plane, in sheet radii (so the same
# data works if the sheet is retuned), and each has its own time. The director
# flies the head along them; the shader opens a gap along each one.

@export_group("E · The Cuts")
# The two shaders hold `cut_seg[CUT_MAX]` with a fixed size, because a GLSL
# uniform array has to have one. This is that size, and it is asserted against
# `cuts.size()` in `tests/chain_ultimate_integration.gd`: adding a sixth cut and
# forgetting the shader would otherwise be a silent no-op on the last stroke.
const CUT_SLOTS := 6
# 5 cuts. The brief allows 3-6 and asks for 横/斜/交叉 with the last one heaviest.
# Each entry is [ax, ay, bx, by] — a segment in SHEET RADII, so the choreography
# reads as the shape it is: 1 and 4 are near-horizontal, 3 is near-vertical, 2 and
# 5 cross the others.
#
# THE TIMES ARE NOT IN THIS TABLE. They are `cut_start + i * cut_gap`, which is
# one number per rhythm instead of five numbers to keep in step with a list — and
# the spacing is a fact the brief cares about ("高速"), so it is stated once.
@export var cuts: Array[Vector4] = [
	Vector4(-0.78, 0.34, 0.74, -0.10),
	Vector4(-0.62, -0.58, 0.66, 0.22),
	Vector4(-0.20, 0.84, 0.18, -0.80),
	Vector4(-0.86, -0.14, 0.82, 0.44),
	Vector4(-0.70, -0.66, 0.72, 0.62),
]
# THE RHYTHM IS DERIVED, NOT PICKED. PHASE 6 is 2.15-2.85 and the last cut's gap
# has to be finished opening by 2.85, so `cut_start + 4 * cut_gap + cut_open_time
# <= t_tear_start` is a real constraint and not a preference: move `t_tear_start`
# without moving these and the sheet comes apart while a stroke is still opening.
@export var cut_start := 2.22
@export var cut_gap := 0.12
# 0.0 is a hairline and 1.0 is fully open. The last cut in the list is driven
# further open than the rest (see `cut_final_extra`) because the brief asks for
# the last one to be the heavy one.
@export var cut_open_width := 0.055
@export var cut_final_extra := 2.1
@export var cut_open_time := 0.14
# How long the tip spends CROSSING a stroke. The rest of the gap is spent
# travelling from this stroke's far end to the next one's near end, so the head
# never teleports between cuts — it is on a chain, and a chain that blinks from
# one end of a cut to the other is the single most obvious way to break the read.
@export var cut_stroke_time := 0.075

# ===========================================================================
# 5 · THE TEAR — 漫画撕裂
# ===========================================================================
#
# 不是粒子爆炸. The sheet comes apart as PRINT does: it splits along its cuts, the
# pieces separate and tumble a little, and the split edge goes bright — paper
# white over a hard ink line. Nothing flies far (the brief says 裂片翻飞, not
# 炸开), and nothing spins fast enough to become confetti.

@export_group("F · The Manga Tear")
@export var shard_count := 6
@export var shard_spread := 0.62
@export var shard_spin := 34.0
@export var shard_tumble := 52.0
# How long the burst takes. It is short on purpose: a tear is an event.
@export var tear_time := 0.35
@export var tear_flash := 0.55
# The white edge along a split. Wide enough to be a drawn line rather than a
# one-pixel seam, because a one-pixel seam is invisible at 720p.
@export var tear_edge_width := 0.055
@export var tear_ink_width := 0.018

# ===========================================================================
# 6 · THE RESTORE
# ===========================================================================
#
# 被撕裂的二维膜碎开 → 溶散 / 飘散 / 折回 → 世界恢复. The hole left in the world
# closes over this long, and the sheet's pieces go before it does, so the last
# thing on screen is the world rather than an effect.

@export_group("G · The Restore")
@export var restore_time := 0.35
@export var restore_dissolve := 0.20
@export var hole_close_delay := 0.06

# ===========================================================================
# 7 · CAMERA
# ===========================================================================
#
# The camera does NOT take over. Its whole budget is: a few degrees of FOV, a
# couple of impulses, and one hundredth of a metre of shake. The brief §五.4 says
# this skill is most at risk from 信息过多 and 速度混乱, and a director that also
# drives the camera is the fastest way to get there.

@export_group("H · Camera")
# FOV closes 5 degrees into the thrust and holds. 起手不是马上炸特效 — a narrowing
# frame is how a shooter says "something is about to be different" without any
# effect existing yet.
@export var fov_close := -5.0
@export var fov_close_time := 0.15
@export var fov_open_time := 0.45
# Impulses: the bite, the pull, the first cut, the tear. Four, and no more.
@export var impulse_bite := 0.055
@export var impulse_pull := 0.075
@export var impulse_cut := 0.030
@export var impulse_tear := 0.115
@export var impulse_decay := 7.5

# ===========================================================================
# 8 · GAMEPLAY
# ===========================================================================

@export_group("I · Gameplay")
@export var damage := 260.0
@export var poise_damage := 320.0
@export var cooldown := 34.0
# Brief §五.1: a single target, and it does not have to be the one the anchor was
# aimed at. Anything within this of the sheet's centre when it tears takes it.
#
# LARGER THAN THE WOUND, AND THAT IS FORCED. A body standing inside the film's
# own screen silhouette is printed ON the film when the capture is taken, so the
# target MUST stand outside it — and outside it in the HORIZONTAL only, because a
# body cannot be put above or below a film that hangs in front of it. See the note
# over `TARGET_STAND` in `chain_ultimate_lab.gd`.
#
# The film's edge is at 0.515 of the frame's half-width at the rip, and the dummy
# stands 5.0m from the camera where the frame's half-width is 6.22m — so its whole
# 1.8m width has to be past `0.515 + 0.145 = 0.66`, i.e. 4.11m to the side. It
# stands at 4.5, which puts its origin 5.13m from the wound at the tear. This is
# that distance plus the margin for the room being re-dressed around it.
@export var hit_radius := 5.6

# ===========================================================================
# FUNCTIONS — the ceremony's arithmetic, in one place
# ===========================================================================

## Progress 0..1 across a window. Clamped, and safe when the window is degenerate.
static func span(t: float, start: float, end: float) -> float:
	return clampf((t - start) / maxf(end - start, 0.0001), 0.0, 1.0)


## Seconds since a moment. Never negative, so it can be compared directly.
static func since(t: float, at: float) -> float:
	return maxf(t - at, 0.0)


## Has this moment happened at all. The one-shot counterpart of `span`.
##
## IT EXISTS BECAUSE `exp(-since(t, at))` IS 1.0 BEFORE `at`, which is the
## opposite of what a one-shot means: a flash that decays from a moment that has
## not happened yet is a flash at FULL STRENGTH for the whole run-up. That is
## exactly what put a 0.55 white wash over the reality film from t=0.00 to the
## tear at 2.85 — the film was a blown-out white blob for the entire first pass,
## and every other value in `evaluate` was correct the whole time.
static func after(t: float, at: float) -> float:
	return 1.0 if t >= at else 0.0


## A one-shot: nothing before `at`, then a decay at `rate` per second after it.
static func decay(t: float, at: float, rate: float) -> float:
	return after(t, at) * exp(-since(t, at) * rate)


static func ease_in_out(u: float) -> float:
	return u * u * (3.0 - 2.0 * u)


static func ease_out_cubic(u: float) -> float:
	var v := 1.0 - u
	return 1.0 - v * v * v


static func ease_out_quint(u: float) -> float:
	var v := 1.0 - u
	return 1.0 - v * v * v * v * v


static func ease_in_cubic(u: float) -> float:
	return u * u * u


## The head's flight. Ease-OUT only.
##
## A throw that starts slowly does not read as a throw. The head is already at
## speed the instant it leaves the hand — that is what 直、狠、准 means — and the
## only thing the curve has to do is put it on the anchor without an overshoot
## to correct.
static func thrust_ease(u: float) -> float:
	return ease_out_cubic(u)


## The coil's radius, closing as it winds. `r = start + (end - start) * u^2`:
## the first turn still sits wide (the rope is paying out) and the second is
## already tight, so the two turns do not look like the same turn twice.
func coil_radius_at(u: float) -> float:
	return coil_radius_start + (coil_radius_end - coil_radius_start) * u * u


## The coil's angle, in turns, at ceremony time `t`. Linear in u and multiplied
## by `coil_turns`, so the total is exactly `coil_turns` and the tests can check
## it. `coil_accel` raises the RATE at the end without changing the total.
func coil_turns_at(t: float) -> float:
	var w := span(t, t_coil_start, t_pull_start)
	# Integral of a rate that ramps from 1 to `coil_accel`, normalised so that the
	# integral over 0..1 is exactly 1. With a linear rate r(u) = 1 + (a-1)u, the
	# integral is 1 + (a-1)/2, so dividing by that makes the total `coil_turns`.
	var a := coil_accel
	var raw := w + (a - 1.0) * 0.5 * w * w
	var norm := 1.0 + (a - 1.0) * 0.5
	var shaped := raw / norm
	# The very first instants of the wind are a smoothstep, so the head does not
	# snap from "travelling forward" to "turning" in one frame.
	var ramp := minf(w / 0.18, 1.0)
	return coil_turns * shaped * ease_in_out(ramp)


## When stroke `i` begins. The rhythm, in one place.
func cut_time(i: int) -> float:
	return cut_start + float(i) * cut_gap


## Cut `i`'s two endpoints, in the SHEET'S OWN METRES: `cuts` is authored in
## sheet radii and the aspect is applied here, so a stroke written as "a near
## horizontal across the middle" stays near horizontal on the film however the
## film is stretched. One function, because the shader, the blade and any future
## reader of the choreography all have to agree about where a stroke IS.
##
## THE CONTRACTED RADIUS, NOT THE BUILT ONE. Every stroke happens after the pull
## is over, so the film the tip is cutting is the contracted one — laying the cuts
## out against `sheet_radius` would put them off the edge of the screen, where the
## whole cutting phase would be a line flying around outside the frame.
func cut_endpoints(i: int) -> Vector4:
	if i < 0 or i >= cuts.size():
		return Vector4.ZERO
	var c := cuts[i]
	return Vector4(
		c.x * sheet_aspect.x,
		c.y * sheet_aspect.y,
		c.z * sheet_aspect.x,
		c.w * sheet_aspect.y
	) * (sheet_radius * sheet_contract_end)


## The film's contraction at `t`: 1.0 while it is still part of the world,
## `sheet_contract_end` once it is free. It rides the SAME window and the SAME
## easing as `pull`, on purpose — the picture coming in and the film coming off
## are one motion, and two easings for one motion is how they get out of step.
func sheet_contract_at(t: float) -> float:
	return lerpf(1.0, sheet_contract_end, ease_in_out(span(t, t_pull_start, t_float_start)))


## The film's extent as BUILT — the size of the mesh. Everything that has to agree
## with the mesh itself (the lobes, the shard boundaries, the UV bake) uses this,
## because the mesh does not change.
func sheet_extent() -> Vector2:
	return sheet_aspect * sheet_radius


## The film's extent RIGHT NOW, contraction included: what the frame actually sees,
## what the cuts are laid out against, and what the trident flies around.
##
## IT IS A SECOND FUNCTION ON PURPOSE. For the whole back half of the ceremony
## this and `sheet_extent()` differ by a factor of three, and one function with a
## default argument would be one more place to reach for the wrong one without
## anything going red.
func sheet_extent_at(t: float) -> Vector2:
	return sheet_aspect * (sheet_radius * sheet_contract_at(t))


## How open cut `i` is: the gap along the segment, 0 at its time, full
## `cut_open_time` later. The last cut opens further (brief: 最后一击最重).
func cut_open_at(t: float, i: int) -> float:
	if i < 0 or i >= cuts.size():
		return 0.0
	var at := cut_time(i)
	var u := span(t, at, at + cut_open_time)
	var width := cut_open_width
	if i == cuts.size() - 1:
		width *= cut_final_extra
	return ease_out_quint(u) * width


## How far along cut `i` the tip has travelled, 0..1, and it reaches 1 at
## `time + cut_stroke_time` — NOT at the end of the opening window, because the
## rest of the window is the flight to the next stroke. The gap and the blade
## therefore both read this and cannot disagree about where the stroke has got to.
func cut_trace_at(t: float, i: int) -> float:
	if i < 0 or i >= cuts.size():
		return 0.0
	var at := cut_time(i)
	return ease_in_out(span(t, at, at + cut_stroke_time))


## The peel, per unit of "height" up the sheet: 0 has not let go, 1 has.
##
## The sheet comes away from its LOWER edge first and the tear runs upward, so a
## point at peel coordinate `p` (0 = bottom, 1 = top) is released at
## `t_pull_start + peel_time * p`. Reading it as a function of `t` rather than
## accumulating an offset per frame is what makes the entire ceremony scrubbable.
func peel_at(t: float, p: float) -> float:
	var at := t_pull_start + peel_time * clampf(p, 0.0, 1.0)
	return ease_in_out(span(t, at, at + peel_time * 1.6))


## The burst. 0 while the sheet is whole, 1 when the pieces are fully apart.
func tear_at(t: float) -> float:
	return ease_out_cubic(span(t, t_tear_start, t_tear_start + tear_time))


## The hole in the world closing. Delayed a fraction behind the tear so the
## pieces start to move before the wound does.
func hole_close_at(t: float) -> float:
	return ease_in_out(span(t, t_restore_start + hole_close_delay, t_end))


## The sheet's own dissolution, over the same window as the hole.
func dissolve_at(t: float) -> float:
	return ease_in_cubic(span(t, t_restore_start, t_end))


## Everything above, as one dictionary. The director calls this once per frame and
## passes the result around; nothing downstream reads `t` for itself, which is
## what keeps the phases from disagreeing about what time it is.
func evaluate(t: float) -> Dictionary:
	var coil_turns_now := coil_turns_at(t)
	var coil_u := span(t, t_coil_start, t_pull_start)
	var open: Array[float] = []
	var trace: Array[float] = []
	for i in cuts.size():
		open.append(cut_open_at(t, i))
		trace.append(cut_trace_at(t, i))
	return {
		"t": t,
		"thrust": thrust_ease(span(t, t_thrust_start, t_thrust_start + thrust_travel)),
		"bite": span(t, t_bite, t_bite + bite_time),
		"coil_turns": coil_turns_now,
		"coil_u": coil_u,
		"coil_radius": coil_radius_at(coil_u),
		"pull": ease_in_out(span(t, t_pull_start, t_float_start)),
		"free": span(t, t_float_start, t_cut_start),
		"cut_open": open,
		"cut_trace": trace,
		"cuts_done": _cuts_done(t),
		"tear": tear_at(t),
		"hole_close": hole_close_at(t),
		"dissolve": dissolve_at(t),
		"flash": tear_flash * decay(t, t_tear_start, 6.0),
		"restored": t >= t_end,
	}


func _cuts_done(t: float) -> int:
	var n := 0
	for i in cuts.size():
		if t >= cut_time(i):
			n += 1
	return n


## The head's position, in world space, for the whole ceremony.
##
## ONE function, because the head's path is the ceremony's spine: the thrust, the
## bite, the two turns and the five cuts are not four features, they are one
## trajectory with different phases, and every one of them has to agree with the
## others about where the metal is. `hand` and `anchor` are world positions; the
## camera's basis supplies the two axes the coil turns in.
func head_position(
	t: float, hand: Vector3, anchor: Vector3, cam_basis: Basis
) -> Vector3:
	var e := evaluate(t)
	# ---- 0/1 · THE THROW AND THE BITE ------------------------------------
	var thrown: float = e["thrust"]
	if thrown < 1.0:
		# A straight line from the hand to the anchor. A little above it on the
		# way, because a head thrown at chest height along a rising line reads as
		# being CARRIED rather than thrown.
		var arc := sin(thrown * PI) * 0.18
		return hand.lerp(anchor, thrown) + cam_basis.y * arc
	if t < t_coil_start:
		# §19's bite: a few centimetres PAST the anchor, along the throw's own
		# direction, so the blade ends up inside the core rather than in front of
		# it. `head_size * 0.28` at the chain's own head size is ~8cm.
		var drive: float = e["bite"]
		var dir := (anchor - hand).normalized()
		return anchor + dir * 0.085 * ease_in_out(drive)
	# ---- 3 · THE TWO TURNS -----------------------------------------------
	if t < t_pull_start:
		var turns := float(e["coil_turns"])
		var angle := turns * TAU
		var radius := anchor_radius * float(e["coil_radius"])
		# The orbit is in the camera's own vertical plane, so the turn reads as a
		# circle on screen rather than as an ellipse the player has to decode.
		var right := cam_basis.x.normalized()
		var up := cam_basis.y.normalized()
		return anchor + right * cos(angle) * radius + up * sin(angle) * radius
	# ---- 4/5 · THE PULL AND THE HOLD -------------------------------------
	if t < t_cut_start:
		# The head comes home with the sheet, staying a fixed distance from the
		# sheet's centre so the rope is drawn as the thing doing the hauling.
		var p := sheet_center_at(t, anchor, cam_basis)
		return p - cam_basis.z.normalized() * 0.10 + cam_basis.y * 0.05
	# ---- 6 · THE FIVE CUTS -----------------------------------------------
	if t < t_tear_start:
		var center := sheet_center_at(t, anchor, cam_basis)
		var right2 := cam_basis.x.normalized()
		var up2 := cam_basis.y.normalized()
		# Which stroke, and where in it. `last` is the newest cut that has begun;
		# before it has begun (or after its stroke) the tip is either waiting at
		# the previous stroke's far end or flying to this one's near end, and both
		# of those are the same lerp with different endpoints.
		var last := -1
		for i in cuts.size():
			if t >= cut_time(i):
				last = i
		if last < 0:
			# Between the sheet's arrival and the first stroke: the tip is drawn
			# off the sheet's upper right, poised. It is not idle — it is drawn
			# back, which is the only thing that makes the first cut a STRIKE.
			# The CONTRACTED extent: the film the tip is about to open is the
			# one on screen, not the one the mesh was built at.
			var ext := sheet_extent_at(t)
			return center + (right2 * 0.86 * ext.x + up2 * 0.72 * ext.y).normalized() \
				* maxf(ext.x, ext.y) * 1.25
		var seg := cut_endpoints(last)
		var a := center + right2 * seg.x + up2 * seg.y
		var b := center + right2 * seg.z + up2 * seg.w
		var stroke_end := cut_time(last) + cut_stroke_time
		if t <= stroke_end:
			# On the stroke. The tip CLEARS the sheet's edge instead of stopping
			# on it: a travel that ends exactly on the boundary reads as a stroke
			# that was clipped rather than one that followed through.
			return a.lerp(b, float((e["cut_trace"] as Array)[last]) * 1.08)
		# Off the stroke. Fly to the next one's near end, or — if this was the
		# last — hold clear of the sheet and let the tear take it.
		if last + 1 >= cuts.size():
			return b + (b - a).normalized() * 0.35
		var next := cut_endpoints(last + 1)
		var next_a := center + right2 * next.x + up2 * next.y
		var fly := ease_in_out(span(t, stroke_end, cut_time(last + 1)))
		return b.lerp(next_a, fly)
	# ---- 7/8 · THE TEAR AND AFTER ----------------------------------------
	var c2 := sheet_center_at(t, anchor, cam_basis)
	var away := (c2 - hand)
	return c2 - away.normalized() * 0.35


## The camera's fov at time `t`. Pass `base_fov` 0.0 to get the OFFSET alone.
##
## WHY THIS IS A FUNCTION HERE AND NOT A READ OF THE CAMERA. The camera's real fov
## is `base_fov + fov_hold`, and the director only ever WRITES `fov_hold` — the
## feedback controller composes the number and pushes it onto the camera in its
## own `_process`, which runs after the director's. So anything inside the
## director that reads `camera.fov` gets the PREVIOUS frame's value. At the rip
## that was the entire 5-degree close (the camera read 75.0 where the frame was
## drawn at 70.0), and because the reality sheet's photograph is taken through
## that camera, the film's baked UVs came out 9% wide: its content sat radially
## displaced from the frame it was drawn in. Measured against the world at the
## same pixels, the film matched a 0.912 scale — which is exactly
## `tan(35)/tan(37.5)`. A picture of a view that was never on screen.
func camera_fov_at(t: float, base_fov: float) -> float:
	# Closes into the thrust and holds through the whole ceremony. The tear then
	# OPENS it a few degrees past neutral for a fifth of a second: the closing was
	# the promise and the opening is the receipt.
	if t < t_tear_start:
		return base_fov + fov_close * ease_out_cubic(span(t, 0.0, fov_close_time))
	if t < t_tear_start + fov_open_time:
		var u := ease_out_cubic(span(t, t_tear_start, t_tear_start + fov_open_time))
		return base_fov + lerpf(fov_close, -fov_close * 0.5, u)
	var u2 := ease_in_out(span(t, t_tear_start + fov_open_time, t_end))
	return base_fov + lerpf(-fov_close * 0.5, 0.0, u2)


## Where the sheet's centre is, at time `t`. Public because the sheet, the hole,
## the head and the wound all have to agree about it, and a second copy of this
## arithmetic would be a second thing to get wrong.
func sheet_center_at(t: float, anchor: Vector3, cam_basis: Basis) -> Vector3:
	var e := evaluate(t)
	var pull: float = e["pull"]
	# TOWARD THE PLAYER, and the sign is the whole story. `-cam_basis.z` is the
	# direction the camera is LOOKING, so `anchor + fwd` is further away — the
	# first version of this line drew the film away from the player while its own
	# comment said "toward", which made it shrink instead of grow and left the
	# blade cutting a plane 2.3m behind the picture it was supposed to be cutting.
	var toward := cam_basis.z.normalized()
	# The sheet starts AT the anchor's own depth (it is, at that instant, still
	# part of the world) and is hauled toward the player AND ASIDE. The WOUND does
	# not move: leaving it behind is what makes the film a thing that came off
	# something, and going aside is the only reason the wound is ever visible once
	# the film has grown — see `sheet_drift`.
	var out := anchor
	out += toward * (sheet_pull_distance * pull)
	out += cam_basis.x.normalized() * (sheet_drift.x * pull)
	out += cam_basis.y.normalized() * (sheet_drift.y * pull)
	return out


## The sheet's transform at time `t`: a basis standing in the camera's own frame,
## so the sheet faces the viewer and its local XY are the axes the cuts and the
## lobes are authored in.
func sheet_basis(t: float, cam_basis: Basis) -> Basis:
	var e := evaluate(t)
	var pull: float = e["pull"]
	# A slight roll as it comes free. A perfectly upright sheet hanging in space
	# reads as a UI panel; 6 degrees of roll is the difference between an object
	# and a page.
	var roll := deg_to_rad(-6.0) * pull
	var tilt := deg_to_rad(-7.5) * pull
	var basis := cam_basis.orthonormalized()
	basis = Basis(basis.y, roll) * basis
	basis = Basis(basis.x, tilt) * basis
	return basis
