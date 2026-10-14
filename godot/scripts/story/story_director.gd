extends Node
class_name StoryDirector
# ============================================================================
# FIRST PLAYABLE SEQUENCE — the state machine that makes SEKAI start
# ============================================================================
#
# WHAT THIS NODE IS FOR, IN ONE SENTENCE. It is the only place in the project
# that knows the ORDER of the first ten minutes, and it advances that order for
# exactly one reason: because the player did something.
#
# §21 IS THE WHOLE DESIGN, AND IT IS A PROHIBITION RATHER THAN A FEATURE.
#
#   "不要把流程写成 `if time > 15: spawn enemy`"
#
# So there is no timer in this file that advances a stage. Every transition is
# attached to a signal that a real system emitted about a real body:
#
#   ARRIVAL        -> MET_MIRA        the opening VO finished playing
#   MET_MIRA       -> GET_SWORD       the player pressed E and read Mira out
#   GET_SWORD      -> DRAW_SWORD      the sword physically left the rack
#   DRAW_SWORD     -> BASIC_ATTACK    the BLADE CAME OUT OF THE SAYA (equip_blend)
#   BASIC_ATTACK   -> USE_SKILL       a hit landed on the training post
#   USE_SKILL      -> ENEMY_EVENT     the skill was released AND it connected
#   ENEMY_EVENT    -> FIRST_COMBAT    the hound finished walking into the square
#   FIRST_COMBAT   -> COMBAT_COMPLETE the hound's health reached zero
#   COMBAT_COMPLETE-> NEXT_OBJECTIVE  the post-combat scene finished playing
#
# The one place a clock appears is INSIDE a stage - the opening beat waits, the
# hound pauses before it charges - and that is because a pause is a piece of
# direction, not a piece of progress. A pause never decides WHICH stage comes
# next; it only decides when the next line of the current one is spoken.
#
# WHY THE DIRECTOR DOES NOT OWN THE ACTORS. It never moves the NPC, never swings
# the sword and never damages the hound. It listens to those systems and answers
# with a line of dialogue or a change of objective, so that when ART replaces
# Mira's placeholder with the real model (brief §23) nothing in this file has to
# change - this file has never seen a skeleton.

signal stage_changed(previous: int, current: int)
## One line, no input, fades on its own. The opening and the mid-scene barks.
signal said(speaker: String, text: String, hold: float)
## A block the player advances. E arrives here as "continue".
signal dialogue_started(lines: Array)
signal dialogue_finished()
## What the player is supposed to do now, in one line, top-centre.
signal objective_changed(text: String)
## A thing was acquired / unlocked. Bigger and more ceremonial than a subtitle.
signal toasted(text: String, subtext: String)
## The end-of-sequence card.
signal quest_updated(title: String, body: String)
## The context prompt next to the crosshair: "[F] 交谈".
signal prompt_changed(text: String)
## The world blinked. The stele's runes lit, the sound was pulled out of the
## room, the colour drained for a fifth of a second.
signal anomaly(strength: float)
signal hound_spawned()

enum Stage {
	ARRIVAL,
	MET_MIRA,
	GET_SWORD,
	DRAW_SWORD,
	BASIC_ATTACK,
	USE_SKILL,
	ENEMY_EVENT,
	FIRST_COMBAT,
	COMBAT_COMPLETE,
	NEXT_OBJECTIVE,
}

const STAGE_NAMES := {
	Stage.ARRIVAL: "ARRIVAL",
	Stage.MET_MIRA: "MET_MIRA",
	Stage.GET_SWORD: "GET_SWORD",
	Stage.DRAW_SWORD: "DRAW_SWORD",
	Stage.BASIC_ATTACK: "BASIC_ATTACK",
	Stage.USE_SKILL: "USE_SKILL",
	Stage.ENEMY_EVENT: "ENEMY_EVENT",
	Stage.FIRST_COMBAT: "FIRST_COMBAT",
	Stage.COMBAT_COMPLETE: "COMBAT_COMPLETE",
	Stage.NEXT_OBJECTIVE: "NEXT_OBJECTIVE",
}

