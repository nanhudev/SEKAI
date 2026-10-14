extends Node3D
class_name TrainingPost
# 训练木桩 — the thing §8 makes the player hit, and the only reason it exists.
#
# WHY IT IS NOT A TECHNICAL DUMMY. The dummy is a 120 HP construct with an AI, an
# element ladder and an execution profile, placed so that CUTS can be measured
# against a fixed target. This is a post in a town square that a person swings at
# once so that the game can tell the difference between "the player pressed the
# mouse button" and "the player connected".
#
# THAT DISTINCTION IS THE WHOLE MECHANISM OF §21. The story does not advance on
# `light_attack` being pressed - it advances on this node being STRUCK. A player
# who swings at the sky stays in BASIC_ATTACK until they hit the wood, and that is
# correct: a lesson on how to attack that can be completed by missing is not a
# lesson.
#
# IT CANNOT DIE. `TrainingPost` takes damage and does nothing with it. There is no
# health bar because a post that can be destroyed would leave a story stage with
# nothing to hit, and the brief's §26 explicitly rules out building combat depth
# into the tutorial.

const TB := preload("res://scripts/training/training_build.gd")

signal struck()

## §8: "非常简单即可". A 6 cm post with a bound straw head at chest height - the
## two things that make a practice post read as one at a glance.
const POST_R := 0.075
const POST_H := 1.05
const BUNDLE_R := 0.17
const BUNDLE_LEN := 0.62

var hit_count := 0

var _bundle: Node3D = null
var _hurtbox: CombatHurtbox = null
var _lean := 0.0
var _lean_v := 0.0


func _ready() -> void:
	_build()
	_hurtbox = CombatHurtbox.new()
	_hurtbox.name = "Hurtbox"
	_hurtbox.collision_layer = 2
	_hurtbox.collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.52, 1.85, 0.52)
	cs.shape = box
	cs.position = Vector3(0.0, 0.92, 0.0)
	_hurtbox.add_child(cs)
	add_child(_hurtbox)
	_hurtbox.owner_actor = self
	_hurtbox.hit_received.connect(_on_hit)
	set_process(true)


func _build() -> void:
	var timber := TB.material(Color(0.318, 0.235, 0.163), 0.86)
	var binding := TB.material(Color(0.404, 0.322, 0.204), 0.92)
	var straw := TB.material(Color(0.560, 0.470, 0.290), 0.95)

	TB.post(self, "Stake", Vector3(0.0, -0.35, 0.0), POST_H + 0.35, POST_R, timber, true)
	TB.slab(self, "Foot", Vector3(0.0, 0.04, 0.0), Vector3(0.46, 0.09, 0.46), timber)

	_bundle = Node3D.new()
	_bundle.name = "Bundle"
	_bundle.position = Vector3(0.0, POST_H - 0.10, 0.0)
	add_child(_bundle)
	var head := MeshInstance3D.new()
	head.name = "Straw"
	var cyl := CylinderMesh.new()
	cyl.height = BUNDLE_LEN
	cyl.top_radius = BUNDLE_R
	cyl.bottom_radius = BUNDLE_R * 0.82
	cyl.radial_segments = 14
	head.mesh = cyl
	head.material_override = straw
	_bundle.add_child(head)
	# Two bindings, because a straw bundle with no cord is a barrel.
	for y in [-0.18, 0.16]:
		var ring := MeshInstance3D.new()
		ring.name = "Binding"
		var torus := TorusMesh.new()
		torus.inner_radius = BUNDLE_R
		torus.outer_radius = BUNDLE_R + 0.022
		torus.rings = 16
		torus.ring_segments = 6
		ring.mesh = torus
		ring.position = Vector3(0.0, y, 0.0)
		ring.material_override = binding
		_bundle.add_child(ring)
	TB.label(self, "PostLabel", "练习桩", Vector3(0.0, POST_H + 0.45, 0.0), 0.22,
		Color(0.86, 0.82, 0.70))


func _on_hit(hit: Dictionary) -> void:
	hit_count += 1
	# A DAMPED SPRING, NOT A TWEEN. A tween restarts from zero on every hit, so
	# two fast swings make the post snap back upright between them; a spring that
	# is PUSHED by each hit keeps the wobble continuous and adds to it, which is
	# what makes a heavy land differently from a light without a single number
	# being authored about weight.
	var push := clampf(float(hit.get("poise_damage", 10.0)) / 45.0, 0.25, 1.0)
	_lean_v += push * 5.4
	struck.emit()


func _process(delta: float) -> void:
	# Critically damped: k = 26, c = 2*sqrt(k) ~ 10.2.
	if absf(_lean) < 0.0005 and absf(_lean_v) < 0.0005:
		return
	_lean_v += (-26.0 * _lean - 10.2 * _lean_v) * delta
	_lean += _lean_v * delta
	if _bundle != null:
		_bundle.rotation.x = _lean
		_bundle.rotation.z = _lean * 0.35


## The interaction-hub signature, so the hub does not have to special-case it.
## A post is not interactable - it is hit - so its label is deliberately empty
## and the hub skips it.
func interact_label() -> String:
	return ""
