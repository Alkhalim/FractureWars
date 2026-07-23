extends Node
## Autoload: resolves campaign battles in the simulation layer, independent of
## the campaign scene. Previously all battle resolution lived in campaign.gd, so
## a battle only ever resolved while the campaign scene was listening — which
## made AI-vs-AI headless simulation stall the moment two armies met (each
## re-attacking the same tile forever). Now the pure resolution lives here and
## the campaign scene merely OPTS IN to showing the player dialog + report.
##
## Flow:
##   EventBus.battle_initiated  ->  _on_battle_initiated (this node)
##     - merge garrison reinforcements
##     - player involved AND a UI is active  -> EventBus.battle_player_prompt
##     - otherwise (AI-vs-AI, or headless)   -> auto_resolve() immediately
##   auto_resolve() emits EventBus.battle_auto_resolved(report) when done; the
##   campaign scene (if present) refreshes markers and shows the report.

## Set true by the campaign scene while it is on-screen, so player-involved
## battles wait for the fight/auto/retreat dialog instead of silently
## auto-resolving. Headless (no scene) leaves this false and battles resolve.
var ui_active := false

func _ready() -> void:
	EventBus.battle_initiated.connect(_on_battle_initiated)

func _on_battle_initiated(attacker_id: StringName, defender_id: StringName, hex_pos: Vector2i) -> void:
	var attacker_army: ArmyState = GameManager.state.armies.get(attacker_id)
	var defender_army: ArmyState = GameManager.state.armies.get(defender_id)
	if attacker_army == null or defender_army == null:
		return

	# Garrison reinforcements: if defender is in their own/allied city, merge
	# garrison units. Also check attacker (rare — attacker sitting in own city).
	_merge_garrison_reinforcements(defender_army, hex_pos)
	_merge_garrison_reinforcements(attacker_army, hex_pos)

	var player_fid := GameManager.state.player_faction_id
	var player_involved := attacker_army.faction_id == player_fid or defender_army.faction_id == player_fid
	if player_involved and ui_active:
		# Let the campaign scene present fight / auto-resolve / retreat.
		EventBus.battle_player_prompt.emit(attacker_id, defender_id, hex_pos)
	else:
		auto_resolve(attacker_id, defender_id, hex_pos)

