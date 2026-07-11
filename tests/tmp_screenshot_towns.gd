extends SceneTree
## Temp tool: renders a gallery of the top-down town markers — every culture
## (rows) at city levels 1-5 plus a settlement (columns) — and screenshots it.
## Delete after use.

var _frames := 0
var _campaign: Node = null

const CULTURES := [
	&"empire", &"skulloath", &"gladehost", &"tainted_jade", &"moonspear",
	&"sunblessed", &"thunderswarm", &"cinderguard", &"forsaken",
	&"ivoryscar", &"shardhorde", &"independent",
]

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

func _build_gallery() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 99
	root.add_child(layer)
	var bg := ColorRect.new()
	bg.color = Color(0.13, 0.12, 0.11)
	bg.size = Vector2(1240, 1240)
	layer.add_child(bg)
	var dm: Node = root.get_node("/root/DataManager")
	for row in CULTURES.size():
		var culture: StringName = CULTURES[row]
		var fd = dm.get_faction(culture)
		var fc: Color = fd.color if fd else Color(0.6, 0.6, 0.6)
		var lbl := Label.new()
		lbl.text = String(culture)
		lbl.position = Vector2(6, 60 + row * 98)
		lbl.add_theme_font_size_override("font_size", 12)
		layer.add_child(lbl)
		for col in 6:
			var cell := Node2D.new()
			cell.position = Vector2(190 + col * 168, 80 + row * 98)
			layer.add_child(cell)
			if col == 5:
				_campaign.call("_draw_settlement_art", cell, culture, fc)
			else:
				var level := col + 1
				_campaign.call("_draw_city_art", cell, culture, fc, level == 5, level)

func _shot(name: String) -> void:
	var img := root.get_viewport().get_texture().get_image()
	img.save_png("user://" + name)
	print("SCREENSHOT SAVED: ", ProjectSettings.globalize_path("user://" + name))

func _process(_delta: float) -> bool:
	_frames += 1
	if _campaign == null:
		return false
	if _frames == 30:
		_build_gallery()
	if _frames == 40:
		_shot("town_gallery.png")
		quit()
	return false
