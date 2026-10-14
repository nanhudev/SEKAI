extends Node3D
class_name SwordReach
# SEKAI · HOW A CUT CROSSES THE SPACE BETWEEN TWO PEOPLE
#
# ===========================================================================
# WHY THIS IS NOT "A BIGGER HITBOX"
# ===========================================================================
#
# The basic sentence's four beats are told apart by distance, so the distance has
# to be REAL — not a hitbox that was made longer. Three different ways of
# touching something at range live here, and they are deliberately three
# different mechanisms because they are three different sentences:
#
#   WAVE   a cut that LEAVES the blade and travels. It has a position, it takes
#          time to arrive, and a body standing where it passes is struck by
#          something that went past it. A2.
#
#   TRACE  a cut that happens AT A PLACE, all at once, with no travel at all.
#          The mark is in space; a body inside it was cut. A3.
#
#   ARC    a cut that goes AROUND the player. The sweep is resolved as the blade
#          passes through each slice, so a body in front is hit before a body
#          behind — the order IS the arc. A4.
#
# ===========================================================================
# THE CUT IS AN ANGULAR WINDOW, AND THAT IS NOT A SHORTCUT
# ===========================================================================
#
# `TRACE` does not test "is this body within N metres of a plane". It tests
# whether the body's DIRECTION FROM THE EYE falls inside the mark the player can
# actually see, and then whether it is close enough to be reached.
#
# That distinction matters, because a slash mark on screen is a line, and the set
# of world points that project onto a line is a plane THROUGH THE EYE — the same
# fact `iaido_cut_plane.gd` is built on, and the reason a world cut and an enemy
# cross-section can be one event. A box placed out in front would be a different
# cut from the one drawn, and the player would find the two disagreeing the first
# time they stood off to one side.
#
# So a cut is: an angular window in the view plane (direction, length, thickness,
# offset) and a reach. Everything inside both is cut, at any depth. Which is also
# why three cuts in three directions hit three different sets of things — that is
# the mechanic, not an accident of the query.
#
# ===========================================================================
# WHO DELIVERS THE DAMAGE
# ===========================================================================
#
# Nobody here. A confirmed overlap is turned into the same `hit` Dictionary a
# `CombatHitbox` produces and handed to the controller's one landing path, so
# distance never becomes a second way for damage to work. If a wave hit and a
# sword hit could disagree about poise or hitstop, the combo would have two
# physics engines.

## Layer every hurtbox in the project lives on. See `CombatHurtbox.build_for`.
const HURTBOX_LAYER := 2
## How high above an actor's origin a cut is measured against. The mock enemies
## are 1.8m tall, so a cut aimed at the chest has to be tested against the chest
## — testing against the origin would make every ranged cut miss a standing body
## from above and hit it from below.
const BODY_SAMPLE_HEIGHT := 0.95
## Padding on the broadphase ball. The ball is a BROADPHASE, never the hit test.
const QUERY_PADDING := 1.5
## Nothing closer than this to the eye is cut by a space cut: a mark drawn across
## the lens does not also decapitate the person drawing it.
const MIN_TRACE_DEPTH := 0.75

signal wave_born(node: Node3D, move: SwordMove)
signal wave_died(node: Node3D)
signal trace_resolved(index: int, hits: int, mark: Dictionary)
## The slice's own angles travel with the signal, and that is what lets the trail
## be built from the sweep rather than from a second opinion about where the
## sweep was: a listener that recomputed the slice boundaries from `arc_slices`
## and the move's arc endpoints would be a copy of this arithmetic, and copies
## drift the first time the slicing changes.
signal arc_resolved(slice_index: int, hits: int, from_deg: float, to_deg: float)

## Who is swinging, and whose hurtbox must never be hit by their own cut.
var source: Node3D
## Where a confirmed overlap goes: the controller's own landing path.
var resolver: Node

var _waves: Array[Dictionary] = []
var _seen: Dictionary = {}
var _trace_seen: Dictionary = {}


func set_source(actor: Node3D, landing: Node) -> void:
	source = actor
	resolver = landing


# ===========================================================================
# Lifecycle
# ===========================================================================

## A2's body/wave share a move table; A4 shares it across all slices.
## A3 separately owns one contact table per cut, so it can land three beats.
func begin_move(_move: SwordMove) -> void:
	# A released wave keeps its own move's contact table across a combo transition.
	_seen = {}
	_trace_seen.clear()


