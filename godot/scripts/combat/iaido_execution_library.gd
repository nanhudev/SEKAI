extends RefCounted
class_name IaidoExecutionLibrary

# WHAT EACH MATERIAL DOES WHEN IT IS CUT.
#
# §8 of the execution brief asks for one rule (一切被居合斩开的断面都是同一套规则)
# and a different face per material. The rule is the shape of the cut — a plane,
# a cross-section, a pale lip, a dark interior, no gore. The face is a table,
# and the table is here, in ONE place, so "构造体和生物断面的区别" is a row in a
# table rather than a branch in three systems.
#
# No colour in this table is blood. A stylized RPG that shows an anime-style
# horizontal cross-section in red has chosen gore, and the design explicitly did
# not: 不要默认写实 gore.
#
# THE TABLE IS AUTHORITATIVE AND THE PROFILES DO NOT REPEAT IT.
#
# An enemy declares `cut_material = &"ice"` and nothing else; the runtime stamps
# the four numbers from here when it attaches. A profile that also carried its
# own copy of the colours would be a second source of truth for the same fact,
# and the two would drift the first time either was edited.

## The cross-section, per material family.
##
##   interior_color   the cut face itself. Dark, desaturated, NOT red.
##   rim_color        the pale line at the lip of the cut — the only bright thing
##                    the cut is allowed to have, and it must stay thin.
##   rim              how much of the surface near the cut becomes the lip.
##   band_m           how wide the band of changed material is, at a 1m body.
##                    Scaled by the body's own size at runtime, so a three-metre
##                    construct does not get a one-metre-tall hairline.
##   core_emission    light trapped INSIDE the body, visible only once it is open.
##                    This is what makes a construct read as a machine and not as
##                    a rock: it had something running inside it.
##   core_color       that light's colour.
##   debris_color     the chips thrown off the cut.
const SURFACES := {
	&"construct": {
		"interior_color": Color(0.135, 0.128, 0.125),
		"rim_color": Color(0.855, 0.815, 0.720),
		"rim": 0.46,
		"band_m": 0.040,
		"core_emission": 0.55,
		"core_color": Color(0.320, 0.800, 0.940),
		"debris_color": Color(0.600, 0.575, 0.535),
	},
	&"biological": {
		"interior_color": Color(0.115, 0.085, 0.090),
		"rim_color": Color(0.740, 0.660, 0.630),
		"rim": 0.28,
		"band_m": 0.030,
		"core_emission": 0.0,
		"core_color": Color(0.0, 0.0, 0.0),
		"debris_color": Color(0.500, 0.420, 0.400),
	},
	&"ice": {
		"interior_color": Color(0.280, 0.420, 0.500),
		"rim_color": Color(0.820, 0.920, 1.000),
		"rim": 0.60,
		"band_m": 0.035,
		"core_emission": 0.20,
		"core_color": Color(0.600, 0.880, 1.000),
		"debris_color": Color(0.720, 0.860, 0.940),
	},
	&"plant": {
		"interior_color": Color(0.180, 0.150, 0.100),
		"rim_color": Color(0.700, 0.640, 0.470),
		"rim": 0.32,
		"band_m": 0.026,
		"core_emission": 0.10,
		"core_color": Color(0.520, 0.720, 0.400),
		"debris_color": Color(0.480, 0.430, 0.320),
	},
	&"generic": {
		"interior_color": Color(0.160, 0.150, 0.140),
		"rim_color": Color(0.820, 0.780, 0.700),
		"rim": 0.42,
		"band_m": 0.045,
		"core_emission": 0.0,
		"core_color": Color(0.0, 0.0, 0.0),
		"debris_color": Color(0.550, 0.520, 0.480),
	},
}

const PRESET_DIR := "res://resources/execution/"
const PRESETS := {
	&"construct_sentinel": "construct_sentinel.tres",
	&"biological_placeholder": "biological_placeholder.tres",
	&"heavy_construct": "heavy_construct.tres",
	&"ruin_warden": "ruin_warden.tres",
	&"unanchored_placeholder": "unanchored_placeholder.tres",
}


## The cross-section for one material family, falling back rather than failing:
## a typo in `cut_material` must not leave an enemy with an unshaded cut.
static func surface(material_class: StringName) -> Dictionary:
	var entry: Variant = SURFACES.get(material_class)
	if entry == null:
		entry = SURFACES[IaidoExecutionProfile.MATERIAL_GENERIC]
	return entry


## Stamp the table onto a profile. Called once, when an execution attaches.
static func apply_material(profile: IaidoExecutionProfile) -> void:
	if profile == null:
		return
	var entry := surface(profile.cut_material)
	profile.interior_color = entry["interior_color"]
	profile.rim_color = entry["rim_color"]
	profile.interior_rim = entry["rim"]
	profile.interior_band_m = entry["band_m"]
	profile.core_emission = entry["core_emission"]
	profile.core_color = entry["core_color"]
	profile.debris_color = entry["debris_color"]


## A profile by name, with its material table applied. Handed out as a COPY: the
## .tres on disk is shared, and a debug button that mutated it would retune every
## construct in the game from a panel press.
static func preset(id: StringName) -> IaidoExecutionProfile:
	var file: String = PRESETS.get(id, "")
	if file == "":
		return construct()
	var loaded: Resource = load(PRESET_DIR + file)
	if loaded == null or not (loaded is IaidoExecutionProfile):
		return construct()
	var profile: IaidoExecutionProfile = (loaded as IaidoExecutionProfile).duplicate(true)
	apply_material(profile)
	return profile


static func construct() -> IaidoExecutionProfile:
	return preset(&"construct_sentinel")


static func biological() -> IaidoExecutionProfile:
	return preset(&"biological_placeholder")


static func heavy() -> IaidoExecutionProfile:
	return preset(&"heavy_construct")


static func boss() -> IaidoExecutionProfile:
	return preset(&"ruin_warden")


static func unanchored() -> IaidoExecutionProfile:
	return preset(&"unanchored_placeholder")


## The generic placeholder: an enemy with no authored split geometry and no
## opinion about its material gets a clean, legible, non-gory cut and comes apart
## along it. §9 of the brief: this is what keeps every enemy in the game
## answerable to the signature before ART has answered for any of them.
static func fallback() -> IaidoExecutionProfile:
	var profile := unanchored()
	profile.execution_type = IaidoExecutionProfile.TYPE_CLEAVE
	profile.fallback_execution = IaidoExecutionProfile.TYPE_DISSOLVE
	return profile


## An enemy that may never be cut: it still has to answer the contract, and its
## answer is "no". Used by the test that proves a non-iaido kill does not enter
## the execution path.
static func none() -> IaidoExecutionProfile:
	var profile := construct()
	profile.iaido_execution_supported = false
	profile.execution_type = IaidoExecutionProfile.TYPE_NONE
	return profile
