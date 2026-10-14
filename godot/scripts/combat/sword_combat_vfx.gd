extends Node3D
class_name SwordCombatVFX
signal weapon_event(event: StringName, payload: Dictionary)
const PRESENTATION_CONFIG = preload("res://resources/tuning/SwordPresentationConfig.tres")
var _contacts: Array[Dictionary] = []
var _contact_mesh: ImmediateMesh
var _contact_visual: MeshInstance3D
var visuals_enabled := true
# SEKAI · WHAT THE FOUR BEATS LOOK AND SOUND LIKE
#
# ===========================================================================
# ONE LISTENER, OR THE SENTENCE HAS FOUR AUTHORS
# ===========================================================================
#
# §23 says audio and VFX listen to the move's ANIMATION EVENTS and never guess a
# time. So this node is the listener, and it does two things with what it hears:
# it draws, and it asks the audio director for the sound the event names. One
# listener is the point — if VFX kept one clock and audio kept another, A3's
# third mark and A3's third sound would be two different moments inside one
# gesture, and the beat that exists to be COUNTED would be the one that drifts.
#
# Nothing in this file decides what a cut HITS. Damage, poise, hitstop and the
# reach queries belong to the controller and to `SwordReach`; an event here is
# something the move SAYS. The one place this file and the gameplay half could
# have drifted — A3's three marks — is closed by drawing on the signal
# `SwordReach` emits WHEN it resolves a cut, so the mark and the hit are produced
# by the same call and cannot be a frame apart.
#
# ===========================================================================
# FOUR BEATS, FOUR MECHANISMS, ONE PALETTE (§24)
# ===========================================================================
#
#   A1  a HAIRLINE. Not drawn here: A1 declares `trail_width_scale = 0.42` and
#       the existing blade ribbon becomes the thinnest line in the sentence.
#       A second trail drawn on top of the first is how a thin line becomes a
#       thick one nobody meant to make.
#   A2  a CRESCENT that leaves the blade, built as a child of the wave node so
#       the thing that can hit somebody and the thing the player watches are one
#       transform. No particles anywhere (§5): a cut that only reads because
#       sparks are flying is a cut that does not read.
#   A3  three MARKS IN SPACE, drawn at the instant `SwordReach` resolved them.
#       Each mark is the cut's own angular window — the same two numbers the hit
#       test used — so what is drawn is what was tested, at any depth.
#   A4  a MAJOR ARC with a beginning and an end, built slice by slice from the
#       six `arc_resolved` callbacks in the order the blade crossed them. §14 is
#       explicit that this must not read as a shockwave, and the thing that stops
#       it reading as one is that the ribbon is longer at the end than at the
#       beginning — the opposite of an expanding sphere.
#
# The palette is one palette: white, pale cyan, grey-blue. The four beats are
# told apart by DISTANCE, RHYTHM and the SAYA, so four colours would be
# describing a difference that is already fully described.

# ---------------------------------------------------------------- palette
const WHITE := Color(0.97, 0.99, 1.0)
const PALE_CYAN := Color(0.86, 0.91, 0.94)
# The dark half. Not black: a cut in the air is a shade of the sky, and pure
# black in a pale courtyard reads as a hole rather than as pressure.
const GREY_BLUE := Color(0.30, 0.40, 0.52)

# ------------------------------------------------------------- A2 crescent
## Radius of the crescent, in metres. It has to cover a standing body, because
## the wave's own hitbox is 1.9 m tall — a crescent visibly smaller than what it
## hits teaches the player the wrong size.
const CRESCENT_RADIUS := 1.00
## How much of a circle the crescent occupies, either side of its axis.
const CRESCENT_SPAN := 0.92
## Inner radius as a fraction of the outer. Wide enough to be a visible band,
## narrow enough to stay a crescent: at 0.80 this is a compressed arc, not a ring.
const CRESCENT_INNER := 0.93
## How much the crescent widens across its own flight (§5: "width grows mildly").
const CRESCENT_GROWTH := 1.24
## The brighter leading band, as a fraction of the crescent's band.
const CRESCENT_EDGE := 0.20
const CRESCENT_STEPS := 14

# ------------------------------------------------------------- A3 the marks
## The opening beat of a mark: it WIDENS once as it appears. A cut that pops into
## existence at full width reads as a decal; one that opens reads as a cut.
const SCAR_OPEN := 0.045
## Held, so the eye can count them. A3's three cuts are ~0.18 s apart and the
## brief asks for structure the eye can count, which means cut 1 must still be on
## screen when cut 3 arrives — a mark that has already faded is one mark seen
## three times.
const SCAR_HOLD := 0.46
const SCAR_FADE := 0.55
## World-space thickness of the two bright edges, in metres. Deliberately a WORLD
## width and not an angular one: the fill IS the tested window and therefore
## grows with depth, and an edge that grew with it would draw the same band
## twice. The edge is the drawn line; the fill is the cut.
##
## 0.020 WAS INVISIBLE AT THE RANGE IT IS DRAWN AT. A3 reaches 16 m and the mark
## is brightest at the near end, so the far end — which is where the far body
## actually is — is the thinnest and dimmest part of the picture. At 16 m a 2 cm
## line subtends about 1.5 px at 720p: sub-pixel after filtering. That is why
## pass 05's three cuts washed into haze instead of reading as three lines: the
## countable part of the mark was thinner than a pixel at the distance the beat
## is about. 0.034 is ~2.5 px there and still a line, not a band.
const SCAR_EDGE_WIDTH := 0.034
const SCAR_FILL_SLICES := 5

