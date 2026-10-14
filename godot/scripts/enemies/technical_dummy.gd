extends StaticBody3D
# Technical Dummy — the sword-technique test target.
#
# It exists to answer three questions, so it must TELL the player which question
# is being asked before the answer arrives:
#   Sweep  → can you dodge?
#   Heavy  → can you perfect guard?
#   Lunge  → can you hold your position?
# Every attack is therefore readable from the ring scale, the body colour, the
# wind-up length and (once audio lands) a cue. Reading must not require
# memorising timings.

signal shattered
signal attack_started(variant: int)
signal attack_phase_changed(phase: StringName)
signal element_stage_changed(element_id: StringName, stage: StringName)
signal wall_impact(strength: float)
# 聚合斩 · 这一具身体已经被判定死亡，但还没有被允许倒下. See `_iaido_strike`.
signal iaido_execution_started()

enum State { IDLE, ALERT, ATTACK, STAGGER, FROZEN, DEAD, EXECUTING }

@export var max_health := 120.0
@export var poise_limit := 50.0
# Wind is scaled by this: the same gust throws a light enemy and barely turns a
# heavy one. Element behaviour is about weight, not health.
@export var weight: StringName = ElementLibrary.WEIGHT_MEDIUM
# THE ENEMY ART / TECH CONTRACT. Left empty, this body answers with the generic
# construct profile — which is the point of §E: every enemy is answerable to the
# signature on the day it exists, not the day ART finishes authoring it.
@export var execution_profile: IaidoExecutionProfile

@onready var hurtbox: CombatHurtbox = $Hurtbox
@onready var core: MeshInstance3D = $Core
@onready var attack_hitbox: CombatHitbox = $AttackHitbox
@onready var player: CharacterBody3D = _resolve_player()

var health := 120.0
var poise := 0.0
var state := State.IDLE
var state_timer := 0.0
var attack_cooldown := 1.0
var attack_open := false
var attack_variant := -1
var attack_duration := 0.85
var attack_windup := 0.33
var attack_active_end := 0.53
var attack_shape: BoxShape3D
var cue_material := StandardMaterial3D.new()
var phase: StringName = &"idle"
# What the last hit DID to this body, for whoever landed it. See `take_hit_outcome`.
var hit_outcome: StringName = &""
# True from the instant a lethal 聚合斩 landed to the instant the director has
# taken the body over. It is the answer to "must something else be told about
# this death", and it is read ONCE, by the director, in the same frame.
var execution_pending := false
# The deep cut left by a signature that did NOT kill. §G §9: the player has to be
# able to tell that this was the strongest thing in the game even when it was
# not enough.
var deep_slash := 0.0
var sword_reaction: Node

var telegraph: MeshInstance3D
var telegraph_material: StandardMaterial3D
var telegraph_flash := 0.0
var last_interrupt := 0.0

# --- elements, as data -------------------------------------------------------
# There is no `if element == frost` anywhere below. The rules live in
# ElementLibrary as ElementDefinitions; this actor only decides what a stage
# change means for a body that can stagger, freeze and be thrown into a wall.
var element_defs: Dictionary = {}
var elements := ElementState.new()
var last_wall_impact := 0.0


func _ready() -> void:
	# Joining the group is the whole contract with 白蔷庭's Measure: the style can
	# read the distance to anything in it without knowing what an enemy is.
	add_to_group(CombatTuning.TARGET_GROUP)
	health = max_health
	element_defs = ElementLibrary.all()
	for def in element_defs.values():
		elements._entry(def)
	hurtbox.owner_actor = self
	hurtbox.hit_received.connect(_on_hit)
	attack_hitbox.source = self
	attack_shape = attack_hitbox.get_node("CollisionShape3D").shape.duplicate() as BoxShape3D
	attack_hitbox.get_node("CollisionShape3D").shape = attack_shape
	core.material_override = cue_material
	sword_reaction = preload("res://scripts/combat/sword_hit_reaction.gd").new()
	sword_reaction.name = "SwordHitReaction"
	add_child(sword_reaction)
	sword_reaction.bind(core)
	sword_reaction.add_part(get_node("Body"))
	_build_telegraph()


