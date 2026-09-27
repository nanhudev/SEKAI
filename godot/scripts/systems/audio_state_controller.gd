extends Node
class_name AudioStateController

@onready var music: AudioStreamPlayer = get_parent().get_node("CombatMusic")

var world_paused := false
var music_paused := false
var world_ducked := false
var original_world_volumes: Dictionary = {}


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
			node.volume_db = original_world_volumes[node] - 18.0 if world_ducked else original_world_volumes[node]


func _exit_tree() -> void:
	music.stream_paused = false
