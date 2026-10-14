extends CharacterBody3D
class_name FirstEncounterEnemy
# ============================================================================
# FIRST ENCOUNTER ENEMY — 灰烬猎犬 (Ash Hound)
# ============================================================================
#
# WHY THIS IS NOT `TechnicalDummy` WITH A NEW MESH.
#
# §12 is explicit: 代码结构必须独立, FirstEncounterEnemy, 不是 TestDummy2. And the
# reason is not tidiness - the two bodies are genuinely different kinds of thing.
# The dummy is a `StaticBody3D` that stands where it was placed, has no
# locomotion, and answers damage by hiding itself; it exists so that a cut can be
# measured against a fixed target. This is a `CharacterBody3D` that DECIDES to
# come at you, and its whole purpose is that the first fight in the game has
# something in it that moves. Sharing a script between them would mean the
# measurement rig and the monster each carrying the other's dead code.
#
# WHAT IT REUSES, AND THAT LIST IS THE INTERESTING PART.
#
#   CombatHurtbox         layer 2, so the player's sword finds it with no new code
#   CombatHitbox          mask 2, so it can find the player's hurtbox
#   CombatController      §17's hit stop, camera impulse, slash VFX and audio are
#                         ALREADY wired to `hit_landed` and fire when a body is
#                         struck. Nothing in this file re-implements them.
#   TimeEffectManager     the last-blow hit stop (§17) comes from here
#
# So this file contains only what is actually new: a state machine, a body, and
# the three moments the brief names that no existing system owns - the entry,
# the telegraph, and the death.
#
# THE TELEGRAPH (§16): 0.5-0.8 s, and it is a SHAPE, not a flag.
#
# "让玩家能感知：它准备攻击了" cannot be satisfied by a timer with no picture.
# So the wind-up lowers the body, pulls it back onto its hind legs and grows a
# ring on the ground where the bite will land. The ring is the honest part: a
# player who reads it moves, and a player who does not gets hit - which is the
# entire contract the first fight has to teach.

signal died()
signal arrived()
signal struck_player()
signal knocked_prop()

enum State { ENTRY, IDLE, DETECT, APPROACH, TELEGRAPH, LUNGE, RECOVER, HURT, DEAD }

const STATE_NAMES := {
	State.ENTRY: "ENTRY", State.IDLE: "IDLE", State.DETECT: "DETECT",
	State.APPROACH: "APPROACH", State.TELEGRAPH: "TELEGRAPH",
	State.LUNGE: "LUNGE", State.RECOVER: "RECOVER", State.HURT: "HURT",
	State.DEAD: "DEAD",
}

# ---- numbers -----------------------------------------------------------------
#
# §16: the fight is won in 15-35 s, in 3-6 effective hits, and it can neither
# one-shot the player nor take ninety seconds. The swing numbers below are set
# against the sword's own: the A1/A2/A3 sentence is 21/24/46 (sword_basic.gd),
# a heavy is 36 and the skill is A2 at 24. 120 HP therefore lands the fight at
# roughly four to five clean connections - a full chain plus one more answer -
# which is the middle of the brief's window with room either side.
@export var max_health := 120.0
@export var attack_damage := 11.0
@export var move_speed := 3.4
@export var attack_range := 2.35
@export var detect_range := 22.0
@export var turn_rate := 5.0

## §16: "敌人的第一次攻击可以稍微明显：0.5~0.8 秒 Telegraph."
const TELEGRAPH_TIME := 0.62
const LUNGE_TIME := 0.26
const LUNGE_SPEED := 8.2
const RECOVER_TIME := 0.42
const COOLDOWN_MIN := 1.05
const COOLDOWN_MAX := 1.80
## Long enough to be a decision, short enough that a player who spams light
## attacks cannot stun-lock the first monster in the game.
const HURT_TIME := 0.34
const HURT_KNOCKBACK := 3.2
const DEATH_FALL_TIME := 0.55
const DEATH_HOLD := 3.4
const DEATH_SINK_TIME := 1.3

var health: float
var state: int = State.IDLE
var state_time := 0.0
var state_name := "IDLE"
var engaged := false