# ---------------------------------------------------------------- direction
#
# §2: 3-6 seconds of world before anyone speaks. Long enough that the square is
# a place the player has already looked at, short enough that it is not a
# cutscene - and the player is never locked, never faded to black twice, and
# never has the camera taken away.
const OPENING_HOLD := 4.2
## §19: "玩家周围声音瞬间被抽掉约 0.3 秒". The duck, and the colour drain that
## runs with it. Two numbers because they are two different effects that have to
## feel like one event.
const ANOMALY_SECONDS := 0.30
const ANOMALY_DRAIN := 0.55
## How long the hound stands at the alley mouth before it charges (§13).
const HOUND_ENTRY_PAUSE := 1.1
## §18/§19: the pause after the kill exists so the player watches the thing fall
## and settle before anyone speaks to them about it. 1.4 s is the length of the
## hound's own fall plus its hold, which is why it is not shorter: a line of
## dialogue arriving while the body is still rolling reads as the game having
## something else it would rather be doing.
##
## THE REST OF THE POST-COMBAT SCENE HAS NO BUDGET AT ALL. Mira walks over, and
## that takes as long as it takes - see `_on_hound_died`.
const POST_KILL_BEAT := 1.4

@export var npc_path: NodePath
@export var rack_path: NodePath
@export var post_path: NodePath
@export var stele_path: NodePath
@export var player_path: NodePath
@export var enemy_spawn_path: NodePath
@export var enemy_scene: PackedScene
@export var music_path: NodePath
@export var area_music_path: NodePath

var stage: int = Stage.ARRIVAL
var flags: SekaiSaveFlags

var _npc: Node = null
var _rack: Node = null
var _post: Node = null
var _stele: Node = null
var _player: CharacterBody3D = null
var _enemy: Node = null
var _combat: Node = null
var _fx: CombatScreenFX = null
var _audio_state: Node = null
var _music: AudioStreamPlayer = null
var _area_music: AudioStreamPlayer = null
var _busy := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_resolve()
	# A RETURNING PLAYER DOES NOT SIT THROUGH THE TUTORIAL (§22).
	#
	# The check is `has_first_sword`, not `sequence_complete`, because the two
	# failures are not equally bad: replaying the last scene is a small annoyance,
	# and re-running "you have no weapon" at a player who is holding one is a
	# contradiction the world cannot survive. So the sword is the line.
	if flags != null and flags.is_returning_player():
		call_deferred("_skip_to_open_world")
		return
	call_deferred("_begin")


func _resolve() -> void:
	var w := get_parent()
	# THE FLAGS ARE CREATED HERE RATHER THAN MOUNTED IN THE SCENE, AND THE REASON
	# IS THAT A NULL `flags` IS INVISIBLE. Every write below is a `if flags !=
	# null` guard, so a director without a flag store runs the whole story, looks
	# completely correct on screen, and quietly saves nothing - §22 would simply
	# not be implemented and nothing would say so. Owning the node makes the one
	# object that can be null impossible to be absent.
	flags = SekaiSaveFlags.new()
	flags.name = "SekaiSaveFlags"
	add_child(flags)
	flags.load_flags()
	_npc = get_node_or_null(npc_path)
	_rack = get_node_or_null(rack_path)
	_post = get_node_or_null(post_path)
	_stele = get_node_or_null(stele_path)
	_player = get_node_or_null(player_path) as CharacterBody3D
	_music = get_node_or_null(music_path) as AudioStreamPlayer
	_area_music = get_node_or_null(area_music_path) as AudioStreamPlayer
	if w != null:
		_fx = w.get_node_or_null("CombatScreenFX") as CombatScreenFX
		_audio_state = w.get_node_or_null("AudioStateController")
	if _player != null:
		_combat = _player.get_node_or_null("CombatController")
	# Missing wiring is named rather than skipped, because a director that
	# silently has no NPC in it is a director that plays to an empty square and
	# looks exactly like a director whose dialogue is broken.
	for pair in [["npc", _npc], ["rack", _rack], ["post", _post],
			["stele", _stele], ["player", _player]]:
		if pair[1] == null:
			push_warning("StoryDirector: no '%s' at the exported path -- the first "
				% pair[0] + "playable sequence cannot run. Check MistvalePlaza.tscn.")


# ============================================================ stage plumbing

func stage_name() -> String:
	return STAGE_NAMES.get(stage, "?")


