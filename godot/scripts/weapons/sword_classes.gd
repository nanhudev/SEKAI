extends Node
## THE SWORD-CLASS REGISTRY.  One row per sword, and every number in a row is
## MEASURED off that sword's own GLB -- never typed in from a document.
##
## WHY THIS FILE EXISTS AT ALL
## A sword is not one file.  It is a model, a scabbard, two anchors and a
## judgement volume, and they have to agree about where the tip is, where the
## tsuba is, which way the edge faces and how long the blade runs.  Today those
## numbers are scattered: the model's axis lived in a scene-header comment, the
## seating constants live in IaidoTuning, the mouth is an anchor on the Player,
## and the hitbox is a 1.4 x 1.2 x 1.6 m box that no sword has ever been
## measured against.  The result is that changing the model changes the sword
## while leaving five other things asserting the old one -- which is exactly what
## "换建模不影响位置和技能效果" is asking to stop.
##
## So: one table, derived from the assets, and everything else reads it.
##
## ==========================================================================
## THE FRAME, AND WHY IT IS THIS ONE
## ==========================================================================
## Both the sword and its saya are authored so that, in Godot:
##
##   sword   origin  = the grip centre (where the hand is)
##           +Y      = toward the TIP
##           -X      = the side the cutting edge faces
##           +/-Z    = the flat of the blade
##
##   saya    origin  = the centre of the koiguchi mouth plane
##           +Y      = down the bore, mouth -> kojiri
##           -X      = the side the edge lies against
##           +Z      = the kurikata side
##
## They are the SAME frame, and that is deliberate.  It makes "fully sheathed" a
## pure translation of `tsuba_mouth_y` along +Y instead of a rotation hunt, and
## it means the Iaido director can seat the sword by handing it the scabbard's
## own basis (see iaido_director.gd:_bore_pose).  It is also the convention
## scenes/weapons/Sword_FP.tscn has documented since before either real asset
## existed -- the two GLBs that shipped before were both authored with the blade
## on -Z, which is why the ceremony seated them at ninety degrees to their own
## sheath and why the scene comment was recorded as "wrong" in
## docs/ASSET_MANIFEST.md.  The comment was right.  The files were wrong.
##
## ==========================================================================
## WHAT THESE NUMBERS ARE FOR
## ==========================================================================
##   blade_tip_y, tsuba_mouth_y   -> the seating constants the Iaido director
##                                   needs: guard_setback and blade_reach
##   habaki_*                     -> the saya's mouth bore, with clearance
##   blade_*_base / _tip          -> the saya's taper, and the blade hitbox
##   saya_*                       -> the scabbard's own build dimensions
##   guard_*                      -> the hitbox's start, and the free-tip length
##
## Re-derive with:
##   cmd //c "G:\blender.exe --background --factory-startup \
##     --python F:\SEKAI\tools\blender\sword_build.py -- <blend> <glb>"
##   cmd //c "G:\blender.exe --background --factory-startup \
##     --python F:\SEKAI\tools\blender\saya_build.py  -- <blend> <glb>"
##   and the per-part bound boxes both tools print.
##
## `godot/tools/shot_weapon_rack.gd` prints the LIVE world AABB of whatever the
## training ground is actually holding, so a registry that has drifted from the
## installed asset is caught by a number rather than by a reviewer's memory.

## Clearance per side between the habaki and the saya's bore.  1.75 mm is a fit
## you can feel and cannot see: at the 0.3-1 m first-person distance PART I calls
## the highest bar, a 1.75 mm gap is about a pixel.
const FIT_CLEAR := 0.00175
## Steel the saya's wall is left at.  Under 2 mm and a lacquered wooden shell
## reads as a plastic sleeve; over 4 mm and the mouth stops looking like a hole
## and starts looking like a bucket.
const SAYA_WALL := 0.0032
## How far past the tip the bore continues.  Not slack -- a saya whose tip
## touches its kojiri wears a hole through it.
const SAYA_TIP_CLEAR := 0.022
## How far the judgement volume is fattened past the blade's real section.  A
## blade is 8 mm thick and 36.5 mm wide; a hitbox that exact is unhittable at
## 60 fps.  These are the smallest numbers that stay honest about the shape.
const HITBOX_FATTEN_THICK := 0.007
const HITBOX_FATTEN_WIDTH := 0.010

