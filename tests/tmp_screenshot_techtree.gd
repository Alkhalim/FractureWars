extends SceneTree
## Temp tool: loads a demo campaign, opens the tech tree, screenshots the
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
##
## UI Polish Wave Task P4 addition (2026-08-04, tech tree text readability):
## faction selectable via trailing cmdline arg (`-- empire` / `-- skulloath`,
## default empire), matching the P1/P3 tmp_screenshot_*.gd convention. All
## shots now save with a `p4_<faction>_` prefix. Non-empire runs skip the
## empire-specific bounty-override steps (road_network/emp_aqueducts are
## empire tech ids) and instead run a generic tree-overview/hover/detail pass
## (`_generic_pass`) that picks techs deterministically from the faction's
## own tree, plus tight closeup crops around a node label, a branch/category
## ring label, the hover tooltip box, and the detail dialog, for a readability
## self-critique. Every state change (zoom/pan/hover/dialog) gets a full 10-
## frame settle gap before the next screenshot/crop, per this file's existing
## convention -- crops computed in the SAME frame as a zoom/pan change read
## stale screen coordinates (a real bug hit while extending this file: the
## branch-label crop math used the just-set node-centered view instead of the
## wide view still on screen that frame).
## Run WITHOUT --headless. Delete after use.
## Autoload globals are NOT compile-time resolvable in -s scripts -- always
## fetch via root.get_node("/root/X") (see [[godot-test-harness]]).

var _frames := 0
var _campaign: Node = null
var _hud: Control = null
var _faction_id := &"empire"
var _hover_id := StringName()
var _detail_data: ResearchData = null

func _init() -> void:
	call_deferred("_start")

func _start() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0 and args[0] != "":
		_faction_id = StringName(args[0])
	var gm: Node = root.get_node("/root/GameManager")
	gm._is_transitioning = true
	gm.new_game(_faction_id, false, 0)
	gm._is_transitioning = false
	var scene: PackedScene = load("res://scenes/campaign/campaign.tscn")
	_campaign = scene.instantiate()
	root.add_child(_campaign)

func _shot(name: String) -> void:
	var img := root.get_viewport().get_texture().get_image()
	var fname := "p4_%s_%s" % [String(_faction_id), name]
	img.save_png("user://" + fname)
	print("SCREENSHOT SAVED: ", ProjectSettings.globalize_path("user://" + fname))

## Crops the CURRENT frame (call right after a full-window _shot of the same
## frame, or at least 10 frames after the last state/view change -- see file
## header) to `rect` (Control-logical/get_global_rect() coordinates) + `pad`
## logical px, scaled into the saved PNG's actual pixel space (Windows DPI
## scaling can make these differ -- see tmp_screenshot_p3_city.gd's note).
func _crop(name: String, rect: Rect2, pad: float = 12.0) -> void:
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		print("CROP SKIPPED (empty rect): ", name, " rect=", rect)
		return
	var img := root.get_viewport().get_texture().get_image()
	var logical_size: Vector2 = root.get_visible_rect().size
	var px_scale: Vector2 = Vector2(img.get_size()) / logical_size
	var grown := rect.grow(pad)
	var scaled := Rect2(grown.position * px_scale, grown.size * px_scale)
	var r := Rect2i(scaled).intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	if r.size.x <= 0 or r.size.y <= 0:
		print("CROP SKIPPED (out of bounds): ", name, " rect=", rect)
		return
	var cropped := img.get_region(r)
	var fname := "p4_%s_%s" % [String(_faction_id), name]
	cropped.save_png("user://" + fname)
	print("CROP SAVED: ", ProjectSettings.globalize_path("user://" + fname), " rect=", r, " px_scale=", px_scale)

func _process(_delta: float) -> bool:
	_frames += 1
	if _campaign == null:
		return false
	if _hud == null and _campaign.has_node("UILayer/HUD"):
		_hud = _campaign.get_node("UILayer/HUD")
	if _hud == null:
		return false

	if _frames == 25:
		_hud.call("_toggle_research_panel")

	if _faction_id == &"empire":
		_empire_pass()
	else:
		_generic_pass()

	return false

func hud_tree() -> Control:
	if _hud == null:
		return null
	return _hud.get("_research_tree")

