extends Node
class_name CombatController
# SEKAI · Universal Sword Layer + sword styles.
#
# The controller owns the LANGUAGE (startup / strike / follow / recovery, guard,
# perfect guard, riposte, cancels, buffering). The SwordMoveset only overrides
# numbers and poses. No style gets its own CombatController.

enum State {
	IDLE,
	ATTACK,
	CHARGE,
	BLOCK,
	PARRY,
	RIPOSTE,
	DODGE,
	CAST,
	SKILL,
	STAGGER,
	IAIDO,
	ULTIMATE,
}

signal state_changed(previous: State, current: State)
signal style_changed(style_id: StringName)
signal move_started(move: SwordMove)
# THE MOMENT THE BLADE LEAVES.
#
# `move_started` is the instant the KEY went down. Everything describing motion
# used to ride it, which meant the whoosh and the camera kick arrived a whole
# startup before the blade they claim to describe: 0.085s on a light, 0.185s on
# a charged heavy — five to eleven frames of sound leading a sword that has not
# moved yet. Startup is not dead air, it is the wind-up, and a promise made in
# the wind-up belongs in the wind-up. Everything else belongs here.
signal swing_started(move: SwordMove)
signal hit_landed(move: SwordMove, hit: Dictionary)
signal perfect_guard_landed()
# A hit passed through the space the player had just left. Not "the dodge was
# pressed" — that is `state_changed`, and it happens whether or not anything was
# ever coming. This one only fires when there was something to get out of the
# way of, and it is the hook the audio director hangs the near-miss cue on.
signal dodge_evaded()
signal style_message(text: String)

@export var tuning: CombatTuning = preload("res://resources/tuning/CombatTuning.tres")
@export var frost_ability: AbilityData = preload("res://resources/abilities/frost_stream.tres")
@export var fire_ability: AbilityData = preload("res://resources/abilities/fire_cast.tres")
@export var wind_ability: AbilityData = preload("res://resources/abilities/wind_burst.tres")
@export var starting_style: StringName = &"universal"

@onready var player: CharacterBody3D = get_parent()
@onready var hitbox: CombatHitbox = player.get_node("CameraRig/LookPivot/MotionPivot/ShakePivot/WeaponRoot/SwordHitbox")
@onready var frost_hitbox: CombatHitbox = player.get_node("CameraRig/LookPivot/MotionPivot/ShakePivot/VFXRoot/FrostHitbox")
@onready var fire_hitbox: CombatHitbox = player.get_node("CameraRig/LookPivot/MotionPivot/ShakePivot/VFXRoot/FireHitbox")
@onready var wind_hitbox: CombatHitbox = player.get_node("CameraRig/LookPivot/MotionPivot/ShakePivot/VFXRoot/WindHitbox")
@onready var camera_feedback: CameraFeedbackController = player.get_node("CameraFeedbackController")
@onready var magic_circle: MagicCircle3D = player.get_node("CameraRig/LookPivot/MotionPivot/ShakePivot/VFXRoot/MagicCircle3D")
@onready var hurtbox: CombatHurtbox = player.get_node("Hurtbox")
@onready var dodge_audio: AudioStreamPlayer = player.get_node("DodgeAudio")
@onready var screen_fx: CombatScreenFX = player.get_parent().get_node("CombatScreenFX")
@onready var time_effects: TimeEffectManager = player.get_parent().get_node("TimeEffectManager")
@onready var iaido_director: IaidoDirector = player.get_parent().get_node_or_null("IaidoDirector")
@onready var ultimate_director: Node = player.get_parent().get_node_or_null("MomentOfNoMoonDirector")

var state := State.IDLE
var state_time := 0.0
# THE CLOCK EVERY COMBAT WINDOW IS MEASURED IN. Not wall time.
#
# Every window in this controller — combo, follow-up, riposte, bind, slip, skill
# cooldown — used to be asked for with `Time.get_ticks_msec()`, which keeps
# running at full speed while a hitstop has the world at 0.05x. Measured that
# way a 0.25s follow-up window spends a tenth of a second completely frozen and
# the player is handed two thirds of the decision they bargained for: the stop
# stops being feedback and starts being rent.
#
# Summing the same scaled delta the moves themselves advance on makes every
# window a duration IN SIMULATION. A time scale then costs the player nothing
# they were going to spend anyway, because during a freeze the game does not
# advance and neither does anything the player is waiting on.
#
# IT ALSO STARTS AT ZERO, which is the whole point of a clock that is not the
# wall — and it is a trap. Every window in this file is a timestamp compared
# against it, and every one of those timestamps is initialised to 0.0. Reading
# "open while now <= until" then says 0 <= 0, which is TRUE, so on the very
# first frame of a fresh game the riposte window and the sheath waiver are both
# open and the player's first attack of the run comes out as a RIPOSTE. The
# wall clock hid this for free by starting at whatever second the engine
# happened to be on. So every window below is asked for with a STRICT `<`: a
# window that expires at `until` is closed AT `until`, and 0.0 — the value a
# window has before it has ever been opened — is closed by construction.
var combat_time := 0.0
var buffer := CombatInputBuffer.new()
var attack_kind: StringName = &""
# Whether this move's own departure has been announced yet. One announcement per
# move, at `startup` — see the `swing_started` signal.
var _swing_announced := false
# Sampled when a move is committed, spent when it lands. See _begin_move.
var commit_moving := false
var hitbox_open := false
var dodge_direction := Vector3.FORWARD
var dodge_speed := 11.0
var perfect_guard_count := 0
# How many hits have passed through the space the player was just standing in,
# as opposed to how many dodges were pressed. The second number is meaningless
# and the first one is the whole point of the move.
var dodges_landed := 0
var combo_index := 0
var last_light_at := -10.0
# Renamed from selected_spell, which is the name that hid a real bug: it has
# always held a SCHOOL id, so every read site looked like it was reading the
# armed spell, and nobody noticed that the second spell of each school could not
# be armed at all. The armed spell is spell_id.
var selected_school: StringName = &"frost"
var casting_spell: StringName = &"frost"
# --- magic, as data ----------------------------------------------------------
var schools: Dictionary = {}
var spell_id: StringName = &"frost_stream"
var active_spell: SpellDefinition
var active_field: ElementField
var blade_infusion_left := 0.0
var blade_element: StringName = &"physical"
var wind_step_left := 0.0
var iaido_ready_at := 0.0
var ultimate_ready_at := 0.0

# --- measure (白蔷庭) -------------------------------------------------------
# Distance is read live so the player can watch the state change while they move,
# but it is SAMPLED at commit time when a move begins: closing the gap mid-swing
# must not retrofit the reward onto a swing that was started out of position.
var measure_range := -1.0
var measure_state: StringName = &""
# Reach bonus carried into the hitbox for the move currently being committed.
var move_reach_bonus := 0.0
var measure_ideal_count := 0
var bind_until := 0.0
# 藏锋's loop closer: set by a perfect guard, waives the pre-sheath wait.
var sheath_waive_until := 0.0

# --- style state -------------------------------------------------------------
var movesets: Dictionary = {}
var moveset: SwordMoveset
var style_id: StringName = &"universal"
var active_move: SwordMove
var active_skill: SwordSkill
var active_move_id: StringName = &""
var move_hit := false
var move_startup_override := -1.0
var move_startup_scale := 1.0
var move_poise_scale := 1.0
var charge_ratio := 0.0
var chain_expires_at := 0.0
var chain_active := false
var riposte_until := 0.0
var followup_until := 0.0
var pending_followup_id: StringName = &""
var edge_glint := false
var next_move_startup_scale := 1.0
var skill_cooldowns: Dictionary = {}
var guard_recoil := 0.0
var parry_lateral := 0.0
var sheath_amount := 0.0
var idle_time := 0.0
var hitstop_scale := 1.0
var pose_time := 0.0
var hits_landed := 0
var last_hit_strength := 0.0
var inspect_left := 0.0
var inspect_mix := 0.0
var _impact_frame := -1
var _equip_move := SwordBasic.equip()

# --- 势 / Flow (回风式) -------------------------------------------------------
# Resolved only when moveset.flow_enabled. Kept on the controller rather than
# in the moveset because it is per-fight state, not per-style data.
var flow := 0.0
var flow_idle_time := 0.0
var flow_peak := 0.0

# --- enhance state (纳息 / 惊鸿) ----------------------------------------------
var enhance_left := 0.0
var enhance_startup_scale := 1.0
var enhance_perfect_guard_bonus := 0.0
var enhance_first_hit_poise_scale := 1.0
var enhance_skill_id: StringName = &""
# 惊鸿's contribution: transitions and steering, not numbers.
var enhance_transition_bonus := 0.0
var enhance_steer_bonus := 1.0

# --- slip state (折柳) --------------------------------------------------------
var slip_until := 0.0
var slip_skill: SwordSkill
var slip_count := 0

# Sideways mirror for signatures the player aims themselves (长风). +1 = right.
var move_mirror := 1.0

# ------------------------------------------------- the sword line's own actors
#
# §15 LOCKS THE FOUR BEATS TO FOUR DISTANCES, which means three of them leave the
# blade's own hitbox behind. `SwordReach` is the runtime that crosses that
# distance, and these three references are the whole of the wiring: the reach
# solver that decides what a ranged cut touched, the off-hand actor, and the
# listener that turns the moves' events into things you can see and hear.
const WEAPON_ROOT_PATH := "CameraRig/LookPivot/MotionPivot/ShakePivot/WeaponRoot"

var reach: SwordReach
var saya_rig: SwordSayaRig
## The left hand's control point — the scabbard's ONLY pose source. See
## `SayaHandDriver`; the rig reads it in `seat_home()`.
var saya_hand: SayaHandDriver
var sword_vfx: SwordCombatVFX

## The draw's own absolute scabbard pose, when one is live this frame.
##
## The four cuts move the scabbard by an OFFSET from the hand (`saya_ctrl_*`, and
## `_drive_hand` folds it into the hand's base pose). The draw does not: it authors
## the scabbard's whole pose (`saya_positions` / `saya_rotations`) because a draw is
## a stretch of time in which the blade moves and the scabbard does not -- a hold,
## which no offset-from-something expresses.
##
## Either way the HAND has to end up where the scabbard is, or the arm is solved
## onto a hand that is not holding anything. `_drive_saya_beats` stashes the pose
## here and `_drive_hand` reads it, so the draw needs no second authoring pass.
var _saya_absolute := Transform3D()
var _saya_has_absolute := false

## 0 = the blade is home in the saya; 1 = drawn and settled (§19/§20).
##
## A POSE, not a state: the controller does not care whether the player is
## drawing, and the WeaponManager — already the only runtime writer of what is in
## the hands — is the only thing that moves it. Everything downstream reads it:
## `pose_snapshot()` blends the E0-E3 beats by it and the saya rig takes its
## presence from it, so `1` after `2` is one motion with one author.
var equip_blend := 1.0
## Per-move record of which ranged cuts have already resolved. Keyed by mark
## index rather than by time, because time is a float and "already fired" is not.
var _reach_fired: Dictionary = {}
var _arc_slice := 0


func _ready() -> void:
	buffer.duration = tuning.input_buffer
	hitbox.source = player
	frost_hitbox.source = player
	fire_hitbox.source = player
	wind_hitbox.source = player
	# INPUT CONTRACT V0.1: semantic actions are owned by InputContract autoload.
	# Do not re-bind E/X/C/V/F/Shift/Ctrl/Tab here — that would fight the contract.
	# Legacy adapters (iaido←skill_1, heavy_attack←skill_2) live in InputContract.
	# Magic hotkeys relocated off contract keys: Q cast, Z fire, G frost, B wind.
	_bind_key("fire_cast", KEY_Z)
	_bind_key("frost_cast", KEY_G)
	_bind_key("wind_cast", KEY_B)
	_bind_key("inspect", KEY_U)
	_bind_mouse("inspect", MOUSE_BUTTON_XBUTTON2)
	_bind_key("cast_selected", KEY_Q)
	hurtbox.hit_received.connect(_on_player_hit)
	hitbox.hit_landed.connect(_on_hitbox_landed)
	_bind_mouse("light_attack", MOUSE_BUTTON_LEFT)
	_bind_mouse("block", MOUSE_BUTTON_RIGHT)
	_bind_mouse("attack_primary", MOUSE_BUTTON_LEFT)
	_bind_mouse("parry", MOUSE_BUTTON_RIGHT)
	movesets = SwordMovesetLibrary.build_all()
	schools = MagicLibrary.all()
	set_style(starting_style, true)
	select_school(&"frost")
	# The blade is already in hand when a stage hands the player a sword, so the
	# draw starts out finished. It is only ever run backwards by a weapon switch.
	equip_blend = 1.0 if _holds_sword() else 0.0
	_ensure_sword_actors()


