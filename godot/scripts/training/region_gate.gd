@tool
extends Node3D
# The gate out of the Training Ground and into the actual world.
#
# WHY IT IS IN THE REVIEW HUB AT ALL (brief §20)
# The old review loop was: stop, close the sandbox, open MistvaleRegion, walk
# around, close it, reopen the sandbox, lose your place. That is four context
# switches to answer one question about a wall. A door between the two scenes
# turns the whole thing into one continuous walk, which is the only way anyone
# will ever check the art often enough for it to matter.
#
# It changes the scene to `MistvaleRegion.tscn`. That scene carries its own
# `ReviewWalker` rather than `Player.tscn` (its header explains why, and it is
# the ART line's scene), so this gate does not depend on MAIN having finished the
# Player integration.
#
# What the gate must NOT do is strand the reviewer: see `LDReviewWalker`, which
# owns the way back.

const TB := preload("res://scripts/training/training_build.gd")

const REGION_SCENE := "res://scenes/world/MistvaleRegion.tscn"

@export var display_text: String = "MISTVALE  ·  REGION REVIEW"
@export var reach: float = 4.0

var _player: Node3D = null
var _prompt: Label3D = null
var _in_reach := false
var _leaving := false

const OPENING_W := 6.0
const OPENING_H := 4.4


func _ready() -> void:
	_geometry()
	if Engine.is_editor_hint():
		return
	_bind_interact()


func _geometry() -> void:
	var stone := TB.material(TB.STONE_STRUCT)
	var accent := TB.material(TB.ACCENT, 0.8, 0.4)

	# Two piers and a lintel. The gate is deliberately a real threshold - a
	# doorway you walk through - rather than a button on a wall, because the brief
	# asks for the transition to be diegetic.
	var half := OPENING_W * 0.5
	TB.slab(self, "Pier_L", Vector3(-half - 0.6, OPENING_H * 0.5, 0.0), Vector3(1.2, OPENING_H, 1.6), stone)
	TB.slab(self, "Pier_R", Vector3(half + 0.6, OPENING_H * 0.5, 0.0), Vector3(1.2, OPENING_H, 1.6), stone)
	TB.slab(self, "Lintel", Vector3(0.0, OPENING_H + 0.45, 0.0), Vector3(OPENING_W + 2.4, 0.9, 1.6), stone)
	TB.slab(self, "Keystone", Vector3(0.0, OPENING_H + 0.45, -0.86), Vector3(0.9, 0.5, 0.2), accent)

	# Sill: a single step up so the threshold is felt underfoot, not just seen.
	TB.slab(self, "Sill", Vector3(0.0, 0.09, 0.0), Vector3(OPENING_W, 0.18, 1.6),
		TB.material(TB.STONE_COURT))

	TB.label(self, "GateLabel", display_text, Vector3(0.0, OPENING_H + 1.35, 0.0), 0.42)

	_prompt = TB.label(self, "GatePrompt", "[F]  进入 Mistvale Region",
		Vector3(0.0, 2.4, 1.1), 0.30, Color(1.0, 0.98, 0.86))
	_prompt.visible = false


func _bind_interact() -> void:
	if not InputMap.has_action(&"interact"):
		InputMap.add_action(&"interact")
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_F
		InputMap.action_add_event(&"interact", ev)


func _resolve() -> void:
	if _player != null and is_instance_valid(_player):
		return
	var tree := get_tree()
	if tree == null:
		return
	_player = tree.get_first_node_in_group(&"player") as Node3D
	if _player == null:
		var scene := tree.current_scene
		if scene != null:
			_player = scene.find_child("Player", true, false) as Node3D


func _process(_delta: float) -> void:
	if Engine.is_editor_hint() or _leaving:
		return
	_resolve()
	if _player == null or _prompt == null:
		return
	var near := _player.global_position.distance_to(global_position) <= reach
	if near != _in_reach:
		_in_reach = near
		_prompt.visible = near


func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint() or _leaving or _player == null:
		return
	if not event.is_action_pressed(&"interact"):
		return
	if _player.global_position.distance_to(global_position) > reach:
		return
	get_viewport().set_input_as_handled()
	_enter_region()


func _enter_region() -> void:
	if not ResourceLoader.exists(REGION_SCENE):
		# Loud, and specific about which file is missing - never a silent failure.
		push_error("TrainingGround gate: region scene not found at %s" % REGION_SCENE)
		return
	_leaving = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	print("[TrainingGround] entering region review: %s" % REGION_SCENE)
	var err := get_tree().change_scene_to_file(REGION_SCENE)
	if err != OK:
		_leaving = false
		push_error("TrainingGround gate: change_scene_to_file failed with code %d" % err)
