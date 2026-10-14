extends SceneTree
# Damage receipts, input recovery and separate cuts, through real runtime nodes.
var world: Node3D
var player: CharacterBody3D
var combat: CombatController
var receipts: Array[Dictionary] = []
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

func frames(count := 3) -> void:
	for i in count:
		await physics_frame

func run() -> void:
	world = load("res://scenes/combat/CombatSandbox.tscn").instantiate()
	root.add_child(world)
	await frames()
	player = world.get_node("Player")
	combat = player.get_node("CombatController")
	player.set_physics_process(false)
	combat.hitstop_scale = 0.0
	# Reversing before the blade is home must still finish the draw.
	var manager := player.get_node("WeaponManager")
	manager.equip_weapon(&"chain")
	await create_timer(0.30).timeout
	manager.equip_weapon(&"sword")
	await create_timer(0.50).timeout
	check(combat.equip_blend >= 0.999, "sheathe reversal stranded the blade")
	check(combat.request(&"light"), "attack rejected after sheathe reversal")
	combat.stow()
	# Inspect returns before an attack, without swallowing its buffered input.
	var inspect := InputEventAction.new()
	inspect.action = &"inspect"
	inspect.pressed = true
	Input.parse_input_event(inspect)
	await create_timer(0.15).timeout
	check(combat.inspect_mix > 0.5,"inspect input never raised the blade")
	combat.request(&"light")
	await create_timer(0.10).timeout
	check(combat.active_move != null,"inspect swallowed the gameplay interrupt")
	combat.stow()
	manager.equip_weapon(&"chain")
	await create_timer(1.95).timeout
	manager.equip_weapon(&"sword")
	await create_timer(1.43).timeout
	check(combat.equip_blend < 0.999,"draw fixture had already completed")
	check(combat.request(&"light"),"a clear blade could not cancel the final equip settle")
	combat.stow()
	combat.set_process(false)
	# An isolated real hurtbox. No feedback counter stands in for damage.
	var target := Node3D.new()
	target.name = "ReceiptTarget"
	world.add_child(target)
	target.position = player.position + Vector3(0,0,-6)
	var hurt := CombatHurtbox.build_for(target,Vector3(1.2,2.2,1.2),Vector3(0,0.95,0))
	hurt.hit_received.connect(func(hit: Dictionary): receipts.append(hit.duplicate()))
	await frames()
	combat.attack_kind = &"light"
	combat._begin_move(SwordBasic.a3(),CombatController.State.ATTACK)
	var move := combat.active_move
	# Feel V2: A3 is a single physical rising cut, not three ranged queries.
	combat.hitbox.set_active(true)
	combat.hitbox._on_area_entered(hurt)
	combat.hitbox._on_area_entered(hurt)
	var damage := 0.0
	var poise := 0.0
	for hit in receipts:
		damage += float(hit.damage)
		poise += float(hit.poise_damage)
	check(receipts.size()==1,"A3 uppercut must deliver once per target")
	check(is_equal_approx(damage,46.0),"A3 combined damage must remain 46, got %s" % damage)
	check(is_equal_approx(poise,26.0),"A3 weights must also normalize posture damage")
	check((receipts[0].slash_direction as Vector3).y > 0.75 and receipts[0].rising_cut,"A3 must carry upward reaction direction")
	print("A3 receipt: contacts=",receipts.size()," damage=",damage," poise=",poise)
	# The real Area3D delivery method must reject the second mechanism before damage.
	for wave_first in [false,true]:
		receipts.clear()
		combat._begin_move(SwordBasic.a2(),CombatController.State.ATTACK)
		var body_box := CombatHitbox.new()
		world.add_child(body_box)
		body_box.source = player
		body_box.damage = 24.0
		body_box.contact_filter = combat._accept_sword_contact
		body_box.set_active(true)
		var wave_box := CombatHitbox.new()
		world.add_child(wave_box)
		wave_box.source = player
		wave_box.damage = 24.0
		wave_box.contact_filter = combat.reach._accept_wave_contact.bind(combat.active_move,combat.reach._seen)
		wave_box.set_active(true)
		if wave_first:
			wave_box._on_area_entered(hurt)
			body_box._on_area_entered(hurt)
		else:
			body_box._on_area_entered(hurt)
			wave_box._on_area_entered(hurt)
		check(receipts.size()==1,"A2 body/wave contact order doubled actual damage")
		body_box.queue_free()
		wave_box.queue_free()
	print("A2 receipt: one actual damage delivery in both body/wave contact orders")
	# A wave retains A2 even if A3 has begun before it hits.
	receipts.clear()
	var old_move := combat.active_move
	var old_seen := combat.reach._seen
	combat._begin_move(SwordBasic.a3(),CombatController.State.ATTACK)
	var late := {"target":target,"damage":24.0,"poise_damage":19.0,"element":&"physical","source":player}
	old_seen.clear()
	check(combat.reach._accept_wave_contact(late,old_move,old_seen),"late A2 wave was incorrectly rejected")
	hurt.receive_hit(late)
	var landed: Array[StringName] = []
	combat.hit_landed.connect(func(m: SwordMove,_h:Dictionary): landed.append(m.id))
	combat._on_hitbox_landed(late)
	check(landed == [SwordBasic.A2],"late wave was attributed to A3")
	# Static targets' AI can be off while their visual reaction is still alive.
	var enemy := world.get_node("TechnicalDummy")
	enemy.set_process(false)
	enemy.sword_reaction.react({"slash_direction":Vector3.RIGHT,"damage":21.0})
	await frames(2)
	check(enemy.sword_reaction.offset.length()>0.01,"static target lost its directional flinch")
	combat.stow()
	world.queue_free()
	await frames(8)
	receipts.clear()
	late.clear()
	old_seen.clear()
	print("PASS: sword core damage and input regression" if failures.is_empty() else "FAIL: "+str(failures))
	call_deferred("quit",0 if failures.is_empty() else 1)