## Builds the two actors the sword line needs and nothing else can own.
##
## WHY THEY ARE MADE IN CODE RATHER THAN PLACED IN `Player.tscn`. The saya is
## parented to `WeaponRoot`, which lives four nodes down inside the camera rig,
## and the combo's marks and trails are things that happened IN THE WORLD —
## parenting those to a shaking camera would drag A3's three cuts around every
## time the player took a step. One function that knows both answers beats two
## scene edits that have to agree with it, and it means a stage that builds its
## own player gets the whole sword line for free.
func _ensure_sword_actors() -> void:
	if reach == null:
		reach = SwordReach.new()
		reach.name = "SwordReach"
		add_child(reach)
		reach.set_source(player, self)
	var weapon_root := player.get_node_or_null(WEAPON_ROOT_PATH) as Node3D
	if weapon_root != null and saya_rig == null:
		saya_rig = SwordSayaRig.new()
		saya_rig.name = "SwordSayaRig"
		weapon_root.add_child(saya_rig)
		saya_rig.set_weapon(&"iaito")
	# THE LEFT HAND, and it is created here for the same reason the scabbard is:
	# a stage that builds its own player gets the whole sword line for free. It is
	# a CHILD OF `WeaponRoot` at identity, so its transform is already in the
	# frame both the sword and the scabbard are authored in and no conversion is
	# needed anywhere. See `SayaHandDriver` for why the scabbard's pose comes from
	# it rather than from a constant or from the blade.
	if weapon_root != null and saya_hand == null:
		saya_hand = SayaHandDriver.new()
		saya_hand.name = "SayaHandSocket"
		weapon_root.add_child(saya_hand)
		saya_hand.base_position = SwordBasic.saya_home()
		saya_hand.base_basis = Basis.from_euler(SwordBasic.SAYA_MOUTH_R)
		saya_rig.hand = saya_hand
	if sword_vfx == null:
		sword_vfx = SwordCombatVFX.new()
		sword_vfx.name = "SwordCombatVFX"
		var world := player.get_parent()
		if world != null:
			# DEFERRED, AND THIS ONE WORD IS THE DIFFERENCE BETWEEN THE SWORD
			# LANGUAGE BEING VISIBLE AND NOT. This function runs from `_ready`, at
			# which point the stage is still setting up the children it is adding
			# — and Godot REFUSES a direct `add_child` on a parent in that state
			# with "Parent node is busy setting up children". The refusal is an
			# error and not an exception, so `sword_vfx` stayed non-null and
			# ORPHANED: never in the tree, so its `_ready` never ran, so it never
			# built its arc visual, and every wave, trace and sweep it created over
			# an entire session was built into a node that was not in the world.
			#
			# What that looked like from outside: A2's wave, A3's three marks and
			# A4's sweep were all mechanically present — `SwordReach` reported the
			# hits, the tests passed on every one of them — and not one of them
			# appeared on screen. The delivery clip was fourteen seconds of a
			# sword being swung at nothing, and the only evidence in the entire log
			# was one line at startup that every grep in this session had been
			# filtering out.
			world.add_child.call_deferred(sword_vfx)
			# `bind` only stores three references and connects five signals, so it
			# is safe before the deferred add lands. `_ready` is what builds the
			# meshes, and it runs when the node actually enters the tree.
			sword_vfx.bind(self, reach, _find_audio_director())


func _find_audio_director() -> Node:
	var world := player.get_parent()
	if world == null:
		return null
	return world.get_node_or_null("CombatAudioDirector")


# ---------------------------------------------------------------- magic data

func select_school(school_id: StringName) -> bool:
	# The quick-swap keys (Z / R / C): pick a school and take its default spell.
	if not schools.has(school_id):
		return false
	var school: MagicSchool = schools[school_id]
	var primary := school.primary()
	if primary == null:
		return false
	_adopt_spell(school_id, primary.id)
	return true


func select_spell(wanted: StringName) -> bool:
	# The Ability Wheel's only entry point, and deliberately the only way to arm
	# a spell. Routing every source of "what is in my hand" through one function
	# is what makes "is this spell reachable?" a question a test can answer by
	# walking the library instead of a hope.
	var spell := spell_by_id(wanted)
	if spell == null:
		return false
	_adopt_spell(spell.school_id, spell.id)
	return true


func _adopt_spell(school_id: StringName, wanted: StringName) -> void:
	selected_school = school_id
	casting_spell = school_id
	spell_id = wanted


func current_school() -> MagicSchool:
	# selected_school is the school the Ability Wheel confirmed, so it — not the
	# in-flight cast — decides what "current" means. The cast snapshots its own
	# spell so a wheel change mid-cast cannot swap it underneath.
	return schools.get(selected_school)


func current_spell() -> SpellDefinition:
	var school := current_school()
	if school == null:
		return null
	return school.get_spell(spell_id) if school.get_spell(spell_id) != null else school.primary()


func spell_by_id(wanted: StringName) -> SpellDefinition:
	for school in schools.values():
		var found := (school as MagicSchool).get_spell(wanted)
		if found != null:
			return found
	return null


func is_infused() -> bool:
	return blade_infusion_left > 0.0 and blade_element != &"physical"


func grant_infusion(element_id: StringName, duration: float) -> void:
	blade_infusion_left = maxf(blade_infusion_left, duration)
	blade_element = element_id


func _update_magic(delta: float) -> void:
	if blade_infusion_left > 0.0:
		blade_infusion_left = maxf(0.0, blade_infusion_left - delta)
		if blade_infusion_left == 0.0:
			blade_element = &"physical"
	if wind_step_left > 0.0:
		wind_step_left = maxf(0.0, wind_step_left - delta)
	# Carrying the blade through a live field lights it. The sword joins the
	# magic system by being moved through it, never by opening a menu.
	if active_field != null and is_instance_valid(active_field) and active_field.is_alive():
		var element := ElementLibrary.get_element(active_field.element_id)
		if element != null and element.infusion_duration > 0.0:
			if player.global_position.distance_to(active_field.global_position) <= active_field.radius:
				grant_infusion(element.id, element.infusion_duration)


func _spend_wind_step() -> void:
	wind_step_left = 2.6


# Wind crossing a live element carries it outward: fire spreads, frost chills
# whatever is standing nearby. This is the mechanical reason the two elements
# are worth combining instead of stacking.
func wind_spread() -> bool:
	var spread_any := false
	var parent := player.get_parent()
	for node in parent.get_children():
		if node is ElementField and (node as ElementField).is_alive():
			var field := node as ElementField
			var element := ElementLibrary.get_element(field.element_id)
			if element != null and element.spread_by_wind:
				field.spread()
				spread_any = true
	# The gust also has to reach the world, not only the actors: pushing a crate
	# is the visible proof that wind is force rather than damage.
	if parent.has_node("WindProps"):
		var props: WindProps = parent.get_node("WindProps")
		var blown := props.blow(
			player.global_position, -player.global_transform.basis.z, 7.0, 55.0, 6.0
		)
		if blown > 0:
			spread_any = true
	if spread_any:
		style_message.emit("风 · 扩散")
	return spread_any


func on_the_move_hit_bonus() -> bool:
	# Whether the last attack was committed by a player who was moving of their
	# own accord. Public so the Lab and the movie renderer can show it instead of
	# asking a viewer to trust the caption.
	return commit_moving


func _player_intends_to_move() -> bool:
	# Input intent, not velocity: the attack's own lunge can fake velocity, and
	# it cannot fake a held direction. Indices on purpose as well, because with
	# the action map missing this must degrade to "standing", not to an error.
	if not InputMap.has_action(&"move_forward"):
		return false
	return (
		Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back").length() > 0.1
	)


func speed_multiplier() -> float:
	# 风步 is momentum, not a teleport: it changes how fast you can change where
	# you are, and it decays.
	if wind_step_left > 0.0:
		return 1.28
	return 1.0


func _bind_key(action: StringName, key: Key) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var event := InputEventKey.new()
	event.physical_keycode = key
	InputMap.action_add_event(action, event)


func _bind_mouse(action: StringName, button: MouseButton) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var event := InputEventMouseButton.new()
	event.button_index = button
	InputMap.action_add_event(action, event)


func _unhandled_input(event: InputEvent) -> void:
	# ---------------------------------------------------------------- THE BODY
	# Dodge is owned by InputContract (Shift Down → request dodge). Magic is the
	# off hand, so casts survive a weapon switch. 风 × 链 stays reachable because
	# casting does not stop when the chain comes out.
	if event.is_action_pressed("fire_cast"):
		select_school(&"fire")
		request(&"cast")
		return
	if event.is_action_pressed("frost_cast"):
		select_school(&"frost")
		request(&"cast")
		return
	if event.is_action_pressed("wind_cast"):
		select_school(&"wind")
		request(&"cast")
		return
	if event.is_action_pressed("cast_selected"):
		request(&"cast")
		return
	# ----------------------------------------------------------------- THE SWORD
	# Everything below belongs to the sword, and the sword is not always in the
	# player's hands. This one gate is the whole arbitration: no style branch, no
	# second CombatController, and the chain reads the same slot to decide whether
	# it is the one being held.
	if not _holds_sword():
		return
	if event.is_action_pressed("inspect"):
		if state == State.IDLE and equip_blend >= 1.0:
			inspect_left = 1.5
		return
	# INPUT CONTRACT: LMB primary, RMB parry, E/X/C/V skills. Adapters keep
	# existing iaido / heavy_attack / block action names working.
	if event.is_action_pressed("light_attack") or event.is_action_pressed("attack_primary"):
		request(&"light")
	elif event.is_action_pressed("heavy_attack") or event.is_action_pressed("skill_2"):
		request(&"heavy")
	elif (event.is_action_released("heavy_attack") or event.is_action_released("skill_2")) and state == State.CHARGE:
		release_heavy()
	elif event.is_action_pressed("style_skill_1"):
		trigger_skill(0)
	elif event.is_action_pressed("style_skill_2"):
		trigger_skill(1)
	elif event.is_action_pressed("style_skill_3") or event.is_action_pressed("skill_3"):
		trigger_skill(2)
	elif event.is_action_pressed("iaido") or event.is_action_pressed("skill_1"):
		request(&"iaido")
	elif event.is_action_pressed("ultimate"):
		request(&"ultimate")
	elif event.is_action_pressed("block") or event.is_action_pressed("parry"):
		request(&"block")
	elif event.is_action_released("block") or event.is_action_released("parry"):
		if buffer.pending == &"block":
			buffer.clear()
		if state in [State.BLOCK, State.PARRY]:
			finish_action()


func _holds_sword() -> bool:
	# No slot at all means a stage that predates the weapon switch: the sword is
	# then simply always the active weapon.
	var slot := player.get_node_or_null("WeaponSlot")
	if slot == null:
		return true
	return bool(slot.call("holds", WeaponSlot.SWORD))


# ---------------------------------------------------------------- lifecycle

func _process(delta: float) -> void:
	combat_time += delta
	state_time += delta
	pose_time += delta
	inspect_left = maxf(0.0, inspect_left - delta)
	var inspecting := state == State.IDLE and inspect_left > 0.0 and equip_blend >= 1.0 and _holds_sword()
	inspect_mix = move_toward(inspect_mix, 1.0 if inspecting else 0.0, delta / (0.12 if inspecting else 0.07))
	if state == State.IDLE and inspect_mix <= 0.001 and buffer.pending != &"":
		var manager := player.get_node_or_null("WeaponManager")
		if equip_blend >= 1.0 or (manager != null and manager.drawing_in and equip_blend >= SwordBasic.NE_BLADE_CLEAR):
			var next := buffer.take(_now())
			if next != &"":
				_start(next)
	guard_recoil = maxf(0.0, guard_recoil - delta * 3.2)
	if enhance_left > 0.0:
		enhance_left = maxf(0.0, enhance_left - delta)
		if enhance_left == 0.0:
			style_message.emit("纳息 · 结束")
	_update_sheath(delta)
	_update_flow(delta)
	_update_magic(delta)
	measure_range = measure_distance_now()
	measure_state = measure_label()

	# THE SWORD'S OWN STATES NEED THE SWORD (§5).
	#
	# Casting and dodging belong to the body and the off hand - §2 is main hand sword,
	# off hand magic, and "风 × 链 is only reachable because casting does not stop when
	# the chain comes out" - so those two keep running through a weapon switch. The
	# blade's states do not.
	#
	# Without this, a cut that was mid-arc when the chain came out keeps advancing on
	# a weapon nobody is holding, and `_process_move` re-opens the hitbox that the
	# unequip had just closed: an invisible, unowned blade still landing hits from a
	# body that is holding a chain. It also cannot be caught by a screenshot, which is
	# why the guard is here rather than in the switch.
	var blade_can_run := _holds_sword()
	if blade_can_run and state == State.ATTACK and active_move != null and active_move.id in SwordBasic.light_chain() and buffer.pending == &"light" and _can_cancel(&"light"):
		var queued := buffer.take(_now())
		if queued != &"": _start(queued)
	match state:
		State.ATTACK, State.RIPOSTE, State.SKILL:
			if blade_can_run:
				_process_move()
		State.CHARGE:
			if blade_can_run:
				_process_charge(delta)
		State.CAST:
			_process_cast()
		State.DODGE:
			if state_time >= tuning.dodge_duration:
				finish_action()
	_drive_saya()


## The off hand, every frame.
##
## The sheath has two ways of knowing where to be, and which one applies is the
## whole of this function: a move that authors the sheath's own beats is asking
## it to ACT, and every other frame is asking it to hold still. There is no third
## case and, in particular, no "derive it from the blade" case — see
## `SwordSayaRig`'s header for the 0.21 m of scabbard travel per cut that one cost.
##
## `presence` and `pull` are still written because they are true statements about
## the off hand; nothing about the sheath's pose reads the latter any more.
func _drive_saya() -> void:
	if saya_rig == null or not is_instance_valid(saya_rig):
		return
	saya_rig.visible = _saya_has_the_stage()
	saya_rig.presence = smoothstep(0.0, 0.55, equip_blend)
	# Cleared every frame and set by the only thing that can set it. A stale
	# absolute pose left armed would pin the hand to where the last draw ended.
	_saya_has_absolute = false
	var pull := 0.0
	var choreographed := false
	if active_move != null and state in [State.ATTACK, State.RIPOSTE, State.SKILL]:
		var raw := active_move.raw_time_at(state_time, move_startup_scale)
		pull = SwordBasic.saya_pull(active_move, raw)
		choreographed = _drive_saya_beats(active_move, raw)
		_drive_saya_ctrl(active_move, raw)
	elif equip_blend < 0.999:
		# The draw runs on the SAME clock the pose sample uses, so the sheath and
		# the blade cannot land on different frames of one five-beat sentence.
		var equip := _equip_move
		var raw := equip_blend * equip.total_time()
		pull = SwordBasic.saya_pull(equip, raw)
		choreographed = _drive_saya_beats(equip, raw)
		_drive_saya_ctrl(equip, raw)
	saya_rig.pull = pull
	# `asked` does NOT spare the rest pose. A move's control beats are an OFFSET
	# from the hand, not a pose of their own — `seat_home()` is the only thing that
	# builds a transform out of (hand, offset), so a cut that asks for 4 cm still
	# goes through it and simply gets a different answer.
	if not choreographed:
		saya_rig.seat_home()
	_drive_hand()


