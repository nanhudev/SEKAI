extends Node
class_name WorldPauseManager

@onready var audio_state: AudioStateController = get_parent().get_node("AudioStateController")
var locked := false
var previous_tree_pause := false
var previous_world_audio := false
var previous_music := false


func acquire() -> void:
	if locked:
		return
	previous_tree_pause = get_tree().paused
	previous_world_audio = audio_state.world_paused
	previous_music = audio_state.music_paused
	locked = true
	audio_state.pause_world_audio()
	get_tree().paused = true


func release() -> void:
	if not locked:
		return
	locked = false
	get_tree().paused = previous_tree_pause
	if is_instance_valid(audio_state):
		if not previous_world_audio:
			audio_state.resume_world_audio()
		if not previous_music:
			audio_state.resume_music()


func _exit_tree() -> void:
	release()
