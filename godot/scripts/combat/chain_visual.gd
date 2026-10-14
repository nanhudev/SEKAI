extends Node3D
class_name ChainVisual
# 缚星链'S BODY: handle, the coils in the hand, the rope, the trident head.
#
# This is a DRAWING. Nothing in the gameplay reads it, and it has no physics of
# its own — which is deliberate, and is now the whole point of V3 (§3): fifty
# RigidBody3Ds and forty-nine joints would be unstable, unsynchronisable and
# unreadable in first person, and none of that instability is something a player
# can feel. What a player CAN feel is weight, sag, lag, tautness — and LENGTH,
# which is the thing V3 exists to add.
#
# The rope is a curve, not a simulation:
#
#   point(t) = lerp(hand, head, t)
#            + DOWN   * sag * sin(pi * t)      ← weight (slack when the head is close)
#            + BEHIND * bow * sin(pi * t)      ← lag (the chain trails a fast head)
#
# Sag and bow are both driven by SLACK and killed by TENSION, so the same code
# produces all three states the brief asks for (§33):
#   held / slow   → visibly hanging
#   fast swing    → straighter, knifing through the air
#   taut          → a straight metal line
#
# Why analytic and not Verlet: the rope has to look right in the one frame a
# player screenshots, every frame, at any framerate, and it must never explode.
# A hanging-cable formula cannot do any of those things wrong.
#
# ===========================================================================
# §1 / §2 / §25 / §26 — WHAT V3 ADDS: THE WEAPON IS LONG, AND YOU CAN SEE IT
#
# Two drawings, both driven by one number — HOW FAR THE HEAD IS PAID OUT.
#
#   THE COIL RIG      how much rope is still in the fist. A preset bundle of
#                     loops whose count falls as the head goes out and climbs
#                     back as it is reeled in. Nothing is simulated: the point
#                     is that a stationary player can see that they are holding
#                     eight metres of chain, not two.
#
#   THE LINK POOL     how much rope is DRAWN. A constant link SIZE, not a
#                     constant link count (§25): a chain drawn with 28 links at
#                     a 9m throw is a 32cm-per-link fence. The pool is 96 and
#                     the drawn subset is `reach / link_spacing`, so the links
#                     are the same size at rest and at full stretch.
#
# Both read `reach / chain_length`, so the quantity the player watches and the
# quantity the drawing reads are the same quantity.

const LINK_TINT := Color(0.72, 0.74, 0.79)
const HEAD_TINT := Color(0.45, 0.47, 0.52)
const HANDLE_TINT := Color(0.26, 0.24, 0.22)
const TRAIL_TINT := Color(0.95, 0.72, 0.35)

# ===========================================================================
# §5 — THE LINK IS A RING, NOT A CUBE.
#
# V3 drew the chain as a squat BOX, and the user's note on the whole weapon was
# "视觉太飘 / 缺少重量感". Part of that is these boxes: a chain of near-cubes has no
# HOLES in it, and the holes are most of what tells an eye "chain" rather than
# "rod with notches". A ring also weighs more than a cube of the same footprint,
# because the eye can see the metal is a closed loop.
#
# The link is an OVAL — longer along the rope than across it, the way a forged link
# is. Width across the rope is `LINK_WIDTH_SCALE` of the length along it.
#
# AND FORGED, NOT DRAWN, which is two numbers that were both measured wrong.
#
#   1 · THE RING. A TorusMesh is a POLYGON and `rings` is how many sides it has. This
#       was 6, i.e. every link in this weapon was a HEXAGON — and at the 60cm the held
#       bundle is photographed from, a hexagon does not read as a ring, it reads as an
#       outline drawn in six straight lines. That is most of what "white wire" meant;
#       it was never the tint. Now 12, where the curvature is smooth at every range
#       this weapon is ever seen from.
#
#   2 · THE METAL. `LINK_TUBE_RATIO` is the hole as a fraction of the link's half
#       length: the tube's radius is `half · (1 − ratio)`. At 0.66 the metal was 8mm
#       bent round a 3.9cm ring — a ratio of 0.20 against the 0.3 a real forged link
#       runs — so each link came out as a thin band with a huge hole and the bundle
#       read as a pile of wire loops. §5 asks for the opposite ("thicker than
#       realistic, a clear oval / forged shape"). At 0.52 the metal is 2.3cm thick
#       across a 9.5cm link, and the link's OUTER extent is unchanged, so the pitch
#       and every consumer of it stay exactly where they were.
#
# The second number is why the first one matters: a thick tube on a six-sided ring is
# still a hexagon, and a smooth ring with a thin tube is still wire.
const LINK_TUBE_RATIO := 0.7
#
# Two facts had to survive from V3, and both are reasons the old box was chosen:
# the link must be big enough to read at four metres (a hair-thin torus is a dotted
# line), and the PITCH may not change — `chain_physicality` samples the drawn
# polyline for its sag, and a coarser polyline undersamples a 0.95m sag at its
# apex. So the size comes from the ring's outer radius and the pitch is untouched.
const LINK_WIDTH_SCALE := 0.66
# §LINK METAL — ONE NUMBER, AND IT IS NOT A GUESS. See `_link_material`: 0.75 rendered
# the weapon as a black silhouette, and 0.45 still rendered the held bundle as a
# charcoal blob (a fistful's averaged curvature reflects the sky away from the eye).
const LINK_METALLIC := 0.20
# How much of the pitch a link's own length takes up. ABOVE 1, so consecutive links
# OVERLAP and visibly thread through each other.
#
# IT USED TO BE 0.86, AND THE RENDER IS WHAT SAID WHAT THAT MEANT. A link 0.86 of its own
# pitch long on an 11cm pitch is a 9.5cm ring at centres 11cm apart — a 1.54cm gap between
# every pair, i.e. NOT ONE LINK THREADS ANY OTHER, and the idle capture read as a string
# of separate fat doughnuts rather than as a chain. A torus chain only interlocks when
#     |pitch − ring outer radius| < ring inner radius,
# i.e. when the PITCH lies inside (0.023, 0.072) for a 9.46cm link — and a real chain runs
# pitch / link-length at about 0.5–0.6. 0.86 was 1.16: the links were FURTHER APART than
# they were long. Measured A/B: `.render/stow_idle_zoom_ab.png`.
#
# SO THE INTERLOCK IS BOUGHT WITH PITCH AND NOT WITH SIZE, which is the whole reason this
# constant is allowed to move at all. `link_spacing` 0.11 → 0.052 and this 0.86 → 1.82,
# which leaves the LINK EXACTLY THE SIZE IT WAS:
#     length 0.052 · 1.82 = 0.0946 m   (was 0.11 · 0.86 = 0.0946)
#     half-edges stay 0.0312 / 0.0114 / 0.0473 m   (measured by `stow_diag.gd`)
# and pitch / length = 0.052 / 0.0946 = 0.55, dead centre of the band real chain runs.
# §5's "thicker than realistic, a clear oval / forged shape" is untouched — not one
# dimension of the link moved, only the DENSITY of links along the rope. It is still
# exactly ONE link size in this weapon (§PART H, and no second system).
#
# AND IT IS A WHOLE-WEAPON CHANGE, because this pitch is the free rope's pitch too: the
# pool goes 96 → 200 so `links · link_spacing` still covers `chain_length`
# (200 · 0.052 = 10.4 m ≥ 10.0 m), and the finer polyline makes the free rope BETTER
# sampled, not worse (see `chain_moveset.gd` on why the COARSER 0.145 was what went red).
const LINK_FILL := 1.752
# ===========================================================================
# §6 / §STOW · V4·B — THE SURPLUS CHAIN HAS A STOWAGE, AND IT IS FOUR OPEN ARCS.
#
# THE FAILURE THIS REPLACES, IN THE USER'S OWN WORDS: 多出来的 6–8m 链条如果只是堆在
# 手边，会立刻变成一坨金属毛线。哪怕攻击本身做得再好，待机第一眼就会掉价。
#
# That is the correct diagnosis of what stood here. The previous pass built a
# TUMBLING NESTED SPIRAL — one continuous rope gathered into `coil_max` bights, each
# bight rolled 36° further than the last so that no two shared a plane. It fixed the
# honeycomb plate, every link in it was the rope's own forged oval in the rope's own
# steel, and `tools/probe_chain_framing.gd` still measured it at **0.43 x 0.46 m,
# NDC (0.23, -0.46)** — half the height of the first-person frame, sitting just to the
# right of the crosshair. The read was 一坨金属毛线, and no amount of link fidelity
# could have changed it, because a first-person weapon is judged at a glance.
#
# THE MISTAKE WAS THE ABSTRACTION. A fistful is what a rope does when it is DROPPED.
# What a professional does with six metres of surplus chain is STOW it, and the stow
# is the part that says "this weapon is long and its owner knows what to do with it".
# A tangle says the opposite — it says the weapon is longer than its owner. So the
# surplus stops being a lump and becomes a SET OF OPEN ARCS:
#
#   `coil_max` layers, each ONE ARC of `ARC_SWEEP` (132°) with two free ends, growing
#   outward from 13cm to 15.5cm along ONE SHARED NORMAL, each layer's centre stepped
#   outboard / down / into depth. The union is a SPIRAL FAN, and the outer end of the
#   outermost arc is the rope's FREE END — which is also the end that pays out first.
#   `_place_coils` therefore hides the outermost first, and the weapon sheds the way a
#   rope actually leaves a stow.
#
# FOUR, AND NOT EIGHT, BECAUSE THE UNIT CHANGED. `coil_max` is still
# `chain_length / coil_per_loop` and still derived from the ROPE; `coil_per_loop` is
# 2.5m rather than 1.25m because the stow's unit is now the LAYER — an arc of several
# links — and not the single turn. The old bundle claimed eight 1.25m turns inside a
# fist whose drawing held about a metre of chain: an eightfold lie. Four layers at
# 2.5m is a fourfold one, and §7 licenses exactly this. What the stow must never lie
# about is what §26 actually asks for: the COUNT (twice the rope still means twice
# the arcs) and the LINK SIZE (every seam is still `link_spacing` apart, so there is
# still exactly ONE link size in this weapon — §PART H, and no second system).
#
# AND THE RULE THAT DECIDES THE FRAME IS THE USER'S, AND IT IS A MEASUREMENT:
#
#     余链永远不能出现在准星周围。
#
# So the stow is anchored at the LEFT hip, it may not enter the central band of the
# frame, and `chain_v4_slice` projects every drawn stow link and fails if one lands
# inside it. The old bundle sat at NDC (0.23, -0.46) — that is not a tuning error, it
# is the exact thing the rule forbids, and it is why the rule is an assertion now
# instead of a note in a document.
#
# FAKE THE CHAIN. MAKE THE WEAPON REAL. Nothing here is simulated. The arcs are one
# authored shape, they ride the hand anchor in camera space, and gameplay still reads
# only the hand, the head, the contact point and the hitbox.
# ===========================================================================
# WHERE THE STOW SITS, AND HOW THE FAN IS TURNED TO FACE THE EYE.
#
# All of it in the HANDLE's own space — which at rest IS the camera's, so the look
# pitch cannot move the stow one pixel and the framing arithmetic has to be done only
# once (`tools/probe_chain_framing.gd`) instead of every time the player looks down.
#
# MEASURED, AND THE NUMBER IS A FRAME BUDGET RATHER THAN A POSE.
#
# The bundle used to hang off `(-0.09, 0.10, -0.05)`, 9cm INBOARD of the hand, which put
# it at camera-space (0.21, -0.24, -0.67) = NDC (0.23, -0.46) — the wrong side of the
# crosshair entirely. So the anchor is a target in the OPPOSITE quadrant, and handle-local
# = that target minus the hand anchor's own (0.30, -0.34, -0.62).
#
# BUT THE QUADRANT ALONE IS NOT ENOUGH, AND THE DEPTH IS WHAT SETS THIS CONSTANT NOW.
# `ARC_LEAN` puts the fan's normal off the view axis on purpose (see that block), and that
# makes `ARC_DEPTH` step each layer TOWARD THE LENS as well as down and outboard — so at
# 0.52m from the eye every layer is magnified ~10% more than the one before it and pushed
# further from the frame's centre. MEASURED at the old anchor: `stow_frame_reach()` 1.382
# with layer 3 at NDC x −1.382, y −1.147 — one to four tenths of the frame OUTSIDE the
# picture — while `stow_breach()` read a clean 0.0000, because that reading only watches
# the MIDDLE of the frame. A fan too big does not breach; it walks out of the left edge.
#
# PUSHING THE STOW DEEPER FIXES IT, AND IT IS ALSO WHAT 腰后 MEANS. At 0.82m the same
# 0.35m fan subtends a third less, so the walk fits: MEASURED, reach 0.953 with all four
# layers inside, margin +0.0573, per-layer NDC maxima 0.953 / 0.756 / 0.847 / 0.887 —
# still increasing outward, so 最外层最大 survives the perspective. The neighbouring half
# metre is a PLATEAU, not a knife edge: x in [−0.98, −0.96] × z in [−0.26, −0.20] all read
# FIT with both clearances positive, which is the property that matters.
#
# ---- AND THE HEIGHT IS THE "FLOATING" AXIS, WHICH IS WHY IT MOVED. The depth was already
# right; what the frame still showed was a bundle hanging BELOW the horizon on the lower
# left, which reads as a heap resting on something rather than a stow suspended beside the
# hip. MEASURED at y 0.189 the four arcs sit at NDC y −0.42…−0.24 (L1), −0.46…−0.31 (L2),
# −0.57…−0.48 (L3); at 0.260 they sit at −0.32…−0.12, −0.34…−0.16, −0.46…−0.32 — level with
# the fist instead of under it, and clear of the ground line the lead-in used to sweep.
#
# IT IS NEARLY FREE, WHICH IS THE PART WORTH RECORDING. `stow_frame_reach()` 0.844 → 0.925
# (still FIT), margin +0.0732 → +0.0637, and the BEND IMPROVES, 0.1120 → 0.1130, because a
# shorter run to the anchor means a gentler arrival turn. The window is real on the far
# side too: at 0.400 the bundle is at eye level with margin +0.0284, and at 0.480 the
# tightest link is 0.009 from the band — so this is a middle-of-the-window value, not the
# extreme. MEASURED: the per-layer NDC boxes in `stow_diag.gd` at five heights.
#
# AND THE FINAL X AND Z ARE THE PRICE OF `STOW_PITCH`, so they belong to that block rather
# than to this one: at 0.42 the fan lies over far enough that its inboard end reaches the
# band (margin +0.0224), and left+back is the pair that buys it back — 0.22m further left
# and 0.07m deeper end at `reach 0.829 · margin +0.0312`. See the pitch table: neither half
# works alone.
#
# ---- MIRRORED: THE CHAIN IS IN THE LEFT HAND AND THE SURPLUS IS AT THE RIGHT HIP.
#
# User ruling. The handle went left because every sword style idles its grip at camera-space
# x = +0.30 (`moveset_library.gd`), so a right-hand chain grip shared the sword's quadrant and
# the weapon switch read as a swap in place rather than as a different hand. The fan had to come
# with it: it is welded to the hand (`_stow_rest_transform` = `hx * STOW_ANCHOR`), so the
# surplus hangs a fixed 1.04m to the hand's left and the right→left run IS the lead-in.
#
# WHY NOT JUST MOVE THE HAND. MEASURED, moving `ChainHandAnchor` and re-deriving this x so the
# fan held its camera-space place:
#
#     ChainHandAnchor.x    +0.30     −0.18     −0.30
#     hand→stow run        1.05m     0.70m     0.50m
#     tightest drawn turn  0.1268    0.0948    0.0842   (want >= chain's 0.1110)
#     neighbour clearance  +0.0023   −0.0029   −0.0051  (want > 0)
#
# The tight turn lands mid-LEAD-IN, and the lead-in's chord is what sets it: the Hermite's
# tangents are `chord * ARC_LEAD_SLACK`, so the run scales with `|entry − eye|` and half the run
# turns twice as hard. No `ARC_LEAD_SLACK` value recovers it — that window is already measured
# and narrow (1.60 reads 0.0930, 4.20 reads 0.1089, peak 2.60–3.00). The run is too SHORT, not
# mistuned. Hence a MIRROR, which is an isometry and so keeps every reading.
#
# HOW M = diag(−1,1,1) IS EXPRESSED. A negative scale on `ChainHandAnchor` would do it in one
# line and IS safe for winding (the chain material is `CULL_DISABLED`), but Godot refuses a
# determinant-negative basis in `Basis.get_quaternion()`, so every `.rotation` read underneath
# throws `must be normalized ... casted to a Quaternion` — measured, ~400 errors a run, and
# STEP 0 forbids a debugger error. So M is folded into the constants that GENERATE the stow and
# every basis stays PROPER. Six flips, each with exactly one functional reader:
#
#     M · STOW_ANCHOR                    -> x negated                     (this line)
#     M · (Ry(yaw)·Rx(pitch)·Rz(roll))   -> Ry(−yaw)·Rx(pitch)·Rz(−roll)  (STOW_YAW, STOW_ROLL)
#     M · (Rx(lean)·Rz(spin))            -> Rx(lean)·Rz(−spin)            (ARC_SPIN)
#     M · theta, theta = START + SWEEP·s -> (π − START) + (−SWEEP)·s      (ARC_START, ARC_SWEEP)
#     M · (ARC_STACK · s)                -> −ARC_STACK · s               (ARC_STACK)
#
# The handle needs nothing: every part of it is x-symmetric (all offsets are `Vector3(0.0, …)`),
# and the steel eyelet reads its azimuth off this same vector, so it lands on the mirrored
# shoulder by construction. The thrown rope and the trident head are children of `ChainVisual`
# and are driven by WORLD points, so they follow the hand and the aim rather than being mirrored.
const STOW_ANCHOR := Vector3(1.040, 0.260, -0.270)
# The fan is turned about 22° about the vertical, so its inboard end recedes into
# depth. A fan parallel to the image plane is a DECAL; this one is seen at an angle,
# and the far side is the side pointing at the crosshair — so foreshortening does part
# of the safe-zone work for free.
const STOW_YAW := 0.38
# ---- THE PITCH IS THE "偏扁" LEVER, AND RULING ④ IS WHY IT IS A LEVER AT ALL.
#
# When the user chose 圆弧 + 斜视投影 over squashing the 3D path, they moved the flattened
# look out of the geometry and into the CAMERA — so the number that buys it is the attitude
# of the fan's PLANE, not its shape. MEASURED, the angle between the fan's normal and the
# view axis (`stow_diag.gd`'s `HANDLE` block); the fan projects to an ellipse whose width
# is `cos` of it:
#
#     STOW_PITCH    0.18     0.34     0.42     0.50     0.66
#     off the axis  52.9     61.4     65.6     69.9     78.4   deg
#     flatten       0.60     0.48     0.41     0.34     0.20   (minor/major)
#     bend          0.1278   0.1307   0.1317  0.1329  0.1330   (want >= 0.1110)
#     reach         0.877    0.848    0.829   0.818   0.796    (want < 1.0)
#     margin        +0.0718  +0.0420  +0.0224 -0.0014 -0.0456  (want > 0)
#
# EVERY COLUMN BUT THE LAST IMPROVES AS THE FAN LIES OVER, which is the pleasant surprise
# and the reason this is worth a table: an edge-on fan is shorter on screen (reach down),
# and its layers step along a normal that is now more perpendicular to the view axis, so
# the stack separates instead of hiding behind itself. The last column is the catch — a fan
# lying over swings its INBOARD end toward the crosshair, and at 0.50 it breaches.
#
# 0.42 is the last value with room to spare, and the margin it costs is bought back by the
# ANCHOR rather than by this number: at (−1.040, 0.260, −0.270) the bundle is pushed left
# (margin) and back (reach) together, which is what makes 0.42 affordable:
# `reach 0.829 · margin +0.0312 · bend 0.1331 vs 0.1110 · fan 65.6° · shaft 58.0°`.
# Pushing the anchor deeper ALONE does not work and is worth recording: it shrinks the fan
# toward the vanishing point, which is the frame's centre, so `margin` goes NEGATIVE
# (−0.0058 at z −0.270 alone, −0.0216 at −0.340). Only the pair moves both the right way.
const STOW_PITCH := 0.42
const STOW_ROLL := 0.26

