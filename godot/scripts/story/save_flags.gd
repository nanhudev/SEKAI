extends Node
class_name SekaiSaveFlags
# THE FLAGS THE FIRST PLAYABLE SEQUENCE NEEDS, AND NOTHING ELSE.
#
# WHY THIS IS NOT AN INVENTORY / SAVE ARCHITECTURE. The brief for this round is
# explicit (§22): if the save system is primitive, do not rewrite it into a large
# architecture - save the key flags reliably and stop. This project has no save
# file at all today (`grep -rn "user://" godot/scripts/` came back empty, and the
# only `FileAccess` uses in the tree are test-tool readbacks), so the honest
# version of "save the story stage" is a small JSON document with three keys in
# it, written through one function and read through one function.
#
# WHY THE KEYS ARE FLAGS AND NOT A STEP NUMBER.
#
#   first_sequence_state   the LAST story stage the player reached, as a string
#   has_first_sword        the sword was physically picked up off the rack
#   first_enemy_defeated   the Ash Hound actually died
#
# A single `stage` integer would be smaller and it would be wrong, because the
# three things it would conflate are three DIFFERENT kinds of fact. `get_sword`
# is not a stage the player passes through, it is a possession they either have
# or do not; `first_enemy_defeated` is an irreversible world event that has to
# survive even if the sequence is later replayed from an earlier branch. §22
# names exactly these three, and a flag you can ask about on its own is the
# thing that makes "do not replay the tutorial" one condition instead of a
# chain of comparisons.
#
# A LOAD IS ALLOWED TO FAIL. A corrupt or absent file is not an error state, it
# is a new game, so every read falls back to a fresh player rather than pushing
# a warning nobody can act on. What is NOT allowed is a silent PARTIAL read: the
# file is parsed whole and any key that is missing or of the wrong type is
# reported in one line naming it.

const PATH := "user://sekai_flags.json"
const VERSION := 1

const KEY_SEQUENCE_STATE := "first_sequence_state"
const KEY_HAS_SWORD := "has_first_sword"
const KEY_ENEMY_DEFEATED := "first_enemy_defeated"
const KEY_COMPLETED := "first_playable_complete"

## The three facts, plus whether the sequence as a whole has been seen through.
##
## `sequence_state` is stored as the NAME of a StoryState value rather than its
## ordinal. An enum is reordered by adding a case in the middle, and a save file
## that silently reinterprets "5" as a different stage after such an edit is a
## bug with no symptom until a player is teleported into the middle of a scene
## they never saw.
var sequence_state: StringName = &""
var has_first_sword := false
var first_enemy_defeated := false
var sequence_complete := false

var _loaded := false


## True when this session should skip the tutorial and simply drop the player
## into the world, which is §22's requirement and the only reason to read the
## file at all on boot.
func is_returning_player() -> bool:
	return has_first_sword or sequence_complete


func load_flags() -> void:
	_loaded = true
	if not FileAccess.file_exists(PATH):
		return
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		push_warning("SekaiSaveFlags: %s exists but could not be opened (%d). "
			% [PATH, FileAccess.get_open_error()]
			+ "Starting a new game.")
		return
	var text := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("SekaiSaveFlags: %s is not a JSON object. Starting a new game."
			% PATH)
		return
	var doc: Dictionary = parsed
	var missing := PackedStringArray()
	var wrong := PackedStringArray()
	if doc.has(KEY_SEQUENCE_STATE) and typeof(doc[KEY_SEQUENCE_STATE]) == TYPE_STRING:
		sequence_state = StringName(doc[KEY_SEQUENCE_STATE])
	elif doc.has(KEY_SEQUENCE_STATE):
		wrong.append(KEY_SEQUENCE_STATE)
	else:
		missing.append(KEY_SEQUENCE_STATE)
	for pair in [[KEY_HAS_SWORD, "has_first_sword"],
			[KEY_ENEMY_DEFEATED, "first_enemy_defeated"],
			[KEY_COMPLETED, "sequence_complete"]]:
		if not doc.has(pair[0]):
			missing.append(pair[0])
			continue
		if typeof(doc[pair[0]]) != TYPE_BOOL:
			wrong.append(pair[0])
			continue
		set(pair[1], bool(doc[pair[0]]))
	if not missing.is_empty() or not wrong.is_empty():
		# Named, once, so an old file that predates a key is legible in the log
		# instead of quietly reading as "false, therefore replay the tutorial".
		print("[SAVE] %s: missing=%s wrong-type=%s -- absent keys read as false"
			% [PATH, ", ".join(missing) if not missing.is_empty() else "-",
			   ", ".join(wrong) if not wrong.is_empty() else "-"])


func save_flags() -> void:
	var doc := {
		"version": VERSION,
		KEY_SEQUENCE_STATE: String(sequence_state),
		KEY_HAS_SWORD: has_first_sword,
		KEY_ENEMY_DEFEATED: first_enemy_defeated,
		KEY_COMPLETED: sequence_complete,
	}
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f == null:
		push_warning("SekaiSaveFlags: could not write %s (%d). The story will "
			% [PATH, FileAccess.get_open_error()]
			+ "still play, but it will replay on the next launch.")
		return
	f.store_string(JSON.stringify(doc, "\t"))
	f.close()


## Wipes the file so the next New Game really is one. Called by the main menu's
## debug entry, never on a normal boot - a save that erases itself when the
## player looks at it is worse than no save.
func clear() -> void:
	sequence_state = &""
	has_first_sword = false
	first_enemy_defeated = false
	sequence_complete = false
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))


## One dim line for the debug overlay (§28).
func debug_line() -> String:
	return "SAVE  state=%s  sword=%s  enemy=%s  done=%s" % [
		String(sequence_state) if sequence_state != &"" else "(new)",
		"yes" if has_first_sword else "no",
		"yes" if first_enemy_defeated else "no",
		"yes" if sequence_complete else "no",
	]
