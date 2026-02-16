extends Node

var state: GameState
var current_phase: Enums.GamePhase = Enums.GamePhase.MAIN_MENU
var movement_system: MovementSystem
var city_system: CitySystem = CitySystem.new()

# Commander name lists per faction
const COMMANDER_NAMES := {
	&"empire": [
		"Legate Aurelius", "Prefect Cassius", "Tribune Marcellus", "Centurion Varro",
		"Commander Gaius", "Marshal Tiberius", "Captain Lucius", "General Septimus",
		"Prefect Helena", "Legate Octavia", "Tribune Valeria", "Commander Flavia",
	],
	&"skulloath": [
		"Warchief Grak", "Bonelord Thresh", "Ravager Krul", "Dread Maw Vex",
		"Skull Warden Zhag", "Gore Fist Brul", "Howler Nix", "Bonecaller Dren",
		"War Mistress Skaela", "Dread Mother Vhul", "Ravager Ghast", "Blood Seer Morg",
	],
	&"gladehost": [
		"Grove Keeper Aelind", "Thorn Warden Sylara", "Root Guard Faelen", "Leaf Marshal Thandril",
		"Bark Shield Eryn", "Vine Watcher Olwen", "Shade Walker Miriel", "Canopy Lord Thaelen",
		"Branch Warden Ysviel", "Moss Sentinel Caedris", "Dew Guard Lirael", "Grove Marshal Alathir",
	],
	&"tainted_jade": [
		"Serpent Lord Ixcatl", "Jade Fang Quetzal", "Venom Priest Tlacael", "Shadow Coatl Xipe",
		"Scale Warden Cipac", "Mist Serpent Yaotl", "Jade Eye Necuame", "Fang Master Itzli",
		"Serpent Queen Malinal", "Venom Seer Xochitl", "Jade Priestess Atzi", "Coatl Keeper Izel",
	],
}
var _commander_name_counters: Dictionary = {} # faction_id -> int

func new_game() -> void:
	state = GameState.new()

	# Generate hex map
	state.hex_map = MapGenerator.generate_hex_map(DataManager.regions)
	movement_system = MovementSystem.new(state.hex_map)

	_init_factions()
	_init_regions()
	_init_cities()
	_init_armies()
	_init_diplomacy()
	current_phase = Enums.GamePhase.CAMPAIGN
	get_tree().change_scene_to_file("res://scenes/campaign/campaign.tscn")

func _init_factions() -> void:
	_commander_name_counters.clear()
	for faction_id in DataManager.factions:
		var fs := FactionState.new()
		fs.faction_data_id = faction_id
		fs.resources = {
			Enums.ResourceType.GOLD: 100,
			Enums.ResourceType.IRON: 50,
			Enums.ResourceType.FOOD: 80,
			Enums.ResourceType.TECHNOLOGY: 20,
			Enums.ResourceType.SHARD_ESSENCE: 0,
			Enums.ResourceType.WOOD: 30,
		}
		state.faction_states[faction_id] = fs

func _init_regions() -> void:
	# Assign starting regions to factions via hex map tile ownership
	for faction_id in DataManager.factions:
		var faction_data: FactionData = DataManager.factions[faction_id]
		var fs: FactionState = state.faction_states[faction_id]
		for region_id in faction_data.starting_regions:
			state.hex_map.set_region_owner(region_id, faction_id)
			fs.owned_regions.append(region_id)

func _init_armies() -> void:
	# Create Empire starting army at their first region center
	var empire_data: FactionData = DataManager.get_faction(&"empire")
	if empire_data and empire_data.starting_regions.size() > 0:
		var center := MapGenerator.get_region_center(empire_data.starting_regions[0])
		var army := _create_army(&"empire", center,
			[&"legionary", &"legionary", &"emberlight_auxilia"])
		state.armies[army.army_id] = army

	# Create Skulloath starting army
	var skulloath_data: FactionData = DataManager.get_faction(&"skulloath")
	if skulloath_data and skulloath_data.starting_regions.size() > 0:
		var center := MapGenerator.get_region_center(skulloath_data.starting_regions[0])
		var army := _create_army(&"skulloath", center,
			[&"warband_raider", &"skulloath_raider", &"runebound_wyvern", &"bonecaller"])
		state.armies[army.army_id] = army

	# Create Gladehost starting army
	var gladehost_data: FactionData = DataManager.get_faction(&"gladehost")
	if gladehost_data and gladehost_data.starting_regions.size() > 0:
		var center := MapGenerator.get_region_center(gladehost_data.starting_regions[0])
		var army := _create_army(&"gladehost", center,
			[&"grove_warden", &"grove_warden", &"thornbow_scout"])
		state.armies[army.army_id] = army

	# Create Tainted Jade starting army
	var jade_data: FactionData = DataManager.get_faction(&"tainted_jade")
	if jade_data and jade_data.starting_regions.size() > 0:
		var center := MapGenerator.get_region_center(jade_data.starting_regions[0])
		var army := _create_army(&"tainted_jade", center,
			[&"jade_fang", &"jade_fang", &"coatl_shaman"])
		state.armies[army.army_id] = army