func _set_stage(next: int) -> void:
	if stage == next:
		return
	var previous := stage
	stage = next
	# WRITTEN THROUGH ON EVERY TRANSITION. §22 asks for the story stage to
	# persist, and the only moment at which it is guaranteed to be a coherent
	# number is here - not in `_exit_tree`, which is not reached when the process
	# is killed from the menu.
	if flags != null:
		flags.sequence_state = StringName(stage_name())
		flags.save_flags()
	print("[STORY] %s -> %s" % [STAGE_NAMES.get(previous, "?"), stage_name()])
	stage_changed.emit(previous, next)
	_announce_objective()


func _announce_objective() -> void:
	var text := objective_for(stage)
	if text != "":
		objective_changed.emit(text)


func objective_for(which: int) -> String:
	match which:
		Stage.ARRIVAL:
			return ""
		Stage.MET_MIRA:
			return "和广场上的那个人说话"
		Stage.GET_SWORD:
			return "从武器架上拿起那把旧剑"
		Stage.DRAW_SWORD:
			return "拔刀　[R]"
		Stage.BASIC_ATTACK:
			return "对着木桩挥一刀　[LMB]"
		Stage.USE_SKILL:
			return "试试剑气　[Q]"
		Stage.ENEMY_EVENT:
			return ""
		Stage.FIRST_COMBAT:
			return "击退它"
		Stage.COMBAT_COMPLETE:
			return ""
		Stage.NEXT_OBJECTIVE:
			return "前往冒险者公会"
	return ""


## §22: a returning save does not replay the tutorial. Asked by the world (which
## has to decide whether the player starts with empty hands) and by the director
## itself, from the same place, so the two can never disagree about who this is.
func is_returning_player() -> bool:
	return flags != null and flags.is_returning_player()


func _skip_to_open_world() -> void:
	# The player already has the sword, so the world boots in its finished
	# shape: blade in hand, nothing to be taught, and the hound already dealt
	# with. `Stage.NEXT_OBJECTIVE` is where that leaves them.
	if _combat != null:
		_combat.set("equip_blend", 1.0)
	_set_stage(Stage.NEXT_OBJECTIVE)
	_bark("", "—— 雾栖镇 · 集市广场 ——", 2.4)


# ================================================================== the show

func _begin() -> void:
	_set_stage(Stage.ARRIVAL)
	await _wait(OPENING_HOLD)
	# §3: the first thing anyone says is a question about the player's body,
	# not about the world. 复活 / 穿越 / 勇者 are not in this dialogue on
	# purpose - the only fact the scene reveals is 你不是这里的人.
	await _say("米拉", "……醒了？", 2.0)
	await _wait(0.6)
	await _say("米拉", "你刚才就这样倒在广场中央。", 2.8)
	await _wait(0.9)
	await _say("米拉", "奇怪。", 1.4)
	await _wait(0.5)
	await _say("米拉", "你身上一点魔力的气息都没有。", 3.0)
	await _wait(1.2)
	# THE FIRST WORLD HOOK. No explanation follows it, and that is the point:
	# the stele answers a question nobody asked, and then stops talking.
	if _stele != null and _stele.has_method("pulse"):
		_stele.call("pulse", 1.0)
	anomaly.emit(1.0)
	await _wait(2.2)
	await _say("米拉", "……", 1.6)
	await _wait(0.3)
	_set_stage(Stage.MET_MIRA)


## Blocks the script for `seconds` WITHOUT blocking the tree.
##
## WHY EVERY CALLER MUST `await` THIS, AND WHY THAT IS A BUG THAT WOULD HAVE
## SHIPPED SILENTLY. A function that reaches an `await` suspends and hands
## control straight back to its caller; a caller that does not itself `await`
## therefore runs its NEXT line immediately. Written without the keyword, the
## opening beat above would fire all five lines in the same frame and stack five
## overlapping subtitle timers, and it would look from the code like a normal
## scripted sequence - the bug is an absence, in a file where every line looks
## right. The `await` is the sequence.
func _wait(seconds: float) -> void:
	if seconds > 0.0:
		await get_tree().create_timer(seconds).timeout


func _say(speaker: String, text: String, hold: float) -> void:
	said.emit(speaker, text, hold)
	await get_tree().create_timer(hold).timeout