# §STOW — THE ARCS. Every number here exists to stop the fan reading as concentric
# rings, which the user named as the very next failure mode: 非常容易再次出现之前那种
# 「几个圆盘贴在镜头边」的 UI 感.
#   - wider with every layer (`ARC_R_GROW`) AND falling along each arc
#     (`ARC_R_SPIRAL`), so no two layers are congruent and the path is a spiral
#     sector rather than a set of rings;
#   - each layer stepped a further `ARC_DEPTH` along ONE SHARED NORMAL and spun a
#     further `ARC_SPIN` within that shared plane (`ARC_LEAN`), so the layers are
#     stacked in SPACE without being rolled out of parallel with each other;
#   - open: `ARC_SWEEP` is 132°, so every layer has two free ends — which is the whole
#     difference between a stow and a UI disc.
const ARC_R_INNERMOST := 0.130  # the arc nearest the fist, in metres
# ...AND IT GROWS MORE SLOWLY THAN THE FIRST PASS DID, BECAUSE THE OUTER TURN IS WHAT
# LEAVES THE FRAME. At 0.06 a layer the outermost arc is 18% wider than the innermost, and
# its own leftmost link came back at NDC x −0.98 … −1.09 depending on the lean: the coil
# did not fit, at any lean, because the growth was pushing it out. 0.045 keeps the
# outermost-largest read (9% across the fan, 3% a layer — still monotone, still
# 最外层最大) and brings the widest layer back to −0.93. MEASURED: the per-layer NDC boxes.
const ARC_R_GROW := 0.045      # ...and the winding opens this much wider per layer
# WHERE THE FAN OPENS, AND IT IS DECIDED BY THE FRAME RATHER THAN BY TASTE.
#
# The first pass ran from 130° and swept 200°, and the capture is what fixed the framing:
# the arc hung BELOW its own anchor, so half the fan fell off the bottom of the screen and
# the reading came back x −0.95..0.36, y −1.37..−0.42 — two of the four layers invisible
# and the whole thing 0.04 NDC from the safe band. The window is what it is: at half a
# metre the frame is 1.69 × 0.95 m, the band takes the middle 0.4 of it, and the four
# layers of a 0.42 m coil occupy 0.44 NDC — so there is no room to be sloppy.
#
# AND THE SECOND REASON IS THE RUN, WHICH IS NOT A FRAMING ARGUMENT AT ALL. The rope
# reaches the stow from the FIST, which sits up and to the right; the winding starts at
# the ENTRY. Begin the winding on the far side of the fan and the run has to cross the
# whole coil to reach it — and what it crosses are the OUTER windings, one `ARC_DEPTH`
# apart, which is not enough room for a link that is 6.24cm wide where it stands across
# the rope. MEASURED, and this is what killed 130°: `stow_interpenetration()` = 1, the
# failing pair named 0↔1, one run link against one arc link, `d·n` +0.0454 against
# `rA + rB` 0.0594.
#
# −1.15 rad (−66°) puts the entry on the fan's LOWER-RIGHT — the side the fist is already
# on — so the run lands on the near point of the winding instead of crossing it. The 228°
# gap then faces away from the body, and every layer still opens to the left and up.
#
# THE NUMBER IS NOT KNIFE-EDGE, which is the property that actually matters: at −1.15 the
# whole neighbourhood (−1.30 … −1.00, and 0.62 … 0.86 rad of lean) reads 0, so the stow is
# nowhere near the boundary of "not a knot". `stow_interpenetration()`, 27 link boxes.
const ARC_START := 4.29159      # rad: π − (−1.15) — the MIRROR of −66°, entry on the fan's lower-LEFT
# ---- THE WINDING HAS TO BE CONTINUOUS, AND THAT IS NOT A STYLE CHOICE ----------------
#
# `ARC_SWEEP` is the winding per layer and there is NO per-layer angular term, because a
# term like that cannot be added without tearing the rope. For the path to run from the
# end of one layer's arc into the start of the next, `ARC_SWEEP` is the ONLY increment the
# angle may take; any extra advance θ gets per layer is a tear of exactly that size.
#
# MEASURED, AND THIS WAS THE KNOT. The previous version advanced the angle by a further
# `ARC_LEAD` (12°) per layer on top of a 200° sweep, so each boundary was a −188° jump. The
# resampler then laid a link straight across that jump — one long link spanning ~16cm of
# the fan, cutting through the arcs behind it. It did not look like a bug, because the two
# arcs still met end-to-end at a point; it looked like a knot. The tell was in the numbers:
# cross-layer pairs that should have been `ARC_DEPTH` = 0.048 apart along the shared normal
# measured 0.016. `stow_interpenetration()` reports the count, and the per-pair `d·n` is
# what named the cause.
#
# So the four layers are four consecutive segments of ONE winding, and HOW LONG EACH SEGMENT
# IS decides whether the stow reads as arcs or as a spool. A spool and a fan are the same
# path at different lengths, and that is the whole of this constant.
#
# At 200° a layer the four layers are 800° — two and a fifth turns — so at a typical angle
# two of the four arcs are lying on top of each other and the eye cannot separate them. The
# quantity that decides it is just `coil_max · ARC_SWEEP / 360°`: the number of layers
# stacked at a typical angle. NO AMOUNT OF RADIAL GROWTH CAN FIX THAT: the frame caps the
# outer radius a little past 0.15m and the chain cannot bend below 0.111m, so all four radii
# live inside a 4cm window — 1cm a layer against a link that is 6.2cm wide — and the layers
# have to separate along the fan's NORMAL instead (see the `ARC_DEPTH` block).
#
# MEASURED, and the column that matters is the overlapping PAIR COUNT: the fewer pairs of
# links that overlap, the more air the stow is read through.
#
#     ARC_SWEEP     3.49     2.80     2.30     1.90     1.55    (rad a layer)
#     degrees        200      160      132      109       89
#     stacked       2.22     1.78     1.47     1.21     0.99    layers at a typical angle
#     links drawn     74       67       62       58       54
#     overlapping     21       17       15       14       12
#     bend          0.1278   0.1301   0.1268   0.1145   0.1157 (want >= 0.1110)
#
# 2.30 is the last value with both a real bend margin and under a turn and a half: 132° a
# layer is an unmistakably OPEN arc with a 228° gap, and 1.47 turns is close enough to one
# that four consecutive arcs read AS four arcs. 1.90 would be a cleaner 1.2 turns and 12
# pairs, but 3% of bend margin is not somewhere to leave a weapon.
#
# (AND IT COULD NOT BE SET BEFORE NOW, WHICH IS THE PART WORTH KEEPING. The same column read
# 0.1037 at 2.20 — a bend FAILURE — when it was swept against the old anchor and the old
# pitch, and that is what put 200° beyond discussion. `STOW_ANCHOR` and `STOW_PITCH` then
# moved, both of them improving the run's arrival turn, and the constraint moved with them.
# An old sweep is a measurement of an old object: this one was re-run, not trusted.)
const ARC_SWEEP := -2.30        # rad of winding per layer; −132° is the MIRROR of +132° (see STOW_ANCHOR)
# ---- THE LAYERS HAVE TO BE APART, AND "APART" IS A DISTANCE IN METRES ----------------
#
# The first V4·B pass set the four arcs 1.2–1.6cm further out with every layer and called
# that "layered". The render said otherwise: four arcs 1.2cm apart read as ONE KNOT,
# because a link is not a line — it is 6.2cm wide ACROSS the rope (`link_spacing ·
# LINK_FILL` through `LINK_WIDTH_SCALE`), so two lanes 1.2cm apart are two lanes drawn
# inside the SAME link. Nothing about the anchor, the sweep, the tilt or the shading can
# rescue an arc drawn through the middle of the arc behind it.
#
# RADIAL SEPARATION BIG ENOUGH TO CLEAR A LINK IS ARITHMETICALLY IMPOSSIBLE HERE, and
# that is worth writing down rather than re-deriving every time it looks tempting.
# Clearing a 6.2cm-wide link needs a ≥ 6.5cm step; four layers then want 19.5cm of radius
# on top of a first ring that is already 8cm (three 9.5cm links round one turn is the
# smallest this rope can be coiled, and that is the same 下限 that killed the old
# bundle). A fan that fits inside the 0.62 NDC the safe band leaves at half a metre has
# about 0.25 m of width to live in. The two numbers differ by a factor of four.
#
# SO THE SEPARATION GOES WHERE THE ROPE IS THIN, NOT WHERE IT IS WIDE. A link's hole axis
# IS the arc plane's normal, and across that axis a link is one tube thick
# (`link_spacing · LINK_FILL · (1 − LINK_TUBE_RATIO) / 2` = 2.27cm). Stepping the layers
# along the SHARED normal clears them of each other, and it costs no radius at all.
#
# AND THE STEP IS 4.3cm, NOT 2.3cm, BECAUSE THE LINKS ALTERNATE. Consecutive links are
# turned a quarter turn about the rope (§5, and it is what makes a chain read as a chain),
# so an even link is a slab 6.24cm along the RADIUS by 2.27cm along the normal, and its
# odd neighbour is that slab transposed. Two such crosses clear each other when EITHER
# axis is clear by half of (6.24 + 2.27) = 4.26cm — so the normal has to buy 4.26, not
# 2.27, and `ARC_DEPTH` is 4.8cm.
#
# (Radial, for the record, needs 6.24cm — the same figure the paragraph above already
# priced out of the frame. Alternation is what makes the axial route the cheaper one, and
# it is also why a coil of real chain is loose: this is the same 下限 the old fistful hit.)
#
# 4.26cm IS THE GEOMETRIC MINIMUM, NOT THE NUMBER THIS CONSTANT HAS TO BEAT, and the
# difference is worth keeping because the derivation is tempting. Two corrections, both
# measured: (1) the winding ADVANCES along the normal as it goes round, so every link's
# tangent carries `ARC_DEPTH / arc-length-per-layer` ≈ 0.11 of the normal — which adds
# 0.0473 × that, about 5mm, to EACH link's projection; (2) the RUN's links are not in the
# plane at all and project up to 2.3cm. A first pass at raising `ARC_DEPTH` to cover the
# worst pair therefore made the frame worse and left the pair in place — 0.056 still read
# 1 — because the failing pair was a run link against an arc link, and what that pair
# actually wanted was for the rope to stop crossing the fan (see `ARC_START`).
#
# SO THE READING THAT DECIDES THIS CONSTANT IS THE MEASURED ONE: `stow_interpenetration()`
# = 0 over 23 link boxes, and the smallest per-layer-pair gap 1.77cm (`stow_diag.gd`,
# layers 1↔3) — 28% of a link's width, against a 4.8cm step the derivation above only
# claimed 12% of margin on.
const ARC_DEPTH := 0.048        # ...and this far along the SHARED normal — see below
#
# WHICH MAKES THE STACK DIRECTION THE THING THAT MATTERS, and it has to be VISIBLE. A
# depth step read straight down the view axis is invisible; four layers that never touch
# can still read as one knot if they land on the same pixels. `ARC_LEAN` therefore tilts
# the whole fan — ALL LAYERS TOGETHER, so they stay parallel and the step stays exactly
# `ARC_DEPTH` — so that the shared normal is off the view axis and the four arcs come
# apart ON SCREEN as well as in space: 明显错层, read literally.
#
# `ARC_LEAN` turns about the fan's own X, which keeps the WIDE axis in the image plane
# and pushes the squashed axis into depth. That is the whole reason the fan still reads
# 偏扁 — a wide, shallow 3:1 fan — instead of turning into a disc seen face on.
#
# AND IT IS A FRAME-HEIGHT BUDGET, IN NDC, WHICH IS WHY IT IS NOT 0.95 ANY MORE. In the
# stow's own space the normal is (0, −sin L, cos L) and the stow basis turns it into
# (−0.35 … −0.40, −sin, +cos) in handle space — so raising `L` buys vertical stagger and
# pays for it in screen HEIGHT, and the height is the axis the frame is short of. At 0.95
# the normal is 0.88 down and the fourth layer lands at NDC y −0.94: 3% off the bottom
# edge, with the head bob that the idle rig also applies. At 0.78 it is 0.75 down, the
# fourth layer sits at −0.94 … −0.81 WITH the rest of the fan above it, and the four
# layers still separate by ~0.1 NDC each. MEASURED: the per-layer NDC boxes in
# `stow_diag.gd`, and the frame itself.
#
# RE-MEASURED AT THE CURRENT ANCHOR (0.82m, see `STOW_ANCHOR`), and the per-layer y boxes
# are now L0 −0.953…−0.166, L1 −0.425…−0.267, L2 −0.480…−0.308, L3 −0.569…−0.477 — the
# deepest link on the whole path is a LEAD-IN link, not the fourth layer, because moving the
# stow deeper cut the layers' screen stagger in proportion. The lean is still the frame-
# height lever it was, but the numbers above belong to the old 0.52m anchor.
#
# AND LEANING FURTHER IS NOT AVAILABLE. Swept 1.05 / 1.25 / π÷2 against the current anchor:
# `stow_frame_reach()` 1.422 / 1.489 / 1.391 — all WORSE than 0.78 — and `chain_min_bend_radius()`
# climbs with the lean (0.1491 / 0.2020 / 1.5304) because the fan's plane stops containing the
# links' favourable bend direction, so the drawn path fails the bend outright. 0.78 is the
# load-bearing value, not a taste.
const ARC_LEAN := 0.78          # rad: the fan's own lean, 44.7° off the stow plane
const ARC_SPIN := -0.12         # rad each layer is spun inside that plane; sign is the MIRROR (see STOW_ANCHOR)
const ARC_STACK := -0.010       # ...and its centre stepped this far outboard; sign is the MIRROR
const ARC_DROP := 0.003         # ...and this far down
const ARC_SIZE_JITTER := 0.10   # no two layers the same size, deterministically (no RNG)
# THE TWO SHAPE NUMBERS, AND THEY ARE A FRAME BUDGET RATHER THAN A LOOK. `ARC_WIDE`
# stretches the fan along its own X (which the lean keeps in the image plane) and
# `ARC_SQUASH` presses it along its own Y, so the pair reads as one flat wide spiral —
# 偏扁的螺旋扇面, as asked for — and between them they decide whether the outer turn fits.
# At 1.30 / 0.60 the widest layer came back at NDC x −0.93 and the lowest at y −0.95:
# inside the frame, but 3% off the bottom edge with the idle rig's head bob still to come.
# 1.22 / 0.48 puts the widest at −0.89 and the lowest at −0.92 and keeps the 2.5:1
# wide-and-flat read. MEASURED: the per-layer NDC boxes, `stow_diag.gd`.
#
# (The squash ALSO shortens the winding, which moves every seam and therefore the layer
# cuts — the numbers are not monotone in it, which is why the pair was swept and not
# derived. The interval that works is wide: 0.48 … 0.55 at 1.22 reads 0.)
const ARC_SQUASH := 1.0
const ARC_WIDE := 1.0

# THE LEAD-IN: how many links run from the handle's eye to the first arc, and how far
# that run droops. The run is why the fist and the stow read as ONE rope — metres of
# plainly visible chain crossing the frame, in shot at every moment of the idle.
# 96 rather than 8, and the margin is enormous: the run's polyline steps are
# `chord-based`, so 8 samples over a ~1m chord is a 12cm gap against a `link_spacing` of
# 5.4cm — the resample would be laying seams on a polyline COARSER than the thing it is
# spacing. 96 puts the samples a centimetre apart, well inside one link.
#
# (THE 5.4cm IS THE POINT OF RE-READING THIS. The paragraph here used to say
# `link_spacing` was 11cm and the run 0.75m, and both had moved; the rule is the ratio,
# not the numbers, which is why the ratio is what is written down now.)
const ARC_LEAD_STEPS := 96
const ARC_LEAD_DROOP := 0.085
# ...AND HOW FAR THE RUN COMMITS TO ITS TWO END TANGENTS, as a multiple of its own chord
# length — the Hermite's only remaining freedom (see `_stow_path`). Small and the run is a
# near-straight strut from fist to hip, which is the thing the sag comment above is against;
# large and it overshoots into an S.
#
# THE VALUE IS SET BY THE BEND, IT IS A TWO-SIDED WINDOW, AND THE WHOLE ROW WAS RE-READ WHEN
# THE DEPARTURE ANGLE CHANGED. The run has to leave the fist the way a hanging chain does
# and arrive travelling the way the winding travels, and how hard it turns is exactly this
# chord. MEASURED, `chain_min_bend_radius()` 0.1110 m against the drawn path's tightest turn:
#
#     ARC_LEAD_SLACK    2.20     2.60     3.00     3.60     4.20
#     tightest turn   0.1120   0.1162   0.1156   0.1128   0.1089    (want >= 0.1110)
#
# Too short and the run is drawn tighter than the chain can bend, so its links interpenetrate
# at the turn (0.55 reads 0.0644, 1.60 reads 0.0930); too long and it overshoots its own
# arrival tangent and folds back, which is the 4.2 row. 2.60 is the middle of what is left.
#
# AND THE ROW MOVED BECAUSE `_stow_leave` DID, which is the reason to keep the table rather
# than the number: 2.2 was comfortably inside the window when the run left the eye straight
# down the shaft, and it is now 1mm off the floor — the departure turns 52 deg to clear the
# hilt, so the run has that much less chord to arrive on. Tuning one end of the rope moved
# the other's constant, and nothing but a re-sweep would have said so.
#
# AND THE RUN IS THE SAFE-ZONE READING, NOT THE FAN. A run that leaves the fist heading
# straight for the hip cuts across the middle of the frame; the user's rule is that the
# surplus lives LOW AND LEFT, and 回收 wants the long chain seen crossing the bottom of the
# shot. MEASURED at the current anchor: the tightest drawn link is `|max(nx,ny)|` 0.437 at
# ndc (−0.437, −0.429) — a layer-0 (lead-in) link dipping just under the band, while the
# fan's own layers stay 0.489 and beyond. The margin is the run's to spend.
#
# FLATTENING THE RUN WAS TRIED AS A FIX FOR THE KNOT AND IT MADE IT WORSE, which is the
# reading that says this constant is not the problem. At 0.40 the run stays close to its
# own chord, so it lies IN the winding's plane all the way in — and the overlap count went
# 1 → 4 on the spot. A rope has to hang; the fix belonged at `ARC_START`.
const ARC_LEAD_SLACK := 2.60
# ...AND IT ARRIVES FROM OUT OF PLANE, WHICH IS THE WHOLE REASON IT IS A ROPE AND NOT A
# LINE. The winding is 4.8cm deep per layer and a link is 6.24cm wide, so a run that comes
# in IN the winding's plane is one layer away from the second turn at best — and it grazed
# it, every time, at every hang tried (measured: 2, 4 and 1 overlapping pairs at 0.26 / 0.32
# / 0.38). A rope joining a coil does not arrive in the coil's plane; it comes in from the
# side. So the run's approach direction is the winding's tangent tilted back along the
# shared normal by this much, which puts the last metre of run BEHIND every turn and lets it
# cross the coil's mouth without touching it. It was 0.8 ≈ 39°.
#
# IT IS NOW 0.0, AND THAT IS A MEASUREMENT RATHER THAN A REVERSAL. The whole reason for the
# tilt was that a run arriving IN the winding's plane grazed the fan — but that was measured
# at `ARC_START` 1.75 rad, BEFORE the entry moved to the fan's lower-right (−1.15). With the
# entry on the fist's own side there is no crossing left to avoid, and the tilt is now pure
# cost: a 39° angular discontinuity is a KINK, and once the links interlock (`LINK_FILL`
# 1.82) a kink is worse than a graze. MEASURED, at the new `ARC_START`:
#
#     ARC_LEAD_BACK   stow layered   stow margin
#         0.8            −0.0030       +0.0502
#         0.0            −0.0009       +0.0747     ← 0.0, and both readings better
#
# The margin gain is 0.025 NDC, which is a quarter of the safe band's own half-width. The
# const and the `m1` term are kept rather than deleted because the ABILITY to arrive out of
# plane is a property of the path, not a mistake: a future `ARC_START` that puts the entry
# back on the far side needs it again, and re-deriving a Hermite end tangent is how this
# block has already been "fixed" wrongly once.
const ARC_LEAD_BACK := 0.0
# THE FREE END: a few links past the outermost arc, hanging. The one part of the stow
# holding nothing, and the reason it reads as rope rather than as a manufactured shape.
#
# IT LEAVES ALONG THE ARC'S OWN TANGENT, AND IT DID NOT USED TO. The tail was a fixed
# `Vector3(ARC_TAIL_OUT, −ARC_TAIL_DROP, 0)` in STOW space, three steps long — 5.2cm of
# chain, one link. So it met the end of the arc at whatever angle that fixed direction
# happened to make with the arc's tangent, which is a CORNER, and a corner in a chain is
# links that cannot fit: MEASURED at `stow_tightest_radius()`, the single tightest turn on
# the whole drawn path was seam 51 — the tail — at r = 0.0525 m and a 39.9° step. The run
# was second at 0.0644 m. The arc itself was never the problem: at the innermost radius it
# measures 0.133 m, and the fan's own end curvature was the squashed ellipse's fault. Once
# `ARC_SQUASH` goes to 1.0 the only tight turns left are these two junctions.
#
# So the tail is now an incremental heading that STARTS PARALLEL to the arc and bends
# downward as it goes — smooth at the junction by construction, rather than smooth by
# finding a direction that happens to line up. `ARC_TAIL_LEN` is how much chain hangs
# (5 links, so the free end reads as a length of rope and not as a stub) and
# `ARC_TAIL_DROOP` is how far the heading commits to straight down by the end of it.
const ARC_TAIL_STEPS := 6
const ARC_TAIL_LEN := 0.16
const ARC_TAIL_DROOP := 0.3
# Samples per layer before the arc-length resample. 90 over 132° is 1.5° a step, well
# inside one link (23° at the innermost radius), so the resample never invents a corner.
const ARC_STEPS := 90
# §STOW SAFE ZONE — 余链永远不能出现在准星周围. The half-extent, in NDC (-1..1 is the
# whole frame), of the central band the stow may not enter. 0.38 is the middle of the
# user's 35–40% and is deliberately at the STRICT end of it. `stow_breach()` is the
# reading, and `chain_v4_slice` fails on anything above zero.
const SAFE_HALF := 0.38
# ...AND WHAT THE RULE IS ABOUT, WHICH IS NOT THE FIST. 余链 is the surplus chain; the
# first links out of the handle's eye are the weapon's JOINT with the hand, and the hand
# is where it is — with the `ChainHandAnchor` at (0.30, −0.34, −0.62) the eye itself sits
# at NDC (0.355, −0.420), which is 0.04 outside a 0.38 band no matter what the stow does.
# So the reading skips the run within `STOW_JOINT` of the eye: two links of joint, by
# GEOMETRY rather than by index, so a stow that really did move into the middle still
# fails on all of its own links. Measured: with the joint skipped the nearest surplus link
# is 0.089 clear, and every arc is 0.24 or more clear.
const STOW_JOINT := 0.16

# WHERE THE ROPE LEAVES THE HANDLE, in the handle's own space. One place, THREE readers:
# `build_handle` puts the steel eye here, `_stow_path` welds the lead-in link to the same
# point, and `_stow_leave` reads the offset to know which way the rope has to go. It was
# written out twice — and the stow's copy was missing entirely, which is how the two
# drifted 12cm apart.
#
# ---- AND THE ROPE WAS RUNNING THROUGH THE HILT. MEASURED, and there was no reading for
# it until `stow_diag.gd` grew a JOINT block. The eye sat on the handle's AXIS and the
# rope left it along the stow's own down, which works out to 18.1 deg off the shaft — so
# it entered the metal collar's top face and left through its side: `eye ring vs the hilt
# −0.0450 m`, `rope vs the hilt −0.0177 m at seam 1`. A ring laid across the thing it is
# supposed to hang from.
#
# TWO CHANGES, because the ring and the rope were both wrong and they are one problem.
# 1 · THE EYE MOVES OFF THE AXIS, onto the collar's shoulder on the STOW'S OWN SIDE, and
#     up 1cm. `HANDLE_EYE_OUT` is measured against the handle's silhouette
#     (`_handle_radius()` in `stow_diag.gd`: collar 0.038 r, grip 0.032, hand stop 0.046),
#     and it is derived FROM `STOW_ANCHOR`, so the eye is always on the side the surplus
#     hangs on and no second constant can drift.
# 2 · THE EYE'S AXIS BECOMES THE ROPE'S OWN DEPARTURE (`_handle_leave`). A torus is an
#     eyelet: the rope passes through its HOLE, so the axis has to BE the leaving
#     direction. It was 86.3 deg away — a rope through a rim.
const HANDLE_EYE_HEIGHT := 0.150
const HANDLE_EYE_OUT := 0.030
# HOW MUCH OF THE DEPARTURE IS "DOWN" RATHER THAN "TOWARD THE STOW", as a weight against
# the direction from the eye to the stow's anchor (see `_stow_leave`). 1.0 would leave at
# 38 deg off the shaft and still graze the collar's rim; 0.0 is the rope lying along its
# own chord, which the `ARC_LEAD_SLACK` block records as the thing that folds it. 0.70
# leaves at 51.9 deg: past the collar's radius (0.038) within 4cm of travel, with the
# rope already 2cm outboard when it draws level with the collar's top.
const ARC_LEAD_CLEAR := 0.70

# §11 — HOW LONG THE STOW TAKES TO GIVE WAY TO THE THROW, AND TO COME BACK.
#
# This is a RIG-driven blend and not a reach mapping, and that distinction was
# measured rather than chosen. `coils_for()` drives the count from `reach /
# chain_length`, which is honest about the rope — but 左甩 only pays out 3 of the 10
# metres, so at the peak of the sweep it still reported 5 of 8 layers, and the frame
# showed a full stow of chain sitting in front of the very arc it is supposed to be
# the hero of. No monotonic function of reach can fix that, because the reach is not
# what changed: the RIG changed. §1 already says the stow belongs to RIG A (HELD), so
# leaving RIG A is the event that sheds it, and `_coils` stays the rope's own number
# underneath. SHED is fast because a paying-out rope leaves a stow quickly; GATHER is
# slow because re-laying three metres by hand takes a moment, which is also what makes
# "retract → idle" read as the weapon being stowed again rather than teleporting to
# full. §STOW·V4·B names the GATHER explicitly: 不要在一帧里突然生成完整盘链.
const BUNDLE_SHED_TIME := 0.16
const BUNDLE_GATHER_TIME := 0.45
# How much of the stow the throw takes with it, AND THIS NUMBER IS THE USER'S.
#
# §STOW·V4·B specifies A1 as 弧段数量从 4 → 2, i.e. exactly half the layers, and with
# `coil_max` at 4 that pins the share at 0.50 — not "as many as look right". Not 1.0,
# either: at least one layer always stays on the hip, or the rope would start in
# mid-air with nothing left to come out of, which is the joint §6 exists to prevent.
const BUNDLE_SHED_SHARE := 0.50
# §10/§11 — AND THE SHED IS STEPPED, NOT SWEPT. This is the second half of the same
# ruling and it was found by LOOKING at the capture rather than at the number.
#
# `_bundle_fade` used to be a continuous ramp, so 4 → 2 went by in four or five frames
# at 60fps. Every reading agreed with the brief — the count really did come down by
# two — and the PICTURE still showed the held bundle vanishing. A blend that crosses
# both of its own thresholds inside one glance is a cut wearing a blend's clothes, and
# §10 asks for the opposite reading: 玩家明显看到长链从身边被抽出去. §11 asks for the
# mirror of it on the way back, 必须看得见 REPACK.
#
# So the release is a LADDER: one arc at a time, and each step is HELD for a dwell
# before the next is allowed. The dwell is DERIVED from the times above and the number
# of steps rather than typed, so the total shed and gather times the tests already
# measure are exactly preserved and this change cannot silently retime them:
#
#     dwell(release) = BUNDLE_SHED_TIME   / steps = 0.080 s   (4→3, then 3→2)
#     dwell(repack)  = BUNDLE_GATHER_TIME / steps = 0.225 s   (2→3, then 3→4)
#
# 80ms is about five frames — long enough to be a state and not a smear — and 225ms is
# the "re-laying three metres by hand" beat the GATHER comment above already asks for.
const BUNDLE_SHED_STEPS := 2