# ------------------------------------------------------------- A4 the arc
## The band's width across the sweep, in metres. A 優弧 on a human body is a
## blade's sweep, not a wall: wider than a blade would read as a shockwave.
##
## 0.32 WAS A WALL. Pass 05 is why this is 0.13. At eye level and a 3-5 m radius,
## a 32 cm ribbon subtends about 4.6 degrees, which is roughly 100 px of height at
## 720p — and a 100 px tall, semi-transparent pale-cyan band wrapped 270 degrees
## around the viewer does not read as a blade going past. It reads as a sheet of
## water standing in the air, which is what every A4 frame in that pass looked
## like: the white head was legible and the sweep it was leading was not.
##
## 0.13 is 1.9 degrees, ~41 px: the head is now obviously the widest part of the
## thing it belongs to, which is what "leading edge" is supposed to mean.
const ARC_BAND := 0.07
## How far the sweep rises across its travel (§14: "略有高度变化，不要绝对数学圆").
const ARC_LIFT := 0.22
## How much the radius breathes. Same reason, on the other axis.
const ARC_BREATH := 0.055
## A cut that is still there is not a cut: the head fades last, so the read is
## "the blade went past here", not "a ring exists here now".
const ARC_LIFE := 0.55
## Subdivisions per slice along the arc. Six slices of this many points is a
## smooth sweep without a mesh budget anyone has to think about.
const ARC_SUBDIV := 5

# ------------------------------------------------------------------ tuning
## 0..1+ multiplier on everything this node draws. A reviewer can turn the layer
## off and check that the GAMEPLAY still reads without it, which is the only
## honest test of whether an effect is decoration.
var intensity := 1.0
## When false, A3's domain window is ignored. Used while the Iaido ceremony is
## being reviewed, where the camera is already held by another director.
var domain_enabled := true
## When false, the SPATIAL CUT PLANES are not drawn at all.
##
## §15 of the Saya Controlled Stillness pass asks for exactly this and gives both
## options -- "lowered or switched off" -- because `intensity` is not enough on
## its own for a close-in review camera. The A3 marks are windows in space: a
## trapezoid whose half-width and half-thickness are the cut's own ANGULAR
## tolerances times depth, so at the move's reach they are a band 21 m wide and
## 3 m thick. A review camera 4 m from a subject 1 m across is INSIDE that band,
## and at any alpha that makes it read as a cut in the air it is the loudest thing
## in the frame -- drawn straight across the blade and the scabbard the clip
## exists to compare.
##
## The ribbon and the crescent are not affected: they are what says WHEN the cut
## happened, and a motion clip without them loses half its evidence.
var scars_enabled := true


## §15's switch, as a method so a caller does not have to know the flag's name.
## Turning it off also clears any mark already on screen, because a plane drawn
## before the switch was thrown is still a plane in the frame.
func set_scars_enabled(enabled: bool) -> void:
	scars_enabled = enabled
	if enabled:
		return
	for scar in _scars:
		var node: Node3D = scar["node"]
		if is_instance_valid(node):
			node.queue_free()
	_scars.clear()

var controller: CombatController
var reach: SwordReach
var audio: Node

# Per-move bookkeeping, reset from the controller's `move_started` — A1's
# `SwordMove` is the SAME Resource object every time it is used, so comparing
# instances would let the second A1 of a session fire no events at all.
var _move: SwordMove
var _fired: Dictionary = {}

var _waves: Array[Dictionary] = []
var _scars: Array[Dictionary] = []
var _arc_bands: Array[Dictionary] = []
var _arc_mesh: ImmediateMesh
var _arc_visual: MeshInstance3D
var _arc_head_mesh: ImmediateMesh
var _arc_head: MeshInstance3D
var _arc_core: StandardMaterial3D
var _arc_head_material: StandardMaterial3D

# The domain's own contribution, remembered so it can be given back. Every field
# used here belongs to another system at other times (`sustain_fov` to the chain
# ultimate, the screen focus to the ceremony), so this node never assumes it
# started from zero — it restores what it found.
var _domain_active := false
var _domain_prev_still := 0.0
var _domain_prev_sustain := 0.0
var _domain_prev_focus := 0.0


func _ready() -> void:
	_build_arc_visual()
	_contact_mesh = ImmediateMesh.new()
	_contact_visual = MeshInstance3D.new()
	_contact_visual.name = "SwordContactSparks"
	_contact_visual.mesh = _contact_mesh
	_contact_visual.material_override = _make_material(WHITE,1.0,true)
	_contact_visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_contact_visual)


## Binds the layer to the three things it listens to: the move's clock (the
## controller), the moment a cut happened (`SwordReach`) and the sound.
func bind(p_controller: CombatController, p_reach: SwordReach, p_audio: Node) -> void:
	_unbind()
	controller = p_controller
	reach = p_reach
	audio = p_audio
	if reach != null:
		reach.wave_born.connect(_on_wave_born)
		reach.wave_died.connect(_on_wave_died)
		reach.trace_resolved.connect(_on_trace_resolved)
		reach.arc_resolved.connect(_on_arc_resolved)
	if controller != null:
		controller.move_started.connect(_on_move_started)
		controller.hit_landed.connect(_on_contact)
		controller.perfect_guard_landed.connect(_on_parry)
		controller.swing_started.connect(_on_swing)


func _unbind() -> void:
	if reach != null and is_instance_valid(reach):
		if reach.wave_born.is_connected(_on_wave_born):
			reach.wave_born.disconnect(_on_wave_born)
		if reach.wave_died.is_connected(_on_wave_died):
			reach.wave_died.disconnect(_on_wave_died)
		if reach.trace_resolved.is_connected(_on_trace_resolved):
			reach.trace_resolved.disconnect(_on_trace_resolved)
		if reach.arc_resolved.is_connected(_on_arc_resolved):
			reach.arc_resolved.disconnect(_on_arc_resolved)
	if controller != null and is_instance_valid(controller):
		if controller.move_started.is_connected(_on_move_started):
			controller.move_started.disconnect(_on_move_started)
		for pair in [[controller.hit_landed,_on_contact],[controller.perfect_guard_landed,_on_parry],[controller.swing_started,_on_swing]]:
			if pair[0].is_connected(pair[1]):
				pair[0].disconnect(pair[1])


func _exit_tree() -> void:
	# The domain changes values the rest of the game reads. Leaving the room with
	# the lens still squeezed would be one beat's property outliving the beat.
	_release_domain()