# A stage is allowed to own its own enemies now (see ChainLab), and a dummy that
# demanded `get_parent().get_node("Player")` could only ever live in one scene.
# Look for the sibling first because that is still the common case, then fall back
# to the group the player puts itself in.
func _resolve_player() -> CharacterBody3D:
	var sibling := get_parent().get_node_or_null("Player") as CharacterBody3D
	if sibling != null:
		return sibling
	return get_tree().get_first_node_in_group(CombatTuning.PLAYER_GROUP) as CharacterBody3D


# Convenience mirrors so debug UI and older tooling can still read a number.
# The ElementState remains the single source of truth.
var frost: float:
	get: return elements.value(ElementLibrary.FROST)
	set(value): elements.set_value(ElementLibrary.FROST, value)


var burn: float:
	get:
		var def: ElementDefinition = element_defs.get(ElementLibrary.FIRE)
		return 0.0 if def == null else (1.0 if elements.value(ElementLibrary.FIRE) > 0.0 else 0.0)
	set(value):
		var def: ElementDefinition = element_defs.get(ElementLibrary.FIRE)
		if def != null:
			elements.set_value(ElementLibrary.FIRE, 1.0 if value > 0.0 else 0.0)


func element_stage(element_id: StringName) -> StringName:
	var def: ElementDefinition = element_defs.get(element_id)
	if def == null:
		return &""
	return elements.stage_name(def)


func is_brittle() -> bool:
	return state == State.FROZEN


func is_alive() -> bool:
	# EXECUTING is not alive. The damage already landed and the body cannot act;
	# what is still standing is a picture, not a combatant. Anything that asks
	# this question gets the same answer it would get if the click had already
	# happened — which is the whole point of settling the death at the cut.
	return not _is_gone()


## Out of the fight, one way or another: dead, or dead-and-not-yet-admitted.
##
## The distinction matters to exactly one system in the game (the execution
## ceremony) and to nothing else, which is why everything that used to ask "is it
## dead" now asks this instead — a held body is not a body that may still swing.
func _is_gone() -> bool:
	return state == State.DEAD or state == State.EXECUTING


func _clear_element(element_id: StringName) -> void:
	elements.clear(element_id)


func _build_telegraph() -> void:
	# A ring at the body that grows through the wind-up and snaps shut exactly
	# when the attack becomes active. This is the parry cue.
	var mesh := TorusMesh.new()
	mesh.inner_radius = 0.72
	mesh.outer_radius = 1.0
	telegraph_material = StandardMaterial3D.new()
	telegraph_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	telegraph_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	telegraph_material.albedo_color = Color(0.5, 0.85, 1.0, 0.0)
	mesh.material = telegraph_material
	telegraph = MeshInstance3D.new()
	telegraph.name = "TelegraphRing"
	telegraph.mesh = mesh
	telegraph.rotation = Vector3(PI * 0.5, 0.0, 0.0)
	telegraph.position = Vector3(0.0, 0.3, 0.0)
	telegraph.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(telegraph)