## Centers the tree's view on `research_id`'s node at `zoom`, so it (and any
## tooltip) land inside the screenshot regardless of viewport size.
func _center_on(tree: Control, research_id: StringName, zoom: float) -> void:
	tree.set("_zoom", zoom)
	var node_pos: Vector2 = tree.get("_node_positions").get(research_id, Vector2(750, 750))
	var tree_center := Vector2(750, 750)  # mirrors _RadialTechTree.TREE_CENTER
	tree.set("_view_offset", (tree_center - node_pos) * zoom)
	tree.queue_redraw()

## Wide view showing the whole tree incl. every branch/category ring label.
## Re-triggers the tree's OWN first-draw auto-fit path (`_zoom_fitted` flag
## in `_draw()`) instead of reimplementing the span/size formula here --
## reimplementing it with the viewport size instead of the tree Control's own
## `size` (panel content is smaller than the window) computed a zoom that was
## too large and clipped the outer branch labels off the visible panel; this
## calls the exact same code path production uses, so it can't drift.
func _wide_view(tree: Control) -> void:
	tree.set("_zoom_fitted", false)
	tree.set("_view_offset", Vector2.ZERO)
	tree.queue_redraw()

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

## Tight closeup crop around one branch (category ring) label -- read against
## the current view (call only after a settled _wide_view() + a 10-frame
## gap, so every label is on screen).
func _crop_branch_label(tree: Control) -> void:
	var bangles: Dictionary = tree.get("_branch_angles")
	if bangles.is_empty():
		print("CROP SKIPPED (no branch angles): branch_label_closeup.png")
		return
	var tree_global: Vector2 = tree.get_global_rect().position
	var first_branch = bangles.keys()[0]
	var angle: float = bangles[first_branch]
	var label_radius := 1180.0 + 50.0  # mirrors TIER_RADII[5] + 50 in _draw()
	var tree_center := Vector2(750, 750)
	var label_pos := tree_center + Vector2(cos(angle) * label_radius, sin(angle) * label_radius)
	var branch_screen: Vector2 = tree.call("_to_screen", label_pos)
	_crop("branch_label_closeup.png", Rect2(tree_global + branch_screen - Vector2(90, 20), Vector2(220, 55)))

## Tight closeup crop around one node's name label (call after a settled
## _center_on() + a 10-frame gap).
func _crop_node_label(tree: Control, node_id: StringName) -> void:
	var tree_global: Vector2 = tree.get_global_rect().position
	var npos: Vector2 = tree.get("_node_positions").get(node_id, Vector2(750, 750))
	var node_screen: Vector2 = tree.call("_to_screen", npos)
	_crop("label_closeup.png", Rect2(tree_global + node_screen - Vector2(90, 15), Vector2(180, 90)))

## Tight closeup crop around the hover tooltip box (call after a settled
## hover + a 10-frame gap). The box anchors near the node, flipping to the
## left if it wouldn't fit on the right -- this window is generous enough to
## contain either side.
func _crop_tooltip(tree: Control, node_id: StringName) -> void:
	var tree_global: Vector2 = tree.get_global_rect().position
	var npos: Vector2 = tree.get("_node_positions").get(node_id, Vector2(750, 750))
	var node_screen: Vector2 = tree.call("_to_screen", npos)
	_crop("hover_tooltip_closeup.png", Rect2(tree_global + node_screen - Vector2(20, 140), Vector2(380, 280)))

