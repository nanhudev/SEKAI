extends Control
class_name ReverseWaveEffect
# Multi-layer reverse compression — the debris half of it.
#
# This is NOT an energy ring. The visible compression front (a lit crest or a
# dark density band, whichever suits what it crosses) is drawn by
# iaido_world_split.gdshader, because only a screen-sampling shader can decide
# that from the pixels behind it. This node adds the other half: streaks of air
# and dust being dragged inward along the same shells, so the shells are also
# readable as something physical being swallowed rather than as a moving
# circle.
#
# The streaks are dark with a thin lit core, not white: they travel over a pale
# sky and a pale floor, where white streaks are invisible.
#
# The final drain is a separate, much tighter burst: three shells collapsing is
# convergence, the last instant before the click is a vacuum.

const DARK := Color(0.20, 0.24, 0.32, 1.0)
const PALE := Color(0.90, 0.93, 0.97, 1.0)
const SQUASH := 0.66
const TILT := -0.30

# Radius curve, shared with ring_profile() in the shader: a shell keeps its
# size for most of its life and then collapses fast into the sheath mouth.
const SHELL_START := 0.95
const SHELL_SEED := [0.0, 2.7, 5.1]

var anchor_uv := Vector2(0.22, 0.80)
var progress := Vector3.ZERO
var strength := 0.0
var suck := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false


func set_frame(anchor: Vector2, shell_progress: Vector3, opacity: float, drain: float = 0.0) -> void:
	anchor_uv = anchor
	progress = Vector3(
		clampf(shell_progress.x, 0.0, 1.0),
		clampf(shell_progress.y, 0.0, 1.0),
		clampf(shell_progress.z, 0.0, 1.0)
	)
	strength = clampf(opacity, 0.0, 1.0)
	suck = clampf(drain, 0.0, 1.0)
	visible = (
		(strength > 0.001 and (progress.x < 1.0 or progress.y < 1.0 or progress.z < 1.0))
		or suck > 0.001
	)
	queue_redraw()


func _draw() -> void:
	if not visible:
		return
	var centre := anchor_uv * size
	var unit := size.y
	for shell in 3:
		var p: float = progress[shell]
		if p <= 0.001 or p >= 1.0:
			continue
		var falloff := pow(1.0 - p, 0.55)
		var base := SHELL_START * unit * falloff
		var fade := sin(clampf(p, 0.0, 1.0) * PI) * strength
		_draw_motes(centre, base, float(SHELL_SEED[shell]), falloff, fade)
	if suck > 0.001:
		_draw_drain(centre)


func _frac(value: float) -> float:
	return value - floor(value)


func _draw_motes(centre: Vector2, radius: float, shell_seed: float, falloff: float, alpha: float) -> void:
	# Air being dragged inward: short streaks whose tail points outward.
	var count := 34
	for i in count:
		var fi := float(i)
		var angle := fi * 2.399 + shell_seed
		var start: float = radius * (0.80 + _frac(sin(fi * 12.9898 + shell_seed) * 43758.5453) * 0.40)
		var point: Vector2 = Vector2(cos(angle), sin(angle) * float(SQUASH)).rotated(float(TILT))
		var tail_length: float = radius * (0.09 + _frac(sin(fi * 78.233 + shell_seed) * 12345.678) * 0.15)
		var head: Vector2 = centre + point * start
		var tail: Vector2 = centre + point * (start + tail_length)
		var mote_alpha := alpha * 0.85 * clampf(falloff * 1.5, 0.0, 1.0)
		# A dark refraction edge with a thin lit core, so the streak survives
		# both the pale sky and the pale floor.
		draw_line(head, tail, Color(DARK.r, DARK.g, DARK.b, mote_alpha * 0.62), 1.5)
		draw_line(head, tail, Color(PALE.r, PALE.g, PALE.b, mote_alpha * 0.50), 0.8)


func _draw_drain(centre: Vector2) -> void:
	# The last instant: everything close to the sheath mouth is pulled in hard.
	# Streaks get shorter and brighter as they close, which reads as speed.
	var count := 46
	for i in count:
		var fi := float(i)
		var angle := fi * 2.399 + 1.3
		var reach := size.y * (0.10 + _frac(sin(fi * 31.7 + 4.1) * 3719.13) * 0.26)
		var point: Vector2 = Vector2(cos(angle), sin(angle) * float(SQUASH)).rotated(float(TILT))
		var length := reach * (0.30 - 0.22 * suck)
		var head: Vector2 = centre + point * (reach - length)
		var tail: Vector2 = centre + point * reach
		var alpha := suck * (0.35 + 0.45 * _frac(sin(fi * 7.3) * 9781.31))
		draw_line(head, tail, Color(DARK.r, DARK.g, DARK.b, alpha * 0.55), 1.2)
		draw_line(head, tail, Color(PALE.r, PALE.g, PALE.b, alpha * 0.45), 0.7)
