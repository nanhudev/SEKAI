extends Resource
class_name IaidoTuning

# ---------------------------------------------------------------------------
# SEKAI · Iaido / 聚合斩 — Signature Skill master timeline (V4).
#
# Artistic direction, unchanged and not negotiable without the user:
#   THIS IS AN 8.8 SECOND CEREMONY, NOT A 1-2 SECOND FLOURISH.
#   The draw is one tenth of it. The holds are the point. Do NOT compress it
#   to "feel responsive"; compression only arrives later as an "Iaido mastery"
#   talent, and only after the user has playtested.
#
# V4 exists because V3 was structurally right and still read as a prototype in
# four specific ways, each of which is now a measurable parameter rather than a
# matter of taste:
#
#   1. A THICK DARK BAR ACROSS THE FRAME for two seconds. The wound was drawn
#      with a shadowed cross-section band plus an ivory lip running its whole
#      length for the whole hold, which is a UI separator, not a break. V4
#      deletes every drawn edge: after the blade passes, the ONLY evidence of
#      the cut is that the two halves of the world no longer line up.
#   2. THE WORLD DID NOT ACTUALLY SPLIT. The halves were displaced, but the
#      opening was authored wide enough to cover its own displacement. V4 keeps
#      the opening a slit (<= 9px at 1080p) and lets the separation (10px per
#      half, so a 20px step) carry the read.
#   3. THE SCABBARD WAS A BOX. The blade could not be seen to enter anything.
#      V4 adds a real koiguchi anchor and drives the sword along the bore axis.
#   4. THE TENSION WAS FLAT. V3 spread its beats evenly. V4 keeps one long
#      stillness, one extremely fast draw, and one very slow final sheathe.
#
# PHASE MAP (V7)
#   0.00 - 0.26  A · WORLD SILENCE        the world is switched off
#   0.26 - 3.24  B/C · RETURN + CHARGE    ONE LINEAR MOTION covering the whole
#                                         charge. The blade walks home at a
#                                         single constant speed while the
#                                         energy converges, and it is FULLY
#                                         HOME at the instant the world stops.
#   3.06 - 3.24  D · GREY                 the world turns to grey glass
#   3.24 - 3.58  D · TIME STOP            everything stops, including the void
#   3.58 - 3.68  E · SHEATH LOCK          the koiguchi closes on a blade that
#                                         is already home
#   3.68         E · SHEATH CLICK         click
#   3.68 - 4.68  E · ONE SECOND           a full second of nothing. this is the
#                                         last chance to change your mind
#   4.68 - 4.78  F · INSTANT DRAW         100ms, against two seconds of waiting
#   4.78 - 5.02  G · CONSEQUENCE DELAY    0.24s in which the blade is OUT, the
#                                         pose is held, and NOTHING HAPPENS
#   5.02 - 5.50  G · THE SPLIT            the world becomes two pieces
#   5.50 - 5.90  G · HERO HOLD            [dead] the poster: one world, two
#                                         surfaces, and nothing moving
#   5.90 - 7.15  H · FRACTURE STREAM      the stress cracks grow along the
#                                         slash, the surface vitrifies, and the
#                                         panes take the world over one at a time
#   6.30 - 7.30  K · WRIST ARCS           the blade is brought under control
#   7.20         L · FIRST TO LET GO      a handful of panes come loose
#   7.30 - 8.40  L · RETURN TO SHEATH     last 5-10cm crawl into the mouth
#   8.40         L · FINAL CLICK          the blade is home
#   8.46 - 9.15  M · DEVOUR + COLLAPSE    structural failure. the pieces move.
#   9.15 - 9.90  N · RESTORE              drawn back in, reality reconnects
#
# WHY V7 REORDERS V6
#
# V6 got the time stop right and then spent the whole split window eating the
# world. The glassification stream started at the same instant as the cut and
# ran the length of the slash, so by the time the two halves had moved far
# enough apart to be legible, two thirds of the frame had already been consumed.
# The result read exactly as the user described it:
#
#     完整画面 + 一条裂纹贴图
#
# — a whole picture with a line drawn on it. Not a break, because at no single
# instant was there a world that was visibly two pieces.
#
# The fix is not a new effect. It is three reorderings and one deletion:
#
#   1. CONSEQUENCE DELAY. The blade is out at 4.78 and the world does not react
#      until 5.02. In between, the pose is held and nothing moves. Threat reads
#      as speed when the reaction is late — 拔刀本身更快、更危险.
#   2. THE SPLIT GETS ITS OWN WINDOW, and it is the ONLY thing happening in it.
#      No cracks, no glass, no drain: just two halves of one world moving apart.
#   3. THE HERO HOLD. 0.40s of absolute stillness on a broken world, declared as
#      a dead window so nothing — camera, blade, void drift — can move in it.
#      This is the screenshot the whole skill exists for.
#   4. THE STREAM MOVES AFTER ALL OF THAT. It is what happens when the broken
#      surface can no longer hold its shape, not what causes the break.
#
# CUT FIRST. FRACTURE SECOND. COLLAPSE LAST. The glass is the consequence, and
# in V6 it was the cause.
# ---------------------------------------------------------------------------

# --- PHASE A · WORLD SILENCE ---------------------------------------------
@export_group("A · World Silence")
@export var silence_start := 0.0
@export var silence_end := 0.26
@export var silence_fov := 4.0
# Barely anything here. Colour is not a state the ceremony starts in — it is
# taken away over the charge, from the koiguchi outward, so at t=0 the world is
# still itself and the drain is something the sword does to it.
@export var silence_desaturation := 0.10

# --- PHASE B/C · RETURN TO HIP, INSIDE THE CHARGE ------------------------
# 收刀不单独成段. The blade does NOT get its own beat in front of the charge,
# and it does NOT stop half-way home and wait there.
#
# It used to: 0.26-1.06 walked to the hip and parked with the last 5cm proud of
# the mouth, the whole two-second charge passed with the sword standing still,
# and a separate seat at 3.58 pushed the rest of it in. Two motions, two
# easings (ease-in-out then ease-out-cubic), and — for the entire charge — a
# blade visibly NOT yet in its scabbard. The user's note was that this reads as
# the sheathe being a separate animation that happens to precede the charge:
#
#     不要单独出现收刀了，蓄力过程中慢慢收刀，蓄力完成之后就收完全，线性
#
# So there is now exactly ONE motion, and it is deliberately the least
# interesting curve there is. `sheath_start -> sheath_end` is walked at a
# CONSTANT speed along the tip's own path (see `_sheath_path()` in the
# director), and `sheath_end` is `time_stop_start` — i.e. the blade arrives
# home at the same instant the world stops, two and a half seconds of the
# ceremony later. The charge IS the sheathe. Nothing is parked, nothing is
# proud of the mouth, and there is no second act: the click at `first_click`
# is the koiguchi closing on a sword that has been home for half a second.
@export_group("B/C · Return To Hip")
@export var sheath_start := 0.26
@export var sheath_end := 3.24
@export var sheath_move_cue := 0.52

