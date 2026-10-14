extends RefCounted
class_name SwordBasic
const CONFIG = preload("res://resources/tuning/SwordConfig.tres")

static func attack_value(field: String, index: int) -> float:
	var values: PackedFloat32Array = CONFIG.get(field)
	return values[index]
# Sword mature pass: two-handed right probing cut -> left return -> body-led uppercut -> major arc.
# A2 retains the existing pressure wave; A3 is now one close rising body contact.
# The left hand counterbalances each cut and owns the physical draw/sheath bore.
# Legacy A3 constants below remain for compatibility with archived probes.
#
# ===========================================================================
# THE KEYS ARE AUTHORED IN CAMERA SPACE
# ===========================================================================
#
# x right, y up, -z forward, blade tip along +Y of its own node. Same frame the
# Universal layer already uses, so nothing downstream has to learn anything —
# and when the ART line's real hand/arm animation lands it replaces these
# numbers, not the timing language around them.
#
# ===========================================================================
# NUMBERS ARE FIRST-PASS ON PURPOSE
# ===========================================================================
#
# §29 and §37 both say the same thing: at this stage FEEL is the deliverable and
# the damage figures are a placeholder. The repair windows, the event instants
# and the distance grammar are the parts that are meant to survive tuning.

# --------------------------------------------------------------------- ids
const READY := Vector3(0.24,-0.23,-0.62)
const READY_R := Vector3(-0.39585,0.0,-0.584081)

const A1 := &"sb_a1"
const A2 := &"sb_a2"
const A3 := &"sb_a3"
const A4 := &"sb_a4"
const EQUIP := &"sb_equip"

# ------------------------------------------------------------- event names
# §23's contract. Audio and VFX listen to these; nothing guesses a time.
const EV_SHEATH_TOUCH := &"A1_SHEATH_TOUCH"
const EV_DRAW := &"A1_DRAW"
const EV_ACTIVE := &"A1_ACTIVE"
const EV_FINISH := &"A1_FINISH"
const EV_RELEASE := &"A2_RELEASE"
const EV_WAVE := &"A2_WAVE"
const EV_A2_FINISH := &"A2_FINISH"
const EV_A3_SHEATHE := &"A3_SHEATHE"
const EV_DOMAIN_START := &"A3_DOMAIN_START"
const EV_CUT_1 := &"A3_CUT_1"
const EV_CUT_2 := &"A3_CUT_2"
const EV_CUT_3 := &"A3_CUT_3"
const EV_DOMAIN_END := &"A3_DOMAIN_END"
const EV_ARC_START := &"A4_ARC_START"
const EV_A4_ACTIVE := &"A4_ACTIVE"
const EV_ARC_END := &"A4_ARC_END"

# --- presentation events (SWORD PRESENTATION V3) ---------------------------
#
# These are NOT combat events: nothing about them can hit anybody, and the hit
# resolution does not read them. They exist because §3's draw has beats whose
# whole content is light, and the alternative to naming the instant is a VFX node
# guessing it from the move's total length — which goes stale the first time the
# draw is retuned, silently, in the direction of the blade still being in the
# sheath.
const EV_EQUIP_CARRY := &"EQUIP_CARRY"       # the assembly is up and still
const EV_EQUIP_GLINT := &"EQUIP_GLINT"       # Beat 3's cold glint begins
const EV_EQUIP_SEAT := &"EQUIP_SEAT"         # blade home, stance reached
const EV_SAYA_PUSH := &"SAYA_PUSH"           # Beat 4: the off hand drives back

# --------------------------------------------------------- audio event names
# §25's vocabulary, SPOKEN rather than guessed. A beat's identity cue is declared
# on the move (`SwordMove.audio_cue`) and its later instants are named here, so
# the sound of A3's second cut is attached to the same number that produced the
# second mark. All of them resolve through `CombatAudioDirector.play_event`,
# which is the one door into the audio system.
const AU_SAYA_TOUCH := &"SWORD_SAYA_TOUCH"
const AU_DRAW := &"SWORD_IAIDO_DRAW"
const AU_WAVE := &"SWORD_WAVE_CUT"
const AU_SPACE_CUT_1 := &"SWORD_SPACE_CUT_1"
const AU_SPACE_CUT_2 := &"SWORD_SPACE_CUT_2"
const AU_SPACE_CUT_3 := &"SWORD_SPACE_CUT_3"
const AU_ARC := &"SWORD_ARC_WIDE"

# ------------------------------------------------------------- pose anchors
#
# The saya mouth, in camera space: left side, below the chest, a little forward,
# with the blade lying along the sheath. A1 STARTS here and A3 RETURNS here, so
# this single anchor is what makes the two beats rhyme instead of merely
# following each other.
const SAYA_MOUTH := Vector3(-0.40, -0.40, -0.86)
## The rotation the sword has while it is at that mouth, and therefore — since
## the blade lies down the bore — the direction the SCABBARD points too.
##
## Solved, not typed: this triple puts the blade's own +Y on roughly
## (-0.30, -0.73, 0.62), which is down, back and a little left, i.e. a saya worn
## at the left hip with its mouth up at the hand. The alternative — leaving the
## blade horizontal and to the left — would have the scabbard held out sideways
## like a torch, and it is the *saya's* direction that makes the draw read.
const SAYA_MOUTH_R := Vector3(-0.50, 0.50, 2.55)


## Where the mouth IS when the blade is home — the mouth plane, in the sentence's
## own space.
##
## ONE EXPRESSION, THREE READERS, and the reason this is a function rather than a
## number is that the three have to be the SAME point and not three points that
## happen to agree:
##
##   * every `SAYA_MOUTH` beat, which is the sword's origin — a tsuba's worth
##     behind the mouth;
##   * `SwordSayaRig`'s rest pose, which is where the saya sits when nobody is
##     asking it to do anything;
##   * the LAST beat of the draw, so that the moment the draw stops being
##     choreographed is not also the moment the sheath moves.
##
## The third one was the bug. The draw used to end at a hand-placed point 133 mm
## from this one, and `tools/probe_saya_motion.gd` measured the handover as a
## single-update jump of 128.9 mm — a teleport, on every weapon switch, in a
## place where no screenshot can show anything at all.
##
## `id` is a parameter rather than a read of this file's own constant because
## `SwordSayaRig` wears whatever class the weapon slot names, and a second
## sword class must not silently inherit the first one's tsuba setback.
static func saya_home(id: StringName = WEAPON_ID) -> Vector3:
	return SAYA_MOUTH + Basis.from_euler(SAYA_MOUTH_R) * Vector3.UP \
		* SwordClasses.guard_setback(id)


