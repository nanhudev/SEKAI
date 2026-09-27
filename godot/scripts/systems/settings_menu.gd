extends Control

signal back_pressed

var fov_slider: HSlider
var sensitivity_slider: HSlider
var motion_slider: HSlider
var shake_slider: HSlider


func _ready() -> void:
	var background := ColorRect.new()
	background.color = Color("0b1b20")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var rows := VBoxContainer.new()
	rows.position = Vector2(80, 120)
	rows.custom_minimum_size = Vector2(420, 360)
	add_child(rows)
	var title := Label.new()
	title.text = "设置"
	title.add_theme_font_size_override("font_size", 30)
	rows.add_child(title)
	rows.add_child(_label("视野角度"))
	fov_slider = _slider(60.0, 100.0, 75.0)
	rows.add_child(fov_slider)
	rows.add_child(_label("鼠标灵敏度"))
	sensitivity_slider = _slider(0.001, 0.006, 0.0024)
	sensitivity_slider.step = 0.0001
	rows.add_child(sensitivity_slider)
	rows.add_child(_label("镜头运动"))
	motion_slider = _slider(0.0, 2.0, 1.0)
	motion_slider.step = 0.05
	rows.add_child(motion_slider)
	rows.add_child(_label("镜头震动"))
	shake_slider = _slider(0.0, 2.0, 1.0)
	shake_slider.step = 0.05
	rows.add_child(shake_slider)
	var back := Button.new()
	back.text = "返回"
	back.custom_minimum_size = Vector2(300, 48)
	back.pressed.connect(func() -> void: back_pressed.emit())
	rows.add_child(back)


func _label(value: String) -> Label:
	var label := Label.new()
	label.text = value
	return label


func _slider(minimum: float, maximum: float, value: float) -> HSlider:
	var slider := HSlider.new()
	slider.min_value = minimum
	slider.max_value = maximum
	slider.value = value
	slider.custom_minimum_size = Vector2(340, 28)
	return slider
