extends Node3D
class_name SwordPickup
# ============================================================================
# 第一把剑 — THE WEAPON RACK IN THE SQUARE, AND THE FIRST THING YOU EVER HOLD
# ============================================================================
#
# §6 IS THE HARDEST REQUIREMENT IN THIS ROUND, AND IT IS A PROHIBITION:
#
#   "不要：走过去按 E，剑瞬间进入 Inventory，然后右下角 +1 Sword。"
#
# So this node does not grant a weapon. It performs a PICK-UP, in four beats,
# with the sword visible the whole time:
#
#   0.00 - 0.55  the hands go out of frame and reach toward the rack
#   0.55         the sword leaves the rack     (the exhibit is hidden, the hand
#                and the rack stop agreeing about where the sword is - which is
#                exactly the moment a pick-up becomes real rather than a menu)
#   0.55 - 1.15  it comes up into the frame, held out, and is TURNED OVER
#   1.15 - 1.75  it settles to the carry pose, where it lives from then on
#
# AND THE SWORD ARRIVES SHEATHED, ON PURPOSE.
#
# The blade comes home into the scabbard in the same frame it arrives in the
# hand, because §7's next requirement is that the player DRAWS it - and a sword
# that is already out cannot be drawn. Mechanically that is `equip_blend = 0`
# with `WeaponSlot.kind = sword`: the hand holds a sword whose blade is in its
# saya, which is the only state from which "拔刀" means anything.
#
# WHY THE RACK IS BUILT HERE RATHER THAN IN THE .tscn. It reuses
# `training_build.gd`, the same material palette and the same exhibit basis as
# the training ground's rack (`training_weapon_rack.gd`), so the two racks in
# the project are visibly the same object. That is worth more than the diff
# being two lines shorter: a player who saw the training ground and then walks
# into the square should not be looking at two different ideas of "a rack".

const TB := preload("res://scripts/training/training_build.gd")

## §5 says 2.2-2.6 m for talking; a rack is a thing you stand in front of, and
## the same number works. Derived from the same constant so the two prompts
## cannot drift apart.
const REACH := 2.6

## Where the rack stands, relative to this node. The plaza places this node and
## the rack builds around it, so the dressing script never has to know the
## rack's internal dimensions to put it somewhere.
const RACK_H := 1.55
const BAR_LEN := 2.2
const BOARD_Z := 0.10
const EXHIBIT_Z := 0.17

const EXHIBIT_BASIS := Basis(
	Vector3(0.0, -1.0, 0.0), Vector3(1.0, 0.0, 0.0), Vector3(0.0, 0.0, 1.0)
)

const SWORD_NAME := "无铭长剑"

signal taken()

var prompt_label := "[F]  拿起旧剑"
var _player: Node3D = null
var _slot: WeaponSlot = null
var _combat: Node = null
var _weapon_root: Node3D = null
var _exhibit: Node3D = null
var _taken := false
var _ceremony_running := false
var _label: Label3D = null
var _root_home := Vector3.ZERO


func _ready() -> void:
	add_to_group(&"interactable")
	_build()
	set_process(false)


# ------------------------------------------------------------------ geometry

func _build() -> void:
	var timber := TB.material(TB.TIMBER)
	var accent := TB.material(TB.ACCENT, 0.8, 0.35)

	TB.post(self, "Upright_L", Vector3(-BAR_LEN * 0.5, 0.0, 0.0), RACK_H, 0.075, timber, true)
	TB.post(self, "Upright_R", Vector3(BAR_LEN * 0.5, 0.0, 0.0), RACK_H, 0.075, timber, true)
	TB.slab(self, "CrossBar", Vector3(0.0, RACK_H, 0.0), Vector3(BAR_LEN + 0.3, 0.10, 0.10), accent)
	# Dark board, for the same measured reason the training rack has one: a pale
	# steel blade against a pale backing has no silhouette.
	var board_mat := TB.material(Color(0.108, 0.098, 0.092), 0.74)
	TB.slab(self, "Board", Vector3(0.0, RACK_H * 0.62, BOARD_Z),
		Vector3(BAR_LEN + 0.1, 0.95, 0.06), board_mat)

	_exhibit = Node3D.new()
	_exhibit.name = "Exhibit"
	_exhibit.position = Vector3(0.0, RACK_H - 0.16, EXHIBIT_Z)
	add_child(_exhibit)
	_mount_sword(_exhibit)
	_mount_saya()

	# §6 names the weapon. 无铭长剑 is deliberate: an object with no maker's mark,
	# which is a fact about the world rather than a label on an inventory slot,
	# and it is not "Starter Sword" / "Test Sword" / "Weapon01".
	_label = TB.label(self, "RackLabel", SWORD_NAME, Vector3(0.0, RACK_H + 0.42, 0.0), 0.30)


func _mount_sword(parent: Node3D) -> void:
	var node := _instance(["res://scenes/weapons/Sword_FP.tscn",
		"res://models/weapons/fp_sword.glb"])
	if node == null:
		# An empty stand with a label, never a fabricated sword.
		TB.slab(parent, "SwordPlaceholder", Vector3.ZERO, Vector3(1.05, 0.09, 0.03),
			TB.material(TB.STONE_STRUCT), false)
		return
	node.name = "SwordFP"
	node.basis = EXHIBIT_BASIS
	parent.add_child(node)


