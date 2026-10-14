extends Resource
class_name MagicSchool
# A school is a set of spells sharing one element identity. It is deliberately
# thin: the element's rules live in ElementDefinition, and the school only says
# which spells belong together and which one is the default.

@export var id: StringName = &""
@export var display_name := ""
@export var tagline := ""
@export var element: ElementDefinition
@export var spells: Array[SpellDefinition] = []


func primary() -> SpellDefinition:
	return spells[0] if not spells.is_empty() else null


func get_spell(spell_id: StringName) -> SpellDefinition:
	for spell in spells:
		if spell.id == spell_id:
			return spell
	return null


func field_spell() -> SpellDefinition:
	for spell in spells:
		if spell.field_radius > 0.0:
			return spell
	return null