# ===========================================================================
# §MOTION — THE FLOATING CHAIN IS NOT A DECAL ON THE CAMERA.
# ===========================================================================
#
# FROZEN, AND THIS BLOCK DOES NOT TOUCH IT. What the stow LOOKS like at rest was
# settled and verified — `STOW_ANCHOR`, `STOW_PITCH`, `ARC_SWEEP`, `ARC_LEAN`,
# `HANDLE_EYE_*`, the eye's orientation. Everything below is a perturbation AROUND
# that pose, and every term is written so that AT REST IT IS EXACTLY ZERO. A player
# standing still is drawn by the frozen numbers and nothing else; motion is the only
# thing that can move the stow, and `_lag_safe_scale()` is the only thing that can
# bound it.
#
# WHY A SPRING AND NOT PHYSICS. The brief is explicit: no RigidBody, no JiggleBone,
# no rope solver. What it asks for is CONTROLLED INERTIA — the surplus trails, then
# catches up, and never leaves a box the framing can survive. That is a critically
# damped second-order filter on a target the camera already produces.
#
# WHY THE TARGET IS AN OFFSET AND NOT THE HAND ITSELF, and this is the one design
# decision here that had to be measured rather than reasoned. Tracking the hand's
# POSITION with a 85ms filter looks like the obvious reading of §2, and it is wrong:
# a critically damped filter tracking a RAMP settles at a steady-state error of
# `2·v·τ`, so at a 3.5 m/s walk it would trail 0.60 m — the cap would bind on every
# frame of every walk and the "lag" would be a constant offset with no relationship
# to speed. Worse, that error grows with speed without limit.
#
# So the trail is `speed × MOTION_LAG_PER_SPEED`, capped in metres, and the spring
# filters THAT. The three quantities the brief names are then three separate, legible
# knobs: the trail's SIZE is the metres-per-speed, §2's 50–100ms is the time constant,
# and §5's budget is the cap. None of them can silently absorb another's job.
#
# THE OVERSHOOT IS FREE AND DELIBERATE (§3 玩家停止：浮链继续前移几厘米). A
# critically damped spring has no overshoot in its STEP response, but the spring's
# input here is not a step — it is a velocity, which is already falling when the hand
# stops. The error dynamics are e(t) = (e0 + (ė0 + ω·e0)·t)·e^(-ωt), so a nonzero
# relative rate at the moment the hand stops carries the stow PAST the rest pose
# exactly once before it settles. That is the 几厘米 of §3, and it is measured rather
# than asserted.
const MOTION_LAG_TAU := 0.062
# AND IT IS NOT CRITICALLY DAMPED, WHICH §3 REQUIRES AND MY FIRST READING OF THE BRIEF
# GOT WRONG. The brief offers "spring / damped interpolation" or "简单 critically damped
# vector", and I took the second — then measured an overshoot of exactly ZERO on every
# stop, because §3's 继续前移几厘米 IS an overshoot and the error dynamics of a critically
# damped filter have no zero crossing on a STEP. The step is the right model here too: the
# target is not the hand's position but a velocity-proportional OFFSET (see above), so when
# the hand stops the target returns to zero as a step, not as a ramp, and ζ = 1 settles
# into it without ever passing. ζ = 0.58 gives the ~11% overshoot §3 asks for and still
# decays at ζω = 9.4/s, which is what keeps §9's dodge inside its 300 ms.
const MOTION_LAG_ZETA := 0.58
# How far the stow trails per metre per second of hand speed. 0.0072 s ≈ 2.5cm at a
# walk and 4.6cm at a sprint, i.e. §3's 克制 and §8's 明显向后 in one number.
const MOTION_LAG_PER_SPEED := 0.0072
# THE HARD CAP, in metres. It is NOT the safe-zone rule — `_lag_safe_scale()` is. This
# is the outer bound that also has to hold when there is no camera to project through
# (a headless rig, a test driving `update_chain` directly), so the safe-zone rule can
# never be the only thing between the player and a 40cm chain in the crosshair.
const MOTION_LAG_MAX := 0.055
# §8 — sprint drags visibly harder. Applied to the trail's LENGTH and not to the cap,
# so a sprint cannot buy itself a bigger box than a walk; it only stops lagging sooner.
const MOTION_SPRINT_SHARE := 0.42
const MOTION_SPRINT_SPEED := 6.2
# The hand velocity is smoothed before it drives anything. The handle is drawn with its
# own tremor and look-lag, and a filter that read those as "the player is running"
# would put the stow in permanent motion. Short enough that a dodge is still an impulse.
const MOTION_VEL_TAU := 0.030
# §4 — ROTATION LAGS TOO, AND MUCH LESS IN PITCH.
#
# The target is a steady-state offset proportional to the hand's ANGULAR velocity,
# which is what makes a fast turn leave the fan 3–8° behind and then 回正 when the turn
# stops: the target returns to zero and the filter has nothing left to hold. 8° is a
# cap rather than a taste — a 180°/s turn asks for 13.5° before the clamp, so the clamp
# is doing real work and is mutation-testable.
const MOTION_TURN_TAU := 0.075
const MOTION_TURN_MAX := 0.13962634015954636  # 8°, written as a number so the cap is greppable
# 镜头一抬整束链翻过去 is the failure §4 names, so pitch gets a fraction of the response
# its own rate would ask for.
const MOTION_TURN_PITCH_SHARE := 0.30
# §6 — ONE ROOT, FOUR RESPONSE SPEEDS. The layers may not be four independent objects
# (that is the DEAD KNOT the whole stow revision was fought over), so the major motion
# is shared by the root and each layer adds only a small trail proportional to how far
# its response is from 1.00. Layer 0 is 1.00 ON PURPOSE: the lead-in is welded to it,
# and a layer that trailed away from the eye would tear the rope off its own hand.
const MOTION_LAYER_RESPONSE := [1.00, 0.94, 0.88, 0.82]
# Metres of extra trail on the slowest layer at FULL lag, bounded by the measurement
# that matters: the layers' own clearance is 13.4mm (`stow_ring_readings().layered`),
# and the worst relative shift between ADJACENT layers is (1.00 − 0.94) × this = 1.5mm.
const MOTION_LAYER_SPREAD := 0.025
# §7 — ALIVE, NOT ANIMATED. Two incommensurate low frequencies (periods 5.9s and 4.3s)
# so the sum never repeats on any timescale a player can feel, amplitudes about a
# centimetre, and ZERO AT t = 0 so frame 0 is the frozen pose exactly and the verified
# stills do not move.
const MOTION_IDLE_DRIFT := 0.013   # metres, vertical
const MOTION_IDLE_SWAY := 0.010    # metres, lateral
const MOTION_IDLE_ROLL := 0.019198621771937623  # 1.1°
const MOTION_IDLE_HZ_A := 0.17
const MOTION_IDLE_HZ_B := 0.23
# A frame that hitched must not be allowed to integrate a spring through the floor.
const MOTION_MAX_STEP := 1.0 / 30.0

# §12 — THE TIME CONSTANT THE SURPLUS IS BROUGHT HOME IN WHILE THE CHAIN IS LOADED. It is
# a second constant rather than a flag on the first because §2's 50–100 ms is a description
# of a HELD weapon absorbing a footstep, and a loaded one has a different job: by §12 the
# four layers must 立即 stop drifting when the head bites, and by §10 they must be seen to
# be drawn out of the stow when a technique commits. 22 ms puts a walking trail's last
# centimetre inside three frames at 60 fps — faster than the eye can follow as a motion,
# which is what 立即 means here, while still being a spring and not a teleport.
const MOTION_LOAD_TAU := 0.022

# §5 — THE SAFE-ZONE CLAMP'S HEADROOM, and it is an NDC reading because that is what
# the safe-zone rule is written in (see `stow_breach`).
#
# THE BINDING CONSTRAINT IS THE CROSSHAIR BAND, NOT THE FRAME. The frozen pose reads
# `margin +0.0314` against the 0.38 band and `reach 0.850` against 1.0, so a motion
# has ~0.031 of NDC to spend toward the centre and ~0.135 toward the edge. A trail
# along the view axis changes the projection scale, which moves a point at |x| 0.41 by
# about 0.023 — i.e. the crosshair side is roughly three quarters consumed by a
# maximum-length trail. That is exactly why the clamp exists and why it is a
# PROJECTION test rather than a metres test: 3cm of travel forward and 3cm of travel
# sideways are not the same picture.
const STOW_REACH_LIMIT := 0.985

# How much of the spare chain turns into visible hanging. Bigger = droopier.
const SAG_PER_SLACK := 0.34
const SAG_LIMIT := 0.95
# ONLY THE FIRST FEW METRES OF SPARE ROPE CAN SAG (§1). Past this, the spare rope
# is COILED IN THE PLAYER'S HAND and cannot droop, because it is not in the air.
# Without this cap a 10m rope would spend every frame of every technique pinned at
# `SAG_LIMIT`, and the loose → tight beat of §3 would have no room left to happen.
const SLACK_FOR_SAG := SAG_LIMIT / SAG_PER_SLACK
# Lateral bow per m/s of head speed. Small: a chain trails, it does not flap.
const BOW_PER_SPEED := 0.055
const BOW_LIMIT := 0.85
# Trail: a RIBBON of constant LENGTH in metres, not a fixed count of frames. A
# count would make the trail 8cm long at rest and 20m long at full spin.
const TRAIL_MAX_LENGTH := 2.6
const TRAIL_MIN_POINTS := 5
const TRAIL_MAX_POINTS := 90
const TRAIL_WIDTH := 0.055
# Below this the head is not travelling and has no direction of its own.
const HEAD_AIM_MIN_SPEED := 1.2
# How many links back the fallback tangent is taken from. One link is ~9.5cm, and
# the LAST one carries the whole of the rope's sag and bow, so aiming a head off
# it tilts the blade by tens of degrees exactly when the rope is most visible.
const HEAD_TANGENT_LINKS := 5
# Time constant of the head's own turn. Long enough that a reversal is a swing and
# not a flip, short enough that it still reads as following the throw.
#
# MEASURED, not chosen. `chain_physicality` group C reads the cosine between the
# head's blade and its own direction of travel while a 横缚 is in the air, and a
# first-order filter chasing a direction that is itself rotating lags by `ω·τ`. The
# strike turns the head's bearing at about 26° per frame — 27 rad/s — so at τ =
# 0.045 the blade sat ~70° behind its own motion for the whole of the fastest part
# of every strike: the head spent the strike looking somewhere other than where it
# was going (§5), which is what a ball on a string does. 0.030 puts the lag inside
# a right angle while keeping the turn a turn: a 90° reversal still takes ~3 frames.
const HEAD_TURN_TAU := 0.030

# ===========================================================================
# §0 — CHAIN V4: THREE RIGS, NOT ONE SPLINE.
#
# V3 WAS REJECTED, AND THE REASON IS NOT IN ANY OF ITS NUMBERS. The user's read of
# the clean tour is exact: "摄像机前挂了一条 spline, 末端沿路径运动" — a spline hung in
# front of the camera with something sliding along its end. That is precisely what
# ONE analytic curve from hand to head IS. The head is placed by the move's own
# maths, the rope is then drawn as whatever satisfies those two endpoints, so the
# chain has no identity of its own in any state at all. Coil count, sag, pitch,
# Bezier smoothing — every one of those is polish on a wrong abstraction.
#
# So V4 does not draw the weapon with one span. It draws it with THREE:
#
#   HELD      idle / ready. The authored bundle in the fist, a short hanging chain,
#             the trident resting at the end of it.
#   SWING     A1 / A2 / A3. An authored shape with its own loose → taut beat, and a
#             head that LAGS THE HANDLE — the two things that make a thrown mass
#             read as thrown rather than as translated.
#   TENSION   contact. Hand → contact point, nearly straight, the head LOCKED to the
#             surface it bit. No simulation, and above all no drift.
#
# FAKE THE CHAIN. MAKE THE WEAPON REAL. Gameplay only ever reads the hand anchor,
# the head, the contact point and the hitbox. Every polygon in this file is
# presentation and nothing else reads it.
enum Rig { HELD, SWING, TENSION }

# §12 — HEAD LAG. THE RETURN OF THE THROWN MASS.
#
# A1 asks for 50–120ms between the handle moving and the head arriving, and NO
# value of any other constant in this file can produce it: the head is placed by
# the move's own pose curve, so handle and head move on the same frame by
# construction. The lag is therefore its own layer — a first-order filter on the
# head's POSITION, running in SWING only.
#
# It is presentation and it stays presentation. The hitbox, `ChainDirector._head`
# and every test that reads `head_position()` still see the authoritative point;
# what the player sees is the blade arriving late, which is the whole of the
# cause-and-effect A1 is supposed to have.
#
# 0.055s is measured against the strike rather than chosen: `ch_sweep` turns the
# head through 150° in 0.26s, so a 55ms filter leaves the blade ~32° behind the
# handle at the peak — visible as lag, and short of the head being in the wrong
# place. It decays to nothing by the end of the arc, so the head is on target
# exactly when the strike is.
const RIG_LAG_TAU := 0.055
# Below this much head motion the filter is bypassed entirely, so a chain at rest
# cannot creep toward its own target one millimetre at a time.
const RIG_LAG_MIN_SPEED := 0.6

# §13/§15 — LOOSE → TAUT, DRIVEN BY MOTION AND NOT BY SPARE ROPE.
#
# THE BUG THIS DELETES. Sag was `slack * SAG_PER_SLACK * (1 - tension)` where
# `slack = min(chain_length - reach, SLACK_FOR_SAG)`. On a 10m chain `reach` is
# under 7.2m for every frame of A1, so the min() always returned its cap, every
# frame of every attack drew the maximum droop, and §3's loose → taut beat could
# not happen even in principle. The beat the brief asks for was unreachable.
#
# A swung chain is tight because the head is moving ACROSS the rope, not because
# rope ran out — and that distinction is also what keeps a THROW reading as loose.
# A thrown head travels ALONG its own chain; a swept head travels across it. So the
# tightening is driven by the TANGENTIAL speed only:
#
#   throw  (radial motion, tangential ≈ 0) → the chain hangs all the way out
#   sweep  (across the rope, tangential = full speed) → a near-taut metal arc
#
# which is the reading the eye already has, arrived at for free.
const SWING_SAG_MAX := 0.45
const SWING_TAUT_SPEED := 11.0
# §13/§15 ask for a "loose S-ish curve" at the start and a "near-taut long arc" at
# the peak. The S is the droop aimed SIDEWAYS — away from where the head is being
# dragged — while the chain is still slow. This is how much of it is spent there.
const SWING_LEDE_SHARE := 0.62
# And the trailing bow is let go as the sweep comes up to speed, or the peak of a
# "near-taut" arc would still be bowed by most of a metre.
const SWING_BOW_RELEASE := 0.55

# §19/§20 — THE BITE. A short micro-drive into the surface after contact, so
# "locked" is something the player watches happen rather than something they infer
# from the head having stopped. Then the chain comes up on the same beat.
const CONTACT_SAG := 0.12
const BITE_DRIVE_SHARE := 0.22
# §19 — AND THE TENSION IS A THIRD BEAT, WHICH IT WAS NOT.
#
# §19 names the sequence CONTACT → BITE → TENSION. It was two: `load` was
# `0.35 + 0.65 * _ease(_bite_phase)`, a pure function of the bite, so the load hit
# 1.0 on the same frame the bite did. The tell was in the capture, not in the code —
# the wall take's `chain_v4_wall_bite` and `chain_v4_tension` stills both fired on
# FRAME 265, i.e. two named beats of the sequence had produced ONE picture. A single
# expression cannot be two beats.
#
# The bite is the micro-drive into the material and it keeps its own `bite_time`.
# The load now has its own clock, started at the same contact and running PAST the
# bite, so the rope goes slack-then-straight while the head is already still. 0.26s
# on top of the 0.10s bite puts the trident fully loaded about a third of a second
# into an 0.85s hold, which leaves the held pose on screen long enough to read as a
# state rather than as a frame.
const TENSION_BUILD_TIME := 0.26
# §21 — the handle pays BACKWARD against a loaded chain, by centimetres. This is
# the weapon's own body resistance; it is deliberately not camera shake.
const HANDLE_RESIST := 0.045
# §9 — how far and how far round the wind-up goes. 7.5cm and 19° is enough to be
# felt in the frame and short of the weapon appearing to detach from the hand.
const PRELOAD_REACH := 0.075
const PRELOAD_ROLL := 0.34

# A LOADED LINE HUMS. At full tension the chain shivers: it is the visual half of
# §43's "tension must be perceptible", and it is the one cue that says "at the
# limit" while a straight line alone only says "far away". Deliberately TINY — 13mm
# at full load — because §33 forbids the chain looking like a rubber band, and a
# taut rope that whips around is exactly that. It reads as metal under strain, not
# as slack, and 7.5Hz is above the sway of the idle pose so the two never argue.
const TREMOR_PER_TENSION := 0.013
const TREMOR_HZ := 7.5
# Below this much tension the line is merely out there rather than loaded.
const TREMOR_MIN_TENSION := 0.82

# These are FALLBACKS — `chain_moveset.gd` drives both through `configure()`, and that is
# where the interlock rationale lives. Kept in step with it so a test that builds a
# ChainVisual without a moveset measures the same rope the game draws. See `LINK_FILL`.
var links := 200
var link_spacing := 0.052
var head_size := 0.34
var chain_length := 10.0
var coil_max := 8
var coil_min := 1
var coil_radius := 0.105
# How far apart the bights stack along the bundle's own axis. It was 0.040, which is
# a SPOOL spacing — right for a rope lying in 10cm turns on a form, wrong for a
# gathered fistful. Once the bights are 21–29cm across and the axis leans 39° forward,
# a 4cm pitch walks the bundle 20cm up and 12cm forward of the fist, i.e. out of the
# corner it belongs in and into the middle of the shot. 0.024 keeps the whole bundle
# 0.17m along the axis — tight enough that the bights CROSS instead of stacking, which
# is the crossing §6 asks to see and the one arrangement in which every bight stays
# separately visible from one fixed viewpoint.
var coil_pitch := 0.024

var _link_mesh: MultiMeshInstance3D
var _head: Node3D
var _head_blade: MeshInstance3D
var _trail: MeshInstance3D
var _trail_mesh: ImmediateMesh
var _trail_points: Array[Vector3] = []
var _handle: Node3D
var _tremor_time := 0.0
# The polyline as last drawn, hand → head. Kept and exposed because "the chain looks
# like a chain" is a claim about these numbers: how far the drawn line strays from a
# straight rope is exactly what separates sag, bow and vibration, and a test that
# cannot ask where the links ARE can only assert that something was drawn.
var _points: Array[Vector3] = []
# Where the head is POINTING, kept between frames so it can be eased (§5).
var _head_dir := Vector3.FORWARD
# ---- the V3 drawings, and the one number both of them read -------------------
# How far the head is out, as last handed in. Everything below is derived.
var _reach := 0.0
var _links_drawn := 0
var _coils := 0
# THE STOW. `_coil_root` carries the fan's transform, `_coil_loops` is one node per
# LAYER — index 0 is the arc nearest the fist and the last index is the free end, which
# is the order `_stow_path` walks the rope in and the order `_place_coils` sheds it in.
# The names still say "coil" for the wire-compatible ones (`coil_loops()`, `coils()` are
# read by `chain_physicality`, `chain_v4_slice` and `tools/probe_chain_framing.gd`); a
# "coil" now means one open arc of the stow.
var _coil_root: Node3D
var _coil_loops: Array[MeshInstance3D] = []
# The stow's own centre-line, in STOW SPACE, kept from the build so the safe-zone
# reading can project the real thing instead of a bounding box. Twenty points.
var _stow_seams: Array[Vector3] = []
# ...and where each layer's arc begins in that list, as seam indices. `_stow_path` sets
# it; `_arc_cut()` reads it. Without it a layer would have to be split by an equal share
# of the path, and the lead-in is a third of the path — so hiding the first layer would
# cut the weapon off its own hand.
var _arc_cuts: PackedInt32Array = PackedInt32Array()
# §11 — HOW MUCH OF THE STOW HAS BEEN GIVEN UP TO THE THROW. 0 is the full fan,
# 1 is the attack chain with the hip all but bare. See `_place_coils`.
var _bundle_fade := 0.0
# ...and how many of the stow's layers that fade actually left on screen THIS frame,
# which is the number §11 is a claim about. Kept because a claim that cannot be read
# back is decoration: the first V4 review of the shed was done by eye, on a frame where
# the stow and the rig could each have explained what was there.
var _bundle_shown := 0

# ---- §MOTION state ----------------------------------------------------------
# The lag lives in ONE offset vector and ONE rotation vector, both in the WORLD, and
# both zero at rest. Kept as world vectors rather than as a transform so the spring
# can be re-clamped every frame without ever re-deriving where the stow "should" be
# from a stale pose.
var _motion_off := Vector3.ZERO
var _motion_vel := Vector3.ZERO
var _motion_ang := Vector3.ZERO
var _motion_ang_vel := Vector3.ZERO
var _motion_ready := false
var _motion_prev_target := Transform3D()
var _motion_prev_origin := Vector3.ZERO
var _motion_target_ready := false
var _hand_vel := Vector3.ZERO
var _idle_time := 0.0
# Readings for the review. `_motion_lag` is what was actually applied AFTER the
# safe-zone clamp, and `_motion_lag_scale` is how much of the spring's demand survived
# it — so "did the lag happen" and "did the clamp eat it" are two different numbers
# instead of one picture.
var _motion_lag := Vector3.ZERO
var _motion_lag_scale := 1.0
var _motion_layer_shift := 0.0
# §7's breathing drift, kept SEPARATE from `_motion_lag` on purpose. The hand is under
# the camera rig and is never perfectly still — tremor, look-lag and the sway spring all
# put a millimetre on it — so a reading taken off the total could not tell the designed
# drift from the weapon's own micro-motion, and the assertion that §7 exists passed for
# the wrong reason (removing the drift from the sum entirely left the suite green).
var _motion_idle := Vector3.ZERO
# The frozen pose this frame's perturbation was measured around. Exposed because the
# safe-zone clamp is a pure function of (rest, offset, basis) and a test that wants to
# ask "would a demand no frame can hold be compressed" has to be able to build one.
var _motion_rest := Transform3D.IDENTITY
# §10/§11 — the release ladder's own clock, so a step is HELD rather than swept past.
var _release_step := 0
var _release_hold := 0.0
# The camera the safe-zone clamp projects through, resolved once. Cached because the
# clamp asks six times a frame and `get_viewport().get_camera_3d()` is a tree walk.
var _motion_camera_cache: Camera3D = null
## The pixel size the safe-zone clamp projects through. `Vector2.ZERO` asks the live
## viewport; a headless caller MUST pin it, because a headless viewport is 64x64 and an
## aspect taken from it moves every reading. See `_view_frame`.
var motion_frame := Vector2.ZERO

# ---- V4 — which of the three drawings this frame is -------------------------
var rig := Rig.HELD
# The head AS DRAWN, which in SWING is the filtered one. Everything downstream —
# the links, the trail, the head's own placement — reads this and never the
# director's authoritative `head`, so the lag layer cannot leak into gameplay.
var _vis_head := Vector3.ZERO
var _vis_head_ready := false
# Where the head bit and what surface it bit into. §20's tension curve runs
# hand → THESE, not hand → wherever the director currently thinks the head is: a
# bitten head does not follow anything.
var _contact_point := Vector3.ZERO
var _contact_normal := Vector3.UP
var _contact_age := 0.0
var _bite_phase := 0.0
# §19 — the tension's own clock. Deliberately NOT `_bite_phase`: the bite drives the
# head into the surface over `bite_time`, and the load keeps building after it. See
# `TENSION_BUILD_TIME` for the capture that proved these were being conflated.
var _load_phase := 0.0
var _load := 0.0
# How long the bite lasts. Owned by the director (it is `moveset.wall_bite_time`),
# because the same beat is also an audio event and the two must not be two clocks.
var bite_time := 0.09
# The handle's own displacement, in the hand's local space. §21's backward
# resistance lives here, so it can never be confused with a camera move.
var _handle_offset := Vector3.ZERO
# §14's reading, in WORLD space. `_handle_offset` is the parent-space `position` the
# drawing needs; this is the displacement as a physical quantity, which is the only form in
# which "2–5 cm, toward the thing the chain caught on" is a checkable sentence.
var _handle_resist_world := Vector3.ZERO
var _handle_rot := Vector3.ZERO
# The A1 preload. See `set_preload`.
var _preload := 0.0
var _preload_dir := Vector3.ZERO