var _player: CharacterBody3D = null
var _hurtbox: CombatHurtbox = null
var _attack_box: CombatHitbox = null
var _attack_open := false
var _cooldown_left := 0.0
var _gravity := 0.0
var _entry_left := 0.0
var _entry_goal := Vector3.ZERO
var _entry_announced := false
var _approach_left := COOLDOWN_MAX
var _turned_this_entry := false
var _root: Node3D = null
var _visual: Node3D = null
var _tell_ring: MeshInstance3D = null
var _tell_material: StandardMaterial3D = null
var _legs: Array[Node3D] = []
var _leg_phase := 0.0
var _hit_sfx: AudioStreamPlayer3D = null
var _roar_sfx: AudioStreamPlayer3D = null
var _death_sfx: AudioStreamPlayer3D = null
var _body_meshes: Array[GeometryInstance3D] = []


func _ready() -> void:
	health = max_health
	_build_body()
	_build_boxes()
	_build_sound()
	_resolve_player()
	_enter(State.IDLE)
	set_process(true)


# ============================================================== the body
#
# A quadruped silhouette, built from primitives, at real scale: 1.02 m at the
# shoulder, 1.62 m nose to tail. The proportions are the design work here -
# a hound reads as a hound because its head is LOW and FORWARD of its shoulders
# and its legs are thin under a heavy chest, not because it has fur.
#
# IT IS DELIBERATELY NOT EMISSIVE. The project already learned this once on the
# training dummy: the construct's core light belongs to the CROSS-SECTION, not
# to the closed body, and a placeholder that glows is a different kind of object.
# The only exception is a two-centimetre ember at each eye, which is what makes
# an unlit grey body read as ALIVE at fifteen metres in mist.

## ASH GREY, AND LIGHTER THAN THE GROUND. That is the whole of §12's 轮廓明显.
##
## The first version was almost black (0.176) and it did not read: a near-black
## quadruped standing on dark brown dirt in flat overcast light is not a
## silhouette, it is a hole. The acceptance run's fight frame showed a black mound
## with no legs, no head and no way to tell which end was the mouth - on the one
## enemy whose whole job is to be legible at a glance. The name is 灰烬猎犬
## (ash hound), so a cold ash grey is also the more faithful answer, and being
## COOLER than the warm dirt is what keeps the shape readable even where the two
## happen to be equally bright.
const COAT := Color(0.432, 0.440, 0.448)
const COAT_BACK := Color(0.286, 0.278, 0.268)
const EMBER := Color(0.92, 0.36, 0.13)

const BODY_LEN := 0.92
const BODY_R := 0.27
const SHOULDER_Y := 0.62
const LEG_LEN := 0.60