# --- PHASE C · REVERSE COMPRESSION ---------------------------------------
# Accelerating convergence: each shell is shorter than the last, then a final
# instant drain swallows whatever is left. Never one constant-speed ring.
#
# THE WINDOWS OVERLAP. A shell's visible ring peaks in the middle of its window
# and has collapsed to a point at the mouth by the end of it, so shells laid out
# end to end leave a lull between every pair — the "小断电" in the middle of the
# wind-up. Each shell now opens while the previous one is still collapsing
# (0.40 / 0.38 / 0.30 into it) and the vacuum opens before the last shell has
# died, so the compression never stops moving from `wave_start` to the stop.
# The durations still shorten — 0.60 / 0.52 / 0.44 — because the accelerating
# rhythm comes from the staging, not from the lengths being large.
@export_group("C · Reverse Compression")
@export var wave_start := 1.06
@export var ring1_start := 1.06
@export var ring1_end := 1.66
@export var ring2_start := 1.46
@export var ring2_end := 1.98
@export var ring3_start := 1.84
@export var ring3_end := 2.28
# The vacuum is not a shell — it is the single event that swallows what the
# shells left — so it gets a long window and runs UNTIL THE WORLD STOPS.
#
# `suck_end` must equal `time_stop_start` (they are both 3.24), and the
# integration test asserts it: the union of the four windows then covers the
# whole charge, so there is no instant between the first shell opening and the
# clock stopping at which nothing is travelling. Ending it at 3.10 left a 0.14s
# tail where every shell and the vacuum were parked and only the envelope was
# still fading — a decrescendo of nothing, which is what the user heard as a
# power cut.
@export var suck_start := 2.14
@export var suck_end := 3.24
# The charge's STRENGTH ends here, releasing over [wave_end - 0.20, grey_end] so
# the sword is still pulling the world in as the colour leaves it and the two
# stop together. Releasing at `wave_end` left a fifth of a second with neither
# warp nor grey — the other half of the power cut.
@export var wave_end := 3.06
@export var wave_fov := 7.0
# Camera nudge magnitudes, in radians, for the only three impulses in the
# performance: the vacuum, the slash, and the collapse.
@export var slash_impulse := 0.024
@export var wave_impulse := 0.006

# --- PHASE D · GREY, THEN ABSOLUTE STOP ----------------------------------
# THE CHARGE PAYS OFF AS TWO BEATS, NOT ONE, AND THE GREY IS SOMETHING THE
# SWORD DOES RATHER THAN A STATE THE WORLD IS PUT INTO.
#
# Colour does not switch off globally at the end of the charge: it drains out of
# the world FROM THE KOIGUCHI OUTWARD, starting the moment the charge starts and
# finishing as the charge does. A uniform desaturation is a filter, and a filter
# has no cause — it just means the camera changed. Anchoring the change to the
# mouth of the scabbard makes the two seconds of standing still visibly be DOING
# something, which is the entire job of that hold.
#
# Then, with the world already dead, everything stops — including the thing
# behind reality. Sequence matters: greying inside the stop makes the stop look
# like a render hitch; stopping first makes the grey look like a filter.
@export_group("D · Grey + Time Stop")
@export var hold_start := 3.06
# The colour has finished leaving by here — which is also the instant the stop
# begins. `grey_spread` in the shader is what travels; this is where it lands.
@export var grey_end := 3.24
@export var time_stop_start := 3.24
@export var time_stop_end := 3.58
@export var hold_end := 3.58
@export var hold_fov := 9.0
@export var hold_desaturation := 0.74

# --- PHASE E · SEAT + CLICK + ONE SECOND ---------------------------------
# The blade goes home in the first tenth of a second, and then nothing happens
# for a full second. That second is the whole point of the phase: the player has
# asked for the cut, the sword is seated, and the world is giving them one last
# chance to not be here for it.
@export_group("E · Sheath Lock")
@export var seat_start := 3.58
@export var fov_pull_start := 3.58
@export var first_click := 3.68
@export var wait_end := 4.68
@export var fov_pull_end := 4.78
@export var draw_fov := 13.0
@export var ivory_flash_duration := 0.030
@export var ivory_flash_strength := 0.26

# --- PHASE F · INSTANT DRAW ----------------------------------------------
# 100ms against two seconds of waiting. The first `draw_axial_share` of it is
# pure extraction along the bore; only then does the blade leave the axis and
# arc out. A straight lerp between two poses skips the extraction, and the
# extraction is the part that reads as a draw.
@export_group("F · Instant Draw")
@export var draw_start := 4.68
@export var draw_end := 4.78
@export var draw_axial_share := 0.55

# --- PHASE G · THE SPLIT -------------------------------------------------
# THE HOLE IS NEVER AUTHORED INDEPENDENTLY OF THE DISPLACEMENT.
#
# V4/V6 carried two separate tracks — `gap_px` and `separation_px` — and a guard
# that asserted their ratio, which is a guard against the code disagreeing with
# itself. V1's disaster was a 50px lit band over a 12px displacement: the hole
# was the picture. The ratio is the thing that must never invert, so in V7 there
# is only ONE track and the hole is derived from it:
#
#     gap_px = separation_px * gap_ratio        (0.60)
#
# Retuning the separation retunes the hole with it, the ratio cannot drift, and
# "make the crack bigger" is now one number instead of two that have to be kept
# in step by hand.
#
# `gap_ratio` must stay under 0.75. The eye reads the DISPLACEMENT as the break
# and the HOLE as the depth of it; past about three quarters, the hole becomes
# the picture again and the wound turns back into a beam, whatever colour it is.
@export_group("G · World Split")
# The blade is out at `draw_end` (4.78). This is 0.24s later, and the gap is the
# 150-300ms of NOTHING the design asks for: no shift, no crack, no sound. The
# draw has to feel like it might simply not have worked.
@export var cut_start := 5.02
# The split is complete. The halves have moved as far apart as they ever will,
# the hole is at its full width, and everything after this until `hero_hold_end`
# is a hold on a world that is visibly in two pieces.
@export var cut_end := 5.50
# THE HERO HOLD. A dead window — see `time_stops()`. The camera, the blade, the
# panes and the void's own drift are all pinned for 0.40s so the player can look
# at a broken world with nothing moving in it. This is the frame the acceptance
# test screenshots, and it has to work as a still.
@export var hero_hold_end := 5.90
# THE HOLE AS A FRACTION OF THE SEPARATION. See the note above: under 0.75.
#
# 裂缝大一点, and it is the half of it that is actually visible. Raising
# `separation_px` alone widens the misregistration but leaves the OPENING where
# it was, and the opening is the thing the eye measures as "how wide is the
# break" — the step across it is read as damage.
#
# THE CEILING IS 0.75 AND PASS 4 IS NOWHERE NEAR IT. 0.60 here, against a
# separation of 11, puts the slit at 6.6 authored px: 4.4 real px at 720p,
# which is the middle of FINAL LOCK PART A's 2-5px band. It sat at 0.34 for
# one round of this pass and that was a misreading of PART A — the numbers
# PART A asks to be cut by 50-70% are the EAT COLLAR (which was ±148 authored
# px and is now ±14.4, see CLAIM_TAIL), not the slit. The slit is what the
# reviewer is being asked to LOOK INTO, and at 0.34 it was under two real
# pixels: present in the frame, absent from the read.
@export var gap_ratio := 0.60
# A sub-pixel floor, so the wound exists as a hairline the instant the split
# begins rather than appearing at a threshold.
@export var gap_min_px := 0.3
# The blade passing: a 1-3px ivory line that exists for 30ms and is then gone
# for the rest of the performance. This is the ONLY line allowed.
@export var blade_flash_duration := 0.030

