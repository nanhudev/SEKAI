extends SceneTree

## HOW FAR IN FRONT OF THE BODY TO STAND, derived for the same reason as the hitbox
## test: this file used to place the player at `Vector3(0, 1.15, -0.6)`, which was
## "2.4m in front of the dummy" only while the dummy sat on the origin axis. The dummy
## was moved to `x = -2.487` and the test started reporting `Expected one perfect
## guard, got 0` — the enemy's `AttackHitbox` was firing at a point 2.49m to the
## side of the player, so nothing ever reached the guard arc.
##
## 2.4m is kept: it is the separation the guard assertions were tuned against.
const STAND_BACK := 2.4


func _stand_in_front(dummy: Node3D) -> Vector3:
	# The player faces -Z by default and the body is on the +Z side of this point.
	return Vector3(dummy.global_position.x, 1.15, dummy.global_position.z + STAND_BACK)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var sandbox: PackedScene = load("res://scenes/combat/CombatSandbox.tscn")
	var world: Node3D = sandbox.instantiate()
	root.add_child(world)
	var player: CharacterBody3D = world.get_node("Player")
	var dummy: Node3D = world.get_node("TechnicalDummy")
	var combat: CombatController = player.get_node("CombatController")
	var enemy_hitbox: CombatHitbox = dummy.get_node("AttackHitbox")
	player.global_position = _stand_in_front(dummy)
	await physics_frame
	await physics_frame
	combat.set_state(CombatController.State.BLOCK)
	enemy_hitbox.set_active(true)
	await physics_frame
	await physics_frame
	if combat.perfect_guard_count != 1:
		push_error("Expected one perfect guard, got %s" % combat.perfect_guard_count)
		quit(1)
		return
	if dummy.state != dummy.State.STAGGER:
		push_error("Enemy did not stagger after perfect guard")
		quit(1)
		return
	print("PASS: Area3D enemy hit triggers perfect guard and stagger")
	quit(0)
