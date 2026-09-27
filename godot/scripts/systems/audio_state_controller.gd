extends Node
class_name AudioStateController

@onready var music: AudioStreamPlayer = get_parent().get_node("CombatMusic")

var world_paused := false
var music_paused := false
var world_ducked := false
var duck_db := 0.0
var original_world_volumes: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(delta: float) -> void:
	var target := 40.0 if world_ducked else 0.0
	if absf(duck_db - target) < 0.01:
		return
	duck_db = move_toward(duck_db, target, delta * 400.0)
	_apply_volumes()


func pause_world_audio() -> void:
	world_paused = true
	_apply()


func resume_world_audio() -> void:
	world_paused = false
	_apply()


func pause_music() -> void:
	music_paused = true
	_apply()


func resume_music() -> void:
	music_paused = false
	_apply()


func duck_world_audio() -> void:
	world_ducked = true
	_apply()


func restore_world_audio() -> void:
	world_ducked = false
	_apply()


func _apply() -> void:
	music.stream_paused = world_paused or music_paused
	for node in get_tree().get_nodes_in_group("world_audio"):
		if node is AudioStreamPlayer or node is AudioStreamPlayer2D or node is AudioStreamPlayer3D:
			node.stream_paused = world_paused
			if not original_world_volumes.has(node):
				original_world_volumes[node] = node.volume_db
	_apply_volumes()


func _apply_volumes() -> void:
	for node in original_world_volumes.keys():
		if is_instance_valid(node):
			node.volume_db = original_world_volumes[node] - duck_db


func _exit_tree() -> void:
	music.stream_paused = false