# --- PHASE H · SEPARATION -------------------------------------------------
# Per half, in 1080p pixels, along the cut normal. 26 here means up to a 52px
# step between the two images wherever an edge crosses the wound.
#
# 裂缝大一点. This was 20 (a 40px step) and the note asked for a bigger break.
# It is raised here rather than in the hole, because the displacement is the
# term that carries the read: the eye believes the misregistration across every
# silhouette and merely glances at the opening. `gap_ratio` is untouched at
# 0.62 — still a long way under the 0.75 ceiling, so the wound stays a slit the
# displacement is revealed through rather than a band the picture is seen past.
#
# This is the term that carries the read, and it is the term that was allowed to
# grow: every silhouette crossing the cut misregisters, which is what says
# "these are two pieces of the world" rather than "there is a dark line".
#
# THE TWO HALVES DO NOT MOVE EQUALLY, AND THEY DO NOT STAY PARALLEL.
#
# A break that moves both sides by exactly the same amount, along exactly the
# same axis, in exactly the same plane has a symmetry no physical event has —
# and symmetry is what the eye reads as "digital". `split_bias` gives side A 45%
# of the travel and side B the rest, and a few hundredths of a degree of
# differential rotation tilts the two images by a hair relative to each other.
# Both are far below the threshold of noticing individually. What they do is
# stop the wound reading as a slide transition.
@export_group("H · Separation")
# FINAL LOCK PART B — 4-6px on side A, 5-8px on side B, 8-14px total, "根据分辨
# 率缩放". 11 authored px is 7.3 real px per half at 720p, i.e. a 14.7px step:
# the top of the brief's band, and half of what the reviewer watched and called
# an overlay. The step is still what carries the read — every silhouette that
# crosses the wound moves — it is simply no longer a wide slide.
@export var separation_px := 11.0
@export var split_bias := 0.45
# The halves do not only separate along the normal — each also slides a little
# ALONG the cut, so the misregistration is not perpendicular to the wound. This
# is the fraction of the separation that becomes along-cut slide. The world
# shader and the pane offset in IaidoGlassLayer both read it, or the glass and
# the world would disagree about where the halves sit.
@export var split_shear := 0.50
@export var split_rotation_a_deg := 0.05
@export var split_rotation_b_deg := -0.08
@export var depth_parallax := 0.010

# --- PHASE I · CAPTURE + THE BROKEN EDGE ---------------------------------
# The world capture for the glass is taken INSIDE THE HERO HOLD, which is a
# change of meaning rather than of timing. It used to be taken at the instant of
# the cut, on the theory that the panes should carry an unbroken picture. They
# should not: the panes are the pieces of a world that is ALREADY in two pieces,
# and a pane carrying a continuous image of a surface that has been cut in half
# puts the lie straight back into the effect the moment it moves. Taken at 5.70
# the capture contains the split, the hole, the displaced halves and the edge
# band — so every shard shows the building / ground / sky it was cut from AND
# the fact that its world was broken, which is the whole of §24.
#
# The FOV is also constant from 4.78 to 9.15, so a capture taken here still
# registers with the live frame all the way through the collapse. That is not a
# coincidence — it is why the capture is allowed to move at all.
@export_group("I · Capture")
@export var capture_time := 5.70
## How long before `capture_time` the capture rig is armed. The rig is a second
## camera on the same world and needs one drawn frame before its picture can be
## taken; 0.12 s is seven frames at 60, and `capture_time` sits inside the hero
## hold, so arming early costs nothing but a little overdraw — inside a dead
## window every frame is the same frame.
@export var capture_arm_lead := 0.12
@export var cut_desaturation := 0.78

# --- THE BROKEN EDGE -----------------------------------------------------
# A break does not end at its outline. It ends in a band of material that has
# changed state, and without it the wound's boundary is just the edge of a
# shape. Three things happen in this band, in this order outward from the hole:
#
#   INNER VOID EDGE   the last pixels before the hole go near-black.
#                     (drawn by the void itself, see the shader)
#   REFRACTION EDGE   the world BENDS toward the wound over `edge_band_px`.
#                     This is the one that matters: a few pixels of real UV
#                     displacement on each side is what proves the surface is
#                     not flat any more. V6 had this at 0.55px mixed at 0.22 —
#                     a fifth of a pixel of effective movement, which is to say
#                     it was not there.
#   SPECULAR EDGE     a cold catch of light. NEVER along the whole length: only
#                     the fraction of the cut between `edge_spec_low` and
#                     `edge_spec_high` in a low-frequency field along the slash,
#                     which is about a quarter of it. An evenly lit edge is a
#                     neon slash, and a neon slash is a UI element.
@export_group("Broken Edge")
# 6 -> 8 with 裂缝大一点. This is the BAND of changed material on each side of
# the hole, so it is the third and widest way the break reads bigger without a
# single new thing being drawn: the hole widened, its edge got raggeder, and
# the material that has visibly changed state around it widened with them.
@export var edge_band_px := 4.0
@export var edge_refract_px := 3.0
@export var edge_spec_strength := 0.22
@export var edge_spec_low := 0.56
@export var edge_spec_high := 0.72
@export var edge_spec_color := Color(0.72, 0.86, 0.96)

# --- PHASE J · THE FRACTURE STREAM ---------------------------------------
# 流式玻璃化. The surface does not become glass all at once; the change travels
# ALONG the slash, from the end the blade entered to the end it left, opening
# outward from the wound as it goes. Each pane becomes glass as the front
# reaches it, and the world it is cut from is consumed at the same instant — one
# event seen twice, which is why the glass reads as the surface peeling off the
# void rather than as a layer added on top of a picture.
#
# IT NO LONGER STARTS WITH THE CUT. In V6 this ran from 4.78, so the world was
# already being eaten while it was still trying to separate, and the split never
# got a frame in which it was legible. The stream is what happens when a broken
# surface can no longer hold its shape — it is not what breaks it.
@export_group("J · Fracture Stream")
@export var glass_start := 5.90
@export var glass_prop_end := 6.80
@export var glass_stream_end := 7.15
# The panes let go in the same order the front arrived, one after another, over
# this span. Set to 0 to detach them all together (which is what a "shatter"
# looks like and is not what this is).
@export var stream_detach_span := 1.32
@export var glass_end := 7.15
@export var post_break_slide_px := 14.0