func _create_army(faction_id: StringName, hex_pos: Vector2i, unit_ids: Array) -> ArmyState:
	var army := ArmyState.new()
	army.army_id = state.generate_id()
	army.faction_id = faction_id
	army.hex_pos = hex_pos
	army.movement_remaining = 2.0

	for uid in unit_ids:
		var unit_data := DataManager.get_unit(uid)
		if unit_data:
			var instance := UnitInstance.new()
			instance.init_from_data(unit_data, state.generate_id())
			army.units.append(instance)

	# Set max movement from unit composition
	army.movement_remaining = army.get_max_movement()

	# Generate commander name
	army.commander_name = _generate_commander_name(faction_id)
	return army

func _generate_commander_name(faction_id: StringName) -> String:
	var names: Array = COMMANDER_NAMES.get(faction_id, [])
	if names.is_empty():
		return "Commander"
	var idx: int = _commander_name_counters.get(faction_id, 0)
	var name: String = names[idx % names.size()]
	_commander_name_counters[faction_id] = idx + 1
	return name

func _init_cities() -> void:
	for faction_id in DataManager.factions:
		var faction_data: FactionData = DataManager.factions[faction_id]
		var fs: FactionState = state.faction_states[faction_id]
		var is_first_city := true
		for region_id in faction_data.starting_regions:
			var center := MapGenerator.get_region_center(region_id)
			var city := CityState.new()
			city.city_id = state.generate_id()
			city.region_id = region_id
			city.faction_id = faction_id
			city.hex_pos = center
			city.level = 1
			city.population = 100
			city.is_capital = is_first_city
			city.buildings.append(&"barracks") # Free starting barracks
			state.cities[city.city_id] = city
			fs.owned_cities.append(city.city_id)
			is_first_city = false

func _init_diplomacy() -> void:
	# Empire relations
	state.diplomacy[&"empire:skulloath"] = Enums.FactionRelation.WAR
	state.diplomacy[&"skulloath:empire"] = Enums.FactionRelation.WAR
	state.diplomacy[&"empire:gladehost"] = Enums.FactionRelation.FRIENDLY
	state.diplomacy[&"gladehost:empire"] = Enums.FactionRelation.FRIENDLY
	state.diplomacy[&"empire:tainted_jade"] = Enums.FactionRelation.WAR
	state.diplomacy[&"tainted_jade:empire"] = Enums.FactionRelation.WAR
	# Skulloath relations
	state.diplomacy[&"skulloath:gladehost"] = Enums.FactionRelation.NEUTRAL
	state.diplomacy[&"gladehost:skulloath"] = Enums.FactionRelation.NEUTRAL
	state.diplomacy[&"skulloath:tainted_jade"] = Enums.FactionRelation.WAR
	state.diplomacy[&"tainted_jade:skulloath"] = Enums.FactionRelation.WAR
	# Gladehost vs Tainted Jade
	state.diplomacy[&"gladehost:tainted_jade"] = Enums.FactionRelation.WAR
	state.diplomacy[&"tainted_jade:gladehost"] = Enums.FactionRelation.WAR

func get_army_at_tile(coord: Vector2i) -> ArmyState:
	for army_id in state.armies:
		var army: ArmyState = state.armies[army_id]
		if army.hex_pos == coord:
			return army
	return null

func get_armies_at_tile(coord: Vector2i) -> Array[ArmyState]:
	var result: Array[ArmyState] = []
	for army_id in state.armies:
		var army: ArmyState = state.armies[army_id]
		if army.hex_pos == coord:
			result.append(army)
	return result

func get_enemies_at_tile(coord: Vector2i, my_faction: StringName) -> Array[ArmyState]:
	var result: Array[ArmyState] = []
	for army in get_armies_at_tile(coord):
		if army.faction_id != my_faction and get_relation(my_faction, army.faction_id) == Enums.FactionRelation.WAR:
			result.append(army)
	return result

func get_relation(faction_a: StringName, faction_b: StringName) -> Enums.FactionRelation:
	if faction_a == faction_b:
		return Enums.FactionRelation.ALLIED
	var key := StringName(str(faction_a) + ":" + str(faction_b))
	return state.diplomacy.get(key, Enums.FactionRelation.NEUTRAL)

func merge_armies_at_tile(coord: Vector2i, faction_id: StringName, prefer_army_id: StringName = &"") -> void:
	var armies_here: Array[ArmyState] = []
	for aid in state.armies:
		var army: ArmyState = state.armies[aid]
		if army.hex_pos == coord and army.faction_id == faction_id:
			armies_here.append(army)
	if armies_here.size() <= 1:
		return
	# Prefer the specified army as merge target
	var target: ArmyState = armies_here[0]
	if prefer_army_id != &"":
		for a in armies_here:
			if a.army_id == prefer_army_id:
				target = a
				break
	for a in armies_here:
		if a.army_id == target.army_id:
			continue
		for unit in a.units:
			target.units.append(unit)
		remove_army(a.army_id)