func _process(delta: float) -> void:
	_tick_move_events()
	_tick_domain()
	_tick_waves(delta)
	_tick_scars(delta)
	_tick_arc(delta)
	_tick_contacts(delta)


# ===========================================================================
# The move's clock
# ===========================================================================

func _on_move_started(move: SwordMove) -> void:
	_move = move
	_fired.clear()


## Fires every event the move has reached and has not said yet.
##
## The move AND its clock come from the controller in one answer
## (`presentation_clock`), because the two questions — "which move" and "how far
## in" — must not be askable separately: a listener that read A1's clock next to
## the draw's move would fire the wrong three sounds during a weapon switch.
##
## The clock is the move's OWN, so a draw bonus that shortens the wind-up by 22%
## moves the cut with it rather than firing A3's second cut before its first.
func _tick_move_events() -> void:
	if controller == null:
		return
	var clock := controller.presentation_clock()
	# The draw events do not play backward; sheathe has its own physical receipts.
	if clock.get("reverse",false):
		_move = null
		_fired.clear()
		return
	var move: SwordMove = clock.get("move") as SwordMove
	if move == null:
		# Nothing is being presented. Only the events that describe a beat CLOSING
		# are flushed: a cut cancelled before it happened has no cut to report.
		if _fired.size() > 0:
			_flush_closing_events()
		return
	if move != _move:
		_move = move
		_fired.clear()
	var raw := float(clock.get("time", 0.0))
	for entry in move.events:
		var event_id: StringName = entry.get("id", &"")
		if event_id == &"" or _fired.has(event_id):
			continue
		if raw < float(entry.get("t", 0.0)):
			continue
		_fired[event_id] = true
		_announce(event_id)


## The move is over. Only the events that describe a beat CLOSING are flushed: a
## cut cancelled before it happened has no cut to report, so the three space cuts
## are never invented. A beat's own close is different — if a style shortened the
## recovery enough that the authored instant falls past the end, the move still
## finished, and saying so late is true while saying nothing at all is not.
func _flush_closing_events() -> void:
	if _move == null:
		return
	for entry in _move.events:
		var event_id: StringName = entry.get("id", &"")
		if event_id == &"" or _fired.has(event_id):
			continue
		if not SwordBasic.is_closing_event(event_id):
			continue
		_fired[event_id] = true
		_announce(event_id)


## One event becomes a sound. The visual half is already handled by whichever
## signal produced the geometry, so there is nothing to draw from here — and the
## asymmetry is deliberate: sound is safe to play from a clock, geometry is not.
func _announce(event_id: StringName) -> void:
	if event_id in [SwordBasic.EV_DRAW,SwordBasic.EV_EQUIP_GLINT]:
		emit_weapon_event(&"SWORD_DRAW",{"move":String(_move.id) if _move != null else ""})
	var audio_event := SwordBasic.audio_for_event(event_id)
	if audio_event == &"":
		return
	if audio == null or not is_instance_valid(audio) or not audio.has_method("play_event"):
		return
	# A cut that happens fourteen metres away must not be heard in the hands that
	# made it (PART M). The position comes from the move's own mark rather than
	# from the camera: what is heard is where the cut WAS.
	var at := _event_position(event_id)
	audio.call("play_event", audio_event, _event_intensity(event_id), &"", at, at != Vector3.ZERO)


## Where an audible instant happened, or zero for a sound that belongs to the
## player's own hands. Only the two events that are genuinely somewhere else are
## given a position; everything else is a swing, and a swing is in the arms.
func _event_position(event_id: StringName) -> Vector3:
	if event_id == SwordBasic.EV_WAVE:
		for wave in _waves:
			var node: Node3D = wave["node"]
			if is_instance_valid(node):
				return node.global_position
		return Vector3.ZERO
	if event_id in [SwordBasic.EV_CUT_1, SwordBasic.EV_CUT_2, SwordBasic.EV_CUT_3]:
		var camera := _camera()
		if camera == null or _move == null:
			return Vector3.ZERO
		var want := _event_time(event_id)
		for mark in _move.traces:
			if absf(float(mark.get("t", -1.0)) - want) > 0.001:
				continue
			var angle := deg_to_rad(float(mark.get("angle", 0.0)))
			var basis := camera.global_basis
			var dir := (basis.x * cos(angle) + basis.y * sin(angle)).normalized()
			# Halfway along the mark: the near end is the player's own shoulder and
			# the far end is where the cut stopped, so the middle is the cut.
			var depth := float(mark.get("reach", 16.0))
			var offset: Vector2 = mark.get("offset", Vector2.ZERO)
			return camera.global_position - basis.z * depth + basis.x * offset.x * depth + basis.y * offset.y * depth
	return Vector3.ZERO


func _event_time(event_id: StringName) -> float:
	if _move == null:
		return -1.0
	for entry in _move.events:
		if entry.get("id", &"") == event_id:
			return float(entry.get("t", -1.0))
	return -1.0


func _event_intensity(event_id: StringName) -> float:
	if event_id in [SwordBasic.EV_CUT_1, SwordBasic.EV_CUT_2, SwordBasic.EV_CUT_3]:
		return 0.85
	if event_id == SwordBasic.EV_ARC_START:
		return 1.0
	if event_id in [SwordBasic.EV_SHEATH_TOUCH, SwordBasic.EV_A3_SHEATHE]:
		return 0.55
	return 0.7