## Which way the bore runs, in camera space: from the mouth down the scabbard,
## which is also the blade's own +Y while it is home. Unit length.
##
## This is the ONE direction a scabbard can be moved along while a blade is in it.
## Sliding the mouth deeper down the blade is what a left hand actually does in a
## draw, and it costs no clearance — the axes stay parallel, so `FIT_CLEAR` is
## untouched. Any component perpendicular to this is the mouth walking off the
## blade, which is the fault `tools/probe_blade_clearance.gd` measures.
static func bore_axis(id: StringName = WEAPON_ID) -> Vector3:
	return (Basis.from_euler(SAYA_MOUTH_R) * Vector3.UP).normalized()


## Where the grip has to be for the blade's TIP to sit `depth` metres inside the
## mouth — the partial seat §13 of the Controlled Stillness brief asks A3 for.
##
## Derived from the same two registry numbers the full seating already uses, so a
## partial return cannot disagree with the complete one: at `depth == reach -
## tsuba` it returns `SAYA_MOUTH` exactly, which is the beat every return used to
## be written as by hand.
static func partial_seat(depth: float, id: StringName = WEAPON_ID) -> Vector3:
	return SAYA_MOUTH + bore_axis(id) * (SwordClasses.guard_setback(id) + depth
		- SwordClasses.blade_reach(id))


## How far the pose's own scabbard mouth is from where the scabbard's mouth is.
##
## Two readers, one expression — the same discipline as `saya_home`, and for the
## same reason. `TempSwordVisual` uses it to decide when the blade is close enough
## to its seat that a lagging filter would push it through the scabbard wall, and
## `CombatController` uses it to decide when the left hand has to stop breathing
## and hold. Two copies of this arithmetic would be two chances for the pose and
## the hand to disagree about when "home" starts.
##
## A pose is a position AND a rotation, so the comparison is between two mouth
## PLANES: the blade's own (`origin + +Y * tsuba`) and the scabbard's.
static func mouth_gap(position: Vector3, rotation: Vector3,
		id: StringName = WEAPON_ID) -> float:
	return mouth_gap_to(position, rotation, saya_home(id), id)


## The same gap, measured to a mouth the caller supplies.
##
## ===========================================================================
## `saya_home()` IS WHERE THE SAYA RESTS, AND THE SAYA DOES NOT ALWAYS REST
## ===========================================================================
## The rest position is the right mouth for every cut, because a cut has nothing
## to say to a scabbard and the scabbard stays home. It is the WRONG mouth for
## the three acts that move it: A1 pulls it 48 mm, A2 and A4 tuck it 56 and 76,
## and A3 holds it at an anchor 50 mm off the rest and works it 15 mm up and down
## the bore on top of that. `SAYA_MOUTH_R` is the half of it that costs clearance
## and the anchor is not on that axis.
##
## So a constraint measured against the rest released up to 65 mm early on A3,
## and `tools/probe_blade_clearance.gd` saw exactly that: at t = 0.317 s of A3
## the frame held 11 mm of blade inside the mouth with a 0.6 degree axis error
## while `follow` read 0.9325 -- i.e. the filter believed the blade was 9 mm
## clear when it was 11 mm in. The target was perfect (`targ` 0.0000). The
## scabbard had simply moved and nothing told the test.
static func mouth_gap_to(position: Vector3, rotation: Vector3, mouth: Vector3,
		id: StringName = WEAPON_ID) -> float:
	var blade_mouth := position \
		+ Basis.from_euler(rotation) * Vector3.UP * SwordClasses.guard_setback(id)
	return blade_mouth.distance_to(mouth)


## THE WINDOW IN WHICH THE POSE IS A CONSTRAINT AND NOT A MOTION.
##
## Returns 1 when the scabbard must be held EXACTLY — no breathing, no lag, no
## tremor, no pose filter — 0 when nothing about it is constrained, and a smooth
## ramp between so there is no mode change to snap at.
##
## ===========================================================================
## THE WINDOW IS A LENGTH, SO IT IS DERIVED FROM ONE
## ===========================================================================
## The old rule was `equip_blend <= NE_BLADE_CLEAR`, which is the DRAW's clock:
## it cannot see A1 putting the blade home at t = 0 of every swing, and it cannot
## see A3 putting it home three times with the equip idle.
##
## The obvious replacement — "is the blade near the mouth", with a hand's width
## for a threshold — is worse in a way that took a probe run to see. The gap
## between the blade's own mouth plane and the scabbard's mouth GROWS BY EXACTLY
## THE EXTRACTION DISTANCE, so a 50 mm window releases the constraint after 50 mm
## of a 757 mm extraction: the blade is still almost entirely inside the scabbard
## and the filter is free to lag it off the bore, which is what
## `tools/probe_blade_clearance.gd` then measured at A3 (39.9 mm of transverse
## error with 0.19 m of blade still home).
##
## A blade is inside its scabbard until its TIP passes the mouth, and `gap` is
## the extraction distance itself -- `saya_home()` is the koiguchi and
## `mouth_gap()` measures to it, so `gap == blade_reach` is exactly the frame the
## tip clears. That IS the window, so that is what the window is.
##
## == WHY THE FIRST EDITION RELEASED 84 mm TOO EARLY ==
## It ramped from `blade_reach - guard_setback - 0.080`, which reads like "a
## hand's width of margin" and is not: measured against the extraction it spends
## the last 84 mm of tip INSIDE the tube with the rider layers already coming
## back. `tools/probe_blade_clearance.gd` caught it as an intermittent fault --
## `a1` reported 25.3 mm on one run and 1.9 mm on the next -- because the
## violation lived in the one or two frames either side of the release and the
## probe's sample phase is not stable across runs. A fault that appears on some
## runs is worse than one that appears on all of them.
##
## So the near edge holds until 6 mm of tip is left, and the far edge is the
## ramp. Both are small on purpose: this is a geometric boundary, not a feel
## knob, and a release the player can watch is a release that is in the wrong
## place.
const SEAT_HOLD := 0.006
const SEAT_RELEASE := 0.090


