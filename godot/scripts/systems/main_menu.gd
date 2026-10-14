extends Control

## THE TITLE SCREEN. Three doors, ordered by how much they are "the game".
##
##   New Game  — MistvalePlaza: the FIRST PLAYABLE SEQUENCE. This is the game.
##   Region    — MistvalePlayable: the imported UE5 town, with the real Player.
##               It used to open MistvaleRegion, the blockout map walker, which
##               is geography and has no player in it. Now that the town is real
##               and its golden route has been measured walkable end to end, the
##               door opens the place the game is set in rather than the blockout
##               of it.
##   Sandbox   — the combat instrument, and the third door keeps its old name
##               because that is what a player calls it. What is behind it is now
##               the LD-02 training compound rather than `CombatSandbox.tscn`:
##               the 24 m arena had no ground, no sky texture and one dummy
##               standing on the walking line, so it could answer questions about
##               fighting and about nothing else. The compound is a superset —
##               same director stack, plus racks, a combat court, a duel ring,
##               the terrain park, a long range and a gate into the region.
##               `main_flow.gd` holds the one line that decides this.
##
## The subtitle used to read COMBAT SANDBOX, which described the sandbox rather
## than the product and was the wrong first impression for the one screen every
## player sees. It now names the prologue the New Game button actually opens.

signal new_game_pressed
signal start_pressed
signal region_pressed
signal settings_pressed
signal exit_pressed


func _ready() -> void:
	var background := ColorRect.new()
	background.color = Color("0b1b20")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var rows := VBoxContainer.new()
	rows.position = Vector2(80, 140)
	rows.custom_minimum_size = Vector2(360, 320)
	add_child(rows)
	var title := Label.new()
	title.text = "SEKAI  ·  世界之外"
	title.add_theme_font_size_override("font_size", 32)
	rows.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "序章  ·  雾栖镇"
	rows.add_child(subtitle)
	# The first door, and the only one that is the game rather than a tool.
	_add_button(rows, "开始游戏", func() -> void: new_game_pressed.emit())
	# The second door. It now opens the imported UE5 town with the real Player in
	# it, so the label no longer offers "map roaming" — the blockout walker it
	# used to describe is still on disk but is no longer what the button reaches.
	# The third door goes to the training compound — a 112 x 78 m
	# place with ground under it — and the label now says so, because a button
	# labelled 战斗沙盒 that opens a room signed TRAINING GROUND is a label that
	# has stopped describing its destination.
	_add_button(rows, "探索雾谷（城镇）", func() -> void: region_pressed.emit())
	_add_button(rows, "进入战斗沙盒（训练场）", func() -> void: start_pressed.emit())
	_add_button(rows, "设置", func() -> void: settings_pressed.emit())
	_add_button(rows, "退出", func() -> void: exit_pressed.emit())


func _add_button(parent: VBoxContainer, title: String, callback: Callable) -> void:
	var button := Button.new()
	button.text = title
	button.custom_minimum_size = Vector2(300, 48)
	button.pressed.connect(callback)
	parent.add_child(button)
