extends Node
# THE WEAPON MANAGER. What the player is holding, and the hand that changes it.
#
# WHAT IT IS NOT. It does not decide what the sword or the chain DO, and neither
# weapon knows it exists. `WeaponSlot` is still the single source of truth for "what
# is in my hands" - one node, on the Player - and this node is its only runtime
# writer. Everything downstream already reads that slot (CombatController gates on
# it, ChainDirector gates on it, the HUD reports it), so a switch needs no second
# arbitration layer and no `if weapon ==` anywhere.
#
# WHY IT IS A SYSTEM AND NOT TWO `if key == 1` LINES IN THE PLAYER. The naive version
# of this feature changes the slot and NOTHING ELSE, and it fails in a way that is
# invisible until you look at the right frame: a chain that was mid-throw keeps
# flying while a sword swings underneath it, or a sword that was mid-arc re-opens its
# hitbox after the hand has moved on. §5 is the list - disable hitboxes, stop the
# action, clear the attack state, clear the temporary target, clear the visual state,
# hide the weapon - and a list that long is a system, not a line in an input handler.
#
# THE SWITCH IS SHORT ON PURPOSE (§6). Cleanup is instant, the slot changes, and the
# incoming weapon rises into the frame over 0.18s. There is no transition animation
# and there is deliberately no attempt at one: this build exists so a playtest can
# answer whether the WEAPONS are right, and a longer flourish would only be a second
# thing to look at.
#
# KEYS (§1 / INPUT CONTRACT). 1 sword, 2 phantom chain, 3 mirror = DEVELOPMENT
# QUICK SWITCH. Tab Hold = Combat UI, Shift = Dodge→Sprint — owned by InputContract.
# Mirror skills: E place / X travel.
#
# THE DEV INDICATOR (§8). One dim line in the bottom right naming the two keys, and a
# 0.9s name flash on the switch so the hand-off is legible without reading anything.
# F7 makes the whole thing disappear, and nothing here prints numbers: §16's playtest
# mode is closer to shipping than to a debug overlay, so RADIUS / STATE / TENSION stay
# behind F8 where they already live.

signal weapon_switched(previous: StringName, current: StringName)
signal sword_sheathe_started()
signal sword_seated()

## The registry. A third weapon is a row here plus that weapon's own nodes - there is
## no other place that knows how many weapons exist.
const WEAPONS := [
	{"id": &"sword", "key": KEY_1, "label": "剑 Sword", "flash": "剑 · SWORD"},
	{"id": &"phantom_chain", "key": KEY_2, "label": "虚链 Phantom", "flash": "虚链 · PHANTOM CHAIN"},
	{"id": &"mirror", "key": KEY_3, "label": "镜 Mirror", "flash": "镜 · MIRROR"},
]

## Star-Bind Chain stays equippable for labs / racks / movie tools, but it is NOT
## a hotkey. Key 2 is Phantom Chain (虚链). Do not put CHAIN back on KEY_2.
const ALSO_EQUIPPABLE := [&"chain"]

## §6 allows 0.15-0.30s. This is the whole transition for a weapon that arrives
## with nothing to do: a raise, nothing else.
const SWITCH_SECONDS := 0.18
## THE SWORD IS THE EXCEPTION, and §19/§20 are why. A sword does not arrive, it
## is TAKEN OUT OF SOMETHING. SWORD PRESENTATION V3 makes that five beats rather
## than four keys — carry, partial draw, hold, cold glint, seat — so this is the
## length of `SwordBasic.equip()`, and it replaces the raise rather than sitting
## on top of it: a raise under a draw would be the hand doing two things at once.
##
## MUST EQUAL `SwordBasic.NE_TOTAL`, and the reason it is a copy rather than a
## call is that a `const` cannot read a function. `SwordHoldController` and the
## tests both derive theirs from the move; if you retune the beats, this is the
## one number that has to be moved by hand, and `tools/probe_draw_beats.gd`
## asserts the two agree so that forgetting it is a FAIL and not a short draw.
const DRAW_SECONDS := 1.75
## §2's shared contract: the sheathe is the same sentence read backwards, so it
## costs the same. It was 0.55 s when a draw was 0.62 s and the two were
## unrelated numbers; they are one number now, and §7-§10's reworked recovery is
## what that number contains.
const SHEATHE_SECONDS := 1.75
const SWORD_CONFIG = preload("res://resources/tuning/SwordConfig.tres")
## How far below its home pose the incoming weapon starts. Deep enough to be out of
## frame at the bottom edge, shallow enough that 0.18s does not read as a drop.
const RAISE_DROP := 0.70
const FLASH_SECONDS := 0.9
## §8's "Developer HUD Toggle". F8 is the combat lab, F1/F2 are the Training Ground's
## lighting modes, so the indicator gets its own key rather than sharing one.
const INDICATOR_KEY := KEY_F7