## Releases every wave in flight. Called when a move ends, when the weapon
## changes and by a stage's RESET — a wave that outlives its attack is a cut
## nobody is holding any more.
func clear() -> void:
	var dying := _waves.duplicate()
	_waves.clear()
	for wave in dying:
		var node: Node3D = wave["node"]
		if not is_instance_valid(node):
			continue
		var hitbox: CombatHitbox = wave["hitbox"]
		if is_instance_valid(hitbox):
			hitbox.set_active(false)
		wave_died.emit(node)
		node.queue_free()
	_seen.clear()
	_trace_seen.clear()


func _exit_tree() -> void:
	clear()


func active_wave_count() -> int:
	var live := 0
	for wave in _waves:
		if wave["alive"]:
			live += 1
	return live


## THE ONE GATE EVERY MECHANISM PASSES THROUGH before it is allowed to cut a body.
## Returns true if this body was already cut by the move in flight, in which case
## the caller must do nothing at all — not even the hitstop.
##
## Why it is a gate and not a flag on one side: WHICH mechanism lands first is not
## deterministic. A2's blade hitbox and its wave overlap from 0.5m to 2.1m, and
## whether the Area3D overlap or the wave's travel reports first depends on which
## physics frame each one happened to wake up on. Marking only the wave (the first
## attempt at this) therefore fixed the close-range double cut on the takes where
## the blade won the race and left it on the takes where the wave did — a bug that
## reproduces four times out of five, which is the worst frequency a bug can have.
func claim(actor: Node3D) -> bool:
	if actor == null:
		return false
	if _seen.has(actor):
		return true
	_seen[actor] = true
	return false


## Whether the move in flight has already cut `actor`.
func has_cut(actor: Node3D) -> bool:
	return actor != null and _seen.has(actor)


# ===========================================================================
# WAVE — A2. A cut that leaves the blade.
# ===========================================================================

## Launches the travelling cut and returns the node the VFX should draw on: the
## wave's transform IS the visual's transform, so what the player sees and what
## can hit them cannot drift apart.
func fire_wave(move: SwordMove, damage_scale: float) -> Node3D:
	if move == null or move.reach <= 0.0:
		return null
	# §5 asks the crescent to travel "slightly upward". The tilt belongs to the
	# WAVE and not to the player's aim: the cut rises because it is a rising cut,
	# not because the sword was pointed at the sky.
	var forward := (_forward() + Vector3.UP * 0.11).normalized()

	var node := Node3D.new()
	node.name = "SwordWave"
	var release := _eye()
	if source != null:
		var visual := source.get_node_or_null("CameraRig/LookPivot/MotionPivot/ShakePivot/WeaponRoot/TempSwordVisual")
		if visual != null:
			var blade_point: Vector3 = visual.pose_position + Basis.from_euler(visual.pose_rotation) * Vector3.UP * float(visual.blade_length) * 0.65
			release = (visual.get_parent() as Node3D).global_transform * blade_point
	node.global_transform = Transform3D(_basis_facing(forward), release)
	add_child(node)

	var hitbox := CombatHitbox.new()
	hitbox.name = "WaveHitbox"
	hitbox.collision_layer = 0
	hitbox.collision_mask = HURTBOX_LAYER
	hitbox.source = source
	# A HITBOX IS NOTHING WITHOUT A SHAPE. `CombatHitbox._ready()` adopts the
	# `CollisionShape3D` child it finds and `configure()` sizes that copy — so an
	# `Area3D` built in code with no shape child is an area that CANNOT overlap
	# anything, and it fails the worst way available: `configure()` returns
	# without a word, `set_active()` flips `monitoring` and looks correct, the VFX
	# draws, the node travels and dies at its authored reach, and the crescent
	# passes through every body in the arena in complete silence. The scene's own
	# `SwordHitbox` has this child declared in the `.tscn`, which is why only the
	# runtime-built one was ever broken.
	var shape := CollisionShape3D.new()
	shape.name = "CollisionShape3D"
	shape.shape = BoxShape3D.new()
	hitbox.add_child(shape)
	# Added to the tree FIRST: `_ready()` runs here, adopts `shape`, and only then
	# can `configure()` do anything at all. Sizing before this point is a no-op.
	node.add_child(hitbox)
	# Thin across the plane of the cut, tall enough to cross a body, and a metre
	# deep so a wave covering 0.43m per physics frame cannot pass through anyone.
	hitbox.configure(Vector3(2.6, 1.9, 1.0), Vector3.ZERO)
	hitbox.damage = move.damage * damage_scale
	hitbox.poise_damage = move.poise_damage
	hitbox.element = move.element
	hitbox.impulse = 2.6
	hitbox.contact_filter = _accept_wave_contact.bind(move, _seen, (-_view_basis().x + Vector3.UP * 0.45).normalized())
	# THE WAVE HAS TO BE ABLE TO LAND. `CombatHitbox` reports an overlap on its
	# own signal, and only the node that OWNS the hitbox knows where a confirmed
	# overlap goes — the body rig's hitbox is wired up in the controller, and this
	# one is built at runtime, so without this line the crescent flies through
	# every body in the arena and nothing at all happens. It looked correct: the
	# VFX drew, the node travelled, the node died at its authored reach, and the
	# only observable was that mid-range targets were never cut.
	hitbox.hit_landed.connect(_on_wave_hit)
	hitbox.set_active(true)

	_waves.append({
		"node": node, "hitbox": hitbox, "move": move, "damage_scale": damage_scale,
		"travelled": 0.0, "alive": true,
		"reach": move.reach, "speed": maxf(move.reach_speed, 0.1),
	})
	wave_born.emit(node, move)
	return node


