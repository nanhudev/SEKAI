extends StaticBody3D

signal shattered

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


func _ready() -> void:
	health = max_health
	hurtbox.owner_actor = self
	hurtbox.hit_received.connect(_on_hit)
	attack_hitbox.source = self


func _process(delta: float) -> void:
	if state == State.DEAD:
		return
	state_timer = maxf(0.0, state_timer - delta)
	attack_cooldown = maxf(0.0, attack_cooldown - delta)
	if state in [State.IDLE, State.ALERT] and attack_cooldown == 0.0 and global_position.distance_to(player.global_position) < 3.4:
		state = State.ATTACK
		state_timer = 0.85
		attack_cooldown = 2.3
	if state == State.ATTACK:
		var should_open := state_timer < 0.52 and state_timer > 0.32
		if should_open != attack_open:
			attack_open = should_open
			attack_hitbox.set_active(should_open)
		if state_timer == 0.0:
			state = State.ALERT
			attack_hitbox.set_active(false)
			attack_open = false
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