## ===========================================================================
## THE LEFT HAND, EVERY FRAME
## ===========================================================================
##
## Three inputs and nothing else, and the order they are decided in is the whole
## of §29 ("Saya moves only when it has a reason"):
##
##   THE AUTHORED POSE   always. Whatever the move asked for, or the rest.
##   SEAT PIN            how close the blade is to its mouth this frame.
##   LIVELINESS          whether anything is happening at all.
##
## The last two are the ones that had to be gotten right rather than written,
## and both are the same argument from opposite ends:
##
##   * `seat_pin` is the hand going STILL. A sixth of a centimetre of breath
##     while a blade with `FIT_CLEAR` = 1.75 mm of clearance comes through the
##     mouth is a blade through the wall, and the frames it would happen in are
##     exactly the frames the act is about.
##   * `live_target` is the hand being ALIVE. With nothing running the scabbard
##     has to breathe, because the alternative is the Pass01 fault: a prop
##     welded to the camera, measured at 0.0000 m of travel across four cuts.
##
## Both are scaled by the same smooth distance, so there is no frame in which the
## hand is half-alive at the mouth.
func _drive_hand() -> void:
	if saya_hand == null or not is_instance_valid(saya_hand):
		return
	saya_hand.visible = saya_rig.visible
	# ===========================================================================
	# THE ACT'S OWN OFFSET GOES ON THE HAND, NOT ON THE SCABBARD
	# ===========================================================================
	# Measured by `tools/probe_saya_per_move.gd` before this line existed: across
	# A1/A2/A3/A4 the HAND travelled 0.0-0.6 mm while the scabbard's mouth moved
	# 48-76 mm away from it. The act was displacing the scabbard THROUGH a
	# stationary grip.
	#
	# That is the same number stated three ways, and all three are faults:
	#
	#   §30  the left arm is solved onto this node's transform, so a hand that
	#        does not move cannot show "Saya 向下 Tuck, 左肘要变化" -- the arm had
	#        nothing to respond to. Measured, not assumed: `hand` column = 0.0 mm.
	#   §39-2  "does the saya read as being held by the left hand" is YES at idle
	#        (the gap is zero there) and NO during every act, which is worse than
	#        a consistent no, because it is a grip that opens only when you look.
	#   §27  "Saya vs Left Hand" is a P0 class. A scabbard sliding 76 mm out of
	#        the grip is that class from the other side: not a mesh through a mesh,
	#        but a held object letting go.
	#
	# The mouth's own trajectory does not change -- `seat_home` read
	# `hand.position + control_pos` and now reads `hand.position`, where the hand
	# already has `control_pos` in it. The same total, carried by the object that
	# is supposed to be doing the carrying, so the arm comes with it.
	var rest := SwordBasic.saya_home(saya_rig.weapon_id)
	var rest_basis := Basis.from_euler(SwordBasic.SAYA_MOUTH_R)
	if _saya_has_absolute:
		# THE DRAW, and there is nothing to fold in: the draw IS the pose. It wins
		# outright rather than blending with the rest, for the same reason the draw
		# authors absolute beats at all -- a hold is a stretch of time in which the
		# scabbard does not move while the blade does, and a blend would move it.
		rest = _saya_absolute.origin
		rest_basis = _saya_absolute.basis
	else:
		var weight := saya_rig.control_weight
		if weight > 0.0:
			rest_basis = Basis.from_euler(saya_rig.control_rot * weight) * rest_basis
			rest += saya_rig.control_pos * weight
	saya_hand.base_position = rest
	saya_hand.base_basis = rest_basis
	# The body's own velocity, expressed in the hand's parent frame. Taken from
	# the player rather than from the camera rig so that a head-turn does not read
	# as the hand lagging. The vertical is dropped: a falling body's fall is the
	# legs' business and a scabbard that plunges with it reads as a loose prop.
	var rig := saya_hand.get_parent() as Node3D
	if rig != null:
		var local := rig.basis.inverse() * player.velocity
		saya_hand.body_velocity = Vector3(local.x, 0.0, local.z)
	var snap := pose_snapshot()
	var gap := SwordBasic.mouth_gap_to(snap["position"], snap["rotation"],
		saya_mouth(), saya_rig.weapon_id)
	saya_hand.seat_pin = SwordBasic.seat_restraint(gap, saya_rig.weapon_id)
	# §29, as one line: alive only when nothing is being asked. A draw is the hand
	# holding a scabbard against a blade rather than carrying it, and a cut is the
	# hand working — neither is a moment for the hand to be breathing on its own.
	var busy := equip_blend > 0.0001 and equip_blend < 0.999
	var working := active_move != null \
		and state in [State.ATTACK, State.RIPOSTE, State.SKILL]
	saya_hand.live_target = 0.0 if (busy or working) else 1.0


## Where the scabbard's mouth IS, as opposed to where it rests.
##
## `SwordBasic.saya_home()` is the mouth of a scabbard nobody is holding, and it
## is the answer for every act that does not move one. It is the wrong answer for
## the four that do — see `SwordBasic.mouth_gap_to`. One accessor rather than a
## read of `saya_rig.transform` at each call site, because the three readers of
## this distance have to be reading the same one.
func saya_mouth() -> Vector3:
	if saya_rig != null and is_instance_valid(saya_rig):
		return saya_rig.mouth_point()
	return SwordBasic.saya_home()


## Places the sheath from the LEFT HAND's own authored request (`saya_ctrl_*`).
##
## Returns whether the move had one, so the caller knows not to fall through to
## the plain rest — a move that authors nothing for the hand must say so, instead
## of leaving the last frame's offset welded on.
##
## It is NOT a second way to place the saya: the answer still comes from
## `seat_home()`, and this only writes the offset that function reads. That is
## why a move with control beats but no absolute beats (every cut) and a move with
## both (the draw) cannot disagree about where the scabbard is.
func _drive_saya_ctrl(move: SwordMove, t: float) -> bool:
	saya_rig.control_weight = 0.0
	if move == null or not move.has_saya_ctrl():
		return false
	var shot := SwordPoseSampler.sample_arrays(
		move.saya_ctrl_times, move.saya_ctrl_positions,
		move.saya_ctrl_rotations, PackedVector3Array(), t)
	if shot.is_empty():
		return false
	saya_rig.control_pos = shot["position"]
	saya_rig.control_rot = shot["rotation"]
	saya_rig.control_weight = 1.0
	return true


## Places the sheath from its own authored beats. Returns whether it did, so a
## move without them falls through to the derived seating instead of being left
## where it was — a saya stuck at the last choreographed frame is worse than one
## that is merely derived.
func _drive_saya_beats(move: SwordMove, t: float) -> bool:
	if move == null or not move.has_saya_beats():
		return false
	var shot := SwordPoseSampler.sample_arrays(
		move.beat_times, move.saya_positions, move.saya_rotations, move.saya_bows, t)
	if shot.is_empty():
		return false
	saya_rig.place_absolute(shot["position"], shot["rotation"])
	# ===========================================================================
	# AND THE HAND GOES WITH IT
	# ===========================================================================
	# The draw used to place the scabbard absolutely and leave the hand at its rest
	# pose, which is the same fault the four cuts had, in a different code path: the
	# arm is solved onto the HAND, so an arm whose hand is at the combat rest while
	# the scabbard climbs to the waist presents a hand that is not holding anything.
	#
	# The body clip's own caption for this act already claimed otherwise -- "the
	# hand carries the koiguchi up past the hip and the arm is ALIVE doing it" --
	# which is what a caption written before the measurement is worth.
	#
	# No second authoring pass is needed: the scabbard's origin IS its mouth, and the
	# hand grips at the koiguchi, so "where the scabbard is" IS "where the hand is".
	# One pose, read twice.
	_saya_absolute = Transform3D(Basis.from_euler(shot["rotation"]), shot["position"])
	_saya_has_absolute = true
	return true


## Whether THIS rig is the one wearing the saya right now.
##
## ===========================================================================
## FOUR SCABBARDS, ONE WAIST
## ===========================================================================
## A probe over a live session (`tools/probe_saya_visibility.gd`) found the
## player wearing TWO scabbards at once, from two different rigs, reachable
## three separate ways:
##
##   * `SwordSayaRig`                      -- this file's own. A1 touches its
##                                            mouth, A3 goes home into it, and
##                                            its seating is derived from the
##                                            sword so it cannot drift.
##   * `SheathAnchor/CeremonyScabbard`     -- `IaidoDirector`'s, opened for the
##                                            whole of 居合斩.
##   * `TempSwordVisual/Scabbard`          -- 藏锋's sheathed idle, shown for as
##                                            long as `sheath_enabled` is on.
##   * `TempSwordVisual/Sword_FP/Sheath`   -- the training rack's exhibit.
##
## Every one of them is individually correct and none of them can see the other
## three, so the collision was not visible in ANY file — it only existed on
## screen. The rule that resolves it belongs here, because this function is the
## only thing that already runs every frame with the sword's own pose in hand.
##
## It is a PRESENCE question rather than a pose one, so it is answered before
## the pose is computed: a saya that is not on stage should not be paid for at
## all.
func _saya_has_the_stage() -> bool:
	# 1. THE SWORD HAS TO BE THE WEAPON IN HAND. A saya riding a hip while the
	#    chain is out is a sword that was never put away — and this was the
	#    visible half of the same bug. §20 puts the whole point in the order:
	#    the blade goes home FIRST, so by the time the switch finishes the rig
	#    has nothing left to be.
	if not _holds_sword():
		return false
	# 2. THE CEREMONY BRINGS ITS OWN. `IaidoDirector` opens `CeremonyScabbard`
	#    and drives the blade into it along its own eight-second timeline. Two
	#    saya means two mouths, and the blade can only be inside one of them.
	if iaido_director != null and iaido_director.active:
		return false
	# 3. 藏锋's SHEATHED IDLE BRINGS ITS OWN TOO. `TempSwordVisual/Scabbard`
	#    shows at a pose the moveset authors, for the whole time the style is
	#    selected. Standing down for the ENTIRE style — and not merely while
	#    `sheath_amount` is non-zero — is deliberate: the style's scabbard is
	#    visible from the first frame the style is chosen, so a gate that waited
	#    for the blade to actually start travelling would show both for that
	#    frame, which is precisely the artifact this rule exists to remove.
	#
	#    Giving up the derived seating here is a real cost and not a free win:
	#    under 藏锋 the sword language's A1/A3 ride the moveset's own authored
	#    scabbard pose instead of this rig's. It is the smaller lie of the
	#    two — one saya with an authored pose beats two saya with a perfect one.
	if moveset != null and moveset.sheath_enabled:
		return false
	return true


func _process_move() -> void:
	if active_move == null:
		finish_action()
		return
	var startup := effective_startup()
	var strike_end := startup + active_move.strike
	var contact_start := startup
	if active_move.id in SwordBasic.light_chain():
		contact_start += active_move.strike * 0.38
	var should_open := (
		active_move.damage > 0.0
		and active_move.reach_mode in [&"body", &"wave"]
		and state_time >= contact_start
		and state_time < strike_end
	)
	if should_open != hitbox_open:
		hitbox_open = should_open
		hitbox.set_active(should_open)
	# Announced once, at the moment the blade actually departs. A move that is
	# cancelled inside its own wind-up never gets here, which is correct: there
	# was no swing to describe.
	if not _swing_announced and state_time >= startup and active_move.strike > 0.0:
		_swing_announced = true
		swing_started.emit(active_move)
		_emit_move_camera(active_move)
	_dispatch_reach(active_move, startup)
	if state_time >= _move_end_time():
		finish_action()


# ===========================================================================
# THE DISTANCE IS THE MECHANIC (§15 / §22)
# ===========================================================================
#
# A cut that leaves the sword is not a longer hitbox, so three of the four beats
# resolve here instead of through `CombatHitbox`: A2's wave begins where the
# blade was, A3's marks happen at an instant, A4's sweep is sliced across its own
# travel. `SwordReach` owns HOW each of them decides; this function owns WHEN,
# and it answers that from the move's own data — the same numbers the sampler and
# the event list read — so retiming a beat moves its hit with it.
#
# The clock is `raw_time_at`, not `state_time`. A draw bonus shortens the wind-up
# by 22%, and a mark hung off the scaled clock would arrive early on exactly the
# swings the player earned.
func _dispatch_reach(move: SwordMove, startup: float) -> void:
	if reach == null or move == null:
		return
	match move.reach_mode:
		&"wave":
			# One cut, launched as the blade departs. Not on the hitstop, not on
			# the input: the wave exists because the sword moved.
			var release_at := startup + move.strike * 0.50 if move.id == SwordBasic.A2 else startup
			for event in move.events:
				if event.get("id") == SwordBasic.EV_WAVE:
					release_at = startup + maxf(0.0, float(event["t"]) - move.startup)
			if not _reach_fired.has("wave") and state_time >= release_at:
				_reach_fired["wave"] = true
				reach.fire_wave(move, 1.0)
		&"trace":
			# A cut that happens AT A PLACE. Each mark resolves on its own
			# instant, and the instants are the move's own — the same constants
			# the beat list and the event list use, so the mark the player sees,
			# the cut that landed and the sound that played are one number
			# wearing three hats.
			var raw := move.raw_time_at(state_time, move_startup_scale)
			for i in move.traces.size():
				var key := "trace_%d" % i
				if _reach_fired.has(key):
					continue
				if raw < float(move.traces[i].get("t", 0.0)):
					continue
				_reach_fired[key] = true
				# The index travels WITH the mark. `cut_trace` reports it back on
				# `trace_resolved`, and a listener that had to recover it from a
				# key the authored mark does not carry would silently collapse
				# three cuts into one — which is exactly what the first run of the
				# V2 acceptance sheet did: all three marks found a body and the
				# sheet reported "1 of 3", because all three reported index 0.
				var mark: Dictionary = (move.traces[i] as Dictionary).duplicate()
				mark["index"] = i
				reach.cut_trace(move, mark, move.reach_damage_scale)
		&"arc":
			# THE SWEEP TAKES TIME, so it is resolved in slices and only ever
			# forwards. Resolving all 270 degrees at the end would strike a body
			# that was behind the player before the blade had moved at all, which
			# is a shockwave wearing a sword's animation.
			var slices := maxi(move.arc_slices, 1)
			if _arc_slice >= slices:
				return
			var from := startup
			var to := startup + move.strike
			var u := clampf((state_time - from) / maxf(to - from, 0.0001), 0.0, 1.0)
			var want := int(floor(u * float(slices)))
			var span := move.reach_arc_to - move.reach_arc_from
			while _arc_slice <= want and _arc_slice < slices:
				var a0 := move.reach_arc_from + span * float(_arc_slice) / float(slices)
				var a1 := move.reach_arc_from + span * float(_arc_slice + 1) / float(slices)
				reach.sweep_arc(move, _arc_slice, a0, a1, move.reach_damage_scale)
				_arc_slice += 1