const WEAPON_ROOT_PATH := "CameraRig/LookPivot/MotionPivot/ShakePivot/WeaponRoot"

## The first-person sword rigs. NOT the sword's business and NOT the chain's: the
## switch itself is the only thing that knows both weapons exist, so it is the only
## thing that can hide one when the other is in hand. This list lives here and only
## here - it used to be a second copy in CombatSandbox, and a duplicated path list is
## a bug waiting for the day one of the two copies is updated.
## TempSwordVisual is the placeholder; Sword_FP is the real rig ART is building to
## replace it (see scenes/weapons/Sword_FP.tscn), which is why this is a list.
const SWORD_RIGS := [
	"CameraRig/LookPivot/MotionPivot/ShakePivot/WeaponRoot/TempSwordVisual",
]

## True for the whole of a switch, including the raise. Read by `can_switch_weapon`
## so a key mash cannot start a second hand-off mid-hand-off.
var switching := false
## Seconds left of the raise. Exposed because the duration is a spec number and a test
## has to be able to time it.
var switch_left := 0.0

var _slot: WeaponSlot
var _player: Node3D
var _combat: Node
var _weapon_root: Node3D
var _root_home := Vector3.ZERO
var _flash_left := 0.0
var _told_missing_slot := false
## The slot waiting for the sword to finish going home. Set when the player asks
## for something other than the sword while holding it; consumed when the
## sheathe reaches zero. Non-empty means "a put-away is in progress".
var _pending_slot: StringName = &""
var _sheathe_left := 0.0
## True while a DRAW is running, i.e. while `equip_blend` is climbing.
var drawing_in := false
var _draw_left := 0.0
## True only for the instant this manager is itself calling `_slot.equip()`.
##
## `WeaponSlot` is a public API and this manager is not its only caller: the dev
## panel swaps a weapon from a button, the movie renderer swaps one from a
## timeline, and half the test suite swaps one to set up a scene. None of those
## asked for a transition, and none of them should get an animation they did not
## ask for - but all of them used to leave a rig that thought the hand was
## somewhere it was not, which is a sword that refuses to swing because
## `equip_blend` still says "not drawn". So the signal handler needs to be able
## to tell "the hand changed because I took it through a draw" (keep the blend,
## it is being animated) from "the hand changed under me" (snap the blend).
var _own_change := false
var _indicator: CanvasLayer
var _key_labels: Array[Label] = []
var _flash_label: Label
var _indicator_shown := true


func _ready() -> void:
	_player = get_parent() as Node3D
	if _player == null:
		push_warning("WeaponManager: parent is not a Node3D, so there is no player to arm.")
		return
	_slot = _player.get_node_or_null("WeaponSlot") as WeaponSlot
	_combat = _player.get_node_or_null("CombatController")
	_weapon_root = _player.get_node_or_null(WEAPON_ROOT_PATH) as Node3D
	if _weapon_root != null:
		_root_home = _weapon_root.position
	_bind_keys()
	if _slot != null:
		# THE ONLY SUBSCRIPTION THAT MATTERS. Cleanup hangs off the SLOT's change
		# rather than off this node's key handling, so the dev panel's buttons and the
		# training racks get identical cleanup for free. One owner of "the hand
		# changed", not three.
		_slot.changed.connect(_on_slot_changed)
	_build_indicator()
	_refresh_indicator()
	apply_weapon_visibility()