# ===========================================================================
# A3's micro domain (§6)
# ===========================================================================
#
# The one beat allowed to change the WORLD instead of the pose: the camera stops
# moving, the lens squeezes, and the room loses a little of its colour — enough
# that the player feels the beat is different, not so much that the world stops.
# §26 asks for the camera to be STABLE here rather than kicked, which is why this
# is a sustained envelope and not an impulse: three marks in half a second cannot
# be counted through a shake.
#
# WHAT IS DELIBERATELY NOT HERE: an ambient audio duck. §6 lists it as an option
# and it is skipped on purpose — this project has no ambience bus, and the only
# music bus is owned by `combat_music.gd`. A second writer to a value another
# system owns shows up later as "the music went quiet and never came back", so
# the beat is carried by the camera and the lens instead.
func _tick_domain() -> void:
	if controller == null or _move == null or not domain_enabled or not _move.has_domain():
		_release_domain()
		return
	var clock := controller.presentation_clock()
	if (clock.get("move") as SwordMove) != _move:
		_release_domain()
		return
	var raw := float(clock.get("time", 0.0))
	var from := _move.domain_from
	var to := _move.domain_to
	if raw < from or raw > to:
		_release_domain()
		return
	var u := clampf((raw - from) / maxf(to - from, 0.0001), 0.0, 1.0)
	# In fast, out slowly: the world leans in to listen and then lets go, rather
	# than a pause button being pressed and released.
	var opening := clampf((raw - from) / 0.05, 0.0, 1.0)
	var closing := 1.0 - clampf((u - 0.62) / 0.38, 0.0, 1.0)
	_apply_domain(opening * closing)


func _apply_domain(amount: float) -> void:
	if not _domain_active:
		_domain_prev_still = controller.camera_feedback.iaido_still
		_domain_prev_sustain = controller.camera_feedback.sustain_fov
		_domain_prev_focus = controller.screen_fx.desaturation
		_domain_active = true
	var k := clampf(amount, 0.0, 1.0) * intensity
	# Stillness, not a freeze: `set_iaido_still` suppresses the gait, the shake
	# and the trauma decay. At 0.55 the camera is settled enough to read three
	# marks and still moving enough that the player does not think time stopped.
	controller.camera_feedback.set_iaido_still(_domain_prev_still + k * 0.55)
	# A sustained -1.6° is a compression you feel and cannot point at. An event
	# kick would have decayed before the second cut, which is the wrong shape:
	# the whole point is that the beat HOLDS.
	controller.camera_feedback.sustain_fov = _domain_prev_sustain - k * 1.6
	controller.screen_fx.set_iaido_focus(_domain_prev_focus + k * 0.30)


func _release_domain() -> void:
	if not _domain_active:
		return
	_domain_active = false
	if controller == null or not is_instance_valid(controller):
		return
	controller.camera_feedback.set_iaido_still(_domain_prev_still)
	controller.camera_feedback.sustain_fov = _domain_prev_sustain
	controller.screen_fx.set_iaido_focus(_domain_prev_focus)


# ===========================================================================
# A2 · the crescent that leaves the blade
# ===========================================================================

func _on_wave_born(node: Node3D, move: SwordMove) -> void:
	if not visuals_enabled:
		return
	if node == null or not is_instance_valid(node):
		return
	# A CARRIER, not the wave node itself. The wave node has the hitbox as its
	# child, so scaling the node to make the crescent grow would grow the thing
	# that decides hits — a visual tuning change silently lengthening a weapon.
	var carrier := Node3D.new()
	carrier.name = "Crescent"
	node.add_child(carrier)
	var body := _make_material(GREY_BLUE, 0.16, false)
	var edge := _make_material(WHITE, 0.78, true)
	_add_crescent(carrier, "CrescentBody", body, 1.0)
	_add_crescent(carrier, "CrescentEdge", edge, CRESCENT_EDGE)
	_waves.append({
		"node": node,
		"carrier": carrier,
		"body": body,
		"edge": edge,
		"start": node.global_position,
		"reach": maxf(move.reach, 0.001) if move != null else 1.0,
	})


func _on_wave_died(node: Node3D) -> void:
	for i in _waves.size():
		if _waves[i]["node"] == node:
			_waves.remove_at(i)
			return


func _tick_waves(_delta: float) -> void:
	if _waves.is_empty():
		return
	for wave in _waves:
		var node: Node3D = wave["node"]
		if not is_instance_valid(node):
			continue
		# The wave's own TRAVEL is the clock, not a lifetime in seconds: a fade
		# driven by seconds would drift against the flight the moment anybody
		# retuned `reach_speed`, and the visual would end somewhere the hitbox
		# did not.
		var u := clampf(
			float(wave["start"].distance_to(node.global_position)) / float(wave["reach"]),
			0.0, 1.0,
		)
		var carrier: Node3D = wave["carrier"]
		if is_instance_valid(carrier):
			# Widening mildly and thinning as it flies: the crescent spends its
			# shape travelling rather than arriving the size it left.
			carrier.scale = Vector3(lerpf(1.0, CRESCENT_GROWTH, u), lerpf(1.0, 0.86, u), 1.0)
		_set_alpha(wave["body"], lerpf(0.16, 0.03, u) * intensity)
		_set_alpha(wave["edge"], lerpf(0.78, 0.20, u) * intensity)


## One band of the crescent, in the carrier's local space with -Z forward — the
## frame `SwordReach._basis_facing` gives the wave node. `band` is the fraction
## of the arc's thickness this band occupies, so the leading edge is built by the
## same function at a hair's width instead of by a second piece of geometry that
## would have to be kept in step by hand.
func _add_crescent(carrier: Node3D, part_name: String, material: StandardMaterial3D, band: float) -> void:
	var mesh := ImmediateMesh.new()
	var outer := CRESCENT_RADIUS
	var thickness := CRESCENT_RADIUS * (1.0 - CRESCENT_INNER) * band
	var inner := outer - thickness
	var tint := material.albedo_color
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in CRESCENT_STEPS + 1:
		var u := float(i) / float(CRESCENT_STEPS)
		var angle := lerpf(-CRESCENT_SPAN, CRESCENT_SPAN, u)
		# Tapering to nothing at the horns, because a crescent with blunt ends is
		# a bracket.
		var taper := 0.30 + 0.70 * sin(u * PI)
		var dir := Vector3(sin(angle), cos(angle), 0.0)
		mesh.surface_set_color(tint)
		mesh.surface_add_vertex(dir * inner)
		mesh.surface_add_vertex(dir * (inner + thickness * taper))
	mesh.surface_end()
	var part := MeshInstance3D.new()
	part.name = part_name
	part.mesh = mesh
	part.material_override = material
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	carrier.add_child(part)


