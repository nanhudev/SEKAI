extends CanvasLayer
class_name ParryDebugOverlay
# Developer-mode timing readout for perfect guard.
#
# The design rule is that a player must be able to READ when to parry, not
# memorise it. This overlay exists so we can verify that readability with real
# numbers instead of arguing about it: it shows the enemy's wind-up / active
# / recover window and the player's own perfect-guard window on the same time
# axis, in developer mode only.

@onready var sandbox: Node3D = get_parent()
@onready var player: CharacterBody3D = sandbox.get_node("Player")
@onready var combat: CombatController = player.get_node("CombatController")
@onready var dummy: Node3D = sandbox.get_node("TechnicalDummy")

var panel: PanelContainer
var label: Label
var bar: ProgressBar
var visible_now := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 3
	panel = PanelContainer.new()
	panel.position = Vector2(20, 320)
	panel.visible = false
	add_child(panel)
	var rows := VBoxContainer.new()
	panel.add_child(rows)
	label = Label.new()
	label.custom_minimum_size = Vector2(320, 0)
	rows.add_child(label)
	bar = ProgressBar.new()
	bar.custom_minimum_size = Vector2(320, 12)
	bar.max_value = 1.0
	bar.show_percentage = false
	rows.add_child(bar)


func toggle() -> void:
	visible_now = not visible_now
	panel.visible = visible_now


func _process(_delta: float) -> void:
	if not visible_now:
		return
	var guard := combat.moveset.guard
	var window := guard.perfect_guard_window
	if combat.enhance_left > 0.0:
		window += combat.enhance_perfect_guard_bonus
	var enemy_phase: StringName = &"-"
	var enemy_progress := 0.0
	if dummy.has_method("attack_phase"):
		enemy_phase = dummy.call("attack_phase")
		enemy_progress = dummy.call("attack_phase_progress")
	var blocking := combat.state in [CombatController.State.BLOCK, CombatController.State.PARRY]
	var remaining := 0.0
	if combat.state == CombatController.State.BLOCK:
		remaining = maxf(0.0, window - combat.state_time)
	label.text = "PARRY DEBUG\nenemy %s  %.2f\nplayer PG window %.3fs  %s\nstyle %s\n%s" % [
		enemy_phase,
		enemy_progress,
		window,
		("OPEN %.3fs" % remaining) if blocking else "closed",
		combat.moveset.display_name,
		combat.debug_state_line(),
	]
	bar.value = enemy_progress
	bar.modulate = Color(1.0, 0.4, 0.35) if enemy_phase == &"active" else Color(0.5, 0.8, 1.0)
