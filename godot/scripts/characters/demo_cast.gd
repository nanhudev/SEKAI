extends RefCounted
## DEMO_CAST -- the cast manifest loader (SEKAI / C-PH line).
##
## ROLE != MODEL.  `character_id` is the story identity and never changes;
## `placeholder_model` is the rehearsal costume and is expected to be replaced.
## Narrative, dialogue and quest code reference ONLY the character_id.  When the
## real model arrives, one line changes in resources/cast/demo_cast.json and
## nothing else in the project moves.
##
## Deliberately NOT a `class_name`.  Adding one rewrites Godot's global class
## cache, and every other session sharing this working tree would have to re-import.
## Consumers do:
##
##     const DemoCast = preload("res://scripts/characters/demo_cast.gd")
##     var actor: Dictionary = DemoCast.actor("vell")
##     var node := DemoCast.spawn("vell")
##
## Data lives in res://resources/cast/demo_cast.json and is cross-checked against
## the actual bakes by tools/character/validate_cast.py.  `problems()` is the
## in-engine half: it catches what Python cannot -- a GLB that exists on disk but
## failed to become a Godot resource.

const MANIFEST_PATH := "res://resources/cast/demo_cast.json"

static var _manifest: Dictionary = {}
static var _loaded := false


# ---------------------------------------------------------------- raw access

static func manifest() -> Dictionary:
	if not _loaded:
		_loaded = true
		if not FileAccess.file_exists(MANIFEST_PATH):
			push_error("[DEMOCAST] missing %s" % MANIFEST_PATH)
			return {}
		var f := FileAccess.open(MANIFEST_PATH, FileAccess.READ)
		if f == null:
			push_error("[DEMOCAST] cannot open %s" % MANIFEST_PATH)
			return {}
		var parsed: Variant = JSON.parse_string(f.get_as_text())
		f.close()
		if typeof(parsed) != TYPE_DICTIONARY:
			push_error("[DEMOCAST] %s is not a JSON object" % MANIFEST_PATH)
			return {}
		_manifest = parsed as Dictionary
	return _manifest


static func characters() -> Array:
	var m := manifest()
	return m.get("characters", []) as Array


static func ids() -> PackedStringArray:
	var out := PackedStringArray()
	for c in characters():
		out.append(String((c as Dictionary).get("character_id", "")))
	return out


static func find(character_id: String) -> Dictionary:
	for c in characters():
		var d := c as Dictionary
		if String(d.get("character_id", "")) == character_id:
			return d
	return {}


# ---------------------------------------------------------------- story-facing API
# Everything below is what narrative code should use.  None of it exposes a model
# path: that is the whole point of the file.

static func actor(character_id: String) -> Dictionary:
	var a := find(character_id)
	if a.is_empty():
		push_error("[DEMOCAST] no such character_id: '%s' (known: %s)"
				% [character_id, ", ".join(ids())])
	return a


static func display_name(character_id: String) -> String:
	var a := find(character_id)
	return String(a.get("display_name", character_id))


static func scene_role(character_id: String) -> String:
	return String(find(character_id).get("scene_role", ""))


static func model_path(character_id: String) -> String:
	return String(find(character_id).get("placeholder_model", ""))


## The name of the skeleton profile this role is bound to.  Two roles share a
## profile only if their rigs behave identically -- see validate_cast.py.
static func skeleton_profile_name(character_id: String) -> String:
	return String(find(character_id).get("skeleton_profile", ""))


static func skeleton_profile(character_id: String) -> Dictionary:
	var n := skeleton_profile_name(character_id)
	var profiles := manifest().get("skeleton_profiles", {}) as Dictionary
	return profiles.get(n, {}) as Dictionary


## The per-character motion intent: base-motion tweaks plus the action ids this
## role still needs.  An empty dictionary means "registered, no animation pass"
## (second_candidate), which is a decision, not an omission.
static func motion(character_id: String) -> Dictionary:
	var ap := String(find(character_id).get("animation_profile", ""))
	if ap == "":
		return {}
	var profiles := manifest().get("animation_profiles", {}) as Dictionary
	return profiles.get(ap, {}) as Dictionary