# ===========================================================================
# A3 · three marks in space
# ===========================================================================

## Draws the cut `SwordReach` just resolved. Taking the geometry from the signal
## rather than from a clock is what makes "the mark the player sees" and "the
## window that was tested" one object: the signal is emitted from inside the
## resolution, so they cannot be a frame apart even if the move is retuned.
func _on_trace_resolved(_index: int, _hits: int, mark: Dictionary) -> void:
	if not visuals_enabled:
		return
	# §15: the plane can be switched off and the mark then simply is not made.
	# Checked HERE rather than in `_tick_scars`, because a mark that is built and
	# then hidden still costs the mesh and still lights nothing.
	if not scars_enabled:
		return
	var camera := _camera()
	if camera == null:
		return
	var eye := camera.global_position
	var basis := camera.global_basis
	var angle := deg_to_rad(float(mark.get("angle", 0.0)))
	var offset := mark.get("offset", Vector2.ZERO) as Vector2
	# The direction the mark runs, and the axis its thickness is measured on.
	# `across` is ALSO the normal of the cut's plane through the eye — the same
	# fact `SwordReach.cut_trace` tests against, restated as geometry, which is
	# why the drawn line and the tested window cannot disagree.
	var dir := (basis.x * cos(angle) + basis.y * sin(angle)).normalized()
	var across := (basis.x * -sin(angle) + basis.y * cos(angle)).normalized()
	# The mark's own offset, moved onto those two axes so the three cuts of A3 do
	# not all pass through one point — three lines meeting at one place read as a
	# starburst, which is a UI glyph rather than a sword technique.
	var centre := eye
	var forward := -basis.z + basis.x * offset.x + basis.y * offset.y
	var node := Node3D.new()
	node.name = "SpaceScar"
	add_child(node)
	var fill := _scar_material(GREY_BLUE, eye, -basis.z, dir, offset.dot(Vector2(cos(angle),sin(angle))))
	var edge := _scar_material(PALE_CYAN, eye, -basis.z, dir, offset.dot(Vector2(cos(angle),sin(angle))))
	_build_scar_fill(node, centre, forward, dir, across, float(mark.get("reach", 16.0)), fill)
	_build_scar_edges(node, centre, forward, dir, across, float(mark.get("reach", 16.0)), edge)
	_scars.append({"node": node, "fill": fill, "edge": edge, "age": 0.0})


## The cut's window, drawn as what it is: a trapezoid whose half-width along the
## blade and half-thickness normal to it are the cut's own ANGULAR tolerances
## multiplied by depth. Drawn as a fixed-width slab it would be a mark that
## disagrees with its own test the first time somebody stood at the far end of it.
func _build_scar_fill(node: Node3D, eye: Vector3, forward: Vector3, dir: Vector3,
		across: Vector3, reach: float, material: Material) -> void:
	var half_len: float = _move.trace_half_len_tan if _move != null else 0.72
	var half_thick: float = _move.trace_half_thick_tan if _move != null else 0.11
	var near_d := SwordReach.MIN_TRACE_DEPTH
	var far_d := maxf(reach, near_d + 1.0)
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	# Two surfaces, one on each side of the cut's own plane. Both are needed
	# because the player is standing IN the plane: a single sheet would be edge-on
	# to the only eye that ever looks at it, i.e. invisible. The thickness is what
	# makes a plane into a thing you can see, and it is the same trick
	# `ShadowCutMark` uses at the other end of the game.
	for i in SCAR_FILL_SLICES:
		var d0 := lerpf(near_d, far_d, float(i) / float(SCAR_FILL_SLICES))
		var d1 := lerpf(near_d, far_d, float(i + 1) / float(SCAR_FILL_SLICES))
		# Fading with depth: a 3 m band at 14 m is honest geometry and a lie as a
		# solid colour.
		#
		# The near end came down from 0.34 in pass 06 and the far end went UP from
		# 0.10, which flattens the ramp: the wedge is the cut's angular tolerance
		# and it is 23 m wide at full reach, so it can only ever be the pressure
		# around the line. Left bright at the near end it was the loudest thing in
		# the frame — brighter than the two hairlines that are the actual cut —
		# which is the whole reason the three marks read as a wash.
		var alpha := lerpf(0.20, 0.14, float(i) / float(SCAR_FILL_SLICES))
		mesh.surface_set_color(Color(GREY_BLUE.r, GREY_BLUE.g, GREY_BLUE.b, alpha))
		for side in [-1.0, 1.0]:
			for vertex in _window_quad(eye, forward, dir, across, d0, d1, half_len, half_thick, side):
				mesh.surface_add_vertex(vertex)
	mesh.surface_end()
	_attach_scar_mesh(node, "ScarFill", mesh, material)


## The two bright boundaries of the window, at a small WORLD width so the line
## stays a line at fourteen metres. This is the part that reads as the cut; the
## fill is the pressure around it.
func _build_scar_edges(node: Node3D, eye: Vector3, forward: Vector3, dir: Vector3,
		across: Vector3, reach: float, material: Material) -> void:
	var half_len: float = _move.trace_half_len_tan if _move != null else 0.72
	var near_d := SwordReach.MIN_TRACE_DEPTH
	var far_d := maxf(reach, near_d + 1.0)
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var steps := 9
	for side in [-1.0, 1.0]:
		for i in steps:
			var d0 := lerpf(near_d, far_d, float(i) / float(steps))
			var d1 := lerpf(near_d, far_d, float(i + 1) / float(steps))
			# Brightest where the cut was made and dying outward: the near end is
			# the sword, the far end is where the cut stopped being the sword.
			#
			# The far end is 0.42 rather than 0.22 because the far end is the half
			# of the mark that has a body in it: A3's far target is at 15 m, and a
			# line that has faded to a fifth of its brightness by the time it
			# arrives is a line that only tells the story at the player's feet.
			var alpha := lerpf(0.95, 0.42, float(i) / float(steps))
			mesh.surface_set_color(Color(PALE_CYAN.r, PALE_CYAN.g, PALE_CYAN.b, alpha))
			for vertex in _hairline_quad(eye, forward, dir, across, d0, d1, half_len, side):
				mesh.surface_add_vertex(vertex)
	mesh.surface_end()
	_attach_scar_mesh(node, "ScarEdge", mesh, material)