func _process_charge(delta: float) -> void:
	if active_move == null:
		finish_action()
		return
	if Input.is_action_pressed("heavy_attack") or Input.is_action_pressed("skill_2"):
		charge_ratio = minf(1.0, charge_ratio + delta / maxf(tuning.heavy_charge_time, 0.05))
		return
	# Programmatic or released: a short press is a tap Heavy, never a stuck state.
	if state_time >= tuning.heavy_tap_grace or charge_ratio >= 1.0:
		release_heavy()


func _process_cast() -> void:
	var ability := _current_ability()
	if ability == null:
		finish_action()
		return
	var should_open := state_time >= ability.startup and state_time < ability.startup + ability.active
	if should_open != hitbox_open:
		hitbox_open = should_open
		_current_spell_hitbox().set_active(should_open)
		if should_open:
			# Fires exactly once per cast, when the active window opens.
			_spend_spell()
	if state_time >= ability.startup + ability.active + ability.recovery:
		finish_action()


func _update_sheath(delta: float) -> void:
	if not moveset.sheath_enabled:
		sheath_amount = 0.0
		idle_time = 0.0
		return
	if state == State.IDLE:
		idle_time += delta
		# 截锋 shortens the wait before the sword starts going home: a clean
		# deflect IS 藏锋's moment, so it must also feed the style's own loop.
		var delay := moveset.sheath_delay
		if _now() < sheath_waive_until:
			delay = 0.0
		if idle_time >= delay:
			var speed := 1.0 / maxf(moveset.sheath_time * _sheathe_time_scale(), 0.05)
			sheath_amount = minf(1.0, sheath_amount + delta * speed)
	else:
		idle_time = 0.0
		# Drawing is never slow: the strike itself covers the motion.
		sheath_amount = maxf(0.0, sheath_amount - delta / 0.08)


func _sheathe_time_scale() -> float:
	if enhance_left <= 0.0 or enhance_skill_id == &"":
		return 1.0
	var skill := moveset.get_skill(enhance_skill_id)
	if skill == null or skill.kind != SwordSkill.Kind.ENHANCE:
		return 1.0
	return skill.enhance_sheathe_scale


# ------------------------------------------------------------------ 势 / Flow

func _update_flow(delta: float) -> void:
	if not moveset.flow_enabled:
		flow = 0.0
		flow_peak = 0.0
		flow_idle_time = 0.0
		return
	# Standing still is what lets the momentum go. Attacking or being hit keeps
	# it alive; simply holding a guard does not.
	flow_peak = maxf(flow_peak, flow)
	if state in [State.IDLE, State.BLOCK]:
		flow_idle_time += delta
		if flow_idle_time > moveset.flow_decay_delay:
			_lose_flow(moveset.flow_decay * delta)
	else:
		flow_idle_time = 0.0


func flow_ratio() -> float:
	if not moveset.flow_enabled or moveset.flow_max <= 0.0:
		return 0.0
	return clampf(flow / moveset.flow_max, 0.0, 1.0)


func _gain_flow(amount: float) -> void:
	if not moveset.flow_enabled:
		return
	flow_idle_time = 0.0
	flow = clampf(flow + amount, 0.0, moveset.flow_max)
	flow_peak = maxf(flow_peak, flow)


func _lose_flow(amount: float) -> void:
	if not moveset.flow_enabled:
		return
	flow = maxf(0.0, flow - amount)


func reset_flow() -> void:
	flow = 0.0
	flow_peak = 0.0
	flow_idle_time = 0.0


# ------------------------------------------------------------------ requests

# ------------------------------------------------------- measure (白蔷庭)

# The nearest actor standing in the small cone in front of the player. Group
# membership is the entire contract — the controller never asks what kind of
# thing it found, exactly as it never asks what an element means.
func measure_target() -> Node3D:
	var best: Node3D = null
	var best_distance := moveset.measure_max_range
	var origin := player.global_position
	var forward := -player.global_transform.basis.z
	var cos_limit := cos(deg_to_rad(moveset.measure_cone_degrees))
	for node in get_tree().get_nodes_in_group(CombatTuning.TARGET_GROUP):
		var actor := node as Node3D
		if actor == null or not is_instance_valid(actor):
			continue
		if actor.has_method("is_alive") and not actor.call("is_alive"):
			continue
		var to_actor := actor.global_position - origin
		to_actor.y = 0.0
		var distance := to_actor.length()
		if distance <= 0.001 or distance > best_distance:
			continue
		if forward.dot(to_actor / distance) < cos_limit:
			continue
		best = actor
		best_distance = distance
	return best


func measure_distance_now() -> float:
	if not moveset.measure_enabled:
		return -1.0
	var target := measure_target()
	if target == null:
		return -1.0
	var to_target := target.global_position - player.global_position
	to_target.y = 0.0
	return to_target.length()


# &"" means "the style has no measure" or "nobody is in front of you". An empty
# lane is not "too far" — there is simply no fight to measure yet.
func measure_label() -> StringName:
	if not moveset.measure_enabled or measure_range < 0.0:
		return &""
	if measure_range < moveset.measure_close:
		return &"close"
	if measure_range > moveset.measure_far:
		return &"far"
	return &"ideal"


# Measure buys startup, reach and posture. It must never buy damage, or the style
# stops being about controlling distance and becomes about standing still in the
# right spot.
func _apply_measure_scale(move: SwordMove) -> void:
	move_reach_bonus = 0.0
	if not moveset.measure_enabled:
		return
	match measure_label():
		&"close":
			move_startup_scale *= moveset.measure_close_startup_scale
			move_poise_scale *= moveset.measure_close_poise_scale
		&"far":
			move_startup_scale *= moveset.measure_far_startup_scale
			move_poise_scale *= moveset.measure_far_poise_scale
		&"ideal":
			move_startup_scale *= moveset.measure_ideal_startup_scale
			move_poise_scale *= moveset.measure_ideal_poise_scale
			# Only a properly extended point is longer: 穿庭 and 白蔷刺 gain
			# reach, a short horizontal cut gains nothing.
			if move.hitbox_offset.z < -1.6:
				move_reach_bonus = moveset.measure_ideal_reach
			measure_ideal_count += 1


# ----------------------------------------------------------- bind (白蔷庭)

# The perfect guard did not push the attacker away; it trapped the blade. The
# player now has a very short window with three exits, and the choice is the
# reward — not a damage number.
func _bind_open(now: float) -> bool:
	return moveset.guard.bind_enabled and now < bind_until and state == State.PARRY


func _start_bind_exit(move_id: StringName) -> bool:
	var move := moveset.get_move(move_id)
	if move == null:
		return false
	bind_until = 0.0
	riposte_until = 0.0
	move_startup_scale = 1.0
	move_poise_scale = 1.0
	attack_kind = &"bind"
	_begin_move(move, State.RIPOSTE)
	return true


func request(action: StringName) -> bool:
	var now := _now()
	if inspect_mix > 0.001:
		inspect_left = 0.0
		if action == &"light":
			# A short return before seating A1 avoids teleporting from inspect into the bore.
			buffer.push(action, now)
			return false
		inspect_mix = 0.0
	# 合围: Heavy inside the bind window cuts on the way back out. Light inside
	# the same window is the riposte and is handled immediately below, because
	# in a bind the deck window and the riposte window are the same window.
	if action == &"heavy" and _bind_open(now) and moveset.guard.bind_heavy_id != &"":
		return _start_bind_exit(moveset.guard.bind_heavy_id)
	# Riposte is a real reward window: Light inside it always wins.
	if action == &"light" and _riposte_open(now):
		return _start_riposte()
	# 燕返 follow-up: only exists after the first cut connected.
	if action in [&"light", &"skill"] and _followup_open(now):
		return _start_followup()
	if state == State.IDLE:
		var accepted := _start(action)
		if not accepted and action == &"light" and equip_blend < 1.0:
			buffer.push(action, now)
		return accepted
	if _can_cancel(action):
		return _start(action)
	# One committed combo press is remembered until its existing link gate.
	# Startup presses still drop, and holding a button cannot queue a whole chain.
	if action == &"light" and state == State.ATTACK and active_move != null and active_move.id in SwordBasic.light_chain() and state_time >= effective_startup():
		buffer.push(action,now)
		var link_at := effective_startup()+active_move.strike+active_move.pose_span()*active_move.cancel_open
		buffer.expires_at = now+maxf(buffer.duration,link_at-state_time+0.06)
		return false
	# Buffering a 7-second ceremony would be a trap; drop it instead.
	if action in [&"iaido", &"ultimate"]:
		return false
	# §18: INPUT BUFFER IS NOT COMBO MEMORY.
	#
	# A cancel is "stop what you are doing and do this instead", and it opens as
	# soon as the blade has been committed — see `_can_cancel`, which is reached
	# above this line. A BUFFER is "remember this and start it when I finish".
	# Accepting one from the first frame of a swing turns a mashed button into
	# four hundred milliseconds of memory wearing a hundred-and-fifty-millisecond
	# name, and the player's next input is then whatever they happened to press
	# while watching the last one. The window opens only in the last slice of the
	# move, which is the only stretch in which "I saw the end coming" is true.
	if state_time < _buffer_open_at():
		return false
	buffer.push(action, now)
	return false


## How deep into the current move a buffered input starts being remembered.
##
## Mirrors `_can_cancel`'s arithmetic deliberately — same startup scaling, same
## recovery scaling — because a buffer window pinned to the raw move and a cancel
## window pinned to the played move would disagree the moment a style bought
## itself a faster draw.
func _buffer_open_at() -> float:
	if active_move == null:
		return 0.0
	return active_move.startup * move_startup_scale \
		+ active_move.strike \
		+ active_move.pose_span() * recovery_scale() * 0.62


func _can_cancel(action: StringName) -> bool:
	match state:
		State.PARRY:
			# A bind adds one exit to the parry state: Heavy. Light and Dodge are
			# already the other two.
			if action == &"heavy":
				return _bind_open(_now()) and moveset.guard.bind_heavy_id != &""
			return action in [&"light", &"dodge", &"block"]
		State.ATTACK, State.RIPOSTE:
			if active_move == null:
				return true
			# 势 opens the exits earlier: at full Flow the style stops snagging
			# between cuts. Note this lowers the *threshold fraction*, because a
			# smaller fraction means the cancel unlocks sooner.
			var transition := 1.0
			if moveset.flow_enabled:
				transition = lerpf(1.0, maxf(0.15, 1.0 - moveset.flow_transition_bonus), flow_ratio())
			# 惊鸿 stacks on top of 势: while it is up, the style stops snagging
			# almost entirely, which is what "更自由衔接" has to mean in data.
			if enhance_left > 0.0 and enhance_transition_bonus > 0.0:
				transition *= maxf(0.12, 1.0 - enhance_transition_bonus)
			var cancel_at := (
				effective_startup()
				+ active_move.strike
				+ active_move.pose_span() * active_move.cancel_open * transition
			)
			# 假章: a feint is the ONE move whose exit opens during the wind-up.
			# The threat is the pose; taking the pose back is the technique.
			if active_move.feint_cancel_from < 1.0:
				cancel_at = minf(cancel_at, effective_startup() * active_move.feint_cancel_from)
			if state_time < cancel_at:
				return false
			if action == &"dodge":
				# Dodging out is allowed once the blade has actually been
				# committed past contact: the swing cannot be free, or attacks
				# stop meaning anything. 回风 opens earliest, 藏锋 latest.
				# A feint pulls this gate back with its wind-up, or the style
				# could bluff but not leave.
				var dodge_at := effective_startup() + active_move.strike * moveset.dodge_cancel_from * transition
				if active_move.feint_cancel_from < 1.0:
					dodge_at = minf(dodge_at, effective_startup() * active_move.feint_cancel_from)
				return state_time >= dodge_at
			return action in [&"light", &"heavy", &"block"]
		State.SKILL:
			return action == &"dodge" and state_time >= 0.12
		State.CHARGE:
			return action in [&"dodge", &"block"]
		_:
			return false


func _can_act_now() -> bool:
	return state == State.IDLE or _can_cancel(&"light")