func _process(delta: float) -> void:
	if state == State.DEAD or state == State.EXECUTING:
		# 一个已经死了的东西不再做任何决定. EXECUTING means the damage landed, the
		# AI is off, and the only thing left is for the director to let the body
		# fall — so this function has nothing to say until `reset_dummy()`.
		return
	if deep_slash > 0.0:
		deep_slash = maxf(0.0, deep_slash - delta)
	if player == null:
		# A stage with no player in it (a static target row for the chain, say).
		# It still has to react to being hit, so only the AI is skipped.
		_update_elements(delta)
		return
	state_timer = maxf(0.0, state_timer - delta)
	attack_cooldown = maxf(0.0, attack_cooldown - delta)
	if state in [State.IDLE, State.ALERT] and attack_cooldown == 0.0 and global_position.distance_to(player.global_position) < 3.4:
		_start_attack()
	if state == State.ATTACK:
		var elapsed := attack_duration - state_timer
		var should_open := elapsed >= attack_windup and elapsed < attack_active_end
		if should_open != attack_open:
			attack_open = should_open
			attack_hitbox.set_active(should_open)
			if should_open:
				telegraph_flash = 1.0
				_set_phase(&"active")
			else:
				_set_phase(&"recover")
		elif not attack_open:
			_set_phase(&"windup")
		if attack_variant == 2 and should_open:
			global_position += global_transform.basis.z * 8.0 * delta
		if state_timer == 0.0:
			state = State.ALERT
			attack_hitbox.set_active(false)
			attack_open = false
			core.scale = Vector3.ONE
			_set_phase(&"idle")
	if state == State.STAGGER and state_timer == 0.0:
		state = State.ALERT
		_set_phase(&"idle")
	if state == State.FROZEN and state_timer == 0.0:
		state = State.ALERT
		_clear_element(ElementLibrary.FROST)
		_set_phase(&"idle")
	_update_elements(delta)
	core.rotation.y += delta * (0.0 if state == State.FROZEN else 0.6)
	_update_cue(delta)


func _update_elements(delta: float) -> void:
	# All element bookkeeping is data-driven. This function never asks what an
	# element "means"; it asks the ElementState what changed.
	if state == State.EXECUTING:
		return
	var report := elements.update(delta)
	var tick := float(report["tick_damage"])
	if tick > 0.0:
		health -= tick
		poise += float(report["tick_poise"])
	for def in report["expired"]:
		element_stage_changed.emit((def as ElementDefinition).id, &"normal")
	for change in report["transitions"]:
		var def: ElementDefinition = change["def"]
		var to_stage := int(change["to"])
		var name := def.stage_names[to_stage] if def.has_ladder() else &""
		element_stage_changed.emit(def.id, name)
	if last_wall_impact > 0.0:
		last_wall_impact = maxf(0.0, last_wall_impact - delta)
	if health <= 0.0:
		_die()
		return
	if poise >= poise_limit and state != State.FROZEN:
		poise = 0.0
		state = State.STAGGER
		state_timer = 0.6
		_open_idle()


func _die() -> void:
	if state == State.EXECUTING:
		# The body is already dead by damage and is being held upright on purpose.
		# Hiding it here would delete the one thing the ceremony is about.
		return
	state = State.DEAD
	attack_hitbox.set_active(false)
	visible = false
	hurtbox.monitorable = false
	telegraph.visible = false
	_set_phase(&"dead")


func _update_cue(delta: float) -> void:
	telegraph_flash = maxf(0.0, telegraph_flash - delta * 5.0)
	if state == State.ATTACK and not attack_open:
		var preparation := clampf((attack_duration - state_timer) / attack_windup, 0.0, 1.0)
		core.scale = Vector3.ONE * (1.0 + preparation * (0.28 if attack_variant == 1 else 0.16))
		cue_material.albedo_color = Color(1.0, 0.45, 0.2).lerp(Color(1.0, 0.15, 0.08), preparation) if attack_variant == 1 else Color(0.4, 0.85, 1.0).lerp(Color(0.9, 1.0, 1.0), preparation)
		# The ring contracts onto the body as the strike approaches: the frame
		# it disappears is the frame the attack goes live.
		var shrink := 1.25 - preparation * 0.45
		telegraph.scale = Vector3.ONE * shrink
		var glow := 0.10 + preparation * preparation * 0.55
		telegraph_material.albedo_color = Color(0.55, 0.9, 1.0, glow)
	else:
		core.scale = core.scale.lerp(Vector3.ONE, minf(1.0, delta * 12.0))
		# Tint comes from the element definitions, so adding an element never
		# means editing the enemy again.
		var elemental_color := Color(0.5, 0.75, 0.8)
		for key in elements.active_ids():
			var def: ElementDefinition = element_defs[key]
			if def != null:
				elemental_color = elemental_color.lerp(def.tint, 0.55)
		cue_material.albedo_color = elemental_color
		var flash_scale := 1.0 + telegraph_flash * 1.4
		telegraph.scale = Vector3.ONE * flash_scale
		telegraph_material.albedo_color = Color(1.0, 0.96, 0.86, telegraph_flash * 0.85)
	if last_interrupt > 0.0:
		last_interrupt = maxf(0.0, last_interrupt - delta)
		telegraph_material.albedo_color = Color(1.0, 0.85, 0.4, 0.7)