# ---------------------------------------------------------------- public API (§2)

## Puts `wanted` in the player's hands. Returns whether anything changed: a switch to
## the weapon already held is a NO-OP, not a re-equip (§1 - pressing 1 while holding
## the sword must not restart the sword).
func equip_weapon(wanted: StringName) -> bool:
	if not knows(wanted):
		return false
	if _slot == null:
		_warn_missing_slot()
		return false
	if not can_switch_weapon():
		return false
	if _slot.kind == wanted:
		# The only way this is NOT a no-op: the sword is on its way home and the
		# player has changed their mind. Changing your mind mid-sheathe must take
		# the blade back out, or the press reads as a dropped input.
		if _pending_slot != &"":
			_pending_slot = &""
			_sheathe_left = 0.0
			_draw_left = float(SWORD_CONFIG.get("draw_time")) * (1.0 - float(_combat.get("equip_blend")))
			drawing_in = true
			return true
		return false
	var previous := _slot.kind
	# PUTTING THE SWORD AWAY IS ITS OWN ACT (§3), and it has to happen BEFORE the
	# slot changes. `_on_slot_changed` hides the sword rig on frame one, so a slot
	# change taken now would cut the sheathe off before it started and the sword
	# would simply disappear from the hand — the exact reading §20 is about.
	if _slot.is_sword():
		_begin_sheathe(wanted)
		return true
	if wanted == &"sword":
		# The draw replaces the raise; duration is owned by SwordConfig.
		_own_change = true
		var drew := _slot.equip(wanted)
		_own_change = false
		if not drew:
			return false
		_begin_draw()
		weapon_switched.emit(previous, wanted)
		return true
	_own_change = true
	var took := _slot.equip(wanted)
	_own_change = false
	if not took:
		return false
	# The raise starts here and not in `_on_slot_changed`, because the slot also
	# changes from the dev panel: a button in a panel that makes the weapon slide
	# around in the player's hands is a lab artefact, not a switch.
	_begin_raise()
	weapon_switched.emit(previous, wanted)
	return true


func current_weapon() -> StringName:
	return _slot.kind if _slot != null else &""


func finish_draw_for_attack() -> bool:
	if not drawing_in or _pending_slot != &"" or _combat == null:
		return false
	if float(_combat.get("equip_blend")) < SwordBasic.NE_BLADE_CLEAR:
		return false
	# Interrupt only the final settling beat: the blade is already out of the bore.
	_draw_left = 0.0
	drawing_in = false
	_combat.set("equip_blend", 1.0)
	return true


func get_current_weapon() -> StringName:
	# Same answer, named the way §2 names it. Kept as a second entry point rather
	# than a rename so anything already reading `current_weapon` keeps working.
	return current_weapon()


func can_switch_weapon() -> bool:
	if _slot == null:
		return false
	if _slot.is_sword() and _combat != null and _combat.state in [CombatController.State.ATTACK, CombatController.State.RIPOSTE]:
		return _combat._can_cancel(&"light")
	# A raise in progress does NOT block a second press. 0.18s is short but it is not
	# zero, and a player who taps 2 then 1 inside it is changing their mind about a
	# weapon that is already out of their hand - refusing that press would read as a
	# dropped input for no benefit. The raise is on the hand, not on the weapon, so the
	# new weapon simply rises with the motion already under way.
	return not _in_a_cinematic()


## The key hint, built from the registry so it cannot go stale.
func key_hint() -> String:
	var parts := PackedStringArray()
	for i in WEAPONS.size():
		parts.append("[%d] %s" % [i + 1, String(WEAPONS[i]["label"])])
	return "   ".join(parts)


