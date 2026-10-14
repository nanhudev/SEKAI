extends AudioStreamPlayer

var created_bus := false

func _ready() -> void:
	if AudioServer.get_bus_index("Music") == -1:
		AudioServer.add_bus()
		AudioServer.set_bus_name(AudioServer.bus_count - 1, "Music")
		created_bus = true
	bus = "Music"
	if stream == null:
		push_warning("Combat music could not be loaded")
		return
	if stream is AudioStreamMP3:
		stream.loop = true
	volume_db = -12.0
	play()


func _exit_tree() -> void:
	stop()
	stream = null
	if created_bus:
		var index := AudioServer.get_bus_index("Music")
		if index > 0:
			AudioServer.remove_bus(index)
