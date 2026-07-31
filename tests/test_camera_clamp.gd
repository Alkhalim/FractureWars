extends SceneTree
## Camera pan clamp must use the SAME hex metrics the map renders with.
## Regression: campaign_camera.gd had a stale local HEX_RADIUS=32 while the
## renderer uses 38 — the clamp walled off the eastern/southern ~16% of the
## world (Ivoryscar's home was unreachable after the first pan).
## Scene scripts don't compile headless, so this guards the contract at the
## source level: exactly one radius definition (HexMapData), both scene
## scripts reference it, and the clamp math uses the shared spacings.

var _fails := 0

func _check(cond: bool, label: String) -> void:
	if cond:
		print("  PASSED: " + label)
	else:
		_fails += 1
		print("  FAILED: " + label)

func _init() -> void:
	_check(HexMapData.HEX_RADIUS == 38.0, "HexMapData exposes render hex radius 38")
	_check(absf(HexMapData.HEX_H_SPACING - 57.0) < 0.01, "shared h-spacing = radius * 1.5")
	_check(absf(HexMapData.HEX_V_SPACING - 65.816) < 0.01, "shared v-spacing = radius * 1.732")

	var cam_src := (load("res://scenes/campaign/campaign_camera.gd") as GDScript).source_code
	_check(not cam_src.contains("HEX_RADIUS := 3"),
		"camera defines no local hex radius (single source of truth)")
	_check(cam_src.contains("HexMapData.HEX_H_SPACING") and cam_src.contains("HexMapData.HEX_V_SPACING"),
		"camera clamp reads shared spacings from HexMapData")

	var map_src := (load("res://scenes/campaign/campaign.gd") as GDScript).source_code
	_check(map_src.contains("const HEX_RADIUS := HexMapData.HEX_RADIUS"),
		"campaign renderer derives its radius from HexMapData")

	if _fails == 0:
		print("ALL PASSED (test_camera_clamp)")
	else:
		print("%d FAILED (test_camera_clamp)" % _fails)
	quit(0 if _fails == 0 else 1)