func finish_action() -> void:
	# Did a CUT just end, or is this a cleanup call with nothing running? The
	# difference decides §17, and getting it wrong is invisible until you count
	# the cuts: `finish_action()` is also reached from `stow()` and from
	# `_process_move`'s empty guard, i.e. with `active_move == null` and
	# `attack_kind` still reading `light` from a cut that ended minutes ago.
	var ended_a_chain_cut := active_move != null \
		and attack_kind in [&"light", &"sprint", &"retreat"]
	if state == State.SKILL:
		_finish_skill()
	_close_hitbox()
	magic_circle.set_casting(false)
	active_spell = null
	# A whiff costs momentum. If missing were free, 回风 would just be a faster
	# Universal and the style would have no idea behind it.
	if (
		moveset.flow_enabled
		and not move_hit
		and attack_kind in [&"light", &"sprint", &"retreat", &"heavy", &"skill"]
	):
		_lose_flow(moveset.flow_loss_miss)
	if state == State.IAIDO:
		screen_fx.reset()
		camera_feedback.fov_hold = 0.0
		time_effects.reset()
	hitbox_open = false
	# A wave that outlives its attack is a cut nobody is holding any more: A2's
	# crescent is released here rather than being allowed to fly on into a
	# weapon switch, a dodge or the next style's chain.
	if reach != null:
		reach.clear()
	active_move = null
	active_skill = null
	active_move_id = &""
	move_startup_override = -1.0
	move_startup_scale = 1.0
	move_poise_scale = 1.0
	move_reach_bonus = 0.0
	charge_ratio = 0.0
	chain_active = false
	# The chain stays open for the style's grace window even if nothing was
	# buffered: the next cut is a continuation, not a restart.
	#
	# ONLY IF A CUT ACTUALLY ENDED. Re-arming on every cleanup call is a promise
	# the code cannot keep - the window never expires, `combo_index` keeps
	# climbing, and the cut a player makes after putting the sword away is the
	# fifth cut of a sentence they had already finished. §17 is about the window
	# being a WINDOW.
	if ended_a_chain_cut:
		chain_expires_at = _now() + moveset.combo_window
	elif buffer.pending != &"":
		chain_expires_at = _now() + moveset.combo_window
	# A follow-up window must not expire before the cut it belongs to has even
	# finished animating, or the player is punished for watching their own move.
	if pending_followup_id != &"":
		followup_until = maxf(followup_until, _now() + tuning.followup_grace)
	set_state(State.IDLE)
	var next := buffer.take(_now())
	if next != &"":
		_start(next)


func stow() -> void:
	# PUT THE SWORD AWAY. §5's unequip cleanup for this half of the weapon.
	#
	# The buffer goes FIRST, and that is the whole reason this is a function rather
	# than a bare `finish_action()` call. `finish_action()` ends by taking a buffered
	# input and starting it - so a player who presses light and then switches weapons in
	# the same breath would have a cut begin INSIDE the cleanup that was supposed to end
	# one, and that cut would then run on a body holding something else.
	#
	# The follow-up window goes with it: it is a promise the sword made about a cut that
	# is no longer in anyone's hands.
	buffer.clear()
	pending_followup_id = &""
	followup_until = 0.0
	# ...AND SO DOES THE COMBO MEMORY (§17). `combo_index` is how far through the
	# sentence the player was, and `chain_expires_at` is the promise to continue it
	# - both are about a sword that is no longer in the hand. Without this, `stow()`
	# would end the cut and then immediately re-open the grace window, so the first
	# cut after a weapon round trip would be A3 instead of A1 and the player would
	# be answering a question they had already dropped.
	combo_index = 0
	chain_expires_at = 0.0
	# `finish_action()` closes the hitbox, clears the active move and returns the state
	# to IDLE. What it cannot do is stop a NEW one starting, which is `_process`'s
	# `_holds_sword()` check - the two together are the whole of §5.
	finish_action()


func set_state(next: State) -> void:
	if state == next:
		return
	var previous := state
	state = next
	state_time = 0.0
	state_changed.emit(previous, next)


func _restart_state(next: State) -> void:
	# Cancelling one attack straight into the next one keeps the same State, so
	# set_state() would skip the reset and the new move would inherit the old
	# move's clock.
	set_state(next)
	state_time = 0.0


# -------------------------------------------------------------------- starts

func _start(action: StringName) -> bool:
	# THE BLADE HAS TO BE OUT (§19/§20).
	#
	# During a draw or a put-away the sword is somewhere between the player's hand
	# and their own scabbard, and a cut started here would be a swing with a
	# weapon that is half inside its sheath — and, on the way out, a swing at the
	# exact moment the rig is about to be hidden. The body is not locked: dodging,
	# blocking, casting and the chain all stay available, because none of them
	# needs the sword.
	if equip_blend < 1.0 and action in [&"light", &"heavy", &"iaido", &"ultimate"]:
		var manager := player.get_node_or_null("WeaponManager")
		if action != &"light" or manager == null or not manager.finish_draw_for_attack():
			return false
	match action:
		&"light":
			return _start_light()
		&"heavy":
			return _start_charge()
		&"block":
			set_state(State.BLOCK)
			return true
		&"dodge":
			return _start_dodge()
		&"cast":
			return _start_cast()
		&"iaido":
			return _start_signature()
		&"ultimate":
			return _start_ultimate()
		_:
			return false


func _start_light() -> bool:
	if not moveset.has_light_chain():
		return false
	var now := _now()
	var chain := moveset.light_chain
	var chosen := false
	if moveset.sprint_light_id != &"" and Input.is_action_pressed("sprint") and player.velocity.length() > 4.0:
		active_move_id = moveset.sprint_light_id
		combo_index = 0
		attack_kind = &"sprint"
		chosen = true
	elif moveset.retreat_light_id != &"" and _retreating():
		active_move_id = moveset.retreat_light_id
		combo_index = 0
		attack_kind = &"retreat"
		chosen = true
	if not chosen:
		# A chain continues while the previous light is still swinging (a cancel
		# into the next cut) or within the style's combo grace after it ended.
		if combo_index > 0 and (chain_active or now <= chain_expires_at):
			combo_index = (combo_index % chain.size()) + 1
		else:
			combo_index = 1
		active_move_id = chain[combo_index - 1]
		attack_kind = &"light"
	var move := moveset.get_move(active_move_id)
	if move == null:
		return false
	move_startup_scale = 1.0
	move_poise_scale = 1.0
	# Sheathed draw bonus: the 藏锋 rhythm pays off only if you actually waited.
	if moveset.sheath_enabled and combo_index == 1 and sheath_amount >= 0.82:
		move_startup_scale *= moveset.sheathed_startup_scale
		move_poise_scale *= moveset.sheathed_poise_scale
		style_message.emit("纳刀 · 拔刀强化")
	if edge_glint and move.id == moveset.guard.glint_move_id:
		edge_glint = false
		move_startup_scale *= moveset.guard.glint_startup_scale
		move_poise_scale *= moveset.guard.glint_poise_scale
	if enhance_left > 0.0:
		move_startup_scale *= enhance_startup_scale
		if combo_index == 1:
			move_poise_scale *= enhance_first_hit_poise_scale
	if next_move_startup_scale != 1.0:
		move_startup_scale *= next_move_startup_scale
		next_move_startup_scale = 1.0
	chain_expires_at = 0.0
	last_light_at = now
	_begin_move(move, State.ATTACK)
	return true


func _start_charge() -> bool:
	var move := moveset.get_move(moveset.heavy_id)
	if move == null:
		return false
	if move.id == &"uni_heavy":
		var entry := pose_snapshot()
		move.anchor = entry.position
		move.anchor_rot = entry.rotation
	active_move = move
	active_move_id = move.id
	attack_kind = &"heavy"
	move_hit = false
	charge_ratio = 0.0
	move_startup_override = -1.0
	move_startup_scale = 1.0
	move_poise_scale = 1.0
	idle_time = 0.0
	sheath_amount = 0.0
	chain_active = false
	_restart_state(State.CHARGE)
	return true


func release_heavy() -> void:
	if state != State.CHARGE or active_move == null:
		return
	var move := active_move
	var ratio := charge_ratio
	var charge_pose := pose_snapshot()
	# The wind-up already happened during CHARGE, so the strike is immediate.
	move_startup_override = 0.0
	if move.id == &"uni_heavy":
		# A quick tap finishes the small physical load; a held charge cuts now.
		move_startup_override = maxf(0.0,0.18-state_time)
		move.anchor = charge_pose.position
		move.anchor_rot = charge_pose.rotation
	move_startup_scale = 1.0
	move_poise_scale = 1.0
	move_hit = false
	followup_until = 0.0
	pending_followup_id = &""
	idle_time = 0.0
	sheath_amount = 0.0
	var damage_scale := 1.0
	if ratio > 0.08:
		var t := clampf((ratio - 0.08) / 0.92, 0.0, 1.0)
		move_poise_scale = lerpf(1.0, move.charged_poise_bonus, t)
		damage_scale = lerpf(1.0, move.charged_damage_bonus, t)
		camera_feedback.add_trauma(0.05 * t)
		camera_feedback.fov_kick(-1.2 * t)
	_write_hitbox(move, damage_scale)
	charge_ratio = ratio
	_restart_state(State.ATTACK)
	_swing_announced = false
	move_started.emit(move)


func _start_riposte() -> bool:
	var move := moveset.get_move(moveset.guard.riposte_id)
	if move == null:
		return false
	riposte_until = 0.0
	move_startup_scale = 1.0
	move_poise_scale = 1.0
	# 截锋 lit the edge: the answer out of a perfect guard is faster and heavier.
	if edge_glint and move.id == moveset.guard.glint_move_id:
		edge_glint = false
		move_startup_scale *= moveset.guard.glint_startup_scale
		move_poise_scale *= moveset.guard.glint_poise_scale
	attack_kind = &"riposte"
	_begin_move(move, State.RIPOSTE)
	return true


func _start_followup() -> bool:
	var follow := moveset.get_move(pending_followup_id)
	if follow == null:
		return false
	followup_until = 0.0
	pending_followup_id = &""
	move_startup_scale = 1.0
	move_poise_scale = 1.0
	buffer.clear()
	attack_kind = &"followup"
	_begin_move(follow, State.SKILL)
	return true


func _start_dodge() -> bool:
	var stamina: float = player.get("stamina")
	if not player.unlimited_resources and stamina < tuning.dodge_stamina_cost:
		return false
	if not player.unlimited_resources:
		player.set("stamina", stamina - tuning.dodge_stamina_cost)
	var input_vector := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var wish := Vector3(input_vector.x, 0, input_vector.y)
	dodge_direction = (player.transform.basis * (wish if wish.length_squared() > 0.01 else Vector3.FORWARD)).normalized()
	camera_feedback.fov_kick(10.0)
	var side := dodge_direction.dot(player.global_basis.x)
	camera_feedback.roll_impulse(side * 3.5)
	camera_feedback.add_impulse(Vector2(0.0, 0.025))
	dodge_audio.play()
	set_state(State.DODGE)
	return true


func _start_cast() -> bool:
	var school := current_school()
	var spell := current_spell()
	if spell == null or school == null:
		return false
	casting_spell = school.id
	spell_id = spell.id
	active_spell = spell
	var mana: float = player.get("mana")
	if not player.unlimited_resources and mana < spell.mana_cost:
		active_spell = null
		return false
	if not player.unlimited_resources:
		player.set("mana", mana - spell.mana_cost)
	camera_feedback.fov_kick(1.5 if spell.cast_mode == SpellDefinition.Cast.QUICK else 2.6)
	# Colour comes from the element definition, not from a ternary on a string.
	if school.element != null:
		magic_circle.circle_color = Color(
			school.element.tint.r, school.element.tint.g, school.element.tint.b, 0.85
		)
	_configure_spell_hitbox(spell)
	magic_circle.set_casting(true)
	set_state(State.CAST)
	return true


func _configure_spell_hitbox(spell: SpellDefinition) -> void:
	var target := _current_spell_hitbox()
	target.configure(spell.hitbox_size, spell.hitbox_offset)
	target.damage = spell.hitbox_damage
	target.poise_damage = spell.hitbox_poise
	target.impulse = spell.hitbox_impulse
	target.element = spell.element_id
	target.element_scale = spell.element_application_scale


func _spend_spell() -> void:
	# Called once per cast, when the active window opens, so a spell that leaves
	# something behind does it exactly once.
	var spell := active_spell if active_spell != null else current_spell()
	if spell == null:
		return
	if spell.infuses_blade:
		for school in schools.values():
			var element: ElementDefinition = (school as MagicSchool).element
			if element != null and element.id == spell.element_id:
				grant_infusion(element.id, element.infusion_duration)
				break
	if spell.field_radius > 0.0:
		_spawn_field(spell)
	if spell.id == &"wind_step":
		_spend_wind_step()
	if spell.element_id == ElementLibrary.WIND:
		wind_spread()
		# 风 × 链 (§24). Wind does not add damage to a chain — it adds SPIN, which
		# is the chain's own currency, so the most natural pairing in the whole
		# system is one line: ask the other weapon, if there is one, to speed up.
		# Asked here because this is the one place a wind spell actually resolves.
		var chain := player.get_node_or_null("ChainDirector")
		if chain != null:
			chain.call("apply_wind_boost")


# One place, so the chain's guard cannot be applied twice and cannot be skipped.
func _chain_deflect(hit: Dictionary) -> bool:
	var chain := player.get_node_or_null("ChainDirector")
	if chain == null:
		return false
	return bool(chain.call("try_deflect", hit))


func _spawn_field(spell: SpellDefinition) -> void:
	if active_field != null and is_instance_valid(active_field):
		active_field.queue_free()
	var field := ElementField.new()
	field.element_id = spell.element_id
	field.radius = spell.field_radius
	field.duration = spell.field_duration
	field.tick_interval = spell.field_tick_interval
	var element := ElementLibrary.get_element(spell.element_id)
	field.setup(element, player)
	field.position = Vector3(0.0, 0.0, -spell.field_offset)
	player.get_parent().add_child(field)
	field.global_position = player.global_position + (-player.global_transform.basis.z * spell.field_offset)
	active_field = field
	if element != null:
		style_message.emit("%s · 区域封锁" % spell.display_name)


func _start_signature() -> bool:
	# A SIGNATURE is style identity, not the ultimate slot. 聚合斩 is a ceremony
	# (a director takes over); 长风 is a short sequence the player keeps driving.
	if moveset.signature_id == &"":
		style_message.emit("此流派尚无 Signature")
		return false
	if _now() < iaido_ready_at:
		style_message.emit("Signature · 冷却中")
		return false
	if moveset.signature_id == &"iaido":
		return _start_iaido_ceremony()
	return _start_move_signature()


