extends SceneTree
# MEASURE THE CHAIN LOOP'S REAL CADENCE.
#
# The review package's chain clips claim to show A1 → A2 → A3. `combat_movie_renderer`
# already refuses to let a take lie about that — it prints "light played ch_sweep,
# but this take claims ch_throw" — and it caught this package's first spacing at
# 0.70s doing exactly that.
#
# So the spacing is a MEASUREMENT, not a guess. Two things are needed:
#
#   1. the loop's own reason for restarting (the trace), and
#   2. the cadence at which it does NOT restart (the sweep).
#
# A press is modelled the way the renderer models it: scheduled at an ABSOLUTE
# time, then retried frame by frame until the chain accepts it. That matters,
# because a press fired too early is REFUSED (`_can_act()`), not buffered, so a
# "one press, read once" experiment would measure the wrong thing entirely.

const SCENE := "res://scenes/combat/CombatSandbox.tscn"
const DT := 1.0 / 60.0

var chain
var trace := false


func _initialize() -> void:
	var sandbox := (load(SCENE) as PackedScene).instantiate() as Node3D
	root.add_child(sandbox)
	for i in 5:
		await process_frame
	var player := sandbox.get_node("Player")
	chain = player.get_node("ChainDirector")
	var mgr := player.get_node_or_null("WeaponManager")
	if mgr != null:
		mgr.call("equip_weapon", &"chain")
	else:
		player.get_node("WeaponSlot").call("equip", &"chain")
	for i in 5:
		await process_frame
	# The chain's own _process must not advance the clock while this probe owns it.
	chain.set_process(false)

	var moveset = chain.get("moveset")
	print("light_window    = %.2f s" % float(moveset.get("light_window")))
	print("light_chain     = %s" % str(moveset.get("light_chain")))
	print("home_radius     = %.2f    max_radius = %.2f"
		% [float(moveset.get("home_radius")), float(moveset.get("max_radius"))])
	for id in [&"ch_sweep", &"ch_return", &"ch_throw"]:
		var m = _move(id)
		if m != null:
			print("  %-10s startup=%.2f active=%.2f recovery=%.2f  authored=%.2f"
				% [String(id), float(m.startup), float(m.active), float(m.recovery),
					float(m.startup) + float(m.active) + float(m.recovery)])

	print("\n### CADENCE SWEEP — three presses at an absolute interval")
	for gap in [0.40, 0.50, 0.58, 0.62, 0.66, 0.70, 0.78, 0.90]:
		var got := _trial(gap)
		var ok: bool = got.size() == 3 and got[0] == &"ch_sweep" \
			and got[1] == &"ch_return" and got[2] == &"ch_throw"
		print("  gap %.2fs -> %-44s %s" % [gap, str(got), "A1/A2/A3 OK" if ok else "RESTARTED"])

	quit(0)


func _move(id: StringName):
	var lib = chain.get("move_library")
	if lib == null:
		return null
	for key in lib.keys():
		if key == id:
			return lib[key]
	return null


func _trial(gap: float, verbose := false) -> Array:
	chain.call("reset")
	_advance(90)
	var out: Array = []
	var elapsed := 0.0
	for k in 3:
		var scheduled := float(k) * gap
		while elapsed < scheduled:
			_advance(1)
			elapsed += DT
		var tries := 0
		var accepted := false
		while not accepted and tries < 90:
			accepted = chain.call("request", &"light")
			if not accepted:
				_advance(1)
				elapsed += DT
			tries += 1
		if verbose:
			print("    press %d  at t=%.2f  accepted=%s after %d frame(s)"
				% [k, elapsed, str(accepted), tries])
		if accepted:
			out.append(chain.get("active_move").id)
		else:
			out.append(&"REFUSED")
	if verbose:
		print("    final state=%s  index=%d"
			% [str(chain.get("state")), int(chain.get("_chain_index"))])
	return out


func _advance(n: int) -> void:
	for i in n:
		chain.call("step", DT)
		if trace:
			var m = chain.get("active_move")
			print("      t=%.2f  state=%-10s idle=%.2f  index=%d  move=%s  r=%.2f"
				% [float(chain.get("state_time")), str(chain.get("state")),
					float(chain.get("_idle_time")), int(chain.get("_chain_index")),
					String(m.id) if m != null else "-", float(chain.get("radius"))])