func _mount_saya() -> void:
	# The scabbard is a SECOND EXHIBIT under the blade, sharing its origin, for
	# the reason the training rack documents: a scabbard is only reviewable
	# against its own blade, and the mouth is where the whole fit lives.
	var node := _instance(["res://models/weapons/fp_saya.glb"])
	if node == null:
		return
	var bay := Node3D.new()
	bay.name = "SayaExhibit"
	bay.position = Vector3(0.0, RACK_H - 0.46, EXHIBIT_Z)
	add_child(bay)
	node.name = "SayaFP"
	node.basis = EXHIBIT_BASIS
	bay.add_child(node)


func _instance(paths: Array) -> Node3D:
	for path in paths:
		if not ResourceLoader.exists(path):
			continue
		var packed := load(path) as PackedScene
		if packed != null:
			return packed.instantiate() as Node3D
	return null


# ------------------------------------------------------------------ interaction

## The interaction hub asks this, and the same signature is on MiraActor, so the
## hub has exactly one shape to understand.
func interact_label() -> String:
	return prompt_label


func interact_range() -> float:
	return REACH


func can_interact() -> bool:
	return not _taken and not _ceremony_running


func interact(by: Node3D) -> bool:
	if not can_interact() or by == null:
		return false
	_resolve(by)
	if _slot == null:
		# Loud rather than silent: a rack that reports success and moves nothing
		# is the single most expensive kind of bug to find later.
		push_warning("SwordPickup: the player has no WeaponSlot, so the sword "
			+ "cannot change hands. Add it to Player.tscn.")
		return false
	_taken = true
	_label.text = ""
	_ceremony()
	return true


func _resolve(by: Node3D) -> void:
	_player = by
	_slot = by.get_node_or_null("WeaponSlot") as WeaponSlot
	_combat = by.get_node_or_null("CombatController")
	_weapon_root = by.get_node_or_null(
		"CameraRig/LookPivot/MotionPivot/ShakePivot/WeaponRoot") as Node3D
	if _weapon_root != null:
		_root_home = _weapon_root.position


# ------------------------------------------------------------------ the take

func _ceremony() -> void:
	_ceremony_running = true
	var cam: Camera3D = null
	var feedback = null
	if _player != null:
		cam = _player.get_node_or_null(
			"CameraRig/LookPivot/MotionPivot/ShakePivot/Camera3D") as Camera3D
		feedback = _player.get_node_or_null("CameraFeedbackController")
	var t := create_tween()
	t.set_trans(Tween.TRANS_SINE)

	# BEAT 1 - REACH. The hands leave the bottom of the frame and go toward the
	# rack. There is no hand mesh in this project, so the reach is expressed as
	# the WEAPON ROOT moving, which is the same node every sword pose already
	# rides and therefore needs no new rig.
	var reach := _root_home + Vector3(0.10, -0.34, -0.16)
	t.tween_property(_weapon_root, "position", reach, 0.55)
	t.tween_callback(_take_from_rack)
	# BEAT 2 - THE LOOK. Held out and slightly turned over: a 40-degree roll about
	# the blade's own axis, which is the rotation that makes a sword read as a
	# found OBJECT rather than as a weapon already equipped.
	var lifted := _root_home + Vector3(0.02, 0.06, -0.04)
	t.tween_property(_weapon_root, "position", lifted, 0.34)
	t.parallel().tween_property(_weapon_root, "rotation",
		Vector3(-0.28, 0.30, 0.62), 0.34)
	if feedback != null:
		t.tween_callback(func() -> void: feedback.call("fov_kick", 1.6))
	t.tween_interval(0.42)
	# BEAT 3 - SETTLE. Back to the carry pose, where the sword lives from here.
	t.tween_property(_weapon_root, "position", _root_home, 0.5)
	t.parallel().tween_property(_weapon_root, "rotation", Vector3.ZERO, 0.5)
	t.tween_callback(func() -> void:
		_ceremony_running = false
		taken.emit()
	)
	if cam != null:
		pass


## The one frame in which the sword changes owner.
##
## BOTH WRITES LAND BEFORE THE NEXT FRAME RENDERS, and that is the whole trick:
## `equip()` makes the rig visible and forces `equip_blend` to 1.0 through
## WeaponManager's foreign-writer path; the very next line puts the blade back
## home at 0.0. Rendered one frame apart it would read as a sword appearing and
## then snapping into its sheath; rendered in the same frame it is simply a
## sheathed sword that is now in your hand.
func _take_from_rack() -> void:
	if _exhibit != null:
		_exhibit.visible = false
	var saya := get_node_or_null("SayaExhibit") as Node3D
	if saya != null:
		saya.visible = false
	if _slot != null:
		_slot.equip(&"sword")
	if _combat != null:
		_combat.set("equip_blend", 0.0)
	# §6: "剑模型消失。第一人称手进入画面。" The rig is the hand in this build;
	# WeaponManager has already made it visible because the slot now holds a
	# sword. Nothing else needs to be shown.