## Clears the weapon state without changing which weapon is held. Used by the
## Training Ground's RESET, which has to put the hands back to a known state without
## deciding for the player what they should be holding.
func reset_weapons() -> void:
	if _combat != null and _combat.has_method("stow"):
		_combat.call("stow")
	switching = false
	switch_left = 0.0
	# A RESET PUTS THE HANDS BACK TO A KNOWN STATE, and "half way through a draw"
	# is not one. The blade snaps to whatever the slot says it should be, which is
	# the only answer a reset can give without deciding for the player.
	_pending_slot = &""
	_sheathe_left = 0.0
	drawing_in = false
	_draw_left = 0.0
	if _combat != null:
		_combat.set("equip_blend", 1.0 if _slot != null and _slot.is_sword() else 0.0)
	if _weapon_root != null:
		_weapon_root.position = _root_home


static func knows(wanted: StringName) -> bool:
	for row in WEAPONS:
		if row["id"] == wanted:
			return true
	return wanted in ALSO_EQUIPPABLE


# ---------------------------------------------------------------- input (§1)

func _bind_keys() -> void:
	# Created at runtime for the same reason every other binding in this project is:
	# project.godot has no [input] section to edit, and the training ground must not
	# be the scene that adds one.
	for i in WEAPONS.size():
		var action := StringName("weapon_%d" % (i + 1))
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		var event := InputEventKey.new()
		event.keycode = WEAPONS[i]["key"]
		event.physical_keycode = WEAPONS[i]["key"]
		InputMap.action_add_event(action, event)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var key := (event as InputEventKey).keycode
	if key == INDICATOR_KEY:
		_set_indicator_shown(not _indicator_shown)
		get_viewport().set_input_as_handled()
		return
	for i in WEAPONS.size():
		if event.is_action_pressed(StringName("weapon_%d" % (i + 1))):
			if not equip_weapon(WEAPONS[i]["id"]):
				# Either the weapon is already in hand (nothing to say) or the
				# switch is being refused. A refusal has to be visible or the
				# player concludes the key is broken.
				_say_why_refused(WEAPONS[i]["id"])
			get_viewport().set_input_as_handled()
			return


func _say_why_refused(wanted: StringName) -> void:
	if _slot == null or _slot.kind == wanted:
		# Nothing to explain: the weapon asked for is already in hand (§1).
		return
	# The only refusal left is a ceremony, so the reason can just say so. A key that
	# silently does nothing is indistinguishable from a broken key.
	_flash("仪式中 · 不可换手")


# ---------------------------------------------------------------- the switch (§5)

func _on_slot_changed(_previous: StringName, current: StringName) -> void:
	if not _own_change:
		# A FOREIGN WRITER. The dev panel, the training rack, a movie renderer or a
		# test swapped the weapon without going through `equip_weapon()`, so there
		# is no draw or sheathe in flight and nothing will ever animate the blend
		# back to an honest number. Snap it: the rig has to agree with the slot on
		# the same frame, or `CombatController` reads "the blade is not drawn" and
		# refuses every attack the player makes with a sword that is visibly in
		# their hands.
		_pending_slot = &""
		_sheathe_left = 0.0
		drawing_in = false
		_draw_left = 0.0
		switching = false
		switch_left = 0.0
		if _weapon_root != null:
			_weapon_root.position = _root_home
		if _combat != null:
			_combat.set("equip_blend", 1.0 if current == &"sword" else 0.0)
	# §5, in order. The sword's half is `stow()` on the controller - buffered input
	# dropped, hitbox closed, move cleared, state back to IDLE - and the chain's half
	# is `ChainDirector.reset()`, which already releases any hook, wipes the momentum
	# and puts the head back in the fist. It is wired to this same signal inside the
	# chain, so neither weapon had to be told about the other for it to happen.
	if _combat != null and _combat.has_method("stow"):
		_combat.call("stow")
	apply_weapon_visibility()
	_flash_for(current)
	_refresh_indicator()


