extends CanvasLayer
class_name StoryUI
# ============================================================================
# THE HUD THAT GROWS.
# ============================================================================
#
# §20: 不要一开始把所有 UI 打开. The rule this file implements is narrower and
# stronger than "hide the bars at the start": **a piece of HUD may only exist
# once something in the world has made it true.** The HP bar is not dimmed, it
# is absent, because the player has nothing that can take damage until the hound
# is in the square; the skill prompt is absent until Mira teaches a skill. The
# bars are not "hidden for atmosphere" - they are not there.
#
# So there is exactly one public entry point per fact:
#
#     objective(text)        the one line telling you what to do
#     prompt(text)           "[F] 交谈" -- present only when the key would work
#     subtitle(...)          someone is talking at you
#     open_dialogue(lines)   someone is talking WITH you
#     toast(...)             you acquired / unlocked something
#     quest(...)             the sequence ended and the world got bigger
#     show_health(...)       nothing can hurt you yet, so this is never called early
#
# WHAT IT DELIBERATELY DOES NOT DO. It does not know the story stages, it does
# not know the sword exists, and it never asks the director a question. Every
# string it displays was pushed to it by something that had already happened.
# That is what lets the same HUD be reused by a later scene that has a different
# script - and it is also why a HUD bug can never stall the sequence.
#
# IT IS ALSO THE GAME'S ONLY WESTERN-SCRIPT SURFACE, SO IT IS BUILT IN CODE.
# A .tscn of twenty nested containers is unreviewable in a diff and would have
# to be rebuilt by hand for every layout change; this file is one place to read
# and one place to change, which is the same reasoning the project already uses
# for its placeholder props (`training_build.gd`).

const KEY_DEBUG := KEY_F3
const KEY_ADVANCE := KEY_E

const COLOUR_TEXT := Color(0.94, 0.96, 0.97)
const COLOUR_DIM := Color(0.68, 0.76, 0.78)
const COLOUR_ACCENT := Color(0.88, 0.76, 0.52)
const COLOUR_SHADOW := Color(0, 0, 0, 0.85)

var _fade: ColorRect
var _subtitle_box: PanelContainer
var _speaker_label: Label
var _utterance: Label
var _objective_label: Label
var _prompt_label: Label
var _toast_box: VBoxContainer
var _toast_title: Label
var _toast_sub: Label
var _quest_box: PanelContainer
var _quest_title: Label
var _quest_body: Label
var _health_box: VBoxContainer
var _health_bar: ProgressBar
var _health_caption: Label
var _debug_label: Label

var _subtitle_left := 0.0
var _objective_left := 0.0
var _toast_left := 0.0
var _quest_left := 0.0

var _lines: Array = []
var _line_index := -1
var _line_left := 0.0
var _in_dialogue := false
var _debug_shown := false
var _health_shown := false

signal dialogue_closed()


func _ready() -> void:
	layer = 10
	_build_fade()
	_build_hud()
	set_process(true)


# --------------------------------------------------------------------- build

func _build_fade() -> void:
	_fade = ColorRect.new()
	_fade.name = "Fade"
	_fade.color = Color(0, 0, 0, 1)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_fade)