## A line that nothing waits on. Used where the caller has to return a value on
## the same frame (`try_talk`) and therefore cannot suspend.
func _bark(speaker: String, text: String, hold: float) -> void:
	said.emit(speaker, text, hold)


# ---------------------------------------------------------- 1. the first talk

## What E says while standing next to Mira, or "" when she has nothing to say.
##
## THE PROMPT IS A PROPERTY OF THE STORY, NOT OF HER. She cannot know that she has
## nothing to add while the player is mid-lesson, and a "[E] 交谈" that opens onto
## a line she has already said three times is the single most common way a first
## playable feels unfinished. So the world asks the director, and the director
## answers from the stage.
func npc_prompt() -> String:
	# ONE LINE, AND THAT MATTERS. A `match` pattern list is NOT an expression
	# inside brackets, so a GDScript line break after the comma does not continue
	# it - the parser reads `Stage.BASIC_ATTACK,` as the whole list and then
	# reports "Expected expression for match pattern" on the NEXT line. That
	# parses as a hard failure of this file, which in turn makes every script that
	# types a variable as `StoryDirector` fail to parse, which is how a one-line
	# over-wrap silently disabled the entire plaza.
	match stage:
		Stage.MET_MIRA, Stage.GET_SWORD, Stage.DRAW_SWORD, Stage.BASIC_ATTACK, Stage.USE_SKILL, Stage.NEXT_OBJECTIVE:
			return "[F]  交谈"
	return ""


## Called by the NPC when the player presses F (interact) in range. Returns whether
## the conversation actually started, so the caller can leave the input unhandled if
## this stage has nothing to say in this place.
func try_talk() -> bool:
	match stage:
		Stage.MET_MIRA:
			_play_first_talk()
			return true
		Stage.GET_SWORD:
			_bark("米拉", "……先拿那个。", 2.2)
			return true
		Stage.DRAW_SWORD, Stage.BASIC_ATTACK:
			_bark("米拉", "别看我，看木头。", 2.0)
			return true
		Stage.USE_SKILL:
			_bark("米拉", "……你还挺熟练。", 2.2)
			return true
		Stage.NEXT_OBJECTIVE:
			dialogue_started.emit([
				{"speaker": "米拉", "text": "公会那边应该有人认得这个。", "hold": 3.0},
				{"speaker": "米拉", "text": "……如果有的话。", "hold": 3.0},
			])
			return true
		_:
			return false


func _play_first_talk() -> void:
	# §5, verbatim in shape: she checks the body, she checks the kit, she
	# points. She never explains anything, because the whole scene is one
	# person noticing that another person does not belong here.
	dialogue_started.emit([
		{"speaker": "米拉", "text": "你还能走吗？", "hold": 2.2},
		{"speaker": "米拉", "text": "至少看起来没受伤。", "hold": 2.6},
		{"speaker": "米拉", "text": "等等……", "hold": 1.6},
		{"speaker": "米拉", "text": "你连武器都没有？", "hold": 2.4},
		{"speaker": "米拉", "text": "先拿那个。", "hold": 2.2},
	])
	_set_stage(Stage.GET_SWORD)


# -------------------------------------------------------- 2. the first sword

func on_sword_taken() -> void:
	_on_sword_taken()


func _on_sword_taken() -> void:
	if flags != null:
		flags.has_first_sword = true
		flags.save_flags()
	if stage == Stage.NEXT_OBJECTIVE:
		return
	_set_stage(Stage.DRAW_SWORD)
	if _npc != null and _npc.has_method("react"):
		_npc.call("react")
	if _npc != null and _npc.has_method("point_at"):
		if _post != null:
			_npc.call("point_at", (_post as Node3D).global_position)


# -------------------------------------------------------- 3. the first draw

## The draw is driven by the blade's own equip blend, so "the player drew" is
## not a key press that was noticed - it is `equip_blend` having crossed a line
## on the rig. A key press can be swallowed or buffered; the blend cannot lie
## about where the sword is.
func on_sword_drawn() -> void:
	if stage != Stage.DRAW_SWORD:
		return
	_set_stage(Stage.BASIC_ATTACK)
	if _npc != null and _npc.has_method("react"):
		_npc.call("react")
	await _wait(0.5)
	await _say("米拉", "对着那个。", 2.4)


