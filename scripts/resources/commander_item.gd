class_name CommanderItem
extends Resource

@export var id: StringName
@export var display_name: String
@export var description: String
@export var rarity: StringName # "common", "rare", "legendary"
@export var effects: Dictionary = {} # effect_type -> value
@export var source_factions: Array[StringName] = []
@export var gift_tags: Array[StringName] = [] # e.g. [&"martial", &"luxury"]