func _start_iaido_ceremony() -> bool:
	var now := _now()
	var stamina: float = player.get("stamina")
	if float(player.get("health")) <= 0.0 or iaido_director.active:
		return false
	if not is_instance_valid(player.get_node_or_null("CameraRig/LookPivot/MotionPivot/ShakePivot/WeaponRoot/TempSwordVisual")):
		return false
	if not player.unlimited_resources and stamina < 35.0:
		style_message.emit("聚合斩 · 体力不足")
		return false
	if not player.unlimited_resources:
		player.set("stamina", stamina - 35.0)
	# SIGNATURE technique: its own cooldown, and it never occupies Ultimate.
	iaido_ready_at = now + iaido_director.combat_tuning.restore_end + 2.0
	buffer.clear()
	set_state(State.IAIDO)
	iaido_director.start_iaido(true)
	# THE HAND-OFF HAS TO HAPPEN ON THIS FRAME AND NOT IN `_drive_saya`.
	#
	# `WorldPauseManager.acquire()` runs inside `start_iaido` and sets
	# `get_tree().paused`, and this controller is PAUSABLE (it never overrides
	# `process_mode`). So `_process` — and therefore `_drive_saya` — does not run
	# again until the blade is already home. A rule evaluated per frame would be
	# evaluated one frame too late, and the player would watch two scabbards for
	# the full eight seconds. That is not a hypothesis: it is what
	# `probe_saya_visibility.gd` recorded before this line existed.
	#
	# It re-arms itself for free. The ceremony's exit runs `finish_iaido` →
	# `_hard_reset` → `pause_manager.release`, and the next unpaused frame
	# evaluates the SAME rule with `active` already false — one judge, two
	# moments, and no second copy of the condition to keep in step.
	if saya_rig != null and is_instance_valid(saya_rig):
		saya_rig.visible = _saya_has_the_stage()
	return true


func _start_move_signature() -> bool:
	var move := moveset.get_move(moveset.signature_id)
	if move == null:
		return false
	if not _can_act_now():
		return false
	if state != State.IDLE:
		_close_hitbox()
	apply_player_aimed_mirror()
	iaido_ready_at = _now() + tuning.signature_cooldown
	active_skill = null
	move_startup_scale = 1.0
	move_poise_scale = 1.0
	attack_kind = &"signature"
	buffer.clear()
	_begin_move(move, State.SKILL)
	style_message.emit("%s · SIGNATURE" % move.display_name)
	return true


func apply_player_aimed_mirror() -> void:
	# Signature cuts the player aims: the side comes from the movement input at
	# the moment the cut starts, so the sequence is steered, never scripted.
	var wish := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	move_mirror = -1.0 if wish.x < -0.3 else 1.0


func _start_ultimate() -> bool:
	if ultimate_director == null or moveset.ultimate_id == &"":
		style_message.emit("此流派尚未习得 Ultimate")
		return false
	if not ultimate_director.has_method("start_moment"):
		return false
	if _now() < ultimate_ready_at:
		style_message.emit("无明一刻 · 冷却中")
		return false
	buffer.clear()
	active_move = null
	_close_hitbox()
	set_state(State.ULTIMATE)
	if not ultimate_director.call("start_moment"):
		set_state(State.IDLE)
		return false
	return true


func _begin_move(move: SwordMove, next_state: State) -> void:
	# Carry the actual preceding guard/idle/recovery into the next load.
	# Ordinary cuts stay drawn; only equip and Iaido use the scabbard bore.
	if move.id in SwordBasic.light_chain():
		var entry := pose_snapshot()
		move.anchor = entry.position
		move.anchor_rot = entry.rotation
	active_move = move
	active_move_id = move.id
	move_hit = false
	move_startup_override = -1.0
	idle_time = 0.0
	sheath_amount = 0.0
	followup_until = 0.0
	pending_followup_id = &""
	# A sequence the player drives (长风) opens its window immediately: whiffing
	# must not end the player's own combination. 燕返 still has to be earned.
	if move.followup_id != &"" and move.followup_from_start:
		pending_followup_id = move.followup_id
		followup_until = _now() + move.followup_window
	move_mirror = 1.0
	if move.player_aimed:
		apply_player_aimed_mirror()
	# Measure is sampled HERE, at the moment of commitment: walking forward during
	# the wind-up must not retrofit an ideal-measure reward onto a swing that was
	# started out of position.
	_apply_measure_scale(move)
	# Movement intent is sampled here for the same reason, and because the old
	# test at hit time was measuring the wrong thing entirely: `velocity > 3.0`
	# sampled a few hundred ms after the input is satisfied by the attack's OWN
	# lunge, so every lunging cut scored as a moving hit and 势 could not tell "I
	# ran into this" from "I stood still" — both phases of a side-by-side take
	# peaked at exactly the same value. Intent is also the honest measure of what
	# 回风's fantasy is about: the player choosing to move, not the animation
	# dragging them.
	commit_moving = _player_intends_to_move()
	chain_active = attack_kind in [&"light", &"sprint", &"retreat"]
	_write_hitbox(move, 1.0)
	hitbox.contact_filter = _accept_sword_contact
	# NOT here. The camera used to describe the swing at the moment the input was
	# received, which is the wind-up; it now belongs to `swing_started`, which is
	# the departure. Here we only arm the flag that lets it fire exactly once.
	_swing_announced = false
	# The reach runtime is re-armed per move, not per cut: A3 lands three times
	# inside one gesture and A4 sweeps six slices, and both mean "this body has
	# already been cut by this attack".
	_reach_fired.clear()
	_arc_slice = 0
	if reach != null:
		reach.begin_move(move)
	_restart_state(next_state)
	move_started.emit(move)


func _write_hitbox(move: SwordMove, damage_scale: float) -> void:
	var offset := Vector3(
		move.hitbox_offset.x * move_mirror,
		move.hitbox_offset.y,
		move.hitbox_offset.z - move_reach_bonus
	)
	hitbox.configure(move.hitbox_size, offset)
	hitbox.damage = move.damage * damage_scale
	hitbox.poise_damage = move.poise_damage * move_poise_scale
	# An infused blade carries its element into the cut, which is how a sword
	# interacts with a state the magic system created.
	hitbox.element = blade_element if is_infused() else move.element
	hitbox.hit_delay = 0.0


func _emit_move_camera(move: SwordMove) -> void:
	if move.camera_impulse != Vector2.ZERO:
		camera_feedback.add_impulse(move.camera_impulse)
	if move.camera_roll != 0.0:
		camera_feedback.roll_impulse(move.camera_roll)
	if move.fov_kick != 0.0:
		camera_feedback.fov_kick(move.fov_kick)
	if move.trauma > 0.0:
		camera_feedback.add_trauma(move.trauma)


# ------------------------------------------------------------------- skills

func trigger_skill(index: int) -> bool:
	if index < 0 or index >= moveset.skills.size():
		return false
	var skill: SwordSkill = moveset.skills[index]
	if _now() < float(skill_cooldowns.get(skill.id, 0.0)):
		style_message.emit("%s · 冷却中" % skill.display_name)
		return false
	var move := moveset.get_move(skill.move_id)
	if move == null:
		return false
	if not _can_act_now():
		return false
	if state != State.IDLE:
		_close_hitbox()
	# 折柳 opens its window the instant the skill starts: here the defence IS the
	# skill, so the window must not wait for the move to finish.
	if skill.kind == SwordSkill.Kind.SLIP:
		slip_skill = skill
		slip_until = _now() + skill.slip_window
	active_skill = skill
	move_startup_scale = 1.0
	move_poise_scale = 1.0
	if enhance_left > 0.0:
		move_startup_scale *= enhance_startup_scale
	attack_kind = &"skill"
	_begin_move(move, State.SKILL)
	skill_cooldowns[skill.id] = _now() + skill.cooldown
	style_message.emit(skill.display_name)
	return true


func _finish_skill() -> void:
	var skill := active_skill
	if skill == null:
		return
	if skill.kind == SwordSkill.Kind.ENHANCE:
		enhance_left = skill.enhance_duration
		enhance_startup_scale = skill.enhance_startup_scale
		enhance_perfect_guard_bonus = skill.enhance_perfect_guard_bonus
		enhance_first_hit_poise_scale = skill.enhance_first_hit_poise_scale
		enhance_skill_id = skill.id
		# 惊鸿 buys smoothness, not numbers.
		enhance_transition_bonus = skill.enhance_transition_bonus
		enhance_steer_bonus = skill.enhance_steer_bonus
		style_message.emit("%s · 生效" % skill.display_name)


func skill_cooldown_left(index: int) -> float:
	if index < 0 or index >= moveset.skills.size():
		return 0.0
	var skill: SwordSkill = moveset.skills[index]
	return maxf(0.0, float(skill_cooldowns.get(skill.id, 0.0)) - _now())


func reset_skill_cooldowns() -> void:
	skill_cooldowns.clear()
	iaido_ready_at = 0.0
	ultimate_ready_at = 0.0


func signature_cooldown_left() -> float:
	return maxf(0.0, iaido_ready_at - _now())


func ultimate_cooldown_left() -> float:
	return maxf(0.0, ultimate_ready_at - _now())


func notify_ultimate_finished() -> void:
	set_state(State.IDLE)


# -------------------------------------------------------------------- styles

func set_style(wanted: StringName, force: bool = false) -> bool:
	if movesets.is_empty():
		movesets = SwordMovesetLibrary.build_all()
	if not movesets.has(wanted):
		return false
	if not force and wanted == style_id:
		return false
	if not force and state != State.IDLE:
		style_message.emit("切换流派需要先站稳")
		return false
	moveset = movesets[wanted]
	style_id = moveset.style_id
	active_move = null
	active_move_id = &""
	combo_index = 0
	chain_expires_at = 0.0
	enhance_left = 0.0
	enhance_skill_id = &""
	enhance_transition_bonus = 0.0
	enhance_steer_bonus = 1.0
	slip_until = 0.0
	slip_skill = null
	move_mirror = 1.0
	move_reach_bonus = 0.0
	bind_until = 0.0
	sheath_waive_until = 0.0
	measure_range = -1.0
	measure_state = &""
	measure_ideal_count = 0
	edge_glint = false
	guard_recoil = 0.0
	parry_lateral = 0.0
	sheath_amount = 0.0
	idle_time = 0.0
	reset_flow()
	style_changed.emit(style_id)
	style_message.emit(moveset.display_name)
	return true


# ------------------------------------------------------------------ movement

func movement_scale() -> float:
	match state:
		State.IDLE:
			return 1.0
		State.ATTACK, State.RIPOSTE, State.SKILL:
			var steer := active_move.steer if active_move != null else 0.2
			# 顺势: at full Flow the sword stops dragging you out of your line.
			if moveset.flow_enabled:
				steer *= lerpf(1.0, moveset.flow_steer_bonus, flow_ratio())
			if enhance_left > 0.0:
				steer *= enhance_steer_bonus
			return steer
		State.CHARGE:
			return 0.22
		State.BLOCK:
			return moveset.guard.move_scale
		State.PARRY:
			return 0.12
		State.CAST:
			return 0.35
		State.STAGGER:
			return 0.10
		_:
			return 0.0


func attack_lunge_velocity() -> Vector3:
	# A sidestep in progress (perfect-guard steer, or a 折柳 slip) overrides the
	# move's own forward lunge: leaving the line is the point of both.
	if not is_zero_approx(parry_lateral) and state in [State.PARRY, State.SKILL, State.IDLE]:
		return player.global_transform.basis.x * parry_lateral * 4.0
	if active_move == null or is_zero_approx(active_move.lunge):
		return Vector3.ZERO
	if state not in [State.ATTACK, State.RIPOSTE, State.SKILL]:
		return Vector3.ZERO
	var duration := active_move.strike
	var base := 0.0 if move_startup_override >= 0.0 else effective_startup()
	var start := maxf(0.0, base - duration * active_move.lunge_lead)
	var end := start + duration * (1.0 + active_move.lunge_lead)
	if state_time < start or state_time >= end:
		return Vector3.ZERO
	var span := maxf(end - start, 0.0001)
	var u := (state_time - start) / span
	# sin() shape: peak speed mid-window, whole displacement == move.lunge.
	var amplitude := active_move.lunge * PI / (2.0 * span)
	var forward := -player.global_transform.basis.z
	return forward * signf(active_move.lunge) * amplitude * sin(u * PI)


func is_sheathed() -> bool:
	return moveset.sheath_enabled and sheath_amount >= 0.82


func dodge_speed_now() -> float:
	if state_time < 0.05:
		return 0.0
	if state_time < 0.12:
		return dodge_speed * smoothstep(0.05, 0.12, state_time)
	if state_time < 0.20:
		return dodge_speed
	var tail := clampf((state_time - 0.20) / 0.16, 0.0, 1.0)
	return dodge_speed * (1.0 - tail) * (1.0 - tail)


# How far the hands are displaced at a given point through the dodge, in units
# of "the offset a dodge asks for": +1 is fully dragged, 0 is home, and negative
# is the OVERSHOOT past rest when the body slows down under the blade.
#
# Authored as three beats rather than a curve fitted to a shape, because the
# three are three different things the player has to be able to see: the leave,
# the catch-up past rest, and the settle. Collapsing them into one ease would
# put the peak somewhere in the middle and lose the arrival entirely — which is
# what the old one-offset pose did.
func _dodge_pose_k(u: float) -> float:
	if u < 0.18:
		# LEAVE. The body has gone and the hands have not.
		return SwordPoseSampler.ease_out(u / 0.18, 2.0)
	if u < 0.62:
		# CATCH UP, and past: the body is slowing and the blade keeps going,
		# which is the only reason a stop reads as a stop rather than a pause.
		return 1.0 - 1.35 * SwordPoseSampler.ease_in((u - 0.18) / 0.44, 2.0)
	# SETTLE, finished before the state does, so the last frames are usable.
	return -0.35 + 0.35 * SwordPoseSampler.ease_out((u - 0.62) / 0.38, 2.0)


# ---------------------------------------------------------------------- pose

func effective_startup() -> float:
	if active_move == null:
		return 0.0
	if move_startup_override >= 0.0:
		return move_startup_override
	return active_move.startup * move_startup_scale