## The list of action ids this role must be able to play.  This is the authoring
## backlog in machine-readable form -- see the brief's P0/P1 ordering.
static func required_actions(character_id: String) -> PackedStringArray:
	var out := PackedStringArray()
	for a in (motion(character_id).get("actions", []) as Array):
		out.append(String(a))
	return out


## Which library clips exist right now to serve a shared motion name.
static func clips_for(motion_name: String) -> PackedStringArray:
	var out := PackedStringArray()
	var base := manifest().get("base_motions", {}) as Dictionary
	var spec := base.get(motion_name, {}) as Dictionary
	for c in (spec.get("clips", []) as Array):
		out.append(String(c))
	return out


# ---------------------------------------------------------------- spawning

## Instantiate a role's placeholder.  `overrides` may carry {"model": path} to
## force a specific actor -- used by the rehearsal stage for A/B against a
## candidate model, which must NOT require editing the manifest.
static func spawn(character_id: String, overrides: Dictionary = {}) -> Node3D:
	var a := find(character_id)
	var path := String(overrides.get("model", a.get("placeholder_model", "")))
	if path == "":
		push_error("[DEMOCAST] '%s' has no placeholder_model" % character_id)
		return null
	if not ResourceLoader.exists(path):
		# exists on disk but NOT as a resource == the import failed.  Python-side
		# validation cannot see this, which is why this check lives here.
		push_error("[DEMOCAST] '%s' -> %s is not a loadable resource (import failed?)"
				% [character_id, path])
		return null
	var packed := load(path) as PackedScene
	if packed == null:
		push_error("[DEMOCAST] %s is not a PackedScene" % path)
		return null
	var node := packed.instantiate() as Node3D
	node.name = character_id
	node.set_meta("character_id", character_id)
	node.set_meta("scene_role", String(a.get("scene_role", "")))
	node.set_meta("placeholder_model", path)
	return node


# ---------------------------------------------------------------- self-check

## Returns a list of human-readable problems; empty means the manifest is usable.
## Deliberately independent of validate_cast.py: that one checks the bakes, this
## one checks that Godot can actually load what the manifest promises.
static func problems() -> PackedStringArray:
	var out := PackedStringArray()
	var m := manifest()
	if m.is_empty():
		out.append("manifest did not load: %s" % MANIFEST_PATH)
		return out

	var profiles := m.get("skeleton_profiles", {}) as Dictionary
	var anim := m.get("animation_profiles", {}) as Dictionary
	var seen := {}

	for c in characters():
		var d := c as Dictionary
		var cid := String(d.get("character_id", ""))
		if cid == "":
			out.append("a character entry has no character_id")
			continue
		if seen.has(cid):
			out.append("duplicate character_id '%s'" % cid)
		seen[cid] = true

		var sp := String(d.get("skeleton_profile", ""))
		if not profiles.has(sp):
			out.append("%s: unknown skeleton_profile '%s'" % [cid, sp])
		var ap := String(d.get("animation_profile", ""))
		# "" is legal and meaningful: registered, no animation pass (P2 rule).
		if ap != "" and not anim.has(ap):
			out.append("%s: unknown animation_profile '%s'" % [cid, ap])

		var model := String(d.get("placeholder_model", ""))
		if model == "":
			out.append("%s: no placeholder_model" % cid)
		elif not ResourceLoader.exists(model):
			out.append("%s: placeholder_model is not loadable: %s" % [cid, model])

	# every base motion that claims clips must name clips the library really has
	var lib := PackedStringArray()
	for cand in characters():
		var p := String((cand as Dictionary).get("placeholder_model", ""))
		if ResourceLoader.exists(p):
			var scn := load(p) as PackedScene
			if scn != null:
				var inst := scn.instantiate()
				for pl in inst.find_children("*", "AnimationPlayer", true, false):
					lib = (pl as AnimationPlayer).get_animation_list()
					break
				inst.queue_free()
			break
	if lib.size() > 0:
		var base := m.get("base_motions", {}) as Dictionary
		for key in base:
			if String(key).begins_with("_"):
				continue
			for clip in ((base[key] as Dictionary).get("clips", []) as Array):
				if not lib.has(String(clip)):
					out.append("base_motions.%s names clip '%s', which the library does not have"
							% [key, clip])
	return out
