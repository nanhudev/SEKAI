extends SceneTree
## Dumps the combat numbers that decide FEEL, so a review document never has to
## quote them from memory.
##
## WHY THIS EXISTS. The review package hand-writes `CHAIN_CURRENT_VALUES.md` and
## `MOVEMENT_VALUES.md`, and both of those are read by someone who cannot check
## them: a reviewer with no repository. A hand-copied tuning value that has drifted
## from the resource is therefore worse than no document at all - it is a
## confident wrong statement about the build. So the numbers are PRINTED FROM THE
## LIVE RESOURCES here and pasted from this output, exactly the way the audio cues
## come from `dump_iaido_cues.gd` rather than from a list someone maintained.
##
## It reads and prints. It mutates nothing.
##
##   G:/Godot/Godot_v4.4.1-stable_win64_console.exe --headless --path godot \
##     --script res://tools/dump_combat_values.gd

const TUNING := "res://resources/tuning/CombatTuning.tres"


func _initialize() -> void:
	_dump_tuning()
	_dump_chain_geometry()
	_dump_chain_moves()
	_dump_sword_styles()
	quit()


func _dump_tuning() -> void:
	var t := load(TUNING) as CombatTuning
	print("### MOVEMENT / TIMING TUNING  (", TUNING, ")")
	if t == null:
		print("  !! tuning failed to load")
		return
	# Named one at a time on purpose: a generic property sweep would also print the
	# resource's script path and every group marker, and a dump nobody reads is a
	# dump that stops being updated.
	for name in [
		"walk_speed", "sprint_speed", "walk_pace", "jog_accel_rate", "sprint_accel_rate",
		"stop_accel", "brake_accel", "slope_up_cost", "slope_down_gain",
		"jump_velocity", "dodge_duration", "dodge_iframes", "dodge_stamina_cost",
		"evade_hitstop", "input_buffer", "combo_window", "followup_grace",
		"light_hitstop", "heavy_hitstop", "perfect_guard_window",
		"heavy_charge_time", "heavy_tap_grace", "player_stagger_threshold",
		"shatter_hitstop", "signature_cooldown",
		"light_camera_impulse", "heavy_camera_impulse", "shake_decay",
		"max_stamina", "max_mana",
		"iaido_range", "iaido_cone_degrees",
	]:
		print("  %-26s %s" % [name, str(t.get(name))])


func _dump_chain_geometry() -> void:
	var chain := ChainLibrary.build()
	print("\n### CHAIN GEOMETRY  (", chain.get_class(), " id=", chain.id, ")")
	for name in [
		"chain_length", "max_radius", "min_radius", "head_radius", "links",
		"link_spacing", "radius_momentum_scale",
		"coil_per_loop", "coil_max", "coil_min", "coil_radius", "coil_pitch",
		"home_radius", "home_height", "home_azimuth_degrees", "retract_time",
		"momentum_max", "momentum_decay",
		"retract_overshoot", "retract_out",
		"tension_ratio", "tension_window", "tension_knee", "tension_rise", "tension_fall",
		"taut_fov", "taut_snap_trauma", "taut_feel_threshold",
		"impact_speed_ref", "impact_hitstop_min", "impact_hitstop_max",
		"hook_bite_time", "pull_distance", "yank_share", "pull_tugs", "pull_tug_gap",
		"light_window", "deflect_perfect_window",
		"movement_scale_orbit", "orbit_max_hold", "orbit_min_hold", "orbit_damage",
	]:
		print("  %-26s %s" % [name, str(chain.get(name))])
	# The coil count is DERIVED from the rope, so print the derivation rather than
	# letting the document imply `coil_max` was chosen on its own (§26).
	print("  -- derived --")
	print("  %-26s %.3f" % ["coil_max implied by rope", chain.chain_length / chain.coil_per_loop])
	print("  %-26s %.3f" % ["links implied by rope", chain.chain_length / chain.link_spacing])
	print("  %-26s %.3f" % ["taut radius", chain.max_radius * chain.tension_ratio])
	print("  %-26s %.3f" % ["rope left in hand while taut", chain.chain_length - chain.max_radius])