static func seat_restraint(gap: float, id: StringName = WEAPON_ID) -> float:
	var clear := SwordClasses.blade_reach(id)
	return 1.0 - smoothstep(clear - SEAT_HOLD, clear + SEAT_RELEASE, gap)


# A1's ending. Deliberately NOT the idle pose: the brief is explicit that the
# blade stops on the right and does not recentre, because that is what gives A2
# a natural start instead of a re-take.
const RIGHT_SIDE := Vector3(0.44, -0.46, -0.86)
const RIGHT_SIDE_R := Vector3(0.04, 0.34, -1.24)
# A2's ending, which A3 begins from: still on the off hand's side of the body.
const LEFT_MID := Vector3(-0.34, -0.30, -0.84)
const LEFT_MID_R := Vector3(-0.10, -0.24, 1.05)

# ------------------------------------------------------------------ timings
# A3's structure, in seconds, exactly as §9 lays it out. Named because the trace
# instants, the event instants and the beat list all have to agree, and three
# copies of "0.34" is three chances for them to stop agreeing.
const A3_RETURN_HOME := 0.10
const A3_HOLD_END := 0.16
const A3_CUT1 := 0.16
const A3_CUT2 := 0.34
const A3_CUT3 := 0.54
const A3_RESOLVE := 0.68
const A3_SETTLE := 0.78
const A3_TOTAL := 1.00

# ------------------------------------------------- §12-§14 · A3's left hand
#
# THE ANCHOR is the pose the hand holds for the whole three-cut sequence: the
# mouth offered up and forward, toward where the blade comes from. It is added to
# the BLADE's seated beats as well, which is the whole reason it can exist — a
# mouth that moves and a blade that does not is a blade through the wall.
const A3_ANCHOR := Vector3(0.0, 0.028, -0.042)
# §13's partial returns, as a fraction of the blade's own length: 20-30% the
# first time and 25-35% the second. Expressed as a fraction so the deepest point
# of a return cannot silently stop being proportional when the sword class
# changes length.
const A3_SEAT_1 := 0.26
const A3_SEAT_2 := 0.34
# How far clear of the mouth the alignment beat sits. 60 mm is about a third of
# the scabbard's outer width: far enough that the turn that follows it cannot
# clip the koiguchi, near enough that the slide in is still legible.
const A3_ALIGN_GAP := 0.060
# §14's reciprocation, along the bore and only along the bore. 15 mm is inside
# the 1-3 cm the brief asks for and is invisible to the clearance: the scabbard
# slides down its own axis, so the axes stay parallel.
const A3_RECEIVE := 0.015

# ------------------------------------------------- §7-§17 · the left hand
#
# One block, because they are one idea read four ways: a scabbard moves only when
# it has a reason, and the reasons are present / clear / receive / tuck.
#
# A1 · §8's counter-pull. Its DIRECTION is not free — see `a1()`. 48 mm of
# translation is inside the brief's 3-6 cm and 5.2 degrees of roll is inside its
# 5-10.
const A1_COUNTER_PULL := 0.048
const A1_ROLL := 0.090
const A1_HOLD := 0.110
## How far clear of the mouth A1's wind-up sits — i.e. how far the blade has
## travelled down its own scabbard by the time the wrist is allowed to move. 30 mm
## of tip outside the koiguchi is enough that the turn that follows cannot clip
## it, and it is small enough that the draw still reads as "the blade was home a
## moment ago". See `a1()` for why the wind-up has to be a slide at all.
const A1_CLEAR_GAP := 0.030
# A2 · §10's tuck: left, down, and in toward the body, 56 mm in total.
const A2_CLEAR := Vector3(-0.040, -0.035, 0.018)
const A2_CLEAR_R := Vector3(0.0, -0.055, 0.045)
# A4 · §16's tuck: left, back and down. 76 mm, the largest in the sentence.
const A4_TUCK := Vector3(-0.050, -0.048, 0.030)
const A4_TUCK_R := Vector3(0.020, -0.095, 0.055)

# The full sentence, measured: 0.40 + 0.415 + 1.00 + 0.66 = 2.48s. The brief
# asks for 2.5-4.0s and warns against every beat becoming a two-second set
# piece; this sits at the bottom of that band on purpose, because it is a BASIC
# and the player has to be able to do it without waiting for it.
const COMBAT_STANCE_R := Vector3(0.04, 0.28, -0.90)

# ------------------------------------------------------------- E0 → E3 (§19)
#
# R E T I R E D · E1, E2 and EQUIP_TOTAL. These four numbers were the chord
# through pose space that the five-beat draw below replaced: two interior keys and
# a 0.62 s length. Only `EQUIP_E0` is still read, because the first beat of any
# draw is t=0 and naming it is worth a constant.
#
# They are kept rather than deleted for exactly one reason: `EQUIP_TOTAL` reads
# like "the length of the draw" and is not, and a file that no longer contains it
# cannot be grepped for a caller that still believes it. It had one —
# `tools/sword_basic_v2_movie.gd` documented its capture loop with
# "`DRAW_SECONDS` == `EQUIP_TOTAL` == 0.62s" for a build where the draw is 1.75 s.
const EQUIP_E0 := 0.00
const EQUIP_E1_RETIRED := 0.20
const EQUIP_E2_RETIRED := 0.42
const EQUIP_TOTAL_RETIRED := 0.62