# --- RETURN COMPRESSION · the shells open again on the way home -----------
# 收刀前没有扭曲 was the user's note, and it is a fair one: the blade walks home
# over a frame that has stopped being touched by anything, so the last and
# slowest physical process in the ceremony is the one with no pressure in it.
#
# So the charge's own shells are opened a SECOND time while the blade is walked
# back to the mouth — slower, wider and weaker than the charge. The shape is not
# re-authored: `_return_rhythm` in the director stretches the charge's windows
# by `return_wave_scale`, so retuning the charge retunes the return with it and
# the two can never drift into being different effects.
#
# The charge is the sword taking something out of the world. The return is the
# world closing back around the sword. Same language, opposite direction.
@export_group("L · Return Compression")
@export var return_wave_start := 6.80
# 0.72 stretches the charge's 2.18s of compression to 1.57s, landing the release
# on the final click rather than after it: `6.80 + 2.18 * 0.72 = 8.37`, and
# `final_click` is 8.40. The warp is therefore present for the whole walk back
# to the mouth — 收刀前没有扭曲 — and gone the instant the blade is home.
@export var return_wave_scale := 0.72
@export var return_wave_strength := 0.62

# --- PHASE K · FLOAT + ROTATE --------------------------------------------
# 漂浮旋转. The panes keep turning while the blade is put away. This is the only
# point in the ceremony where the camera, the sword and the world are all still
# and something else is moving, so it is the beat that sells the glass as
# objects rather than as a screen layer.
@export_group("K · Float + Rotate")
@export var spin_start := 6.30
@export var spin_first_end := 6.78
@export var spin_end := 7.30
# FINAL LOCK PART I — the sword yields the centre of the frame to the break.
#
# After the world is in two pieces the first subject is THE BROKEN WORLD and the
# blade is the second, so both arcs are tighter, lower and further right than
# they were — the sweep no longer carries the blade back across the wound. The
# lift is nearly gone for the same reason: it was pulling the arcs up into the
# middle of the frame, which is where the cut is.
@export var spin_radius_first := 0.038
@export var spin_radius_second := 0.015
@export var spin_lift := 0.004

# --- PHASE L · RETURN TO SHEATH ------------------------------------------
# The last 5-10cm have to be the slowest physical process in the whole
# performance. `final_insert_slowdown` is how much of the total travel time is
# given to that final approach.
@export_group("L · Return To Sheath")
@export var slow_sheathe_start := 7.30
@export var final_insert_start := 7.90
@export var slow_sheathe_end := 8.40
@export var final_click := 8.40
@export var final_insert_slowdown := 0.42

# --- PHASE K · DEVOUR ----------------------------------------------------
# 吞噬. THIS IS WHAT THE END OF THE CEREMONY IS FOR. It runs AFTER the blade is
# home, not before, and it finishes the job the stream started: the far corners
# the front never reached are eaten, the emptiness closes over the frame, and
# the surface lets go completely. Doing it before the sheathe (as V5 did) put
# the world's disappearance in the middle of the one beat that is supposed to be
# about the sword.
@export_group("M · Devour")
# FINAL LOCK PART K — THE CLICK IS THE TRIGGER, NOT A PRELUDE TO ONE.
#
# The collapse used to begin 0.25s AFTER the final sheath click, which made the
# click a sound effect and let the world break on its own schedule. The brief
# makes the click the second climax, with world / enemy / audio all firing off
# it within ±1-3 frames. 8.42 is two frames after `final_click` — inside the
# brief's spread, so the three are one event rather than three coincidences.
@export var devour_start := 8.40
@export var devour_end := 9.15
@export var seated_hold_end := 8.40
@export var collapse_start := 8.42
@export var collapse_end := 9.15
# The collapse is the one moment the opening is ALLOWED to beat the displacement:
# reality is letting go, not being cut, so the hole widening past the step is the
# correct read for a single transient frame. It is held to 15px because it is
# 1.4% of the frame height — a collapse, not a wipe — and it lasts 0.5s against
# 40px of separation, so it can never be mistaken for the wound itself.
@export var collapse_gap_px := 18.0
@export var collapse_impulse := 0.018
# How far a failed world cell is allowed to slide off its neighbours. This is
# the cue that reads as "material", not the seam line: a seam drawn on a flat
# surface is a grey line on a screen, a seam with a visible step across it is a
# broken surface.
@export var shatter_px := 42.0

# --- WORLD DRAIN · where the surface has already been eaten ----------------
# The emptiness is not a fade and it is not a lighting state. It spreads as a
# FRONT, and behind the front there is no world information at all — only the
# void's own depth. Fading the whole frame uniformly is a brightness slider:
# every silhouette stays in shot, just quieter, and it reads as a mistake.
#
# TWO fronts feed it, and they are the same front seen at two moments:
#
#   `stream`  eats what the glassification front has already turned over, so the
#             world leaves exactly where the panes arrive. This is the peeling.
#   `devour`  finishes the job at the end of the ceremony, after the blade is
#             home, and swallows what the stream never reached.
@export_group("World Drain")
# The devour resolves into the SAME void the wound opened onto, so these carry
# the same lift the void palette took — otherwise the collapse ends on a black
# frame while the wound that caused it was blue, and the two read as unrelated
# events instead of one absence arriving.
# FINAL LOCK PART N — THE DEVOUR RESOLVES INTO THE WOUND, NOT INTO A FADE.
#
# These were a full step brighter and bluer than the void palette, so the end of
# the ceremony emptied the frame into a different absence than the one the cut
# opened onto — two unrelated events instead of one absence arriving. They now
# sit just above `void_back_color` / `void_deep_color`: the corners the stream
# never reached go to the SAME place the wound already was.
@export var drained_world_color := Color(0.038, 0.068, 0.140)
@export var drained_world_deep := Color(0.014, 0.026, 0.058)
# The crack network belongs to the surface that is leaving, so it goes with it.
@export var drain_crack_fade := 1.0

# --- PHASE L · RESTORE ---------------------------------------------------
@export_group("N · Restore")
@export var restore_start := 9.15
@export var restore_end := 9.90
@export var reconnect_pulse := 0.030

# --- Combat resolution ---------------------------------------------------
# THE HIT LANDS WHEN THE WORLD REACTS, NOT WHEN THE BLADE LEAVES.
#
# `damage_time` used to be one hundredth of a second after the draw, which put
# the hit flash, the target marks and the enemy's stagger in the same frame as
# the blade coming out — i.e. it spent the consequence delay on nothing. The
# delay exists so the draw reads as fast and the world reads as slow, and the
# payoff has to be on the far side of it: the enemy is cut at the instant the
# world splits.
@export_group("Combat")
@export var damage_time := 5.02

