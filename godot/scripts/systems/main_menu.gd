extends Control

signal start_pressed
signal settings_pressed
signal exit_pressed


func _ready() -> void:
	var background := ColorRect.new()
	background.color = Color("0b1b20")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var rows := VBoxContainer.new()
	rows.position = Vector2(80, 160)
	rows.custom_minimum_size = Vector2(360, 280)
	add_child(rows)
	var title := Label.new()
	title.text = "SEKAI  ·  世界之外"
	title.add_theme_font_size_override("font_size", 32)
	rows.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "COMBAT SANDBOX"
	rows.add_child(subtitle)
	_add_button(rows, "进入战斗沙盒", func() -> void: start_pressed.emit())
	_add_button(rows, "设置", func() -> void: settings_pressed.emit())
	_add_button(rows, "退出", func() -> void: exit_pressed.emit())


func _add_button(parent: VBoxContainer, title: String, callback: Callable) -> void:
	var button := Button.new()
	button.text = title
	button.custom_minimum_size = Vector2(300, 48)
	button.pressed.connect(callback)
	parent.add_child(button)