func _attach_scar_mesh(node: Node3D, part_name: String, mesh: ImmediateMesh, material: Material) -> void:
	var instance := MeshInstance3D.new()
	instance.name = part_name
	instance.mesh = mesh
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.add_child(instance)


## Four corners of one side of the window between two depths, as two triangles.
## `magnitude` selects which of the window's two bounding surfaces this is.
func _window_quad(eye: Vector3, forward: Vector3, dir: Vector3, across: Vector3,
		d0: float, d1: float, half_len: float, half_thick: float, magnitude: float) -> Array[Vector3]:
	var a := eye + forward * d0 + dir * (half_len * d0 * -1.0) + across * (half_thick * d0 * magnitude)
	var b := eye + forward * d0 + dir * (half_len * d0) + across * (half_thick * d0 * magnitude)
	var c := eye + forward * d1 + dir * (half_len * d1) + across * (half_thick * d1 * magnitude)
	var d := eye + forward * d1 + dir * (half_len * d1 * -1.0) + across * (half_thick * d1 * magnitude)
	return [a, b, c, a, c, d]


func _hairline_quad(eye: Vector3, forward: Vector3, dir: Vector3, across: Vector3,
		d0: float, d1: float, half_len: float, side: float) -> Array[Vector3]:
	var half := SCAR_EDGE_WIDTH * 0.5
	var p0 := eye + forward * d0 + dir * (half_len * d0 * side)
	var p1 := eye + forward * d1 + dir * (half_len * d1 * side)
	return [
		p0 - across * half, p0 + across * half, p1 - across * half,
		p1 - across * half, p0 + across * half, p1 + across * half,
	]


func _tick_scars(delta: float) -> void:
	if _scars.is_empty():
		return
	var dying: Array[Dictionary] = []
	for scar in _scars:
		scar["age"] = float(scar["age"]) + delta
		var age := float(scar["age"])
		(scar["fill"] as ShaderMaterial).set_shader_parameter("progress",minf(age / SCAR_OPEN,1.0))
		(scar["edge"] as ShaderMaterial).set_shader_parameter("progress",minf(age / SCAR_OPEN,1.0))
		var alpha := 1.0
		if age < SCAR_OPEN:
			# Opens: a cut appearing is a cut WIDENING, and a mark that pops into
			# existence at full strength reads as a decal that was always there.
			alpha = age / SCAR_OPEN
		elif age > SCAR_OPEN + SCAR_HOLD:
			alpha = 1.0 - clampf((age - SCAR_OPEN - SCAR_HOLD) / SCAR_FADE, 0.0, 1.0)
		var fade := clampf(alpha, 0.0, 1.0) * intensity
		# The bright edges go first and the pressure outlives them: what stays on
		# the screen last is the cut, not the highlight.
		_set_alpha(scar["fill"], 0.34 * fade)
		_set_alpha(scar["edge"], 0.95 * fade * fade)
		if fade <= 0.001:
			dying.append(scar)
	for scar in dying:
		_scars.erase(scar)
		var node: Node3D = scar["node"]
		if is_instance_valid(node):
			node.queue_free()
	# The age is driven by the scaled delta and not by a wall clock on purpose:
	# the marks must hold through A3's own hitstop, and `Time.get_ticks_msec()`
	# would fade them on a different schedule every time a hit stopped the world.


# ===========================================================================
# A4 · the major arc
# ===========================================================================

## Appends the piece of the sweep the blade just crossed.
##
## Built in sweep order, which is the only reason the ribbon has a head and a
## tail: the geometry is a record of where the blade HAS been, so at any instant
## the far end is the beginning of the cut and the near end is where the blade
## is. §14's START and END are not two decorations bolted on — they are what the
## slice-by-slice build already means.
func _on_arc_resolved(slice_index: int, _hits: int, from_deg: float, to_deg: float) -> void:
	if not visuals_enabled:
		return
	var camera := _camera()
	if camera == null:
		return
	var forward := _flat_forward(camera)
	_arc_bands.append({
		"from": from_deg,
		"to": to_deg,
		"index": slice_index,
		"age": 0.0,
		# The radius and the span are captured WITH the slice rather than read
		# live from the move: A4's ribbon has to outlive A4 (it is still fading
		# when the next input lands), and a band drawn on whatever move happens to
		# be active would change shape the instant the player pressed anything.
		"radius": maxf(_move.reach_radius, 0.5) if _move != null else 4.0,
		"span": maxf(absf(_move.reach_arc_to - _move.reach_arc_from), 1.0) if _move != null else 270.0,
		"sweep_from": _move.reach_arc_from if _move != null else from_deg,
		# The frame is captured per slice, so a player who turns during the sweep
		# gets the arc they actually cut rather than one re-projected afterwards.
		"origin": camera.global_position,
		"forward": forward,
		"right": _flat_right(forward),
	})


func _build_arc_visual() -> void:
	_arc_mesh = ImmediateMesh.new()
	_arc_core = _make_material(PALE_CYAN, 1.0, true)
	_arc_visual = MeshInstance3D.new()
	_arc_visual.name = "MajorArcTrail"
	_arc_visual.mesh = _arc_mesh
	_arc_visual.material_override = _arc_core
	_arc_visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_arc_visual)
	# The head has its own mesh and material so the leading edge can be whiter
	# than the body without a second colour language: the trail is cyan, the
	# place the blade is RIGHT NOW is white — that is §14's END, said in colour.
	_arc_head_mesh = ImmediateMesh.new()
	_arc_head_material = _make_material(WHITE, 1.0, true)
	_arc_head = MeshInstance3D.new()
	_arc_head.name = "MajorArcHead"
	_arc_head.mesh = _arc_head_mesh
	_arc_head.material_override = _arc_head_material
	_arc_head.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_arc_head)