## Hides every first-person sword rig while the sword is not in hand. Public because a
## stage may want to re-assert it (CombatSandbox does, and the rule is one function
## rather than two copies of a path list).
func apply_weapon_visibility() -> void:
	if _player == null or _slot == null:
		return
	var sword_in_hand := _slot.is_sword()
	for path in SWORD_RIGS:
		var rig := _player.get_node_or_null(path) as Node3D
		if rig != null:
			rig.visible = sword_in_hand


func _begin_raise() -> void:
	if switching:
		# Already rising. Re-snapping the hand to the bottom would turn an interrupted
		# switch into a stutter; letting it finish turns it into one motion.
		return
	switching = true
	switch_left = SWITCH_SECONDS
	if _weapon_root != null:
		_weapon_root.position = _root_home - Vector3(0.0, RAISE_DROP, 0.0)


## E0 for a sword that is arriving: the blade is home in the saya and the hand is
## on the hilt. Nothing rises, because a sword taken out of a sheath is already
## where it is — the motion is the DRAW, not a hand coming up from below.
func _begin_draw() -> void:
	drawing_in = true
	_draw_left = float(SWORD_CONFIG.get("draw_time"))
	_pending_slot = &""
	if _combat != null:
		_combat.set("equip_blend", 0.0)
		_combat.call("advance_draw", 0.0, float(SWORD_CONFIG.get("draw_time")))


## How much of the sword's put-away is left as a fraction, for a caller that wants
## to know whether it is safe to do something else yet.
func sheathe_progress() -> float:
	if _pending_slot == &"" or float(SWORD_CONFIG.get("sheath_time")) <= 0.0:
		return 1.0
	return 1.0 - clampf(_sheathe_left / float(SWORD_CONFIG.get("sheath_time")), 0.0, 1.0)


## Starts the put-away: the swing is ended NOW and the blade travels home over the
## next 0.55 s.
##
## THE ORDER MATTERS AND IT IS §5's. `stow()` — hitbox closed, buffered input
## dropped, move cleared, state back to IDLE — happens on the frame the key is
## pressed, because a cut must not survive a weapon change for even one frame.
## What does NOT happen on that frame is the SLOT changing: the rig has to stay
## visible while the blade goes home, or the sheathe is a sword vanishing rather
## than a sword being put away.
func _begin_sheathe(wanted: StringName) -> void:
	_pending_slot = wanted
	_sheathe_left = float(SWORD_CONFIG.get("sheath_time")) * float(_combat.get("equip_blend")) if _combat != null else float(SWORD_CONFIG.get("sheath_time"))
	drawing_in = false
	if _combat != null and _combat.has_method("stow"):
		_combat.call("stow")
	sword_sheathe_started.emit()


func _process(delta: float) -> void:
	if _pending_slot != &"":
		_sheathe_left = maxf(0.0, _sheathe_left - delta)
		if _combat != null:
			_combat.call("advance_sheathe", delta, float(SWORD_CONFIG.get("sheath_time")))
		if _sheathe_left <= 0.0:
			sword_seated.emit()
			var wanted := _pending_slot
			_pending_slot = &""
			# NOW the slot changes: the blade is home, so the cleanup that hides the
			# rig and drops the buffered input has nothing left to interrupt.
			_own_change = true
			var took := _slot.equip(wanted)
			_own_change = false
			if took:
				weapon_switched.emit(&"sword", wanted)
				# ...AND THE INCOMING WEAPON STILL HAS TO ARRIVE. §6's whole point is
				# that a weapon does not teleport into the hand, and a sheathe is not
				# an exemption from it - the chain that appears the instant the blade
				# clicks home is a pop wearing a 0.55s delay. So the raise runs here,
				# AFTER the put-away, because a raise under the sheathe would drag the
				# blade that is still travelling to its mouth.
				_begin_raise()
	if drawing_in:
		_draw_left = maxf(0.0, _draw_left - delta)
		if _combat != null:
			_combat.call("advance_draw", delta, float(SWORD_CONFIG.get("draw_time")))
		if _draw_left <= 0.0:
			drawing_in = false
	if switching:
		switch_left = maxf(0.0, switch_left - delta)
		var t := 1.0 - switch_left / SWITCH_SECONDS
		# Squared so the weapon arrives fast and settles, rather than floating up
		# at a constant rate - a linear raise reads as an elevator.
		var drop := RAISE_DROP * (1.0 - t) * (1.0 - t)
		if _weapon_root != null:
			_weapon_root.position = _root_home - Vector3(0.0, drop, 0.0)
		if switch_left <= 0.0:
			switching = false
			if _weapon_root != null:
				_weapon_root.position = _root_home
	if _flash_left > 0.0:
		_flash_left = maxf(0.0, _flash_left - delta)
		_paint_flash()


