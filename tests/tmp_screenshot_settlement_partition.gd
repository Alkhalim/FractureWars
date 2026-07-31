extends SceneTree
## Temp tool (Task 2, Settlement Building Partition verification): loads an
## Empire campaign (seed 0), founds a settlement next to the capital via
## GameManager.found_settlement, grants imperial_drill research so the
## curated military chain head (cohort_barracks) is actually offered
## alongside the universal 4 + the science/cultural chain head
## (village_gathering_place, unresearched), then opens _show_city_panel on
## the new settlement and screenshots the "Available Buildings" short list.
## Modeled on tests/tmp_screenshot_cinderguard.gd (new_game + instantiate +
## frame-counted _process pattern, intro/tutorial suppression). Delete after
## use.
##   godot --path . --resolution 1600x900 -s res://tests/tmp_screenshot_settlement_partition.gd

var _frames := 0
var _campaign: Node = null
var _hud: Node = null
var _settlement_id: StringName = &""

func _init() -> void:
	call_deferred("_start")

func _start() -> void:
	var gm: Node = root.get_node("/root/GameManager")
	gm._is_transitioning = true
	gm.new_game(&"empire", false, 0)
	gm._is_transitioning = false
	gm.state.faction_intro_shown = true
	gm.state.tutorial_enabled = false
	var scene: PackedScene = load("res://scenes/campaign/campaign.tscn")
	_campaign = scene.instantiate()
	root.add_child(_campaign)
	_hud = _campaign.get_node("UILayer/HUD")

func _shot(name: String) -> void:
	var img := root.get_viewport().get_texture().get_image()
	img.save_png("user://" + name)
	print("SCREENSHOT SAVED: ", ProjectSettings.globalize_path("user://" + name))

func _process(_delta: float) -> bool:
	_frames += 1
	if _campaign == null:
		return false

	if _frames == 10:
		var gm: Node = root.get_node("/root/GameManager")
		var pid: StringName = gm.state.player_faction_id
		var fs = gm.state.faction_states.get(pid)
		# Grant the curated military chain-head research (Task 1b) so the
		# settlement's short list shows a chain-tagged building, not just
		# the universal 4 -- mirrors how test_settlement_partition.gd's
		# empire assertion grants imperial_drill for the same reason.
		if fs and not fs.completed_research.has(&"imperial_drill"):
			fs.completed_research.append(&"imperial_drill")

		var capital: CityState = null
		for cid in gm.state.cities:
			var c: CityState = gm.state.cities[cid]
			if c.faction_id == pid and c.is_capital:
				capital = c
				break
		if capital == null:
			print("WARNING: no player capital found")
		else:
			var chosen_hex := Vector2i(-9999, -9999)
			for n in HexHelper.get_neighbors(capital.hex_pos):
				var tile = gm.state.hex_map.get_tile(n)
				if tile == null:
					continue
				if tile.terrain == Enums.TerrainType.WATER:
					continue
				# Skip if another city already occupies this hex
				var occupied := false
				for cid2 in gm.state.cities:
					if gm.state.cities[cid2].hex_pos == n:
						occupied = true
						break
				if occupied:
					continue
				chosen_hex = n
				break
			if chosen_hex == Vector2i(-9999, -9999):
				print("WARNING: no free non-water neighbor hex found next to capital")
			else:
				_settlement_id = gm.found_settlement(pid, chosen_hex, capital.city_id)
				print("FOUNDED SETTLEMENT: ", _settlement_id, " at ", chosen_hex)
				if _settlement_id != &"":
					var settlement: CityState = gm.state.cities[_settlement_id]
					print("  is_settlement=", settlement.is_settlement, " is_mobile_camp=", settlement.is_mobile_camp, " region=", settlement.region_id)
					var available = gm.city_system.get_available_buildings(settlement, true)
					var ids: Array[String] = []
					for b in available:
						ids.append(str(b.id))
					print("  AVAILABLE BUILDINGS (short list): ", ids)

	if _frames == 14 and _settlement_id != &"":
		_hud.call("_show_city_panel", _settlement_id)

	if _frames == 60:
		var city_panel: Control = _hud.get("city_panel")
		if city_panel:
			print("CITY PANEL visible=", city_panel.visible, " modulate.a=", city_panel.modulate.a, " rect=", city_panel.get_global_rect())
		else:
			print("WARNING: city_panel node not found on HUD")
		_shot("win_settlement_menu.png")
		quit()
	return false