func _set_phase(next: StringName) -> void:
	if phase == next:
		return
	phase = next
	attack_phase_changed.emit(phase)


func _start_attack() -> void:
	attack_variant = (attack_variant + 1) % 3
	state = State.ATTACK
	attack_open = false
	var to_player := player.global_position - global_position
	rotation.y = atan2(to_player.x, to_player.z)
	match attack_variant:
		0: # broad sweep, readable dodge check
			attack_duration = 0.82
			attack_windup = 0.38
			attack_active_end = 0.56
			attack_shape.size = Vector3(3.0, 1.4, 1.6)
			attack_hitbox.damage = 12.0
			attack_hitbox.poise_damage = 12.0
		1: # longer heavy windup, perfect-guard check
			attack_duration = 1.05
			attack_windup = 0.64
			attack_active_end = 0.79
			attack_shape.size = Vector3(1.8, 1.7, 2.2)
			attack_hitbox.damage = 22.0
			attack_hitbox.poise_damage = 40.0
		2: # forward lunge, repositioning check
			attack_duration = 0.9
			attack_windup = 0.47
			attack_active_end = 0.63
			attack_shape.size = Vector3(1.4, 1.5, 2.0)
			attack_hitbox.damage = 15.0
			attack_hitbox.poise_damage = 18.0
	state_timer = attack_duration
	attack_cooldown = 1.6
	_set_phase(&"windup")
	attack_started.emit(attack_variant)


	# 6) The body tells the attacker what it just became.
	#
	# A hit has always travelled one way: the hitbox delivers a dictionary and
	# learns nothing back, so the sword could only ever answer its own numbers
	# and never what it DID. Shatter is the loudest thing that can happen in this
	# game and it was invisible to the hand that caused it — same sound, same
	# stop, same shake as poking a stranger. This is read ONCE, by whoever landed
	# the hit, and cleared on read: it is an answer to a question, not a state
	# anyone may poll.
	hit_outcome = &"interrupt"


# Read once, cleared on read: see `hit_outcome`.
func take_hit_outcome() -> StringName:
	var taken := hit_outcome
	hit_outcome = &""
	return taken


# Whether this body is currently frozen solid - the ONE thing the audio line asks a
# body about itself.
#
# It is a duck-typed contract rather than a state read, and that is the point: the
# audio director must not know what a TechnicalDummy is, and any future actor that
# can be frozen earns shatter audio for free by answering this method. Without it, a
# blade landing on frozen matter had no way to hear the difference between ice and a
# body, so SHATTER could not be triggered by the thing the brief says causes it.
func is_frozen() -> bool:
	return state == State.FROZEN