func _ready() -> void:
	# The chain lives in world space: the hand moves with the camera and the head
	# moves with nothing at all, so a parent transform would only ever be in the
	# way. `top_level` makes this node's children world-space, which is exactly
	# the coordinate system the director already thinks in.
	top_level = true
	# ...BUT `top_level` KEEPS THE TRANSFORM THE NODE ALREADY HAD. Flipping the flag
	# does not clear it, so this node kept the player's SPAWN position, and every
	# link — whose instance transform is a world coordinate — was drawn offset by
	# it. The head is placed with an explicit global transform and so was correct,
	# which is what made the bug invisible: a chain whose head is on the enemy and
	# whose links are five metres behind it still answers `is_drawn() == true`, and
	# still looks like a chain to a camera that happens to sit where the offset puts
	# it. This node is not a place, it is a coordinate system, so it takes the
	# identity transform and the instance transforms become the world coordinates
	# they were always written as.
	transform = Transform3D.IDENTITY
	_build_links()
	_build_head()
	_build_trail()
	_build_coils()


func configure(
	count: int,
	length: float,
	size: float,
	spacing: float = 0.0,
	coils_max: int = 8,
	coils_min: int = 1
) -> void:
	links = maxi(2, count)
	chain_length = maxf(0.5, length)
	# The link length is the SPACING, not `length / count`: the pool is a ceiling
	# and the drawn subset is what the rope actually needs (§25).
	link_spacing = maxf(0.02, spacing if spacing > 0.0 else length / float(links))
	head_size = size
	coil_max = maxi(1, coils_max)
	coil_min = clampi(coils_min, 0, coil_max)
	if is_inside_tree():
		_build_links()
		_build_head()
		_build_coils()


# The first-person handle. Parented to a camera-space anchor (not to this node)
# so it rides the hand: the chain then runs from screen space out into the world,
# which is the only way a first-person chain reads as attached to the player.
# The COILS ride the same anchor, because they are held, not thrown.
#
# ===========================================================================
# §3 — FIVE PARTS, NOT A BLACK CYLINDER.
#
# V3's handle was a tapered cylinder and a torus, and the user's note on it is the
# design brief: 不是黑色圆柱. A grip with nothing on it is a stick; what makes a
# weapon's handle read as built is that the eye can find the JOINTS — where the
# hand stops, where the metal begins, where the chain leaves, where the weight is.
#
# THE AXIS IS THE FIX. The old grip was rotated a quarter turn, so it lay along the
# VIEW axis while the bundle stood up along the vertical — a grip and a fistful of chain
# on two different axes, which no amount of detailing recovers. The handle is vertical
# and the chain leaves it forward from a collar at the top: one object, one direction.
#
# The stow no longer shares the handle's axis and does not try to (§STOW·V4·B): the run
# from that collar eye at the top of the grip to the fan at the hip IS the attachment,
# and it is 75cm of plainly visible chain rather than a shape that touches the fist.
func build_handle(anchor: Node3D) -> void:
	for child in anchor.get_children():
		if child.name == &"ChainHandleVisual":
			child.queue_free()
	_handle = Node3D.new()
	_handle.name = "ChainHandleVisual"
	anchor.add_child(_handle)
	# ===========================================================================
	# §LIGHT — AND WHY THE FISTFUL AND THE ROPE HAVE TO BE IN THE SAME WORLD.
	#
	# `WeaponRoot` is composited by `ForegroundWeaponLayer`, which moves meshes onto its
	# own render layer and draws them from a `SubViewport` with `own_world_3d`. That
	# world has no Environment and no lights, so anything moved into it renders under a
	# black sky — and the V4 review frame caught the consequence: the SAME `LINK_TINT`
	# with the SAME material read PALE on the thrown rope (a child of `ChainVisual`, on
	# the default layer) and CHARCOAL on this handle's bundle.
	#
	# For THIS weapon that is not survivable, because the handle holds one end of the
	# rope the world is drawing the other end of. Same material, two cameras, two
	# answers — and no lighting work inside a `transparent_bg` viewport fixes it,
	# because the sky that supplies the ambient is exactly what `transparent_bg`
	# removes. So the chain's held parts opt OUT and are drawn by the world camera, like
	# the rope. See `ForegroundWeaponLayer.WORLD_DRAWN`.
	#
	# The cost, stated where it applies: a world-drawn handle can clip into geometry the
	# player stands very close to. For a 10m chain that is a trade worth making.
	_handle.add_to_group(ForegroundWeaponLayer.WORLD_DRAWN)

	# Two materials, because §3 asks for a handle that reads as built out of more
	# than one thing. The wrap is rough and near-diffuse so it carries light in a
	# scene lit by one directional light; the furniture is the same steel family as
	# the links (0.45 metallic) for the reason recorded there — a mirror with
	# nothing to mirror renders black.
	var wrap := StandardMaterial3D.new()
	wrap.albedo_color = Color(0.30, 0.24, 0.21)
	wrap.roughness = 0.88
	wrap.metallic = 0.04
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.58, 0.57, 0.56)
	steel.roughness = 0.42
	steel.metallic = 0.45

	# 1 · THE GRIP. Where the hand actually is, so it is centred on the anchor.
	_handle.add_child(_part(_cylinder(wrap, 0.028, 0.032, 0.190), Vector3(0.0, 0.0, 0.0)))
	# Two wrap ridges, so the grip has a rhythm under the fingers rather than being
	# a smooth rod. Small: 4mm of proud metal, not a knurled grip.
	for k in 2:
		var ridge := Vector3(0.0, -0.045 + 0.045 * float(k), 0.0)
		_handle.add_child(_part(_cylinder(steel, 0.034, 0.034, 0.008), ridge))

	# 2 · THE HAND STOP. The flange that says "the hand goes here and no further".
	_handle.add_child(_part(_cylinder(steel, 0.046, 0.040, 0.018), Vector3(0.0, -0.098, 0.0)))

	# 3 · THE METAL COLLAR. Where the grip stops being a grip.
	_handle.add_child(_part(_cylinder(steel, 0.034, 0.038, 0.034), Vector3(0.0, 0.108, 0.0)))

	# 4 · THE CHAIN EYE. The chain visibly leaves through it, which is the joint
	# that stops the rope looking like it starts in mid-air — and "through" is now
	# literal: the ring is turned so its HOLE faces the direction the rope departs in
	# (`_handle_leave`), where before it stood across the rope at 86.3 deg and the rope
	# crossed its rim. It also sits on the collar's shoulder rather than on the axis
	# (`HANDLE_EYE_OUT`), which is what gives the rope room to clear the hilt.
	var eye := MeshInstance3D.new()
	var eye_mesh := TorusMesh.new()
	eye_mesh.inner_radius = 0.013
	eye_mesh.outer_radius = 0.027
	eye_mesh.rings = 6
	eye_mesh.ring_segments = 8
	eye.mesh = eye_mesh
	eye.material_override = steel
	eye.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	eye.basis = _basis_y_along(_handle_leave())
	eye.position = _handle_eye()
	_handle.add_child(eye)

	# 5 · THE END CAP. §3's rear weight: the reason the thing has mass at the bottom
	# of the fist and does not read as a rod with a ring on top.
	_handle.add_child(_part(_cylinder(steel, 0.041, 0.026, 0.030), Vector3(0.0, -0.120, -0.010)))
	var pommel := MeshInstance3D.new()
	var pommel_mesh := SphereMesh.new()
	pommel_mesh.radius = 0.021
	pommel_mesh.height = 0.042
	pommel_mesh.radial_segments = 8
	pommel_mesh.rings = 4
	pommel.mesh = pommel_mesh
	pommel.material_override = steel
	pommel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pommel.position = Vector3(0.0, -0.142, -0.010)
	_handle.add_child(pommel)

	# Rebuilt here as well as in `_ready`, because before a hand anchor exists
	# there is nowhere for a HELD bundle to live and the rig falls back to a
	# world-space stand-in at the hand. Attaching the real anchor supersedes it.
	_build_coils()


# Node + mesh + where it sits on the handle. Four of the five parts above are the
# same three lines, and writing them out five times is how a handle drifts apart.
func _part(
	mesh: Mesh,
	at: Vector3,
	material: StandardMaterial3D = null,
	rot: Vector3 = Vector3.ZERO
) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	if material != null:
		node.material_override = material
	node.position = at
	node.rotation = rot
	# NO SHADOW, and it is not an optimisation. Once the handle is drawn by the WORLD
	# camera (`WORLD_DRAWN`), its shadow is cast from where the camera is — from the
	# player's own face — and lands on the ground directly in front of them. A
	# first-person weapon is not a thing in the world and must not throw one.
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node


func _cylinder(material: StandardMaterial3D, top: float, bottom: float, height: float,
		segments: int = 10) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = height
	mesh.radial_segments = segments
	mesh.rings = 1
	mesh.material = material
	return mesh


func set_chain_visible(shown: bool) -> void:
	if _link_mesh != null:
		_link_mesh.visible = shown
	if _head != null:
		_head.visible = shown
	if _trail != null and not shown:
		_trail.visible = false
	if _handle != null:
		_handle.visible = shown
	if _coil_root != null and _handle == null:
		_coil_root.visible = shown
	if not shown:
		# The head's aim is eased from its own history, so a chain put away and
		# taken out again must not swing round from wherever it was last pointing.
		_head_dir = Vector3.FORWARD
		_trail_points.clear()


# Is the weapon actually being drawn right now. Asked by tests, and by anything
# that later needs to know whether the chain is in the world without reaching into
# this file's private nodes.
func is_drawn() -> bool:
	return _link_mesh != null and _link_mesh.visible


# ============================================================================
#  §0 — THE THREE RIGS. What the weapon IS, chosen by the game.
# ============================================================================

## Which presentation is being drawn. Called every frame by the director, so it is
## cheap and idempotent: only a CHANGE does any work.
func set_rig(next: Rig) -> void:
	if next == rig:
		return
	rig = next
	# A rig change is a new drawing, not a filter. Carrying the SWING layer's head
	# across would drag a frame-and-a-half-old position into the contact rig, which
	# is the one rig whose entire job is that the head does not move.
	_vis_head_ready = false
	if rig != Rig.TENSION:
		_contact_age = 0.0
		_bite_phase = 0.0
		_load_phase = 0.0
	if rig != Rig.SWING:
		_preload = 0.0


## The head has bitten. `point` is the surface contact in world space, `normal` its
## outward normal. From here the drawing is anchored: the trident is placed ON this
## transform and stays there until the rig changes.
func set_contact(point: Vector3, normal: Vector3) -> void:
	_contact_point = point
	_contact_normal = (
		normal.normalized() if normal.length_squared() > 0.000001 else Vector3.UP
	)
	rig = Rig.TENSION
	_vis_head_ready = false
	_contact_age = 0.0
	_bite_phase = 0.0
	_load_phase = 0.0


## §9 PRELOAD. A 0..1 strength plus the world direction the sweep is coming FROM,
## held for the wind-up and released through the startup. It pulls the HANDLE
## opposite the sweep before it goes: the "cause" half of A1. The head has no
## separate preload curve on purpose — it lags the handle (§12), and a wind-up that
## moved both would be one rigid object, which is the opposite of the brief.
func set_preload(amount: float, from_dir: Vector3) -> void:
	_preload = clampf(amount, 0.0, 1.0)
	_preload_dir = (
		from_dir.normalized() if from_dir.length_squared() > 0.000001 else Vector3.ZERO
	)
	# §10 — AND THIS IS ALSO THE WIND-UP SIGNAL THE LADDER READS. `_preload` is nonzero
	# exactly while a technique is committing, so the first arc leaves DURING 4 → 3 rather
	# than waiting for the swing state — which is §10's ordering, produced by a signal the
	# director already sends, with no new channel between the two files and no flag that can
	# latch. See `_update_release`.


## How far through the bite the drawing is, 0 at contact and 1 when the head has
## finished driving into the surface. Exposed because "the head locked to the wall"
## is a claim about this number and not about a picture.
func bite_phase() -> float:
	return _bite_phase


## The head as last DRAWN. In SWING this is the lagged one; a test that wants to
## know whether the lag is real asks this and `ChainDirector.head_position()` and
## compares them, rather than trusting that a filter was installed.
func drawn_head() -> Vector3:
	return _vis_head


# ---- §MOTION readings -------------------------------------------------------
#
# Exposed for exactly the reason `drawn_head()` is: "it has inertia" is a claim about
# NUMBERS, and a test that can only see a picture cannot tell a lag from a decal painted
# on the camera. Each of these answers one of the brief's questions and nothing else.
#
# The lag ACTUALLY APPLIED, in world metres, after the safe-zone clamp. At rest this is
# the §7 idle drift and the drag part is zero, which is what makes "did it lag" and "is it
# alive at rest" two different readings off one number.
func motion_lag() -> Vector3:
	return _motion_lag


## THE INERTIA ALONE — the spring's own offset, with §7's breathing drift excluded and
## §5's clamp not applied.
##
## Split out from `motion_lag()` because the two answer different questions and the first
## version of the test conflated them: the idle drift is about a CENTIMETRE by design, so a
## "has the kick settled" reading taken against the TOTAL can never fall below the drift and
## reported a 667 ms settle for a spring that had actually finished in about a hundred. A
## reading that cannot go below its own noise floor is not a reading.
func motion_drag() -> Vector3:
	return _motion_off


## §7 — THE BREATHING DRIFT ALONE, with the inertia excluded. The counterpart of
## `motion_drag()` for the other half of the offset, and split out for the same reason:
## "the chain is alive at rest" and "the chain is being dragged" are different claims and
## one total cannot carry both.
func motion_idle() -> Vector3:
	return _motion_idle


## The frozen pose the current perturbation is measured around, as an unperturbed
## transform. The safe-zone clamp is a pure function of this, an offset and a basis, so
## this is what lets a test build a demand rather than wait for one to happen.
func motion_rest() -> Transform3D:
	return _motion_rest


## §14 — HOW FAR THE HANDLE HAS BEEN HAULED, in its parent's space. `HANDLE_RESIST` is the
## whole of §14's 2–5 cm and this is the only way to know it lands there: the constant
## exists, the load exists, and neither of them is the displacement. The VECTOR is returned
## rather than its length because the direction is the other half of the claim — a handle
## pulled in the wrong direction is still 4.5 cm of weight and is still wrong.
func handle_resist() -> Vector3:
	return _handle_resist_world


## How much of the spring's demand survived §5's clamp. 1.0 means the clamp never had to
## intervene; below that, the motion was compressed to keep the crosshair rule.
func motion_lag_scale() -> float:
	return _motion_lag_scale


func motion_lag_limit() -> float:
	return MOTION_LAG_MAX


## §4 — the angle the fan is currently behind the hand by, in radians.
func motion_turn_lag() -> float:
	return _motion_ang.length()


func motion_turn_limit() -> float:
	return MOTION_TURN_MAX


## The smoothed hand speed the trail is computed from. Reported because the trail is
## `speed × MOTION_LAG_PER_SPEED`, so a take that claims to show a sprint can be checked
## against the number that actually drove the drag.
func motion_hand_speed() -> float:
	return _hand_vel.length()


## §6 — how far each layer has been leaned back, in metres. Layer 0 must be exactly 0.0
## (the lead-in is welded to it) and the list must be non-increasing, because a list that
## ran the other way would mean the OUTERMOST arc was leading the hand.
func motion_layer_offsets() -> Array[float]:
	var out: Array[float] = []
	for loop in _coil_loops:
		out.append(loop.position.length())
	return out


## Where the stow root was actually written this frame. The motion is a transform, so a
## reading that only reported an offset vector could not tell a moved root from a moved
## anchor.
func motion_root_origin() -> Vector3:
	return _coil_root.global_transform.origin if _coil_root != null else Vector3.ZERO


## §10/§11 — how many arcs the release ladder has taken away, and the ladder's own step
## count, so "the shed is stepped" can be asserted as a reachable set of counts rather
## than inferred from a fade value.
func release_step() -> int:
	return _release_step


func release_steps() -> int:
	return BUNDLE_SHED_STEPS


## How loaded the chain is, 0..1: tension while swinging, the bite's own ramp while
## anchored. The single number the sag and the handle's resistance both read.
func load() -> float:
	return _load


## The wind-up in force, 0..1. See `set_preload` — §9's claim is that A1 moves the
## handle the WRONG WAY before it goes, and that is a claim about this number.
func preload_amount() -> float:
	return _preload


# ---- §25/§26, THE TWO ANSWERS THE DRAWING IS MADE OF ------------------------
# Both pure functions of the reach, so a test can ask what the drawing WILL do
# without running a frame — and so the rig and the assertion can never drift.

# How many links the rope is drawn with at this reach. A CONSTANT LINK SIZE:
# two links hanging at rest, eighty-seven at full stretch, same 9.5cm each.
func visible_links_for(reach: float) -> int:
	return clampi(int(roundf(maxf(0.0, reach) / maxf(0.001, link_spacing))), 2, links)


# How many loops are still coiled in the hand, `coil_min` .. `coil_max`.
func coils_for(reach: float) -> int:
	var paid := clampf(maxf(0.0, reach) / maxf(0.001, chain_length), 0.0, 1.0)
	return int(roundf(lerpf(float(coil_max), float(coil_min), paid)))


# What the last update actually drew. The claim "the weapon looks long while it is
# idle and short while it is thrown" is a claim about these two integers.
func links_drawn() -> int:
	return _links_drawn


func coils() -> int:
	return _coils


# §11 — how many turns of the fistful the last frame actually SHOWED. `coils()` is the
# rope's own number and stays high through a throw; this one is the drawing's, and it
# is the one that has to fall when the rig leaves HELD.
func drawn_bundle() -> int:
	return _bundle_shown


func coil_loops() -> Array[MeshInstance3D]:
	return _coil_loops


func update_chain(
	hand: Vector3,
	head: Vector3,
	head_velocity: Vector3,
	tension: float,
	delta: float
) -> void:
	if _link_mesh == null:
		return
	var taut := clampf(tension, 0.0, 1.0)
	_tremor_time += delta
	_contact_age += delta

	# ---- 1 · WHICH HEAD IS BEING DRAWN -----------------------------------
	#
	# The one place the three rigs disagree about where the weapon IS. Everything
	# downstream — the rope's endpoints, the links, the trail, the trident — reads
	# `target` and never `head`, so the lag layer cannot leak into the hitbox.
	var target := head
	var forced_dir := Vector3.ZERO
	if rig == Rig.TENSION:
		# §19 THE BITE. The head arrives at the surface and then drives SHORT of
		# it over `bite_time`, and stays there. `_contact_point` is the surface, so
		# the blade ends up inside the material it bit — which is what "咬住" means
		# and what a head merely stopped in front of the wall never says.
		_bite_phase = clampf(_contact_age / maxf(0.01, bite_time), 0.0, 1.0)
		# §19 — the load's own clock, running past the bite. See `TENSION_BUILD_TIME`.
		_load_phase = clampf(
			_contact_age / maxf(0.01, bite_time + TENSION_BUILD_TIME), 0.0, 1.0
		)
		target = _contact_point - _contact_normal * head_size * BITE_DRIVE_SHARE * _ease(_bite_phase)
		# §18 — orientation. The central blade runs INTO the surface, so the
		# trident's own axis is -normal and the fork opens back out of the wall.
		forced_dir = -_contact_normal
		_vis_head = target
		_vis_head_ready = true
	elif rig == Rig.SWING:
		if _vis_head_ready:
			# §12 — THE LAG. A first-order filter, so the drawn head trails the
			# authoritative one by ~`RIG_LAG_TAU` of travel: at the peak of a
			# 150°/0.26s sweep the blade sits about 30° behind the handle, which is
			# the difference between a swung mass and a translated one. It decays
			# to nothing as the arc ends, so the head is on target when it lands.
			var blend := 1.0 - exp(-maxf(delta, 0.0001) / RIG_LAG_TAU)
			_vis_head = _vis_head.lerp(head, blend)
		else:
			_vis_head = head
			_vis_head_ready = true
		target = _vis_head
	else:
		_vis_head = head
		_vis_head_ready = true
		target = _vis_head

	# ---- 2 · THE ROPE'S SPARE, AND HOW MUCH OF IT CAN HANG ----------------
	#
	# TWO REACHES, AND THEY ARE DELIBERATELY NOT THE SAME ONE (§2/§25).
	#
	#   paid_out    hand → the head the DIRECTOR owns. How many metres are still
	#               coiled in the fist is a fact about the weapon, and it may not
	#               wobble because the drawing is a frame and a half behind. This is
	#               what the BUNDLE reads — measured, because reading the lagged span
	#               instead left 3 loops in the hand at 8.8m of throw and reddened
	#               `chain_physicality`'s "the rope is not paying out".
	#   drawn_reach hand → the head AS DRAWN. The LINKS read this, because they are
	#               placed along that very polyline and a count that disagreed with
	#               its own span would change the link SIZE mid-throw (§25).
	var paid_out := hand.distance_to(head)
	var drawn_reach := hand.distance_to(target)
	var span := target - hand
	# §1: only the rope that is IN THE AIR can hang. Every metre past this cap is
	# coiled in the fist, so it contributes nothing to the shape of the span.
	var slack := minf(maxf(0.0, chain_length - paid_out), SLACK_FOR_SAG)
	var sag := minf(SAG_LIMIT, slack * SAG_PER_SLACK) * (1.0 - taut)

	# ---- 3 · §15 · WHAT ACTUALLY TIGHTENS A CHAIN -------------------------
	#
	# Only the part of the head's motion ACROSS the rope. A thrown head runs along
	# its own chain and the rope stays slack all the way out — which is exactly
	# what a throw should look like and what `chain_physicality` group B measures.
	# A swept head runs across the rope, and THAT is what pulls it straight.
	var cross_dir := Vector3.ZERO
	var fast := 0.0
	if span.length() > 0.05:
		var rope_dir := span.normalized()
		var tangential := head_velocity - rope_dir * head_velocity.dot(rope_dir)
		if tangential.length() > 0.05:
			cross_dir = tangential.normalized()
		if rig == Rig.SWING:
			fast = clampf(tangential.length() / SWING_TAUT_SPEED, 0.0, 1.0)
			sag = minf(sag, SWING_SAG_MAX * (1.0 - fast) * (1.0 - taut))

	var load := taut
	# §20 — ANCHORED. The chain comes up straight as the bite completes, and the
	# droop it had while it was merely thrown is not part of the anchored picture.
	if rig == Rig.TENSION:
		sag = CONTACT_SAG * (1.0 - _ease(_load_phase))
		load = clampf(0.35 + 0.65 * _ease(_load_phase), 0.0, 1.0)
	_load = load

	# §13 — THE LEDE. While the head is still slow the droop leans AWAY from where
	# it is about to be dragged, which is the loose S at the top of the arc; as the
	# sweep comes up to speed the droop goes straight down and then disappears.
	var sag_dir := Vector3.DOWN
	if rig == Rig.SWING and cross_dir != Vector3.ZERO:
		sag_dir = (
			Vector3.DOWN - cross_dir * ((1.0 - fast) * SWING_LEDE_SHARE)
		).normalized()

	# The chain trails a fast head. Using the horizontal velocity keeps a
	# vertical slam from bowing the chain into the floor, the same mistake the
	# wind gust made when it carried its pitch.
	var flat := Vector3(head_velocity.x, 0.0, head_velocity.z)
	var bow := Vector3.ZERO
	if rig != Rig.TENSION and flat.length() > 0.05:
		var pull := minf(BOW_LIMIT, flat.length() * BOW_PER_SPEED) * (1.0 - taut)
		if rig == Rig.SWING:
			# …and the trail is let go as the sweep hits its own speed, or the
			# peak of a "near-taut" arc would still be bowed by most of a metre.
			pull *= 1.0 - fast * SWING_BOW_RELEASE
		bow = -flat.normalized() * pull

	# THE HUM. Perpendicular to the line, horizontal, zero when the chain is not
	# loaded. It rides the same arch as sag and bow so the ends stay pinned: a chain
	# that vibrated at the hand would look like the PLAYER was shaking.
	var tremor := Vector3.ZERO
	var hum := clampf((load - TREMOR_MIN_TENSION) / maxf(0.001, 1.0 - TREMOR_MIN_TENSION), 0.0, 1.0)
	if hum > 0.0:
		var axis := span
		axis.y = 0.0
		if axis.length() > 0.05:
			axis = axis.normalized()
			tremor = (
				Vector3(-axis.z, 0.0, axis.x)
				* TREMOR_PER_TENSION
				* hum
				* sin(_tremor_time * TAU * TREMOR_HZ)
			)

	_reach = paid_out
	_links_drawn = visible_links_for(drawn_reach)
	_coils = coils_for(paid_out)
	# §11 — the fistful makes way for the throw, and since §10/§11 it does so as a STEPPED
	# LADDER with a dwell per arc. Driven once per frame by `_update_release`; it is not
	# integrated here any more, because one expression of the release is what lets the
	# release and the repack be timed against each other.

	# The span is drawn with exactly as many links as the paid-out rope needs, and
	# they are placed at even fractions of it — so the link size is a property of
	# the WEAPON and not of how far the throw went (§25).
	var drawn := _links_drawn
	var points: Array[Vector3] = []
	points.resize(drawn + 1)
	for i in range(drawn + 1):
		var t := float(i) / float(drawn)
		var arch := sin(PI * t)
		points[i] = hand.lerp(target, t) + sag_dir * sag * arch + (bow + tremor) * arch
	_points = points
	_place_links(points, drawn)
	_place_head(target, points, head_velocity, delta, forced_dir)
	_place_handle(hand, target)
	_update_release(delta)
	_place_coils(hand, delta)
	_update_trail(target, delta)


