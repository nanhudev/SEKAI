extends Node3D
## THE FIRST-PERSON SWORD, AS A RIG THAT CANNOT MISPLACE ITSELF.
##
## Deliberately NO `class_name`. Nothing resolves this script by name -- the scene
## attaches it by path and the driver holds it as a plain `Node3D` -- and a global
## name would mean the class cache has to be rewritten before anything else can
## load, which is a cost with no payer. Same reasoning as reaching the registry by
## `preload` rather than by making it global.
##
## ==========================================================================
## WHAT THIS FILE IS FOR
## ==========================================================================
## `scenes/weapons/Sword_FP.tscn` is the sword as the game should see it: the
## two GLBs, the anchors a consumer needs, and the blade's judgement volume.
## This script is the part of it that cannot be written as three numbers in a
## scene file -- deriving the volume from the registry, and putting the real
## scabbard where the ceremony expects one.
##
## ==========================================================================
## THE SWAP, AND WHY IT IS DONE THIS WAY AND NOT THE DOCUMENTED WAY
## ==========================================================================
## REQ-2 originally asked MAIN to instance this scene under `WeaponRoot` and set
## `TempSwordVisual.visible = false`.  That plan is WRONG, and it is wrong in
## exactly the way "换建模不影响位置和技能效果" is asking about:
##
##   * `iaido_director.gd:46` and `moment_of_no_moon_director.gd:55` both
##     hard-`get_node()` TempSwordVisual and then WRITE ITS TRANSFORM for the
##     whole ceremony.  Hiding the node does not stop that -- it hides the only
##     thing being animated, so the ceremony would play out on an invisible
##     placeholder while the real sword sat still at its idle pose.  The skill
##     would look broken while every line of its code ran correctly.
##   * `temp_sword_visual.gd` is not a passive carrier either: the trail, the
##     glint band, the void rim, the contact springs and the five locomotion
##     channels are all children of that node.
##
## So the swap goes the other way round: **this scene is a CHILD of the existing
## carrier, and the carrier keeps every one of its jobs.**  Nothing about how the
## sword is posed, judged or animated changes; only what is drawn changes.  No
## node path moves, no file outside `scripts/weapons/` and this scene is edited,
## and `Player.tscn` is not touched at all.
##
## ==========================================================================
## THE SCABBARD, AND WHY THERE IS A STAND-IN IN THE WAY
## ==========================================================================
## `Player.tscn` carries `WeaponRoot/SheathAnchor/CeremonyScabbard` -- a
## `MeshInstance3D` running `iaido_scabbard_rig.gd`, which is COMBAT's
## STRUCTURALLY FAITHFUL procedural stand-in for the real saya.  Its own header
## says it plainly:
##
##   "It is built to the numbers in the brief, so replacing it with the GLB is a
##    geometry-only swap with no runtime change."
##
## and it publishes the frame it is built in -- origin at the centre of the
## koiguchi mouth plane, +Y down the bore, -X the edge side, +Z the kurikata
## side.  That is the SAME frame `tools/blender/saya_build.py` authors
## `fp_saya.glb` in (see `scripts/weapons/sword_classes.gd`'s frame section), so
## the real saya needs **no rotation and no offset** to take its place: identity
## under the same node is the whole transformation.
##
## `iaido_scabbard_rig.gd:49` is also the hook that makes this a one-line swap
## from ART's side -- `if mesh == null: build()`.  The stand-in is therefore
## replaced by CLEARING ITS MESH (kept, not destroyed: `restore_standin()` puts
## it back) and adding the real saya as a child of the same node, where it
## inherits the visibility the director already drives
## (`iaido_director.gd:845`).  Nothing in COMBAT has to know.
##
## ==========================================================================
## OTHER CONSUMERS
## ==========================================================================
## This scene is ALSO the training ground's rack exhibit, instantiated with no
## `TempSwordVisual` above it.  Every install step below is therefore guarded and
## simply does not run off the player; the rack gets the sword and the volume and
## nothing else.  See `training_weapon_rack.gd`.

## Which row of `SwordClassRegistry` this rig is.  A second sword-class weapon is
## a row there plus an instance of this scene with this field changed -- there is
## no `if weapon_id ==` anywhere in this file, and nothing here is typed in from
## a document.
## The registry, reached by path rather than by a `class_name`.  A `preload` keeps
## this a plain file dependency: it adds no global name to the project and needs
## no class-cache rewrite, and the only thing being borrowed is a table.
const Registry := preload("res://scripts/weapons/sword_classes.gd")

@export var weapon_id: StringName = &"iaito"

## The seated saya is OFF by default.  A sword that is being HELD is not also in
## its sheath, and the two states want to be separate display items on a rack.
## `set_seated_saya_visible()` is the switch.
@export var seated_saya_visible := false

## Replaces COMBAT's procedural ceremony scabbard with the real one when this rig
## finds itself on the player.  Exported so the swap can be ablated in one click
## if the real saya ever regresses the ceremony.
@export var install_ceremony_scabbard := true