func _on_hit(hit: Dictionary) -> void:
	if state == State.DEAD or state == State.EXECUTING:
		return
	hit_outcome = &"hit"
	if sword_reaction != null:
		sword_reaction.react(hit)
	# ---- 聚合斩 · THE SIGNATURE IS NOT JUST A BIG NUMBER ---------------------
	#
	# Checked FIRST, before every interaction below, and deliberately so. A frozen
	# construct being shattered and a construct being cut in half by the same
	# blade are not the same event, and the signature is the one that gets to say
	# what happened to the body: §H of the brief, 不能用普通死亡表现.
	if hit.get("iaido", false):
		_iaido_strike(hit)
		return
	var element_id: StringName = hit.get("element", &"physical")
	var def: ElementDefinition = element_defs.get(element_id)
	var heavy: bool = float(hit.get("poise_damage", 0.0)) >= 35.0
	var frozen := state == State.FROZEN
	var frost_def: ElementDefinition = element_defs.get(ElementLibrary.FROST)
	var frost_stage := elements.stage_index(frost_def)

	# 1) The reference combo. A frozen target is brittle: the heavy follow-up is
	#    what cashes in the setup the player built. This is the one interaction
	#    every other one is measured against.
	if frozen and heavy:
		var shatter_damage := 55.0 * float(hit.get("frozen_bonus", 1.0))
		health -= shatter_damage
		hit_outcome = &"shatter"
		_clear_element(ElementLibrary.FROST)
		state = State.STAGGER
		state_timer = 1.0
		attack_hitbox.set_active(false)
		_open_idle()
		shattered.emit()
		if health <= 0.0:
			_die()
		return

	# 2) Brittle Break: a heavy landing on a merely FROSTED target breaks the
	#    brittle layer for real damage. Not Frozen — deliberately a rung earlier,
	#    so 藏锋's heavy has a reason to exist against frost that is not Shatter.
	if heavy and frost_stage >= 2 and frost_stage < 3:
		hit_outcome = &"brittle"
		damage_brittle_break(hit)
		return

	# 3) Ordinary damage.
	var damage := float(hit.get("damage", 0.0))
	if frozen:
		damage *= float(hit.get("frozen_bonus", 1.0))
	if def != null:
		damage += def.impact_damage
	health -= damage
	poise += float(hit.get("poise_damage", 0.0))

	if hit.get("interrupt", false):
		# 断章: cutting an action in half has to actually stop it.
		attack_hitbox.set_active(false)
		attack_open = false
		state = State.STAGGER
		state_timer = 0.95
		poise = 0.0
		last_interrupt = 0.5
		_open_idle()

	if def != null:
		_apply_element(def, hit)

	if health <= 0.0:
		_die()
		return
	if poise >= poise_limit and state != State.FROZEN:
		poise = 0.0
		state = State.STAGGER
		state_timer = 0.6
		_open_idle()


# ===================================================================== 聚合斩
# THE ENEMY'S HALF OF THE EXECUTION CONTRACT.
#
# Two questions, answered here and nowhere else: did this blade actually kill me,
# and am I a body that can be cut. Everything after that — the held pose, the
# cross-section, the fall on the sheath click — belongs to `IaidoExecution`, and
# the clock belongs to the director. This actor owns no part of the performance;
# it owns the DECISION, which is the only part that has to be per-enemy.

## What happens to THIS body when the signature kills it. §E of the brief.
func iaido_execution_profile() -> IaidoExecutionProfile:
	if execution_profile != null:
		return execution_profile
	return IaidoExecutionLibrary.construct()


## True in the frame a lethal signature landed and until the director has taken
## the body over. Read ONCE, like `take_hit_outcome`.
func expects_iaido_execution() -> bool:
	return execution_pending and state == State.EXECUTING


func _iaido_strike(hit: Dictionary) -> void:
	# DAMAGE IS SETTLED AT THE CUT, NOT AT THE CLICK. §O of the brief: the enemy
	# is dead now — the only thing the click is allowed to change is whether
	# anyone can see it. A body that stayed fully combat-capable through three
	# seconds of ceremony because its death was "scheduled" would be a bug the
	# player experiences as being hit by a corpse.
	var damage := float(hit.get("damage", 0.0))
	health -= damage
	poise = 0.0
	attack_hitbox.set_active(false)
	attack_open = false
	if state == State.FROZEN or state == State.STAGGER:
		_open_idle()

	var profile := iaido_execution_profile()
	if health <= 0.0 and profile != null and profile.is_supported():
		_enter_execution_hold(profile)
		return
	# 9 · NON-LETHAL. Never a fake cleave: the刀 was strong and the body survived
	# it, and the player has to be able to read that from the body rather than
	# from a damage number.
	_iaido_deep_slash(hit)


func _enter_execution_hold(profile: IaidoExecutionProfile) -> void:
	# Everything that could make this body act is switched off in one place.
	# §O: AI disabled, hitbox disabled, damage disabled, movement locked — the
	# visual is what is being held, not the threat.
	state = State.EXECUTING
	state_timer = 0.0
	attack_hitbox.set_active(false)
	attack_open = false
	telegraph.visible = false
	hurtbox.monitorable = false
	execution_pending = true
	hit_outcome = &"iaido_execution"
	_set_phase(&"executed")
	iaido_execution_started.emit()