# A confirmed wave overlap, forwarded to the same landing path a sword hit and a
# space cut use. The wave is a third mechanism for REACHING something, not a
# third way for a hit to work: damage, poise, hitstop and the target's reaction
# are all decided downstream, once.
func _on_wave_hit(hit: Dictionary) -> void:
	if resolver == null or not is_instance_valid(resolver):
		return
	if not resolver.has_method("_on_hitbox_landed"):
		return
	# Tagged, so the controller can tell the wave apart from the blade it came out
	# of and can refuse the second cut if the blade wins the race the other way.
	hit["reach_mode"] = &"wave"
	resolver.call("_on_hitbox_landed", hit)


func _accept_wave_contact(hit: Dictionary, move: SwordMove, seen: Dictionary, direction := Vector3.ZERO) -> bool:
	var actor := hit.get("target") as Node3D
	if actor == null or seen.has(actor):
		return false
	seen[actor] = true
	hit["reach_mode"] = &"wave"
	hit["sword_move"] = move
	if not direction.is_zero_approx():
		hit["slash_direction"] = direction
	hit["sword_contact_accepted"] = true
	return resolver != null and bool(resolver.call("_accept_sword_contact", hit))


func _physics_process(delta: float) -> void:
	if _waves.is_empty():
		return
	var finished: Array[Dictionary] = []
	for i in _waves.size():
		var wave: Dictionary = _waves[i]
		if not wave["alive"]:
			finished.append(wave)
			continue
		var node: Node3D = wave["node"]
		if not is_instance_valid(node):
			wave["alive"] = false
			finished.append(wave)
			continue
		var step: float = wave["speed"] * delta
		wave["travelled"] = float(wave["travelled"]) + step
		node.global_position += -node.global_basis.z * step
		# The wave dies at its AUTHORED REACH and not at a lifetime in seconds: a
		# clip that arrives somewhere else because the speed was retuned is a
		# weapon whose range moved while nobody was looking.
		if float(wave["travelled"]) >= float(wave["reach"]):
			wave["alive"] = false
			var hitbox: CombatHitbox = wave["hitbox"]
			if is_instance_valid(hitbox):
				hitbox.set_active(false)
			finished.append(wave)
	if finished.is_empty():
		return
	for wave in finished:
		_waves.erase(wave)
		var node: Node3D = wave["node"]
		if not is_instance_valid(node):
			continue
		wave_died.emit(node)
		node.queue_free()


# ===========================================================================
# TRACE — A3. A cut that happens at a place.
# ===========================================================================