func _tick_arc(delta: float) -> void:
	if _arc_bands.is_empty():
		return
	var live: Array[Dictionary] = []
	for band in _arc_bands:
		band["age"] = float(band["age"]) + delta
		if float(band["age"]) <= ARC_LIFE:
			live.append(band)
	_arc_bands = live
	if _arc_bands.is_empty():
		_arc_mesh.clear_surfaces()
		_arc_head_mesh.clear_surfaces()
		_arc_visual.visible = false
		_arc_head.visible = false
		return
	_arc_mesh.clear_surfaces()
	_arc_head_mesh.clear_surfaces()
	var last_index := maxf(1.0, float(_arc_bands.size() - 1))
	_arc_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for band in _arc_bands:
		var alive := 1.0 - clampf(float(band["age"]) / ARC_LIFE, 0.0, 1.0)
		# The tail is dimmer than the head even before anything starts fading:
		# the blade has already left that part of the circle, and a trail that is
		# uniformly bright is a drawn shape rather than a record of motion.
		var along := lerpf(0.55, 1.0, clampf(float(band["index"]) / last_index, 0.0, 1.0))
		var alpha := alive * along * intensity
		for vertex in _band_vertices(band, float(band["radius"]), float(band["span"])):
			_arc_mesh.surface_set_color(Color(PALE_CYAN.r, PALE_CYAN.g, PALE_CYAN.b, vertex["alpha"] * alpha * 0.28))
			_arc_mesh.surface_add_vertex(vertex["point"])
	_arc_mesh.surface_end()
	# The head: a bright cap on the newest band plus a short spur pointing where
	# the blade is going. Without it the ribbon is a shape; with it the shape is
	# a cut that is still moving.
	var newest: Dictionary = _arc_bands[_arc_bands.size() - 1]
	var head_alpha := (1.0 - clampf(float(newest["age"]) / (ARC_LIFE * 0.45), 0.0, 1.0)) * intensity
	_arc_head_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for vertex in _head_vertices(newest, float(newest["radius"]), float(newest["span"])):
		_arc_head_mesh.surface_set_color(Color(WHITE.r, WHITE.g, WHITE.b, vertex["alpha"] * head_alpha))
		_arc_head_mesh.surface_add_vertex(vertex["point"])
	_arc_head_mesh.surface_end()
	_arc_visual.visible = true
	_arc_head.visible = head_alpha > 0.01


