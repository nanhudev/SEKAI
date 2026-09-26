extends StaticBody3D

signal shattered
signal attack_started(variant: int)

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


func _ready() -> void:
	health = max_health
	hurtbox.owner_actor = self
	hurtbox.hit_received.connect(_on_hit)
	attack_hitbox.source = self
	attack_shape = attack_hitbox.get_node("CollisionShape3D").shape.duplicate() as BoxShape3D
	attack_hitbox.get_node("CollisionShape3D").shape = attack_shape
	core.material_override = cue_material


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
		if attack_variant == 2 and should_open:
			global_position += global_transform.basis.z * 8.0 * delta
		if state_timer == 0.0:
			state = State.ALERT
			attack_hitbox.set_active(false)
			attack_open = false
			core.scale = Vector3.ONE
	if state == State.STAGGER and state_timer == 0.0:
		state = State.ALERT
	if state == State.FROZEN and state_timer == 0.0:
		state = State.ALERT
		frost = 0.0
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
	if state == State.ATTACK and not attack_open:
		var preparation := clampf((attack_duration - state_timer) / attack_windup, 0.0, 1.0)
		core.scale = Vector3.ONE * (1.0 + preparation * (0.28 if attack_variant == 1 else 0.16))
		cue_material.albedo_color = Color(1.0, 0.45, 0.2).lerp(Color(1.0, 0.15, 0.08), preparation) if attack_variant == 1 else Color(0.4, 0.85, 1.0).lerp(Color(0.9, 1.0, 1.0), preparation)
	else:
		core.scale = core.scale.lerp(Vector3.ONE, minf(1.0, delta * 12.0))
		cue_material.albedo_color = Color(0.5, 0.75, 0.8)


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
		1: # longer heavy windup, perfect-guard check
			attack_duration = 1.05
			attack_windup = 0.64
			attack_active_end = 0.79
			attack_shape.size = Vector3(1.8, 1.7, 2.2)
			attack_hitbox.damage = 22.0
		2: # forward lunge, repositioning check
			attack_duration = 0.9
			attack_windup = 0.47
			attack_active_end = 0.63
			attack_shape.size = Vector3(1.4, 1.5, 2.0)
			attack_hitbox.damage = 15.0
	state_timer = attack_duration
	attack_cooldown = 1.6
	attack_started.emit(attack_variant)


func _on_hit(hit: Dictionary) -> void:
	if state == State.DEAD:
		return
	var heavy: bool = hit.get("poise_damage", 0.0) >= 35.0
	if state == State.FROZEN and heavy:
		health -= 55.0
		frost = 0.0
		state = State.STAGGER
		state_timer = 1.0
		attack_hitbox.set_active(false)
		shattered.emit()
	else:
		health -= float(hit.get("damage", 0.0))
		poise += float(hit.get("poise_damage", 0.0))
		if hit.get("element", &"physical") == &"frost":
			frost += 45.0
			if frost >= 100.0:
				state = State.FROZEN
				state_timer = 4.0
				attack_hitbox.set_active(false)
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
		if poise >= poise_limit and state != State.FROZEN:
			poise = 0.0
			state = State.STAGGER
			state_timer = 0.6
	if health <= 0.0:
		state = State.DEAD
		attack_hitbox.set_active(false)
		visible = false
		hurtbox.monitorable = false


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


func on_perfect_guard() -> void:
	attack_hitbox.set_active(false)
	attack_open = false
	state = State.STAGGER
	state_timer = 0.9
	attack_cooldown = 2.0


func freeze_for_debug() -> void:
	state = State.FROZEN
	state_timer = 4.0
	frost = 100.0
	attack_hitbox.set_active(false)