func _build_hud() -> void:
	# --- objective: one line, top centre -----------------------------------
	_objective_label = _label("Objective", 22, COLOUR_ACCENT)
	_objective_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_objective_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_objective_label.position = Vector2(-330, 54)
	_objective_label.custom_minimum_size = Vector2(660, 0)
	_objective_label.visible = false
	add_child(_objective_label)

	# --- interaction prompt: nothing more than the key and the verb --------
	_prompt_label = _label("Prompt", 20, COLOUR_TEXT)
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_prompt_label.position = Vector2(-240, 42)
	_prompt_label.custom_minimum_size = Vector2(480, 0)
	_prompt_label.visible = false
	add_child(_prompt_label)

	# --- subtitle: the speaker's name above the line, bottom centre --------
	_subtitle_box = PanelContainer.new()
	_subtitle_box.name = "Subtitle"
	_subtitle_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_subtitle_box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_subtitle_box.position = Vector2(-400, -168)
	_subtitle_box.custom_minimum_size = Vector2(800, 0)
	_subtitle_box.add_theme_stylebox_override("panel", _panel_style(0.58))
	_subtitle_box.visible = false
	add_child(_subtitle_box)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	_subtitle_box.add_child(col)
	_speaker_label = _label("Speaker", 16, COLOUR_ACCENT)
	col.add_child(_speaker_label)
	# NOT `_label("", ...)`. `Node.set_name("")` is an engine ERROR ("Condition
	# name.is_empty() is true"), so a deliberately anonymous label is not a thing
	# you can have - pass a name you will never look up instead. The engine does
	# not care what it is; it only cares that it is not empty.
	_utterance = _label("Utterance", 22, COLOUR_TEXT)
	_utterance.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_utterance)

	# --- toast: the acquisition moment, and only that ----------------------
	_toast_box = VBoxContainer.new()
	_toast_box.name = "Toast"
	_toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_toast_box.position = Vector2(-300, -140)
	_toast_box.custom_minimum_size = Vector2(600, 0)
	_toast_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_toast_box.add_theme_constant_override("separation", 4)
	_toast_box.visible = false
	add_child(_toast_box)
	_toast_title = _label("ToastTitle", 30, COLOUR_TEXT)
	_toast_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_box.add_child(_toast_title)
	_toast_sub = _label("ToastSub", 18, COLOUR_ACCENT)
	_toast_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_box.add_child(_toast_sub)

	# --- quest card: the end of the sequence ------------------------------
	_quest_box = PanelContainer.new()
	_quest_box.name = "QuestCard"
	_quest_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_quest_box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_quest_box.position = Vector2(-280, -90)
	_quest_box.custom_minimum_size = Vector2(560, 0)
	_quest_box.add_theme_stylebox_override("panel", _panel_style(0.66))
	_quest_box.visible = false
	add_child(_quest_box)
	var qcol := VBoxContainer.new()
	qcol.add_theme_constant_override("separation", 8)
	_quest_box.add_child(qcol)
	_quest_title = _label("QuestTitle", 18, COLOUR_ACCENT)
	_quest_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	qcol.add_child(_quest_title)
	_quest_body = _label("QuestBody", 26, COLOUR_TEXT)
	_quest_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	qcol.add_child(_quest_body)

	# --- health: drawn last, shown last -----------------------------------
	_health_box = VBoxContainer.new()
	_health_box.name = "Health"
	_health_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_health_box.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_health_box.position = Vector2(36, -76)
	_health_box.custom_minimum_size = Vector2(280, 0)
	_health_box.add_theme_constant_override("separation", 4)
	_health_box.visible = false
	add_child(_health_box)
	_health_caption = _label("HealthCaption", 14, COLOUR_DIM)
	_health_caption.text = "生命"
	_health_box.add_child(_health_caption)
	_health_bar = ProgressBar.new()
	_health_bar.custom_minimum_size = Vector2(280, 12)
	_health_bar.max_value = 100.0
	_health_bar.value = 100.0
	_health_bar.show_percentage = false
	_health_box.add_child(_health_bar)

	# --- debug: off unless asked (§28) ------------------------------------
	_debug_label = _label("Debug", 14, Color(0.62, 0.92, 0.72))
	_debug_label.position = Vector2(16, 16)
	_debug_label.visible = false
	add_child(_debug_label)


func _label(node_name: String, size: int, colour: Color) -> Label:
	var l := Label.new()
	# `Node.set_name("")` is an engine ERROR, not a no-op, so an empty name is
	# substituted rather than passed through. This helper builds eleven labels and
	# a future one will inevitably be called with "" by an author who wants an
	# anonymous label; the whole point is that they cannot have one, quietly.
	l.name = node_name if not node_name.is_empty() else "Label"
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", colour)
	l.add_theme_color_override("font_shadow_color", COLOUR_SHADOW)
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 2)
	return l