func on_sword_sheathed() -> void:
	# Putting the sword away is allowed at any time and is not a stage change.
	# Recorded only so the debug overlay can show that the four states are real.
	pass


# --------------------------------------------------- 4. the first real hit

func on_training_hit() -> void:
	if stage != Stage.BASIC_ATTACK:
		return
	_set_stage(Stage.USE_SKILL)
	await _wait(0.35)
	await _say("米拉", "……还真会。", 2.0)
	await _wait(0.7)
	await _say("米拉", "那这个呢？", 2.0)
	toasted.emit("剑气", "Q")


func on_skill_released() -> void:
	if stage != Stage.USE_SKILL:
		return
	# The interrupt (§11) hangs off the skill LANDING, not off the key. A player
	# who presses Q into empty air has not finished the lesson, and the hound
	# arriving at that moment would be the game changing the subject while the
	# player is still mid-sentence.
	pass


func on_skill_connected() -> void:
	if stage != Stage.USE_SKILL:
		return
	_set_stage(Stage.ENEMY_EVENT)
	_begin_enemy_event()


# ------------------------------------------------ 5. the world interrupts

func _begin_enemy_event() -> void:
	await _wait(0.9)
	# The interruption is three signals in a row and no explanation: a distant
	# impact, the bell changing its mind, and a shout. §11 asks for the tutorial
	# to be interrupted BY THE WORLD, so nothing in this sequence is addressed
	# to the player's current task.
	if _npc != null and _npc.has_method("react"):
		_npc.call("react")
	if _npc != null and _npc.has_method("look_at_point"):
		_npc.call("look_at_point", _enemy_spawn_point())
	await _say("", "……", 0.9)
	await _spawn_hound()
	_set_stage(Stage.FIRST_COMBAT)
	# The music starts on the frame the hound is in the square, because that is
	# the frame the square stops being a town. It is a plain AudioStreamPlayer
	# rather than `combat_music.gd` for the reason written into the .tscn: the
	# story, not the node, decides when this piece of music exists.
	if _music != null and _music.stream != null:
		_music.play()


func _enemy_spawn_point() -> Vector3:
	var marker := get_node_or_null(enemy_spawn_path) as Node3D
	if marker != null:
		return marker.global_position
	return Vector3.ZERO


func _spawn_hound() -> void:
	if enemy_scene == null:
		push_warning("StoryDirector: no enemy_scene exported; the first combat "
			+ "cannot happen. Check MistvalePlaza.tscn.")
		return
	_enemy = enemy_scene.instantiate()
	var marker := get_node_or_null(enemy_spawn_path) as Node3D
	var world := get_parent()
	world.add_child(_enemy)
	if marker != null:
		(_enemy as Node3D).global_position = marker.global_position
	(_enemy as Node3D).rotation.y = 0.0
	_enemy.connect("died", _on_hound_died)
	_enemy.connect("arrived", _on_hound_arrived)
	_enemy.connect("struck_player", _on_hound_struck_player)
	_enemy.connect("knocked_prop", _on_hound_knocked_prop)
	hound_spawned.emit()
	# §13: it does not appear in front of the player, it WALKS IN. The pause is
	# here rather than inside the enemy because "stand still and look at the
	# thing you are about to charge" is direction, and the enemy script has no
	# business knowing about the story.
	if _enemy.has_method("stage_entry"):
		_enemy.call("stage_entry", HOUND_ENTRY_PAUSE)


func _on_hound_knocked_prop() -> void:
	said.emit("", "远处巷口的木箱被撞翻了。", 1.8)


func _on_hound_arrived() -> void:
	said.emit("", "有人喊了一声：魔兽！", 2.0)


func _on_hound_struck_player() -> void:
	# One acknowledgement and then silence. An enemy that talks every time it
	# hits you turns a fight into a lecture.
	pass


# --------------------------------------------------- 6. the fight is over