## The registry.  Keys are weapon ids -- the same ids `WeaponSlot` uses, so
## `WeaponSlot.kind` is the lookup.
const CLASSES := {
	&"iaito": {
		"display_name": "剑 · SWORD",
		"model": "res://models/weapons/fp_sword.glb",
		"scabbard": "res://models/weapons/fp_saya.glb",
		# --- the blade, along +Y from the grip origin -------------------
		"tip_y": 0.7650,          # where the blade ends
		"tsuba_mouth_y": 0.0042,  # the tsuba face that meets the koiguchi
		"guard_face_y": -0.0030,  # the tsuba face toward the pommel
		"habaki_end_y": 0.0375,   # where the habaki stops and bare blade starts
		"grip_end_y": -0.2680,
		"kashira_y": -0.2860,
		# --- sections, as half extents --------------------------------
		"blade_half_w_base": 0.01825,
		"blade_half_w_tip": 0.01450,
		"blade_half_t_base": 0.00400,
		"blade_half_t_tip": 0.00290,
		"habaki_half_w": 0.02000,   # edge-to-spine, the widest thing going in
		"habaki_half_t": 0.00510,
		"guard_half_w": 0.03885,
		"guard_half_t": 0.03480,
		"guard_half_y": 0.00300,
		# --- the saya, whose origin IS the mouth plane ----------------
		"bore_len": 0.790,
		"body_len": 0.803,
		"taper": 0.855,
		"tri_count": 8810,
	},
}

const DEFAULT_ID := &"iaito"


static func has(id: StringName) -> bool:
	return CLASSES.has(id)


static func get_class_def(id: StringName) -> Dictionary:
	return CLASSES[id] if CLASSES.has(id) else CLASSES[DEFAULT_ID]


static func ids() -> Array:
	return CLASSES.keys()


# ---------------------------------------------------------------------------
#  the seating constants the Iaido ceremony runs on
# ---------------------------------------------------------------------------

## Distance from the sword's origin to the tsuba's mouth-side face.
##
## `iaido_director.gd:_bore_pose()` places the sword at
## `seat_origin - seat_basis.y * (guard_setback + (1 - depth) * blade_reach)`,
## and the contract is "fully seated = tsuba against the mouth".  So this has to
## be the measured tsuba face, not a remembered one.  IaidoTuning ships 0.045,
## which is this number for a sword whose tsuba sits 45 mm up its own origin --
## 41 mm in front of where this one's does.  For this asset the tsuba is 4.2 mm
## in FRONT of the grip centre, so a ceremony run on 0.045 leaves the habaki and
## 41 mm of blade root hanging outside the mouth.
static func guard_setback(id: StringName) -> float:
	return float(get_class_def(id)["tsuba_mouth_y"])


## Axial travel of the sword origin between fully seated and fully drawn: the
## distance from the origin to the tip.  IaidoTuning ships 0.95, i.e. it expects
## a 950 mm blade; this one is 765 mm, so the draw would finish 189 mm short of
## clearing its own sheath.
static func blade_reach(id: StringName) -> float:
	var d := get_class_def(id)
	return float(d["tip_y"]) - float(d["tsuba_mouth_y"])


## The distance from the sword's ORIGIN to its tip, which is where the tip is
## drawn from and therefore what a trail, a glint band or a void rim has to be
## sized against.
##
## NOT the same number as `blade_reach`, and the difference is the whole point:
## `blade_reach` is a SEATING measurement (tsuba face -> tip, 0.7608 m) because
## the ceremony is about the mouth; this is a RENDERING measurement (origin ->
## tip, 0.7650 m) because a trail is about the mesh.  They differ by
## `tsuba_mouth_y` -- 4.2 mm here, i.e. nothing, but they are not the same
## quantity and a weapon whose guard sits further up its own origin would make
## the difference visible.
##
## The first-person driver used to hard-code `BLADE_LENGTH := 0.95`, which is
## 185 mm of trail drawn past a tip that stops at 0.765 -- red and pale
## geometry in the air in front of the blade.
static func visual_length(id: StringName) -> float:
	return float(get_class_def(id)["tip_y"])


# ---------------------------------------------------------------------------
#  the model paths
# ---------------------------------------------------------------------------

## The sword model.  Read from the row rather than typed at the call site so the
## driver and the registry cannot disagree about which file is the sword.
static func model_path(id: StringName) -> String:
	return String(get_class_def(id)["model"])


static func scabbard_path(id: StringName) -> String:
	return String(get_class_def(id)["scabbard"])


## True when the row's own files are actually present.  A registry that names a
## GLB which is not on disk is a worse failure than no registry at all: the swap
## would half-apply and leave the placeholder hidden with nothing in its place.
## So the driver asks this first and falls back whole.
static func assets_present(id: StringName) -> bool:
	var d := get_class_def(id)
	return ResourceLoader.exists(String(d["model"])) \
		and ResourceLoader.exists(String(d["scabbard"]))


## Where the sword origin sits, along the bore, at a given seating depth.
## 1.0 = tsuba on the mouth, 0.0 = tip exactly at the mouth.  Mirrors
## `iaido_director.gd` so a test can assert the two agree without running the
## ceremony.
static func bore_back(id: StringName, depth: float) -> float:
	return guard_setback(id) + (1.0 - clampf(depth, 0.0, 1.0)) * blade_reach(id)