func _panel_style(alpha: float) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.03, 0.05, 0.06, alpha)
	s.border_color = Color(0.55, 0.72, 0.75, 0.28)
	s.set_border_width_all(1)
	s.set_corner_radius_all(2)
	s.set_content_margin_all(14)
	return s


# ================================================================ public API

## Fade the world in. The first playable opens on black and takes 1.2 s to
## arrive, which is the "短暂淡黑" the menu hands over to (§1) and also the
## space in which the region finishes building behind the curtain.
func fade_in(seconds := 1.2) -> void:
	_fade.visible = true
	_fade.color.a = 1.0
	var t := create_tween()
	t.tween_property(_fade, "color:a", 0.0, seconds)
	t.tween_callback(func() -> void: _fade.visible = false)


func fade_out(seconds := 0.6) -> void:
	_fade.visible = true
	var c := _fade.color
	c.a = 0.0
	_fade.color = c
	var t := create_tween()
	t.tween_property(_fade, "color:a", 1.0, seconds)


func objective(text: String) -> void:
	if text == "":
		_objective_label.visible = false
		_objective_left = 0.0
		return
	_objective_label.text = text
	_objective_label.visible = true
	# Long enough to read twice. The banner is the player's only instruction, so
	# it does not fade on the same beat as a line of dialogue.
	_objective_left = 6.0


func prompt(text: String) -> void:
	if text == "":
		_prompt_label.visible = false
		return
	_prompt_label.text = text
	_prompt_label.visible = true


## One-shot line, no input. `hold` is how long it stays before it starts fading.
func subtitle(speaker: String, text: String, hold: float) -> void:
	if _in_dialogue:
		return
	_speaker_label.text = speaker
	_speaker_label.visible = speaker != ""
	_utterance.text = text
	_subtitle_box.visible = true
	_subtitle_box.modulate.a = 1.0
	_subtitle_left = maxf(hold, 0.8)
	_prompt_label.visible = false


## A block the player advances. Each entry is {speaker, text, hold}; `hold` is
## the MINIMUM time before the advance key is accepted, so a line cannot be
## skipped by the key that started the conversation.
func open_dialogue(lines: Array) -> void:
	_lines = lines
	_line_index = -1
	_in_dialogue = true
	_next_line()


func is_talking() -> bool:
	return _in_dialogue


## Called by the world when the player used E/Space to advance. Returns whether
## the key was consumed, so the caller knows whether to mark the input handled.
func advance_dialogue() -> bool:
	if not _in_dialogue:
		return false
	if _line_left > 0.0:
		return true
	_next_line()
	return true


func _next_line() -> void:
	_line_index += 1
	if _line_index >= _lines.size():
		_close_dialogue()
		return
	var row: Dictionary = _lines[_line_index]
	_speaker_label.text = String(row.get("speaker", ""))
	_speaker_label.visible = _speaker_label.text != ""
	_utterance.text = String(row.get("text", ""))
	_subtitle_box.visible = true
	_subtitle_box.modulate.a = 1.0
	_line_left = maxf(float(row.get("hold", 1.6)), 0.6) * 0.55


func _close_dialogue() -> void:
	_in_dialogue = false
	_lines = []
	_line_index = -1
	_subtitle_box.visible = false
	dialogue_closed.emit()


func toast(title: String, subtext: String) -> void:
	_toast_title.text = title
	_toast_sub.text = subtext
	_toast_sub.visible = subtext != ""
	_toast_box.visible = true
	_toast_box.modulate.a = 1.0
	_toast_left = 3.0


func quest(title: String, body: String) -> void:
	_quest_title.text = title
	_quest_body.text = body
	_quest_box.visible = true
	_quest_box.modulate.a = 1.0
	_quest_left = 6.0