## ── Faction-agnostic P4 pass: overview, hover tooltip, detail dialog ──
func _generic_pass() -> void:
	if _frames == 45:
		var tree := hud_tree()
		var dm: Node = root.get_node("/root/DataManager")
		var fs := _player_fs()
		if tree == null or fs == null:
			print("ERROR: tree or faction state not found at frame 45")
			return
		# Pick techs deterministically (sorted ids -- Dictionary iteration
		# order is insertion order, not guaranteed stable across data edits):
		# lowest-tier owned tech forced "completed" (exercises the gold
		# completed-label color) and one with prerequisites for the detail
		# dialog's Prerequisites list.
		var ids: Array = tree.get("_node_data").keys()
		ids.sort_custom(func(a, b): return str(a) < str(b))
		var completed_pick := StringName()
		var detail_pick := StringName()
		for id in ids:
			var data: ResearchData = dm.research.get(id)
			if data == null:
				continue
			if completed_pick == StringName() and data.tier <= 1:
				completed_pick = id
			if detail_pick == StringName() and data.prerequisites.size() > 0:
				detail_pick = id
		if completed_pick != StringName() and not fs.completed_research.has(completed_pick):
			fs.completed_research.append(completed_pick)
		_hover_id = detail_pick if detail_pick != StringName() else completed_pick
		_detail_data = dm.research.get(_hover_id) if _hover_id != StringName() else null
		print("[%s] completed_pick=%s hover/detail_pick=%s" % [_faction_id, completed_pick, _hover_id])
		_wide_view(tree)

	if _frames == 55:
		var tree := hud_tree()
		if tree == null:
			return
		_shot("tree_overview.png")
		_crop_branch_label(tree)
		if _hover_id != StringName():
			_center_on(tree, _hover_id, 0.9)
			tree.set("_hovered_id", _hover_id)

	if _frames == 65:
		var tree := hud_tree()
		if tree and _hover_id != StringName():
			_crop_node_label(tree, _hover_id)
			_shot("hover_tooltip.png")
			_crop_tooltip(tree, _hover_id)

	if _frames == 75:
		if _detail_data:
			_hud.call("_show_research_detail", _detail_data)
		else:
			print("ERROR: no detail_data picked for ", _faction_id)

	if _frames == 85:
		_shot("detail_dialog.png")
		var dialog := _hud.get_node_or_null("ResearchDetailDialog")
		if dialog:
			_crop("detail_dialog_closeup.png", (dialog as Control).get_global_rect())
		print("ALL DONE (%s)" % _faction_id)
		quit()

## ── Empire pass: original bounty-gate rendering + lease-refresh exercise,
## same frame numbering as _generic_pass so both share one _process(). ──
func _empire_pass() -> void:
	if _frames == 45:
		var dm: Node = root.get_node("/root/DataManager")
		var gm: Node = root.get_node("/root/GameManager")
		var road: ResearchData = dm.research.get(&"road_network")
		var aqueducts: ResearchData = dm.research.get(&"emp_aqueducts")
		var tree := hud_tree()
		_detail_data = road
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
			_wide_view(tree)
		else:
			print("ERROR: road_network/emp_aqueducts research or tree not found at frame 45")

	if _frames == 55:
		var tree := hud_tree()
		if tree == null:
			return
		_shot("tree_overview.png")
		_crop_branch_label(tree)
		_center_on(tree, &"road_network", 0.9)
		tree.set("_hovered_id", &"road_network")

	if _frames == 65:
		var tree := hud_tree()
		if tree:
			_crop_node_label(tree, &"road_network")
			_shot("hover_locked.png")
			_crop_tooltip(tree, &"road_network")
			# emp_aqueducts unlocks codex_sanctum -- confirms the gate dot
			# (bottom-left) and the unlock star (top-right) coexist post-fix.
			_center_on(tree, &"emp_aqueducts", 0.9)
			tree.set("_hovered_id", &"emp_aqueducts")

	if _frames == 75:
		_shot("gate_and_unlock_markers.png")
		if _detail_data:
			_hud.call("_show_research_detail", _detail_data)
		else:
			print("ERROR: road_network research not found for the detail-dialog screenshot")

	if _frames == 85:
		_shot("detail_dialog.png")
		var dialog := _hud.get_node_or_null("ResearchDetailDialog")
		if dialog:
			_crop("detail_dialog_closeup.png", (dialog as Control).get_global_rect())
			dialog.queue_free()
		var tree := hud_tree()
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
		_hud.call("_refresh_research_panel")
		var tree2 := hud_tree()
		print("road_network cache AFTER _refresh_research_panel(): ",
			tree2.get("_bounty_gate_state").get(&"road_network", -1) if tree2 else "NO TREE")
		print("Same tree instance reused: ", tree == tree2)
		print("Pan/zoom preserved (not reset): zoom ", zoom_before, " -> ", tree2.get("_zoom") if tree2 else null,
			" | offset ", offset_before, " -> ", tree2.get("_view_offset") if tree2 else null)
		if tree2:
			_center_on(tree2, &"road_network", tree2.get("_zoom"))
			tree2.set("_hovered_id", &"road_network")

	if _frames == 95:
		_shot("after_lease_refresh.png")
		print("ALL DONE (empire)")
		quit()