# --- 聚合斩 · THE EXECUTION ----------------------------------------------
# THE SIGNATURE KILLS. That is not a balance tweak, it is the whole premise of the
# execution system: §FINAL RULE asks that the enemy which dies to this刀 be the
# proof that the刀 happened, and an enemy that is merely left at 55 health cannot
# be that proof. So the primary target of the slash takes a number that is lethal
# to a standard enemy, and everything else the same plane passes through takes
# one that usually is — which is also what makes MULTI-KILL (§P) real rather than
# theoretical.
#
# 240 against a 120-health construct is not inflation: `execution_damage` is not
# a damage number at all, it is the answer to "did this kill it", and it is read
# exactly once, by one enemy, to decide which of two entirely different deaths it
# gets. A future damage-curve pass may retune it freely.
@export_group("Execution")
@export var execution_damage := 240.0
@export var execution_damage_splash := 120.0
# The only camera bias in the ceremony that looks at something the player did not
# choose to look at, so it is bounded twice: by magnitude, and by the target
# having to already be inside the middle of the frame. §J.
@export var execution_settle := 0.010
@export var execution_settle_offset_limit := 0.55

# --- Camera ---------------------------------------------------------------
# How fast the three cinematic impulses die away, per second of CEREMONY time.
#
# The impulses are evaluated from the timeline rather than accumulated on the
# frame clock. Accumulating them meant the camera kept settling through a time
# stop that is supposed to freeze it mid-move, and — worse — it made two renders
# of the same instant differ, so a frozen window could never be proven frozen.
@export_group("Camera")
@export var camera_impulse_decay := 12.6

# --- The scabbard (C2B-05 mechanical interface) --------------------------
# The mouth is a real anchor, not a prop pose. The sword cannot be lerped
# between two pretty transforms any more: it has to travel along the bore,
# because the whole second half of the ceremony is the blade going home and a
# lerp does not pass through the mouth.
@export_group("Scabbard")
# Centre of the koiguchi, in WeaponRoot space.
@export var sheath_position := Vector3(-0.58, -0.46, -0.72)
# Mouth -> kojiri. This is the scabbard's local +Y, and the direction the blade
# travels to go home. Authored down and back, so the body leaves the frame
# within about a third of a metre and the mouth stays the focus.
@export var scabbard_axis := Vector3(-0.20, -0.72, 0.66)
# Which way the cutting edge faces when the blade is seated (the local -X).
# Worn edge-up, as a katana is.
@export var scabbard_edge := Vector3(0.15, 0.55, 0.82)
# Axial travel of the sword origin between fully seated and fully drawn.
@export var blade_reach := 0.95
# Sword-local y of the tsuba's outer face. Fully seated = tsuba against the
# mouth, which is what puts the guard and only the guard outside it.
@export var guard_setback := 0.045
# How far home the blade is when the opening sheathe finishes. ONE, because the
# blade is fully seated: it used to be 0.94 — "parked" with 5cm of blade root
# proud — and the whole charge then ran with the sword visibly not yet in its
# scabbard. 蓄力完成之后就收完全. See PHASE B/C above.
@export var sheath_depth := 1.0

# --- Framing --------------------------------------------------------------
@export_group("Framing")
@export var drawn_position := Vector3(0.44, -0.55, -1.05)
@export var drawn_rotation := Vector3(-0.22, 0.06, -1.02)
@export var cut_angle_degrees := -30.0
@export var cut_center := Vector2(0.5, 0.5)
# How much the two faces of the break chip independently of each other. Zero
# gives two mirrored outlines, which is a drawn shape; a few pixels of
# independent raggedness is what makes the void's edge read as a fracture
# rather than as a cut-out. The wound carries no drawn cross-section in V4 —
# this chipping is the only thing shaping its edge.
#
# 4 -> 6 with 裂缝大一点: the raggedness is measured OUTWARD from the hole on
# both faces, so it is the second place the break gets wider without anything
# new being drawn. A perfectly straight edge reads as a slit cut in a print;
# these few pixels are what make it a broken one.
@export var void_edge_width_px := 4.5

# --- Void palette (cold, airless, NOT sci-fi portal) ---------------------
# THE PALETTE HAS TO SURVIVE THE WIDTH THE WOUND ACTUALLY HAS.
#
# These were authored as near-black sRGB — #020711 back, #06142A depth,
# #0B2A4A near the wound — which renders correctly and is why the wound came
# out at rgb(0,0,5): a hole with nothing in it reads as a black line, and
# §1 forbids the primary effect to be one. The values are lifted roughly 3x,
# holding the same hue, so the slot shows DEPTH instead of absence. Sampled at
# the hero hold the band now sits around rgb(22,44,84) against a world of
# rgb(150,160,175): unmistakably dark, unmistakably blue, unmistakably a hole.
# FINAL LOCK PART C — "near-black navy / deep indigo / desaturated cyan depth /
# tiny pale core occasionally. 不要 neon blue." These were lifted ~3x in the
# previous pass because a hole with nothing in it reads as a black LINE — but
# that pass was buying legibility with width, and it paid for it twice: the slot
# was 17.7 authored px wide AND bright enough to read as a blue band across the
# frame. Now that PART A has narrowed it to 3.7px, the slot can be dark again.
# Roughly 45% off the previous values, holding the hue.
@export_group("Void Palette")
@export var void_back_color := Color(0.030, 0.052, 0.110)
@export var void_deep_color := Color(0.070, 0.132, 0.260)
@export var void_lip_color := Color(0.105, 0.208, 0.365)
@export var void_core_color := Color(0.420, 0.580, 0.700)
@export var void_life := 1.0
# The void drifts while the world does not. 0.1 is deliberate: any faster and
# it reads as an effect running on top of the frame rather than as somewhere
# the frame has opened onto.
@export var void_speed := 0.10

