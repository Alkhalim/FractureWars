extends SceneTree
## Temp tool: loads a demo campaign as empire (4 bounty-gated techs: road_network
## T2/granite, emp_aqueducts T3/orchards, emp_harbor_cities T3/fisheries,
## emp_war_machines T4/titanstone_quarry), opens the tech tree, screenshots the
## overview, then verifies road_network's rendering path end to end:
##   1. Forces its whole prerequisite chain "completed" so prereqs_met is true
##      regardless of turn-0 game state (nothing is researched yet at frame 45).
##   2. Prints the REAL bounty-gate state (from ResearchSystem.is_bounty_locked
##      / the tree's own _bounty_gate_state cache) for road_network at this map
##      seed, for diagnostic purposes.
##   3. Overrides the tree's cached _bounty_gate_state entry to 1 (locked) so
##      the red/gold-dot node render and the hover tooltip's "Requires:" line
##      are GUARANTEED visible in the screenshot, independent of whether this
##      seed's map happens to hand empire a granite bounty at start. This only
##      exercises the _draw()/_draw_hover_tooltip() rendering path (Task 5);
##      the underlying gate logic itself is covered by headless
##      test_bounty_gated_techs.
##   4. Force-opens _show_research_detail on road_network and screenshots the
##      Required Resources row -- that dialog reads BountySystem/
##      DiplomacySystem directly (not the tree's cache), so its color reflects
##      TRUE empire bounty ownership at this seed.
## Run WITHOUT --headless. Delete after use.
## Autoload globals are NOT compile-time resolvable in -s scripts -- always
## fetch via root.get_node("/root/X") (see [[godot-test-harness]]).

var _frames := 0
var _campaign: Node = null

func _init() -> void:
	call_deferred("_start")

func _start() -> void:
	var gm: Node = root.get_node("/root/GameManager")
	gm._is_transitioning = true
	gm.new_game(&"empire", false, 0)
	gm._is_transitioning = false
	var scene: PackedScene = load("res://scenes/campaign/campaign.tscn")
	_campaign = scene.instantiate()
	root.add_child(_campaign)

func _shot(name: String) -> void:
	var img := root.get_viewport().get_texture().get_image()
	img.save_png("user://" + name)
	print("SCREENSHOT SAVED: ", ProjectSettings.globalize_path("user://" + name))

func _process(_delta: float) -> bool:
	_frames += 1
	if _campaign == null:
		return false
	if _frames == 25:
		var hud: Control = _campaign.get_node("UILayer/HUD")
		hud.call("_toggle_research_panel")
	if _frames == 45:
		_shot("techtree_default.png")
		var dm: Node = root.get_node("/root/DataManager")
		var gm: Node = root.get_node("/root/GameManager")
		var road: ResearchData = dm.research.get(&"road_network")
		var tree: Control = hud_tree()
		if road and tree:
			var fs := _player_fs()
			if fs:
				var chain := _collect_ancestors(dm, road)
				for id in chain:
					if not fs.completed_research.has(id):
						fs.completed_research.append(id)
			print("road_network real bounty-gate cache state (0 met/ungated, 1 locked, 2 map-absent): ",
				tree.get("_bounty_gate_state").get(&"road_network", -1))
			print("road_network real is_bounty_locked(empire): ",
				gm.research_system.is_bounty_locked(&"empire", road))
			# Guarantee the visual regardless of this seed's bounty RNG --
			# exercises the _draw() rendering path deterministically.
			tree.get("_bounty_gate_state")[&"road_network"] = 1
			tree.set("_zoom", 0.7)
			# Center the view on road_network's node so it (and its tooltip)
			# land inside the screenshot regardless of viewport size.
			var node_pos: Vector2 = tree.get("_node_positions").get(&"road_network", Vector2(750, 750))
			var tree_center := Vector2(750, 750)  # mirrors _RadialTechTree.TREE_CENTER
			tree.set("_view_offset", (tree_center - node_pos) * 0.7)
			tree.set("_hovered_id", &"road_network")
			tree.queue_redraw()
	if _frames == 55:
		_shot("techtree_hover_locked.png")
		var hud: Control = _campaign.get_node("UILayer/HUD")
		var dm: Node = root.get_node("/root/DataManager")
		var road: ResearchData = dm.research.get(&"road_network")
		if road:
			hud.call("_show_research_detail", road)
		else:
			print("ERROR: road_network research not found for the detail-dialog screenshot")
	if _frames == 65:
		_shot("techtree_detail_dialog.png")
		quit()
	return false

func hud_tree() -> Control:
	var hud: Control = _campaign.get_node("UILayer/HUD")
	return hud.get("_research_tree")

func _player_fs() -> FactionState:
	var gm: Node = root.get_node("/root/GameManager")
	var state = gm.get("state")
	return state.faction_states.get(state.player_faction_id)

## Recursively walks `data`'s prerequisite chain (not including `data` itself).
func _collect_ancestors(dm: Node, data: ResearchData) -> Array[StringName]:
	var result: Array[StringName] = []
	var seen: Dictionary = {}
	var queue: Array = data.prerequisites.duplicate()
	while not queue.is_empty():
		var id: StringName = queue.pop_front()
		if seen.has(id):
			continue
		seen[id] = true
		result.append(id)
		var pdata: ResearchData = dm.research.get(id)
		if pdata:
			for p in pdata.prerequisites:
				queue.append(p)
	return result
