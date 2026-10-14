extends SceneTree

func _initialize() -> void:
	var source := preload("res://scripts/weapons/sword_hand_presentation.gd")
	var library: AnimationLibrary = source.build_library()
	var result := ResourceSaver.save(library,"res://resources/animations/SwordPresentation.tres")
	print("Sword Feel animation library: ",library.get_animation_list()," save=",result)
	library = null
	call_deferred("quit",result)
