extends Node3D
class_name PhantomChainVFX
# Hand anchor ring, idle phantom links, bind ring, tension pulse.
# Presentation only — no gameplay reads this.

var profile: PhantomChainProfile

var _hand_ring: MeshInstance3D
var _idle_links: Array[MeshInstance3D] = []
var _bind_ring: MeshInstance3D
var _pulse: MeshInstance3D

var _idle_timer := 1.2
var _idle_life := 0.0
var _equip_blend := 0.0
var _bind_flash := 0.0
var _pulse_life := 0.0
var _pulse_from := Vector3.ZERO
var _pulse_to := Vector3.ZERO
var equipped := false


func _ready() -> void:
	_build()


func configure(p: PhantomChainProfile) -> void:
	profile = p


func set_equipped(on: bool) -> void:
	equipped = on
	if not on:
		_equip_blend = 0.0
		_idle_life = 0.0
		_bind_flash = 0.0
		_pulse_life = 0.0
		_hide_all()


func play_equip() -> void:
	_equip_blend = 0.001


func show_bind_ring(at: Vector3) -> void:
	if _bind_ring == null:
		return
	_bind_ring.global_position = at + Vector3.UP * 0.9
	_bind_flash = 1.0
	_bind_ring.visible = true


func play_tension_wave(from: Vector3, to: Vector3) -> void:
	_pulse_from = from
	_pulse_to = to
	_pulse_life = profile.tension_wave_ms if profile else 0.18
	if _pulse != null:
		_pulse.visible = true


func update_hand(hand_pos: Vector3, delta: float) -> void:
	if _hand_ring == null:
		return
	if equipped and _equip_blend < 1.0:
		var dur := profile.equip_seconds if profile else 0.55
		_equip_blend = minf(1.0, _equip_blend + delta / maxf(0.05, dur))
	elif not equipped:
		_equip_blend = maxf(0.0, _equip_blend - delta * 4.0)

	_hand_ring.global_position = hand_pos
	_hand_ring.rotation.z += delta * 0.8
	var a := 0.0
	if _equip_blend > 0.0 and _equip_blend < 1.0:
		# Phase 1–3: ring + short float, then settle to faint ready.
		a = lerpf(0.0, 0.55, smoothstep(0.0, 0.45, _equip_blend))
		a = lerpf(a, 0.22, smoothstep(0.45, 1.0, _equip_blend))
	elif equipped:
		a = 0.18
	var mat := _hand_ring.material_override as StandardMaterial3D
	if mat != null:
		mat.albedo_color.a = a
	_hand_ring.visible = a > 0.02

	_update_idle(hand_pos, delta)
	_update_bind_ring(delta)
	_update_pulse(delta)


func _update_idle(hand_pos: Vector3, delta: float) -> void:
	if not equipped or _equip_blend < 0.95:
		for link in _idle_links:
			link.visible = false
		return
	_idle_timer -= delta
	if _idle_life > 0.0:
		_idle_life = maxf(0.0, _idle_life - delta)
		var k := _idle_life / 0.55
		for i in _idle_links.size():
			var link := _idle_links[i]
			var off := Vector3(
				0.08 + float(i) * 0.07,
				0.04 * sin(Time.get_ticks_msec() * 0.004 + float(i)),
				-0.10 - float(i) * 0.05
			)
			link.global_position = hand_pos + off
			link.rotate_y(delta * (1.2 + float(i) * 0.4))
			var m := link.material_override as StandardMaterial3D
			if m != null:
				m.albedo_color.a = 0.22 * k
			link.visible = k > 0.05
		return
	if _idle_timer <= 0.0:
		_idle_life = 0.55
		var lo := profile.idle_link_interval_min if profile else 0.8
		var hi := profile.idle_link_interval_max if profile else 2.0
		_idle_timer = randf_range(lo, hi)


func _update_bind_ring(delta: float) -> void:
	if _bind_ring == null:
		return
	if _bind_flash <= 0.0:
		_bind_ring.visible = false
		return
	_bind_flash = maxf(0.0, _bind_flash - delta * 2.2)
	_bind_ring.scale = Vector3.ONE * lerpf(1.6, 1.0, 1.0 - _bind_flash)
	var m := _bind_ring.material_override as StandardMaterial3D
	if m != null:
		m.albedo_color.a = 0.55 * _bind_flash


func _update_pulse(delta: float) -> void:
	if _pulse == null:
		return
	if _pulse_life <= 0.0:
		_pulse.visible = false
		return
	var total := profile.tension_wave_ms if profile else 0.18
	_pulse_life = maxf(0.0, _pulse_life - delta)
	var u := 1.0 - _pulse_life / maxf(0.01, total)
	_pulse.global_position = _pulse_from.lerp(_pulse_to, u)
	var m := _pulse.material_override as StandardMaterial3D
	if m != null:
		m.albedo_color.a = 0.55 * (1.0 - absf(u - 0.5) * 2.0)


func _hide_all() -> void:
	if _hand_ring != null:
		_hand_ring.visible = false
	for link in _idle_links:
		link.visible = false
	if _bind_ring != null:
		_bind_ring.visible = false
	if _pulse != null:
		_pulse.visible = false


func _build() -> void:
	_hand_ring = _ghost_torus("HandAnchor", 0.035, 0.055, Color(0.75, 0.85, 0.98, 0.2))
	add_child(_hand_ring)
	for i in 3:
		var link := _ghost_torus("IdleLink%d" % i, 0.018, 0.032, Color(0.7, 0.8, 0.95, 0.2))
		link.visible = false
		add_child(link)
		_idle_links.append(link)
	_bind_ring = _ghost_torus("BindRing", 0.35, 0.42, Color(0.7, 0.85, 1.0, 0.5))
	_bind_ring.visible = false
	add_child(_bind_ring)
	_pulse = MeshInstance3D.new()
	_pulse.name = "TensionPulse"
	var sphere := SphereMesh.new()
	sphere.radius = 0.06
	sphere.height = 0.12
	_pulse.mesh = sphere
	_pulse.material_override = _ghost_mat(Color(0.85, 0.92, 1.0, 0.5))
	_pulse.visible = false
	add_child(_pulse)


func _ghost_torus(node_name: String, inner: float, outer: float, col: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	var torus := TorusMesh.new()
	torus.inner_radius = inner
	torus.outer_radius = outer
	torus.rings = 10
	torus.ring_segments = 14
	mi.mesh = torus
	mi.material_override = _ghost_mat(col)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visible = false
	return mi


func _ghost_mat(col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = col
	m.emission_enabled = true
	m.emission = Color(col.r, col.g, col.b)
	m.emission_energy_multiplier = 0.45
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = false
	return m
