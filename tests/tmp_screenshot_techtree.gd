extends SceneTree
## Temp tool: loads a demo campaign as empire (4 bounty-gated techs: road_network
## T2/granite, emp_aqueducts T3/orchards, emp_harbor_cities T3/fisheries,
## emp_war_machines T4/titanstone_quarry), opens the tech tree, screenshots the
## overview, then verifies the rendering path end to end, including the
## code-review fix pass (2 Critical + 1 Important):
##   1. Forces road_network's and emp_aqueducts' whole prerequisite chains
##      "completed" so prereqs_met is true regardless of turn-0 game state
##      (nothing is naturally researched yet at frame 45).
##   2. Prints the REAL bounty-gate state (from ResearchSystem.is_bounty_locked
##      / the tree's own _bounty_gate_state cache) for both at this map seed,
##      for diagnostic purposes, BEFORE any override.
##   3. Overrides the tree's cached _bounty_gate_state entries to 1 (locked) so
##      the red/gold-dot node render and the hover tooltip's "Requires:" line
##      are GUARANTEED visible in the screenshots, independent of whether this
##      seed's map happens to hand empire a granite/orchards bounty at start.
##      This only exercises the _draw()/_draw_hover_tooltip() rendering path
##      (Task 5); the underlying gate logic itself is covered by headless
##      test_bounty_gated_techs.
##   4. Screenshots emp_aqueducts (gated AND unlocks a building -- real
##      collision in shipped data) to confirm the gold gate-dot (bottom-left,
##      post-fix) and the unlock star (top-right) coexist without overlapping.
##   5. Force-opens _show_research_detail on road_network and screenshots the
##      Required Resources row -- that dialog reads BountySystem/
##      DiplomacySystem directly (not the tree's cache), so its color reflects
##      TRUE empire bounty ownership at this seed.
##   6. Fix-verification for the "stale cache" Critical finding: grants empire
##      a fake RESOURCE_LEASE treaty for granite (mirrors what
##      propose_bounty_lease's real terms shape produces), then calls
##      hud._refresh_research_panel() directly -- the exact function whose
##      "reuse existing tree" branch now calls _refresh_bounty_gate_state().
##      Prints the cache value for road_network before/after and confirms
##      pan/zoom/hover were NOT reset (the tree instance must stay reused),
##      then screenshots the tree showing road_network flip from locked-red
##      to unlocked-green with no code path recreating the panel.
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
		var aqueducts: ResearchData = dm.research.get(&"emp_aqueducts")
		var tree: Control = hud_tree()
		if road and aqueducts and tree:
			var fs := _player_fs()
			if fs:
				for data in [road, aqueducts]:
					var chain := _collect_ancestors(dm, data)
					for id in chain:
						if not fs.completed_research.has(id):
							fs.completed_research.append(id)
			print("road_network real bounty-gate cache state (0 met/ungated, 1 locked, 2 map-absent): ",
				tree.get("_bounty_gate_state").get(&"road_network", -1))
			print("road_network real is_bounty_locked(empire): ",
				gm.research_system.is_bounty_locked(&"empire", road))
			print("emp_aqueducts real bounty-gate cache state: ",
				tree.get("_bounty_gate_state").get(&"emp_aqueducts", -1))
			# Guarantee the visual regardless of this seed's bounty RNG --
			# exercises the _draw() rendering path deterministically.
			tree.get("_bounty_gate_state")[&"road_network"] = 1
			tree.get("_bounty_gate_state")[&"emp_aqueducts"] = 1
			tree.set("_zoom", 0.7)
			_center_on(tree, &"road_network")
			tree.set("_hovered_id", &"road_network")
			tree.queue_redraw()
		else:
			print("ERROR: road_network/emp_aqueducts research or tree not found at frame 45")

	if _frames == 55:
		_shot("techtree_hover_locked.png")
		var tree: Control = hud_tree()
		if tree:
			# emp_aqueducts unlocks codex_sanctum -- confirms the gate dot
			# (bottom-left) and the unlock star (top-right) coexist post-fix.
			_center_on(tree, &"emp_aqueducts")
			tree.set("_hovered_id", &"emp_aqueducts")
			tree.queue_redraw()

	if _frames == 65:
		_shot("techtree_gate_and_unlock_markers.png")
		var hud: Control = _campaign.get_node("UILayer/HUD")
		var dm: Node = root.get_node("/root/DataManager")
		var road: ResearchData = dm.research.get(&"road_network")
		if road:
			hud.call("_show_research_detail", road)
		else:
			print("ERROR: road_network research not found for the detail-dialog screenshot")

	if _frames == 75:
		_shot("techtree_detail_dialog.png")
		var hud: Control = _campaign.get_node("UILayer/HUD")
		var existing := hud.get_node_or_null("ResearchDetailDialog")
		if existing:
			existing.queue_free()
		var tree: Control = hud_tree()
		var zoom_before = tree.get("_zoom") if tree else null
		var offset_before = tree.get("_view_offset") if tree else null
		# Grant empire a lease on granite -- mirrors the terms shape
		# propose_bounty_lease() produces (diplomacy_system.gd:425-431).
		var gm: Node = root.get_node("/root/GameManager")
		var state = gm.get("state")
		var treaty := TreatyInstance.new()
		treaty.treaty_id = state.generate_id()
		treaty.treaty_type = Enums.TreatyType.RESOURCE_LEASE
		treaty.faction_a = &"__test_owner__"
		treaty.faction_b = &"empire"
		treaty.turns_remaining = 10
		treaty.terms = {bounty_hex = Vector2i(0, 0), bounty_id = &"granite", gold_per_turn = 1}
		state.diplomacy_state.treaties[treaty.treaty_id] = treaty
		print("Granted empire a granite lease. road_network cache BEFORE reopen: ",
			tree.get("_bounty_gate_state").get(&"road_network", -1) if tree else "NO TREE")
		# The exact fix under test: _refresh_research_panel()'s "reuse existing
		# tree" branch now calls _refresh_bounty_gate_state(). This is the same
		# function real gameplay calls whenever the panel is (re)shown.
		hud.call("_refresh_research_panel")
		var tree2: Control = hud_tree()
		print("road_network cache AFTER _refresh_research_panel(): ",
			tree2.get("_bounty_gate_state").get(&"road_network", -1) if tree2 else "NO TREE")
		print("Same tree instance reused: ", tree == tree2)
		print("Pan/zoom preserved (not reset): zoom ", zoom_before, " -> ", tree2.get("_zoom") if tree2 else null,
			" | offset ", offset_before, " -> ", tree2.get("_view_offset") if tree2 else null)
		if tree2:
			_center_on(tree2, &"road_network")
			tree2.set("_hovered_id", &"road_network")
			tree2.queue_redraw()

	if _frames == 85:
		_shot("techtree_after_lease_refresh.png")
		quit()

	return false

func hud_tree() -> Control:
	var hud: Control = _campaign.get_node("UILayer/HUD")
	return hud.get("_research_tree")

## Centers the tree's view on `research_id`'s node at its current zoom, so it
## (and any tooltip) land inside the screenshot regardless of viewport size.
func _center_on(tree: Control, research_id: StringName) -> void:
	var zoom: float = tree.get("_zoom")
	var node_pos: Vector2 = tree.get("_node_positions").get(research_id, Vector2(750, 750))
	var tree_center := Vector2(750, 750)  # mirrors _RadialTechTree.TREE_CENTER
	tree.set("_view_offset", (tree_center - node_pos) * zoom)

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