## Full headless battle resolution. Runs the V2 simulator, applies casualties,
## siege, loot, captives, XP, item drops and faction mechanics. Emits
## EventBus.battle_auto_resolved(report) — report is empty for AI-vs-AI, or a
## populated dict when the player was involved (for the scene to display).
func auto_resolve(attacker_id: StringName, defender_id: StringName, hex_pos: Vector2i) -> void:
	var attacker_army: ArmyState = GameManager.state.armies.get(attacker_id)
	var defender_army: ArmyState = GameManager.state.armies.get(defender_id)
	if attacker_army == null or defender_army == null:
		return

	# Snapshot HP before battle for report
	var atk_snapshot: Array[Dictionary] = []
	for unit in attacker_army.units:
		var ud := DataManager.get_unit(unit.unit_data_id)
		atk_snapshot.append({
			"name": ud.display_name if ud else str(unit.unit_data_id),
			"hp_before": unit.current_hp,
			"max_hp": ud.max_hp if ud else unit.current_hp,
		})
	var def_snapshot: Array[Dictionary] = []
	for unit in defender_army.units:
		var ud := DataManager.get_unit(unit.unit_data_id)
		def_snapshot.append({
			"name": ud.display_name if ud else str(unit.unit_data_id),
			"hp_before": unit.current_hp,
			"max_hp": ud.max_hp if ud else unit.current_hp,
		})

	# Calculate commander bonuses for both sides
	var atk_cmd_bonuses := CommanderSystem.get_commander_army_bonuses(attacker_army.commander)
	var def_cmd_bonuses := CommanderSystem.get_commander_army_bonuses(defender_army.commander)
	# Apply camp building bonuses (Sunblessed Sunfire Forge etc.)
	_apply_camp_building_bonuses(attacker_army, atk_cmd_bonuses)
	_apply_camp_building_bonuses(defender_army, def_cmd_bonuses)

	# Snapshot army strengths before battle (for loot and XP calculation)
	var atk_strength_pre := attacker_army.get_total_strength()
	var def_strength_pre := defender_army.get_total_strength()

	# Create V2 headless battle simulation
	var campaign_terrain := Enums.TerrainType.PLAINS
	if GameManager.state and GameManager.state.hex_map:
		var tile := GameManager.state.hex_map.get_tile(hex_pos)
		if tile:
			campaign_terrain = tile.terrain

	var sim := BattleSimulatorV2.new()
	sim.compute_grid_size(attacker_army, defender_army)
	var terrain := BattleTerrainGen.generate(campaign_terrain, hex_pos.x * 1000 + hex_pos.y, sim.grid_width, sim.grid_height)
	sim.setup_terrain(terrain)
	sim.setup_attacker_formations(attacker_army, atk_cmd_bonuses)
	sim.setup_defender_formations(defender_army, def_cmd_bonuses)
	sim.assign_ai_orders_both_sides()

	# Run simulation to completion
	for tick in range(sim.max_ticks):
		sim.simulate_tick()
		if sim.is_finished:
			break

	# Apply results
	var atk_survivors := sim.get_surviving_formations(0)
	var def_survivors := sim.get_surviving_formations(1)

	_apply_auto_battle_results(attacker_army, atk_survivors)
	_apply_auto_battle_results(defender_army, def_survivors)

	# Elderbeast recovery: if a beast's escort army lost, apply recovery mechanic
	for side_army in [attacker_army, defender_army]:
		if side_army.elderbeast_id != &"":
			_handle_elderbeast_battle_aftermath(side_army)

	# Grant veterancy XP to surviving units
	_grant_auto_veterancy_xp(attacker_army, atk_survivors, def_strength_pre)
	_grant_auto_veterancy_xp(defender_army, def_survivors, atk_strength_pre)

	var atk_alive := atk_survivors.size() > 0 or attacker_army.elderbeast_id != &""
	var def_alive := def_survivors.size() > 0 or defender_army.elderbeast_id != &""

	# Build HP after data for report
	var atk_hp_after: Dictionary = {} # index -> hp
	for bu in atk_survivors:
		for i in atk_snapshot.size():
			if i < attacker_army.units.size() and attacker_army.units[i].instance_id == bu.instance_id:
				atk_hp_after[i] = bu.current_hp
	var def_hp_after: Dictionary = {}
	for bu in def_survivors:
		for i in def_snapshot.size():
			if i < defender_army.units.size() and defender_army.units[i].instance_id == bu.instance_id:
				def_hp_after[i] = bu.current_hp

	# Award captives
	var winner_side := sim.winner_side
	if winner_side >= 0:
		var winner_faction := attacker_army.faction_id if winner_side == 0 else defender_army.faction_id
		var winner_captives: int = sim.captives.get(winner_side, 0)
		if winner_captives > 0:
			var wfs: FactionState = GameManager.state.faction_states.get(winner_faction)
			if wfs:
				wfs.resources[Enums.ResourceType.CAPTIVES] = wfs.resources.get(Enums.ResourceType.CAPTIVES, 0) + winner_captives

	if not def_alive:
		# Mark garrison as defeated so it doesn't respawn at full strength
		if defender_army.is_garrison:
			var garrison_city := GameManager.city_system.get_city_at_hex(hex_pos)
			if garrison_city:
				garrison_city.garrison_defeated_turn = GameManager.state.current_turn
				garrison_city.garrison_hp_ratio = 0.0
		GameManager.remove_army(defender_id)

	# Garrison assault: check if attacker won (morale/routing victory counts)
	var garrison_retreat := false
	var def_faction_id := defender_army.faction_id
	if defender_army.is_garrison and def_alive:
		var attacker_won_garrison := (winner_side == 0 and atk_alive)
		if attacker_won_garrison:
			# Attacker won — garrison overrun, treat as destroyed
			var garrison_city := GameManager.city_system.get_city_at_hex(hex_pos)
			if garrison_city:
				garrison_city.garrison_defeated_turn = GameManager.state.current_turn
				garrison_city.garrison_hp_ratio = 0.0
			GameManager.remove_army(defender_id)
			def_alive = false
		else:
			# Attacker failed to defeat garrison — retreat with survivors or die
			GameManager.remove_army(defender_id) # garrison regenerates next attack
			def_alive = false
			if atk_alive:
				# Retreat attacker 1 tile back from the city
				var retreat_hex := _find_retreat_hex(attacker_army, hex_pos)
				if retreat_hex != Vector2i(-1, -1):
					attacker_army.hex_pos = retreat_hex
					GameManager.movement_system.invalidate_positions()
				attacker_army.movement_remaining = 0.0
				attacker_army.battle_exhausted = true
				garrison_retreat = true
				# Persist garrison damage — surviving garrison spawns with reduced HP
				var garrison_city := GameManager.city_system.get_city_at_hex(hex_pos)
				if garrison_city:
					var total_max := 0
					var total_current := 0
					for unit in defender_army.units:
						var data := DataManager.get_unit(unit.unit_data_id)
						if data:
							total_max += data.max_hp
						total_current += unit.current_hp
					if total_max > 0:
						garrison_city.garrison_hp_ratio = clampf(float(total_current) / float(total_max), 0.01, 1.0)
			else:
				GameManager.remove_army(attacker_id)
	elif not atk_alive:
		GameManager.remove_army(attacker_id)

	# Remove surviving garrison armies (they regenerate on next attack)
	if def_alive and defender_army.is_garrison:
		GameManager.remove_army(defender_id)
		def_alive = false

	# Stalemate: both armies survive — separate and exhaust
	if atk_alive and def_alive:
		attacker_army.battle_exhausted = true
		attacker_army.movement_remaining = 0.0
		defender_army.battle_exhausted = true
		defender_army.movement_remaining = 0.0
		_separate_armies_stalemate(attacker_army, defender_army)

	# Handle siege consequences (same as manual battle)
	if atk_alive and not def_alive and not garrison_retreat:
		attacker_army.hex_pos = hex_pos
		GameManager.movement_system.invalidate_positions()
		attacker_army.battle_exhausted = true
		attacker_army.movement_remaining = 0.0
		EventBus.battle_resolved.emit(attacker_army.faction_id, hex_pos)
		GameManager.diplomacy_system._apply_hostile_action_ripple(attacker_army.faction_id, def_faction_id, 5)
		var city_at := GameManager.city_system.get_city_at_hex(hex_pos)
		if city_at and city_at.faction_id != attacker_army.faction_id:
			GameManager.city_system.start_siege(city_at.city_id, attacker_army.faction_id)
			# Overrunning the garrison is a decisive assault win.
			if defender_army.is_garrison and city_at.is_under_siege:
				GameManager.city_system.award_siege_overrun(city_at)
		elif city_at and city_at.faction_id == attacker_army.faction_id and city_at.is_under_siege:
			GameManager.city_system.break_siege(city_at.city_id)
	elif garrison_retreat:
		EventBus.battle_resolved.emit(def_faction_id, hex_pos)
		GameManager.diplomacy_system._apply_hostile_action_ripple(def_faction_id, attacker_army.faction_id, 5)
	elif def_alive and not atk_alive:
		EventBus.battle_resolved.emit(defender_army.faction_id, hex_pos)
		GameManager.diplomacy_system._apply_hostile_action_ripple(defender_army.faction_id, attacker_army.faction_id, 5)
		var city_at := GameManager.city_system.get_city_at_hex(hex_pos)
		if city_at and city_at.faction_id == defender_army.faction_id and city_at.is_under_siege:
			GameManager.city_system.break_siege(city_at.city_id)

	# Siege pressure from a field battle fought on a besieged city hex.
	# Excludes garrison assaults (handled above); handles both "besieger attacks
	# relief on the hex" and "relief attacks besieger on the hex".
	var siege_city := GameManager.city_system.get_city_at_hex(hex_pos)
	if siege_city and siege_city.is_under_siege and not attacker_army.is_garrison and not defender_army.is_garrison:
		var besieger_fid := siege_city.siege_faction
		var besieger_is_atk := attacker_army.faction_id == besieger_fid
		var besieger_is_def := defender_army.faction_id == besieger_fid
		if besieger_is_atk or besieger_is_def:
			var besieger_alive := atk_alive if besieger_is_atk else def_alive
			var enemy_alive := def_alive if besieger_is_atk else atk_alive
			var atk_frac := float(attacker_army.get_total_strength()) / maxf(1.0, float(atk_strength_pre))
			var def_frac := float(defender_army.get_total_strength()) / maxf(1.0, float(def_strength_pre))
			var besieger_frac := atk_frac if besieger_is_atk else def_frac
			var enemy_frac := def_frac if besieger_is_atk else atk_frac
			GameManager.city_system.award_siege_battle(siege_city, besieger_alive, enemy_alive, besieger_frac, enemy_frac)

	# Build battle context for context-aware skill selection
	var base_ctx: Array[StringName] = []
	var ctx_tile := GameManager.state.hex_map.get_tile(hex_pos)
	if ctx_tile:
		base_ctx.append(StringName("terrain_" + Enums.TerrainType.keys()[ctx_tile.terrain].to_lower()))
	if GameManager.city_system.get_city_at_hex(hex_pos):
		base_ctx.append(&"in_city")

	# Collect used and faced unit tags from both sides
	var unit_tag_types := ["cavalry", "ranged", "mage", "infantry", "beast", "monster", "construct"]
	var atk_used_tags: Dictionary = {}
	var def_faced_tags: Dictionary = {}
	for f in sim.attacker_formations:
		for tag in f.tags:
			if tag in unit_tag_types:
				atk_used_tags[tag] = true
	for f in sim.defender_formations:
		for tag in f.tags:
			if tag in unit_tag_types:
				def_faced_tags[tag] = true
	var def_used_tags: Dictionary = {}
	var atk_faced_tags: Dictionary = {}
	for f in sim.defender_formations:
		for tag in f.tags:
			if tag in unit_tag_types:
				def_used_tags[tag] = true
	for f in sim.attacker_formations:
		for tag in f.tags:
			if tag in unit_tag_types:
				atk_faced_tags[tag] = true

	var atk_ctx: Array[StringName] = base_ctx.duplicate()
	atk_ctx.append(&"was_attacker")
	atk_ctx.append(&"battle_won" if atk_alive else &"battle_lost")
	atk_ctx.append(StringName("enemy_" + defender_army.faction_id))
	for tag in def_faced_tags:
		atk_ctx.append(StringName("faced_" + tag))
	for tag in atk_used_tags:
		atk_ctx.append(StringName("used_" + tag))

	var def_ctx: Array[StringName] = base_ctx.duplicate()
	def_ctx.append(&"was_defender")
	def_ctx.append(&"battle_won" if def_alive else &"battle_lost")
	def_ctx.append(StringName("enemy_" + attacker_army.faction_id))
	for tag in atk_faced_tags:
		def_ctx.append(StringName("faced_" + tag))
	for tag in def_used_tags:
		def_ctx.append(StringName("used_" + tag))

	# Commander XP and item drops (use pre-battle strengths)
	if attacker_army.commander:
		CommanderSystem.grant_battle_xp(attacker_army.commander, def_strength_pre, atk_alive, atk_ctx)
		var atk_trait_changes := CommanderSystem.evaluate_traits(attacker_army.commander, atk_ctx)
		for change in atk_trait_changes:
			EventBus.commander_trait_changed.emit(attacker_army.commander, change.action, change.trait_id)
		if atk_alive and not def_alive:
			CommanderSystem.apply_item_drop(attacker_army.commander, defender_army.faction_id)
	if defender_army.commander:
		CommanderSystem.grant_battle_xp(defender_army.commander, atk_strength_pre, def_alive, def_ctx)
		var def_trait_changes := CommanderSystem.evaluate_traits(defender_army.commander, def_ctx)
		for change in def_trait_changes:
			EventBus.commander_trait_changed.emit(defender_army.commander, change.action, change.trait_id)
		if def_alive and not atk_alive:
			CommanderSystem.apply_item_drop(defender_army.commander, attacker_army.faction_id)

	# Battle loot for the winner
	var _loot_gold := 0
	var _loot_iron := 0
	if atk_alive and not def_alive:
		_loot_gold = int(sqrt(def_strength_pre) * 1.26)
		_loot_iron = int(sqrt(def_strength_pre) * 0.31)
		var wfs: FactionState = GameManager.state.faction_states.get(attacker_army.faction_id)
		if wfs:
			wfs.resources[Enums.ResourceType.GOLD] = wfs.resources.get(Enums.ResourceType.GOLD, 0) + _loot_gold
			wfs.resources[Enums.ResourceType.IRON] = wfs.resources.get(Enums.ResourceType.IRON, 0) + _loot_iron
	elif def_alive and not atk_alive:
		_loot_gold = int(sqrt(atk_strength_pre) * 1.26)
		_loot_iron = int(sqrt(atk_strength_pre) * 0.31)
		var wfs: FactionState = GameManager.state.faction_states.get(defender_army.faction_id)
		if wfs:
			wfs.resources[Enums.ResourceType.GOLD] = wfs.resources.get(Enums.ResourceType.GOLD, 0) + _loot_gold
			wfs.resources[Enums.ResourceType.IRON] = wfs.resources.get(Enums.ResourceType.IRON, 0) + _loot_iron

	# Faction mechanic: Thunderswarm storm fury rises from battles
	for fid in [attacker_army.faction_id, defender_army.faction_id]:
		if fid == &"thunderswarm":
			var tfs: FactionState = GameManager.state.faction_states.get(fid)
			if tfs:
				tfs.storm_fury = mini(tfs.storm_fury + 15, 100)

	# Faction mechanic: Sunblessed solar faith changes from battle results
	for battle_pair in [[attacker_army.faction_id, atk_alive], [defender_army.faction_id, def_alive]]:
		if battle_pair[0] == &"sunblessed":
			var sfs: FactionState = GameManager.state.faction_states.get(battle_pair[0])
			if sfs:
				if battle_pair[1]:
					sfs.solar_faith = mini(sfs.solar_faith + 10, 100)
				else:
					sfs.solar_faith = maxi(sfs.solar_faith - 15, 0)

	# Build report only when the player is involved (the scene displays it)
	var report: Dictionary = {}
	var player_fid := GameManager.state.player_faction_id
	var player_involved := attacker_army.faction_id == player_fid or defender_army.faction_id == player_fid
	if player_involved:
		var player_won := (attacker_army.faction_id == player_fid and atk_alive and not def_alive) or \
			(defender_army.faction_id == player_fid and def_alive and not atk_alive)
		report = {
			"atk_faction": attacker_army.faction_id,
			"def_faction": defender_army.faction_id,
			"atk_snapshot": atk_snapshot,
			"def_snapshot": def_snapshot,
			"atk_hp_after": atk_hp_after,
			"def_hp_after": def_hp_after,
			"atk_alive": atk_alive,
			"def_alive": def_alive,
			"captives": sim.captives.get(0 if attacker_army.faction_id == player_fid else 1, 0) if player_won else 0,
			"loot_gold": _loot_gold if player_won else 0,
			"loot_iron": _loot_iron if player_won else 0,
		}

	# Let the campaign scene (if present) refresh markers and show the report.
	EventBus.battle_auto_resolved.emit(report)