func _dump_chain_moves() -> void:
	var chain := ChainLibrary.build()
	print("\n### CHAIN MOVES")
	print("  light_chain = ", chain.light_chain)
	print("  heavy_id=", chain.heavy_id, "  hook_id=", chain.hook_id,
		"  taut_light=", chain.taut_light_id, "  taut_heavy=", chain.taut_heavy_id,
		"  bound_light=", chain.bound_light_id, "  bound_heavy=", chain.bound_heavy_id,
		"  deflect=", chain.deflect_id)
	var ids := chain.move_ids()
	ids.sort()
	for id in ids:
		var m: ChainMove = chain.get_move(id)
		var total: float = m.startup + m.active + m.recovery
		print("\n  --- %s  (%s)  path=%d  total=%.3fs" % [id, m.display_name, m.path, total])
		print("      startup=%.3f  active=%.3f  recovery=%.3f" % [m.startup, m.active, m.recovery])
		print("      damage=%.1f  poise=%.1f  impulse=%.1f  hitstop=%.3f  trauma=%.2f  fov=%.2f" % [
			m.damage, m.poise_damage, m.impulse, m.impact_hitstop, m.camera_trauma, m.fov_kick])
		print("      radius %.2f -> %.2f   height %.2f -> %.2f" % [
			m.radius_from, m.radius_to, m.height_from, m.height_to])
		print("      azimuth0=%.1f  arc1=%.1f  arc2=%.1f  split=%.2f  carry=%.1f  ease=%d/%.1f" % [
			m.start_azimuth_degrees, m.arc_degrees, m.arc_degrees_2, m.arc_split,
			m.carry_anticipation_degrees, m.ease, m.ease_power])
		print("      continue_from_head=%s  steer=%.2f  mom_gain=%.2f  mom_whiff=%.2f  mom_cost=%.2f" % [
			str(m.continue_from_head), m.steer, m.momentum_gain, m.momentum_whiff_cost,
			m.impact_momentum_cost])


func _dump_sword_styles() -> void:
	print("\n### SWORD STYLES")
	for style_id in SwordMovesetLibrary.all_styles():
		var ms: SwordMoveset = SwordMovesetLibrary.build(style_id)
		print("\n  --- %s  (%s)  implemented=%s" % [style_id, ms.display_name, str(ms.implemented)])
		if ms.tagline != "":
			print("      tagline: ", ms.tagline)
		print("      light_chain=%s  heavy=%s  riposte=%s" % [
			str(ms.light_chain), str(ms.heavy_id), str(ms.riposte_id)])
		print("      signature=%s  ultimate=%s" % [str(ms.signature_id), str(ms.ultimate_id)])
		print("      combo_window=%.3f  dodge_cancel_from=%.2f" % [ms.combo_window, ms.dodge_cancel_from])
		print("      flow_enabled=%s  flow_max=%.0f  gain_hit=%.0f  min_recovery=%.2f" % [
			str(ms.flow_enabled), ms.flow_max, ms.flow_gain_hit, ms.flow_min_recovery])
		if ms.guard != null:
			print("      guard: dmg_mult=%.2f  stam/hit=%.1f  heavy_x%.1f  pg_window=%.3f  parry=%.2fs" % [
				ms.guard.damage_multiplier, ms.guard.stamina_per_hit,
				ms.guard.heavy_stamina_multiplier, ms.guard.perfect_guard_window,
				ms.guard.parry_duration])
		for skill in ms.skills:
			print("      skill: %s (%s)" % [str(skill.id), str(skill.display_name)])
		var m_ids := ms.moves.keys()
		m_ids.sort()
		for id in m_ids:
			var m: SwordMove = ms.moves[id]
			print("        %-14s startup=%.3f strike=%.3f follow=%.3f recovery=%.3f  dmg=%.1f poise=%.1f hitstop=%.3f" % [
				str(id), m.startup, m.strike, m.follow_time, m.recovery,
				m.damage, m.poise_damage, m.hitstop])
