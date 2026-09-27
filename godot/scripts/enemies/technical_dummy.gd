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

enum State { IDLE, ALERT, ATTACK, STAGGER, FROZEN, DEAD }

@export var max_health := 120.0
@export var poise_limit := 50.0

@onready var hurtbox: CombatHurtbox = $Hurtbox
@onready var core: MeshInstance3D = $Core
@onready var attack_hitbox: CombatHitbox = $AttackHitbox
@onready var player: CharacterBody3D = get_parent().get_node("Player")

var health := 120.0
var poise := 0.0
var frost := 0.0
var burn := 0.0
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

var telegraph: MeshInstance3D
var telegraph_material: StandardMaterial3D
var telegraph_flash := 0.0
var last_interrupt := 0.0


func _ready() -> void:
	health = max_health
	hurtbox.owner_actor = self
	hurtbox.hit_received.connect(_on_hit)
	attack_hitbox.source = self
	attack_shape = attack_hitbox.get_node("CollisionShape3D").shape.duplicate() as BoxShape3D
	attack_hitbox.get_node("CollisionShape3D").shape = attack_shape
	core.material_override = cue_material
	_build_telegraph()


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
	if state == State.DEAD:
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
		frost = 0.0
		_set_phase(&"idle")
	if state != State.FROZEN:
		frost = maxf(0.0, frost - delta * 4.0)
	if burn > 0.0:
		burn = maxf(0.0, burn - delta)
		health -= 5.0 * delta
		if health <= 0.0:
			state = State.DEAD
			visible = false
			attack_hitbox.set_active(false)
	core.rotation.y += delta * (0.0 if state == State.FROZEN else 0.6)
	_update_cue(delta)


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
		var elemental_color := Color(0.5, 0.75, 0.8)
		if frost > 0.0:
			elemental_color = elemental_color.lerp(Color(0.82, 0.95, 1.0), clampf(frost / 100.0, 0.0, 1.0))
		if burn > 0.0:
			elemental_color = elemental_color.lerp(Color(1.0, 0.37, 0.1), clampf(burn / 3.0, 0.0, 0.8))
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


func _on_hit(hit: Dictionary) -> void:
	if state == State.DEAD:
		return
	var heavy: bool = float(hit.get("poise_damage", 0.0)) >= 35.0
	if state == State.FROZEN and heavy:
		var shatter_damage := 55.0 * float(hit.get("frozen_bonus", 1.0))
		health -= shatter_damage
		frost = 0.0
		state = State.STAGGER
		state_timer = 1.0
		attack_hitbox.set_active(false)
		_open_idle()
		shattered.emit()
	else:
		var damage := float(hit.get("damage", 0.0))
		if state == State.FROZEN:
			damage *= float(hit.get("frozen_bonus", 1.0))
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
		if hit.get("element", &"physical") == &"frost":
			frost += 45.0
			if frost >= 100.0:
				state = State.FROZEN
				state_timer = 4.0
				attack_hitbox.set_active(false)
				_open_idle()
		elif hit.get("element", &"physical") == &"fire":
			burn = 3.0
		elif hit.get("element", &"physical") == &"wind":
			var source: Node3D = hit.get("source")
			if source != null:
				var away := global_position - source.global_position
				away.y = 0.0
				if away.length_squared() > 0.01:
					global_position += away.normalized() * float(hit.get("impulse", 0.0))
			state = State.STAGGER
			state_timer = 0.45
			attack_hitbox.set_active(false)
			_open_idle()
		if poise >= poise_limit and state != State.FROZEN:
			poise = 0.0
			state = State.STAGGER
			state_timer = 0.6
			_open_idle()
	if health <= 0.0:
		state = State.DEAD
		attack_hitbox.set_active(false)
		visible = false
		hurtbox.monitorable = false
		telegraph.visible = false
		_set_phase(&"dead")


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
	if state == State.DEAD:
		return
	attack_variant = ((variant - 1) + 3) % 3
	attack_cooldown = 0.0
	_start_attack()


func on_interrupted(stagger: float) -> void:
	if state == State.DEAD:
		return
	attack_hitbox.set_active(false)
	attack_open = false
	state = State.STAGGER
	state_timer = stagger
	_open_idle()


func reset_dummy() -> void:
	health = max_health
	poise = 0.0
	frost = 0.0
	burn = 0.0
	state = State.IDLE
	state_timer = 0.0
	attack_cooldown = 1.0
	attack_variant = -1
	attack_hitbox.set_active(false)
	visible = true
	hurtbox.monitorable = true
	telegraph.visible = true
	last_interrupt = 0.0
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