# ── Pure helpers (moved verbatim from campaign.gd) ─────────────

## Merge garrison units from a city into a defending army
func _merge_garrison_reinforcements(army: ArmyState, hex_pos: Vector2i) -> void:
	if army.is_garrison:
		return  # Garrison armies don't merge with themselves
	var city_at := GameManager.city_system.get_city_at_hex(hex_pos)
	if city_at == null:
		return
	# City must be owned by the army's faction or allied
	if city_at.faction_id != army.faction_id:
		var relation := GameManager.get_relation(city_at.faction_id, army.faction_id)
		if relation != Enums.FactionRelation.ALLIED:
			return
	# Generate garrison units and add to army
	var garrison_comp: Array = GameManager.city_system._get_garrison_composition(city_at)
	var reinforcement_count := 0
	for entry in garrison_comp:
		var uid: StringName = entry.unit_id
		var unit_data := DataManager.get_unit(uid)
		if unit_data == null:
			continue
		for i in entry.count:
			var instance := UnitInstance.new()
			instance.init_from_data(unit_data, GameManager.state.generate_id())
			army.units.append(instance)
			reinforcement_count += 1
	# Store count so we can strip them back out after battle
	if reinforcement_count > 0:
		army.set_meta("garrison_reinforcement_count", reinforcement_count)