func found_settlement(faction_id: StringName, hex_pos: Vector2i, parent_city_id: StringName) -> StringName:
	var parent_city: CityState = state.cities.get(parent_city_id)
	if parent_city == null:
		return &""

	# Determine region from hex
	var tile := state.hex_map.get_tile(hex_pos)
	if tile == null:
		return &""

	var city := CityState.new()
	city.city_id = state.generate_id()
	city.region_id = tile.region_id
	city.faction_id = faction_id
	city.hex_pos = hex_pos
	city.level = 1
	city.population = 50
	city.is_capital = false
	state.cities[city.city_id] = city

	var fs: FactionState = state.faction_states.get(faction_id)
	if fs:
		fs.owned_cities.append(city.city_id)

	# Mark parent capital as having used its founding ability
	parent_city.can_found_settlement = false

	return city.city_id

func get_faction_armies(faction_id: StringName) -> Array[ArmyState]:
	var result: Array[ArmyState] = []
	for army_id in state.armies:
		var army: ArmyState = state.armies[army_id]
		if army.faction_id == faction_id:
			result.append(army)
	return result

func move_army_along_path(army_id: StringName, path: Array[Vector2i]) -> void:
	var army: ArmyState = state.armies.get(army_id)
	if army == null or path.is_empty():
		return

	for tile_coord in path:
		var cost := state.hex_map.get_movement_cost(tile_coord, army.faction_id)
		if army.movement_remaining < cost:
			break

		# Check if army is leaving a besieged city hex
		_check_siege_departure(army)

		var from_pos := army.hex_pos
		army.hex_pos = tile_coord
		army.movement_remaining -= cost
		army.has_moved = true
		EventBus.army_moved.emit(army_id, from_pos, tile_coord)

		# Check for battle
		var enemies := get_enemies_at_tile(tile_coord, army.faction_id)
		if enemies.size() > 0:
			EventBus.battle_initiated.emit(army_id, enemies[0].army_id, tile_coord)
			return

		# Check for enemy city at this hex → start siege
		var city_at := city_system.get_city_at_hex(tile_coord)
		if city_at and city_at.faction_id != army.faction_id:
			if not city_at.is_under_siege or city_at.siege_faction != army.faction_id:
				city_system.start_siege(city_at.city_id, army.faction_id)

		# Break siege on own cities if army arrives
		if city_at and city_at.faction_id == army.faction_id and city_at.is_under_siege:
			city_system.break_siege(city_at.city_id)

		# Claim unclaimed shards
		_try_claim_shard(tile_coord, army.faction_id)

		# Take ownership of neutral tiles in the region
		var tile := state.hex_map.get_tile(tile_coord)
		if tile and tile.owner_faction == &"":
			tile.owner_faction = army.faction_id

	# Merge friendly armies at final position
	if army:
		merge_armies_at_tile(army.hex_pos, army.faction_id, army_id)

func _check_siege_departure(army: ArmyState) -> void:
	# If this army was besieging a city and is now leaving, check if any other
	# friendly army remains. If not, break siege.
	var city_at := city_system.get_city_at_hex(army.hex_pos)
	if city_at == null or not city_at.is_under_siege:
		return
	if city_at.siege_faction != army.faction_id:
		return
	# Check if any OTHER friendly army remains at this hex
	var other_present := false
	for aid in state.armies:
		var a: ArmyState = state.armies[aid]
		if a.army_id != army.army_id and a.hex_pos == army.hex_pos and a.faction_id == army.faction_id:
			other_present = true
			break
	if not other_present:
		city_system.break_siege(city_at.city_id)

func _try_claim_shard(hex_pos: Vector2i, faction_id: StringName) -> void:
	for shard_id in state.active_shards:
		var shard: ShardInstance = state.active_shards[shard_id]
		if shard.hex_pos == hex_pos and shard.claimed_by == &"":
			shard.claimed_by = faction_id
			var fs: FactionState = state.faction_states.get(faction_id)
			if fs:
				fs.owned_shards.append(shard_id)
			EventBus.shard_claimed.emit(shard_id, faction_id)
			break

func remove_army(army_id: StringName) -> void:
	var army: ArmyState = state.armies.get(army_id)
	if army:
		EventBus.army_destroyed.emit(army_id, army.faction_id)
		state.armies.erase(army_id)

func change_region_owner(region_id: StringName, new_owner: StringName) -> void:
	var old_owner := state.get_region_owner(region_id)

	# Remove from old owner
	if old_owner != &"":
		var old_fs: FactionState = state.faction_states.get(old_owner)
		if old_fs:
			old_fs.owned_regions.erase(region_id)

	# Set all tiles in region to new owner
	state.hex_map.set_region_owner(region_id, new_owner)

	# Add to new owner
	if new_owner != &"":
		var new_fs: FactionState = state.faction_states.get(new_owner)
		if new_fs and not new_fs.owned_regions.has(region_id):
			new_fs.owned_regions.append(region_id)

	EventBus.region_ownership_changed.emit(region_id, old_owner, new_owner)
