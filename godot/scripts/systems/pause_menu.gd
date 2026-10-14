extends Control

signal resume_pressed
signal settings_pressed
signal title_pressed
signal exit_pressed


func _ready() -> void:
	var background := ColorRect.new()
	background.color = Color(0.02, 0.06, 0.08, 0.82)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var rows := VBoxContainer.new()
	rows.position = Vector2(80, 130)
	rows.custom_minimum_size = Vector2(320, 300)
	add_child(rows)
	var title := Label.new()
	title.text = "旅途暂歇"
	title.add_theme_font_size_override("font_size", 30)
	rows.add_child(title)
	_add_button(rows, "继续", func() -> void: resume_pressed.emit())
	_add_button(rows, "设置", func() -> void: settings_pressed.emit())
	_add_button(rows, "回到标题", func() -> void: title_pressed.emit())
	_add_button(rows, "退出", func() -> void: exit_pressed.emit())


func _add_button(parent: VBoxContainer, title: String, callback: Callable) -> void:
	var button := Button.new()
	button.text = title
	button.custom_minimum_size = Vector2(300, 48)
	button.pressed.connect(callback)
	parent.add_child(button)