func recovery_scale() -> float:
	if active_move == null:
		return 1.0
	var scale := active_move.recovery_scale
	if move_hit:
		scale *= active_move.hit_recovery_scale
		if moveset.flow_on_hit_recovery < 1.0:
			scale *= moveset.flow_on_hit_recovery
		# 势 only pays out on connected cuts. A whiff must stay slow, or the
		# style stops punishing the thing it is built to punish.
		if moveset.flow_enabled:
			scale *= lerpf(1.0, moveset.flow_recovery_at_max, flow_ratio())
	else:
		scale *= active_move.miss_recovery_scale
	if scale < 1.0:
		var floor_scale := moveset.flow_min_recovery / maxf(active_move.recovery, 0.001)
		scale = maxf(scale, floor_scale)
	return scale


func _move_end_time() -> float:
	if active_move == null:
		return 0.0
	return effective_startup() + active_move.strike + active_move.pose_span() * recovery_scale()


func pose_snapshot() -> Dictionary:
	var position := moveset.idle_pose
	var rotation := moveset.idle_pose_rot
	var intensity := 0.0
	var stiffness := moveset.pose_stiffness
	match state:
		State.ATTACK, State.RIPOSTE, State.SKILL:
			if active_move != null:
				var sampled := SwordPoseSampler.sample(active_move, authored_move_time(), recovery_scale())
				position = sampled.position
				rotation = sampled.rotation
				intensity = sampled.intensity
		State.CHARGE:
			if active_move != null:
				# The anticipation is stretched across the whole charge.
				var load_time := 0.18 if active_move.id == &"uni_heavy" else maxf(tuning.heavy_charge_time,0.05)
				var t := minf(state_time/load_time,1.0)*active_move.startup*0.985
				var sampled := SwordPoseSampler.sample(active_move, t)
				position = sampled.position
				rotation = sampled.rotation
				intensity = 0.35 + charge_ratio * 0.4
				stiffness = moveset.pose_stiffness * 1.15
		State.BLOCK:
			position = moveset.guard.pose
			rotation = moveset.guard.pose_rot
			if guard_recoil > 0.0:
				var k := clampf(guard_recoil, 0.0, 1.0)
				position = position.lerp(moveset.guard.parry_pose, k)
				rotation = SwordPoseSampler.arc(rotation, moveset.guard.parry_pose_rot, k)
			intensity = 0.2
		State.PARRY:
			var guard := moveset.guard
			var u := clampf(state_time / maxf(guard.parry_duration, 0.01), 0.0, 1.0)
			if u < 0.35:
				var k := SwordPoseSampler.ease_in(u / 0.35, 1.6)
				position = guard.pose.lerp(guard.parry_pose, k)
				rotation = SwordPoseSampler.arc(guard.pose_rot, guard.parry_pose_rot, k)
			else:
				var k := SwordPoseSampler.ease_out((u - 0.35) / 0.65, 2.0)
				position = guard.parry_pose.lerp(moveset.idle_pose, k)
				rotation = SwordPoseSampler.arc(guard.parry_pose_rot, moveset.idle_pose_rot, k)
			intensity = 0.6
		State.DODGE:
			# A dodge is a RELOCATION, and it is the one act in the game that
			# moves the player a couple of metres in a third of a second. It has
			# to be possible to see that happen.
			#
			# This used to be one offset held for the whole state: the hands went
			# out on the fourth frame and stayed out until the dodge ended, then
			# came home. Measured, that reads `=*#%%%%%%%%%%%%%%%%%%` — a step,
			# not a move. There is no arrival in it, and without an arrival a
			# dodge is a teleport with a duration attached.
			#
			# So the hands are driven through three beats over the dodge's own
			# length: they are LEFT BEHIND as the body goes (which is the only
			# thing in first person that says *I* moved rather than the world
			# moving), they then OVERSHOOT past rest as the body slows — the
			# overshoot is what makes a stop read as a stop — and they are HOME
			# before the state ends, so the player can act out of the last frames
			# instead of waiting for the pose to snap back.
			var side := dodge_direction.dot(player.global_basis.x)
			var u := clampf(state_time / maxf(tuning.dodge_duration, 0.0001), 0.0, 1.0)
			var k := _dodge_pose_k(u)
			# Dragged BACK and against the direction of travel: -side is out to
			# the trailing side, +z is toward the player, and the hands also dip
			# because the body dropped into the step.
			position = moveset.idle_pose + Vector3(-side * 0.16, -0.12, 0.10) * k
			rotation = moveset.idle_pose_rot + Vector3(-0.2, 0.0, -side * 0.28) * k
			# The tremor belongs to the exertion, so it rides the displacement
			# rather than sitting at a constant hum for the whole state.
			intensity = 0.10 + 0.28 * absf(k)
		State.STAGGER:
			position = moveset.idle_pose + Vector3(0.0, -0.16, 0.10)
			rotation = moveset.idle_pose_rot + Vector3(0.30, 0.0, 0.0)
			intensity = 0.15
		State.CAST:
			position = moveset.idle_pose + Vector3(-0.04, -0.05, -0.06)
			intensity = 0.25
		_:
			pass
	# THE DRAW (§19/§20). A blade that is not yet home in the hand is not a
	# special case in the renderer: it is the same pose pipeline, blended out of
	# the five beats. At `equip_blend = 0` the sword is exactly at
	# `SwordBasic.saya_home()` with the saya's own axis, which is the pose the
	# scabbard is seated from — so "the blade is in the sheath" is true because
	# two systems agree about one number, not because two pictures look similar.
	#
	# =========================================================================
	# AND THE HANDOVER IS BEAT 5's, NOT THE WHOLE DRAW'S
	# =========================================================================
	#
	# The cross-fade into the style's idle pose used to be weighted by
	# `equip_blend` outright, across all 1.75 seconds of the draw. That is the
	# right shape for a four-key chord — where every intermediate position IS a
	# straight line between "sheathed" and "idle" — and it is wrong for a
	# sentence, because a cross-fade renders a pose that is PARTLY the idle:
	#
	#     blend 0.54 (the pause)  ->  54% of the idle pose in the blade
	#     blend 0.61 (the glint)  ->  61%
	#
	# `tools/probe_draw_seating.gd` measured what that costs. The blade's distance
	# from the scabbard's own BORE LINE — the one constraint a draw has, because
	# the blade is inside a tube whose designed clearance is
	# `SwordClasses.FIT_CLEAR` = 1.75 mm — was **0.927 m** at the worst instant,
	# with an axis error of **89.5 degrees**. Every one of the five beats was
	# being rendered as a blade half-way to somewhere else, and the saya, which is
	# driven from its beats directly and is therefore exact, held still and
	# watched it happen.
	#
	# So the handover is a RAMP THAT STARTS WHEN THE BLADE IS OUT:
	# `smoothstep(NE_BLADE_CLEAR, 1.0, blend)` is 0 for the whole of segments 1-5
	# and reaches 1 exactly at the end, where the pose has to be the idle one
	# because the draw is over. It is continuous at both ends by construction, so
	# nothing about the arrival changes; what changes is that Beats 1-4 are now on
	# screen as authored.
	if equip_blend < 0.999 and state in [State.IDLE, State.STAGGER]:
		var equip := _equip_move
		var drawn := SwordPoseSampler.sample(equip, equip_blend * equip.total_time())
		var handover := smoothstep(SwordBasic.NE_BLADE_CLEAR, 1.0, equip_blend)
		position = (drawn.position as Vector3).lerp(position, handover)
		# ...AND THE HANDOVER IS A ROTATION BLEND LIKE EVERY OTHER ONE.
		# See `SwordPoseSampler.arc`. The §18 fault is a property of the OPERATION, so
		# a handover that lerps three angles while the sampler it is handing over
		# FROM slerps rotations would put the discontinuity back at the seam.
		rotation = SwordPoseSampler.arc(drawn.rotation as Vector3, rotation, handover)
		intensity = maxf(intensity, float(drawn.intensity))
	# A player-aimed cut is the same authored pose taken from the other side,
	# because the player chose the side. Mirroring keeps one authored move able
	# to answer "he is on my left" without a second animation.
	if move_mirror < 0.0 and state in [State.ATTACK, State.RIPOSTE, State.SKILL]:
		position.x = -position.x
		rotation.y = -rotation.y
		rotation.z = -rotation.z
	# 归鞘 is a pose, not an effect on top: the whole weapon travels to the hip
	# so the next draw reads as an actual draw.
	if moveset.sheath_enabled and sheath_amount > 0.0 and state in [State.IDLE, State.STAGGER]:
		var s := SwordPoseSampler.ease_out(sheath_amount, 1.5)
		position = position.lerp(moveset.sheath_pose, s)
		rotation = SwordPoseSampler.arc(rotation, moveset.sheath_pose_rot, s)
	if inspect_mix > 0.0 and state == State.IDLE:
		position = position.lerp(Vector3(0.18, -0.36, -0.78), inspect_mix)
		rotation = SwordPoseSampler.arc(rotation, Vector3(0.20, -0.32, -0.70), inspect_mix)
	if Input.is_action_pressed("sprint") and player.velocity.length() > 2.0 and state == State.IDLE:
		position.y -= 0.13
		rotation.z -= 0.12
	else:
		# Look-lag keeps the weapon attached to a body, not bolted to the camera.
		position.x -= camera_feedback.look_lag.x * 0.30
		position.y += camera_feedback.look_lag.y * 0.22
	return {
		"position": position,
		"rotation": rotation,
		"stiffness": stiffness,
		"damping": moveset.pose_damping,
		"tremor": moveset.tremor,
		"intensity": intensity,
		# The ribbon's width is a property of the BEAT, not of the style (§24): A1
		# is the thinnest line in the sentence and A4's sweep is the widest, and a
		# style-wide number could never tell them apart because 回风 and 一文字
		# both run this same Universal layer.
		"trail_width": moveset.trail_width * (active_move.trail_width_scale if active_move != null else 1.0),
		"sheath": sheath_amount,
		"style": style_id,
		"move_id": active_move_id,
	}


# ===========================================================================
# The presentation clock (§23)
# ===========================================================================

## Which move's events are running right now, and where in it they are — or an
## empty answer when nothing is being presented.
##
## ONE FUNCTION, NOT TWO GETTERS. If a listener could ask "which move" and "how
## far in" separately it could pair A1's clock with the draw's move, and the
## failure would be three sounds arriving in the wrong order during a weapon
## switch. The two answers travel together so that cannot be expressed.
##
## The clock is the move's OWN (`raw_time_at`), because the events, the trace
## marks and the domain window are all authored in raw move seconds and a draw
## bonus must not bend them.
func authored_move_time() -> float:
	if active_move == null: return 0.0
	if move_startup_override >= 0.0:
		if state_time < move_startup_override:
			return active_move.startup*state_time/maxf(move_startup_override,0.001)
		return active_move.startup+maxf(0.0,state_time-move_startup_override)
	return active_move.raw_time_at(state_time,move_startup_scale)

func presentation_clock() -> Dictionary:
	if not _holds_sword():
		return {}
	if active_move != null and state in [State.ATTACK, State.RIPOSTE, State.SKILL]:
		return {
			"move": active_move,
			"time": authored_move_time(),
			"scale": move_startup_scale,
		}
	if equip_blend < 0.999 and state in [State.IDLE, State.STAGGER]:
		var equip := _equip_move
		var manager := player.get_node_or_null("WeaponManager")
		return {"move": equip, "time": equip_blend * equip.total_time(), "scale": 1.0, "reverse":manager != null and manager._pending_slot != &""}
	return {}


## Moves `equip_blend` toward its target over `seconds`. The WeaponManager owns
## when; this owns that it is a smooth pose rather than a switch.
func advance_draw(delta: float, seconds: float) -> void:
	if seconds <= 0.0:
		equip_blend = 1.0
		return
	equip_blend = clampf(equip_blend + delta / seconds, 0.0, 1.0)


func advance_sheathe(delta: float, seconds: float) -> void:
	if seconds <= 0.0:
		equip_blend = 0.0
		return
	equip_blend = clampf(equip_blend - delta / seconds, 0.0, 1.0)


## True once the blade is out of the saya and in the hand.
##
## NOT a rename of `is_sheathed()`: that one reports 藏锋's 归鞘 pose, which is a
## style mechanic about where the blade is resting during an idle. This one
## reports the equip sequence, i.e. whether the sword has been DRAWN at all. Two
## different questions with one honest answer each, and merging them would make
## 藏锋's sheathed idle look like a weapon that was never equipped.
func is_drawn() -> bool:
	return equip_blend >= 0.5


# ----------------------------------------------------------------- enemy hit

func _accept_sword_contact(hit: Dictionary) -> bool:
	var contact_move: SwordMove = hit.get("sword_move", active_move)
	if contact_move == null:
		return false
	var target := hit.get("target") as Node3D
	if contact_move.reach_mode == &"wave" and not hit.get("sword_contact_accepted", false) and reach != null and reach.claim(target):
		return false
	hit["sword_contact_accepted"] = true
	hit["sword_move"] = contact_move
	var direction: Vector3 = hit.get("slash_direction", Vector3.ZERO)
	if direction.is_zero_approx():
		direction = player.global_basis.x
		if contact_move.id == SwordBasic.A2:
			direction = (-direction + Vector3.UP * 0.45).normalized()
		elif contact_move.id == SwordBasic.A3:
			direction = (Vector3.UP - player.global_basis.z * 0.30).normalized()
		elif contact_move.reach_mode == &"arc" and target != null:
			var radial := target.global_position - player.global_position
			direction = Vector3(-radial.z, 0.0, radial.x).normalized()
	hit["slash_direction"] = direction
	hit["move_id"] = contact_move.id
	hit["finisher"] = contact_move.id == SwordBasic.A4
	hit["rising_cut"] = contact_move.id == SwordBasic.A3
	if contact_move.interrupt_bonus > 1.0 and target != null and target.has_method("is_telegraphing") and target.call("is_telegraphing"):
		hit["damage"] = float(hit.get("damage", 0.0)) * contact_move.interrupt_bonus
		hit["poise_damage"] = float(hit.get("poise_damage", 0.0)) * contact_move.interrupt_bonus
		hit["interrupt"] = true
	if contact_move.frozen_bonus != 1.0:
		hit["frozen_bonus"] = contact_move.frozen_bonus
	return true