func _ease(t: float) -> float:
	var x := clampf(t, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)


# §9 and §21 — THE HANDLE IS THE THING THAT MOVES.
#
# Two displacements, both in the HAND's own space so they read as body motion and
# never as a camera move:
#
#   the preload   the wind-up. A1 pulls the handle 7cm the wrong way before it
#                 goes, which is the "cause" the brief asks for and the half of
#                 weight that no amount of camera shake can supply.
#   the resist    the load. A chain pulled tight hauls the weapon root back along
#                 its own bearing — centimetres, not shake (§15 forbids the shake).
func _place_handle(hand: Vector3, head: Vector3) -> void:
	if _handle == null:
		return
	var want := Vector3.ZERO
	if _preload > 0.0:
		want -= _preload_dir * (_preload * PRELOAD_REACH)
	var to_head := head - hand
	if _load > 0.0 and to_head.length() > 0.05:
		want += to_head.normalized() * (_load * HANDLE_RESIST)
	# Kept in WORLD space before it is turned into a parent-space `position`, because the
	# direction is half of §14's claim and a displacement expressed in the hand's own frame
	# cannot be compared with the rope. See `handle_resist()`.
	_handle_resist_world = want
	var parent := _handle.get_parent() as Node3D
	if parent != null:
		want = parent.global_basis.inverse() * want
	_handle_offset = want
	_handle.position = want
	_handle.rotation = Vector3(0.0, 0.0, -_preload * PRELOAD_ROLL)


# Where the links were last drawn, as a copy: hand → head, one point per link seam.
func drawn_points() -> Array[Vector3]:
	return _points.duplicate()


# How far the drawn chain strays from the straight line between its own ends, in
# metres. This single number is the difference between a rope under load and a rope
# hanging — and it is bounded on purpose: §33 forbids the rubber band.
func drawn_slack() -> float:
	if _points.size() < 3:
		return 0.0
	var a := _points[0]
	var b := _points[_points.size() - 1]
	var span := b - a
	var length := span.length()
	if length < 0.0001:
		return 0.0
	var worst := 0.0
	for i in range(1, _points.size() - 1):
		var offset := _points[i] - a
		worst = maxf(worst, (offset - span * (offset.dot(span) / (length * length))).length())
	return worst


func _build_links() -> void:
	if _link_mesh == null:
		_link_mesh = MultiMeshInstance3D.new()
		_link_mesh.name = "Links"
		add_child(_link_mesh)
	_link_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mesh := _link_geometry()
	var material := _link_material()
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = mesh
	# The POOL. Only `visible_instance_count` moves per frame — allocating 96 and
	# drawing 2 costs one buffer, not two allocations.
	multi.instance_count = links
	multi.visible_instance_count = links
	_link_mesh.multimesh = multi


# §0 — THE TRIDENT. Central piercing blade, two splayed side blades, two rear
# barbs, one heavy collar where the rope enters.
#
# It has to support 刺 / 钩 / 贯穿 / 拉扯 / 扫击 with its SILHOUETTE ALONE, because
# that is all a player gets while it is doing 40 m/s across the middle of the
# screen. So the three readings are separate parts rather than one shape doing
# everything: the central spike IS 贯穿 (long, straight, on the chain axis), the
# splayed pair is 扫击 (a wide fork), and the rear barbs are 钩 / 拉扯 — they face
# BACKWARD, so the head still holds something when the chain is hauled.
#
# §4: geometry and material only. No glow, no trail-as-identity — those are
# decoration over a shape that has to work on its own. Local forward is -Z.
func _build_head() -> void:
	if _head == null:
		_head = Node3D.new()
		_head.name = "TerminalHead"
		add_child(_head)
	# Rebuilt in place rather than queued: `configure` may run after `_ready`, and
	# a frame of doubled trident is a frame the review will photograph.
	for child in _head.get_children():
		_head.remove_child(child)
		child.free()

	var material := StandardMaterial3D.new()
	material.albedo_color = HEAD_TINT
	# §HEAD METAL — THE SAME TRAP AS THE LINKS, AND IT WAS STILL OPEN HERE.
	#
	# 0.95 metallic / 0.22 roughness is a mirror, and a mirror with nothing to
	# mirror is black. The whole weapon is lit by one directional light plus a sky,
	# so the head — the single object the player has to track at 40m/s — rendered in
	# the first V3 tour as a pure black speck: HEAD_TINT is a pale bone-steel
	# (0.78, 0.76, 0.71) and NONE of it was reaching the frame.
	#
	# The V4 review frame shows the OPPOSITE failure: the blades came back pure white
	# with no shading across their faces, so five prisms read as five separate paper
	# shards rather than as one object with facets. Metallic was lowered to 0.30 for
	# that, and it was NOT ENOUGH — because with one directional light plus a sky, a
	# 0.84 albedo saturates whatever the metallic is: the head was still a white
	# cut-out in the PASS A frame. 0.68 is the number that keeps the facets.
	# the links settled on for the same reason, and roughness up a little keeps a
	# highlight on the edge without flattening the face.
	material.roughness = 0.44
	material.metallic = LINK_METALLIC

	var h := head_size
	# ---------------------------------------------------------------------
	# WHAT THIS SHAPE HAS TO DO, AND WHAT IT WAS DOING INSTEAD.
	#
	# §4 asks for four things (central piercing blade, two outward hook blades, a
	# reinforced central body, a chain attachment) whose SILHOUETTE reads as a trident
	# at 6–10m. The V4 review frame showed the shape failing at 1.3m, which is the
	# generous case: five prisms of 0.66m, 0.40m, 0.40m, 0.22m and 0.22m growing out of
	# a body 0.12m across. A blade 23 times longer than it is thick, mounted on a nut,
	# is not a trident — it is a shard, and five of them are five shards.
	#
	# So every number below is a RATIO against the old worst offenders, and the two
	# that matter are these:
	#
	#   THICKNESS   was 0.085h on the central blade. It is 0.20h now — the blade is
	#               still 5:1, which reads as a blade, instead of 23:1, which reads as
	#               a splinter that happens to be sharp.
	#   BODY        was a 0.42h-wide hub. The body is now 0.64h across and 0.95h long,
	#               so there is a middle for the fork to be MOUNTED on — §4's
	#               "reinforced central body", and the thing that makes three points
	#               read as one weapon.
	#
	# And the fork must NOT splay far. The first V4 pass read "a trident is a wide shape,
	# a pair of near-parallel prongs is a carving fork" and pushed the side prongs to
	# 0.85 of the axis — 40°. THE FRAME REFUTED THE SENTENCE: five pale prisms radiating
	# from one point is a STARFISH, and no amount of correct thickness on each prism
	# fixes a bad arrangement of five. The two shapes are not distinguished by width;
	# they are distinguished by whether the points SHARE A DIRECTION. Real tines splay
	# 20°ish and stay parallel; a fan to 40° stops being a fork of any kind. 0.40 is
	# 22°, and the rear flukes came down from 0.58h to 0.40h for the same reason — they
	# were the fourth and fifth prongs of the starfish.
	# ---------------------------------------------------------------------

	# 1 · THE REAR COLLAR. Where the rope enters, and the heaviest single volume — the
	#     head has to look like it is on the END of a chain, not skewered by one.
	var hub := MeshInstance3D.new()
	var hub_mesh := CylinderMesh.new()
	hub_mesh.top_radius = h * 0.20
	hub_mesh.bottom_radius = h * 0.26
	hub_mesh.height = h * 0.24
	hub_mesh.radial_segments = 8
	hub.mesh = hub_mesh
	hub.material_override = material
	hub.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	hub.rotation.x = PI * 0.5
	hub.position = Vector3(0.0, 0.0, h * 0.38)
	_head.add_child(hub)

	# 2 · THE REINFORCED BODY. One solid step down from the collar to the shoulder, so
	#     the eye has an unbroken middle to hang the fork on.
	_head.add_child(_part(
		_cylinder(material, h * 0.30, h * 0.32, h * 0.62, 8),
		Vector3(0.0, 0.0, h * 0.02),
		material,
		Vector3(PI * 0.5, 0.0, 0.0)
	))
	# 3 · THE SHOULDER / CROSSBAR. §4's mount: one disc, so the three blades are
	#     visibly born of something rather than converging at a point.
	_head.add_child(_part(
		_cylinder(material, h * 0.30, h * 0.34, h * 0.22, 8),
		Vector3(0.0, 0.0, -h * 0.36),
		material,
		Vector3(PI * 0.5, 0.0, 0.0)
	))

	# 4 · 贯穿 — the central blade. The longest of the three, on the weapon's own axis,
	#     and the reason the head's direction is legible from any angle.
	#
	#     §V4·PASS A — THICKNESS IS THE READ, NOT LENGTH. `_blade` builds every tine
	#     through `_basis_y_along`, which puts ALL FIVE of them in ONE PLANE: the head
	#     is a flat fork. A flat fork reads as a trident from exactly the rolls where
	#     the fork faces the eye, and as a handful of separate slivers from every other
	#     roll — and a chain head TUMBLES, so every roll happens. With a 0.20h thickness
	#     on a 0.40h width the edge-on case was a 7cm card, i.e. nothing, which is the
	#     frame that came back. 0.32h is 80% of the width: the tine is a solid spine
	#     that keeps its mass at any roll, and the fork silhouette is then a bonus
	#     rather than the only way the head can be recognised.
	_head.add_child(_blade(material, h * 1.40, h * 0.42, h * 0.32,
		Vector3(0.0, 0.0, -1.0), Vector3(0.0, 0.0, -h * 0.44)))
	# 5 · 钩 — §4's two OUTWARD HOOK BLADES, and THE MEASURED CORRECTION. They used to
	#     leave at 0.85 of the axis, which is 40°, and the frame came back a STARFISH:
	#     five pale prisms radiating from one point, which is a shape no eye reads as a
	#     weapon. A trident's tines are near-PARALLEL with a modest splay; a 40° fan is
	#     a sea urchin. 0.34 is 19°, so the three points still separate at a glance
	#     while sharing one direction — which is the whole of the trident read.
	#
	#     §V4·PASS C — AND THEY ARE LIFTED OUT OF THE PLATE. Every direction here used
	#     to lie in the world XZ plane, and `_blade` builds a blade's WIDTH along
	#     `UP × direction` (horizontal) and its THICKNESS along the third axis — so
	#     when every direction is horizontal the entire head is a PLATE LYING FLAT, and
	#     every blade in it is 0.32h of vertical card. A camera at eye height looking
	#     along the sweep sees that plate EDGE-ON. The frame proves it: mid-sweep the
	#     trident came back a single long NEEDLE, because the splayed pair had collapsed
	#     onto the central blade's own line. It read correctly in the hand, where the
	#     head points at the lens, and that was the trap — a fork only reads from the
	#     rolls where it faces you, and a chain head tumbles through all of them.
	#     +0.30 Y costs no width and no splay, so it cannot re-open the starfish; it
	#     just means the three points are separated in EVERY projection rather than in
	#     one. From the side: central forward, the pair above, the barbs below.
	_head.add_child(_blade(material, h * 0.82, h * 0.30, h * 0.26,
		Vector3(-0.34, 0.30, -1.0), Vector3(-h * 0.17, h * 0.06, -h * 0.34)))
	_head.add_child(_blade(material, h * 0.82, h * 0.30, h * 0.26,
		Vector3(0.34, 0.30, -1.0), Vector3(h * 0.17, h * 0.06, -h * 0.34)))
	# 6 · 拉扯 — the flukes that hold a wall. THEY ARE DELIBERATELY SMALL AND TIGHT.
	#     At 0.58h on a 0.55 splay they were the fourth and fifth prongs of the
	#     starfish, reading as two more points in the silhouette. They are 0.40h now,
	#     they sit right against the reinforced body, and they turn almost straight
	#     back — so they are FLUKES on the head rather than blades off it, which is
	#     what a hook on a bodkin is. The forward silhouette is three points again.
	#     §V4·PASS C — and they carry the DOWN half of the same correction: they are
	#     the head's only points below its own axis, which is what gives the side view
	#     its third reading the moment the pair above goes up. Still 0.40h, still
	#     against the body: the correction is DIRECTION, not size.
	_head.add_child(_blade(material, h * 0.40, h * 0.24, h * 0.20,
		Vector3(-0.62, -0.30, 1.0), Vector3(-h * 0.20, 0.0, -h * 0.22)))
	_head.add_child(_blade(material, h * 0.40, h * 0.24, h * 0.20,
		Vector3(0.62, -0.30, 1.0), Vector3(h * 0.20, 0.0, -h * 0.22)))

	_head_blade = _head.get_child(_head.get_child_count() - 5) as MeshInstance3D


# §4 — A BLADE, AS OPPOSED TO A CONE.
#
# A `CylinderMesh` with no top radius is a cone, and a cone of the right thickness
# to look dangerous is a 3-pixel needle from the side — which is the view a player
# has of a head doing 20 m/s. §4 asks for SILHOUETTE and for a head that is still
# legible at 6–10m, and that is a statement about AREA, so the blades are flattened
# prisms instead: a diamond base ahead of a shoulder, tapering to a point.
#
# Six triangles, built with a SurfaceTool and normals generated — cheap enough to
# put five of them on one head, and the flat faces are what catch the directional
# light so the trident is not a black speck the moment it leaves the hand.
#
# Local +Y is the point; `direction` sends it there and `at` is the MOUNT POINT the
# base sits on, so the point ends up one `length` along `direction` from `at`.
func _blade(material: StandardMaterial3D, length: float, width: float, thickness: float,
		direction: Vector3, at: Vector3) -> MeshInstance3D:
	var b0 := Vector3(-width * 0.5, 0.0, 0.0)
	var b1 := Vector3(0.0, 0.0, -thickness * 0.5)
	var b2 := Vector3(width * 0.5, 0.0, 0.0)
	var b3 := Vector3(0.0, 0.0, thickness * 0.5)
	# The shoulder: the blade widens a little before it tapers, so it has a base
	# rather than being a sliver that starts at a point.
	var m := length * 0.34
	var s0 := Vector3(-width * 0.62, m, 0.0)
	var s1 := Vector3(0.0, m, -thickness * 0.34)
	var s2 := Vector3(width * 0.62, m, 0.0)
	var s3 := Vector3(0.0, m, thickness * 0.34)
	var apex := Vector3(0.0, length, 0.0)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# lower half: base diamond → shoulder
	_quad(st, b0, b1, s1, s0)
	_quad(st, b1, b2, s2, s1)
	_quad(st, b2, b3, s3, s2)
	_quad(st, b3, b0, s0, s3)
	# upper half: shoulder → point
	_tri(st, s0, s1, apex)
	_tri(st, s1, s2, apex)
	_tri(st, s2, s3, apex)
	_tri(st, s3, s0, apex)
	# the base, so the blade is closed and does not read as a hole from behind
	_quad(st, b0, b1, b2, b3)
	st.generate_normals()
	var node := MeshInstance3D.new()
	node.mesh = st.commit()
	# THE MATERIAL ARGUMENT WAS NEVER USED. Every tine in this weapon has been drawing
	# with Godot's DEFAULT material — albedo 1.0, metallic 0, roughness 1 — which is
	# exactly the "flat white paper" the review frame kept showing. It is why lowering
	# `HEAD_TINT` from 0.84 to 0.68 changed the FRAME not at all while the hub and the
	# body beside the tines went grey: those two go through `_part()`, which sets
	# `material_override`, and the five blades did not. A parameter that is accepted and
	# ignored is invisible in every way except the picture.
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var dir := direction.normalized()
	# ===========================================================================
	# THE BASE GOES ON `at`. THIS IS THE BUG THE "LOOSE SHARDS" FRAME WAS SHOWING.
	#
	# This line used to read `at + dir * (length * 0.5)`, which pushed every tine
	# half its own length AWAY from the body it is mounted on. The local geometry puts
	# the base diamond at local Y=0 and the point at local Y=`length`, so the offset
	# moved the base a half-length down the axis: the central blade's base landed at
	# z = −1.20h against a shoulder that ends at z = −0.47h, a 0.73h = 25cm hole
	# between the fork and the body it grows out of.
	#
	# THE GAP IS INVISIBLE AT RANGE AND UNMISSABLE AT ARM'S LENGTH, which is why it
	# survived every take that threw the head out to 3m or more, and why the first
	# close review frame read as "five pale shards floating apart". Perspective closes
	# a 25cm gap over 6 metres; nothing closes it at 1.3m. The header comment a screen
	# above was written believing the blades "grow out of a body" — they did not, and
	# no amount of thickness, splay or material on the tines could have fixed that.
	#
	# `at` is a MOUNT POINT now, and means one thing: the base sits on it and the point
	# is one `length` further along `direction`. Every `at` in `_build_head` is a point
	# inside the reinforced body or the shoulder.
	# ===========================================================================
	node.transform = Transform3D(_basis_y_along(dir), at)
	return node


func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)


func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	_tri(st, a, b, c)
	_tri(st, a, c, d)


# A basis whose +Y is `direction`. See `_blade` and `_place_coils`.
func _basis_y_along(direction: Vector3) -> Basis:
	var y := direction.normalized()
	var ref := Vector3.UP
	if absf(y.dot(Vector3.UP)) > 0.95:
		ref = Vector3.FORWARD
	var x := ref.cross(y).normalized()
	var z := x.cross(y).normalized()
	return Basis(x, y, z)


# §6/§STOW — the stow, built as a PATH and decorated with the rope's own links. See
# the constant block above for what and why, and `_stow_path` for what the path is.
#
# Parented to the handle anchor when there is one, because a stow is worn: it has to
# ride the hand and the camera shake, not the world.
func _build_coils() -> void:
	var parent: Node = _handle if _handle != null else self
	if _coil_root != null:
		if _coil_root.get_parent() != null:
			_coil_root.get_parent().remove_child(_coil_root)
		_coil_root.free()
		_coil_loops.clear()
	_coil_root = Node3D.new()
	_coil_root.name = "HeldStow"
	parent.add_child(_coil_root)

	var material := StandardMaterial3D.new()
	material.albedo_color = LINK_TINT
	# §5 — the same metal as the rope, and the same warning applies: a metallic surface
	# with nothing to reflect renders black, and this one is photographed at half a
	# metre with four layers shading each other. 0.45 was still dark; see LINK_METALLIC.
	material.roughness = 0.44
	material.metallic = LINK_METALLIC

	var link_mesh := _link_geometry()
	var seams := _stow_path()
	_stow_seams = seams
	# ONE NODE PER LAYER, split at the SEAM INDEX WHERE THE ARC BEGINS — not at an equal
	# share of the path. The lead-in is 0.74m of a 2m path, a third of it, so an even
	# split would fold most of the run from the fist into the first layer and hiding that
	# layer would cut the rope off its own hand. `_stow_path` records the cuts; this reads
	# them.
	for layer in coil_max:
		var a := _arc_cut(layer, seams.size())
		var b := _arc_cut(layer + 1, seams.size())
		var arc := MeshInstance3D.new()
		arc.name = "Arc%02d" % layer
		arc.mesh = _bake_links(link_mesh, seams, a, b)
		arc.material_override = material
		arc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_coil_root.add_child(arc)
		_coil_loops.append(arc)

	_coils = -1
	_place_coils(Vector3.ZERO)


# Where layer `layer`'s own links start in the seam list. Clamped, so a shake-up of
# `coil_max` cannot index off the end of a path that was built for a different count.
func _arc_cut(layer: int, seams: int) -> int:
	if _arc_cuts.is_empty():
		return clampi(layer * seams / maxi(1, coil_max), 0, seams)
	var i := clampi(layer, 0, _arc_cuts.size() - 1)
	return clampi(_arc_cuts[i], 0, seams)