# ===========================================================================
# SWORD PRESENTATION V3 · THE DRAW, IN FIVE BEATS
# ===========================================================================
#
# §2 says Sword and Saya are ONE WEAPON SYSTEM and that Equip / Inspect / A1 /
# A3 / Iaido / Weapon Switch share ONE draw-and-sheathe contract. §3 then says
# what the shared contract has to contain. This block is that contract, and the
# reason it replaced a four-key lerp is worth stating once.
#
# WHAT WAS WRONG WITH FOUR KEYS. E0→E3 was a chord through pose space: hilt at
# the mouth, let go, clear, stance. Every *position* on that path was on the
# straight line between its neighbours, and the two things a draw is actually
# watched for — the pause before the blade comes clear, and the moment the blade
# is READ rather than moved — had no way to exist, because a straight line has no
# opinions about time.
#
# WHAT THE MEASUREMENT ADDED. `tools/measure_saya_curve.gd` slices the shipping
# scabbard along its bore: the centreline leaves the mouth's own axis by **16.4 mm**
# over 0.79 m, monotonically toward +X. The blade's own centreline bows the same
# way by **13.1 mm** over its 0.69 m of blade. So the pair was made for each
# other, and the residual a straight extraction leaves inside the wall is about
# **3 mm** — small, but not zero, and not the reason this was rewritten.
#
# THE REASON THIS WAS REWRITTEN is that a 3 mm geometric error is invisible while
# a *rigidly translating assembly* is the most legible thing on screen: the player
# does not see a blade leaving a sheath, they see one object sliding. So the beats
# below are separated by WHAT THE OFF HAND IS DOING and by WHERE THE BLADE STOPS
# MOVING, and the bow on the extraction segment is carried at its measured value
# rather than rounded away.
#
# THE BEATS (§3):
#
#   t=0.00  the assembly is home at the left hip, blade along the saya's axis
#   t=0.35  Beat 1 — the off hand has brought it to the front, near-horizontal,
#           carried at a natural ~17° (the brief allows 15-30° and forbids 90°)
#   t=0.75  Beat 2 — 0.16 m of slow extraction. The blade is out but not read yet
#   t=0.95  the pause. 200 ms, inside §3's 120-250 ms, with the blade NOT moving
#   t=1.07  Beat 3 — the cold glint, 120 ms, inside §3's 80-160 ms. Still still.
#   t=1.40  Beat 4 — the rest of the extraction, faster, saya pushed the other way
#   t=1.75  Beat 5 — stance. Sword to the right, saya home to the left. Ready.
#
# 1.75 s is inside §3's 1.2-2.0 s band, and it is the number the whole five-beat
# structure costs; the old one was 0.62 s because 0.62 s was all a straight line
# could fill.
const NE_BRING := 0.35
const NE_DRAW_PARTIAL := 0.75
const NE_HOLD_END := 0.95
const NE_GLINT_END := 1.07
const NE_DRAW_FULL := 1.40
## Beat 5's own length, and it is Beat 1's on purpose.
##
## THE TURN TO GUARD IS 89°, AND IT CANNOT START UNTIL THE BLADE IS CLEAR. Beat 1
## turns the assembly the other way by 85° in 0.35 s — 254°/s — and when Beat 5
## had only the 0.20 s left over, the same size of turn went at 445°/s: the draw
## read as a slow lift followed by a hard snap, which is a discontinuity in the
## gesture and not in the geometry. Equal windows make it one speed.
##
## 1.75 s total is inside §3's 1.2-2.0 s band and it is the sum this structure
## costs; the alternative ways to pay for it are worse. Taking the time from the
## extraction would push it from 1.82 m/s to 2.6 m/s, which is the blade leaving
## the hand rather than leaving the sheath.
const NE_SETTLE := 0.35
const NE_TOTAL := NE_DRAW_FULL + NE_SETTLE

## THE INSTANT THE BLADE IS CLEAR OF THE MOUTH, as a fraction of the draw.
##
## This is Beat 4's own window boundary, and it is named here because a second
## system has to agree about it. `CombatController.pose_snapshot()` cross-fades
## this whole family into the style's idle pose, and a cross-fade is a pose that
## is PARTLY something else: at 54% of the way through a 1.75 s draw the blend was
## putting 54% of the idle pose into the blade, so the blade rendered at Beat 2's
## time was 0.44 m off its own beat and 0.32 m off the scabbard's bore — through
## the wall of a scabbard it was still inside.
##
## `tools/probe_draw_seating.gd` measured that: **0.93 m of transverse error and
## 89 degrees of axis error at the worst instant**, on a rig whose designed
## clearance is 1.75 mm. Seven green probes missed it because every one of them
## measured one actor, and the fault was in the relationship.
##
## So the handover may not begin until the blade is out, and this constant is the
## line. It is NOT tuned: it is Beat 4, and Beat 4 is where the blade clears the
## mouth because that is what Beat 4 is for.
const NE_BLADE_CLEAR := NE_DRAW_FULL / NE_TOTAL

## How far the blade is drawn at Beat 2, in metres. §3 asks for 12-20 cm; this is
## the middle of that band, and the *only* thing that makes Beat 3 legible — a
## glint needs a surface to run along, and at 0.16 m there is 160 mm of it.
const NE_PARTIAL_DRAW := 0.160

## The near-horizontal carry. §3: "整体接近横置，但不要绝对 90°，允许约 15-30° 自然倾角".
## Expressed as a DIRECTION rather than an euler triple, because "17 degrees above
## horizontal, pointing left" is what the brief actually specifies and a triple
## would have to be reverse-solved into it — and then re-solved every time it is
## retuned. `aim_euler` does the solving, once.
const NE_CARRY_DIR := Vector3(-0.956, 0.292, 0.030)   # 17.0° above horizontal
## Where the assembly is held once the off hand has brought it up. Forward and
## centred compared with the hip: §3's "带到身体前方".
const NE_CARRY_POS := Vector3(-0.335, -0.330, -0.900)
## R E T I R E D · `NE_WHEEL_DIR`
##
## There used to be a third blade direction here — between the carry (left, up)
## and the stance (forward), so that "the tip leads the hand round". It was
## RETIRED as a clip, not as a taste.
##
## It was Beat 4's own pose, which meant the blade turned 72.7° during the
## extraction while the saya turned 0.0° — the `aim` column of
## `tools/probe_saya_motion.gd`, measured segment by segment. A pose's rotation is
## applied about the blade's ORIGIN, which is the grip, and by Beat 4 the grip is
## already most of a metre behind the mouth; so the blade does not pivot in the
## mouth, it sweeps through it. At 0.16 m drawn, ten degrees of tilt puts a 30 mm
## blade through a 30 mm wall.
##
## The physical rule is simpler and stricter than the artistic one: while any of
## the blade is inside the bore, the blade's axis IS the bore's axis. So the
## extraction is a pure translation along `NE_CARRY_DIR` — which is what segment 2
## already was, and why segment 2 never looked wrong — and the entire turn happens
## in Beat 5, where the blade is clear and the wrist is free to take it to guard.
##
## Kept as a comment rather than deleted so the next person tuning the draw knows
## the direction was considered and why it cannot live where it was.
## How far the off hand pushes the saya the other way during Beat 4, in metres
## along the blade's own axis. §3: "左手 Saya 稍向反方向送". Small on purpose — this
## is a counterweight, not a shove, and past a few centimetres the saya stops
## reading as held and starts reading as thrown.
const SAYA_PUSH := 0.048

