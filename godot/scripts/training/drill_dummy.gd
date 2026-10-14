extends "res://scripts/enemies/technical_dummy.gd"
# DRILL DUMMY — the small one, and the one that cannot be killed.
#
# WHY THIS IS A SUBCLASS AND NOT A FLAG ON THE ENEMY
# `technical_dummy.gd` is an ENEMY. It is loaded by the arena, by the playtest range
# and by anything that wants a body to hit, and its death is part of its contract with
# the execution ceremony. A "training mode" boolean on it would mean every reader of
# that file has to hold two behaviours in their head at once, and a bug in the training
# branch would ship inside the enemy.
#
# So the difference is a SUBCLASS, and the difference is exactly two things: this body
# does not die, and it says so to the signature. Everything else — the hit reaction, the
# stagger, the freeze, the chain contract, the real attack — is inherited unchanged,
# because that is the half a "training dummy mode" usually throws away and the half a
# playtest actually needs.
#
# WHAT IT IS FOR (§14 of the playtest brief, and the user's own ask: 不会被打死的)
# A combo is a SEQUENCE. A target that dies in two hits turns that sequence into a
# sequence of dummies, and the player spends the session walking back to the stand
# instead of learning the weapon. This one absorbs the session and stays standing.
#
# WHY IT ALSO REFUSES THE SIGNATURE (聚合斩)
# Being unkillable is not only "health does not reach zero". `_iaido_strike` checks
# the PROFILE before it checks health, so a body with a supported profile would be
# handed to the execution ceremony the moment a lethal cut landed, and it would be
# cut in half three seconds later — a training dummy that the game's own finisher
# can execute is not unkillable, it is merely hard to kill. Answering
# `iaido_execution_supported = false` is the contract's own word for "this body
# cannot be cut", so the deep slash runs instead: the player sees the strongest thing
# in the game land on it and the body survive, which is a legible answer rather than
# a silent one.

## How long the body takes to get back up. Long enough to read as "that hurt", short
## enough that a combo is not interrupted by the wait.
const RECOVER_TIME := 0.9

var _drill_profile: IaidoExecutionProfile


func _build_telegraph() -> void:
	# The ring is the parry cue, so it has to sit ON this body. The parent's ring is
	# sized for a 2.1m construct; on a 1.5m one it would be a hoop floating around its
	# ankles, which is a cue that says "something else is being telegraphed".
	#
	# Built by the parent and then RESIZED rather than copied, because `_update_cue`
	# only ever writes `telegraph.scale` and the material — the mesh radii are nobody
	# else's business, so changing them here survives every frame that follows.
	super()
	if telegraph == null:
		return
	var ring := telegraph.mesh as TorusMesh
	if ring != null:
		ring.inner_radius = 0.50
		ring.outer_radius = 0.70
	telegraph.position = Vector3(0.0, 0.22, 0.0)


## THE ONE ANSWER THAT MAKES IT UNKILLABLE. See the header.
##
## Deliberately returns a live profile with `iaido_execution_supported = false` rather
## than `null`: `null` means "this body has no opinion" and falls back to the generic
## construct profile, which is SUPPORTED, and the dummy would be executed. The contract
## has a word for "no", and this is it.
func iaido_execution_profile() -> IaidoExecutionProfile:
	if _drill_profile == null:
		_drill_profile = IaidoExecutionProfile.new()
		_drill_profile.enemy_id = &"drill_dummy"
		_drill_profile.iaido_execution_supported = false
		_drill_profile.execution_type = IaidoExecutionProfile.TYPE_NONE
		_drill_profile.cut_material = IaidoExecutionProfile.MATERIAL_CONSTRUCT
	return _drill_profile


## THE OTHER HALF OF "IT CANNOT BE KILLED".
##
## Every path that would end this body's participation goes through here — a lethal
## sword hit, a lethal spell, the tick of a damage-over-time element, and the deep slash
## a refused signature leaves. Rather than guard four call sites, the ENDING ITSELF is
## replaced with a knockback, which is both smaller and impossible to miss: a future
## damage source written by someone who has never read this file still cannot kill it.
##
## Health is restored rather than merely clamped above zero, so the readouts a debug
## panel shows stay meaningful — a dummy sitting at 1 HP forever would report the
## session's damage as almost-lethal, every time.
func _die() -> void:
	# A held body is being staged by the execution ceremony, and there is nothing to
	# rescue. Unreachable while the profile above says no, and kept because "should be
	# unreachable" is not the same as "is".
	if state == State.EXECUTING:
		return
	health = max_health
	poise = 0.0
	state = State.STAGGER
	state_timer = RECOVER_TIME
	attack_hitbox.set_active(false)
	attack_open = false
	last_interrupt = 0.4
	_open_idle()


## Nothing to reset that the parent does not already reset — but the drill is a
## training fixture, so it says so out loud rather than relying on the reader
## noticing that it does not override `reset_dummy`.
func is_training_fixture() -> bool:
	return true


## The RESET hook. A fixture owns its own recovery (see `playtest_range`), which is
## what lets a fourth one be added to the room without editing the reset list — and
## which is why this delegates rather than reimplementing health, poise and elements.
func reset_fixture() -> void:
	reset_dummy()