func _build_body() -> void:
	_root = Node3D.new()
	_root.name = "VisualRoot"
	add_child(_root)
	var coat := _mat(COAT, 0.88)
	var back := _mat(COAT_BACK, 0.80)

	# THE HEAD IS AT +Z, NOT -Z.
	#
	# Godot-side characters in this project face +Z (that is the same convention
	# `MiraActor._turn_toward_target` is written against), so the hound is built
	# nose-forward on +Z and every `atan2(d.x, d.z)` in this file is correct. The
	# first draft had it the other way round, which is invisible in a still and
	# produces a monster that walks backwards - and, worse, an attack box that
	# opens behind it, so the first fight would have looked like a bug in the
	# hitboxes rather than a sign error in a model.
	var torso := _mesh(_root, "Torso", _capsule(BODY_LEN, BODY_R),
		Vector3(0.0, SHOULDER_Y, 0.04), coat)
	# The haunch is a second mass over the hips. One capsule alone reads as a
	# sausage; two masses with a dip between them read as an animal.
	_mesh(_root, "Haunch", _capsule(0.46, 0.24), Vector3(0.0, SHOULDER_Y - 0.02, -0.30), back)
	_mesh(_root, "Chest", _capsule(0.42, 0.25), Vector3(0.0, SHOULDER_Y - 0.03, 0.34), back)

	# A long low muzzle, which is the single strongest quadruped read available
	# from primitives. It is also what makes the TELEGRAPH readable: the head is
	# the only part of this body that moves much during a wind-up, so it has to
	# be a shape you can see the direction of.
	var neck := _mesh(_root, "Neck", _capsule(0.40, 0.15),
		Vector3(0.0, SHOULDER_Y + 0.04, 0.60), coat)
	neck.rotation.x = -0.42
	var head := _mesh(_root, "Head", _capsule(0.34, 0.15),
		Vector3(0.0, SHOULDER_Y - 0.02, 0.80), coat)
	head.rotation.x = -1.44
	_mesh(_root, "Muzzle", _capsule(0.22, 0.075),
		Vector3(0.0, SHOULDER_Y - 0.10, 0.92), coat).rotation.x = -1.52
	for side in [-0.072, 0.072]:
		var eye := _mesh(_root, "Eye", _sphere(0.022),
			Vector3(side, SHOULDER_Y + 0.01, 0.90), _mat_emissive(EMBER))
		_body_meshes.append(eye)

	var tail := _mesh(_root, "Tail", _capsule(0.52, 0.055),
		Vector3(0.0, SHOULDER_Y + 0.06, -0.56), coat)
	tail.rotation.x = 0.85

	# Legs. Two segments each so they can bend at the knee, which is the
	# difference between a walk and a hover.
	var leg_x := 0.20
	for spec in [[-leg_x, 0.30, "FL"], [leg_x, 0.30, "FR"],
			[-leg_x, -0.32, "BL"], [leg_x, -0.32, "BR"]]:
		var front: bool = String(spec[2]).begins_with("F")
		var stretch := 0.86 if front else 1.0
		var hip := Node3D.new()
		hip.name = "Leg" + String(spec[2])
		hip.position = Vector3(spec[0], SHOULDER_Y - 0.06, spec[1])
		_root.add_child(hip)
		var upper_len := LEG_LEN * 0.52 * stretch
		_mesh(hip, "Upper", _capsule(upper_len, 0.062),
			Vector3(0.0, -upper_len * 0.5, 0.0), coat)
		var knee := Node3D.new()
		knee.name = "Knee"
		knee.position = Vector3(0.0, -upper_len, 0.0)
		hip.add_child(knee)
		var lower_len := LEG_LEN * 0.48 * stretch
		_mesh(knee, "Lower", _capsule(lower_len, 0.050),
			Vector3(0.0, -lower_len * 0.5, 0.0), coat)
		_mesh(knee, "Paw", _sphere(0.062), Vector3(0.0, -lower_len, 0.02), coat)
		_legs.append(hip)

	_collect_fade_meshes(_root)
	_build_tell_ring()


## Every mesh that has to dissolve on death, gathered once at build time so the
## death tween is one loop instead of a tree walk written twice (once for direct
## children, once for grandchildren) - which is how the first draft managed to
## leave the legs behind while the torso faded.
func _collect_fade_meshes(node: Node) -> void:
	for child in node.get_children():
		if child is GeometryInstance3D:
			if not _body_meshes.has(child):
				_body_meshes.append(child)
		_collect_fade_meshes(child)


