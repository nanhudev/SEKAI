extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene: PackedScene = load("res://scenes/main/Main.tscn")
	var main: Node = scene.instantiate()
	root.add_child(main)
	await process_frame
	if not main.main_menu.visible or main.combat_sandbox != null:
		_fail("Expected main menu on launch")
		return
	main.main_menu.start_pressed.emit()
	await process_frame
	if main.combat_sandbox == null or main.main_menu.visible:
		_fail("Main menu did not enter combat sandbox")
		return
	main.pause_game()
	if not main.pause_menu.visible or main.combat_sandbox.process_mode != Node.PROCESS_MODE_DISABLED:
		_fail("Pause did not stop sandbox processing")
		return
	main.pause_menu.settings_pressed.emit()
	if not main.settings_menu.visible:
		_fail("Settings did not open from pause")
		return
	main.settings_menu.back_pressed.emit()
	if not main.pause_menu.visible:
		_fail("Settings did not return to pause")
		return
	main.pause_menu.resume_pressed.emit()
	# Main runs ALWAYS so the pause menu can still react while the world is
	# paused; the sandbox therefore resumes as PAUSABLE, never INHERIT.
	if main.pause_menu.visible or main.combat_sandbox.process_mode != Node.PROCESS_MODE_PAUSABLE:
		_fail("Resume did not restore sandbox")
		return
	if main.process_mode != Node.PROCESS_MODE_ALWAYS:
		_fail("Main menu flow must keep processing while the world is paused")
		return
	main.pause_game()
	main.pause_menu.title_pressed.emit()
	await process_frame
	if not main.main_menu.visible or main.combat_sandbox != null:
		_fail("Return to title failed")
		return
	main.main_menu.start_pressed.emit()
	await process_frame
	if main.combat_sandbox == null:
		_fail("Restart after returning to title failed")
		return
	print("PASS: menu, combat, pause, settings, title and restart flow")
	quit(0)


func _fail(reason: String) -> void:
	push_error(reason)
	quit(1)