var _blade_volume: Area3D
var _blade_shape_node: CollisionShape3D
var _seated_saya: Node3D
## The stand-in's own mesh, held rather than discarded so the swap is reversible
## for the lifetime of the run.
var _standin_mesh: Mesh
var _standin: MeshInstance3D
var _installed_saya: Node3D


func _ready() -> void:
	_blade_volume = get_node_or_null("BladeVolume") as Area3D
	_blade_shape_node = get_node_or_null("BladeVolume/CollisionShape3D") as CollisionShape3D
	_seated_saya = get_node_or_null("Sheath")
	build_blade_volume()
	set_seated_saya_visible(seated_saya_visible)
	if install_ceremony_scabbard:
		install_real_scabbard()


# ---------------------------------------------------------------- the volume

## Sizes and places the blade's judgement volume from the REGISTRY, so the box
## cannot drift away from the measured mesh.
##
## The scene used to carry this as a hand-typed `BoxShape3D size =
## Vector3(0.0565, 0.7608, 0.022)` -- a second copy of four numbers that already
## exist in `sword_classes.gd`, which is the thing the registry exists to stop.
## The scene now carries no shape at all and this builds it, so there is one
## place to change when a sword changes and the `load_steps` count in the scene
## is honest about what is in it.
##
## The volume ships DISABLED (`monitoring = false`, layer 0) because whether a
## judgement reads the swing volume or the blade is COMBAT's decision -- but its
## SIZE is not a COMBAT decision, so it is derived here rather than remembered
## somewhere.
func build_blade_volume() -> void:
	if _blade_shape_node == null:
		return
	_blade_shape_node.shape = Registry.make_blade_shape(weapon_id)
	if _blade_volume != null:
		_blade_volume.position = Registry.blade_volume_xform(weapon_id).origin


## The distance from the rig origin to the tip, in metres.  The driver reads this
## so its trail is drawn to the blade that is actually there.
func sword_length() -> float:
	return Registry.visual_length(weapon_id)


# ---------------------------------------------------------------- the seated saya

func set_seated_saya_visible(wanted: bool) -> void:
	seated_saya_visible = wanted
	if _seated_saya != null:
		_seated_saya.visible = wanted


func seated_saya() -> Node3D:
	return _seated_saya


# ---------------------------------------------------------------- the ceremony

## Puts the real saya where COMBAT's stand-in is, and retires the stand-in.
##
## Deliberately silent off the player: `get_parent()` is the carrier
## (`TempSwordVisual`) only on the player, so the rack and any future standalone
## user of this scene get a no-op rather than a warning about a node that was
## never supposed to be there.
func install_real_scabbard() -> void:
	var host := get_parent()
	if host == null or host.name != &"TempSwordVisual":
		return
	var weapon_root := host.get_parent()
	if weapon_root == null:
		return
	_standin = weapon_root.get_node_or_null("SheathAnchor/CeremonyScabbard") as MeshInstance3D
	if _standin == null:
		return
	if _installed_saya != null and is_instance_valid(_installed_saya):
		return
	var path := Registry.scabbard_path(weapon_id)
	if not ResourceLoader.exists(path):
		# Leaving the stand-in in place is the correct failure: a ceremony with
		# COMBAT's stand-in scabbard still hides the blade inside a closed tube,
		# which is the one thing the ceremony needs.  An empty anchor would not.
		push_warning("SwordFPRig: '%s' is missing, keeping the procedural scabbard." % path)
		return
	var scene := load(path) as PackedScene
	if scene == null:
		return
	_installed_saya = scene.instantiate()
	# Identity, and that is not a placeholder: the stand-in, the real GLB and the
	# anchor are all authored in the same frame (origin = mouth plane, +Y = down
	# the bore).  See this file's header.
	_installed_saya.name = "Saya"
	_standin.add_child(_installed_saya)
	# Retire the stand-in's own geometry, keeping the node: it is the node whose
	# `visible` the director toggles, and the real saya inherits it.
	if _standin.mesh != null:
		_standin_mesh = _standin.mesh
		_standin.mesh = null


## Puts COMBAT's stand-in back.  Present so the swap is a decision and not a
## one-way edit to a file ART does not own.
func restore_standin() -> void:
	if _installed_saya != null and is_instance_valid(_installed_saya):
		_installed_saya.queue_free()
		_installed_saya = null
	if _standin != null and _standin_mesh != null:
		_standin.mesh = _standin_mesh


# ---------------------------------------------------------------- readouts

## What the swap actually did, for `tools/` probes and for a test to assert
## against rather than to eyeball.
func describe() -> Dictionary:
	return {
		"weapon_id": weapon_id,
		"blade_volume_size": Registry.blade_volume_size(weapon_id),
		"sword_length": sword_length(),
		"seated_saya_visible": _seated_saya != null and _seated_saya.visible,
		"ceremony_saya_installed": _installed_saya != null and is_instance_valid(_installed_saya),
		"standin_retired": _standin != null and _standin.mesh == null,
	}