## The sword this sentence is authored against. One id, read by the registry, so
## the draw's own length is `blade_reach(WEAPON_ID)` rather than a typed number.
const WEAPON_ID := &"iaito"

## The sword-class registry, preloaded rather than named because it carries no
## `class_name` — it is read as a table, which is what it is.
const SwordClasses := preload("res://scripts/weapons/sword_classes.gd")


static func moves() -> Array[SwordMove]:
	return [a1(), a2(), a3(), a4()]


# ===========================================================================
# aim_euler · author a DIRECTION, let the arithmetic find the triple
# ===========================================================================
#
# Every pose in this file used to be a hand-typed euler triple, and the header
# above this function is the apology for that: "THE KEYS ARE AUTHORED IN CAMERA
# SPACE" is true, but a triple is not a direction, it is three angles whose
# product is a direction nobody can read. The draw's whole specification is
# directional — "近横置", "15-30° 倾角", "刀背靠鞘" — and none of those sentences can
# be written as a triple without first solving for one, which is a step where a
# number can be wrong and look fine.
#
# So this takes the sentence's own subject: where the blade's +Y points, and
# which way its spine faces. The basis is built from those two and the euler is
# whatever falls out. `Matrix` is right-handed (X cross Y = Z), which is the
# convention both GLBs are authored in, so a spine given as `Vector3.RIGHT`
# really is the spine for a sword whose edge faces -X.
static func aim_euler(y_dir: Vector3, spine: Vector3 = Vector3.RIGHT) -> Vector3:
	var y := y_dir.normalized()
	if y.length() < 0.5:
		y = Vector3.UP
	var x := spine - y * spine.dot(y)
	if x.length() < 0.0001:
		# Degenerate: the requested spine is parallel to the blade. Any
		# perpendicular will do, and picking it from the world up keeps the
		# result stable instead of returning NaN.
		x = Vector3.FORWARD - y * Vector3.FORWARD.dot(y)
		if x.length() < 0.0001:
			x = Vector3.RIGHT - y * Vector3.RIGHT.dot(y)
	x = x.normalized()
	var z := x.cross(y)
	return Basis(x, y, z).get_euler()


## Which way the blade's spine faces while the blade lies along `y_dir`.
##
## The saya's +X is defined as the side the edge lies against, and the sword's -X
## is the side its edge faces — so the spine (+X) of the two is the same axis, and
## "draw the spine along the mouth" means "bow the path toward +X". This returns
## that axis in camera space for a given blade direction, which is what converts
## the registry's measured `bore_sori` into a pose-space bow.
static func spine_axis(y_dir: Vector3) -> Vector3:
	var y := y_dir.normalized()
	# The carrier: any vector not parallel to the blade, chosen once and stably.
	var ref := Vector3.UP if absf(y.y) < 0.94 else Vector3.FORWARD
	var x := ref.cross(y)
	if x.length() < 0.0001:
		x = Vector3.FORWARD.cross(y)
	return x.normalized()


## A roll about the bore's own axis, as an euler triple.
##
## This is the ONLY rotation a scabbard may take while a blade is near its mouth,
## and that is a geometric fact rather than a stylistic one. Rolling about the
## bore changes which way the mouth's flat faces point without changing which way
## the bore points, so a blade inside keeps its axis and keeps its clearance. Any
## other five degrees is the mouth walking off the blade, and §8's "5-10 degrees"
## is a sentence about what a hand does to a scabbard — a hand rolls it.
static func bore_roll(angle: float) -> Vector3:
	return Basis(bore_axis(), angle).get_euler()


static func light_chain() -> Array[StringName]:
	return [A1, A2, A3, A4]


# ===========================================================================
# A1 — 小居合 · 右划
# ===========================================================================
# CLOSE. FAST. CLEAN.
#
# The blade goes back to the sheath mouth — not all the way home, just a touch —
# holds for a very short beat, and then comes out ACROSS the body to the right.
# The cut and the draw are the same motion; that is what makes it a small iaido
# rather than a diagonal slash that happens to start on the left.
#
# The pose never leaves the right side afterwards. Nothing here recentres, and
# that is deliberate: A2's wind-up IS A1's follow-through, so a re-take would
# make the second beat a second first beat.
static func a1() -> SwordMove:
	var move := SwordMove.new()
	move.id = A1
	move.display_name = "A1 · 试探横切"
	move.note = "Two-handed short right cut; stays drawn and carries into the return."
	move.startup = 0.13
	move.strike = 0.115
	move.follow_time = 0.095
	move.recovery = 0.23
	move.cancel_open = 0.28
	move.hit_recovery_scale = 0.84
	move.miss_recovery_scale = 1.18
	move.on_hit_next_startup_scale = 0.90
	move.damage = attack_value("attack_damage",0)
	move.poise_damage = 16.0
	move.hitstop = attack_value("hit_stop",0)
	move.anchor = READY
	move.anchor_rot = READY_R
	move.wind = Vector3(-0.18,-0.24,-0.64)
	move.wind_rot = aim_euler(Vector3(-0.85,0.38,-0.12))
	move.contact = Vector3(0.24,-0.30,-0.85)
	move.contact_rot = aim_euler(Vector3(0.94,0.15,-0.30))
	move.follow = Vector3(0.42,-0.32,-0.62)
	move.follow_rot = aim_euler(Vector3(0.90,-0.18,-0.36))
	move.recover = Vector3(0.34,-0.33,-0.68)
	move.recover_rot = aim_euler(Vector3(0.76,0.36,-0.27))
	move.anticipation_power = 1.5
	move.strike_power = 1.65
	move.follow_power = 1.4
	move.recovery_power = 1.5
	move.follow_overshoot = 0.10
	move.recover_sag = 0.015
	move.lunge = 0.12
	move.steer = 0.60
	move.camera_impulse = Vector2(0.005,0.001)
	move.camera_roll = -0.8
	move.fov_kick = -0.4
	move.reach_mode = &"body"
	move.hitbox_size = Vector3(2.3,1.25,1.5)
	move.hitbox_offset = Vector3(0,-0.22,-1.30)
	move.trail_width_scale = 0.62
	move.audio_cue = &"sword_feel_a1"
	move.events = [{"t":0.13,"id":EV_ACTIVE}]
	return move