func _apply_camp_building_bonuses(army: ArmyState, cmd_bonuses: Dictionary) -> void:
	if army.camp_city_id == &"":
		return
	var camp_city: CityState = GameManager.state.cities.get(army.camp_city_id)
	if camp_city == null:
		return
	for bid in camp_city.buildings:
		var bdata: BuildingData = DataManager.get_building(bid)
		if bdata and bdata.special_effects.has("army_attack_bonus"):
			cmd_bonuses["attack_bonus"] = cmd_bonuses.get("attack_bonus", 0) + int(bdata.special_effects["army_attack_bonus"])

func _apply_auto_battle_results(army: ArmyState, survivors: Array[BattleSimulatorV2.BattleFormation]) -> void:
	var surviving_ids: Dictionary = {}
	for f in survivors:
		surviving_ids[f.instance_id] = f.current_hp

	var updated_units: Array[UnitInstance] = []
	for unit in army.units:
		if surviving_ids.has(unit.instance_id):
			unit.current_hp = surviving_ids[unit.instance_id]
			updated_units.append(unit)
	army.units = updated_units

func _handle_elderbeast_battle_aftermath(army: ArmyState) -> void:
	var beast: ElderbeastState = GameManager.state.elderbeasts.get(army.elderbeast_id)
	if beast == null:
		return
	# Check if beast unit survived in the army
	var beast_alive := false
	for unit in army.units:
		if unit.instance_id == beast.unit_instance_id:
			beast.hp = unit.current_hp
			beast_alive = true
			break
	if beast_alive:
		return
	# Beast unit was killed — check recovery eligibility
	var other_units_alive := army.units.size() > 0
	if other_units_alive and not beast.is_injured():
		# Recovery: beast flees with 1 HP and becomes injured for 3 turns
		beast.hp = 1
		beast.injured_turns = 3