# THE CENTRE-LINE OF THE STOW, in the stow's own space.
#
# Lead-in from the chain eye → `coil_max` OPEN ARCS, NEAREST THE FIST FIRST → one loose
# tail. Handed back as seams spaced EXACTLY `link_spacing` apart, because that one
# number is what `_link_geometry()` derives a link's size from: seams placed any other
# distance apart would draw the stow out of links a different size than the rope's,
# which is precisely the "two systems" §PART H forbids.
#
# THE ORDER IS THE MECHANISM, NOT A DETAIL. The rope is walked from the FIST outward, so
# layer 0 is the arc nearest the hand and the last layer is the FREE END — which is the
# end a real chain pays out from, and the end §STOW·V4·B takes away first (最外层弧被
# 迅速抽走). Built the other way round, the first thing to vanish would be the arc the
# rope is still attached BY.
#
# Also sets `_arc_cuts`, so a layer can be hidden WITHOUT the lead-in going with it: the
# run out of the fist belongs to layer 0, and layer 0 is the last thing to go.
func _stow_path() -> Array[Vector3]:
	var dense: Array[Vector3] = []
	var cuts: PackedInt32Array = PackedInt32Array()
	# 1 · LEAD-IN. From the chain eye out to the first arc, so the fist and the stow read
	#     as ONE rope rather than as two shapes that happen to be near each other.
	#
	#     §6, MEASURED, AND THE LESSON SURVIVED THE MOVE. The first seam used to be
	#     placed at the bundle anchor's own origin — 9cm inboard and 7cm above the
	#     handle's eye — so the nearest link hung in AIR about 12cm clear of the weapon
	#     and the review frame showed a ball of white wire beside a handle. The eye is
	#     mapped through the SAME transform `_place_coils` puts the stow under, so the
	#     rope's first link is ON the eye by construction rather than by tuning, and it
	#     stays there now that the anchor has moved 75cm.
	var eye := _stow_eye()
	var entry := _stow_point(0.0)
	# THE RUN ARRIVES ALONG THE WINDING, WHICH IS NOT DECORATION — a straight run into a
	# curving arc is a KINK, and a kink is a fold. `stow_interpenetration()` measured one:
	# two links three apart on the rope, a third of a metre of chain between them,
	# overlapping in the corner where the run met the first arc. Nothing about a rope makes
	# that turn, so the run is a quadratic Bézier whose control point sits BACK ALONG THE
	# WINDING'S OWN TANGENT — the curve then reaches the entry point travelling the way the
	# winding already travels, at the angle the arc continues in.
	#
	# The sag is `sin²` rather than `sin` for the same reason: `sin` has a nonzero slope at
	# both ends, so it would put the kink straight back, 8cm down the rope.
	#
	# A CUBIC, NOT A QUADRATIC, because the quadratic's single control point has to pull
	# the curve toward the side the winding's tangent points back to — which is UP AND
	# RIGHT, toward the crosshair — and that cost 0.15 NDC of the safe-zone margin
	# (measured: +0.1953 → +0.0473). Two control points let the run leave the fist DOWNWARD
	# the way a hanging chain does and still arrive travelling the way the winding
	# travels. The margin is the reading; `stow_margin()`.
	var tan0 := (_stow_point(0.05) - entry).normalized()
	# A HERMITE WITH BOTH END TANGENTS PINNED, WHICH IS THE POINT: two free control points
	# can loop, and a run that loops crosses itself — measured, repeatedly, as a pair of
	# links six apart on the rope lying 4mm apart (gap −0.0269) with no layer involved at
	# all. Pinning the tangents instead means the run LEAVES the fist the way a hanging
	# chain does and ARRIVES travelling the way the winding travels; the only freedom left
	# is how far it commits to each, which cannot fold it.
	#
	# AND "THE WAY A HANGING CHAIN DOES" IS NOT THE SAME AS "STRAIGHT DOWN". It was `(0,
	# -1, 0)` in the STOW's own space, which is 18.1 deg off the HANDLE's shaft — so the
	# rope left the eye heading down the hilt and ran inside the collar. `_stow_leave` is
	# the same idea with the hilt's own clearance folded in, and it is one function because
	# the eye's ORIENTATION has to agree with it (`build_handle`).
	var dir0 := _stow_leave()
	var dir1 := (tan0 + _stow_normal() * ARC_LEAD_BACK).normalized()
	var chord := (entry - eye).length() * ARC_LEAD_SLACK
	var m0 := dir0 * chord
	var m1 := dir1 * chord
	for k in ARC_LEAD_STEPS + 1:
		var t := float(k) / float(ARC_LEAD_STEPS)
		var t2 := t * t
		var t3 := t2 * t
		var sag := sin(PI * t)
		var run := (
			eye * (2.0 * t3 - 3.0 * t2 + 1.0)
			+ m0 * (t3 - 2.0 * t2 + t)
			+ entry * (-2.0 * t3 + 3.0 * t2)
			+ m1 * (t3 - t2)
		)
		dense.append(run + Vector3(0.0, -ARC_LEAD_DROOP * sag * sag, 0.0))
	# The run IS layer 0's approach, so layer 0's cut is the start of the whole path.
	#
	# `coil_max` layers are `coil_max + 1` cuts, and the boundaries are the SAME POINTS
	# seen from either side: the cut taken at the start of layer 1 and a cut taken at the
	# end of layer 0 are one dense sample. That is worth saying out loud, because this
	# block has been "fixed" once for an off-by-one that was not there — the seam counts
	# (11 / 3 / 4 / 3 links) look wrong for four similar arcs, but layer 0 legitimately
	# carries the 0.74m lead-in as well as the innermost arc, and 11 − 7 = 4.
	cuts.append(0)
	# 2 · THE ARCS, walked as one continuous parameter so there is no seam where one layer
	#     meets the next.
	for layer in coil_max:
		if layer > 0:
			# the point that both ends the previous arc and starts this one
			cuts.append(dense.size() - 1)
		for i in range(1, ARC_STEPS + 1):
			dense.append(_stow_point(float(layer) + float(i) / float(ARC_STEPS)))
	# 3 · THE FREE END. It leaves the OUTERMOST ARC and hangs — the one part of the stow
	#     holding nothing, and the reason it reads as a length of rope that was stowed
	#     rather than as a manufactured shape.
	#
	#     IT BELONGS TO THE OUTERMOST LAYER, and an earlier version of this got that wrong
	#     by a cut: the layer boundary was taken at the end of the last arc, so the tail
	#     fell past the final cut and NO layer was ever baked for it — the only visible
	#     sign was that a 27-seam path produced 25 drawn links. The cut goes in AFTER the
	#     tail.
	# The heading STARTS as the arc's own last chord and is turned downward a little
	# further at every step, so the junction is C1 by construction — see `ARC_TAIL_DROOP`.
	var last := dense[dense.size() - 1]
	var last_dir := (last - dense[dense.size() - 2]).normalized()
	var tail_step := ARC_TAIL_LEN / float(ARC_TAIL_STEPS)
	var down := Vector3(0.0, -1.0, 0.0)
	for k in ARC_TAIL_STEPS:
		var w := float(k + 1) / float(ARC_TAIL_STEPS)
		last_dir = (last_dir + down * (ARC_TAIL_DROOP * w)).normalized()
		last += last_dir * tail_step
		dense.append(last)
	cuts.append(dense.size() - 1)
	return _stow_resample(dense, cuts)


# WHERE THE ROPE MEETS THE HANDLE, in the stow's own space. One place, two readers:
# `_stow_path` welds the lead-in to it and `stow_links_ndc` uses it to tell the weapon's
# JOINT with the fist from the surplus chain the safe-zone rule is about. Written out
# twice is how the two drifted 12cm apart the last time it happened.
func _stow_eye() -> Vector3:
	if _handle == null:
		return Vector3(0.0, -0.030, 0.0)
	return _stow_basis().inverse() * (_handle_eye() - STOW_ANCHOR)


# THE CHAIN EYE'S POSITION, in the handle's own space. One place, three readers:
# `build_handle` puts the steel eye here, `_stow_eye` welds the lead-in to the same point,
# and `_stow_leave` reads the offset to know which way the rope has to go. The outboard
# direction is DERIVED from `STOW_ANCHOR` rather than written down again — the eye is
# always on the side the surplus hangs on by construction, so no second constant can drift
# away from the first.
func _handle_eye() -> Vector3:
	var out := Vector3(STOW_ANCHOR.x, 0.0, STOW_ANCHOR.z).normalized()
	return Vector3(0.0, HANDLE_EYE_HEIGHT, 0.0) + out * HANDLE_EYE_OUT


# THE DIRECTION THE ROPE LEAVES THE EYE IN, and the two readers are the two things that
# must agree about it: `_stow_path` uses the STOW-space form as the lead-in's opening
# tangent, and `build_handle` uses the HANDLE-space form to turn the eye's hole to face it.
#
# It is the direction from the eye toward the stow's anchor, weighted `ARC_LEAD_CLEAR`
# against the stow's own down. Both halves earn their place: "toward the stow" is what
# carries the rope clear of the hilt — the old pure-down version ran inside the collar —
# and some "down" is what keeps the run a HANGING rope rather than the near-straight strut
# that the `ARC_LEAD_SLACK` block records as the thing that folds it.
func _stow_leave() -> Vector3:
	var toward := -_stow_eye().normalized()
	return (toward + Vector3(0.0, -1.0, 0.0) * ARC_LEAD_CLEAR).normalized()


func _handle_leave() -> Vector3:
	return (_stow_basis() * _stow_leave()).normalized()


# One point of the stow's centre-line, `j` layers in — and `j` is ONE parameter for the
# whole stow, not a layer index plus a fraction. Radius, angle, twist and the step along
# the normal are all smooth functions of it, so the four arcs are four consecutive
# segments of ONE winding and there is no place where the rope could tear.
func _stow_point(j: float) -> Vector3:
	var s := clampf(j, 0.0, float(coil_max))
	# RADIUS opens continuously as the winding goes round, so a layer is a stretch of a
	# spiral rather than a ring and the outermost layer is the widest by construction.
	var radius := ARC_R_INNERMOST * (1.0 + ARC_R_GROW * s)
	# Deterministic (no RNG), so the stow is the same stow every frame and a test can
	# still reason about it — while no two layers come out the same size.
	radius *= 1.0 + ARC_SIZE_JITTER * sin(s * 2.399 + 0.7)
	# `ARC_START` is −1.15 rad (−66°), and the reasons are framing and the RUN rather than
	# taste: from there the winding runs down and round the left, so no part of the fan is
	# ever above the anchor — which is the direction the crosshair is in (see `SAFE_HALF`) —
	# and the entry lands on the fan's LOWER-RIGHT, the side the fist is already on, so the
	# lead-in arrives at the near point of the winding instead of crossing it. The old 130°
	# put the entry on the far side and the run had to cross the whole coil to reach it.
	var theta := ARC_START + ARC_SWEEP * s
	# THE PLANE. `ARC_LEAN` is SHARED BY EVERY LAYER — it is the fan's attitude, not a
	# per-layer tweak — and only `ARC_SPIN` turns with the winding. That is the whole
	# mechanism: because the layers share one plane they share one NORMAL, and a step
	# along that normal is a step no layer can opt out of. The previous version rolled
	# each layer's plane further than the last (`ARC_TILT`), which pointed the four
	# normals four different ways and left no direction in which a step could separate
	# them — see the `ARC_DEPTH` block for why that is the difference between a coil and
	# a knot.
	var plane := _stow_plane(ARC_SPIN * s)
	# THE STEP IS INSIDE THE PLANE TRANSFORM, so it runs along the fan's OWN normal and
	# not along the stow space's Z. Applied outside, it would drift off the normal as
	# `ARC_LEAN` grows, and the clearance the arithmetic above bought would leak away.
	var local := Vector3(
		cos(theta) * radius * ARC_WIDE + ARC_STACK * s,
		sin(theta) * radius * ARC_SQUASH - ARC_DROP * s,
		ARC_DEPTH * s
	)
	return plane * local


# THE STOW'S OWN ORIENTATION, in the handle's own space.
#
# One place, two readers: `_place_coils` turns the root by this and `_stow_path` maps the
# handle's eye back through its inverse to weld the lead-in on. Two expressions of one
# idea is how the two drifted 12cm apart the last time it happened.
func _stow_basis() -> Basis:
	return (
		Basis(Vector3.UP, STOW_YAW)
		* Basis(Vector3.RIGHT, STOW_PITCH)
		* Basis(Vector3.FORWARD, STOW_ROLL)
	)


# THE FAN'S OWN PLANE — the one orientation EVERY layer shares, which is the whole
# mechanism of `ARC_DEPTH`. Two readers: `_stow_point` lays the arcs in it, and
# `_stow_normal` takes its normal for `_link_basis`.
func _stow_plane(spin: float = 0.0) -> Basis:
	return (
		Basis(Vector3(1.0, 0.0, 0.0), ARC_LEAN)
		* Basis(Vector3(0.0, 0.0, 1.0), spin)
	)


# THE DIRECTION THE LAYERS ARE STACKED ALONG, in the stow's own space — the fan plane's
# normal, and therefore ALSO the axis every link's ring plane has to face. One function
# because those two facts must agree: if the links face one way and the layers step
# another, the step stops separating them, and the failure is invisible until it is
# rendered. Spin-invariant by construction (a spin about the normal cannot move the
# normal), so a single call answers for all four layers.
func _stow_normal() -> Vector3:
	return _stow_plane() * Vector3(0.0, 0.0, 1.0)


# Re-space a dense centre-line at exactly `link_spacing`, AND report where each layer of
# the stow begins in seam indices.
#
# Two jobs in one pass on purpose. The cuts are ARC-LENGTH positions — a layer is
# `radius · ARC_SWEEP` of arc and the layers are not the same size, so spacing them by
# layer index would crowd the small layers' links together and string the large layers'
# links apart — and computing them in a second pass would be a second chance to disagree
# about where a layer starts.
func _stow_resample(dense: Array[Vector3], dense_cuts: PackedInt32Array) -> Array[Vector3]:
	var seams: Array[Vector3] = []
	_arc_cuts = PackedInt32Array()
	if dense.is_empty():
		return seams
	seams.append(dense[0])
	_arc_cuts.append(0)
	var travelled := 0.0
	var next_at := link_spacing
	var next_cut := 1
	for i in range(1, dense.size()):
		var seg := dense[i] - dense[i - 1]
		var length := seg.length()
		if length < 0.000001:
			continue
		var start := travelled
		travelled += length
		while next_at <= travelled:
			seams.append(dense[i - 1] + seg / length * (next_at - start))
			next_at += link_spacing
		while next_cut < dense_cuts.size() and dense_cuts[next_cut] <= i:
			_arc_cuts.append(seams.size() - 1)
			next_cut += 1
	# A path so short that a cut never had a seam to land on still has to report
	# `coil_max + 1` cuts, or `_arc_cut()` would silently collapse a layer to nothing.
	while _arc_cuts.size() < coil_max + 1:
		_arc_cuts.append(seams.size() - 1)
	return seams