# ---------------------------------------------------------------------------
#  the saya, derived from the sword
# ---------------------------------------------------------------------------

## The saya's bore at the mouth, as a full size.  Derived from the habaki,
## because the habaki is the widest thing that has to pass it -- a saya sized
## off the blade instead leaves the habaki jamming.
static func saya_mouth_bore(id: StringName) -> Vector2:
	var d := get_class_def(id)
	return Vector2(float(d["habaki_half_w"]) * 2.0 + 2.0 * FIT_CLEAR,
		float(d["habaki_half_t"]) * 2.0 + 2.0 * FIT_CLEAR)


## The saya's outside at the mouth, as a full size.
static func saya_mouth_outer(id: StringName) -> Vector2:
	return saya_mouth_bore(id) + Vector2(SAYA_WALL, SAYA_WALL) * 2.0


## How deep the bore has to be: from the mouth to the tip when seated, plus the
## tip clearance.  Notably NOT a constant -- a 950 mm blade needs a 950 mm bore.
static func saya_bore_len(id: StringName) -> float:
	return float(get_class_def(id)["bore_len"])


static func saya_body_len(id: StringName) -> float:
	return float(get_class_def(id)["body_len"])


## Minimum bore length arithmetic, exposed so a new sword's row can be checked
## rather than guessed: seated tip position + clearance.
static func saya_bore_len_required(id: StringName) -> float:
	return blade_reach(id) + SAYA_TIP_CLEAR


# ---------------------------------------------------------------------------
#  the blade's judgement volume
# ---------------------------------------------------------------------------

## The blade's OWN volume, in the model's local frame.
##
## THIS IS NOT `WeaponRoot/SwordHitbox`.  That node is a BoxShape3D of
## 1.4 x 1.2 x 1.6 m sitting 1.4 m in front of the player, parented to the
## camera rig: it is a SWING VOLUME, a deliberate area-of-effect that a cut
## sweeps through, and it is owned by COMBAT.  It has never been measured against
## any sword, which is why it cannot go wrong when the sword changes -- and also
## why it cannot tell the truth about where the blade was.
##
## This function answers a different question: if a judgement needs the blade
## itself, where is it and how big is it.  A transform built from it can be
## parented to the model, and then it follows every swing for free, for any
## sword, with no authored numbers per style.
static func blade_volume_xform(id: StringName) -> Transform3D:
	var d := get_class_def(id)
	var y0 := float(d["tsuba_mouth_y"])
	var y1 := float(d["tip_y"])
	# The blade's centreline drifts toward the spine as it goes out (the sori),
	# so the volume is centred on the mid-length section rather than on y = 0.
	var mid_y := (y0 + y1) * 0.5
	return Transform3D(Basis(), Vector3(0.0, mid_y, 0.0))


static func blade_volume_size(id: StringName) -> Vector3:
	var d := get_class_def(id)
	var y0 := float(d["tsuba_mouth_y"])
	var y1 := float(d["tip_y"])
	var half_w := maxf(float(d["blade_half_w_base"]), float(d["blade_half_w_tip"])) \
		+ HITBOX_FATTEN_WIDTH
	var half_t := maxf(float(d["blade_half_t_base"]), float(d["blade_half_t_tip"])) \
		+ HITBOX_FATTEN_THICK
	return Vector3(half_w * 2.0, y1 - y0, half_t * 2.0)


## A BoxShape3D sized to the blade.  Returned as a fresh resource every call
## because a shape shared between two Area3Ds is a bug waiting to happen.
static func make_blade_shape(id: StringName) -> BoxShape3D:
	var s := BoxShape3D.new()
	s.size = blade_volume_size(id)
	return s


# ---------------------------------------------------------------------------
#  the scabbard anchors
# ---------------------------------------------------------------------------

## Where the koiguchi sits, in the SWORD's own frame, when fully sheathed.
##
## The sword's origin parked at -tsuba_mouth_y along +Y puts the tsuba's face on
## the mouth plane, so this is where a saya has to be if it is a child of the
## sword.  Equivalently: a saya whose own transform is identity IS the sheathed
## pose, which is what makes the swap safe -- nothing has to be re-posed.
static func saya_in_sword_frame(id: StringName) -> Transform3D:
	return Transform3D(Basis(), Vector3(0.0, guard_setback(id), 0.0))


## The blade still outside the saya at a given depth, in metres.  This is the
## number §8's "draw clearance" is really about.
static func exposed_blade(id: StringName, depth: float) -> float:
	return maxf(0.0, (1.0 - clampf(depth, 0.0, 1.0)) * blade_reach(id))
