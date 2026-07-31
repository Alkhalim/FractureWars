extends SceneTree
## Balance batch (2026-07): 3 small AI-economy fixes.
## 1. Ivoryscar's home region (qareth) now matches its realm_affinity (VOID)
##    like every other playable faction's home region matches its own --
##    it was the only DIVINE/VOID mismatch, flipping the loyalty Same-Realm
##    bonus into a Cultural-Mismatch penalty for every Ivoryscar city.
## 2. Ivoryscar's AI build-priority table now includes a wood producer
##    (sandstone_pit + its tier-2 petrified_quarry) -- the desert biome has
##    zero native wood income, yet several Ivoryscar buildings carry wood
##    upkeep.
## 3. The AI recruit function now bails when the faction's recurring gold
##    income is already non-positive, instead of recruiting purely on unit
##    count regardless of affordability.
## Run: godot --headless --path . -s res://tests/test_ai_economy.gd

var _fails := 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var dm = root.get_node("/root/DataManager")
	var gm = root.get_node("/root/GameManager")
	var tm = root.get_node("/root/TurnManager")

	# ── Item 1: qareth realm now matches Ivoryscar's realm_affinity (VOID=1) ──
	var qareth = dm.get_region(&"qareth")
	if qareth == null:
		_check(false, "qareth region data exists")
	else:
		_check(qareth.realm_influence == Enums.Realm.VOID, "qareth realm_influence == VOID (1), got %s" % [qareth.realm_influence])

	var ivoryscar_faction = dm.get_faction(&"ivoryscar")
	if ivoryscar_faction:
		_check(qareth != null and ivoryscar_faction.realm_affinity == qareth.realm_influence, "qareth realm now matches ivoryscar.realm_affinity")

	# ── Item 2: ivoryscar build priorities carry a wood producer ──
	var ivoryscar_priorities: Array = tm.FACTION_BUILD_PRIORITIES.get(&"ivoryscar", [])
	_check(ivoryscar_priorities.has(&"sandstone_pit"), "ivoryscar build priorities contain sandstone_pit, got %s" % [ivoryscar_priorities])
	_check(ivoryscar_priorities.has(&"petrified_quarry"), "ivoryscar build priorities contain petrified_quarry (sandstone_pit's tier-2), got %s" % [ivoryscar_priorities])
	var sp_idx: int = ivoryscar_priorities.find(&"sandstone_pit")
	var pq_idx: int = ivoryscar_priorities.find(&"petrified_quarry")
	var df_idx: int = ivoryscar_priorities.find(&"dust_fields")
	if sp_idx != -1 and pq_idx != -1:
		_check(sp_idx <= 3, "sandstone_pit sits early in the priority list (index <=3), got index %d" % sp_idx)
		_check(pq_idx == sp_idx + 1, "petrified_quarry immediately follows sandstone_pit, got indices %d/%d" % [sp_idx, pq_idx])
	# Regression guard for a discovered priority-walk quirk: the AI's build
	# walk (_execute_ai_city_management) stops at the first priority entry
	# that is currently buildable, whether or not start_building() actually
	# succeeds -- so a wood-costing entry ivoryscar can never afford
	# (dust_fields) must not sit ahead of the gold-only wood producer, or it
	# would permanently block the walk from ever reaching sandstone_pit.
	if sp_idx != -1 and df_idx != -1:
		_check(sp_idx < df_idx, "sandstone_pit (gold-only) sits ahead of dust_fields (needs wood ivoryscar doesn't have) in the priority walk, got indices %d/%d" % [sp_idx, df_idx])

	var sandstone_pit_bd = dm.get_building(&"sandstone_pit")
	_check(sandstone_pit_bd != null and sandstone_pit_bd.faction_id == &"ivoryscar", "sandstone_pit is an ivoryscar building")
	if sandstone_pit_bd:
		_check(int(sandstone_pit_bd.income_bonus.get(Enums.ResourceType.WOOD, -1)) > 0, "sandstone_pit produces wood, got %s" % [sandstone_pit_bd.income_bonus])

	# ── Item 3: AI recruit gate -- gold income <= 0 blocks recruitment ──
	gm.new_game(&"empire", false, 0)
	var fs: FactionState = gm.state.faction_states.get(&"ivoryscar")
	if fs == null or fs.owned_cities.is_empty():
		_check(false, "ivoryscar faction state with owned cities exists after new_game")
	else:
		var city: CityState = gm.state.cities.get(fs.owned_cities[0])
		_check(city != null, "ivoryscar's first owned city resolves")
		if city:
			# Healthy baseline: a freshly-started game should have positive gold income.
			var healthy_income: int = gm.diplomacy_system.get_faction_resource_income(&"ivoryscar", Enums.ResourceType.GOLD)
			_check(healthy_income > 0, "sanity: fresh ivoryscar gold income is positive before we siege it, got %d" % healthy_income)

			# Craft a collapsed-income faction state: siege every owned city so
			# the faction's recurring gold income totals to <= 0 (sieged cities
			# are excluded from the income scan entirely).
			var sieged_ids: Array = []
			for cid in fs.owned_cities:
				var c: CityState = gm.state.cities.get(cid)
				if c and not c.is_under_siege:
					c.is_under_siege = true
					sieged_ids.append(cid)
			# The income-totals cache is keyed by (turn, faction-turn-index,
			# topology-epoch) and does not know about is_under_siege flips on
			# its own -- force a recompute the same way real siege/capture
			# code paths do (they change city ownership/buildings, which also
			# bumps the epoch).
			gm.city_system.invalidate_region_effects_cache()

			var collapsed_income: int = gm.diplomacy_system.get_faction_resource_income(&"ivoryscar", Enums.ResourceType.GOLD)
			_check(collapsed_income <= 0, "sanity: sieging every owned city collapses gold income to <=0, got %d" % collapsed_income)

			var census: Dictionary = tm._compute_ai_recruit_census(&"ivoryscar")
			var queue_before := city.recruit_queue.size()
			tm._ai_recruit_with_composition(city, &"ivoryscar", census)
			_check(city.recruit_queue.size() == queue_before, "AI recruit gate: no recruitment queued while gold income <= 0 (before=%d, after=%d)" % [queue_before, city.recruit_queue.size()])

			# Restore state for any later checks / cleanliness.
			for cid in sieged_ids:
				var c2: CityState = gm.state.cities.get(cid)
				if c2:
					c2.is_under_siege = false
			gm.city_system.invalidate_region_effects_cache()

	if _fails == 0:
		print("AI ECONOMY TEST PASSED")
		quit(0)
	else:
		print("AI ECONOMY TEST FAILED (%d)" % _fails)
		quit(1)

func _check(cond: bool, label: String) -> void:
	if not cond:
		_fails += 1
		print("FAIL: " + label)
