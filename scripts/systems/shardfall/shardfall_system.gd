class_name ShardfallSystem
extends RefCounted

const REALM_NAMES := ["Divine", "Void", "Elemental", "Nature", "Mortal"]
const REALM_COLORS := [
	Color(0.95, 0.85, 0.2),   # Divine - yellow
	Color(0.5, 0.15, 0.7),    # Void - purple
	Color(0.9, 0.5, 0.15),    # Elemental - orange
	Color(0.2, 0.75, 0.3),    # Nature - green
	Color(0.25, 0.5, 0.9),    # Mortal - blue
]

var guardian_system: ShardGuardianSystem = ShardGuardianSystem.new()
var turns_since_last_fall: int = 0
var base_chance: float = 0.65
var escalation: float = 0.12

func check_shardfall(current_turn: int) -> void:
	turns_since_last_fall += 1

	# Hardcoded: always trigger on turn 3 for the prototype
	if current_turn == 3:
		_trigger_shardfall()
		return

	# Guaranteed shardfall if drought lasts 6+ turns
	if turns_since_last_fall >= 6:
		_trigger_shardfall()
		turns_since_last_fall = 0
		return

	# Scale number of shardfall attempts with map size
	# Large maps (117x78 = ~9000 tiles) get 2-3 attempts per check
	var tile_count := HexMapData.MAP_WIDTH * HexMapData.MAP_HEIGHT
	var attempts := 1 + tile_count / 4000  # ~3 attempts on large map

	var chance := base_chance + (turns_since_last_fall * escalation)
	chance = min(chance, 0.9)

	var triggered := false
	for i in attempts:
		if randf() < chance:
			_trigger_shardfall()
			triggered = true
	if triggered:
		turns_since_last_fall = 0

func _trigger_shardfall() -> void:
	var realm := _pick_realm()
	var hex_pos := _pick_hex_position()
	if hex_pos == Vector2i(-1, -1):
		return

	var shard := ShardInstance.new()
	shard.shard_id = GameManager.state.generate_id()
	shard.realm = realm
	shard.power_level = randi_range(1, 3)
	shard.hex_pos = hex_pos
	shard.turns_remaining = 8

	GameManager.state.active_shards[shard.shard_id] = shard

	# Spawn guardian army to protect the shard
	var army := guardian_system.spawn_guardian_army(shard)
	if army:
		shard.guardian_army_id = army.army_id
		GameManager.state.armies[army.army_id] = army

	EventBus.shardfall_occurred.emit(shard.shard_id, hex_pos, realm)

func _pick_realm() -> Enums.Realm:
	var month_data: Dictionary = DataManager.calendar_months[GameManager.state.current_month]
	var month_realms: Array = month_data.realms

	if randf() < 0.6 and month_realms.size() > 0:
		return month_realms[randi() % month_realms.size()]

	return randi() % 5 as Enums.Realm

func _pick_hex_position() -> Vector2i:
	var hex_map := GameManager.state.hex_map
	if hex_map == null:
		return Vector2i(-1, -1)

	# Prefer tiles in neutral regions, avoid tiles with existing unclaimed shards
	var shard_positions: Dictionary = {}
	for shard_id in GameManager.state.active_shards:
		var shard: ShardInstance = GameManager.state.active_shards[shard_id]
		if shard.claimed_by == &"":
			shard_positions[shard.hex_pos] = true

	var candidates: Array[Vector2i] = []
	var preferred: Array[Vector2i] = [] # Neutral tiles

	for coord in hex_map.tiles:
		if shard_positions.has(coord):
			continue
		# Skip edge tiles
		if coord.x <= 1 or coord.x >= HexMapData.MAP_WIDTH - 2:
			continue
		if coord.y <= 1 or coord.y >= HexMapData.MAP_HEIGHT - 2:
			continue

		var tile: HexMapData.TileState = hex_map.tiles[coord]
		# Skip impassable / unsuitable tiles
		if tile.terrain == Enums.TerrainType.WATER or tile.terrain == Enums.TerrainType.WETLANDS or tile.terrain == Enums.TerrainType.MOUNTAINS:
			continue
		candidates.append(coord)
		if tile.owner_faction == &"":
			preferred.append(coord)

	if preferred.size() > 0:
		return preferred[randi() % preferred.size()]
	elif candidates.size() > 0:
		return candidates[randi() % candidates.size()]

	return Vector2i(-1, -1)

static func get_realm_name(realm: Enums.Realm) -> String:
	if realm >= 0 and realm < REALM_NAMES.size():
		return REALM_NAMES[realm]
	return "Unknown"

static func get_realm_color(realm: Enums.Realm) -> Color:
	if realm >= 0 and realm < REALM_COLORS.size():
		return REALM_COLORS[realm]
	return Color.WHITE