func _grant_auto_veterancy_xp(army: ArmyState, survivors: Array[BattleSimulatorV2.BattleFormation], enemy_strength: int) -> void:
	var formation_damage: Dictionary = {} # instance_id -> damage_dealt
	for f in survivors:
		formation_damage[f.instance_id] = f.damage_dealt
	var base_xp := 8 + mini(enemy_strength / 50, 20)
	for unit in army.units:
		var dmg: int = formation_damage.get(unit.instance_id, 0)
		var damage_bonus := mini(dmg / 40, 10)
		unit.grant_xp(base_xp + damage_bonus)

func _separate_armies_stalemate(attacker: ArmyState, defender: ArmyState) -> void:
	# Defender stays at battle hex, attacker retreats to adjacent tile
	var battle_hex := defender.hex_pos
	var retreat_hex := _find_retreat_hex(attacker, battle_hex)
	if retreat_hex != Vector2i(-1, -1):
		attacker.hex_pos = retreat_hex
		GameManager.movement_system.invalidate_positions()
	else:
		# No valid retreat tile — push defender instead as fallback
		var def_retreat := _find_retreat_hex(defender, attacker.hex_pos)
		if def_retreat != Vector2i(-1, -1):
			defender.hex_pos = def_retreat
			GameManager.movement_system.invalidate_positions()

func _find_retreat_hex(army: ArmyState, enemy_hex: Vector2i) -> Vector2i:
	# Find adjacent hex that's farthest from enemy and passable
	var neighbors := HexHelper.get_neighbors(army.hex_pos)
	var best_hex := Vector2i(-1, -1)
	var best_dist := -1
	for n in neighbors:
		if not GameManager.state.hex_map.tiles.has(n):
			continue
		var tile: HexMapData.TileState = GameManager.state.hex_map.tiles[n]
		if tile.terrain == Enums.TerrainType.WATER:
			continue
		var dist := HexHelper.hex_distance(n, enemy_hex)
		if dist > best_dist:
			best_dist = dist
			best_hex = n
	return best_hex