# --- Glass ----------------------------------------------------------------
# The panes are 3D meshes so they can carry real rotation, depth and angular
# velocity. Their material samples the frozen world, so each shard shows the
# piece of building / ground / sky it was cut out of.
#
# ARRIVING AND LETTING GO ARE TWO DIFFERENT EVENTS.
#
# V6 ran them off one clock: a pane took the world over at the instant the
# fracture front reached it, and it also started moving at that instant. So the
# whole surface had come apart and flown before the blade was even half way
# home, and by the final click — the moment the design says structural failure
# happens — there was nothing left to fail.
#
# They are separated here. `stream` decides when a pane TAKES OVER (the world
# leaves under it and it stands in the world's place, still). Nothing moves
# then. Only `loosen_start` and `collapse_start` physically detach anything:
#
#   loosen_start      a handful of panes — the ones nearest the wound — come
#                     free. They are allowed `loose_drift_scale` of their
#                     velocity, which is to say a few millimetres: enough to
#                     read as no longer attached, not enough to read as falling.
#                     This is 玻璃已经坏了，只是还没有掉.
#   collapse_start    the final click. Every pane fails at once and the real
#                     motion begins. The difference either side of this instant
#                     is supposed to be enormous.
@export_group("Glass")
@export var shard_count := 14
# How many panes are allowed to come loose before the final click. The design
# asks for 2-5; the panes chosen are the ones closest to the wound, because
# those are the ones a real break would release first.
@export var shard_loose_count := 4
@export var loosen_start := 7.20
@export var loose_drift_scale := 0.10
@export var shard_min_delay := 0.03
@export var shard_max_delay := 0.09
@export var shard_drag := 3.8
@export var shard_gravity := 0.85
# Extent of the fracture field, in screen half-heights. Slightly over 1 keeps
# the outer cells running past the frame so nothing reads as a floating tile.
@export var shard_size := 1.15
# How far each micro-cell's picture slides off its neighbours. This is the crack
# — the displacement is the damage and the drawn seam only deepens it — so it
# carries more of the read than it used to (8 -> 11 -> 14). 裂缝大一点: this is
# the term that makes the network read as a surface coming apart rather than as
# lines printed on one, so it moves before the drawn seam does.
@export var refract_px := 14.0

# --- HUD ------------------------------------------------------------------
@export_group("HUD")
@export var hud_presence := 0.15
@export var hud_fade_time := 0.25

# --- Playback -------------------------------------------------------------
@export_group("Playback")
@export_range(0.25, 2.0, 0.05) var debug_speed := 1.0


# --- Easing helpers --------------------------------------------------------
# Kept here so every stage uses the same curves. Do not inline raw lerps
# in the director; a signature skill lives or dies on its easing.

static func span(t: float, start: float, end: float) -> float:
	return clampf((t - start) / maxf(end - start, 0.0001), 0.0, 1.0)


static func ease_out_cubic(x: float) -> float:
	var u := clampf(x, 0.0, 1.0)
	return 1.0 - pow(1.0 - u, 3.0)


static func ease_out_quint(x: float) -> float:
	var u := clampf(x, 0.0, 1.0)
	return 1.0 - pow(1.0 - u, 5.0)


static func ease_in_cubic(x: float) -> float:
	var u := clampf(x, 0.0, 1.0)
	return pow(u, 3.0)


static func ease_in_accel(x: float) -> float:
	# Slow release, violent finish. Used by the instant draw.
	var u := clampf(x, 0.0, 1.0)
	return pow(u, 2.6)


static func ease_in_out(x: float) -> float:
	var u := clampf(x, 0.0, 1.0)
	return u * u * (3.0 - 2.0 * u)


static func smooth(x: float) -> float:
	var u := clampf(x, 0.0, 1.0)
	return u * u * (3.0 - 2.0 * u)


static func ease_in_quint(x: float) -> float:
	var u := clampf(x, 0.0, 1.0)
	return pow(u, 5.0)


# --- The scabbard basis ----------------------------------------------------
# Built rather than authored as a raw euler, so the mechanical relationship is
# legible: +Y is the bore, and -X is the side the edge lies against.
# A raw euler hides which of its three numbers means what, and this thing has
# to line up with a real mesh.
func scabbard_basis() -> Basis:
	var y := scabbard_axis.normalized()
	var e := scabbard_edge - y * scabbard_edge.dot(y)
	if e.length_squared() < 0.000001:
		e = Vector3.FORWARD - y * Vector3.FORWARD.dot(y)
	e = e.normalized()
	var x := -e
	var z := x.cross(y)
	return Basis(x, y, z)


func total_duration() -> float:
	return restore_end


# --- Time stops -----------------------------------------------------------
# THE PERFORMANCE HAS THREE DEAD WINDOWS, AND NOTHING IS ALLOWED TO RUN THROUGH
# THEM.
#
# This is a single source of truth on purpose. In V5 the stop was declared here
# and then contradicted in three places that interpolated on wall time — the FOV
# push, the desaturation and the half-degree camera breath all carried on
# through it, so a "frozen" window measured the same pixel delta as a window
# where things are supposed to move. Any system that wants to know whether the
# ceremony clock is running asks this function, not the wall clock.
#
#   window 0  the grey and the stop: the world has lost its colour and
#             everything, including the void's own drift, stops dead through the
#             seat of the blade.
#   window 1  the second after the blade is home, before it has to come out.
#   window 2  THE HERO HOLD. The world is in two pieces and nothing is allowed
#             to move: not the camera, not the blade, not the panes, not the
#             void behind them. Declaring it here rather than special-casing it
#             is what makes it work — every clock in the ceremony already knows
#             how to be dead inside a window, so the still is free.
func time_stops() -> Array:
	return [
		[time_stop_start, time_stop_end],
		[first_click, wait_end],
		[cut_end, hero_hold_end],
	]


## True while the ceremony clock is held, i.e. inside any dead window.
func clock_held(t: float) -> bool:
	for window in time_stops():
		if t >= float(window[0]) and t < float(window[1]):
			return true
	return false


## CEREMONY TIME ELAPSED SINCE `t0`, WITH EVERY DEAD WINDOW IN BETWEEN REMOVED.
##
## THIS IS THE ONLY CORRECT CLOCK FOR ANYTHING PHRASED AS "HOW LONG SINCE EVENT
## X", and it is what makes a stop actually stop. Inside a dead window the value
## is identical to what it was at entry — the panes hang, the ramps hold — and
## after the window it resumes from exactly there instead of jumping forward.
##
## The windows are clipped to `[t0, t]`, which matters: a window that happened
## BEFORE `t0` must contribute nothing, or a ramp that starts after a stop would
## be evaluated as if it had already been partly spent.
func since(t: float, t0: float) -> float:
	var total := 0.0
	for window in time_stops():
		total += maxf(
			minf(t, float(window[1])) - maxf(t0, float(window[0])), 0.0)
	return maxf(t - t0, 0.0) - total


## The void's own clock: the ceremony clock with every dead window subtracted.
##
## `since(t, 0.0)`, spelled separately because this is the name the rest of the
## codebase reads and because the void is the thing whose drift gives the stop
## away when it is wrong.
func stopped_clock(t: float) -> float:
	return since(t, 0.0)


# --- THE GLASSIFICATION FRONT ---------------------------------------------
#
# ONE FRONT, COMPUTED IN ONE PLACE.
#
# The world shader draws the front and the glass layer decides when each pane
# lets go. If those two ever compute it separately they drift, and a pane that
# arrives before or after the world has left its position is EXACTLY the
# "floating screenshot" fault this whole front exists to delete. So the director
# asks for the value to push to the shader, the glass layer asks for the arrival
# of its own pane, and both get the same curve.

