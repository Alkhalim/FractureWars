class_name TreatyInstance
extends Resource

@export var treaty_id: StringName
@export var treaty_type: int # Enums.TreatyType
@export var faction_a: StringName # proposer
@export var faction_b: StringName # acceptor
@export var turns_remaining: int = -1 # -1 = permanent, >0 = timed
@export var terms: Dictionary = {} # TRADE: {give_resource, give_amount, receive_resource, receive_amount}
