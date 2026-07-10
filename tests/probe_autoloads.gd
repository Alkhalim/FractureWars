extends SceneTree
## Probe: are autoloads available when running with -s?

func _init() -> void:
	call_deferred("_check")

func _check() -> void:
	var gm := root.get_node_or_null("GameManager")
	var dm := root.get_node_or_null("DataManager")
	print("PROBE GameManager=%s DataManager=%s" % [gm != null, dm != null])
	if dm != null:
		print("PROBE units_loaded=%d" % dm.units.size())
	quit()
