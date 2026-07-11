extends SceneTree
## Temp tool: screenshots the reworked economy panel and dilemma dialog.
## Delete after use.

var _frames := 0
var _campaign: Node = null

func _init() -> void:
	call_deferred("_start")

func _start() -> void:
	var gm: Node = root.get_node("/root/GameManager")
	gm._is_transitioning = true
	gm.new_game(&"skulloath", false)
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
	var hud: Control = _campaign.get_node_or_null("UILayer/HUD")
	if hud == null:
		return false
	if _frames == 40:
		# Open the economy panel
		hud.economy_panel.visible = true
		hud._refresh_economy_panel()
	if _frames == 50:
		_shot("ux_economy.png")
		hud.economy_panel.visible = false
		# Fire a dilemma with costs (moonspear ritual has cost dicts)
		hud._show_faction_dilemma_dialog(&"skulloath", "dark_bargain", {
			"title": "Dark Bargain (Corruption: 47)",
			"description": "The old spirits and the demon whisper alike. Choose whose voice grows louder.",
			"choices": [
				{"label": "Feed the Hunger", "description": "Sacrifice 10 Captives: +12 Corruption, +10 Iron.", "effect": "bargain_embrace", "cost": {6: 10}},
				{"label": "Ancestral Rites", "description": "Purge the darkness: -12 Corruption, +2 loyalty in all cities. Costs 40 Gold.", "effect": "bargain_purge", "cost": {0: 40}},
				{"label": "Walk the Line", "description": "Hold the balance. +3 Technology from diverse knowledge.", "effect": "bargain_balance"},
			],
		})
	if _frames == 60:
		_shot("ux_dilemma.png")
		quit()
	return false