func _on_hitbox_landed(hit: Dictionary) -> void:
	var landed_move: SwordMove = hit.get("sword_move", active_move)
	if landed_move == null:
		return
	# §5: A BODY IS CUT ONCE PER MOVE, WHICHEVER MECHANISM GOT THERE FIRST. A2 is
	# the ONLY beat whose two mechanisms overlap in space — a body hitbox that
	# reaches 2.1m and a wave released from the eye — and a body inside blade reach
	# would be cut by the blade AND by the wave, doubling the second beat for
	# standing close and only for standing close.
	#
	# SCOPED TO THE WAVE ON PURPOSE, and that scope is load-bearing rather than
	# tidy. `_on_hitbox_landed` is the single landing path, so an un-scoped gate
	# here is a gate on EVERY hit in the game: the first version of this refused
	# the second and later synthetic contacts of one move, which read downstream as
	# a heavy with no hitstop, a shattered body with no silence, and every
	# follow-up style "never connecting". A dedup that fixes one double-cut by
	# eating every second hit is not a fix.
	if (
		reach != null
		and landed_move.reach_mode == &"wave"
		and not hit.get("sword_contact_accepted", false)
		and hit.get("reach_mode", &"") == &""
		and reach.claim(hit.get("target") as Node3D)
	):
		return
	if landed_move == active_move:
		move_hit = true
	hits_landed += 1
	# 势: connecting is what keeps the style alive, and connecting *while moving*
	# feeds it faster. That is the loop 回风 asks the player to chase.
	if moveset.flow_enabled:
		var on_the_move := attack_kind in [&"sprint", &"retreat"] or commit_moving
		_gain_flow(moveset.flow_gain_movement_hit if on_the_move else moveset.flow_gain_hit)
	var target = hit.get("target")
	hit_landed.emit(landed_move, hit)
	# ASKED AFTER THE BODY HAS ANSWERED, not before: the target decides what it
	# became while `hit_landed` was being delivered, so the outcome is only
	# readable once the blow has actually landed on something capable of opinion.
	var outcome := &""
	if target != null and target.has_method("take_hit_outcome"):
		outcome = target.call("take_hit_outcome")
	# Four answers, one place each, and only ONE of them gets to fire — see §28.
	# Every branch sets what is DIFFERENT about this hit; what a hit does in
	# common is below, once, so adding a fifth answer can never accidentally
	# double the shake the way bolting another `add_trauma` on top would.
	var stop := landed_move.hitstop
	var extra_trauma := 0.0
	var flash := 0.09
	# 断章: only meaningful against an enemy that was mid-action.
	if landed_move.interrupt_bonus > 1.0 and target != null and target.has_method("is_telegraphing") and target.call("is_telegraphing"):
		stop = 0.075
		flash = 0.16
		style_message.emit("断章 · INTERRUPT")
	elif outcome == &"shatter":
		# Not a bigger hit — a STATE ending. Longest stop in the game, and more
		# weight in the hands, because this is the one result the player built
		# deliberately (freeze first) rather than got for swinging hard.
		stop = tuning.shatter_hitstop
		flash = 0.20
		extra_trauma = 0.22
		style_message.emit("碎 · SHATTER")
	else:
		if landed_move.frozen_bonus != 1.0:
			hit["frozen_bonus"] = landed_move.frozen_bonus
	last_hit_strength = clampf(float(hit.get("damage", 0.0)) / 40.0, 0.2, 1.6)
	var frame := Engine.get_process_frames()
	if _impact_frame != frame:
		_impact_frame = frame
		if hitstop_scale > 0.0 and stop > 0.0:
			time_effects.request_hitstop(stop * hitstop_scale)
		if landed_move.reach_mode != &"trace":
			var camera_gain := float(SwordBasic.CONFIG.get("camera_strength"))
			camera_feedback.contact_position_impulse((0.006 if landed_move.reach_mode == &"body" else 0.010) * camera_gain)
			camera_feedback.add_impulse((landed_move.camera_impulse * 1.7 + Vector2(0.0, 0.004)) * camera_gain)
		if extra_trauma > 0.0:
			camera_feedback.add_trauma(extra_trauma)
		screen_fx.flash_hit(flash * hitstop_scale if hitstop_scale > 0.0 else flash * 0.5)
	if landed_move.on_hit_next_startup_scale != 1.0:
		next_move_startup_scale = landed_move.on_hit_next_startup_scale
	if landed_move.followup_id != &"":
		pending_followup_id = landed_move.followup_id
		followup_until = _now() + landed_move.followup_window


func _on_player_hit(hit: Dictionary) -> void:
	# THE CHAIN'S GUARD IS ASKED FIRST, because it does not work like a guard: it
	# disturbs the attack before the body ever meets it, so it has to be offered
	# the hit rather than applied after one. This is also the single place the
	# player's hurtbox is read — a second handler would mean two systems both
	# reacting to one hit, and one of them would always be wrong.
	if _chain_deflect(hit):
		return
	# 折柳: the attack is allowed to pass by. Deliberately checked before dodge
	# and before guard — declining the exchange is the fastest answer available,
	# and it is the exact opposite of what Perfect Guard does.
	if _slip_open():
		_resolve_slip(hit)
		return
	if state == State.DODGE and state_time < tuning.dodge_iframes:
		# The hit went through the space the player had just been standing in.
		# That is an EVENT, and an event with no answer did not happen: without
		# one the player cannot tell a successful evade from a whiff, so the
		# dodge stops being something they aimed and becomes a button they
		# press. §30 says a miss has to read as a miss — the mirror of that is
		# that an evade has to read as an evade.
		#
		# Deliberately SHORTER than any hit that connects: this is a near miss,
		# not a blow, and giving it a hit's worth of stop would make getting out
		# of the way feel heavier than getting hit.
		dodge_evaded.emit()
		if hitstop_scale > 0.0:
			time_effects.request_hitstop(tuning.evade_hitstop * hitstop_scale)
		camera_feedback.add_trauma(0.14)
		camera_feedback.add_impulse(Vector2(0.0, -0.03))
		dodges_landed += 1
		return
	if state in [State.BLOCK, State.PARRY]:
		var guard := moveset.guard
		var heavy := float(hit.get("poise_damage", 0.0)) >= 35.0
		var window := guard.perfect_guard_window
		if enhance_left > 0.0:
			window += enhance_perfect_guard_bonus
		if state == State.BLOCK and state_time <= window:
			_perfect_guard(hit)
			return
		var stamina: float = player.get("stamina")
		var cost := guard.stamina_per_hit * (guard.heavy_stamina_multiplier if heavy else 1.0)
		if not player.unlimited_resources:
			player.set("stamina", maxf(0.0, stamina - cost))
		var block_scale := 1.0 + (0.9 if heavy else 0.0)
		guard_recoil = minf(1.0, guard_recoil + 0.55 * block_scale)
		camera_feedback.add_trauma(0.10 * block_scale)
		camera_feedback.add_impulse(Vector2(-0.012, -0.010) * block_scale)
		# §28: absorbing has always been the missing fourth answer. A heavy
		# squashing the guard and a light brushing it produced the same moment,
		# because the only difference between them was a number in a stamina bar
		# nobody was looking at during the hit.
		var stop := guard.heavy_block_hitstop if heavy else guard.block_hitstop
		if stop > 0.0 and hitstop_scale > 0.0:
			time_effects.request_hitstop(stop * hitstop_scale)
		return
	var damage := float(hit.get("damage", 0.0))
	var health: float = player.get("health")
	player.set("health", maxf(0.0, health - damage))
	camera_feedback.add_trauma(0.12)
	camera_feedback.add_impulse(Vector2(0.01, -0.016))
	if damage >= tuning.player_stagger_threshold and state not in [State.IAIDO, State.ULTIMATE]:
		# You cannot spam through an enemy heavy: this is what makes Guard a
		# decision instead of decoration.
		_close_hitbox()
		active_move = null
		buffer.clear()
		set_state(State.STAGGER)
		get_tree().create_timer(0.26).timeout.connect(func() -> void:
			if is_instance_valid(self) and state == State.STAGGER:
				set_state(State.IDLE)
		)


func _slip_open() -> bool:
	return _now() < slip_until


func _resolve_slip(hit: Dictionary) -> void:
	var skill := slip_skill
	slip_until = 0.0
	slip_skill = null
	slip_count += 1
	var counter_window := 0.9
	var distance := 1.7
	var flow_gain := 0.0
	if skill != null:
		counter_window = skill.slip_counter_window
		distance = skill.slip_distance
		flow_gain = skill.slip_flow_gain
	if flow_gain > 0.0:
		_gain_flow(flow_gain)
	# Step off the line. The player's own input decides the side; failing that,
	# slip away from whoever swung, which is always the correct answer.
	var wish := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var side := 0.0
	if absf(wish.x) > 0.1:
		side = signf(wish.x)
	else:
		var attacker: Node = hit.get("source")
		if attacker is Node3D:
			var away: Vector3 = player.global_position - (attacker as Node3D).global_position
			side = signf(away.dot(player.global_basis.x))
		if is_zero_approx(side):
			side = 1.0
	parry_lateral = side * distance
	get_tree().create_timer(0.30).timeout.connect(func() -> void:
		if is_instance_valid(self):
			parry_lateral = 0.0
	)
	camera_feedback.roll_impulse(side * 4.0)
	camera_feedback.add_impulse(Vector2(side * 0.010, 0.004))
	camera_feedback.fov_kick(2.4)
	# The opening the slip left behind is the whole reward.
	riposte_until = _now() + counter_window
	style_message.emit("折柳 · 落空")


func _perfect_guard(hit: Dictionary) -> void:
	var guard := moveset.guard
	perfect_guard_count += 1
	# A clean deflect is the strongest single source of 势: reading the attack
	# should feel like the most "in the flow" answer available.
	if moveset.flow_enabled:
		_gain_flow(moveset.flow_gain_deflect)
	_close_hitbox()
	var attacker: Node = hit.get("source")
	if attacker != null and attacker.has_method("on_perfect_guard"):
		attacker.call("on_perfect_guard")
	if hitstop_scale > 0.0:
		time_effects.request_hitstop(guard.perfect_guard_hitstop * hitstop_scale)
	camera_feedback.add_impulse(guard.perfect_guard_impulse)
	camera_feedback.add_trauma(minf(guard.perfect_guard_trauma,0.05))
	camera_feedback.fov_kick(-2.0)
	screen_fx.flash_hit(0.18)
	guard_recoil = 1.0
	edge_glint = true
	riposte_until = _now() + guard.riposte_window
	if guard.parry_sheath_waiver > 0.0:
		sheath_waive_until = _now() + guard.parry_sheath_waiver
	if guard.bind_enabled:
		# 合围: nothing is flung away and the player does not leave the line. The
		# blade is trapped; the next 0.3s belong to whoever decides fastest.
		bind_until = _now() + maxf(guard.bind_deck_window, guard.riposte_window)
	else:
		bind_until = 0.0
		if guard.parry_steer > 0.0:
			var side := 1.0 if not Input.is_action_pressed("move_left") else -1.0
			parry_lateral = side * guard.parry_steer
			get_tree().create_timer(guard.parry_duration + 0.12).timeout.connect(func() -> void:
				if is_instance_valid(self):
					parry_lateral = 0.0
			)
	set_state(State.PARRY)
	state_time = 0.0
	perfect_guard_landed.emit()
	style_message.emit(guard.bind_message if guard.bind_enabled else "截锋 · RIPOSTE 窗口")


# -------------------------------------------------------------------- helpers

func _close_hitbox() -> void:
	hitbox.set_active(false)
	hitbox.hit_delay = 0.0
	frost_hitbox.set_active(false)
	fire_hitbox.set_active(false)
	wind_hitbox.set_active(false)
	hitbox_open = false


func _riposte_open(now: float) -> bool:
	return now < riposte_until and state in [State.IDLE, State.PARRY]


func _followup_open(now: float) -> bool:
	return now < followup_until and pending_followup_id != &""


func _retreating() -> bool:
	var input_vector := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	return input_vector.y > 0.4


func _current_ability() -> AbilityData:
	# During a cast the snapshot wins, so changing the wheel mid-cast cannot
	# swap the spell's timings out from under it.
	if state == State.CAST and active_spell != null:
		return active_spell
	var spell := current_spell()
	if spell != null:
		return spell
	# Fallback to the original resources if the school table is ever empty.
	match casting_spell:
		&"fire": return fire_ability
		&"wind": return wind_ability
		_: return frost_ability


func _current_spell_hitbox() -> CombatHitbox:
	match casting_spell:
		&"fire": return fire_hitbox
		&"wind": return wind_hitbox
		_: return frost_hitbox


func _now() -> float:
	return combat_time


func debug_state_line() -> String:
	var move_name := active_move.display_name if active_move != null else "-"
	var flow_text := " · 势=%.0f%%" % (flow_ratio() * 100.0) if moveset.flow_enabled else ""
	var measure_text := ""
	if moveset.measure_enabled:
		var label := measure_state
		if label == &"":
			label = &"-"
		measure_text = " · 距离=%.2fm/%s" % [measure_range, label]
	var bind_text := " · BIND" if _bind_open(_now()) else ""
	return "%s · %s · %.2fs · glint=%s · sheathed=%.2f · chain=%d%s%s%s" % [
		moveset.display_name, move_name, state_time, str(edge_glint), sheath_amount,
		combo_index, flow_text, measure_text, bind_text,
	]


func cycle_hitstop_preset() -> String:
	var presets := [0.0, 1.0, 1.8]
	var index := presets.find(hitstop_scale)
	hitstop_scale = presets[(index + 1) % presets.size()] if index >= 0 else 1.0
	if hitstop_scale <= 0.0:
		return "Off"
	if hitstop_scale > 1.4:
		return "Exaggerated"
	return "Normal"


func _exit_tree() -> void:
	time_effects.reset()