## How far along the slash the front has travelled: 0 at the end the blade
## entered, 1 at the end it left.
func stream_at(t: float) -> float:
	var window := maxf(glass_stream_end - glass_start, 0.0001)
	return ease_in_out(clampf(since(t, glass_start) / window, 0.0, 1.0))


## The head of the front runs PAST the end of the line.
##
## `travel` saturates at 1.0, so a front compared against `stream` directly
## reaches the far end of the slash only in the limit: the last few percent of
## the line sits permanently half-arrived, and what that looks like is a strip
## of live world along one corner that the glass never claims.
##
## These three live here AND in `iaido_fracture_field.gdshaderinc` (as
## IAIDO_LEAD_OVERSHOOT / IAIDO_ARRIVED_BACK / IAIDO_ARRIVED_FRONT). They were
## 1.14 / 0.10 / 0.06 in the shader and plain 1.00 / 0.10 / 0.06 here: the
## world pass finished its front and the glass layer never did, so the panes at
## the far end of the slash topped out at 32% opacity over world the screen pass
## had already fully claimed. `_verify_stream_arrived_matches_the_shader()`
## asserts the two agree now.
const STREAM_LEAD_OVERSHOOT := 1.14
const STREAM_ARRIVED_BACK := 0.10
const STREAM_ARRIVED_FRONT := 0.06


## 1 once the front has passed `travel`, 0 before it.
##
## THE MIRROR OF `iaido_arrived()` IN `iaido_fracture_field.gdshaderinc`. That
## equality is the whole contract, and it is asserted.
func stream_arrived(t: float, travel: float) -> float:
	var lead := stream_at(t) * STREAM_LEAD_OVERSHOOT
	var x := clampf(
		(travel - (lead - STREAM_ARRIVED_BACK))
			/ (STREAM_ARRIVED_BACK + STREAM_ARRIVED_FRONT),
		0.0, 1.0)
	return 1.0 - (x * x * (3.0 - 2.0 * x))


# NOTE: `stream_arrival_time(travel)` used to live here — the bisection that
# inverted the front to find WHEN a pane took the world over. It is gone, and
# deliberately: nothing needs it any more. The fracture front decides when a
# pane TAKES OVER (read as a value, `stream_arrived`), and a pane's physical
# release is `loosen_start` or `collapse_start`. There is no third clock to
# invert, and keeping an inverse for a curve nothing counts from is how a
# helper quietly stops matching the curve it inverts.


# --- HOW FAR OUT OF THE WOUND THE GLASS HAS GROWN --------------------------
#
# 玻璃从裂痕蔓延. THE GLASS IS A BAND OUT OF THE WOUND, NOT A SHEET OVER THE
# FRAME.
#
# `stream_arrived()` answers "has the front passed this point ALONG the slash",
# and on its own that is a false question: every point on the frame answers yes
# eventually, so the panes end up tiling the whole picture from corner to corner
# and the mosaic stops being a consequence of the wound. What it looked like is
# a full-screen net of pastel cards laid over the arena — the wound was no
# longer the source of anything.
#
# `iaido_grown()` in the shared field already knows the missing half of the
# answer: the fracture front is a DISTANCE FROM THE CUT, in authored pixels, and
# it travels outward as the stress rises. The panes are only glass where that
# front has reached. So the glass starts as a line on the wound, creeps outward
# for as long as the fracture ramps, and NEVER covers the corners — the devour
# takes those later, which is what the devour is for.
#
# These four numbers live here AND in `iaido_fracture_field.gdshaderinc` (as
# IAIDO_FRONT_PER_FRACTURE / _PER_SHATTER / _CORE / _TAIL), and they are the
# STRESS reach: how far the fracture NETWORK has spread across the surface. The
# network is thin seams plus a few pixels of displacement, it is secondary
# detail, and NOTHING is removed from the world for it.
#
# HOW MUCH OF THE PICTURE THE PANES TAKE OVER IS A SECOND, MUCH NARROWER
# NUMBER — see CLAIM_CORE / CLAIM_TAIL below. Driving the eat off the stress
# reach is what put a ±45-authored-px near-black band along the cut (60 real px
# at 720p): the network may be wide because it is thin, and the eat may not
# because it is not.
const FRONT_PER_FRACTURE := 90.0
const FRONT_PER_SHATTER := 480.0
const FRONT_CORE := 0.50
const FRONT_TAIL := 1.0


# ---- THE COLLAR ----------------------------------------------------------
#
# FINAL LOCK PART A/B. The panes are FILLED regions with an alpha, and the world
# is DELETED underneath them — so their reach is how much of the frame goes,
# not a detail. Measured at fracture 1 (front 90) the wall of the wound is fully
# glass out to `90 * 0.05 = 4.5` authored px and the last of it is gone by 14.4:
# a skin that hugs the slot the break actually opened.
#
# SIZED AGAINST THE SLIT, NOT AGAINST THE FRONT. `gap_ratio` 0.60 of an 11px
# separation is a 6.6 authored px hole, so the collar is the hole plus the two
# or three pixels of transition PART D asks for as the broken edge band — and
# nothing more, because everything past the slit is a band around a slit and a
# band around a slit is the 世界裂口像 Overlay read arriving through the EAT.
#
# The collapse is the exception and gets its own term (`unleashed_at`), because
# a surface coming apart is all of its pieces at once.
#
# Mirrors IAIDO_CLAIM_CORE / IAIDO_CLAIM_TAIL in the shared field.
const CLAIM_CORE := 0.05
const CLAIM_TAIL := 0.16


## How far out of the wound the fracture front has reached, in authored pixels
## of a 1080-tall frame. The mirror of `iaido_front()`.
func front_at(t: float) -> float:
	return maxf(
		fracture_at(t) * FRONT_PER_FRACTURE + shatter_at(t) * FRONT_PER_SHATTER,
		0.001)


## 1 where the front has grown out to `ad_px` from the cut, 0 beyond it.
## The mirror of `iaido_grown()`.
func grown_at(t: float, ad_px: float) -> float:
	var front := front_at(t)
	var inner := front * FRONT_CORE
	var x := clampf(
		(ad_px - inner) / maxf(front + FRONT_TAIL - inner, 0.0001), 0.0, 1.0)
	return 1.0 - (x * x * (3.0 - 2.0 * x))


## 1 where the panes have taken the surface over, 0 where it is still world.
## The mirror of `iaido_claimed()`.
##
## THIS IS NOT `grown_at()`. `grown_at()` is the STRESS gate — it is what the
## crack network is drawn with, wide on purpose. This is the GLASS gate, and it
## is what the world's EAT is driven from and what the pane's alpha is gated on,
## so it is narrow on purpose. See CLAIM_CORE.
func claimed_at(t: float, ad_px: float) -> float:
	var front := front_at(t)
	var inner := front * CLAIM_CORE
	var x := clampf(
		(ad_px - inner) / maxf(front * CLAIM_TAIL - inner, 0.0001), 0.0, 1.0)
	return 1.0 - (x * x * (3.0 - 2.0 * x))