func _iaido_deep_slash(hit: Dictionary) -> void:
	hit_outcome = &"iaido_deep_slash"
	deep_slash = 1.2
	state = State.STAGGER
	state_timer = 1.2
	poise = 0.0
	last_interrupt = 0.9
	attack_hitbox.set_active(false)
	attack_open = false
	_open_idle()
	if health <= 0.0:
		# A body that cannot be cut still dies of it — it just dies normally, and
		# that is the correct answer for an enemy whose contract says "no".
		_die()
		return
	_show_deep_slash_mark(hit)


## The one thing a signature that failed to kill is allowed to leave behind: a
## cut that is unmistakably the size of the weapon that made it.
func _show_deep_slash_mark(hit: Dictionary) -> void:
	var mark := ShadowCutMark.new()
	var length := maxf(1.1, (core.global_position - global_position).length() * 2.0)
	mark.setup(length, deg_to_rad(-30.0), Color(0.94, 0.90, 0.82))
	add_child(mark)
	mark.global_position = core.global_position
	# 一刀一条线. The mark is laid onto the SAME plane the world was cut on, so a
	# signature that failed to kill still reads as the same weapon: one plane,
	# drawn on a body instead of on the world. The mark's long axis is its local
	# +Y, so the basis is built from the plane's own two directions.
	var normal: Variant = hit.get("cut_normal")
	var line: Variant = hit.get("cut_line")
	if normal is Vector3 and line is Vector3:
		var n: Vector3 = (normal as Vector3)
		var l: Vector3 = (line as Vector3)
		if n.length_squared() > 0.5 and l.length_squared() > 0.5:
			n = n.normalized()
			l = l.normalized()
			mark.global_transform = Transform3D(Basis(l.cross(n), l, n), mark.global_position)
	mark.activate()


func damage_brittle_break(hit: Dictionary) -> void:
	# Frosted → a real heavy. The brittle layer shatters for posture rather than
	# health, which is what makes Frost a setup for a stagger, not for damage.
	var frost_def: ElementDefinition = element_defs.get(ElementLibrary.FROST)
	var bonus := frost_def.brittle_bonus if frost_def != null else 1.0
	var damage := float(hit.get("damage", 0.0))
	if frost_def != null and frost_def.enables_brittle:
		damage *= bonus
	health -= damage
	_clear_element(ElementLibrary.FROST)
	poise = 0.0
	state = State.STAGGER
	state_timer = 0.95
	attack_hitbox.set_active(false)
	attack_open = false
	last_interrupt = 0.4
	_open_idle()
	if health <= 0.0:
		_die()


func _apply_element(def: ElementDefinition, hit: Dictionary) -> void:
	if def.has_ladder() or def.applies_per_hit > 0.0:
		# The spell decides how much of the element it delivers, not the target.
		# A sword hit and a spell both arrive here as 1.0, which is why 寒流 needs
		# three casts to freeze something and 凝霜 needs one.
		var amount := def.applies_per_hit * float(hit.get("element_scale", 1.0))
		var stage := elements.apply(def, amount)
		var name := def.stage_names[stage] if def.has_ladder() else &""
		element_stage_changed.emit(def.id, name)
		if def.is_final_stage(stage):
			# Frozen is a beat, not a switch-off: short, and it leaves the target
			# brittle rather than removed from the fight.
			state = State.FROZEN
			state_timer = def.final_stage_duration
			attack_hitbox.set_active(false)
			attack_open = false
			_open_idle()
			return
		if def.final_stage_staggers:
			state = State.STAGGER
			state_timer = 0.25
			attack_hitbox.set_active(false)
			_open_idle()

	# A damage-over-time element is switched ON rather than climbed, so hold it at
	# a non-zero value and let ElementState tick it down.
	if def.tick_damage > 0.0:
		elements.refresh_dot(def)
		elements.set_value(def.id, maxf(elements.value(def.id), 1.0))

	if def.pushes:
		_push_from(def, hit)