static func a2() -> SwordMove:
	var move := SwordMove.new()
	move.id = A2
	move.display_name = "A2 · 回身左切"
	move.note = "Opposite shoulder carries the return, then releases the existing pressure wave."
	move.startup = 0.15
	move.strike = 0.14
	move.follow_time = 0.13
	move.recovery = 0.26
	move.cancel_open = 0.32
	move.hit_recovery_scale = 0.88
	move.miss_recovery_scale = 1.20
	move.damage = attack_value("attack_damage",1)
	move.poise_damage = 19.0
	move.hitstop = attack_value("hit_stop",1)
	move.anchor = a1().recover
	move.anchor_rot = a1().recover_rot
	move.wind = Vector3(0.46,-0.26,-0.61)
	move.wind_rot = aim_euler(Vector3(0.84,0.46,-0.15))
	move.contact = Vector3(-0.16,-0.28,-0.84)
	move.contact_rot = aim_euler(Vector3(-0.93,0.24,-0.26))
	move.follow = Vector3(-0.31,-0.37,-0.61)
	move.follow_rot = aim_euler(Vector3(-0.81,-0.22,-0.38))
	move.recover = Vector3(-0.12,-0.34,-0.67)
	move.recover_rot = aim_euler(Vector3(-0.55,0.55,-0.33))
	move.anticipation_power = 1.8
	move.strike_power = 1.65
	move.follow_power = 1.35
	move.recovery_power = 1.6
	move.follow_overshoot = 0.13
	move.recover_sag = 0.018
	move.lunge = 0.18
	move.steer = 0.48
	move.camera_impulse = Vector2(-0.006,0.001)
	move.camera_roll = 0.9
	move.fov_kick = -0.75
	move.reach_mode = &"wave"
	move.reach = 8.4
	move.reach_speed = 26.0
	move.hitbox_size = Vector3(2.3,1.4,1.6)
	move.hitbox_offset = Vector3(0,-0.20,-1.32)
	move.trail_width_scale = 1.05
	move.audio_cue = &"sword_wave_swing"
	move.events = [{"t":0.15,"id":EV_RELEASE},{"t":0.21,"id":EV_WAVE}]
	return move

static func a3() -> SwordMove:
	var move := SwordMove.new()
	move.id = A3
	move.display_name = "A3 · 沉身上挑"
	move.note = "Load below the hips, accelerate both hands upward, carry the blade before settling."
	move.startup = 0.20
	move.strike = 0.18
	move.follow_time = 0.15
	move.recovery = 0.28
	move.cancel_open = 0.43
	move.hit_recovery_scale = 0.92
	move.miss_recovery_scale = 1.22
	move.damage = attack_value("attack_damage",2)
	move.poise_damage = 26.0
	move.hitstop = attack_value("hit_stop",2)
	move.anchor = a2().recover
	move.anchor_rot = a2().recover_rot
	move.wind = Vector3(0.12,-0.60,-0.63)
	move.wind_rot = aim_euler(Vector3(-0.82,-0.38,-0.20))
	move.contact = Vector3(0.06,-0.08,-0.81)
	move.contact_rot = aim_euler(Vector3(0.13,0.84,-0.38))
	move.follow = Vector3(0.18,0.055,-0.63)
	move.follow_rot = aim_euler(Vector3(0.43,0.67,-0.34))
	move.recover = Vector3(0.24,-0.24,-0.66)
	move.recover_rot = aim_euler(Vector3(0.60,0.62,-0.20))
	move.anticipation_power = 1.6
	move.strike_power = 1.85
	move.follow_power = 1.35
	move.recovery_power = 1.5
	move.follow_overshoot = 0.12
	move.recover_sag = 0.025
	move.reach_mode = &"body"
	move.hitbox_size = Vector3(1.30,1.80,1.70)
	move.hitbox_offset = Vector3(0,-0.15,-1.45)
	move.lunge = 0.16
	move.steer = 0.35
	move.camera_impulse = Vector2(0,-0.005)
	move.camera_roll = 0.4
	move.fov_kick = -1.0
	move.trail_width_scale = 0.9
	move.audio_cue = &"sword_uppercut"
	return move

static func a4() -> SwordMove:
	var move := SwordMove.new()
	move.id = A4
	move.display_name = "A4 · 回身终结"
	move.note = "A committed shoulder coil, one major arc, counterweighted recovery."
	move.startup = 0.25
	move.strike = 0.28
	move.follow_time = 0.16
	move.recovery = 0.34
	move.cancel_open = 0.68
	move.hit_recovery_scale = 0.92
	move.miss_recovery_scale = 1.25
	move.damage = attack_value("attack_damage",3)
	move.poise_damage = 30.0
	move.hitstop = attack_value("hit_stop",3)
	move.anchor = a3().recover
	move.anchor_rot = a3().recover_rot
	move.wind = Vector3(-0.26,-0.13,-0.44)
	move.wind_rot = aim_euler(Vector3(-0.91,0.31,0.15))
	move.contact = Vector3(0.32,-0.28,-0.89)
	move.contact_rot = aim_euler(Vector3(0.91,0.10,-0.39))
	move.follow = Vector3(0.48,-0.43,-0.46)
	move.follow_rot = aim_euler(Vector3(0.72,-0.12,0.60))
	move.recover = READY
	move.recover_rot = READY_R
	move.anticipation_power = 1.8
	move.strike_power = 1.7
	move.follow_power = 1.4
	move.recovery_power = 1.8
	move.follow_overshoot = 0.16
	move.recover_sag = 0.03
	move.lunge = 0.20
	move.steer = 0.32
	move.camera_impulse = Vector2(0.007,0.002)
	move.camera_roll = -1.4
	move.fov_kick = -1.6
	move.reach_mode = &"arc"
	move.reach_radius = 4.2
	move.reach_arc_from = -140.0
	move.reach_arc_to = 130.0
	move.arc_slices = 6
	move.trail_width_scale = 1.45
	move.audio_cue = &"sword_arc_wide"
	move.events = [{"t":0.25,"id":EV_ARC_START},{"t":0.25,"id":EV_A4_ACTIVE},{"t":0.53,"id":EV_ARC_END}]
	return move


