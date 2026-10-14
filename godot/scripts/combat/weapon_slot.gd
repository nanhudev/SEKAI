extends Node
class_name WeaponSlot
# WHAT IS IN THE PLAYER'S HANDS. Nothing else.
#
# There is exactly one of these, on the Player. Both weapon systems read it and
# neither writes it: a switch is a decision (the Combat Lab today, an inventory
# later), and it has to have one owner or the answer to "who does this click
# belong to" becomes "whichever node the event reached first".
#
# This node is also why no controller needs a `if weapon == ...` branch on the
# player. A system asks whether it is the one being held, and returns if not.
#
# 玩家没有职业，只有经历: the slot holds a WEAPON, never a class. Sword, chain and
# magic are three languages the same character may learn in any order.

signal changed(previous: StringName, current: StringName)

const SWORD := &"sword"
const CHAIN := &"chain"
## PHANTOM CHAIN / 虚链 — independent combat workstream from Sword and from
## Star-Bind Chain (`CHAIN`). Key 2 in WeaponManager. Rule-based visual chain;
## no resident weapon mesh.
const PHANTOM_CHAIN := &"phantom_chain"
## MIRROR / 镜 — independent combat workstream. Key 3 in WeaponManager.
## Position / angle / travel prototype. Do not fold into sword or chain.
const MIRROR := &"mirror"
## EMPTY HANDS, AND IT IS A REAL THIRD STATE RATHER THAN A FLAG ON THE PLAYER.
##
## THE FIRST PLAYABLE NEEDS IT AND NOTHING ELSE DOES. §2 of that round requires the
## player to begin the game owning nothing, §6 requires them to physically pick a
## sword off a rack, and §22 requires the save file to remember that they did. The
## naive version of "does not have a sword yet" is a boolean somewhere on the story
## layer — and it is wrong, because a boolean that the sword systems do not read is
## a lie the moment the player swings: `CombatController._holds_sword()` would say
## yes, the first-person rig would draw a 95 cm blade in a hand that owns nothing,
## and the light chain would be available before the pickup cutscene had finished.
##
## A third KIND costs three lines and makes every existing question answer itself:
## `is_sword()` is false so no sword attack starts, `WeaponManager`'s visibility
## rule hides the rig with no new code, and `ChainDirector`'s `is_chain()` gate
## keeps the chain down. Nothing has to learn that "empty" exists.
##
## It is deliberately NOT the default. A stage that predates the story (the combat
## sandbox, the training ground, every test) should keep handing the player a sword
## on frame one, exactly as it always has.
const NONE := &"none"

var kind: StringName = SWORD


func equip(wanted: StringName) -> bool:
	if wanted != SWORD and wanted != CHAIN and wanted != PHANTOM_CHAIN and wanted != MIRROR and wanted != NONE:
		return false
	if wanted == kind:
		return false
	var previous := kind
	kind = wanted
	changed.emit(previous, kind)
	return true


func holds(wanted: StringName) -> bool:
	return kind == wanted


func is_sword() -> bool:
	return kind == SWORD


func is_chain() -> bool:
	return kind == CHAIN


func is_phantom_chain() -> bool:
	return kind == PHANTOM_CHAIN


func is_mirror() -> bool:
	return kind == MIRROR


func is_empty() -> bool:
	return kind == NONE


func display_name() -> String:
	match kind:
		SWORD:
			return "剑 · Sword"
		CHAIN:
			return "缚星链 · STAR-BIND CHAIN"
		PHANTOM_CHAIN:
			return "虚链 · PHANTOM CHAIN"
		MIRROR:
			return "镜 · MIRROR"
	return "空手 · Unarmed"