## Resolves one cut mark. Returns how many bodies were inside it.
##
## `mark` is one of `SwordMove.traces`: `{t, angle, reach, weight, offset}`. The
## cut is an angular window in the view plane plus a reach, exactly as the mark
## is drawn — see the header for why that is the only honest test.
func cut_trace(move: SwordMove, mark: Dictionary, damage_scale: float) -> int:
	if move == null:
		return 0
	var eye := _eye()
	var basis := _view_basis()
	var angle := deg_to_rad(float(mark.get("angle", 0.0)))
	var reach := float(mark.get("reach", move.reach))
	# 0 is to the right, positive is upward. `dir` runs along the cut; `across` is
	# the in-view-plane perpendicular, which is also the normal of the cut's plane
	# through the eye — so the thickness test and the mark the player sees are the
	# same measurement seen twice.
	var dir := (basis.x * cos(angle) + basis.y * sin(angle)).normalized()
	var across_axis := (basis.x * -sin(angle) + basis.y * cos(angle)).normalized()
	var offset := mark.get("offset", Vector2.ZERO) as Vector2
	# Where the line sits on the lens, in the same tangent units the window uses.
	var centre_across := float(offset.x) * -sin(angle) + float(offset.y) * cos(angle)
	var centre_along := float(offset.x) * cos(angle) + float(offset.y) * sin(angle)
	var half_len := move.trace_half_len_tan
	var half_thick := move.trace_half_thick_tan

	var damage := move.damage * float(mark.get("weight", 1.0)) * damage_scale
	var cut_id := int(mark.get("index", 0))
	if not _trace_seen.has(cut_id):
		_trace_seen[cut_id] = {}
	var cut_targets: Dictionary = _trace_seen[cut_id]
	var hits := 0
	for body in _bodies_within(eye, reach + QUERY_PADDING):
		var actor: Node3D = body["actor"]
		if cut_targets.has(actor):
			continue
		var local := basis.transposed() * ((body["point"] as Vector3) - eye)
		var depth := -local.z
		if depth < MIN_TRACE_DEPTH or depth > reach:
			continue
		# Tangent space: the mark lives here, and so does the test.
		var sx := local.x / depth
		var sy := local.y / depth
		if absf(_project(across_axis, basis, sx, sy) - centre_across) > half_thick:
			continue
		if absf(_project(dir, basis, sx, sy) - centre_along) > half_len:
			continue
		cut_targets[actor] = true
		_seen[actor] = true
		hits += 1
		_deliver(actor, damage, move, dir)
	trace_resolved.emit(int(mark.get("index", 0)), hits, mark)
	return hits


# A world direction expressed in the view plane, dotted with a tangent-space
# point. Written once because both axes of the window use it, and a second
# hand-rolled copy is how the length and the thickness end up measuring two
# different planes.
func _project(world_dir: Vector3, basis: Basis, sx: float, sy: float) -> float:
	return world_dir.dot(basis.x) * sx + world_dir.dot(basis.y) * sy


# ===========================================================================
# ARC — A4. A cut that goes around the player.
# ===========================================================================

## Resolves the slice of the sweep the blade is passing through between two
## angles. `from_deg`/`to_deg` are measured from the player's forward, positive
## toward the player's right.
##
## Sliced rather than resolved once, because the sweep TAKES TIME: a single query
## over the whole 270 degrees would strike a body that was behind the player
## before the blade had moved at all, which is a shockwave wearing a sword's
## animation. Each slice only covers the arc the blade is actually crossing.
func sweep_arc(move: SwordMove, slice_index: int, from_deg: float, to_deg: float, damage_scale: float) -> int:
	if move == null or move.reach_radius <= 0.0:
		return 0
	var origin := _eye()
	var forward := _flat_forward()
	var right := _flat_right(forward)
	var hits := 0
	for body in _bodies_within(origin, move.reach_radius + QUERY_PADDING):
		var actor: Node3D = body["actor"]
		if _seen.has(actor):
			continue
		var to_body: Vector3 = (body["point"] as Vector3) - origin
		var flat := Vector3(to_body.x, 0.0, to_body.z)
		var distance := flat.length()
		if distance > move.reach_radius or distance < 0.15:
			continue
		# Vertically the sweep is a cut at the body's own height: a horizontal
		# 270-degree arc does not reach somebody standing on a wall.
		if absf(to_body.y) > 2.2:
			continue
		var angle := rad_to_deg(atan2(flat.dot(right), flat.dot(forward)))
		if not angle_in_sweep(angle, from_deg, to_deg):
			continue
		_seen[actor] = true
		hits += 1
		_deliver(actor, move.damage * damage_scale, move)
	arc_resolved.emit(slice_index, hits, from_deg, to_deg)
	return hits


## Whether `angle` falls inside the sweep from `from_deg` to `to_deg`. Handles
## the wrap at 180 AND the possibility that the arc was authored backwards: an
## author writing `135 → -140` means the same 275 degrees as `-140 → 135`, and
## should not be rewarded with an attack that hits nothing.
static func angle_in_sweep(angle: float, from_deg: float, to_deg: float) -> bool:
	var span := to_deg - from_deg
	if absf(span) >= 360.0:
		return true
	if is_zero_approx(span):
		return false
	var relative := wrapf(angle - from_deg, -180.0, 180.0)
	return absf(relative) <= absf(span) and relative * signf(span) >= 0.0


# ===========================================================================
# Queries
# ===========================================================================

func _space_state() -> PhysicsDirectSpaceState3D:
	if source == null or not source.is_inside_tree():
		return null
	var world := source.get_world_3d()
	return world.direct_space_state if world != null else null


