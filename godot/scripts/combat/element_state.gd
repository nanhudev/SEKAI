extends RefCounted
class_name ElementState
# Per-actor element tracking. Holds numbers only — it has no idea what "frost"
# or "fire" mean, and it never touches health, states or positions. It answers
# "how much is on me" and "did the stage change", and the actor decides what to
# do about it.
#
# This is what lets the same element rules apply to a dummy, a boss and a
# destructible crate without any of them copying the if-chain.

var entries: Dictionary = {}


func _entry(def: ElementDefinition) -> Dictionary:
	var key := def.id
	if not entries.has(key):
		entries[key] = {
			"def": def,
			"value": 0.0,
			"tick_left": 0.0,
			"since_apply": 999.0,
			"stage": 0,
		}
	return entries[key]


func value(id: StringName) -> float:
	if not entries.has(id):
		return 0.0
	return entries[id]["value"]


func set_value(id: StringName, amount: float) -> void:
	if not entries.has(id):
		return
	entries[id]["value"] = maxf(0.0, amount)
	entries[id]["stage"] = entries[id]["def"].stage_index_for(entries[id]["value"])


func stage_index(def: ElementDefinition) -> int:
	if not entries.has(def.id):
		return 0
	return entries[def.id]["stage"]


func stage_name(def: ElementDefinition) -> StringName:
	if not def.has_ladder():
		return &""
	var index := stage_index(def)
	return def.stage_names[index]


func has(def: ElementDefinition) -> bool:
	return entries.has(def.id) and entries[def.id]["value"] > 0.0


func is_top_stage(def: ElementDefinition) -> bool:
	return def.has_ladder() and def.is_final_stage(stage_index(def))


# Returns the stage index AFTER the application, so the caller can react to a
# transition (frost reaching Frozen is the interesting moment, not the number).
func apply(def: ElementDefinition, amount: float) -> int:
	var entry := _entry(def)
	entry["value"] = maxf(0.0, float(entry["value"]) + amount)
	entry["since_apply"] = 0.0
	entry["stage"] = def.stage_index_for(entry["value"])
	return int(entry["stage"])


func refresh_dot(def: ElementDefinition) -> void:
	var entry := _entry(def)
	entry["tick_left"] = def.tick_interval


func clear(id: StringName) -> void:
	if entries.has(id):
		entries[id]["value"] = 0.0
		entries[id]["stage"] = 0
		entries[id]["tick_left"] = 0.0


func clear_all() -> void:
	for key in entries:
		entries[key]["value"] = 0.0
		entries[key]["stage"] = 0
		entries[key]["tick_left"] = 0.0
		entries[key]["since_apply"] = 999.0


func active_ids() -> Array:
	var out := []
	for key in entries:
		if entries[key]["value"] > 0.0:
			out.append(key)
	return out


# Pure time passing: decay every value, tick every running damage-over-time.
# Returns the damage that should be dealt this frame plus the transitions that
# happened, because the actor needs to know "fire just burned out" and "frost
# just climbed a stage" without polling.
func update(delta: float) -> Dictionary:
	var tick_total := 0.0
	var tick_poise := 0.0
	var transitions: Array = []
	var expired: Array = []
	for key in entries:
		var entry: Dictionary = entries[key]
		var def: ElementDefinition = entry["def"]
		# One element can make another fall away faster (burning thaws frost).
		var decay := def.decay_rate
		for other_key in entries:
			if other_key == key:
				continue
			var other: Dictionary = entries[other_key]
			var other_def: ElementDefinition = other["def"]
			if other["value"] > 0.0 and def.id in other_def.hastens_decay_of:
				decay *= other_def.hasten_multiplier
		entry["since_apply"] = float(entry["since_apply"]) + delta
		if float(entry["value"]) > 0.0 and float(entry["since_apply"]) >= def.decay_delay:
			var before: int = entry["stage"]
			entry["value"] = maxf(0.0, float(entry["value"]) - decay * delta)
			entry["stage"] = def.stage_index_for(entry["value"])
			if int(entry["stage"]) != before:
				transitions.append({"def": def, "from": before, "to": int(entry["stage"])})
			if is_zero_approx(float(entry["value"])):
				entry["value"] = 0.0
				expired.append(def)
		if not def.has_ladder() and def.tick_damage > 0.0 and float(entry["value"]) > 0.0:
			entry["tick_left"] = float(entry["tick_left"]) - delta
			if float(entry["tick_left"]) <= 0.0:
				entry["tick_left"] = def.tick_interval
				tick_total += def.tick_damage
				tick_poise += def.tick_poise
		elif def.has_ladder() and def.tick_damage > 0.0 and entry["stage"] > 0:
			entry["tick_left"] = float(entry["tick_left"]) - delta
			if float(entry["tick_left"]) <= 0.0:
				entry["tick_left"] = def.tick_interval
				tick_total += def.tick_damage
				tick_poise += def.tick_poise
	return {"tick_damage": tick_total, "tick_poise": tick_poise, "transitions": transitions, "expired": expired}