func _push_from(def: ElementDefinition, hit: Dictionary) -> void:
	var source: Node3D = hit.get("source")
	if source == null:
		return
	var away := global_position - source.global_position
	away.y = 0.0
	if away.length_squared() <= 0.01:
		return
	var scale := ElementLibrary.push_scale_for(weight) if def.push_weight_scaled else 1.0
	var applied := float(hit.get("impulse", 0.0)) * scale
	if applied <= 0.0:
		return
	# Move for real, so a wall can stop it. Being thrown into something is the
	# payoff of wind, and it only exists if the environment can interrupt it.
	var collision := move_and_collide(away.normalized() * applied)
	if collision != null:
		var strength := clampf(applied / 4.0, 0.2, 1.5)
		last_wall_impact = strength
		poise += 30.0 * strength
		state = State.STAGGER
		state_timer = 0.75 * strength
		wall_impact.emit(strength)
	else:
		state = State.STAGGER
		state_timer = 0.45
	attack_hitbox.set_active(false)
	attack_open = false
	_open_idle()


func _open_idle() -> void:
	_set_phase(&"idle")


# ------------------------------------------------------------- readable state

func is_telegraphing() -> bool:
	# True from the start of the wind-up until the strike goes live: 断章 only
	# matters if it lands in this window.
	return state == State.ATTACK and not attack_open


func is_striking() -> bool:
	return state == State.ATTACK and attack_open


func attack_phase() -> StringName:
	return phase


func attack_phase_progress() -> float:
	if state != State.ATTACK:
		return 0.0
	var elapsed := attack_duration - state_timer
	if not attack_open:
		return clampf(elapsed / maxf(attack_windup, 0.001), 0.0, 1.0)
	return clampf((elapsed - attack_windup) / maxf(attack_active_end - attack_windup, 0.001), 0.0, 1.0)


func force_attack(variant: int) -> void:
	if _is_gone():
		return
	attack_variant = ((variant - 1) + 3) % 3
	attack_cooldown = 0.0
	_start_attack()


func on_interrupted(stagger: float) -> void:
	if _is_gone():
		return
	attack_hitbox.set_active(false)
	attack_open = false
	state = State.STAGGER
	state_timer = stagger
	_open_idle()


func reset_dummy() -> void:
	if sword_reaction != null:
		sword_reaction.reset()
	health = max_health
	poise = 0.0
	elements.clear_all()
	state = State.IDLE
	state_timer = 0.0
	attack_cooldown = 1.0
	attack_variant = -1
	attack_hitbox.set_active(false)
	visible = true
	hurtbox.monitorable = true
	telegraph.visible = true
	last_interrupt = 0.0
	last_wall_impact = 0.0
	execution_pending = false
	deep_slash = 0.0
	# A mark left by the last experiment is not part of this body. Without this,
	# a debug panel that cut something in half and then reset it would leave the
	# scar hanging in the air, attached to nothing.
	for node in get_children():
		if node is ShadowCutMark:
			node.queue_free()
	_set_phase(&"idle")


func on_perfect_guard() -> void:
	attack_hitbox.set_active(false)
	attack_open = false
	state = State.STAGGER
	state_timer = 0.9
	attack_cooldown = 2.0
	_open_idle()


func freeze_for_debug() -> void:
	state = State.FROZEN
	state_timer = 4.0
	frost = 100.0
	attack_hitbox.set_active(false)
	_open_idle()


