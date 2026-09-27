extends Control
class_name RadialWheel

var selected_spell: StringName = &""
var pointer := Vector2.ZERO

const CENTER := Vector2(140, 140)
const RADIUS := 126.0


func _ready() -> void:
	custom_minimum_size = Vector2(280, 280)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_direction(direction: Vector2) -> void:
	pointer = direction.limit_length(110.0)
	selected_spell = &""
	if direction.length() >= 28.0:
		var angle := atan2(direction.y, direction.x)
		if angle > -5.0 * PI / 6.0 and angle < -PI / 6.0:
			selected_spell = &"fire"
		elif direction.x < 0.0:
			selected_spell = &"frost"
		else:
			selected_spell = &"wind"
	queue_redraw()


func _draw() -> void:
	var names := ["FIRE", "FROST", "WIND"]
	var keys := [&"fire", &"frost", &"wind"]
	var angles := [-PI / 2.0, 5.0 * PI / 6.0, PI / 6.0]
	var colors := [Color(0.85, 0.32, 0.18), Color(0.35, 0.72, 0.94), Color(0.82, 0.89, 0.76)]
	draw_circle(CENTER, RADIUS + 5.0, Color(0.02, 0.06, 0.08, 0.83))
	for index in range(3):
		var angle: float = angles[index]
		var points := PackedVector2Array([CENTER])
		for step in range(25):
			var segment := angle - PI / 3.0 + float(step) / 24.0 * 2.0 * PI / 3.0
			points.append(CENTER + Vector2(cos(segment), sin(segment)) * RADIUS)
		var tint: Color = colors[index]
		tint.a = 0.78 if selected_spell == keys[index] else 0.28
		draw_colored_polygon(points, tint)
		var label_position := CENTER + Vector2(cos(angle), sin(angle)) * 76.0 + Vector2(-45, 7)
		draw_string(get_theme_default_font(), label_position, names[index], HORIZONTAL_ALIGNMENT_CENTER, 90, 18, Color.WHITE)
	draw_arc(CENTER, RADIUS, 0.0, TAU, 72, Color(0.8, 0.9, 0.95, 0.75), 2.0)
	draw_circle(CENTER, 28.0, Color(0.03, 0.07, 0.09, 0.96))
	if pointer.length() > 1.0:
		draw_line(CENTER, CENTER + pointer, Color(0.95, 0.98, 1.0, 0.75), 3.0, true)
		draw_circle(CENTER + pointer, 6.0, Color.WHITE)