func show_health(value: float, maximum: float) -> void:
	if not _health_shown:
		_health_shown = true
		_health_box.visible = true
	_health_bar.max_value = maxf(maximum, 1.0)
	_health_bar.value = clampf(value, 0.0, maximum)


func set_debug_line(text: String) -> void:
	_debug_label.text = text


# ==================================================================== runtime

func _process(delta: float) -> void:
	# ---- EVERY CARD HAS A HOLD AND A FADE, AND THE TWO ARE SEPARATE TESTS ----
	#
	# THE OBVIOUS SHAPE IS WRONG AND IT IS WRONG SILENTLY. Write it as
	#
	#     if left > 0.0:
	#         left -= delta
	#         if left <= 0.0:
	#             alpha -= delta * rate      # <- the fade
	#
	# and the fade runs for exactly ONE FRAME. On the frame the hold reaches zero
	# the outer test is still true, so the fade branch is entered and subtracts
	# `delta * rate` from an alpha of 1.0. On the very next frame `left` is
	# already 0.0, the outer test is false, and the fade never runs again: the
	# card is pinned on screen at alpha 0.995 for the rest of the session.
	#
	# Measured, not reasoned about: a "已装备" toast raised at the sword rack was
	# still drawn in the frame after the first fight - thirty seconds and five
	# story stages later - with the mission-updated card on top of it, the two
	# sets of text overlapping and neither readable. `left` was reaching 0.0
	# perfectly on time the whole while.
	#
	# So the hold and the fade are tested SEPARATELY, and the fade continues
	# after the hold has expired.
	if _subtitle_left > 0.0:
		_subtitle_left = maxf(0.0, _subtitle_left - delta)
	if _subtitle_left <= 0.0 and not _in_dialogue:
		_fade_card(_subtitle_box, delta * 1.6)
	if _in_dialogue:
		if _line_left > 0.0:
			_line_left = maxf(0.0, _line_left - delta)
		# The "press E" hint is the contract: the box does not close on its own.
		_prompt_label.visible = false
	if _objective_left > 0.0:
		_objective_left = maxf(0.0, _objective_left - delta)
	if _objective_left <= 0.0:
		_objective_label.visible = false
	if _toast_left > 0.0:
		_toast_left = maxf(0.0, _toast_left - delta)
	if _toast_left <= 0.0:
		_fade_card(_toast_box, delta * 0.8)
	if _quest_left > 0.0:
		_quest_left = maxf(0.0, _quest_left - delta)
	if _quest_left <= 0.0:
		_fade_card(_quest_box, delta * 0.5)


## One step of a card's fade. Safe to call on a card that is not showing, which
## is what lets every caller be a flat pair of tests with no nesting.
func _fade_card(card: Control, amount: float) -> void:
	if not card.visible:
		return
	card.modulate.a = maxf(0.0, card.modulate.a - amount)
	if card.modulate.a <= 0.01:
		card.visible = false


## `_input` RATHER THAN `_unhandled_input`, AND WHY THAT IS NOT A STYLE CHOICE.
##
## The project binds `cast_selected` to E (CombatController) and `interact` to E
## (every rack and gate). In a scene that mounts a Player, both actions fire on
## the same key, and which one wins would then depend on node order in the tree -
## i.e. on nothing a reader can see. `_input` runs BEFORE `_unhandled_input`, so
## taking the key here and marking it handled makes the outcome deterministic and
## local: while a dialogue is open, E is "continue" and nothing else.
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if (event as InputEventKey).keycode == KEY_DEBUG:
			_debug_shown = not _debug_shown
			_debug_label.visible = _debug_shown
			get_viewport().set_input_as_handled()
			return
	if not _in_dialogue:
		return
	if event.is_action_pressed("ui_accept") \
			or (event is InputEventKey and event.pressed and not event.echo
				and (event as InputEventKey).keycode == KEY_ADVANCE) \
			or (event is InputEventMouseButton and event.pressed):
		advance_dialogue()
		get_viewport().set_input_as_handled()