func _on_hound_died() -> void:
	if stage != Stage.FIRST_COMBAT:
		return
	if flags != null:
		flags.first_enemy_defeated = true
		flags.save_flags()
	_set_stage(Stage.COMBAT_COMPLETE)
	await _wait(POST_KILL_BEAT)
	# The music stops and the square gets its wind back, which is the audible
	# shape of "the fight is over" - the same event, told to the ears instead of
	# to the eyes. Mira is not asked to kill it (§14); she arrives after the
	# fact, which is what makes the player the one who did it.
	if _music != null:
		_music.stop()
	if _npc != null and _npc.has_method("walk_to"):
		var spot: Vector3 = _player.global_position + _player.global_transform.basis * _npc_offset()
		_npc.call("walk_to", spot, 2.6)
		await _wait(2.8)
	if _npc != null and _npc.has_method("look_at_point"):
		_npc.call("look_at_point", _player.global_position)
	await _wait(0.6)
	await _say("米拉", "……", 1.8)
	await _wait(0.4)
	dialogue_started.emit([
		{"speaker": "米拉", "text": "你刚才说，你不会用剑？", "hold": 3.0},
		{"speaker": "米拉", "text": "这不像第一次握剑的人。", "hold": 3.0},
	])
	await _wait(3.4)
	# §19: the second anomaly. Deliberately a degree louder than the first -
	# the same event, and now the character next to you has seen it too, which
	# is the difference between a glitch and a plot.
	if _stele != null and _stele.has_method("pulse"):
		_stele.call("pulse", 1.7)
	_anomaly_with_silence(1.7)
	await _wait(2.6)
	await _say("米拉", "你也看见了，对吧？", 3.2)
	await _wait(3.0)
	_set_stage(Stage.NEXT_OBJECTIVE)
	quest_updated.emit("任务更新", "前往冒险者公会")
	if flags != null:
		flags.sequence_complete = true
		flags.save_flags()


func _npc_offset() -> Vector3:
	# She stops a conversational distance away rather than on top of the camera.
	return Vector3(1.6, 0.0, 1.1)


func _anomaly_with_silence(strength: float) -> void:
	# SOUND FIRST, THEN COLOUR, AND THE SOUND IS THE ONE THAT READS.
	#
	# "玩家周围声音瞬间被抽掉约 0.3 秒" is a DUCK, not a cut: the world keeps
	# playing under it at almost nothing, which is what makes it feel like the
	# room holding its breath instead of the audio being broken. The colour
	# drain runs for the same 0.3 s and then decays over the next second, so the
	# image comes back slightly after the sound does.
	anomaly.emit(strength)
	# `duck_world_audio()` takes no argument on purpose: the depth is a property
	# of the duck (40 dB, reached in 0.1 s at the controller's own ramp rate),
	# and a caller that could choose its own number would eventually choose one
	# that leaves the world audibly running under what is supposed to be silence.
	if _audio_state != null and _audio_state.has_method("duck_world_audio"):
		_audio_state.call("duck_world_audio")
	await get_tree().create_timer(ANOMALY_SECONDS).timeout
	if _audio_state != null and _audio_state.has_method("restore_world_audio"):
		_audio_state.call("restore_world_audio")
	if _fx != null:
		var t := create_tween()
		t.tween_method(_set_drain, ANOMALY_DRAIN * strength, 0.0, 1.4)


func _set_drain(v: float) -> void:
	if _fx != null:
		_fx.set_world_drain(v)


# ------------------------------------------------------------------- queries

## §28. One line, and it is the only thing in the game that names a stage.
func debug_line() -> String:
	var lines := PackedStringArray()
	lines.append("STORY  %s" % stage_name())
	lines.append("WEAPON %s  blade %s" % [
		"sword" if _holds_sword() else "empty",
		"drawn" if _is_drawn() else "sheathed",
	])
	if _enemy != null and is_instance_valid(_enemy):
		lines.append("HOUND  %d / %d  %s" % [
			int(_enemy.get("health")), int(_enemy.get("max_health")),
			String(_enemy.get("state_name")),
		])
	else:
		lines.append("HOUND  --")
	if flags != null:
		lines.append(flags.debug_line())
	return "\n".join(lines)


func _holds_sword() -> bool:
	if _player == null:
		return false
	var slot := _player.get_node_or_null("WeaponSlot")
	return slot != null and bool(slot.call("is_sword"))


func _is_drawn() -> bool:
	return _combat != null and bool(_combat.call("is_drawn"))
