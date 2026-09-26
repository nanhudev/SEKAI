extends Resource
class_name AbilityData

@export var id: StringName
@export var display_name := ""
@export var startup := 0.0
@export var active := 0.0
@export var recovery := 0.0
@export var mana_cost := 0.0
@export var stamina_cost := 0.0
@export var cooldown := 0.0
@export var vfx_scene: PackedScene
@export var audio: AudioStream
@export var camera_profile: Resource
@export var time_profile: Resource
@export var status_effect: Resource
@export var movement_profile: Resource
