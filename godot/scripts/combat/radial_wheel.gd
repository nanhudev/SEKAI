extends Control
class_name RadialWheel
# A radial selector. It deliberately does NOT know what a school or a spell is:
# the HUD hands it a flat list of sectors and it hands back the id under the
# pointer.
#
# It used to hardcode three sectors named FIRE / FROST / WIND and return a school
# id. That is exactly why the second spell of every school was unreachable in
# play: the wheel could not physically express a fourth sector, so nothing
# noticed that the player could only ever cast a primary. Adding a spell to
# MagicLibrary now adds a sector here for free.

# [{id: StringName, label: String, color: Color, group: String}]
var entries: Array = []
var selected_spell: StringName = &""
# What the player has equipped right now. The wheel has to answer two different
# questions — "what am I pointing at" and "what is in my hand" — or the two
# spells of one school stay indistinguishable while you are choosing.
var armed: StringName = &""
var pointer := Vector2.ZERO

const CENTER := Vector2(140, 140)
const RADIUS := 126.0
const LABEL_RADIUS := 84.0


func _ready() -> void:
	custom_minimum_size = Vector2(280, 280)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_entries(list: Array) -> void:
	entries = list
	selected_spell = &""
	queue_redraw()


# Sectors are laid out clockwise from the top, in the order handed in, so the two
# spells of a school always end up next to each other. Public because aiming at a
# sector by hand (tests, future gamepad stick snapping) needs the same geometry
# the drawing uses.
func sector_angle(index: int) -> float:
	return -PI / 2.0 + float(index) * TAU / float(maxi(entries.size(), 1))


func sector_of(wanted: StringName) -> int:
	for index in range(entries.size()):
		if entries[index]["id"] == wanted:
			return index
	return -1


func set_direction(direction: Vector2) -> void:
	pointer = direction.limit_length(110.0)
	selected_spell = &""
	if direction.length() >= 28.0 and not entries.is_empty():
		var step := TAU / float(entries.size())
		var angle := atan2(direction.y, direction.x)
		# floor, not round: rounding sends the two halves of a boundary sector to
		# different answers, so the highlight flickers while you cross the seam.
		var index := int(floor((angle + PI / 2.0 + step * 0.5) / step))
		selected_spell = entries[posmod(index, entries.size())]["id"]
	queue_redraw()


func _draw() -> void:
	draw_circle(CENTER, RADIUS + 5.0, Color(0.02, 0.06, 0.08, 0.83))
	if entries.is_empty():
		draw_arc(CENTER, RADIUS, 0.0, TAU, 72, Color(0.8, 0.9, 0.95, 0.75), 2.0)
		draw_circle(CENTER, 28.0, Color(0.03, 0.07, 0.09, 0.96))
		return
	var font := get_theme_default_font()
	var step := TAU / float(entries.size())
	for index in range(entries.size()):
		var entry: Dictionary = entries[index]
		var center_angle := sector_angle(index)
		var points := PackedVector2Array([CENTER])
		for sub in range(13):
			var segment := center_angle - step * 0.5 + float(sub) / 12.0 * step
			points.append(CENTER + Vector2(cos(segment), sin(segment)) * RADIUS)
		var tint: Color = entry["color"]
		var is_hover: bool = entry["id"] == selected_spell
		var is_armed: bool = entry["id"] == armed
		tint.a = 0.85 if is_hover else (0.52 if is_armed else 0.30)
		draw_colored_polygon(points, tint)
		if is_armed:
			draw_arc(
				CENTER,
				RADIUS - 3.0,
				center_angle - step * 0.5,
				center_angle + step * 0.5,
				12,
				Color(0.97, 0.99, 1.0, 0.9),
				2.5
			)
		var label_position := (
			CENTER + Vector2(cos(center_angle), sin(center_angle)) * LABEL_RADIUS + Vector2(-40.0, 6.0)
		)
		# Wind's tint is nearly white; white-on-white would erase its own label.
		var label_color := Color(0.07, 0.10, 0.13) if tint.get_luminance() > 0.62 else Color.WHITE
		draw_string(
			font,
			label_position,
			String(entry["label"]),
			HORIZONTAL_ALIGNMENT_CENTER,
			80,
			16,
			label_color
		)
	draw_arc(CENTER, RADIUS, 0.0, TAU, 72, Color(0.8, 0.9, 0.95, 0.75), 2.0)
	draw_circle(CENTER, 30.0, Color(0.03, 0.07, 0.09, 0.96))
	var armed_label := ""
	for entry in entries:
		if entry["id"] == armed:
			armed_label = String(entry["label"])
	if armed_label != "":
		draw_string(
			font,
			CENTER + Vector2(-28.0, 6.0),
			armed_label,
			HORIZONTAL_ALIGNMENT_CENTER,
			56,
			15,
			Color(0.92, 0.96, 1.0)
		)
	if pointer.length() > 1.0:
		draw_line(CENTER, CENTER + pointer, Color(0.95, 0.98, 1.0, 0.75), 3.0, true)
		draw_circle(CENTER + pointer, 6.0, Color.WHITE)
