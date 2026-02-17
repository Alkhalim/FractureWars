class_name FactionState
extends Resource

@export var faction_data_id: StringName
@export var resources: Dictionary = {} # ResourceType -> int
@export var owned_regions: Array[StringName] = []
@export var owned_cities: Array[StringName] = []
@export var owned_shards: Array[StringName] = []
@export var commander_pool: Array[CommanderState] = []
@export var item_storage: Array[StringName] = []
@export var is_defeated: bool = false