## 1 once the collapse has the frame, 0 through the whole of the hold.
## The mirror of `iaido_unleashed()`.
func unleashed_at(t: float) -> float:
	return smoothstep(0.02, 0.34, shatter_at(t))


## The STRESS number, and only that: how much of the fracture network this
## point carries. Used to decide whether a pane is WORTH DRAWING at all and how
## it arrives along the slash — the pane's actual opacity is shaped per pixel by
## the collar in `iaido_glass_shard.gdshader`, because a per-pane opacity taken
## from the pane's CENTRE can never match a per-pixel eat, and the mismatch
## between the two is a visible band.
##
## `ad_px` is the distance from the cut in authored pixels (see the shared
## field), `travel` the position along the slash.
func cover_at(t: float, travel: float, ad_px: float) -> float:
	return stream_arrived(t, travel) * grown_at(t, ad_px)


# --- THE COMPRESSION RHYTHM -----------------------------------------------
#
# ONE AUTHORED SHAPE, PLAYED TWICE.
#
# The charge and the return are the same effect in opposite directions, so they
# are the same four windows played from two different starts at two different
# speeds. `scale` stretches each window about `start` and `strength` scales the
# whole envelope, so the return is never re-authored and cannot drift into being
# a different effect as the charge is retuned.
#
# THIS LIVES HERE, NOT IN THE DIRECTOR, FOR THE SAME REASON `stream_at` DOES:
# the property that matters — 蓄力的扭曲空间不要断了 — is a claim about the
# WINDOWS, and `tests/iaido_integration.gd` has to be able to assert it against
# the real arithmetic rather than against a copy of it. A test that re-derives
# the curve only proves the test agrees with itself.
#
# Returns { a, b, c, suck, strength } — exactly the five quantities the shader's
# reverse-compression block reads.
func compression_at(t: float, start: float, scale: float, strength: float) -> Dictionary:
	var s: float = maxf(scale, 0.0001)
	var anchor := wave_start
	# Progress of one shell, measured on the STOPPED clock so a dead window
	# anywhere inside a compression freezes it rather than sliding it.
	var shell := func(t0: float, t1: float) -> float:
		var a: float = start + (t0 - anchor) * s
		var b: float = start + (t1 - anchor) * s
		return span(since(t, a), 0.0, maxf(b - a, 0.0001))
	# The envelope is stretched and offset WITH the shells, or the return would
	# open at full strength before its first shell exists. The release lands on
	# `grey_end` rather than on `wave_end`: the sword is still pulling the world
	# in as the colour leaves it and the two stop together, whereas releasing at
	# `wave_end` left a fifth of a second with neither warp nor grey.
	var env := span(since(t, start - 0.06 * s), 0.0, 0.14 * s)
	env *= 1.0 - ease_in_out(span(
		since(t, start + (wave_end - 0.20 - anchor) * s),
		0.0,
		maxf((grey_end - wave_end + 0.20) * s, 0.0001)))
	# The vacuum is not a shell — it is the single event that swallows what the
	# shells left — so it gets a long window. The shader deliberately does NOT
	# scale its `suck` term by `wave_strength` (it is a mouth glow, not a ring),
	# so `strength` is folded in here; that is the only way the return's vacuum
	# can be weaker than the charge's.
	var suck := span(
		since(t, start + (suck_start - anchor) * s),
		0.0,
		maxf((suck_end - suck_start) * s, 0.0001))
	return {
		"a": shell.call(ring1_start, ring1_end),
		"b": shell.call(ring2_start, ring2_end),
		"c": shell.call(ring3_start, ring3_end),
		"suck": suck * env * strength,
		"strength": env * strength,
	}


# --- THE FRACTURE STRESS ---------------------------------------------------
#
# ONE CURVE, READ BY THREE PLACES.
#
# The world shader turns the fracture network open with it, the panes draw the
# same network with it, and the director uses it to decide how hard the surface
# is being pushed. When those three computed it separately they disagreed — the
# panes were crackling out on a fast ease while the world was still on a slow
# one — and a region could be weak in one layer and strong in the other at the
# same instant. That is the same class of bug the shared UE5 bake exists to
# delete, one level up.
#
# Neither curve crosses a dead window (both are zero until `glass_start`, which
# is the end of the hero hold), so these are plain interpolations and do not
# need the plateau machinery in the director.
func fracture_at(t: float) -> float:
	return _curve(t, [
		Vector2(glass_start, 0.0),
		Vector2(glass_start + 0.20, 0.42),
		Vector2(glass_prop_end, 0.74),
		Vector2(glass_stream_end, 0.95),
		Vector2(slow_sheathe_start, 1.0),
		Vector2(restore_start, 1.0),
		Vector2(restore_end, 0.0),
	], ease_out_cubic)


## 0..1 surface failure. Nothing fails until the collapse.
func shatter_at(t: float) -> float:
	return _curve(t, [
		Vector2(collapse_start, 0.0),
		Vector2(collapse_end, 1.0),
		Vector2(restore_end, 0.0),
	], ease_out_cubic)


## THE STRESS the shaders open the network on: how far past the surface's own
## strength the event is. Both shaders must compute this identically — this is
## that one computation.
func stress_at(t: float) -> float:
	return clampf(fracture_at(t) * 1.20 + shatter_at(t), 0.0, 1.0)


## A piecewise curve, eased once across each segment. The director has a richer
## version with per-segment easing and dead-window plateaus; this one is for the
## curves that are shared and that provably never touch a window.
func _curve(t: float, keys: Array, ease: Callable) -> float:
	if keys.is_empty():
		return 0.0
	if t <= float(keys[0].x):
		return float(keys[0].y)
	for i in range(1, keys.size()):
		var a: Vector2 = keys[i - 1]
		var b: Vector2 = keys[i]
		if t <= float(b.x):
			if is_equal_approx(float(b.x), float(a.x)):
				return float(b.y)
			return lerpf(float(a.y), float(b.y), ease.call(span(t, a.x, b.x)))
	return float(keys[keys.size() - 1].y)


## The windows a compression plays, in seconds, for one start and scale.
##
## Exposed so the integration test can assert the STRUCTURAL property that no
## instant of the charge is dead — i.e. that the windows genuinely overlap —
## without modelling the shader's ring profile. A ring only moves while its
## progress is strictly between 0 and 1, so if the four half-open windows
## `(start, end)` have no hole in their union, nothing can ever be parked.
func compression_windows(start: float, scale: float) -> Array:
	var s: float = maxf(scale, 0.0001)
	var anchor := wave_start
	var out: Array = []
	for pair in [
		[ring1_start, ring1_end],
		[ring2_start, ring2_end],
		[ring3_start, ring3_end],
		[suck_start, suck_end],
	]:
		out.append([
			start + (float(pair[0]) - anchor) * s,
			start + (float(pair[1]) - anchor) * s,
		])
	return out