## One slice of the sweep, as triangles covering the band from the inner to the
## outer edge at each point. Subdivided along the arc so the sweep is a curve and
## not a chord between two slice boundaries.
func _band_vertices(band: Dictionary, radius: float, span: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var a0 := float(band["from"])
	var a1 := float(band["to"])
	for i in ARC_SUBDIV:
		var t0 := float(i) / float(ARC_SUBDIV)
		var t1 := float(i + 1) / float(ARC_SUBDIV)
		var p0 := _arc_point(band, lerpf(a0, a1, t0), radius, span)
		var p1 := _arc_point(band, lerpf(a0, a1, t1), radius, span)
		# Thinner at the far end of the sweep than at the near one, so the ribbon
		# visibly opens up as it travels: the arc is a cut through the world, not
		# a ring that was always there at one width.
		var u0 := clampf(absf(lerpf(a0, a1, t0) - float(band["sweep_from"])) / maxf(span, 0.001), 0.0, 1.0)
		var u1 := clampf(absf(lerpf(a0, a1, t1) - float(band["sweep_from"])) / maxf(span, 0.001), 0.0, 1.0)
		var w0 := ARC_BAND * lerpf(0.70, 1.0, u0)
		var w1 := ARC_BAND * lerpf(0.70, 1.0, u1)
		var v0: Vector3 = p0["centre"]
		var v1: Vector3 = p1["centre"]
		for tri in [
			[v0 - Vector3.UP * w0, v0 + Vector3.UP * w0, v1 - Vector3.UP * w1],
			[v1 - Vector3.UP * w1, v0 + Vector3.UP * w0, v1 + Vector3.UP * w1],
		]:
			for point in tri:
				out.append({"point": point, "alpha": 0.95})
	return out


func _head_vertices(band: Dictionary, radius: float, span: float) -> Array[Dictionary]:
	var a1 := float(band["to"])
	var tip := _arc_point(band, a1, radius, span)
	var ahead := _arc_point(band, a1 + signf(float(band["to"]) - float(band["from"])) * 7.0, radius, span)
	var centre: Vector3 = tip["centre"]
	var spur: Vector3 = ((ahead["centre"] as Vector3) - centre).normalized()
	var width := ARC_BAND * 0.95
	var out: Array[Dictionary] = []
	# A cap across the blade's track, and an arrowhead past it: the cap says the
	# blade is here, the spur says it is still going.
	for tri in [
		[centre - Vector3.UP * width, centre + Vector3.UP * width, centre + spur * 0.20],
		[centre + spur * 0.20 - Vector3.UP * width * 0.45,
			centre + spur * 0.20 + Vector3.UP * width * 0.45,
			centre + spur * 0.28],
	]:
		for point in tri:
			out.append({"point": point, "alpha": 0.85})
	return out


## A point on the sweep. The height and the radius both breathe across the travel
## so the arc is a cut through a world and not a circle drawn on one — §14 asks
## for exactly that and warns against the absolute mathematical circle.
func _arc_point(band: Dictionary, angle_deg: float, radius: float, span: float) -> Dictionary:
	var forward: Vector3 = band["forward"]
	var right: Vector3 = band["right"]
	var a := deg_to_rad(angle_deg)
	var u := clampf(absf(angle_deg - float(band["sweep_from"])) / maxf(span, 0.001), 0.0, 1.0)
	var dir := (forward * cos(a) + right * sin(a)).normalized()
	var r := radius * (1.0 + ARC_BREATH * sin(u * PI))
	var centre: Vector3 = band["origin"] + dir * r + Vector3.UP * (sin(u * PI) * ARC_LIFT - 0.25)
	return {"centre": centre, "dir": dir}


# ===========================================================================
# Shared bits
# ===========================================================================

func emit_weapon_event(event: StringName, payload: Dictionary = {}) -> void:
	var data := payload.duplicate()
	data["version"] = 1
	data["combat_time"] = controller.combat_time if is_instance_valid(controller) else 0.0
	weapon_event.emit(event,data)

func _on_swing(move: SwordMove) -> void:
	emit_weapon_event(&"SWORD_SWING",{"move":String(move.id),"reach_mode":String(move.reach_mode)})

func _on_contact(move: SwordMove, hit: Dictionary) -> void:
	var actor := hit.get("target") as Node3D
	if not is_instance_valid(actor):
		return
	var surface := "body"
	for group in ["metal","stone","wood"]:
		if actor.is_in_group("surface_" + group):
			surface = group
	var point := actor.global_position + Vector3.UP * 0.95
	var tint := Color(1.0,0.87,0.62) if surface == "metal" else Color(0.92,0.94,0.98)
	emit_weapon_event(&"SWORD_HIT",{"move":String(move.id),"position":point,"direction":hit.get("slash_direction",Vector3.ZERO),"surface":surface})
	_spawn_contact(point,tint,false)

func _on_parry() -> void:
	var sword := controller.get_parent().find_child("TempSwordVisual",true,false) as Node3D
	if sword == null:
		return
	var point := sword.global_transform * Vector3(0,0.35,0)
	emit_weapon_event(&"SWORD_PARRY",{"position":point,"surface":"metal"})
	_spawn_contact(point,Color(1.0,0.91,0.70),true)

func _spawn_contact(point: Vector3, tint: Color, parry: bool) -> void:
	if not visuals_enabled:
		return
	if _contacts.size() >= 12:
		_contacts.pop_front()
	_contacts.append({"point":point,"tint":tint,"age":0.0,"life":PRESENTATION_CONFIG.parry_lifetime if parry else PRESENTATION_CONFIG.contact_lifetime,"size":PRESENTATION_CONFIG.impact_scale * (1.6 if parry else 1.0)})

func _tick_contacts(delta: float) -> void:
	if _contact_mesh == null:
		return
	_contact_mesh.clear_surfaces()
	for i in range(_contacts.size()-1,-1,-1):
		_contacts[i].age = float(_contacts[i].age)+delta
		if float(_contacts[i].age) >= float(_contacts[i].life):
			_contacts.remove_at(i)
	_contact_visual.visible = not _contacts.is_empty() and visuals_enabled
	if _contacts.is_empty():
		return
	var camera := _camera()
	if camera == null:
		return
	_contact_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for contact in _contacts:
		var u := clampf(float(contact.age)/float(contact.life),0,1)
		var color: Color = contact.tint
		color.a = (1.0-u)*(1.0-u)*intensity
		var origin: Vector3 = contact.point
		for i in 7:
			var angle := float(i)*TAU/7.0 + 0.31
			var direction := camera.global_basis.x*cos(angle)+camera.global_basis.y*sin(angle)
			var normal := camera.global_basis.x*-sin(angle)+camera.global_basis.y*cos(angle)
			var start := origin+direction*float(contact.size)*u*0.5
			var end := origin+direction*float(contact.size)*(0.45+u)
			for vertex in [start-normal*0.006,start+normal*0.006,end]:
				_contact_mesh.surface_set_color(color)
				_contact_mesh.surface_add_vertex(vertex)
	_contact_mesh.surface_end()

func _camera() -> Camera3D:
	if not is_inside_tree():
		return null
	return get_viewport().get_camera_3d()


func _flat_forward(camera: Camera3D) -> Vector3:
	var forward := -camera.global_basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.000001:
		return Vector3.FORWARD
	return forward.normalized()


func _flat_right(forward: Vector3) -> Vector3:
	return Vector3(-forward.z, 0.0, forward.x).normalized()


func _make_material(tint: Color, alpha: float, additive: bool) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.vertex_color_use_as_albedo = true
	if additive:
		# Additive is what makes a white line read as LIGHT rather than as paint
		# laid over a pale courtyard. The dark fill is the opposite call: additive
		# cannot darken anything, so pressure has to be alpha-blended.
		material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.albedo_color = Color(tint.r, tint.g, tint.b, alpha)
	return material


func _set_alpha(material: Material, alpha: float) -> void:
	if material == null:
		return
	if material is ShaderMaterial:
		material.set_shader_parameter("opacity",clampf(alpha,0.0,1.0))
	else:
		var standard := material as StandardMaterial3D
		var c := standard.albedo_color
		standard.albedo_color = Color(c.r,c.g,c.b,clampf(alpha,0.0,1.0))


## What is on screen right now. Used by the acceptance sheet, which has to prove
## the four beats look like four beats without leaning on a reviewer's memory.
func debug_readout() -> Dictionary:
	return {
		"move": String(_move.id) if _move != null else "",
		"events_fired": _fired.size(),
		"waves": _waves.size(),
		"scars": _scars.size(),
		"arc_bands": _arc_bands.size(),
		"domain": _domain_active,
	}


func _scar_material(tint: Color, eye: Vector3, forward: Vector3, direction: Vector3, offset: float) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = preload("res://resources/shaders/sword_scar_reveal.gdshader")
	material.set_shader_parameter("tint",tint)
	material.set_shader_parameter("cut_eye",eye)
	material.set_shader_parameter("cut_forward",forward)
	material.set_shader_parameter("cut_direction",direction)
	material.set_shader_parameter("cut_offset",offset)
	material.set_shader_parameter("half_length",_move.trace_half_len_tan if _move != null else 0.72)
	return material