# Combat Lab preset. This deliberately goes through the SAME _on_hit path a spell
# uses, so a state forced from the panel behaves exactly like one the player
# created — a Lab shortcut that skipped the machinery would let a broken combo
# look fine on the panel and fail in play.
func apply_debug_state(label: StringName) -> bool:
	match label:
		&"normal":
			if state == State.EXECUTING:
				# A body the ceremony is holding cannot be reset out from under
				# it. `reset_dummy()` here would restore full health, make the
				# body visible and set it to IDLE — while the execution node
				# that owns it is still staging two halves of it. The player
				# would see the enemy standing inside its own corpse, and the
				# enemy could then be killed a second time.
				#
				# So the panel's answer is "no", and the way back is the one
				# §O §12 already provides: end the ceremony. `finish_iaido()`
				# force-resolves every hold, which puts the body back in the
				# fight properly — and `reset_dummy()` works again the moment
				# the state is no longer EXECUTING.
				return false
			elements.clear_all()
			if state != State.DEAD:
				state = State.IDLE
				state_timer = 0.0
			_open_idle()
			return true
		&"burning":
			elements.clear_all()
			_element_hit(ElementLibrary.FIRE, 1)
			return true
		&"frosted":
			elements.clear_all()
			_element_hit(ElementLibrary.FROST, 2)
			return true
		&"frozen":
			elements.clear_all()
			_element_hit(ElementLibrary.FROST, 3)
			return true
	return false


func _element_hit(element_id: StringName, count: int) -> void:
	for i in count:
		_on_hit({
			"damage": 0.0, "poise_damage": 0.0, "element": element_id,
			"impulse": 0.0, "source": null, "target": self,
		})


# ===================================================================== 缚星链
# The chain's contract with whatever it catches. It asks these questions and
# nothing else, exactly the way Measure only asks which group something is in —
# so the weapon never has to know that a "TechnicalDummy" exists.

func weight_class() -> StringName:
	# Read through a method rather than the `weight` field directly: the chain's
	# weight table is the whole reason a hook has three different outcomes, and an
	# interface is the difference between a rule and a convention.
	return weight


func on_chain_hooked(_source: Node3D) -> void:
	# Caught mid-swing. The throw landing is supposed to remove the attack the
	# enemy was already committed to, otherwise "hook the lunge" rewards nothing.
	if _is_gone():
		return
	attack_hitbox.set_active(false)
	attack_open = false
	attack_cooldown = maxf(attack_cooldown, 0.5)
	state = State.ALERT if state != State.FROZEN else State.FROZEN
	state_timer = 0.0
	_open_idle()


func on_chain_released() -> void:
	if _is_gone():
		return
	if state == State.STAGGER:
		state = State.ALERT
		_open_idle()


func apply_bound(seconds: float) -> void:
	# 缚's payoff: off balance, briefly, and shorter the heavier the target is —
	# which is why a heavy enemy is not a victim but an ANCHOR (§18).
	if _is_gone():
		return
	if state == State.FROZEN:
		# A frozen target is already unable to act. Binding it would be spending a
		# setup rather than building one.
		return
	attack_hitbox.set_active(false)
	attack_open = false
	state = State.STAGGER
	state_timer = maxf(state_timer, seconds)
	poise = 0.0
	_open_idle()


# A chain dragging something moves it for real, so the world can interrupt it —
# the same reason wind's push uses move_and_collide instead of a teleport. Pulling
# a light enemy into a pillar is a legitimate outcome.
func chain_pull(offset: Vector3) -> bool:
	if _is_gone():
		return false
	offset.y = 0.0
	if offset.length_squared() < 0.0001:
		return false
	var collision := move_and_collide(offset)
	if collision == null:
		return false
	last_wall_impact = clampf(offset.length() / 2.0, 0.25, 1.2)
	poise += 22.0 * last_wall_impact
	state = State.STAGGER
	state_timer = 0.6 * last_wall_impact
	attack_hitbox.set_active(false)
	attack_open = false
	wall_impact.emit(last_wall_impact)
	_open_idle()
	return true


func on_chain_deflect() -> void:
	# 截链. Deliberately NOT the same reaction as a sword parry: nothing was met,
	# the attack's trajectory was disturbed, so what happens is the enemy's own
	# swing coming apart.
	if _is_gone():
		return
	attack_hitbox.set_active(false)
	attack_open = false
	state = State.STAGGER
	state_timer = 0.55
	poise = 0.0
	last_interrupt = 0.5
	_open_idle()
