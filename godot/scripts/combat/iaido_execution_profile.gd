extends Resource
class_name IaidoExecutionProfile

# THE ENEMY ART / TECH CONTRACT.
#
# From this pass on, every production enemy has to answer one question: what
# happens to THIS body when the signature actually kills it. Not "what death
# animation does it have" — 聚合斩 must not fall back to a normal death, because
# a skill that splits the world and then leaves the enemy to a generic collapse
# reads as two unrelated events. The一刀 has to be the thing that killed it.
#
# The reason this is a Resource and not a dictionary in the enemy's script: the
# answer is not gameplay, it is MATERIAL. What a cut cross-section looks like is
# an art decision (stone versus flesh versus ice), it arrives with the model, and
# it has to be editable by whoever makes the model without touching code.
#
# There is deliberately NO runtime mesh slicing anywhere in this system. Splitting
# an arbitrary skinned mesh at runtime means a boolean per enemy per swing, and
# the performance story for that is a flat no. What a production enemy ships is
# TWO meshes authored to sit on top of each other, or — until ART gets to it —
# the generic clip-plane cut, which needs no per-enemy work at all.

## Which body of behaviour this enemy gets. See `IaidoExecution`.
const TYPE_CLEAVE := &"cleave"      # two solid halves, gravity, they fall
const TYPE_DISSOLVE := &"dissolve"  # the halves stay and come apart along the cut
const TYPE_SPECIAL := &"special"    # authored response: armour splits, core is cut
const TYPE_NONE := &"none"          # no execution; the enemy just dies

## The material families a cross-section can belong to. Every one of these is a
## DIFFERENT thing to look at, and none of them is blood by default.
const MATERIAL_CONSTRUCT := &"construct"
const MATERIAL_BIOLOGICAL := &"biological"
const MATERIAL_ICE := &"ice"
const MATERIAL_PLANT := &"plant"
const MATERIAL_GENERIC := &"generic"

# ---------------------------------------------------------------- the contract

## 1 · Can the signature execute this body at all?
@export var iaido_execution_supported := true
## 2 · cleave / dissolve / special / none. See TYPE_*.
@export var execution_type: StringName = TYPE_CLEAVE
## 3 · Which part of the body may be cut: `full`, `upper`, `core`.
@export var cuttable_region: StringName = &"full"
## 4 · What to do when the runtime finds nothing it can cut — a body whose only
## geometry is a collision proxy, which this project has shipped before. Same
## vocabulary as `execution_type`.
@export var fallback_execution: StringName = TYPE_DISSOLVE

# ---------------------------------------------------------------- who it is

@export var enemy_id: StringName = &""
## A boss may be executed without being cut in half. The response is authored in
## `special_response`; the vocabulary is shared so AUDIO and VFX can branch on it
## without asking what the enemy is called.
@export var special_response: StringName = &""
@export var death_vfx: StringName = &""

# ---------------------------------------------------------------- the cut

## Where the cut is allowed to be, as a fraction of the body height. Used to
## place the topple anchor on the cut plane — never to move the plane itself.
## The plane is the one physical fact and an enemy does not get to re-author it.
@export var preferred_cut_height := 0.55
## The cross-section, by material family. These four numbers are the whole of
## "each material fails differently": the interior colour, the pale rim at the
## lip of the cut, how much light is trapped behind it, and how wide the band of
## changed material is.
@export var cut_material: StringName = MATERIAL_CONSTRUCT
@export var interior_color := Color(0.16, 0.15, 0.14)
@export var rim_color := Color(0.82, 0.78, 0.70)
@export var interior_rim := 0.42
@export var interior_band_m := 0.045
@export var core_emission := 0.0
@export var core_color := Color(0.32, 0.80, 0.94)
@export var debris_color := Color(0.55, 0.52, 0.48)

# ---------------------------------------------------------------- the release

## Two meshes that are each half of the body, authored to sit on top of each
## other at the enemy's origin. `[0]` is the positive side of the plane, `[1]`
## the negative side. Empty means "use the clip-plane cut".
@export var split_variants: Array[PackedScene] = []
## The trace: how long the body stays whole after the cut, then how long the
## hairline takes to become legible.
@export var trace_delay := 0.10
@export var trace_fade := 0.12
## The 1-3cm misalignment that says "it is already dead, it just has not fallen".
@export var align_start := 0.22
@export var align_end := 0.60
@export var hold_separation_m := 0.022
## Small inherited velocity, then gravity. Deliberately NOT a cannon: the design
## word is 失去支撑, loss of structural support, and a piece thrown across the
## room is a different event.
@export var release_force := 0.34
@export var gravity_scale := 1.0
@export var fall_spread := 0.30
@export var tip_angle_deg := 26.0
@export var spin_deg_per_s := 34.0
## The two halves do not fall together. This is the delay between them.
@export var fall_asymmetry := 0.07
## How long the fall itself runs before the piece is parked and dissolved away.
##
## THIS IS BUDGETED, NOT CHOSEN. The release is the final sheath click and the
## restoration of reality is 0.75s after it, so fall + fade + the widest target
## spread has to fit inside that window — otherwise a body is still coming apart
## while the world is being put back together, which is the one thing that would
## make the whole beat look like two effects. `iaido_execution_integration.gd`
## asserts the budget against the real timeline.
@export var fall_duration := 0.45
@export var fade_duration := 0.18
## How long the piece is allowed to exist after the release at the outside. This
## is the FAIL-SAFE margin: nothing may be left standing or lying about because a
## beat was skipped. See `IaidoExecution.lifetime_end()`.
@export var extra_lifetime := 0.12
@export var debris_count := 7
@export var debris_speed := 0.55


func is_supported() -> bool:
	if not iaido_execution_supported:
		return false
	return execution_type != TYPE_NONE


## The behaviour this profile actually resolves to, given whether the runtime
## found anything it can cut. Kept in one place so the director, the runtime and
## the test all answer "what will this enemy do" identically.
##
## NOTE WHAT IS *NOT* A REASON TO FALL BACK. Missing authored split meshes used to
## be, and that would have made the fallback the only path that ever ran: ART has
## not made a single split mesh yet, so every enemy in the game would have taken
## the placeholder route and the real two-part cleave would have been dead code.
## The clip-plane cut needs no per-enemy authoring, so a body with geometry gets
## the real thing today; `fallback_execution` is reserved for a body with no
## geometry at all.
func resolve_mode(has_cuttable_geometry: bool) -> StringName:
	if not is_supported():
		return TYPE_NONE
	if execution_type == TYPE_SPECIAL:
		return TYPE_SPECIAL
	if not has_cuttable_geometry:
		return fallback_execution
	return execution_type


## A copy with one field moved, for the debug panel and the lab. `set()` on an
## exported Resource mutates the loaded .tres, which is how a debug button
## silently retunes every enemy in the game.
func tuned(key: String, value: Variant) -> IaidoExecutionProfile:
	var copy: IaidoExecutionProfile = duplicate(true)
	copy.set(key, value)
	return copy