# Bake the links of seams `[a, b)` into one mesh, so a turn stays a single node whose
# visibility can be switched — which is what `coils()` / `coils_for()` drive, and what
# `chain_physicality` counts. Same geometry, same basis, same alternating roll as the
# drawn rope: `_link_basis(tangent, odd)` is shared, not copied.
func _bake_links(link_mesh: Mesh, seams: Array[Vector3], a: int, b: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(maxi(0, a), mini(b, seams.size() - 1)):
		var tangent := seams[i + 1] - seams[i]
		if tangent.length_squared() < 0.000001:
			continue
		st.append_from(
			link_mesh,
			0,
			Transform3D(
				_link_basis(tangent, i % 2 == 1, _stow_normal()),
				(seams[i] + seams[i + 1]) * 0.5
			)
		)
	# The normals ARE carried over by `append_from` — but they are the torus's own, and
	# a bundle of ninety small tori lit by one directional light averages out dark. The
	# review frame measured it: LINK_TINT at 0.66 albedo came back as charcoal beside a
	# bone-white trident. Rebuilding them smooths the shading across each link so the
	# bundle's overall brightness tracks its albedo, which is the thing that has to be
	# true of a fistful of pale steel. (`deindex()` first: `generate_normals()` needs
	# unwelded vertices, and it also allows the seam between two links to be ignored.)
	st.deindex()
	st.generate_normals()
	return st.commit()


# ==========================================================================================
# §MOTION — CONTROLLED INERTIA, AND THE ONLY PLACE THE STOW IS ALLOWED TO MOVE.
# ==========================================================================================
#
# The frozen pose is `_stow_rest_transform()`. Everything else in this block produces a
# PERTURBATION around it and nothing else, which is what keeps the verified geometry
# verified: at rest the offset is exactly zero and the drawing is bit-for-bit the pose
# the stow revision was signed off at.

## Where the stow would sit if it were welded to the hand. ONE expression of "where the
## stow belongs" — the lag, the clamp and the diag all measure against this, so a change
## to the frozen anchor cannot leave the motion system tracking a second, stale copy.
func _stow_rest_transform(hand: Vector3) -> Transform3D:
	var basis := _stow_basis()
	if _handle != null:
		var hx := _handle.global_transform
		return Transform3D(hx.basis * basis, hx * STOW_ANCHOR)
	return Transform3D(basis, hand)


## The one spring law, shared by the translation and the two rotation axes so they cannot
## drift into three slightly different filters: `ẍ = −2ζω·ẋ − ω²·x` with `x` the error and
## ω = 1/τ. Second order and critically-ish damped — NO RigidBody, no solver, nothing that
## can be integrated to an explosion by a hitched frame.
##
## `zeta` is a parameter rather than the constant because §12 needs a SECOND character from
## the same law: while the chain is held the surplus may overshoot once (that overshoot is
## what makes a stop read as inertia), and while it is loaded it may not — a rope under
## tension does not swing past its own rest pose. Different damping, same equation.
func _lag_accel(x: Vector3, v: Vector3, tau: float, zeta := MOTION_LAG_ZETA) -> Vector3:
	var w := 1.0 / maxf(0.0001, tau)
	return -2.0 * zeta * w * v - w * w * x


func _clamp_len(v: Vector3, limit: float) -> Vector3:
	var l := v.length()
	return v * (limit / l) if l > limit and l > 0.000001 else v


func _motion_camera() -> Camera3D:
	if _motion_camera_cache == null and is_inside_tree():
		_motion_camera_cache = get_viewport().get_camera_3d()
	return _motion_camera_cache


## §5 — THE CLAMP. The spring's demand is compressed toward the rest pose until the
## DRAWING it would produce satisfies the two safe-zone readings, and the largest scale
## that survives is returned.
##
## It is a projection test because the rule is a projection rule: `stow_breach` is in NDC
## against a square band and `stow_frame_reach` is in NDC against the frame edge, so the
## only honest way to ask "would this motion break the crosshair rule" is to project the
## motion. Metres cannot answer it — the same 3cm toward the camera and 3cm across it are
## different pictures, and the band has only ~0.031 of NDC to give.
##
## `0.0` is always legal on purpose. It is the frozen pose, which is verified; if the
## frozen pose itself failed the reading then the lag is not what is broken, and
## compressing the lag further would only hide a real defect behind a safe-looking frame.
func _lag_safe_scale(rest: Transform3D, offset: Vector3, basis: Basis) -> float:
	var cam := _motion_camera()
	if cam == null:
		return 1.0
	var frame := _view_frame()
	if frame.x < 1.0 or frame.y < 1.0:
		return 1.0
	# THE FULL DEMAND IS TESTED EXPLICITLY, and this is a correctness fix rather than an
	# optimisation. A bisection whose upper bound is never evaluated can never RETURN it:
	# with `hi` fixed at 1.0 and six halvings, a demand that was legal in its entirety
	# still came back as 0.984375 — so `motion_lag_scale()` reported "the clamp compressed
	# this" on every frame of a perfectly legal walk, and a test written against that
	# number could not tell a clamp that never fires from one that always does. It did not:
	# disabling the clamp entirely left `chain_v4_slice` green.
	if _stow_ndc_legal(Transform3D(basis, rest.origin + offset), cam, frame):
		return 1.0
	var lo := 0.0
	var hi := 1.0
	# Six bisections put the answer inside 1/64 of the demand, which is finer than the
	# lag's own metre resolution and cheap enough to run every frame: the read is one
	# pass over the drawn seams, and the drawn count is about sixty.
	for _i in 6:
		var mid := 0.5 * (lo + hi)
		var cand := Transform3D(rest.basis.slerp(basis, mid), rest.origin + offset * mid)
		if _stow_ndc_legal(cand, cam, frame):
			lo = mid
		else:
			hi = mid
	return lo


## Both safe-zone readings in ONE pass over the drawn seams, because the clamp runs six
## of these per frame and walking the seam list twice for two numbers would be two thirds
## of the cost of the whole motion system.
func _stow_ndc_legal(xf: Transform3D, camera: Camera3D, frame: Vector2) -> bool:
	for p in _stow_ndc_for(xf, camera, frame):
		var r := maxf(absf(p.x), absf(p.y))
		if r >= STOW_REACH_LIMIT:
			return false
		if r < SAFE_HALF:
			return false
	return true


## Where the player is actually looking, in pixels.
##
## THE FRAME IS AN ARGUMENT, NOT A LOOKUP, and this cost a debug cycle to learn. The
## safe-zone rule is defined with an explicit frame at every other call site —
## `stow_breach(camera, frame)`, `stow_frame_reach(camera, frame)`, and the diag passes
## 1280×720 — because the ASPECT is part of the projection and a frame that disagrees with
## the one the rule was written in is a different rule. A HEADLESS RUN'S VIEWPORT IS A
## 64×64 PLACEHOLDER, so an aspect taken from it is 1.0 instead of 1.78, every point
## projects 1.78× too far from centre, the tightest seam lands at NDC −1.508, and the
## clamp compressed the entire motion to ZERO while the reported reading said 0.850.
##
## `motion_frame` is how a caller pins it. `Vector2.ZERO` means "ask the live viewport",
## which is what a real window wants and what the game does.
func _view_frame() -> Vector2:
	if motion_frame.x >= 1.0 and motion_frame.y >= 1.0:
		return motion_frame
	if not is_inside_tree():
		return Vector2.ZERO
	var vp := get_viewport()
	return Vector2(vp.get_visible_rect().size) if vp != null else Vector2.ZERO


## The whole motion system, one call. Returns nothing and writes `_motion_lag`, because
## the caller is `_place_coils` and the transform it wants is built there.
func _update_stow_motion(hand: Vector3, delta: float) -> void:
	var dt := clampf(delta, 0.0001, MOTION_MAX_STEP)
	var target := _stow_rest_transform(hand)
	_idle_time += dt

	# ---- what the hand is doing, in world linear and angular velocity --------
	var lin := Vector3.ZERO
	var ang := Vector3.ZERO
	if _motion_target_ready:
		lin = (target.origin - _motion_prev_origin) / dt
		var rel := _motion_prev_target.basis.inverse() * target.basis
		var q := rel.get_rotation_quaternion()
		var axis := q.get_axis()
		var angle := q.get_angle()
		if angle > 0.00001 and is_finite(axis.x) and is_finite(axis.y) and is_finite(axis.z):
			# THE AXIS IS CARRIED INTO WORLD SPACE, which is not a formality: `rel` is the
			# rotation of the hand expressed in the PREVIOUS basis' own frame, so `axis` is
			# a LOCAL axis. Decomposing it against the world up and the view's right mixes
			# two frames, and the result was that §4's pitch term read 0.17 deg where its
			# own share asks for 3.4 — an inert axis that happened to look compliant.
			ang = (_motion_prev_target.basis * axis).normalized() * (angle / dt)
	_motion_prev_target = target
	_motion_prev_origin = target.origin
	_motion_target_ready = true
	_hand_vel = _hand_vel.lerp(lin, 1.0 - exp(-dt / MOTION_VEL_TAU))

	# ---- §12 · A LOADED CHAIN DOES NOT DRIFT --------------------------------
	#
	# THE FLOATING ARC IS A HELD-WEAPON PRESENTATION AND NOTHING ELSE. The moment a technique
	# leaves the hand the surplus stops floating and starts being PAID OUT (§10 → §11), and
	# the two motions fight: a bundle that keeps obeying a spring while the rope is drawn out
	# of it reads as the chain resisting the throw. §12 says the same from the other end —
	# Hit：以后：不要：继续：Idle Lag — because once the head has bitten a wall the four layers
	# have to be handed over to the force relationship, not left breathing on a hip.
	#
	# So the drift is switched off outright (it is an IDLE channel) and the spring is asked
	# for its offset in the LOAD's own time constant, critically damped — no overshoot past a
	# rest pose that a taut rope could not swing back from.
	var loaded := rig != Rig.HELD
	var lag_tau := MOTION_LOAD_TAU if loaded else MOTION_LAG_TAU
	var lag_zeta := 1.0 if loaded else MOTION_LAG_ZETA

	# ---- §3/§8 · how far back the surplus is dragged ------------------------
	var speed := _hand_vel.length()
	var sprint := clampf(speed / MOTION_SPRINT_SPEED, 0.0, 1.0)
	var want_len := minf(
		MOTION_LAG_MAX,
		speed * MOTION_LAG_PER_SPEED * (1.0 + MOTION_SPRINT_SHARE * sprint)
	)
	var drag := Vector3.ZERO
	if not loaded and speed > 0.001:
		drag = -_hand_vel.normalized() * want_len
	_motion_vel += _lag_accel(_motion_off - drag, _motion_vel, lag_tau, lag_zeta) * dt
	_motion_off += _motion_vel * dt
	_motion_off = _clamp_len(_motion_off, MOTION_LAG_MAX)

	# ---- §4 · the same for the turn, with pitch given less say --------------
	var up := Vector3.UP
	# THE PITCH AXIS IS THE VIEW'S RIGHT. A look pitches about the camera's own x, and
	# that is the only frame in which "up and down" means anything: `target.basis.x` is the
	# STOW's local right — a tilted frame sitting on a hip — so a look-up decomposed
	# against it returns the cosine of the stow's own lean instead of the pitch rate.
	var right := Vector3.RIGHT
	var motion_cam := _motion_camera()
	if motion_cam != null:
		right = motion_cam.global_transform.basis.x
	elif _handle != null:
		right = _handle.global_transform.basis.x
	right = right.normalized() if right.length_squared() > 0.25 else Vector3.RIGHT
	var want_ang := Vector3.ZERO
	if not loaded:
		want_ang = _clamp_len(
			-up * ang.dot(up) * MOTION_TURN_TAU
				- right * ang.dot(right) * MOTION_TURN_TAU * MOTION_TURN_PITCH_SHARE,
			MOTION_TURN_MAX
		)
	_motion_ang_vel += _lag_accel(_motion_ang - want_ang, _motion_ang_vel, lag_tau, lag_zeta) * dt
	_motion_ang += _motion_ang_vel * dt
	_motion_ang = _clamp_len(_motion_ang, MOTION_TURN_MAX)

	# ---- §7 · alive, not animated ------------------------------------------
	#
	# Added DIRECTLY and not through the spring: it is already smooth, and routing it
	# through the filter would leave a permanent ~4mm on the per-layer trail at rest —
	# i.e. a motion term quietly editing the frozen pose it is not supposed to touch.
	# Two incommensurate frequencies per axis, so no single period is ever felt.
	var t := _idle_time * TAU
	var idle := Vector3.ZERO
	var idle_roll := 0.0
	if not loaded:
		idle = (
			target.basis.y
				* (sin(t * MOTION_IDLE_HZ_A) * 0.70 + sin(t * MOTION_IDLE_HZ_B) * 0.30)
				* MOTION_IDLE_DRIFT
			+ target.basis.x
				* (sin(t * MOTION_IDLE_HZ_B) * 0.60 + sin(t * MOTION_IDLE_HZ_A * 1.3) * 0.40)
				* MOTION_IDLE_SWAY
		)
		idle_roll = sin(t * MOTION_IDLE_HZ_B + 0.9) * MOTION_IDLE_ROLL

	var basis := Basis(Vector3.UP, idle_roll)
	if _motion_ang.length() > 0.000001:
		basis = basis * Basis.from_euler(_motion_ang)
	basis = basis * target.basis

	var offset := _clamp_len(_motion_off + idle, MOTION_LAG_MAX)
	var scale := _lag_safe_scale(target, offset, basis)
	_motion_lag_scale = scale
	_motion_lag = offset * scale
	# Recorded AFTER the clamp so the two readings describe the same frame: `motion_idle()`
	# is the drift the drawing actually received, not the drift that was asked for.
	_motion_idle = idle * scale
	_motion_rest = target
	# The rotation is compressed by the same scale as the translation: they are one
	# motion, and a turn that survived the clamp while its trail did not would read as
	# the fan rotating about a point that is no longer following it.
	if scale < 1.0:
		basis = Basis(Vector3.UP, idle_roll * scale)
		if _motion_ang.length() > 0.000001:
			basis = basis * Basis.from_euler(_motion_ang * scale)
		basis = basis * target.basis
	# §6 · how loaded the major motion is, which is what the per-layer trail is scaled
	# by. Read from the SPRING's own offset and not from `_motion_lag`, so the drift
	# cannot put a permanent shear on the layers.
	_motion_layer_shift = MOTION_LAYER_SPREAD * clampf(
		_motion_off.length() / MOTION_LAG_MAX, 0.0, 1.0
	)

	if _coil_root == null:
		return
	_coil_root.global_transform = Transform3D(basis, target.origin + _motion_lag)


## §6 — ONE ROOT, FOUR RESPONSE SPEEDS. The root has already carried the whole motion;
## this only leans the outer layers a little further down the drag, in the root's own
## local space, so the fan reads as being pulled from the hand end.
func _apply_layer_response(basis: Basis) -> void:
	if _coil_loops.is_empty():
		return
	var local := Vector3.ZERO
	if _hand_vel.length() > 0.05:
		local = (basis.inverse() * -_hand_vel).normalized()
	for i in _coil_loops.size():
		var resp := 1.0
		if i < MOTION_LAYER_RESPONSE.size():
			resp = float(MOTION_LAYER_RESPONSE[i])
		elif not MOTION_LAYER_RESPONSE.is_empty():
			resp = float(MOTION_LAYER_RESPONSE[MOTION_LAYER_RESPONSE.size() - 1])
		_coil_loops[i].position = local * ((1.0 - resp) * _motion_layer_shift)


## §10/§11 — THE RELEASE LADDER. See `BUNDLE_SHED_STEPS` for the readings this replaces.
##
## The wanted end is the rig's job: `HELD` keeps the stow, any other rig gives it up. The
## WIND-UP arms it early — `set_preload` is already the signal the director sends while a
## technique is being committed, so the first arc leaves during the wind-up rather than
## waiting for the swing to begin. That is §10's ordering exactly (4→3 in the wind-up,
## 3→2 in the swing), and it needs no new channel between the director and this file.
##
## One step per dwell and NO MORE, with the remainder carried: a hitched frame cannot buy
## two steps at once, so the total release and repack times stay the sums of the dwells
## and the timings the existing tests measure cannot drift.
func _update_release(delta: float) -> void:
	# STATELESS ON PURPOSE, and the first version was not. A latched `armed` flag has to be
	# cleared by something, and every clear condition that mentions the ladder's own
	# position deadlocks: "clear when the rig is HELD and the ladder is home" can never fire
	# once the ladder has left home, so the stow stayed at 2 of 4 arcs forever and
	# `chain_v4_slice` reported a weapon that had quietly lost half its surplus. Reading the
	# wind-up's own number has no latch to get stuck in: `_preload` is nonzero exactly while
	# a technique is committing, and exactly zero the frame it stops.
	var want := BUNDLE_SHED_STEPS if (rig != Rig.HELD or _preload > 0.05) else 0
	# One step per dwell and NO MORE, with the remainder carried: a hitched frame cannot buy
	# two steps at once, so the total release and repack times stay the sums of the dwells
	# and the timings the existing tests measure cannot drift.
	if _release_step == want:
		_release_hold = 0.0
		_bundle_fade = float(_release_step) / float(maxi(1, BUNDLE_SHED_STEPS))
		return
	var per := (
		BUNDLE_SHED_TIME if want > _release_step else BUNDLE_GATHER_TIME
	) / float(maxi(1, BUNDLE_SHED_STEPS))
	_release_hold += delta
	if _release_hold >= per:
		_release_hold -= per
		_release_step = clampi(_release_step + signi(want - _release_step), 0, BUNDLE_SHED_STEPS)
	_bundle_fade = float(_release_step) / float(maxi(1, BUNDLE_SHED_STEPS))


# The stow's rest pose: the fan at the left hip, turned to meet the eye at an angle.
# See the `STOW_ANCHOR` block for the measured target and why the old anchor — which was
# 9cm INBOARD of the hand and put the whole bundle at NDC (0.23, −0.46) — is the reason
# that block is a target rather than a nudge.
func _place_coils(hand: Vector3, delta := 0.0) -> void:
	if _coil_root == null:
		return
	if delta <= 0.0:
		# BUILD TIME, or a caller with no clock: place the frozen pose and leave the
		# motion system un-armed, so the first frame of a take cannot inherit a lag
		# integrated from a stale transform.
		if _handle == null:
			_coil_root.global_transform = Transform3D(_stow_basis(), hand)
		elif _coil_root.get_parent() == _handle:
			_coil_root.transform = Transform3D(_stow_basis(), STOW_ANCHOR)
		_motion_ready = false
		_motion_target_ready = false
		_motion_off = Vector3.ZERO
		_motion_vel = Vector3.ZERO
		_motion_ang = Vector3.ZERO
		_motion_ang_vel = Vector3.ZERO
		_hand_vel = Vector3.ZERO
		_motion_lag = Vector3.ZERO
		_motion_lag_scale = 1.0
		_motion_layer_shift = 0.0
		_motion_idle = Vector3.ZERO
		_release_step = 0
		_release_hold = 0.0
		_bundle_fade = 0.0
		_idle_time = 0.0
		_apply_layer_response(_stow_basis())
	else:
		_update_stow_motion(hand, delta)
		_apply_layer_response(_coil_root.global_transform.basis)
	var shown := _coils if _coils >= 0 else coil_max
	# §11 — FULL STOW → REDUCED STOW → ATTACK CHAIN, and since §10/§11 the shed walks a
	# LADDER of `BUNDLE_SHED_STEPS` arcs. One arc leaves at a time and each step is held
	# for a dwell, so the release and the repack are both something the player watches
	# happen. See `BUNDLE_SHED_STEPS` for why a continuous fade was not enough.
	shown = maxi(1, shown - _release_step)
	var hand_visible := _handle == null or _handle.visible
	_bundle_shown = shown if hand_visible else 0
	# INNERMOST FIRST, OUTERMOST LAST — `_stow_path` walks the rope from the fist outward,
	# so index 0 is the arc nearest the hand and the last index carries the free end.
	# Hiding from the top therefore sheds the way a rope actually leaves a stow, and the
	# one thing a shed layer can never take with it is the lead-in.
	for i in _coil_loops.size():
		_coil_loops[i].visible = i < shown and hand_visible


# §STOW SAFE ZONE — 余链永远不能出现在准星周围, AS A NUMBER.
#
# The user's rule is a framing rule about the CROSSHAIR, and the crosshair is the centre
# of the projection — so the reading has to be in NDC and taken from the camera, not in
# metres and not from the stow's own transform. This projects the CENTRE-LINE of every
# DRAWN stow link, which is the same line `_bake_links` laid the links on, so a stow that
# moved could not pass by being measured somewhere else.
#
# Returns the deepest penetration of any drawn link into the central band, in NDC units.
# 0.0 means the whole stow is clear of it, and that is exactly what `chain_v4_slice`
# requires. (The link's own radius, about 0.07 NDC at half a metre, is NOT folded in
# here; `stow_margin()` reports the clearance, and the design leaves several times that.)
func stow_breach(camera: Camera3D, frame: Vector2, half: float = SAFE_HALF) -> float:
	var worst := 0.0
	for p in stow_links_ndc(camera, frame):
		worst = maxf(worst, half - maxf(absf(p.x), absf(p.y)))
	return maxf(0.0, worst)


# HOW MUCH ROOM the stow has from the central band: the smallest `max(|x|, |y|)` over its
# drawn links, minus `half`. Negative means something is inside. Reported rather than
# derived, so a review can say HOW MUCH clearance there is and not merely "it passed".
func stow_margin(camera: Camera3D, frame: Vector2, half: float = SAFE_HALF) -> float:
	var pts := stow_links_ndc(camera, frame)
	if pts.is_empty():
		return 0.0
	var closest := 999.0
	for p in pts:
		closest = minf(closest, maxf(absf(p.x), absf(p.y)))
	return closest - half


# The NDC of every DRAWN stow link, in the order they are laid. Anything at or behind the
# lens is skipped: a weapon part can sit outside the frustum, and a point behind the eye
# has no projection rather than a projection at the centre.
func stow_links_ndc(camera: Camera3D, frame: Vector2) -> PackedVector2Array:
	if _coil_root == null:
		return PackedVector2Array()
	return _stow_ndc_for(_coil_root.global_transform, camera, frame)


## The same projection against a CANDIDATE transform, which is what makes §5's clamp
## possible: the motion system has to ask "would the pose I am about to write break the
## safe band" BEFORE writing it, and a reading that could only measure what was already in
## the scene would have to move the chain first and check afterwards.
##
## There is one expression of the drawn set — visibility and the joint-with-the-hand
## exclusion both live here — so a clamp that compressed the wrong set of links could not
## pass while the diag passed too.
func _stow_ndc_for(xf: Transform3D, camera: Camera3D, frame: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	if camera == null or _stow_seams.is_empty():
		return out
	var to_eye := camera.global_transform.affine_inverse()
	var half := tan(deg_to_rad(camera.fov * 0.5))
	var aspect := frame.x / maxf(1.0, frame.y)
	var joint := _stow_eye()
	for layer in _coil_loops.size():
		if not _coil_loops[layer].visible:
			continue
		var a := _arc_cut(layer, _stow_seams.size())
		var b := _arc_cut(layer + 1, _stow_seams.size())
		for i in range(a, mini(b, _stow_seams.size())):
			# the weapon's joint with the hand, not surplus chain — see `STOW_JOINT`
			if _stow_seams[i].distance_to(joint) < STOW_JOINT:
				continue
			var local := to_eye * (xf * _stow_seams[i])
			if local.z >= -0.02:
				continue
			out.append(Vector2(
				local.x / (-local.z * half * aspect),
				local.y / (-local.z * half)
			))
	return out


# §STOW FRAME — THE OTHER HALF OF THE SAFE-ZONE RULE, AND IT WAS MISSING.
#
# `stow_breach()` answers "did the surplus enter the MIDDLE of the picture". Nothing
# answered "did it leave the picture", and those are opposite failures with the same cause:
# the stow is anchored at the hip and the safe band only pushes it AWAY from the centre, so
# a stow that is too big does not breach — it simply falls off the left edge. MEASURED with
# circular arcs: `breach` read a clean 0.0000 while layer 3 sat at NDC x −1.382 and y
# −1.147, one to four tenths of the frame OUTSIDE the picture. The reading that catches it
# is the FARTHEST any drawn link reaches, and it must be under 1.0.
#
# Reported as the largest |max(nx, ny)| over the same drawn links `stow_links_ndc` hands
# back, so the joint-with-the-hand exclusion still applies and this is about SURPLUS chain.
func stow_frame_reach(camera: Camera3D, frame: Vector2) -> float:
	var worst := 0.0
	for p in stow_links_ndc(camera, frame):
		worst = maxf(worst, maxf(absf(p.x), absf(p.y)))
	return worst


# ==========================================================================================
# §JOINT — THE FIST END OF THE SAME ROPE, WHICH HAD NO READING AT ALL.
#
# Every section above judges the stow at the HIP. Nothing judged the HANDLE, and that is
# exactly how the chain came to run straight down the hilt for two revisions: the eye sat
# on the shaft's axis, the departure was `(0, -1, 0)` in the STOW's space, and the stow's
# down is 18.1 deg off the handle's own axis — so the rope entered the metal collar's top
# face and left through its side. MEASURED when the reading was finally written:
# `eye ring vs the hilt -0.0450 m`, `rope vs the hilt -0.0177 m at seam 1`, and the ring
# standing 86.3 deg across the rope it was supposed to be threaded by.
#
# THREE readings, because there are three separate ways to be inside the hilt and the fix
# had to satisfy all of them: the rope's PATH clears the metal, the EYE clears the metal,
# and the eye's HOLE faces the rope. The user's rule is 不要穿模刀手柄, and a rule with no
# number is a rule that comes back.
# ==========================================================================================


# THE HANDLE'S SILHOUETTE RADIUS AT A HEIGHT, read off the MESHES THAT ARE ACTUALLY DRAWN
# rather than off a second copy of the part table. `build_handle` makes six bodies of
# revolution on the handle's own axis — grip, two wrap ridges, hand stop, collar, end cap —
# plus a pommel sphere, and a reading that re-listed their dimensions would be a seventh
# thing to keep in step with them. Reading the meshes means changing the handle changes the
# reading for free, which is the only way a clearance test stays honest.
#
# The EYE is skipped on purpose: it is part of the rope's joint, not part of the hilt the
# rope has to clear, and it is a torus, which is the one shape here that is not a body of
# revolution about the handle's axis.
#
# Two approximations, both conservative: a tapered cylinder is taken at its WIDER end, and
# the pommel's 1cm rearward offset is ignored (a 2cm ball an inch below the fist; a rope
# that reached it would already have failed the grip by three centimetres).
func handle_radius_at(y: float) -> float:
	var r := 0.0
	if _handle == null:
		return r
	for child in _handle.get_children():
		var mi := child as MeshInstance3D
		if mi == null:
			continue
		var cy := mi.position.y
		var mesh := mi.mesh
		if mesh is CylinderMesh:
			var cyl := mesh as CylinderMesh
			if absf(y - cy) <= cyl.height * 0.5:
				r = maxf(r, maxf(cyl.top_radius, cyl.bottom_radius))
		elif mesh is SphereMesh:
			var sp := mesh as SphereMesh
			var hh := maxf(0.0001, sp.height * 0.5)
			var k := absf(y - cy) / hh
			if k <= 1.0:
				r = maxf(r, sp.radius * sqrt(1.0 - k * k))
	return r


# HOW CLOSE THE ROPE COMES TO THE HILT, in metres, negative when it is inside it. The
# reading `chain_v4_slice`'s §JOINT group fails on.
#
# SUB-SAMPLED BETWEEN SEAMS, and it has to be: the seams are one `link_spacing` apart, and
# the worst point of a departure is where the rope draws level with the collar's top rim —
# which falls BETWEEN two seams. Sampled on the seams alone this reading reported the eye's
# own clearance as the minimum and missed the actual minimum by 4cm of travel.
func stow_hilt_clearance() -> float:
	if _handle == null or _coil_root == null or _stow_seams.is_empty():
		return 0.0
	var to_handle := _handle.global_transform.affine_inverse() * _coil_root.global_transform
	var worst := 999.0
	for i in _stow_seams.size():
		var a: Vector3 = _stow_seams[i]
		var b: Vector3 = _stow_seams[mini(i + 1, _stow_seams.size() - 1)]
		for s in 9:
			var p: Vector3 = to_handle * a.lerp(b, float(s) / 8.0)
			if absf(p.y) > 0.24:
				continue
			worst = minf(worst, sqrt(p.x * p.x + p.z * p.z) - handle_radius_at(p.y))
	return 0.0 if worst > 998.0 else worst


# THE RING'S OWN TUBE versus the hilt. A torus's centreline is `(inner + outer) / 2` from
# its axis and its tube is half the difference — the same two facts `build_handle` sizes the
# mesh with — and the clearance below the tube's own radius is the ring's surface, which is
# the thing that would be seen clipping.
func stow_eye_clearance() -> float:
	var ring := _chain_eye()
	if ring == null:
		return 0.0
	var tm := ring.mesh as TorusMesh
	var major := (tm.inner_radius + tm.outer_radius) * 0.5
	var tube := (tm.outer_radius - tm.inner_radius) * 0.5
	var worst := 999.0
	for k in 24:
		var a := TAU * float(k) / 24.0
		var pt: Vector3 = ring.position + ring.basis * Vector3(cos(a) * major, 0.0, sin(a) * major)
		worst = minf(worst, sqrt(pt.x * pt.x + pt.z * pt.z) - handle_radius_at(pt.y) - tube)
	return worst


# DOES THE ROPE GO THROUGH THE EYE, in degrees. A torus is an EYELET: the rope passes through
# its HOLE, so the ring's axis has to BE the direction the rope leaves in. Near 0 the rope
# threads it; near 90 the rope is lying across the ring's rim, which is a ring jammed into
# the thing it hangs from however clear of the metal its outline happens to be.
func stow_eye_threading() -> float:
	var ring := _chain_eye()
	if ring == null:
		return 0.0
	return rad_to_deg(acos(clampf(absf(ring.basis.y.normalized().dot(_handle_leave())), 0.0, 1.0)))


func _chain_eye() -> MeshInstance3D:
	if _handle == null:
		return null
	for child in _handle.get_children():
		var mi := child as MeshInstance3D
		if mi != null and mi.mesh is TorusMesh:
			return mi
	return null


# §STOW — "NOT A KNOT", AS A NUMBER RATHER THAN AN OPINION.
#
# Every other reading of this stow is a projection, and a projection cannot tell a coil
# from a tangle: four arcs 1.2cm apart look like four arcs right up until they are drawn,
# because on screen they ARE four arcs — each one threading through the middle of the one
# behind it. What the eye calls "a knot" is INTERPENETRATION, and interpenetration is a
# distance between two solid objects, so it can be measured and it can be made to fail.
#
# The test is an OBB separating-axis test between every pair of links that are NOT
# NEIGHBOURS ON THE ROPE. Neighbours are skipped because two consecutive links of one
# chain interlock by design (§5's alternation) — a test that counted those could never
# pass, and a test that can never pass is not a test. Everything else must be clear:
# links a hand's breadth apart along the rope, in different layers or the same one.
#
# Boxes rather than tori, and half-edges taken from the SAME `link_spacing` and the SAME
# `_link_basis` the links themselves are built from — so a stow that changed the link size
# or its orientation to hide the problem would change the boxes too.
#
# Returns the number of such pairs that overlap. Zero is the requirement; the number is
# reported rather than a bool, so a review can see how close to zero it is.
func stow_interpenetration() -> int:
	var boxes := _stow_link_boxes()
	var hits := 0
	for i in boxes.size():
		for j in range(i + 2, boxes.size()):
			if _oboxes_overlap(boxes[i], boxes[j]):
				hits += 1
	return hits


# The worst-case clearance between two links that are NOT neighbours on the rope, in
# metres. The count above answers "does it fail"; this answers "by how much", which is what
# a review needs in order to know whether the next change has any room left in it.
func stow_link_clearance() -> float:
	var boxes := _stow_link_boxes()
	var best := 999.0
	for i in boxes.size():
		for j in range(i + 2, boxes.size()):
			best = minf(best, _obox_gap(boxes[i], boxes[j]))
	return 0.0 if best > 900.0 else best


# The DRAWN stow's links as oriented boxes, in the stow's own space. Deliberately the
# same walk `_bake_links` does — same cuts, same tangents, same `_link_basis` — so the
# geometry being tested is the geometry on screen and not a parallel model of it.
#
# EACH BOX IS THREE HALF-EDGE VECTORS, NOT THREE UNIT AXES PLUS EXTENTS, and that is not
# pedantry: `Basis.scaled()` scales ROWS, so `_link_basis` applies `LINK_WIDTH_SCALE` in
# the PARENT frame rather than in the link's own — the frame it returns is sheared, and
# any "unit axis × half extent" model of it would describe a link that is not the one
# being drawn. Taking the columns of the real basis times the real mesh half-extents
# describes exactly the parallelepiped `_bake_links` puts on screen, whatever the
# transform does.
func _stow_link_boxes() -> Array:
	var out := []
	if _coil_loops.is_empty() or _stow_seams.size() < 2:
		return out
	var half := maxf(0.012, link_spacing * LINK_FILL * 0.5)
	var tube := half * (1.0 - LINK_TUBE_RATIO) * 0.5
	var normal := _stow_normal()
	for layer in _coil_loops.size():
		if not _coil_loops[layer].visible:
			continue
		var a := _arc_cut(layer, _stow_seams.size())
		var b := _arc_cut(layer + 1, _stow_seams.size())
		for i in range(maxi(0, a), mini(b, _stow_seams.size() - 1)):
			var tangent := _stow_seams[i + 1] - _stow_seams[i]
			if tangent.length_squared() < 0.000001:
				continue
			# the SAME basis the mesh is baked with — same reference normal, same alternation
			var xf := _link_basis(tangent, i % 2 == 1, normal)
			out.append({
				"layer": layer,
				"c": (_stow_seams[i] + _stow_seams[i + 1]) * 0.5,
				# local X = across (width), local Y = the hole axis (thickness), local Z = the rope
				"e": [xf.x * half, xf.y * tube, xf.z * half],
			})
	return out


# Separating-axis test over the full 15 axes: three face normals from each box and the nine
# cross products between them. `radius` uses the HALF-EDGE VECTORS, so a sheared frame is
# measured as the sheared box it is. Degenerate axes (two nearly parallel boxes produce
# near-zero cross products) are SKIPPED rather than used: a zero-length axis projects to
# zero for both boxes and would report a separation that is not there.
static func _obox_gap(a: Dictionary, b: Dictionary) -> float:
	var ae: Array = a.e
	var be: Array = b.e
	var na: Array = [ae[1].cross(ae[2]), ae[2].cross(ae[0]), ae[0].cross(ae[1])]
	var nb: Array = [be[1].cross(be[2]), be[2].cross(be[0]), be[0].cross(be[1])]
	var axes: Array = []
	axes.append_array(na)
	axes.append_array(nb)
	for i in 3:
		for j in 3:
			axes.append(na[i].cross(nb[j]))
	var d: Vector3 = b.c - a.c
	var best := -999.0
	for axis in axes:
		var l2: float = (axis as Vector3).length_squared()
		if l2 < 0.00000001:
			continue
		var n: Vector3 = axis / sqrt(l2)
		var ra: float = 0.0
		for e in ae:
			ra += absf(n.dot(e))
		var rb: float = 0.0
		for e in be:
			rb += absf(n.dot(e))
		best = maxf(best, absf(n.dot(d)) - ra - rb)
	return best


static func _oboxes_overlap(a: Dictionary, b: Dictionary) -> bool:
	return _obox_gap(a, b) <= 0.0


# ===========================================================================
# §STOW · THE RING TEST — BECAUSE A BOX CANNOT DESCRIBE A CHAIN THAT INTERLOCKS.
#
# `stow_interpenetration()` above boxes each link and asks whether two boxes overlap.
# That is faithful while consecutive links are SEPARATE: at pitch 0.11 against a 9.46cm
# link no two links shared a pixel, and a box round each one described it. It stops being
# faithful the moment the chain interlocks, and it fails in the direction that matters.
#
# Two COPLANAR neighbours — links i and i+2 — are one solid slab each, and a curved path
# rotates them into each other's corners. The box test therefore reports an overlap for a
# pair whose real geometry is two RINGS passing round the link between them. A link is not
# a box: a torus is mostly HOLE. MEASURED the moment the pitch changed: 18 box overlaps
# over 50 boxes, almost all of them `j - i == 2` and within one layer, at gaps of −0.0000
# to −0.0186 m — i.e. exactly the pairs the interlock is built out of.
#
# So this test walks each drawn link's RING CENTRE-LINE — the same circle TorusMesh is
# built round, in the same `_link_basis` frame — and takes the true minimum distance
# between two of them, with SEGMENT-to-segment distance and not point-to-point. At a ring
# radius of 3.6cm a 12-gon samples 1.9cm apart, which is larger than the gap being
# resolved, so a sampled-POINT test would report contact wherever it happened to look and
# miss it wherever it did not.
#
# The reading is MATERIAL clearance in metres: two links clear each other while their
# centre-lines are further apart than the two tube radii added together (2 · 0.0114 =
# 0.0227 m). It is reported for three families, because they answer three different
# questions and only one of them is allowed to be near zero:
#
#     · neighbour (i, i+1)  — links that thread BY DESIGN. This is the chain's own
#                             interlock clearance, and it must be POSITIVE but MAY be
#                             small; it is the number that says the chain is physically
#                             buildable, and it is a property of the LINK, not the stow.
#     · layered   (i, j≥i+2) — the stow's own layering, plus the run. Must be positive.
#     · all                  — the min of the two.
# ===========================================================================
const RING_SAMPLES := 12  # matches TorusMesh.rings — the ring that is drawn, not an ideal

func _stow_link_rings() -> Array:
	var out := []
	if _coil_loops.is_empty() or _stow_seams.size() < 2:
		return out
	var half := maxf(0.012, link_spacing * LINK_FILL * 0.5)
	var major := half * (1.0 + LINK_TUBE_RATIO) * 0.5
	var normal := _stow_normal()
	for layer in _coil_loops.size():
		if not _coil_loops[layer].visible:
			continue
		var a := _arc_cut(layer, _stow_seams.size())
		var b := _arc_cut(layer + 1, _stow_seams.size())
		for i in range(maxi(0, a), mini(b, _stow_seams.size() - 1)):
			var tangent := _stow_seams[i + 1] - _stow_seams[i]
			if tangent.length_squared() < 0.000001:
				continue
			var xf := _link_basis(tangent, i % 2 == 1, normal)
			var centre := (_stow_seams[i] + _stow_seams[i + 1]) * 0.5
			var pts := PackedVector3Array()
			for k in RING_SAMPLES:
				var ang := TAU * float(k) / float(RING_SAMPLES)
				# the mesh's own centre-line: major radius in the ring plane, then the
				# link's frame — which is where `LINK_WIDTH_SCALE` lives (see
				# `_link_basis`), so the oval comes out oval and not as a circle.
				pts.append(xf * Vector3(cos(ang) * major, 0.0, sin(ang) * major) + centre)
			out.append({"layer": layer, "c": centre, "pts": pts, "r": major})
	return out


# Minimum distance between two ring centre-lines, over every segment pair. Pruned by a
# centre-distance bound first, because the rings are small and most pairs are metres
# apart: two rings cannot come closer than (rA + rB) below their centres' separation.
func _ring_gap(a: Dictionary, b: Dictionary) -> float:
	var reach: float = a.r + b.r
	if (b.c - a.c).length() > reach * 3.0:
		return 999.0
	var pa: PackedVector3Array = a.pts
	var pb: PackedVector3Array = b.pts
	var n := pa.size()
	var best := 999.0
	for i in n:
		var p1 := pa[i]
		var q1 := pa[(i + 1) % n]
		for j in n:
			var p2 := pb[j]
			var q2 := pb[(j + 1) % n]
			best = minf(best, _seg_seg_dist(p1, q1, p2, q2))
	return best


func stow_ring_readings() -> Dictionary:
	var rings := _stow_link_rings()
	var hit := {
		"neighbour": 999.0, "layered": 999.0, "all": 999.0, "links": rings.size(),
		"n_at": -1, "n_next": -1, "l_at": -1, "l_next": -1,
		"n_pos": Vector3.ZERO, "l_pos": Vector3.ZERO,
	}
	var tube := maxf(0.002, link_spacing * LINK_FILL * (1.0 - LINK_TUBE_RATIO) * 0.25)
	for i in rings.size():
		for j in range(i + 1, rings.size()):
			var raw := _ring_gap(rings[i], rings[j])
			if raw > 900.0:
				continue
			var gap := raw - 2.0 * tube
			hit.all = minf(hit.all, gap)
			if j == i + 1:
				if gap < hit.neighbour:
					hit.neighbour = gap
					hit.n_at = i
					hit.n_next = j
					hit.n_pos = rings[i].c
			elif gap < hit.layered:
				hit.layered = gap
				hit.l_at = i
				hit.l_next = j
				hit.l_pos = rings[i].c
	for key in ["neighbour", "layered", "all"]:
		if hit[key] > 900.0:
			hit[key] = 0.0
	return hit


# Exact minimum distance between two line SEGMENTS (Ericson, Real-Time Collision
# Detection §5.1.9). Point sampling is not good enough here — see `RING_SAMPLES`.
static func _seg_seg_dist(p1: Vector3, q1: Vector3, p2: Vector3, q2: Vector3) -> float:
	var d1 := q1 - p1
	var d2 := q2 - p2
	var r := p1 - p2
	var a := d1.dot(d1)
	var e := d2.dot(d2)
	var f := d2.dot(r)
	var s := 0.0
	var t := 0.0
	if a <= 0.0000000001 and e <= 0.0000000001:
		return r.length()
	if a <= 0.0000000001:
		t = clampf(f / e, 0.0, 1.0)
	else:
		var c := d1.dot(r)
		if e <= 0.0000000001:
			s = clampf(-c / a, 0.0, 1.0)
		else:
			var b := d1.dot(d2)
			var denom := a * e - b * b
			if denom > 0.0000000001:
				s = clampf((b * f - c * e) / denom, 0.0, 1.0)
			t = (b * s + f) / e
			if t < 0.0:
				t = 0.0
				s = clampf(-c / a, 0.0, 1.0)
			elif t > 1.0:
				t = 1.0
				s = clampf((b - c) / a, 0.0, 1.0)
	return ((p1 + d1 * s) - (p2 + d2 * t)).length()


# THE LINK ON ITS OWN — six links on a DEAD STRAIGHT run, alternating, in the free
# rope's own frame (`ref = UP`). No stow, no curvature, no layers: this is the number the
# link's own proportions decide, and it is the control the stow's reading has to be
# compared against. `chain_interlock_bounds()` is the closed form for the same thing.
#
# It exists because the stow reading alone cannot say WHOSE fault a negative clearance is.
# Measured at pitch 0.052 / `LINK_TUBE_RATIO` 0.52: the closed form claims −0.0028 and the
# stow reports −0.0163 — six times worse — so something between the two must be the path
# rather than the link, and this is what separates them.
func chain_straight_clearance() -> Dictionary:
	var half := maxf(0.012, link_spacing * LINK_FILL * 0.5)
	var major := half * (1.0 + LINK_TUBE_RATIO) * 0.5
	var tube := maxf(0.002, link_spacing * LINK_FILL * (1.0 - LINK_TUBE_RATIO) * 0.25)
	var rings := []
	var t := Vector3.RIGHT
	for i in 6:
		var xf := _link_basis(t, i % 2 == 1)
		var centre := t * (link_spacing * float(i))
		var pts := PackedVector3Array()
		for k in RING_SAMPLES:
			var ang := TAU * float(k) / float(RING_SAMPLES)
			pts.append(xf * Vector3(cos(ang) * major, 0.0, sin(ang) * major) + centre)
		rings.append({"c": centre, "pts": pts, "r": major})
	return {
		"adjacent": _ring_gap(rings[2], rings[3]) - 2.0 * tube,
		"skip1": _ring_gap(rings[2], rings[4]) - 2.0 * tube,
		"skip2": _ring_gap(rings[2], rings[5]) - 2.0 * tube,
	}


# THE FAN'S OWN TIGHTEST TURN, in metres of radius — MEASURED off the resampled seams
# rather than derived from the ellipse. It is the number `chain_min_bend_radius()` has to
# be compared against, and it is read from the DRAWN path so that a change to any `ARC_*`
# constant moves it: the squashed ellipse's ends are the tight spot (`b² / a` = 2.46cm at
# `ARC_SQUASH` 0.48), but the run, the tail and the layer boundaries all contribute, and
# the smallest of them is what decides whether the chain can be drawn as links at all.
#
# Discrete curvature from three consecutive seams: the turn between the two chords over
# the mean chord length. Reported as `INF` where the path is straight.
func stow_tightest_radius() -> float:
	if _stow_seams.size() < 3:
		return INF
	var best := INF
	for i in range(0, _stow_seams.size() - 2):
		var a: Vector3 = _stow_seams[i + 1] - _stow_seams[i]
		var b: Vector3 = _stow_seams[i + 2] - _stow_seams[i + 1]
		var la := a.length()
		var lb := b.length()
		if la < 0.0001 or lb < 0.0001:
			continue
		var turn := a.normalized().angle_to(b.normalized())
		var step := (la + lb) * 0.5
		if turn < 0.0001:
			continue
		best = minf(best, step / turn)
	return best


# THE SHARPEST TURN THIS CHAIN CAN TAKE, in metres of arc radius — MEASURED, not derived.
#
# A chain is not a rope. Its links are rigid bodies 9.46cm long, so it can only follow a
# curve down to the radius at which consecutive links jam into each other; below that the
# links have to occupy the same space and the render shows them fused. The stow's arcs are
# a squashed ellipse and their ENDS are where that matters: an ellipse of semi-axes
# (a, b) has radius of curvature `b² / a` at the ends of its MAJOR axis, and at
# `ARC_SQUASH` 0.48 on an `ARC_R_INNERMOST` of 0.130 that is 0.0624² / 0.1586 = 2.46cm —
# a 2.5cm-radius turn for a 9.5cm link, which is why the ring test reports interference at
# `s = 0.33` (the ellipse's own end) at EVERY pitch tried. Shrinking the pitch does not
# help: the turn per step scales with pitch but the LINK does not, so it stays impossible.
#
# So the fan has to be drawn inside this radius or it is not a chain. Measured on a
# synthetic circular arc of the same pitch and alternation, in the stow's own frame, by
# bisection — the smallest radius at which `(i, i+1)` clearance stops being negative.
func chain_min_bend_radius() -> float:
	var lo := 0.02
	var hi := 3.0
	if _circular_arc_clearance(hi) < 0.0:
		return -1.0
	for _step in 22:                      # 22 bisections: 0.02..3.0 to well under 1mm
		var mid := (lo + hi) * 0.5
		if _circular_arc_clearance(mid) >= 0.0:
			hi = mid
		else:
			lo = mid
	return hi


# The smallest `(i, i+1)` ring clearance on a circular arc of radius `radius`, laid in the
# stow's own frame (so `_link_basis` gets the same `ref` the stow gives it). Ten links,
# which is enough to be in the steady state and small enough to run inside a bisection.
func _circular_arc_clearance(radius: float) -> float:
	var half := maxf(0.012, link_spacing * LINK_FILL * 0.5)
	var major := half * (1.0 + LINK_TUBE_RATIO) * 0.5
	var tube := maxf(0.002, link_spacing * LINK_FILL * (1.0 - LINK_TUBE_RATIO) * 0.25)
	var ref := _stow_normal()
	var dphi := link_spacing / maxf(0.001, radius)
	var rings := []
	for i in 10:
		var phi := dphi * float(i)
		var centre := Vector3(cos(phi) * radius, sin(phi) * radius, 0.0)
		var tangent := Vector3(-sin(phi), cos(phi), 0.0)
		var xf := _link_basis(tangent, i % 2 == 1, ref)
		var pts := PackedVector3Array()
		for k in RING_SAMPLES:
			var ang := TAU * float(k) / float(RING_SAMPLES)
			pts.append(xf * Vector3(cos(ang) * major, 0.0, sin(ang) * major) + centre)
		rings.append({"c": centre, "pts": pts, "r": major})
	var best := 999.0
	for i in rings.size() - 1:
		best = minf(best, _ring_gap(rings[i], rings[i + 1]) - 2.0 * tube)
	return best


# THE CHAIN'S OWN INTERLOCK CLEARANCE, INDEPENDENT OF ANY STOW SHAPE, in metres. Two
# identical tori (major radius m, tube radius r) in perpendicular planes at pitch p have
# centre-lines whose minimum separation is EXACTLY `2m − p` — the stationary points of
# that distance fall at the ring's own quadrant points, so it has a closed form and does
# not need to be swept. Material may not overlap, so:
#
#     no interference:  2m − p ≥ 2r      →  p ≤ 2(m − r) = 2 · inner_radius
#     threaded at all:  p < 2m           (else the ring's inner edge cannot reach round)
#
# so a link of THIS size can be a chain only while the pitch sits inside
# `(2r, 2·inner_radius)` = (0.0227, 0.0492) m — a band 2.7cm wide. That is the whole
# reason the interlock pitch and `LINK_TUBE_RATIO` cannot be chosen independently, and
# this function is the assertion that keeps them honest.
func chain_interlock_bounds() -> Dictionary:
	var half := maxf(0.012, link_spacing * LINK_FILL * 0.5)
	var inner := half * LINK_TUBE_RATIO
	var tube := half * (1.0 - LINK_TUBE_RATIO) * 0.5
	return {
		"pitch": link_spacing,
		"min": 2.0 * tube,          # below this the hole is too small to admit the tube
		"max": 2.0 * inner,         # above this the two tubes interfere
		"clearance": 2.0 * inner - link_spacing,   # interference when negative
	}



func _build_trail() -> void:
	_trail = MeshInstance3D.new()
	_trail.name = "HeadTrail"
	_trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_trail_mesh = ImmediateMesh.new()
	_trail.mesh = _trail_mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = TRAIL_TINT
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.vertex_color_use_as_albedo = true
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_trail.material_override = material
	add_child(_trail)


func _place_links(points: Array[Vector3], drawn: int) -> void:
	var multi := _link_mesh.multimesh
	if multi == null or multi.instance_count < links:
		return
	multi.visible_instance_count = drawn
	for i in drawn:
		var a := points[i]
		var b := points[i + 1]
		var tangent := b - a
		if tangent.length_squared() < 0.000001:
			tangent = Vector3.FORWARD
		# Alternating roll, the way real links sit at right angles to each other.
		# It is the single strongest "this is a chain" cue there is, and it costs
		# one boolean.
		multi.set_instance_transform(
			i, Transform3D(_link_basis(tangent, i % 2 == 1), (a + b) * 0.5)
		)


# §5 — the shared link geometry and material, so the rope, the tail of the held
# bundle and any future loop are visibly made of the same object.
func _link_geometry() -> TorusMesh:
	var half := maxf(0.012, link_spacing * LINK_FILL * 0.5)
	var mesh := TorusMesh.new()
	mesh.outer_radius = half
	mesh.inner_radius = half * LINK_TUBE_RATIO
	# 12 around the ring, not 6: see LINK_TUBE_RATIO for why a hexagon was most of
	# what the bundle's "white wire" read actually was. 8 around the TUBE is left
	# as it was — the cross-section being faceted is deliberate (§5) and it is the
	# ring that has to be round.
	mesh.rings = 12
	mesh.ring_segments = 8
	return mesh


func _link_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = LINK_TINT
	# §LINK METAL. `metallic` 0.75 with `roughness` 0.42 was measured to render the
	# whole weapon as a SILHOUETTE: a metal has no diffuse term, so in a scene lit by
	# one directional light plus a sky cubemap it is whatever the sky reflects and
	# nothing else. LINK_TINT is a light steel and the chain was still black in every
	# frame, which is the giveaway — the albedo was never being shown.
	#
	# 0.45 was the next guess and it was ALSO measured wrong, in the V4 review frame:
	# the fistful still came back as a charcoal blob, because a bundle is not one
	# surface — it is dozens of small ovals whose own curvature sends the reflected
	# sky away from the eye, so the average of the bundle is much darker than the
	# average of a link. The number lives here, once, and the bundle uses it too.
	material.roughness = 0.44
	material.metallic = LINK_METALLIC
	return material


# §5 — WHERE A LINK SITS, GIVEN THE ROPE'S DIRECTION.
#
# The torus's own hole faces +Y and its ring lies in XZ, so the ring must be given
# the rope as one of its two in-plane axes and the hole axis as the remaining
# perpendicular. `odd` then swaps that perpendicular, which turns the ring a
# quarter turn about the rope — the alternation a real chain has.
#
# `ref` IS THE THIRD ARGUMENT BECAUSE THE ROPE AND THE STOW NEED DIFFERENT ONES, and
# getting this wrong is invisible in code and enormous on screen. `across` is built as
# `ref × t`, so it lies in whatever plane `ref` and `t` span — which means `ref` decides
# WHICH WAY THE LINK'S RING PLANE FACES. Free rope has no plane of its own, so world UP is
# the right answer there and the default is unchanged. A stow DOES: its links lie in the
# coil's own plane, and handed UP instead they came out tilted 35° out of that plane —
# 0.814 of each link's 6.24cm width pointing along the stacking normal, which ate the
# whole 4.8cm layer separation and left an interpenetration count of 20 instead of 0.
# Passing `_stow_normal()` is the fix, and the reading that proves it is
# `stow_interpenetration()`.
func _link_basis(tangent: Vector3, odd: bool, ref: Vector3 = Vector3.UP) -> Basis:
	var t := tangent.normalized()
	if absf(t.dot(ref)) > 0.95:
		ref = Vector3.FORWARD
		if absf(t.dot(ref)) > 0.95:
			ref = Vector3.RIGHT
	var across := ref.cross(t).normalized()
	if odd:
		across = across.cross(t).normalized()
	# X = the in-plane width, Y = the hole axis, Z = the rope — the link's LONG axis.
	# Squashing X alone is what turns the circular torus into an oval link.
	#
	# AND THE SQUASH IS APPLIED TO THE COLUMN, WHICH IS NOT WHAT `scaled()` DOES.
	# `Basis.scaled(v)` multiplies ROWS, so it post-scales in the PARENT's frame: the
	# previous `Basis(...).scaled(Vector3(LINK_WIDTH_SCALE, 1, 1))` squashed every link
	# along the chain root's X axis, whatever way the rope happened to run. MEASURED on the
	# stow's own links — the half-edges came back 0.0461 / 0.0109 / 0.0356 when a link is
	# 0.0312 / 0.0114 / 0.0473 — so the links were neither the shape nor the orientation
	# this comment describes, and the error is invisible in a frame because a wrong oval is
	# still an oval. Scaling the column scales the LINK's own width. (This is shared with
	# the drawn rope, so the rope's links change with it; that is the point.)
	return Basis(across * LINK_WIDTH_SCALE, t.cross(across).normalized(), t)


# A slam points the head straight down. `looking_at` needs an up vector that is
# not parallel to the direction, or the basis collapses — and a chain that
# disappears during the one move with the biggest height change is a bug that
# only shows up in the last ninety degrees.
func _basis_along(direction: Vector3) -> Basis:
	if direction.length_squared() < 0.000001:
		return Basis.IDENTITY
	var up := Vector3.UP
	if absf(direction.dot(Vector3.UP)) > 0.98:
		up = Vector3.FORWARD
	return Basis.looking_at(direction, up)


# §5 · THE HEAD MUST POINT WHERE IT IS GOING.
#
# It used to take its direction from the LAST LINK — `head - points[n-1]`, a 17cm
# segment that carries the whole of the rope's sag and bow on its far end. Measured
# before this pass: a head doing 76 m/s along a wide sweep was drawn up to 0.33
# cosine away from its own travel, i.e. pointing most of 70° off, and the reading
# got WORSE the more slack the rope had. The blade was aimed into the floor while
# the head flew forward — the "ball on a string" failure, arrived at by arithmetic.
#
# While the head is actually travelling, its own velocity IS its direction, and
# that is the only reading that stays true through a sag, a bow and a whip alike.
# At rest there is no velocity to point along, so a LONGER slice of the rope takes
# over — the same idea, with the last link's tilt divided by five.
func _place_head(
	head: Vector3,
	points: Array[Vector3],
	velocity: Vector3,
	delta: float,
	forced_dir := Vector3.ZERO
) -> void:
	var solved := Vector3.ZERO
	if forced_dir.length_squared() > 0.000001:
		# §18 — ANCHORED. A head that has bitten does not aim: it is held in the
		# surface along the surface's own normal, and the ease below is skipped
		# because there is nothing for it to swing round from.
		_head_dir = forced_dir.normalized()
		_head.global_transform = Transform3D(_basis_along(_head_dir), head)
		return
	if velocity.length() > HEAD_AIM_MIN_SPEED:
		solved = velocity.normalized()
	elif points.size() >= 2:
		var back := maxi(0, points.size() - 1 - HEAD_TANGENT_LINKS)
		solved = head - points[back]
		if solved.length_squared() > 0.000001:
			solved = solved.normalized()
		else:
			solved = Vector3.ZERO
	if solved != Vector3.ZERO:
		# Eased, so a head that reverses swings round instead of flipping, and a
		# slow head cannot chatter between the two sources above.
		var blend := 1.0 - exp(-maxf(delta, 0.0001) / HEAD_TURN_TAU)
		_head_dir = _head_dir.lerp(solved, blend)
		if _head_dir.length_squared() > 0.000001:
			_head_dir = _head_dir.normalized()
	_head.global_transform = Transform3D(_basis_along(_head_dir), head)


# §M · A TRAIL IS A RIBBON, NOT A LINE STRIP.
#
# A line strip is one pixel wide whatever the resolution, so on a 4K capture the
# "where is the head" cue is invisible — which is the one job it has (§32). It is
# also a fixed COUNT of frames, which makes it 8cm long at rest and twenty metres
# long at full spin. So: constant length in METRES, and a camera-facing ribbon
# that is the same width on any screen. Headless has no camera, so the fallback
# faces +Y instead of the eye and the two never disagree about width.
func _update_trail(head: Vector3, delta: float) -> void:
	if _trail_mesh == null:
		return
	_trail_points.push_front(head)
	while _trail_points.size() > TRAIL_MAX_POINTS:
		_trail_points.pop_back()
	while _trail_points.size() > TRAIL_MIN_POINTS and _trail_span() > TRAIL_MAX_LENGTH:
		_trail_points.pop_back()
	var span := _trail_span()
	var moving := _trail_points.size() >= 3 and span > 0.4
	_trail.visible = moving
	if not moving:
		return
	var cam: Camera3D = null
	if is_inside_tree():
		cam = get_viewport().get_camera_3d()
	_trail_mesh.clear_surfaces()
	_trail_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	var count := _trail_points.size()
	for i in count:
		var age := float(i) / float(count - 1)
		var fade := pow(1.0 - age, 2.0)
		var color := Color(TRAIL_TINT.r, TRAIL_TINT.g, TRAIL_TINT.b, fade * 0.55)
		var p := _trail_points[i]
		var tangent := Vector3.ZERO
		if i + 1 < count:
			tangent = _trail_points[i + 1] - p
		elif i > 0:
			tangent = p - _trail_points[i - 1]
		var face := Vector3.UP
		if cam != null:
			face = cam.global_position - p
		if face.length_squared() < 0.000001:
			face = Vector3.UP
		var side := tangent.cross(face)
		if side.length_squared() < 0.000001:
			side = Vector3.RIGHT
		side = side.normalized() * TRAIL_WIDTH * (0.30 + 0.70 * fade)
		_trail_mesh.surface_set_color(color)
		_trail_mesh.surface_add_vertex(p + side)
		_trail_mesh.surface_set_color(color)
		_trail_mesh.surface_add_vertex(p - side)
	_trail_mesh.surface_end()


func _trail_span() -> float:
	var total := 0.0
	for i in range(1, _trail_points.size()):
		total += _trail_points[i - 1].distance_to(_trail_points[i])
	return total