# ===========================================================================
# THE DRAW · E0 → E1 → E2 → E3 (§19 / §20)
# ===========================================================================
#
# §19 is the whole reason this exists: pressing `1` must not put a sword in the
# player's hand. It must be TAKEN OUT OF SOMETHING.
#
#   E0  the blade is home, the saya is at the left waist, the right hand is on
#       the hilt and the left hand is on the sheath. Nobody is attacking.
#   E1  the blade is coming out: the right hand travels and the left hand pushes
#       the mouth back — the two motions are opposite, which is what a draw IS.
#   E2  clear of the mouth. The saya does not disappear.
#   E3  the combat stance, with the saya STILL in the left hand. There is no
#       moment in this sentence where the off hand becomes empty, because the
#       moment it does the weapon has stopped being a sword and a sheath.
#
# Authored as a beat list and sampled by the same `SwordPoseSampler` the four
# cuts use, so the draw is not a special case in the renderer: it is a pose like
# any other, and the only thing that makes it a cutscene is that nothing can hit
# anybody during it (`damage = 0.0`, so the controller never opens a hitbox).
#
# The one number the controller owns is `equip_blend`; the WeaponManager moves it
# and everything downstream reads it. That is what makes `2 → 1` a DRAW rather
# than a visibility flag.
static var _equip_cache: SwordMove


static func equip() -> SwordMove:
	if _equip_cache != null:
		return _equip_cache
	var move := SwordMove.new()
	move.id = EQUIP
	move.display_name = "E · 拔刀 · NORMAL EQUIP"
	move.note = "Five beats: carry, partial draw, hold, cold glint, seat. The saya works too."
	# No four-phase shape: a draw is beats and has no contact window, so the whole
	# move is `startup` and the beat list is the timeline. `damage = 0.0` is what
	# keeps the controller from ever opening a hitbox during it.
	move.startup = NE_TOTAL
	move.strike = 0.0
	move.follow_time = 0.0
	move.recovery = 0.0
	move.damage = 0.0
	move.cancel_open = NE_BRING

	var carry_dir := NE_CARRY_DIR.normalized()
	# The direction the GRIP travels to leave the sheath. The blade's +Y runs from
	# the grip toward the tip and the tip is what is inside the saya, so extracting
	# means walking the origin the other way.
	var out_dir := -carry_dir
	var reach := SwordClasses.blade_reach(WEAPON_ID)
	var tsuba := SwordClasses.guard_setback(WEAPON_ID)

	var carry := NE_CARRY_POS
	var partial := carry + out_dir * NE_PARTIAL_DRAW
	var full := carry + out_dir * reach
	var carry_rot := aim_euler(carry_dir)

	# The depths this draw passes through, so the bow is READ off the registry's
	# measured curve instead of being a number somebody liked.
	var d_partial := 1.0 - NE_PARTIAL_DRAW / maxf(reach, 0.0001)

	move.beat_times = PackedFloat32Array([
		EQUIP_E0, NE_BRING, NE_DRAW_PARTIAL, NE_HOLD_END, NE_GLINT_END,
		NE_DRAW_FULL, NE_TOTAL,
	])
	move.beat_positions = PackedVector3Array([
		SAYA_MOUTH,      # t=0.00  home at the hip, blade along the saya's own axis
		carry,           # t=0.35  Beat 1 — up, forward, near-horizontal
		partial,         # t=0.75  Beat 2 — 160 mm out, and the blade STOPS
		partial,         # t=0.95  the pause. 200 ms with nothing moving.
		partial,         # t=1.07  Beat 3 — the glint runs and the blade is still
		full,            # t=1.40  Beat 4 — clear of the mouth at last
	RIGHT_SIDE,      # t=1.75  Beat 5 — stance, sword on the right
])
	# THE ROTATION IS HELD UNTIL THE BLADE IS CLEAR, AND THAT IS GEOMETRY.
	#
	# Beats 1 to 4 all carry the SAME axis, and that axis is the saya's own, so
	# the extraction is one straight slide down the bore. The turn to guard is
	# Beat 5's alone — 0.20 s in which the blade is out of the scabbard and the
	# wrist is free.
	#
	# It was not always so. Beat 4 used to aim somewhere between the carry and the
	# stance ("the tip leads the hand round"), and the cost was 72.7° of aim change
	# across the extraction while the saya changed by 0.0°: a blade shearing out
	# through the wall of its own scabbard for the second half of the draw. See
	# the retired `NE_WHEEL_DIR` above for the arithmetic.
	move.beat_rotations = PackedVector3Array([
		SAYA_MOUTH_R,    # the sheathed axis — the same anchor A1 and A3 use
		carry_rot,       # Beat 1's near-horizontal carry
		carry_rot,       # extraction is a translation along this axis, no turn
		carry_rot,
		carry_rot,
		carry_rot,       # Beat 4 — clear of the mouth, and STILL on the bore's axis
		COMBAT_STANCE_R, # Beat 5 — now the wrist takes it to guard
	])
	# THE BOW, per segment, in metres, off the registry's measured bore curve.
	# Segment 1 is the partial extraction and segment 4 is the rest of it; the
	# hold and the glint are deliberately zero because nothing moves in them, and
	# a bow on a segment whose endpoints are equal is a path that leaves and
	# comes back — motion invented to satisfy a rule rather than a hand.
	#
	# The axis is the blade's SPINE, which is the side a katana's sori bows
	# toward and therefore the side the extraction has to lean. See
	# `SwordClasses.bore_bow_between` for why this is millimetres rather than the
	# full 16.4 mm, and why that is the honest answer rather than a fudge.
	var spine := spine_axis(carry_dir)
	move.beat_bows = PackedVector3Array([
		Vector3.ZERO,
		spine * SwordClasses.bore_bow_between(WEAPON_ID, 1.0, d_partial),
		Vector3.ZERO,
		Vector3.ZERO,
		spine * SwordClasses.bore_bow_between(WEAPON_ID, d_partial, 0.0),
		Vector3.ZERO,
	])

	# --- the sheath's own five beats (§2: a second actor, not a prop) --------
	#
	# The mouth does NOT travel with the blade — that is the entire difference
	# between a draw and one object sliding. So the saya's mouth sits still for
	# the whole extraction, and the only two beats where it moves are the two the
	# brief names: it is brought up at Beat 1, and it is pushed the OTHER WAY at
	# Beat 4 while the blade comes out.
	var carry_mouth := carry + carry_dir * tsuba
	var push_mouth := carry_mouth + carry_dir * SAYA_PUSH
	# ...AND IT GOES HOME, WHICH IS NOT A POSE SOMEONE PICKED. The last beat is
	# `saya_home()` because that is where the rig puts the mouth the instant the
	# draw stops being choreographed, and a beat that ends anywhere else makes
	# that instant a teleport. It was `SAYA_MOUTH + (-0.045, -0.105, 0.070)` — a
	# point chosen by eye for how it composed — and the measured cost was a
	# 128.9 mm jump in one update on every switch-out, plus a 0.227 m final
	# segment at 1.14 m/s (the fastest thing the sheath does all draw) that
	# existed only to reach it.
	move.saya_positions = PackedVector3Array([
		saya_home(),     # t=0.00  home, and the same point beat 0 of the blade names
		carry_mouth,     # Beat 1 — the off hand brings it up
		carry_mouth,     # and then it is HELD, which is what a scabbard is for
		carry_mouth,
		carry_mouth,
		push_mouth,      # Beat 4 — pushed back against the blade's travel
		saya_home(),     # Beat 5 — the hand relaxes and the mouth goes home
	])
	move.saya_rotations = PackedVector3Array([
		SAYA_MOUTH_R, carry_rot, carry_rot, carry_rot, carry_rot, carry_rot,
		SAYA_MOUTH_R,
	])

	move.trail_width_scale = 0.42
	move.audio_cue = &"sword_iaido_draw"
	move.events = [
		{"t": EQUIP_E0, "id": EV_SHEATH_TOUCH},
		{"t": NE_BRING, "id": EV_EQUIP_CARRY},
		{"t": NE_DRAW_PARTIAL, "id": EV_DRAW},
		{"t": NE_HOLD_END, "id": EV_EQUIP_GLINT},
		{"t": NE_GLINT_END, "id": EV_SAYA_PUSH},
		{"t": NE_DRAW_FULL, "id": EV_EQUIP_SEAT},
	]
	_equip_cache = move
	return move


