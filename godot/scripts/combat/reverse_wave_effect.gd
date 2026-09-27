extends Control
class_name ReverseWaveEffect
# Multi-layer reverse compression.
#
# This is NOT an energy ring. Three staggered shells of air refraction collapse
# back into the sheath mouth, dragging the world's sound and motion with them.
# Palette stays transparent white / very pale blue: no RGB magic circle.

const PALE := Color(0.90, 0.93, 0.97, 1.0)
const COOL := Color(0.78, 0.86, 0.94, 1.0)
const SQUASH := 0.66
const TILT := -0.30

var anchor_uv := Vector2(0.22, 0.80)
var progress := Vector3.ZERO
var strength := 0.0

# Per-shell base radius (fraction of viewport height) and mote seed.
const SHELL_RADIUS := [0.66, 0.46, 0.30]
const SHELL_SEED := [0.0, 2.7, 5.1]


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false


func set_frame(anchor: Vector2, shell_progress: Vector3, opacity: float) -> void:
	anchor_uv = anchor
	progress = Vector3(
		clampf(shell_progress.x, 0.0, 1.0),
		clampf(shell_progress.y, 0.0, 1.0),
		clampf(shell_progress.z, 0.0, 1.0)
	)
	strength = clampf(opacity, 0.0, 1.0)
	visible = strength > 0.001 and (progress.x < 1.0 or progress.y < 1.0 or progress.z < 1.0)
	queue_redraw()


func _draw() -> void:
	if strength <= 0.001:
		return
	var center := anchor_uv * size
	var unit := size.y
	for shell in 3:
		var p: float = progress[shell]
		if p <= 0.001 or p >= 1.0:
			continue
		# Reverse wave eases IN: the collapse accelerates as it nears the sheath.
		var remaining := 1.0 - pow(p, 1.75)
		var base := float(SHELL_RADIUS[shell]) * unit * remaining
		var shell_seed := float(SHELL_SEED[shell])
		var fade := sin(clampf(p, 0.0, 1.0) * PI) * strength
		_draw_shell(center, base, shell_seed, fade * 0.85)
		_draw_motes(center, base, shell_seed, remaining, fade)


func _frac(value: float) -> float:
	return value - floor(value)


func _draw_shell(center: Vector2, radius: float, shell_seed: float, alpha: float) -> void:
	var outer := PackedVector2Array()
	var inner := PackedVector2Array()
	for i in 73:
		var angle := TAU * float(i) / 72.0
		var wobble := (
			1.0
			+ 0.085 * sin(angle * 3.0 + shell_seed)
			+ 0.050 * sin(angle * 5.0 - shell_seed * 1.7)
			+ 0.032 * sin(angle * 8.0 + shell_seed * 2.3)
		)
		var point := Vector2(cos(angle), sin(angle) * SQUASH).rotated(TILT) * radius * wobble
		outer.append(center + point)
		inner.append(center + point * 0.93)
	# Wide soft band first (refraction), then a crisp thin edge.
	draw_polyline(outer, Color(COOL.r, COOL.g, COOL.b, alpha * 0.14), 4.5, true)
	draw_polyline(inner, Color(PALE.r, PALE.g, PALE.b, alpha * 0.28), 1.15, true)


func _draw_motes(center: Vector2, radius: float, shell_seed: float, remaining: float, alpha: float) -> void:
	# Air being dragged inward: short streaks whose tail points outward.
	var count := 30
	for i in count:
		var fi := float(i)
		var angle := fi * 2.399 + shell_seed
		var start: float = radius * (0.72 + _frac(sin(fi * 12.9898 + shell_seed) * 43758.5453) * 0.55)
		var point: Vector2 = Vector2(cos(angle), sin(angle) * float(SQUASH)).rotated(float(TILT))
		var tail_length: float = radius * (0.10 + _frac(sin(fi * 78.233 + shell_seed) * 12345.678) * 0.16)
		var head: Vector2 = center + point * start
		var tail: Vector2 = center + point * (start + tail_length)
		var mote_alpha := alpha * 0.70 * clampf(remaining * 1.6, 0.0, 1.0)
		draw_line(head, tail, Color(PALE.r, PALE.g, PALE.b, mote_alpha), 1.0)
