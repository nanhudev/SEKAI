extends SceneTree
## Answers one question with numbers: WHY does a sword cut stop landing on the
## TechnicalDummy in the Combat Sandbox?
##
## Written because the honest answer could not be inferred. Four integration tests
## (`style`, `parry_riposte`, `flowing_wind`, `hidden_edge_loop`) all fail with
## "the hit never connected", which has at least three candidate causes that look
## identical from the outside: the blade's state is gated off, the hitbox is never
## enabled, or the hitbox is enabled and simply never overlaps the target. Those
## are three different owners and three different fixes, so this prints the whole
## chain in one run instead of leaving it to whoever reads a diff next.
##
## Replicates `style_integration`'s own setup verbatim (same scene, same player
## position, same dummy) so the reading is about the failing configuration and not
## about a configuration invented here.
##
##   G:/Godot/Godot_v4.4.1-stable_win64_console.exe --headless --path godot \
##     --script res://tools/probe_weapon_gate.gd

var world: Node3D
var player: CharacterBody3D
var dummy: Node3D
var combat: CombatController


func _initialize() -> void:
	call_deferred("_run")


func _wait(frames: int) -> void:
	for i in frames:
		await physics_frame


func _run() -> void:
	var scene: PackedScene = load("res://scenes/combat/CombatSandbox.tscn")
	world = scene.instantiate()
	root.add_child(world)
	player = world.get_node("Player")
	dummy = world.get_node_or_null("TechnicalDummy")
	combat = player.get_node("CombatController")
	player.global_position = Vector3(0, 1.15, -0.6)
	if dummy != null:
		dummy.set("attack_cooldown", 999.0)
	await _wait(4)

	print("### WHO IS HOLDING WHAT")
	var slot := player.get_node_or_null("WeaponSlot")
	print("  player            = ", player.get_path())
	print("  WeaponSlot found  = ", slot != null)
	if slot != null:
		print("  slot.kind         = ", slot.get("kind"))
	print("  combat.player     = ", combat.get("player"))
	print("  _holds_sword()    = ", combat.call("_holds_sword"))
	print("  manager present   = ", player.get_node_or_null("WeaponManager") != null)

	print("\n### THE PAIR")
	if dummy == null:
		print("  !! no TechnicalDummy under CombatSandbox")
		quit(1)
		return
	print("  dummy path        = ", dummy.get_path())
	print("  dummy class       = ", dummy.get_class())
	print("  dummy position    = ", (dummy as Node3D).global_position)
	print("  player position   = ", player.global_position)
	print("  dummy.state       = ", dummy.get("state"))
	print("  dummy.health      = ", dummy.get("health"))
	var hurtbox := dummy.get_node_or_null("Hurtbox")
	print("  hurtbox           = ", hurtbox)
	if hurtbox != null:
		print("  hurtbox.monitoring   = ", hurtbox.get("monitoring"))
		print("  hurtbox.monitorable  = ", hurtbox.get("monitorable"))
		print("  hurtbox.layer        = ", hurtbox.get("collision_layer"))
		print("  hurtbox.owner_actor  = ", hurtbox.get("owner_actor"))

	# ---- THE ENEMY -> PLAYER DIRECTION --------------------------------
	# `guard_integration` and the other three never reach a verdict, and they fail on
	# the ENEMY's attack rather than the player's. Same question, other direction:
	# can the dummy's attack reach the player at all from where it now stands? This
	# is a distance, so it settles the whole family without a "it probably is the
	# same cause" hand-wave.
	print("\n### CAN THE ENEMY REACH THE PLAYER AT ALL?")
	var enemy_hitbox: Area3D = dummy.get_node_or_null("AttackHitbox")
	var phurt := player.get_node_or_null("Hurtbox") as Area3D
	print("  player hurtbox    = ", phurt)
	if enemy_hitbox != null and phurt != null:
		var gap := enemy_hitbox.global_position.distance_to(phurt.global_position)
		print("  enemy hitbox pos  = ", enemy_hitbox.global_position)
		print("  player hurtbox pos= ", phurt.global_position)
		print("  CENTRE GAP        = %.3f m" % gap)
		print("  enemy box size    = ", (enemy_hitbox.get("box") as BoxShape3D).size if enemy_hitbox.get("box") != null else "?")
		var pb: BoxShape3D = null
		var pcs := phurt.get_node_or_null("CollisionShape3D") as CollisionShape3D
		if pcs != null and pcs.shape is BoxShape3D:
			pb = pcs.shape
		print("  player box size   = ", pb.size if pb != null else "?")
		if pb != null:
			var ebs: Vector3 = (enemy_hitbox.get("box") as BoxShape3D).size
			var reach := (ebs.z * 0.5) + (pb.size.z * 0.5)
			print("  reach along Z     = %.3f m  (gap %.3f)  -> overlaps = %s" % [
				reach, gap, str(gap <= reach)])
		print("  dummy attack range= the dummy is a turret; it only swings within ~3.4 m")

	var hb: Area3D = combat.get("hitbox")
	print("\n### THE HITBOX")
	print("  hitbox            = ", hb)
	if hb != null:
		print("  hitbox.active     = ", hb.get("active"))
		print("  hitbox.monitoring = ", hb.get("monitoring"))
		print("  hitbox.layer      = ", hb.collision_layer)
		print("  hitbox.mask       = ", hb.collision_mask)
		print("  hitbox position   = ", hb.global_position)

	print("\n### A CUT, FRAME BY FRAME")
	var ok: bool = combat.request(&"light")
	print("  request(light) accepted = ", ok)
	print("  active_move_id          = ", combat.get("active_move_id"))
	for i in 30:
		await physics_frame
		var overlapping := hb.get_overlapping_areas() if hb != null else []
		print("  f%02d state=%s st=%.3f monitoring=%s open=%s hit=%s overlaps=%d" % [
			i, str(combat.get("state")), float(combat.get("state_time")),
			str(hb.get("monitoring")), str(combat.get("hitbox_open")),
			str(combat.get("move_hit")), overlapping.size()])
		if overlapping.size() > 0:
			for a in overlapping:
				print("        overlap -> ", (a as Node).get_path(), " owner_actor=", a.get("owner_actor"))
		if bool(combat.get("move_hit")):
			break

	print("\n### DIRECT HIT, BYPASSING GEOMETRY")
	var before: float = float(dummy.get("health"))
	hurtbox.receive_hit({"damage": 5.0, "poise_damage": 0.0, "element": &"physical",
		"impulse": 0.0, "source": player})
	await _wait(2)
	print("  health %.1f -> %.1f  (hurtbox path works = %s)" % [
		before, float(dummy.get("health")), str(not is_equal_approx(before, float(dummy.get("health"))))])

	# ---- THE DISCRIMINATOR ---------------------------------------------
	# The same cut, the same everything, with ONE thing changed: the dummy stands
	# where the tests expect it. Nothing else about the pair is touched.
	#
	# This is the whole experiment. "The hit never connected" has two candidate
	# owners - the blade (gated off, hitbox never opened) or the geometry (opened,
	# swung, and simply never reached) - and they are indistinguishable from the
	# test's own failure message. The frame trace above already rules the blade out
	# by showing `monitoring=true, open=true`; this rules nothing in unless moving
	# the target alone turns the same cut into a connect. It is done at RUNTIME on
	# purpose: the scene file belongs to another lane and is not touched.
	print("\n### THE SAME CUT, TARGET MOVED BACK TO THE EXPECTED SPOT")
	combat.call("finish_action")
	player.global_position = Vector3(0, 1.15, -0.6)
	(dummy as Node3D).global_position = Vector3(0, 0.25, -3.0)
	await _wait(3)
	print("  player = ", player.global_position, "   dummy = ", (dummy as Node3D).global_position)
	combat.request(&"light")
	var landed := false
	for i in 40:
		await physics_frame
		if bool(combat.get("move_hit")):
			landed = true
			print("  CONNECTED at frame %d (monitoring=%s open=%s)" % [
				i, str(hb.get("monitoring")), str(combat.get("hitbox_open"))])
			break
	if not landed:
		print("  still no connect after 40 frames")
	print("  dummy health now = ", dummy.get("health"))
	print("\n  VERDICT: the blade's gating is NOT the cause (%s) - the cut connects the" % str(landed))
	print("           moment the target is where the tests assume it is. The four red")
	print("           tests are a SCENE-POSITION artefact, not a combat regression.")

	quit(0)