# Every live body in `radius` of `centre`, as `{actor, point}`. One ball query,
# then the cut's own angular test decides — the ball is a broadphase and is
# never allowed to be the thing that decides.
func _bodies_within(centre: Vector3, radius: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var space := _space_state()
	if space == null:
		return out
	var params := PhysicsShapeQueryParameters3D.new()
	var ball := SphereShape3D.new()
	ball.radius = maxf(radius, 0.5)
	params.shape = ball
	params.transform = Transform3D(Basis.IDENTITY, centre)
	params.collision_mask = HURTBOX_LAYER
	params.collide_with_areas = true
	params.collide_with_bodies = false
	for result in space.intersect_shape(params, 48):
		var area := result.get("collider") as Area3D
		if area == null or not (area is CombatHurtbox):
			continue
		var actor: Node3D = (area as CombatHurtbox).owner_actor
		if actor == null or actor == source or not is_instance_valid(actor):
			continue
		out.append({
			"actor": actor,
			"point": actor.global_position + Vector3.UP * BODY_SAMPLE_HEIGHT,
		})
	return out


func _deliver(actor: Node3D, damage: float, move: SwordMove, direction := Vector3.ZERO) -> void:
	var hit := {
		"damage": damage,
		"poise_damage": move.poise_damage * damage / maxf(move.damage, 0.001),
		"element": move.element,
		"element_scale": 1.0,
		"impulse": 2.4,
		"source": source,
		"target": actor,
		"reach_mode": move.reach_mode,
		"slash_direction": direction,
		"rising_cut": move.id == SwordBasic.A3 and direction.y > 0.75,
	}
	# Straight into the controller's single landing path — the same entry a
	# `CombatHitbox` uses. Distance is not a second way for a hit to work.
	if resolver != null and is_instance_valid(resolver) and resolver.has_method("_accept_sword_contact"):
		if not resolver.call("_accept_sword_contact", hit):
			return
	var hurtbox := actor.get_node_or_null("Hurtbox") as CombatHurtbox
	if hurtbox != null:
		hurtbox.receive_hit(hit)
		if resolver != null and is_instance_valid(resolver) and resolver.has_method("_on_hitbox_landed"):
			resolver.call("_on_hitbox_landed", hit)


# ===========================================================================
# Frames
# ===========================================================================
#
# The cut's frame is the VIEW's frame, not the body's, and it has to be: the
# player aims with the camera, so a cut drawn across the lens has to be measured
# across the lens. The camera is looked up rather than injected because every
# stage in this project builds its own player and none of them should have to
# remember to hand this node a camera.

func _camera() -> Camera3D:
	if source == null or not source.is_inside_tree():
		return null
	return source.get_viewport().get_camera_3d()


func _eye() -> Vector3:
	var camera := _camera()
	return camera.global_position if camera != null else global_position


func _view_basis() -> Basis:
	var camera := _camera()
	return camera.global_basis if camera != null else global_basis


func _forward() -> Vector3:
	return -_view_basis().z


func _flat_forward() -> Vector3:
	var forward := _forward()
	forward.y = 0.0
	if forward.length_squared() < 0.000001:
		return Vector3.FORWARD
	return forward.normalized()


func _flat_right(forward: Vector3) -> Vector3:
	# `forward × UP`, which is the RIGHT vector. The previous form built `UP ×
	# forward`, i.e. the LEFT one, and a left-handed frame is a MIRRORED frame:
	# every angle came back negated, so a body on the player's right measured as
	# if it were on the left. Nothing reported an error — an arc authored
	# `-140 → 130` still sweeps 270 degrees and still hits, it just sweeps the
	# other way round, so A4 started behind the right shoulder and finished
	# behind the left while the pose wound up on the left. Wrong-handed and
	# symmetrical enough to look deliberate.
	return Vector3(-forward.z, 0.0, forward.x).normalized()


## A basis whose -Z is `forward`, right-handed, with Y as close to world up as
## the direction allows. Built directly rather than with `look_at`, which needs
## the node to be in the tree and fails at zero length instead of returning
## something the caller can test.
static func _basis_facing(forward: Vector3) -> Basis:
	var f := forward.normalized()
	if f.length_squared() < 0.000001:
		return Basis.IDENTITY
	# `f.cross(UP)`, not `UP.cross(f)`: the second gives the LEFT vector, and a
	# left-handed basis is a mirrored basis — the wave would fly off mirrored and
	# nothing downstream would report an error.
	var right := f.cross(Vector3.UP)
	if right.length_squared() < 0.000001:
		right = Vector3.RIGHT
	right = right.normalized()
	return Basis(right, right.cross(f).normalized(), -f)