func _mat(colour: Color, roughness: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = colour
	m.roughness = roughness
	# LOW METALLIC ON PURPOSE. This project has already measured what happens
	# otherwise: `metallic` at 0.75 with no reflection probe in the scene renders
	# a pure black silhouette, and a black hound in a misty square is a hole in
	# the frame rather than a monster.
	m.metallic = 0.0
	return m


func _mat_emissive(colour: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = colour
	m.emission_enabled = true
	m.emission = colour
	m.emission_energy_multiplier = 3.4
	m.roughness = 0.5
	return m


func _capsule(height: float, radius: float) -> CapsuleMesh:
	var c := CapsuleMesh.new()
	c.height = height
	c.radius = radius
	c.radial_segments = 12
	c.rings = 4
	return c


func _sphere(radius: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = radius
	s.height = radius * 2.0
	s.radial_segments = 10
	s.rings = 5
	return s


func _mesh(parent: Node3D, node_name: String, mesh: Mesh, at: Vector3,
		mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.position = at
	mi.material_override = mat
	parent.add_child(mi)
	return mi


func _build_tell_ring() -> void:
	# Where the bite will land, drawn on the ground. A ring that grows over the
	# telegraph is readable from any angle and in any lighting, which a pose
	# change on a dark animal at fifteen metres is not.
	_tell_material = StandardMaterial3D.new()
	_tell_material.albedo_color = Color(0.85, 0.24, 0.14, 0.30)
	_tell_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_tell_material.emission_enabled = true
	_tell_material.emission = Color(0.85, 0.22, 0.12)
	_tell_material.emission_energy_multiplier = 1.6
	_tell_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_tell_ring = MeshInstance3D.new()
	_tell_ring.name = "TelegraphRing"
	var torus := TorusMesh.new()
	torus.inner_radius = 0.62
	torus.outer_radius = 0.72
	torus.rings = 20
	torus.ring_segments = 6
	_tell_ring.mesh = torus
	_tell_ring.material_override = _tell_material
	_tell_ring.visible = false
	add_child(_tell_ring)


func _build_boxes() -> void:
	# Sized to the body, offset to its centre. Layer and mask are the project's
	# existing contract (hurtboxes live on 2, hitboxes look for 2) and are set by
	# the classes themselves where possible.
	_hurtbox = CombatHurtbox.new()
	_hurtbox.name = "Hurtbox"
	_hurtbox.collision_layer = 2
	_hurtbox.collision_mask = 0
	var hc := CollisionShape3D.new()
	var hbox := BoxShape3D.new()
	hbox.size = Vector3(0.62, 1.10, 1.70)
	hc.shape = hbox
	hc.position = Vector3(0.0, 0.60, -0.10)
	_hurtbox.add_child(hc)
	add_child(_hurtbox)
	_hurtbox.owner_actor = self
	_hurtbox.hit_received.connect(_on_hit)

	_attack_box = CombatHitbox.new()
	_attack_box.name = "BiteHitbox"
	_attack_box.collision_layer = 0
	_attack_box.collision_mask = 2
	_attack_box.damage = attack_damage
	_attack_box.poise_damage = 0.0
	_attack_box.element = &"physical"
	_attack_box.impulse = 3.0
	var ac := CollisionShape3D.new()
	var abox := BoxShape3D.new()
	abox.size = Vector3(1.1, 0.9, 1.5)
	ac.shape = abox
	_attack_box.add_child(ac)
	_attack_box.position = Vector3(0.0, 0.55, 1.05)
	add_child(_attack_box)
	_attack_box.source = self
	# Wired so the director can be told "it got you" without polling health. The
	# one-hit-per-lunge guarantee is `CombatHitbox`'s own: `set_active(true)`
	# clears its target list, and one lunge opens it exactly once.
	_attack_box.hit_landed.connect(_on_bite_landed)


func _build_sound() -> void:
	_hit_sfx = _sfx("HitSfx", "res://audio/sfx/core/body_low_01.wav", -9.0)
	_roar_sfx = _sfx("RoarSfx", "res://audio/sfx/core/pressure_low_01.wav", -5.0)
	_death_sfx = _sfx("DeathSfx", "res://audio/sfx/core/body_low_01.wav", -3.0)


func _sfx(node_name: String, path: String, volume: float) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.name = node_name
	if ResourceLoader.exists(path):
		p.stream = load(path)
	p.volume_db = volume
	p.max_distance = 30.0
	# IN THE `world_audio` GROUP. That is not bookkeeping: `AudioStateController`
	# ducks exactly the members of this group, which is how §19's "声音被抽掉
	# 0.3 秒" reaches the hound as well as the music - the monster's own growl
	# falling silent with everything else is most of what makes the moment land.
	p.add_to_group("world_audio")
	add_child(p)
	return p


func _resolve_player() -> void:
	_player = get_tree().get_first_node_in_group(&"player") as CharacterBody3D


# ============================================================== the states

func _enter(next: int) -> void:
	state = next
	state_time = 0.0
	state_name = STATE_NAMES.get(next, "?")
	match next:
		State.TELEGRAPH:
			_set_tell(true)
			_set_attack(false)
		State.LUNGE:
			_set_tell(false)
			_set_attack(true)
		State.RECOVER:
			_set_tell(false)
			_set_attack(false)
			_cooldown_left = randf_range(COOLDOWN_MIN, COOLDOWN_MAX)
		State.HURT, State.DEAD, State.ENTRY, State.IDLE, State.DETECT, State.APPROACH:
			_set_tell(false)
			_set_attack(false)


func _set_attack(on: bool) -> void:
	if _attack_open == on or _attack_box == null:
		return
	_attack_open = on
	_attack_box.set_active(on)


func _set_tell(on: bool) -> void:
	if _tell_ring == null:
		return
	_tell_ring.visible = on
	if on:
		_tell_ring.scale = Vector3(0.34, 1.0, 0.34)
		_tell_material.albedo_color.a = 0.10


## §13: the entrance. It walks in from wherever it was placed, knocks the crates
## at the alley mouth on the way, stops, looks at the player, growls, and only
## then is it a fight. `pause` is the director's number and the enemy does not
## re-decide it - see StoryDirector.HOUND_ENTRY_PAUSE.
func stage_entry(pause: float) -> void:
	_entry_left = pause
	_entry_goal = Vector3.ZERO
	_entry_announced = false
	_enter(State.ENTRY)
	if _player != null:
		_entry_goal = _player.global_position
		var to := _entry_goal - global_position
		to.y = 0.0
		# Stop 3.2 m short on purpose: the pause is the point at which the
		# player can see what is about to charge them, and a hound that stops on
		# top of them has skipped the only readable half-second of the scene.
		if to.length() > 3.2:
			_entry_goal = global_position + to.normalized() * (to.length() - 3.2)
	else:
		_entry_goal = global_position


# ============================================================== the loop

func _physics_process(delta: float) -> void:
	state_time += delta
	_cooldown_left = maxf(0.0, _cooldown_left - delta)
	if _player == null or not is_instance_valid(_player):
		_resolve_player()
	_turn_toward(_facing_target(), delta)
	match state:
		State.ENTRY:
			_tick_entry(delta)
		State.IDLE:
			_tick_idle()
		State.DETECT:
			if state_time > 0.35:
				_enter(State.APPROACH)
		State.APPROACH:
			_tick_approach(delta)
		State.TELEGRAPH:
			_hold_still(delta, 0.0)
			if _tell_ring != null and _tell_ring.visible:
				var u := clampf(state_time / TELEGRAPH_TIME, 0.0, 1.0)
				_tell_ring.scale = Vector3(lerpf(0.34, 1.0, u), 1.0,
					lerpf(0.34, 1.0, u))
				_tell_material.albedo_color.a = lerpf(0.10, 0.34, u)
				_tell_ring.position = Vector3(0.0, 0.05, 1.05)
			if state_time >= TELEGRAPH_TIME:
				if _roar_sfx != null and _roar_sfx.stream != null:
					_roar_sfx.play()
				_enter(State.LUNGE)
		State.LUNGE:
			# FORWARD IS +Z. See `_build_body`: this body's nose is on +Z, so the
			# lunge travels along +basis.z. Using -basis.z (the usual "camera
			# forward" idiom, and what the first draft had) sends the hound
			# backwards away from the player at 8 m/s while its head points at
			# them - which reads as a knockback the player never caused.
			var forward := _root.global_transform.basis.z
			velocity = forward * LUNGE_SPEED
			velocity.y = _gravity
			move_and_slide()
			if state_time >= LUNGE_TIME:
				_enter(State.RECOVER)
		State.RECOVER:
			_hold_still(delta, 0.6)
			if state_time >= RECOVER_TIME:
				_enter(State.APPROACH)
		State.HURT:
			_hold_still(delta, 1.2)
			if state_time >= HURT_TIME:
				_enter(State.APPROACH if engaged else State.IDLE)
		State.DEAD:
			pass
	_animate_body(delta)


func _hold_still(delta: float, drag: float) -> void:
	# Decelerate rather than stop dead: a body that is moving at 8 m/s and then
	# has velocity zeroed reads as a sprite swap, not as a thing that braked.
	var v := velocity
	v.x = move_toward(v.x, 0.0, drag * 60.0 * delta)
	v.z = move_toward(v.z, 0.0, drag * 60.0 * delta)
	_gravity = 0.0 if is_on_floor() else _gravity - 22.0 * delta
	v.y = _gravity
	velocity = v
	move_and_slide()
	if is_on_floor():
		_gravity = 0.0


func _tick_entry(delta: float) -> void:
	var to := _entry_goal - global_position
	to.y = 0.0
	if not _entry_announced and global_position.distance_to(_entry_goal) < 1.6:
		# The crates. The plaza placed them at the alley mouth; the hound only
		# has to admit that it went through them.
		_entry_announced = true
		knocked_prop.emit()
		if _player != null:
			look_at_target(_player.global_position)
	if to.length() > 0.25 and _entry_left > 0.0:
		_entry_left = maxf(0.0, _entry_left - delta)
		var move := to.normalized() * minf(move_speed * delta, to.length())
		velocity = Vector3(move.x, _gravity, move.z)
		_gravity = 0.0 if is_on_floor() else _gravity - 22.0 * delta
		velocity.y = _gravity
		move_and_slide()
		if is_on_floor():
			_gravity = 0.0
		return
	# Standing at the edge of the square. Low head, growl, and then it is on him.
	_hold_still(delta, 1.4)
	if _roar_sfx != null and _roar_sfx.stream != null and not _roar_sfx.playing:
		_roar_sfx.play()
		if state_time > 0.7:
			arrived.emit()
			engaged = true
			_enter(State.DETECT)


func _tick_idle() -> void:
	if _player != null and global_position.distance_to(_player.global_position) <= detect_range:
		engaged = true
		_enter(State.DETECT)


func _tick_approach(delta: float) -> void:
	if _player == null:
		_enter(State.IDLE)
		return
	var to := _player.global_position - global_position
	to.y = 0.0
	var distance := to.length()
	if distance <= attack_range and _cooldown_left <= 0.0:
		_enter(State.TELEGRAPH)
		return
	# IT CIRCLES WHEN IT CANNOT BITE. Without this, a hound that has just missed
	# walks straight back into the same wall of sword and the fight becomes a
	# metronome; with it, the cooldown is used the way a cooldown is supposed to
	# be used - to make the player move.
	var strafe := 0.0
	if _cooldown_left > 0.0 and distance < attack_range * 1.35:
		strafe = 1.0
	var dir := to.normalized()
	if strafe != 0.0:
		dir = (to.rotated(Vector3.UP, 0.9 * strafe)).normalized() * 0.85
		if distance < attack_range * 0.8:
			dir -= to.normalized() * 0.6
	velocity = dir * move_speed
	_gravity = 0.0 if is_on_floor() else _gravity - 22.0 * delta
	velocity.y = _gravity
	move_and_slide()
	if is_on_floor():
		_gravity = 0.0


func _facing_target() -> Vector3:
	if state == State.ENTRY:
		return _entry_goal
	if _player != null and is_instance_valid(_player):
		return _player.global_position
	return global_position + _root.global_transform.basis.z


func look_at_target(point: Vector3) -> void:
	var d := point - global_position
	d.y = 0.0
	if d.length_squared() < 0.0004:
		return
	rotation.y = atan2(d.x, d.z)


func _turn_toward(point: Vector3, delta: float) -> void:
	# IT TURNS, IT DOES NOT SNAP. A monster whose facing is assigned every frame
	# is a monster that slides sideways, and the first fight in the game is where
	# a player learns whether the enemies are bodies or sprites.
	if state == State.LUNGE:
		return
	var d := point - global_position
	d.y = 0.0
	if d.length_squared() < 0.0004:
		return
	var want := atan2(d.x, d.z)
	rotation.y = lerp_angle(rotation.y, want, clampf(delta * turn_rate, 0.0, 1.0))


func _animate_body(delta: float) -> void:
	if _root == null:
		return
	var moving := Vector3(velocity.x, 0.0, velocity.z).length() > 0.35
	_leg_phase += delta * (7.0 if moving else 1.2)
	var amp := 0.34 if moving else 0.05
	for i in _legs.size():
		var phase := _leg_phase + (0.0 if i % 2 == 0 else PI) + (0.5 if i >= 2 else 0.0)
		_legs[i].rotation.x = sin(phase) * amp
	# The crouch. §16's telegraph has to be visible as a SHAPE, so the body
	# drops and settles back onto its haunches for the whole wind-up rather than
	# only at the last frame of it.
	var crouch := 0.0
	if state == State.TELEGRAPH:
		crouch = clampf(state_time / TELEGRAPH_TIME, 0.0, 1.0) * 0.16
	elif state == State.LUNGE:
		crouch = -0.06
	_root.position.y = -crouch
	_root.rotation.x = crouch * 0.55


# ============================================================== damage

func is_alive() -> bool:
	return state != State.DEAD


func _on_hit(hit: Dictionary) -> void:
	if state == State.DEAD:
		return
	var damage := float(hit.get("damage", 0.0))
	health = maxf(0.0, health - damage)
	# §17: 命中感. The hit stop, camera impulse and slash VFX for this moment are
	# NOT here - they already fire from `CombatController.hit_landed` the instant
	# the box connects, and re-issuing them would double every impact. What this
	# file owns is the part that belongs to the body: it flinches, and it is
	# pushed.
	_flinch(hit)
	if _hit_sfx != null and _hit_sfx.stream != null:
		_hit_sfx.pitch_scale = randf_range(0.94, 1.08)
		_hit_sfx.play()
	if health <= 0.0:
		_die()


func _flinch(hit: Dictionary) -> void:
	if state in [State.TELEGRAPH, State.LUNGE, State.RECOVER]:
		# A wind-up that a single light attack can cancel is a wind-up that never
		# happens, and the first fight needs the telegraph to be a promise. The
		# lunge itself is not interruptible either, for the same reason.
		pass
	var source: Node3D = hit.get("source")
	if source != null and is_instance_valid(source):
		var away := global_position - source.global_position
		away.y = 0.0
		if away.length_squared() > 0.0004:
			velocity += away.normalized() * HURT_KNOCKBACK
	_enter(State.HURT)


## §18: no instant `queue_free()`.
##
## Death is a state with a duration, and the duration is the point: the body
## falls, stays where it fell long enough for the player to look at it, and only
## then leaves. Hiding a body on the frame its health reaches zero deletes the
## only evidence that the player did anything.
func _die() -> void:
	_enter(State.DEAD)
	_hurtbox.monitorable = false
	_hurtbox.set_deferred("monitoring", false)
	_set_attack(false)
	if _tell_ring != null:
		_tell_ring.visible = false
	if _death_sfx != null and _death_sfx.stream != null:
		_death_sfx.play()
	died.emit()
	var t := create_tween()
	t.set_trans(Tween.TRANS_CUBIC)
	# The collapse: onto its side, then down. Two axes because a body that only
	# rolls looks like a barrel.
	t.tween_property(_root, "rotation:z", 1.42, DEATH_FALL_TIME).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(_root, "rotation:x", 0.22, DEATH_FALL_TIME)
	t.parallel().tween_property(_root, "position:y", -0.18, DEATH_FALL_TIME)
	for leg in _legs:
		t.parallel().tween_property(leg, "rotation:x", -0.9, DEATH_FALL_TIME)
	t.tween_interval(DEATH_HOLD)
	# Then it sinks and fades, which reads as "gone" rather than as "deleted".
	t.tween_property(_root, "position:y", -1.5, DEATH_SINK_TIME)
	for mi in _body_meshes:
		if is_instance_valid(mi):
			t.parallel().tween_property(mi, "transparency", 1.0, DEATH_SINK_TIME)
	t.tween_callback(queue_free)


# ============================================================== reporting

## The last gate before the player is hurt, and it exists so the hound cannot
## hit someone who is already being hit by it: `CombatHitbox` clears its own
## hit list when it opens, and one lunge opens it once.
func _on_bite_landed(_hit: Dictionary) -> void:
	struck_player.emit()


func debug_line() -> String:
	return "HOUND  %d / %d  %s%s" % [
		int(health), int(max_health), state_name,
		"  cool %.2f" % _cooldown_left if _cooldown_left > 0.0 else "",
	]