# ===========================================================================
# The saya's own participation, per beat
# ===========================================================================
#
# §21: the left-hand scabbard is not decoration. At least equip, A1, A3 and the
# switch-out have to move it, and if the off hand is doing nothing the shot says
# so more clearly than any amount of authoring can hide.
#
# Returns 0..1 for "how hard the off hand is working this frame". It is a
# function of the move and the move's own clock, so it is as deterministic as
# the pose it accompanies.
static func saya_pull(move: SwordMove, t: float) -> float:
	if move == null:
		return 0.0
	match move.id:
		A1:
			# The hand pulls the mouth BACK and slightly away as the blade leaves.
			# Opposite motion is what makes it read as a sheath being held rather
			# than a box that happens to be nearby.
			if t < move.startup:
				return 0.35
			var draw := clampf((t - move.startup) / maxf(move.strike, 0.0001), 0.0, 1.0)
			return 0.35 + 0.55 * sin(draw * PI)
		A3:
			# Brace the offhand during the low load, then release as the blade rises.
			return 0.25 * (1.0 - clampf((t-move.startup)/maxf(move.strike+move.follow_time,0.001),0,1))
		A2:
			return 0.25
		A4:
			# The off hand comes across the body to counterbalance the sweep.
			return 0.30 * clampf(t / maxf(move.total_time(), 0.0001), 0.0, 1.0)
		EQUIP:
			# §2's ONE WEAPON SYSTEM, expressed as the off hand's own curve.
			#
			# The draw is the one move where the sheath is doing as much as the
			# blade, and the shape of that work is: nothing (the assembly is
			# already in the hand) → a lift → a long steady hold against a blade
			# being pulled out of it → a push the other way → release.
			#
			# The hold is the part that matters. Between Beat 2 and Beat 4 the
			# blade is moving and the saya must NOT be, so the off hand's exertion
			# is at its highest and its displacement is zero — which is exactly the
			# thing a single `equip_blend` scalar could not say, and the reason
			# §3's pause reads as a pause instead of as a slowdown.
			if t < NE_BRING:
				return 0.55 * clampf(t / maxf(NE_BRING, 0.0001), 0.0, 1.0)
			if t < NE_DRAW_PARTIAL:
				return 0.70
			if t < NE_GLINT_END:
				return 0.85
			if t < NE_DRAW_FULL:
				return 0.95
			return maxf(0.0, 0.95 * (1.0 - (t - NE_DRAW_FULL)
				/ maxf(NE_TOTAL - NE_DRAW_FULL, 0.0001)))
	return 0.0


# ===========================================================================
# §23 / §25 · what an event means to the ears
# ===========================================================================
#
# The mapping lives with the vocabulary rather than in the listener, because the
# vocabulary is what would change if a beat were re-authored: a new event with no
# sound should be a one-line omission here, not a silent branch inside a VFX node.
# An empty answer is the honest one for an event that is only a visual beat —
# A1_ACTIVE is the blade leaving the sheath, which the draw has already said.

## Which sound an event asks for, or &"" if the event is not audible.
static func audio_for_event(event_id: StringName) -> StringName:
	match event_id:
		EV_SHEATH_TOUCH:
			return AU_SAYA_TOUCH
		EV_A3_SHEATHE:
			return AU_SAYA_TOUCH
		EV_DRAW:
			return AU_DRAW
		EV_WAVE:
			return AU_WAVE
		EV_CUT_1:
			return AU_SPACE_CUT_1
		EV_CUT_2:
			return AU_SPACE_CUT_2
		EV_CUT_3:
			return AU_SPACE_CUT_3
		EV_ARC_START:
			return AU_ARC
	return &""


## The events that describe a beat ENDING rather than an instant inside it.
##
## A cut cancelled before it happened has no cut to report, so the three space
## cuts are never invented for a move that was interrupted. A beat's own close is
## different: if a style shortened the recovery enough that the authored instant
## fell past the end, the move still finished, and saying so one frame late is
## true while saying nothing at all is not.
static func is_closing_event(event_id: StringName) -> bool:
	return event_id in [EV_FINISH, EV_A2_FINISH, EV_DOMAIN_END, EV_ARC_END]


## The move's events, in order. Kept as a function so a caller never has to sort
## the author's list itself — an out-of-order event in data should not be able to
## silently arrive before the one that caused it.
static func events_of(move: SwordMove) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if move == null:
		return out
	for entry in move.events:
		out.append(entry)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["t"]) < float(b["t"])
	)
	return out