# A cinema owns the camera, the clock and the blade's transform (§5). Everything else
# may be interrupted - a throw, a retract, an orbit, a recovery - because that is the
# whole point of the gate: the player must be able to change their mind.
func _in_a_cinematic() -> bool:
	if _combat == null:
		return false
	var state := int(_combat.get("state"))
	return state == CombatController.State.IAIDO or state == CombatController.State.ULTIMATE


func _warn_missing_slot() -> void:
	if _told_missing_slot:
		return
	_told_missing_slot = true
	push_warning(
		"WeaponManager on '%s': the Player has no 'WeaponSlot' child, so no weapon can "
		% _player.name
		+ "change hands. Add the WeaponSlot node to Player.tscn."
	)


# ---------------------------------------------------------------- the indicator (§8)

func _build_indicator() -> void:
	_indicator = CanvasLayer.new()
	_indicator.name = "WeaponIndicator"
	_indicator.layer = 3
	add_child(_indicator)

	var row := HBoxContainer.new()
	row.name = "Keys"
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	row.position = Vector2(-420, -112)
	row.add_theme_constant_override("separation", 16)
	_indicator.add_child(row)

	for i in WEAPONS.size():
		var label := Label.new()
		label.text = "[%d] %s" % [i + 1, String(WEAPONS[i]["label"])]
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.add_theme_font_size_override("font_size", 13)
		# Shadowed rather than panelled: a 13px line over a bright courtyard still has
		# to be readable, and a background box is more interface than §8 asks for.
		label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
		label.add_theme_constant_override("shadow_offset_x", 1)
		label.add_theme_constant_override("shadow_offset_y", 1)
		row.add_child(label)
		_key_labels.append(label)

	_flash_label = Label.new()
	_flash_label.name = "Flash"
	_flash_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash_label.add_theme_font_size_override("font_size", 20)
	_flash_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_flash_label.add_theme_constant_override("shadow_offset_x", 1)
	_flash_label.add_theme_constant_override("shadow_offset_y", 1)
	_flash_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_flash_label.custom_minimum_size = Vector2(360, 0)
	_flash_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_flash_label.position = Vector2(-180, -96)
	_flash_label.modulate.a = 0.0
	_indicator.add_child(_flash_label)


func _set_indicator_shown(shown: bool) -> void:
	_indicator_shown = shown
	if _indicator != null:
		_indicator.visible = shown


func _refresh_indicator() -> void:
	if _key_labels.is_empty():
		return
	var held := current_weapon()
	for i in WEAPONS.size():
		# §8: the current one a little brighter, and nothing else marks it.
		_key_labels[i].modulate.a = 1.0 if WEAPONS[i]["id"] == held else 0.42


func _flash_for(weapon_id: StringName) -> void:
	for row in WEAPONS:
		if row["id"] == weapon_id:
			_flash(String(row["flash"]))
			return
	if weapon_id == &"chain":
		_flash("缚星链 · CHAIN")
		return


func _flash(text: String) -> void:
	if _flash_label == null:
		return
	_flash_label.text = text
	_flash_left = FLASH_SECONDS
	_paint_flash()


func _paint_flash() -> void:
	if _flash_label == null:
		return
	# Fades over the last 0.5s so the name is legible first and then does not simply
	# vanish. It is the only thing on screen that names a weapon, so it has to be
	# unmissable at the moment it appears.
	_flash_label.modulate.a = clampf(_flash_left / 0.5, 0.0, 1.0)
